# Interface Contract

> **This file is normative.** Every phase agent MUST read it before writing code, and MUST NOT
> invent names that differ from what is written here. If a phase needs a name that is not in this
> file, the agent adds it to this file in the same change, under the correct section, and says so in
> its completion report.

The single biggest failure mode when several agents implement one Terraform stack in sequence is
**name drift**: phase 2 emits `cluster_id`, phase 3 consumes `cluster_name`, and nothing wires
together. This contract exists to prevent that. Names below are exact, case-sensitive, and final.

---

## 1. Repository layout and scope boundary

### 🛑 Scope boundary — read this first

The repository root contains **two unrelated assessments**:

```
opsfleet/
├── architecture/     ← A DIFFERENT ASSESSMENT. OUT OF SCOPE. DO NOT READ, WRITE, OR LIST IT.
└── terraform/        ← THIS assessment. Your entire working directory.
```

**Every agent working on this assessment operates with `terraform/` as its working directory and
never leaves it.** Do not read, write, list, search, or `cd` into `architecture/` or any other
path outside `terraform/`. It contains an unrelated submission; touching it wastes context and
risks corrupting someone else's work. There is nothing in it you need.

All paths in every document in `docs/` are **relative to `terraform/`**.

### Inside `terraform/`

```
terraform/                            # ← working directory; everything below is in scope
├── README.md                         # user-facing docs, THE GRADED ARTEFACT (Phase 7)
├── .gitignore                        # scoped to this directory (Phase 0)
├── versions.tf                       # terraform{} block: core + provider constraints
├── providers.tf                      # aws + helm provider config (no kubernetes provider)
├── backend.tf                        # S3 backend (partial config)
├── backend.hcl.example               # committed; backend.hcl is gitignored
├── locals.tf                         # name prefix + common tags
├── main.tf                           # module composition only
├── variables.tf
├── outputs.tf
├── terraform.tfvars.example          # committed
├── terraform.tfvars                  # gitignored, never committed
├── docs/                             # THE PLAN — design docs, not deployed
│   ├── README.md                     # index + phase order  (read this first)
│   ├── 00-architecture-and-decisions.md
│   ├── contracts/
│   │   ├── interface-contract.md     # <- you are here
│   │   └── security-checklist.md
│   ├── phases/
│   │   └── phase-NN-*.md             # one implementable unit of work each
│   └── reference/
│       ├── version-pinning.md
│       ├── karpenter-api-reference.md
│       └── gotchas.md
├── bootstrap/                        # separate root module: S3 state backend (Phase 0)
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── versions.tf
├── modules/
│   ├── network/                      # Phase 1
│   ├── eks/                          # Phase 2
│   ├── karpenter/                    # Phase 3 + 4 (AWS-side IAM/SQS + Helm release)
│   └── cluster-resources/          # Phase 5 (NodePool / EC2NodeClass CRs)
│       └── chart/                    # local Helm chart holding the Karpenter CRs
└── examples/                         # Phase 6 — developer-facing demo manifests
    ├── README.md
    ├── deployment-x86.yaml
    ├── deployment-arm64.yaml
    ├── deployment-multiarch.yaml
    ├── deployment-multiarch-preferred.yaml   # added by Phase 6 — see its completion report
    └── job-arch-check.yaml
```

`docs/` living inside `terraform/` is deliberate: it keeps every agent inside one directory tree,
and it puts the design rationale where a reviewer of this assessment will actually find it.

**Rules**

1. `main.tf` contains **module blocks only** — no `resource` blocks. Composition lives at
   the root; implementation lives in `modules/`.
2. Each local module owns exactly one concern and declares its own `variables.tf` / `outputs.tf` /
   `versions.tf` (with `required_providers` but **no** `provider` blocks — providers are configured
   only at the root, and inherited).
3. No module may read another module's state. Data flows root-down: `module.a.output` →
   `module.b.input`, wired in `main.tf`.
4. `bootstrap/` is a **separate root module with local state**. It is applied once, by
   hand, before the main stack. It is never referenced by the main stack except through the backend
   config values it prints.

---

## 2. Naming and tagging

### 2.1 Name prefix

Every AWS resource name derives from a single computed prefix. Defined once, in
`locals.tf`:

```hcl
locals {
  # e.g. "opsfleet-poc"
  name = "${var.project_name}-${var.environment}"
}
```

- `var.project_name` default `"opsfleet"`
- `var.environment` default `"poc"`
- **The EKS cluster name is exactly `local.name`.** Not `${local.name}-eks`, not `${local.name}-cluster`.
  Karpenter discovery tags, the SQS queue name and the IAM role names all derive from it, so it must
  be short and stable. Validate it against `^[a-zA-Z0-9][a-zA-Z0-9-_]{0,36}$`.

### 2.2 Tags

Defined once in `locals.tf` and passed into every module as a `tags` input. Modules merge
their own resource-specific tags on top; modules never re-derive the base set.

```hcl
locals {
  tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Component   = "eks-karpenter-poc"
    },
    var.additional_tags,
  )
}
```

The AWS provider also applies `default_tags` with the same map, so anything created outside a module
(or by a nested module that forgot) still gets tagged. Tagging in both places is deliberate and
harmless — `default_tags` covers drift, explicit tags survive provider replacement.

> ⚠️ **`default_tags` does not reach the resources that dominate the bill.** It applies only to
> resources the AWS *provider* creates. Karpenter calls `ec2:CreateFleet` itself, so every node it
> launches — the entire variable cost of the cluster — is invisible to `default_tags`. The only way
> to tag them is `EC2NodeClass.spec.tags`, which Phase 5 must populate from this same map. Without
> that, Cost Explorer cannot attribute the compute spend to `Project`/`Environment` at all, and the
> tagging story is cosmetic.
>
> Cost allocation tags also have to be **activated** in Billing before they can be used as a Cost
> Explorer dimension — a one-time console/API step per account, not something Terraform does for you.
> Phase 7's README must say so.

### 2.3 Discovery tags — these are load-bearing, do not change them

| Tag key | Value | Applied to | Consumed by |
|---|---|---|---|
| `karpenter.sh/discovery` | `local.name` | private subnets, node security group | Karpenter `subnetSelectorTerms` / `securityGroupSelectorTerms` |
| `kubernetes.io/role/elb` | `1` | public subnets | AWS Load Balancer Controller (public LBs) |
| `kubernetes.io/role/internal-elb` | `1` | private subnets | AWS Load Balancer Controller (internal LBs) |

If the value of `karpenter.sh/discovery` and the `EC2NodeClass` selector ever disagree, Karpenter
reports `no subnets found` and provisions nothing. Both sides read `local.name`; neither hardcodes.

---

## 3. Root module variables

`variables.tf`. **Exact names.** Every variable carries a `description` and a `type`;
constrained ones carry a `validation` block.

| Name | Type | Default | Notes |
|---|---|---|---|
| `project_name` | `string` | `"opsfleet"` | Name prefix component. |
| `environment` | `string` | `"poc"` | Name prefix component. |
| `region` | `string` | `"us-east-1"` | AWS region. |
| `additional_tags` | `map(string)` | `{}` | Merged over the base tag set. |
| **Cost controls** ||||
| `enable_budget_alarm` | `bool` | `true` | Creates an AWS Budget scoped to this stack's tags. The only automated guard against a forgotten cluster. |
| `monthly_budget_usd` | `number` | `450` | Must sit clearly ABOVE the idle band (~$255–295 at defaults including log ingest), or the 80% alert fires every normal month and gets muted. Raise it, do not lower it, if you enable VPC endpoints (+$263). |
| `budget_notification_email` | `string` | `""` | Required when `enable_budget_alarm` is true. Alerts at 80% actual and 100% forecast. |
| `alert_email` | `string` | `""` | Subscribed to the SNS topic that receives the KMS-key-danger alarm (Phase 2). Empty = no subscriber, i.e. the alarm is silent. |
| **Networking** ||||
| `vpc_cidr` | `string` | `"10.0.0.0/16"` | Must be **/18 or larger**. At /20 the computed intra subnets are /28 — 11 usable IPs — and AWS requires ≥6 per cluster subnet while *recommending* ≥16. /18 yields /26 intra subnets (59 usable). |
| `az_count` | `number` | `3` | `2`–`3`. Drives subnet slicing. |
| `single_nat_gateway` | `bool` | `false` | `true` = one NAT for all AZs (**POC cost saver**, single point of failure). |
| `enable_vpc_flow_logs` | `bool` | `true` | CloudWatch flow logs on the VPC. |
| `flow_log_retention_days` | `number` | `30` | |
| `enable_vpc_endpoints` | `bool` | **`false`** | Controls the **interface** endpoints only — ~$263/month for 12 endpoints × 3 AZs, the largest line item in the stack. Off by default; see ADR-11. The S3 **gateway** endpoint is free and is always created regardless. |
| **Cluster** ||||
| `kubernetes_version` | `string` | see `reference/version-pinning.md` | EKS minor, e.g. `"1.34"`. |
| `cluster_endpoint_public_access` | `bool` | `true` | |
| `cluster_endpoint_public_access_cidrs` | `list(string)` | `[]` | **Must be non-empty when public access is on** — enforce with a `validation` block; `0.0.0.0/0` is rejected. |
| `cluster_endpoint_private_access` | `bool` | `true` | Always on. |
| `cluster_enabled_log_types` | `list(string)` | `["api","audit","authenticator","controllerManager","scheduler"]` | |
| `cluster_log_retention_days` | `number` | `90` | 90 is the module default, not an AWS recommendation. Drop to `7` for a POC. |
| `cluster_admin_principal_arns` | `list(string)` | `[]` | IAM principals granted **cluster-admin** via EKS access entries. Operators only. |
| `developer_principal_arns` | `list(string)` | `[]` | IAM principals bound to the `developer_rbac_group` Kubernetes group via a `STANDARD` access entry with **no AWS managed access policy**. Permissions come from the ClusterRole in phase-05 §5.3d. Prefer SSO role ARNs over IAM users. |
| `developer_namespaces` | `list(string)` | `["demo"]` | Namespaces the access entries are **scoped to**. Wildcards work (`team-*`); EKS does not validate they exist. |
| `governed_namespaces` | `list(string)` | `["demo"]` | Namespaces Terraform **creates** with PSA `restricted` labels, a ResourceQuota and a LimitRange. Every non-wildcard entry in `developer_namespaces` must appear here — enforced by a precondition, because access without guardrails is the failure mode. |
| `namespace_quota` | `object({ requests_cpu = string, requests_memory = string, limits_cpu = string, limits_memory = string, max_deployments = number })` | `{ requests_cpu = "20", requests_memory = "40Gi", limits_cpu = "40", limits_memory = "80Gi", max_deployments = 20 }` | Per-namespace ResourceQuota. Field names fixed by Phase 0 to match the 5 fields phase-05 §5.3c's chart template reads (`.Values.namespaceQuota.requestsCpu` etc — Phase 5 does the snake_case→camelCase mapping when it builds Helm values). `services.loadbalancers = "0"` is **not** driven by this variable — phase-05's chart template hardcodes it directly in the ResourceQuota, so a `loadbalancers`/`max_loadbalancers` field here would be unused. |
| **Karpenter** ||||
| `karpenter_version` | `string` | see `reference/version-pinning.md` | Helm chart version. |
| `karpenter_namespace` | `string` | `"kube-system"` | |
| `bootstrap_node_instance_types` | `list(string)` | `["t4g.medium"]` | Managed node group that hosts the Karpenter controller. Graviton by default. |
| `bootstrap_node_ami_type` | `string` | `"AL2023_ARM_64_STANDARD"` | **Must match the architecture of `bootstrap_node_instance_types`.** Validate against `["AL2023_ARM_64_STANDARD","AL2023_x86_64_STANDARD"]`. Changing instance types without this is a hard mismatch. |
| `bootstrap_node_min_size` | `number` | `2` | |
| `bootstrap_node_max_size` | `number` | `3` | |
| `bootstrap_node_desired_size` | `number` | `2` | Note: the EKS module **ignores** changes to this after creation (see `reference/gotchas.md` G-06). |
| `taint_bootstrap_nodes` | `bool` | `true` | Taints the bootstrap group `CriticalAddonsOnly=true:NoSchedule` so user workloads only land on Karpenter nodes. |
| `create_spot_service_linked_role` | `bool` | `false` (changed from `true` in Phase 3 — see its completion report) | Creates `AWSServiceRoleForEC2Spot`. Defaults `false` because the resource errors if the role already exists (any account that has used Spot before) and a root-level `import` block was found to hard-fail `terraform apply` on the fresh-account case instead — see `modules/karpenter/README.md`. Set `true` only after confirming the role does not already exist. |
| `request_service_quotas` | `bool` | `true` | Opens vCPU quota-increase requests in code (P3). Approval is asynchronous — apply success ≠ quota raised. |
| `vcpu_quota_target` | `number` | `128` | Must exceed `nodepool_cpu_limit` + the bootstrap group, or the account quota becomes the real ceiling. |
| `developer_rbac_group` | `string` | `"opsfleet:developers"` | Kubernetes group bound to the developer ClusterRole. Access entries reference it via `kubernetes_groups`; **no AWS managed access policy is associated.** |
| **NodePools** ||||
| `nodepool_cpu_limit` | `number` | `100` | Total vCPU ceiling across all Karpenter NodePools. **Karpenter's `spec.limits` is per-NodePool**, so Phase 5 divides this by the number of enabled pools — with both on, each pool gets 50. The blast-radius cap. |
| `nodepool_memory_limit_gi` | `number` | `400` | Same, for memory. A cpu-only limit lets a memory-heavy workload provision far more instance than intended. |
| `nodepool_capacity_types` | `list(string)` | `["spot","on-demand"]` | Valid values are `spot`, `on-demand`. Karpenter 1.14.0 also recognizes a third value, `reserved` (ODCR/Capacity Blocks; `featureGates.reservedCapacity` is beta and on by default) — see `reference/karpenter-api-reference.md`. Phase 5 §5.3a deliberately does not use capacity reservations, so this variable does not accept it; Phase 0's `validation` block enforces exactly this two-value set. |
| `nodepool_default_arch` | `string` | `"arm64"` | Which pool wins for a pod with no arch constraint, implemented via NodePool `weight`. `arm64` makes Graviton the default. |
| `node_ami_alias` | `string` | `"al2023@latest"` | `EC2NodeClass` AMI alias. Pin to a release tag (e.g. `al2023@v20260701`) for production — see `reference/karpenter-api-reference.md` §2. |
| `enable_arm64_nodepool` | `bool` | `true` | |
| `enable_amd64_nodepool` | `bool` | `true` | |
| **Optional phases** ||||
| `enable_aws_load_balancer_controller` | `bool` | `false` | Phase 9. |
| `enable_metrics_server` | `bool` | `false` | Phase 10. |

Any phase adding a variable adds a row here **in the same change**.

---

## 4. Root module outputs

`outputs.tf`. Consumed by the README, the demo instructions and the verification phase.

| Name | Value |
|---|---|
| `region` | The deployed region. |
| `cluster_name` | `local.name`. |
| `cluster_endpoint` | EKS API endpoint. |
| `cluster_version` | Actual running Kubernetes version (from the module output, not `var`). |
| `cluster_certificate_authority_data` | Marked `sensitive = true`. |
| `cluster_security_group_id` | Cluster (control-plane) SG. |
| `node_security_group_id` | Node SG — the one carrying the `karpenter.sh/discovery` tag. |
| `oidc_provider_arn` | For any IRSA that remains. |
| `vpc_id` | |
| `private_subnet_ids` | |
| `public_subnet_ids` | |
| `karpenter_node_iam_role_name` | Role assumed by Karpenter-launched nodes. |
| `karpenter_node_iam_role_arn` | ARN of the role assumed by Karpenter-launched nodes. Added in Phase 3 — consumed by the phase's own "with credentials" acceptance criteria to resolve the node access entry by principal ARN. |
| `karpenter_controller_iam_role_arn` | Role assumed by the Karpenter controller. |
| `karpenter_interruption_queue_name` | SQS queue for Spot interruption / rebalance events. |
| `configure_kubectl` | Ready-to-run string: `aws eks update-kubeconfig --region <r> --name <n>`. |
| `developer_rbac_group` | The Kubernetes group developers are bound to. Consumed by `verify.sh`'s `kubectl auth can-i --as-group` assertions. |

---

## 5. Local module contracts

These are the seams between phases. A phase agent implements the module *and* must satisfy this
signature exactly, because a later phase is already written against it.

### 5.1 `modules/network` — Phase 1

| Direction | Name | Type |
|---|---|---|
| in | `name` | `string` |
| in | `vpc_cidr` | `string` |
| in | `az_count` | `number` |
| in | `single_nat_gateway` | `bool` |
| in | `enable_flow_logs` | `bool` |
| in | `flow_log_retention_days` | `number` |
| in | `enable_vpc_endpoints` | `bool` |
| in | `tags` | `map(string)` |
| out | `vpc_id` | `string` |
| out | `vpc_cidr_block` | `string` |
| out | `private_subnet_ids` | `list(string)` |
| out | `public_subnet_ids` | `list(string)` |
| out | `intra_subnet_ids` | `list(string)` |
| out | `availability_zones` | `list(string)` |
| out | `vpc_endpoints_security_group_id` | `string` |

### 5.2 `modules/eks` — Phase 2

| Direction | Name | Type |
|---|---|---|
| in | `name` | `string` |
| in | `kubernetes_version` | `string` |
| in | `vpc_id` | `string` |
| in | `private_subnet_ids` | `list(string)` |
| in | `control_plane_subnet_ids` | `list(string)` |
| in | `endpoint_public_access` | `bool` |
| in | `endpoint_public_access_cidrs` | `list(string)` |
| in | `endpoint_private_access` | `bool` |
| in | `enabled_log_types` | `list(string)` |
| in | `log_retention_days` | `number` |
| in | `admin_principal_arns` | `list(string)` |
| in | `developer_principal_arns` | `list(string)` |
| in | `developer_rbac_group` | `string` |
| in | `alert_email` | `string` — subscriber for the KMS-key-danger alarm's SNS topic; `""` = silent |
| in | `bootstrap_node_instance_types` | `list(string)` |
| in | `bootstrap_node_ami_type` | `string` — must match the architecture of `bootstrap_node_instance_types` |
| in | `bootstrap_node_min_size` / `_max_size` / `_desired_size` | `number` |
| in | `taint_bootstrap_nodes` | `bool` |
| in | `enable_metrics_server` | `bool` — Phase 10 only; ignored otherwise |
| in | `tags` | `map(string)` |
| out | `cluster_name` | `string` |
| out | `cluster_endpoint` | `string` |
| out | `cluster_version` | `string` |
| out | `cluster_certificate_authority_data` | `string` (sensitive) |
| out | `cluster_security_group_id` | `string` |
| out | `node_security_group_id` | `string` |
| out | `oidc_provider_arn` | `string` |
| out | `kms_key_arn` | `string` |

### 5.3 `modules/karpenter` — Phases 3 & 4

| Direction | Name | Type |
|---|---|---|
| in | `cluster_name` | `string` |
| in | `cluster_endpoint` | `string` |
| in | `karpenter_version` | `string` — used for **both** the `karpenter` and `karpenter-crd` charts |
| in | `namespace` | `string` |
| in | `node_security_group_id` | `string` |
| in | `create_spot_service_linked_role` | `bool` |
| in | `tags` | `map(string)` |
| out | `controller_iam_role_arn` | `string` |
| out | `node_iam_role_name` | `string` |
| out | `node_iam_role_arn` | `string` |
| out | `interruption_queue_name` | `string` |
| out | `interruption_queue_arn` | `string` |
| out | `namespace` | `string` |
| out | `helm_release_name` | `string` — later phases `depends_on` this to order CR creation after the CRDs exist |

### 5.4 `modules/cluster-resources` — Phase 5

| Direction | Name | Type |
|---|---|---|
| in | `cluster_name` | `string` — feeds both the discovery selectors and the CR names |
| in | `node_iam_role_name` | `string` — becomes `EC2NodeClass.spec.role` |
| in | `namespace` | `string` |
| in | `node_ami_alias` | `string` — e.g. `al2023@latest` |
| in | `capacity_types` | `list(string)` |
| in | `cpu_limit` | `number` |
| in | `memory_limit_gi` | `number` — total memory ceiling (GiB) across all enabled NodePools, divided by `local.enabled_pool_count` to compute `memoryLimitPerPool`. Required so every NodePool carries both a cpu AND a memory limit (S-52) |
| in | `default_arch` | `string` — `arm64` or `amd64`; decides the NodePool weights |
| in | `enable_amd64` | `bool` |
| in | `enable_arm64` | `bool` |
| in | `governed_namespaces` | `list(string)` |
| in | `developer_namespaces` | `list(string)` — the namespaces Phase 2's access entries are scoped to; not consumed by any resource (modules/eks's access entries carry no policy_associations), only by this module's `lifecycle.precondition` tying it to `governed_namespaces` |
| in | `developer_rbac_group` | `string` — the group the developer ClusterRole is bound to |
| in | `namespace_quota` | `object` |
| in | `karpenter_helm_release_name` | `string` — used only as a `depends_on` edge so the CRDs exist first |
| in | `tags` | `map(string)` — rendered into `EC2NodeClass.spec.tags`, the only way Karpenter-launched instances get cost-allocation tags |
| out | `storage_class_name` | `string` — the default `gp3` StorageClass this chart also delivers (see phase-02 §2.5b) |
| out | `governed_namespace_names` | `list(string)` — namespaces created with PSA labels, quota and limit range |
| out | `nodepool_names` | `list(string)` |
| out | `ec2nodeclass_name` | `string` |

---

## 6. Kubernetes object names

Fixed, because the demo manifests and the README reference them literally.

| Object | Kind | Name |
|---|---|---|
| Default node class | `EC2NodeClass` | `default` |
| x86 pool | `NodePool` | `amd64` |
| Graviton pool | `NodePool` | `arm64` |
| Demo namespace | `Namespace` | `demo` |

**Scheduling contract** — how a developer targets an architecture:

```yaml
nodeSelector:
  kubernetes.io/arch: arm64   # or amd64
```

`kubernetes.io/arch` is a well-known label set by the kubelet on every node, so this works without
any Karpenter-specific knowledge. Both NodePools must therefore accept pods that carry it, and a pod
with **no** `nodeSelector` must still schedule. See `reference/karpenter-api-reference.md` for how
NodePool `weight` resolves that case deterministically.

---

## 7. Provider configuration

Configured **only** in `providers.tf`. Never inside a module.

**Exactly two providers: `aws` and `helm`. There is no `kubernetes` provider in this stack.**

That is a deliberate simplification, and it is what the upstream `terraform-aws-modules/eks`
Karpenter example does today. Since v21 the EKS module no longer manages the `aws-auth` ConfigMap,
so it has no Kubernetes-provider dependency of its own — the only reason to add one would be to
create Kubernetes objects, and every Kubernetes object here is delivered by Helm instead (see
ADR-7). Dropping the provider removes an entire class of plan-time failures and one more v3-syntax
migration to get wrong.

```hcl
provider "aws" {
  region = var.region
  default_tags { tags = local.tags }
}

# helm provider v3: `kubernetes` and `exec` are ATTRIBUTES (= { ... }), not blocks.
# The v2 block syntax you will find in most examples does not parse under v3.
provider "helm" {
  kubernetes = {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    # exec fetches a fresh token at call time. NEVER use
    # data.aws_eks_cluster_auth: that token is written into state and expires
    # after 15 minutes, which produces intermittent 401s on long applies.
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.region]
    }
  }
}
```

This requires the AWS CLI on whatever machine runs Terraform.

A known ordering hazard remains — see `reference/gotchas.md`. The rule in one line: **provider
config may reference module outputs, but no resource `count`/`for_each` may depend on a value that
only exists after the cluster is created.** Use static toggle variables for conditional Helm
releases, never cluster-derived values.

---

## 8. Style rules

1. `terraform fmt -recursive` must be clean. CI enforces it.
2. Pin everything: `required_version`, every provider with `~>`, every registry module with an exact
   `version = "X.Y.Z"`. No floating versions, no `latest`, no unpinned Helm charts.
3. Every variable has a `description`. Every output has a `description`.
4. Secrets are never defaults, never in `.tfvars.example`, never in outputs unless `sensitive = true`.
5. Comments explain **why**, not what. `# NAT per AZ so a single AZ failure cannot sever egress for
   the whole cluster` is useful; `# create NAT gateway` is not.
6. `.gitignore` must cover `*.tfvars` (except `*.example`), `.terraform/`, `*.tfstate*`, `.terraform.lock.hcl`
   is **committed** (it is a lockfile, not a secret).
7. No `local-exec`/`remote-exec` provisioners anywhere in the deployable stack.

---

## 9. Completion report format

Every phase doc ends with a `## Completion report` section. The implementing agent fills it in and
stops. The next agent reads it to learn what actually happened versus what was specified.

```markdown
## Completion report
- Status: DONE | BLOCKED | PARTIAL
- Files created/changed: <list>
- Deviations from spec: <what and why — or "none">
- Names added to interface-contract.md: <list — or "none">
- Verification run: <commands executed and their result>
- Notes for the next phase: <anything the next agent must know>
```
