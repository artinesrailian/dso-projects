# Version Pinning Reference

**Verified 2026-08-11, and independently re-verified the same day — every value below was unchanged
on the second pass.** Each was fetched from a primary source, not recalled. Sources are listed so any
of it can be re-checked in seconds.

> **Rule for every phase agent:** take versions from this file. Do not recall them from memory —
> model training data lags reality by months and *will* be wrong. During this project's own research
> the model's recollection said "EKS 1.34 is the latest"; the AWS docs said **1.36**. If this file
> looks stale, run §3 and update it, then note the update in your completion report.

---

## 1. Pinned versions

### Tooling (operator's workstation / CI)

| Tool | Pin | Constraint to write | Notes |
|---|---|---|---|
| Terraform CLI | `1.15.8` | `required_version = ">= 1.11.0"` | 1.15.8 released 2026-07-08. `1.16.0-beta2` exists but is **not GA** — do not pin to it. |
| OpenTofu (alternative) | `1.12.5` | `>= 1.12` | Stack is compatible; not the assumed default. |
| AWS CLI | `>= 2.30` | — | Needs `aws eks get-token` and `update-kubeconfig`. |
| kubectl | within ±1 minor of `1.36` | — | i.e. 1.35–1.37. |
| helm | `>= 3.19` | — | Only needed for manual inspection; Terraform drives Helm itself. |

**Why `>= 1.11.0` specifically.** Two constraints meet here. The eks module itself only needs
`>= 1.5.7`, but this stack uses **S3-native state locking** (`use_lockfile = true`), which landed in
Terraform 1.10 and became the recommended path in 1.11 when DynamoDB locking was deprecated. `1.11.0`
is therefore the real floor.

**Why `>=` and not `~>` for `required_version`:** a pessimistic constraint like `~> 1.15` would lock
users out of Terraform 1.16 the moment it goes GA (beta2 shipped 2026-08-05). `required_version` is
the one place where `~>` is usually the wrong tool. Providers and modules are the opposite — pin
those tightly.

### Providers

| Provider | Latest | Constraint to write | Notes |
|---|---|---|---|
| `hashicorp/aws` | `6.58.0` | `~> 6.58` | eks module v21.24.2 declares a floor of `>= 6.52`, so this is compatible. |
| `hashicorp/helm` | `3.2.0` | `~> 3.2` | **Major 3.** See §2 — the HCL syntax differs from every v2-era example you will find online. |
| `hashicorp/kubernetes` | `3.2.1` | `~> 3.2` | **Major 3.** Use the `_v1`-suffixed resource names (`kubernetes_config_map_v1`, not `kubernetes_config_map`) — the unsuffixed aliases are deprecated. |
| `hashicorp/tls` | `4.3.0` | `~> 4.3` | Required transitively by the eks module (`>= 4.0`). |
| `hashicorp/time` | `0.14.0` | `~> 0.14` | **Required by the eks module (`>= 0.9`) and easy to forget.** A `required_providers` block without it is incomplete. |
| `hashicorp/random` | `3.9.0` | `~> 3.9` | Only if you generate suffixes. |
| `hashicorp/null` | `3.3.0` | `~> 3.3` | Pulled in transitively by the eks module's `eks-managed-node-group` submodule (bootstrap node group, Phase 2) — not "probably not needed" after all; no provisioners of our own regardless. |
| `hashicorp/cloudinit` | `2.4.0` | `~> 2.4` | Not anticipated when this table was first written. Pulled in transitively by the same `eks-managed-node-group` submodule for its user-data rendering. Resolved version verified via `terraform init` on 2026-08-16, not re-checked against the registry independently. |

### Modules

| Module | Pin | Source | Notes |
|---|---|---|---|
| EKS | `21.24.2` | `terraform-aws-modules/eks/aws` | Published 2026-08-06. **v21 renamed most root inputs — see §4.** |
| Karpenter | `21.24.2` | `terraform-aws-modules/eks/aws//modules/karpenter` | Same version as the parent module; keep them identical. |
| VPC | `6.6.1` | `terraform-aws-modules/vpc/aws` | Published 2026-04-02. No renames from v5. |

Pin modules with an **exact** `version = "21.24.2"`, not `~> 21.0`. Registry modules ship frequently
(21.24.2 was five days old when verified) and a floating minor can change generated resource names.

### Kubernetes / platform

| Thing | Pin | Notes |
|---|---|---|
| EKS Kubernetes version | **`1.36`** | Newest in EKS standard support as of 2026-08-11. Also in standard support: 1.35, 1.34, 1.33. |
| Conservative alternative | `1.35` | Use if you would rather not run the newest minor. The assignment says "latest available", so **1.36 is the default**. |
| Karpenter controller | `1.14.0` | GitHub release `v1.14.0`, published 2026-07-11. Flagged **LTS**, supported until Jul 2027. |
| Karpenter Helm chart | `1.14.0` | `oci://public.ecr.aws/karpenter/karpenter` — pulled and verified; `version: 1.14.0`, `appVersion: 1.14.0`. |
| Karpenter **CRD** chart | `1.14.0` | `oci://public.ecr.aws/karpenter/karpenter-crd` — **a second, separate release.** See §2.1. |
| Karpenter CRD API | `karpenter.sh/v1`, `karpenter.k8s.aws/v1` | Single served version per CRD; no v1beta1 is served. See `karpenter-api-reference.md`. |
| Node AMI family | AL2023 | Amazon Linux 2 is EOL for EKS. |

**Kubernetes compatibility — resolved.** Karpenter 1.14.0's own getting-started material pins
`K8S_VERSION="1.36"` and the docs site sets `latest_k8s_version: "1.36"`. Karpenter 1.14.0 on EKS
1.36 is the combination upstream tests and documents. No conflict.

### Kubernetes 1.36 behaviour changes that affect this build

Re-verified against the AWS release notes on 2026-08-11. Standard support: **1.36**, 1.35, 1.34, 1.33.

| Change | Relevance here |
|---|---|
| **`StrictIPCIDRValidation` on by default** — the API rejects IP/CIDR values with leading zeros (`010.0.0.5`) or non-canonical CIDRs (`192.168.0.5/24` instead of `192.168.0.0/24`) | Low risk: Phase 1 derives every CIDR with `cidrsubnet()`, which always emits canonical form. But **any hand-written CIDR** — `endpoint_public_access_cidrs`, an ALB `inbound-cidrs` annotation, a NetworkPolicy — must be canonical. Existing objects are ratcheted; new creates and updates are rejected. |
| **`gitRepo` volumes permanently disabled** | None — not used. Noted so nobody adds one. |
| **SELinux volume labeling GA** (`mount -o context` instead of recursive relabel) | None on AL2023 defaults. Relevant only if you share a volume between privileged and unprivileged pods. |
| **User Namespaces stable** | Opportunity, not a requirement: maps container root to an unprivileged host user, so a breakout grants no node admin. Worth mentioning in the README as a hardening follow-up. |
| **Service `externalIPs` deprecated** (removal planned 1.43) | None — Phase 9 uses the AWS Load Balancer Controller. |
| **1.35 removed cgroup v1; it was also the last release supporting containerd 1.x** | None — AL2023 is cgroup v2 and containerd 2.x by default. Only bites custom AMIs. |
| **No EKS-optimized AL2 AMI from 1.34 onward** | Confirms ADR-10: AL2023 or Bottlerocket only. |
| **Ingress NGINX retired upstream (March 2026)** | Reinforces Phase 9's choice of the AWS Load Balancer Controller over ingress-nginx. |

> ⚠️ **Do not read Karpenter's version out of its git tree.** At git tag `v1.14.0`, both
> `charts/karpenter/Chart.yaml` and `charts/karpenter-crd/Chart.yaml` still say `version: 1.13.0`,
> and `values.yaml` pins `controller.image.tag: 1.13.0`. The release pipeline stamps the real
> version at publish time. The **published OCI artifact** is authoritative — that is what reports
> 1.14.0. Similarly, the chart's `artifacthub.io/crds` annotation still claims the CRDs are
> `v1beta1`; that is dead metadata, and the CRD YAML (which serves only `v1`) wins.

### EKS add-ons

Pin by letting the module resolve `most_recent = true` for the POC, and record the resolved versions
after the first apply. The add-on set is:

| Add-on | Required? | Notes |
|---|---|---|
| `vpc-cni` | yes | Pod networking. |
| `coredns` | yes | Must tolerate the bootstrap node group before Karpenter nodes exist. |
| `kube-proxy` | yes | |
| `eks-pod-identity-agent` | **yes** | Non-optional here: the Karpenter controller uses Pod Identity, and without the agent it cannot obtain credentials. |
| `aws-ebs-csi-driver` | recommended | Needed for any PVC. Requires its own IAM role. |
| `metrics-server` | optional | Phase 10 only. |

`coredns` and `kube-proxy` must be created **before** compute in the module (`before_compute = true`
on `vpc-cni`) or nodes join without networking.

---

## 2. Things that have changed — read before writing HCL

### 2.1 Karpenter ships **two** Helm charts, and you need both

This is the most consequential packaging detail in the whole stack.

The main `karpenter` chart carries its CRDs in `charts/karpenter/crds/`. Helm's `crds/` directory
has a hard rule: **CRDs there are installed on first install only, and are never updated or added by
any subsequent `helm upgrade`.** So a stack that only installs the main chart will work on day one
and then silently fail to pick up new or changed CRDs on every upgrade thereafter — exactly what
happened at 1.14.0, which introduced a brand-new `CapacityBuffer` CRD.

The fix, and the path Karpenter's own docs prescribe, is the separate `karpenter-crd` chart, which
ships the same five CRDs under `templates/` so Helm manages them normally:

```hcl
resource "helm_release" "karpenter_crd" {
  name       = "karpenter-crd"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter-crd"
  version    = "1.14.0"          # keep identical to the controller chart, always
  namespace  = "kube-system"
}

resource "helm_release" "karpenter" {
  # ...
  depends_on = [helm_release.karpenter_crd]
}
```

Both charts must be upgraded together, to the same version. Phase 4 specifies this.

### 2.2 Provider syntax that has changed

Almost every EKS/Karpenter example on the internet was written for `helm` provider v2. This stack
pins v3, and the syntax is different. Getting this wrong produces confusing type errors.

```hcl
# helm provider v3 — CORRECT
resource "helm_release" "karpenter" {
  name       = "karpenter"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = "1.14.0"
  namespace  = "kube-system"

  set = [                                   # a LIST of objects, not repeated blocks
    { name = "settings.clusterName", value = module.eks.cluster_name },
    { name = "settings.interruptionQueue", value = module.karpenter.queue_name },
  ]
}

# helm provider v2 — WRONG under v3, will not parse
#   set {
#     name  = "settings.clusterName"
#     value = "..."
#   }
```

v3 changes in full: it moved to terraform-plugin-framework, so `kubernetes { }` became
`kubernetes = { }`, repeated `registry { }` blocks became a single `registries = [ ... ]` list,
`experiments { }` became `experiments = { }`, and `set` / `set_list` / `set_sensitive` became lists
of objects. It speaks protocol v6, requiring Terraform >= 1.0.

For the `kubernetes` provider v3, prefer `_v1`-suffixed resources: `kubernetes_namespace_v1`,
`kubernetes_secret_v1`, `kubernetes_config_map_v1`, `kubernetes_service_account_v1`.

---

## 3. Re-verification commands

Run this whole block to confirm nothing has drifted. It needs no AWS credentials.

```bash
#!/usr/bin/env bash
set -euo pipefail

jqv() { jq -r "${2}"; }

echo "== Terraform registry: modules =="
for m in terraform-aws-modules/eks/aws terraform-aws-modules/vpc/aws; do
  printf '%-40s %s\n' "$m" \
    "$(curl -s "https://registry.terraform.io/v1/modules/${m}" | jq -r '.version')"
done

echo "== Terraform registry: providers =="
for p in hashicorp/aws hashicorp/helm hashicorp/kubernetes hashicorp/tls hashicorp/time hashicorp/random; do
  printf '%-30s %s\n' "$p" \
    "$(curl -s "https://registry.terraform.io/v1/providers/${p}" | jq -r '.version')"
done

echo "== Terraform CLI (GA only) =="
curl -s 'https://api.releases.hashicorp.com/v1/releases/terraform?limit=20' \
  | jq -r '[.[] | select(.is_prerelease == false)] | .[0].version'

echo "== Karpenter controller =="
curl -s https://api.github.com/repos/aws/karpenter-provider-aws/releases/latest | jq -r '.tag_name'

echo "== Karpenter Helm chart tags (needs no auth for public ECR listing via crane/oras, else check GitHub) =="
helm show chart oci://public.ecr.aws/karpenter/karpenter --version 1.14.0 2>/dev/null \
  | grep -E '^(version|appVersion|kubeVersion):' || echo "  (helm not logged in to public ECR — see below)"

echo "== EKS Kubernetes versions in standard support =="
echo "   open: https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions-standard.html"
# With AWS credentials, this is authoritative:
#   aws eks describe-cluster-versions --query 'clusterVersions[?status==`STANDARD_SUPPORT`].clusterVersion'

echo "== eks module's own declared provider floors =="
curl -s "https://raw.githubusercontent.com/terraform-aws-modules/terraform-aws-eks/v21.24.2/versions.tf"
```

**Karpenter ↔ Kubernetes compatibility** (the one open question, resolve it in Phase 4):

```bash
# public ECR allows anonymous pulls; if helm balks, get a token first:
aws ecr-public get-login-password --region us-east-1 \
  | helm registry login --username AWS --password-stdin public.ecr.aws
helm show chart oci://public.ecr.aws/karpenter/karpenter --version 1.14.0 | grep kubeVersion
# and cross-check the compatibility matrix:
#   https://karpenter.sh/docs/upgrading/compatibility/
```

With credentials, confirm the EKS version list directly:

```bash
aws eks describe-cluster-versions \
  --query 'clusterVersions[?status==`STANDARD_SUPPORT`].[clusterVersion,endOfStandardSupportDate]' \
  --output table
```

---

## 4. Module migration traps (v20 → v21)

The eks module's v21 major renamed nearly every root input by stripping the `cluster_` prefix — but
**left the outputs alone**. This asymmetry is the single most common source of wasted time, because
half of any example you find online is now wrong.

```hcl
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.24.2"

  name               = local.name        # v20 was: cluster_name
  kubernetes_version = "1.36"            # v20 was: cluster_version
  # ...
}

# but reading it back keeps the old prefix:
module.eks.cluster_name       # ✅ correct
module.eks.cluster_version    # ✅ correct
module.eks.name               # ❌ does not exist
module.eks.kubernetes_version # ❌ does not exist
```

### Full rename table (root module)

| v20 input | v21 input |
|---|---|
| `cluster_name` | `name` |
| `cluster_version` | `kubernetes_version` |
| `cluster_enabled_log_types` | `enabled_log_types` |
| `cluster_endpoint_private_access` | `endpoint_private_access` |
| `cluster_endpoint_public_access` | `endpoint_public_access` |
| `cluster_endpoint_public_access_cidrs` | `endpoint_public_access_cidrs` |
| `cluster_encryption_config` | `encryption_config` |
| `cluster_addons` | `addons` |
| `cluster_addons_timeouts` | `addons_timeouts` |
| `cluster_ip_family` | `ip_family` |
| `cluster_service_ipv4_cidr` | `service_ipv4_cidr` |
| `cluster_service_ipv6_cidr` | `service_ipv6_cidr` |
| `cluster_additional_security_group_ids` | `additional_security_group_ids` |
| `create_cluster_security_group` | `create_security_group` |
| `cluster_security_group_id` | `security_group_id` |
| `cluster_security_group_name` | `security_group_name` |
| `cluster_security_group_description` | `security_group_description` |
| `cluster_security_group_additional_rules` | `security_group_additional_rules` |
| `cluster_security_group_tags` | `security_group_tags` |
| `cluster_security_group_use_name_prefix` | `security_group_use_name_prefix` |
| `create_cluster_primary_security_group_tags` | `create_primary_security_group_tags` |
| `cluster_encryption_policy_*` | `encryption_policy_*` |
| `cluster_identity_providers` | `identity_providers` |
| `cluster_timeouts` | `timeouts` |
| `cluster_compute_config` | `compute_config` |
| `cluster_upgrade_policy` | `upgrade_policy` |
| `cluster_force_update_version` | `force_update_version` |
| `cluster_zonal_shift_config` | `zonal_shift_config` |
| `cluster_remote_network_config` | `remote_network_config` |

In the node-group submodules, `cluster_version` → `kubernetes_version` as well.

### Removed in v21

- `enable_efa_support`, `enable_security_groups_for_pods` — for the latter, attach
  `arn:aws:iam::aws:policy/AmazonEKSVPCResourceController` via `iam_role_additional_policies`.
- `manage_aws_auth_configmap` — gone entirely. Use `access_entries` + `authentication_mode`.

### Karpenter submodule: variables removed in v21

Passing any of these is a **hard error**, and they appear in every pre-v21 blog post:

`enable_v1_permissions`, `enable_pod_identity`, `enable_irsa`, `irsa_oidc_provider_arn`,
`irsa_namespace_service_accounts`, `irsa_assume_role_condition_test`.

v21's karpenter submodule is **Pod-Identity-only** and always installs the Karpenter v1 policy.
There is nothing to enable.

### Behaviour changes that bite silently

| Change | Consequence |
|---|---|
| `addons.resolve_conflicts_on_create` now defaults `"NONE"` (was `"OVERWRITE"`) | Add-on creation fails if a conflicting resource already exists. |
| `addons.most_recent` now defaults `true` (was `false`) | Add-on versions float unless pinned. |
| `encryption_config = null` disables custom-KMS encryption | The v20 idiom `{}` no longer does this. Secrets are always encrypted at rest by EKS regardless. |
| IRSA OIDC issuer now uses the dual-stack `oidc-eks` endpoint | Any hand-written IRSA trust policy referencing `oidc.eks` needs updating. |

---

## 5. Defaults that break a naive copy-paste

Verified against v21.24.2 / v6.6.1 source. Each of these defaults to a value that produces a broken
or unreachable cluster if you do not override it.

| Module | Variable | Default | What goes wrong |
|---|---|---|---|
| eks | `endpoint_public_access` | **`false`** | Cluster is private-only. `kubectl` and Terraform from outside the VPC hang with no useful error. |
| eks | `enable_cluster_creator_admin_permissions` | **`false`** | The identity that ran `apply` gets **no** Kubernetes RBAC. First `kubectl get nodes` returns "You must be logged in to the server". |
| eks | `authentication_mode` | `"API_AND_CONFIG_MAP"` | Leaves the legacy aws-auth path enabled. Set `"API"` explicitly. |
| eks | `create_kms_key` | `true` | Fine — but means a KMS key + alias is created and must be handled on destroy. |
| vpc | `enable_nat_gateway` | **`false`** | Private subnets have no egress. Nodes cannot pull images and never join the cluster. |
| vpc | `enable_flow_log` | `false` | Plus `create_flow_log_cloudwatch_log_group` and `create_flow_log_cloudwatch_iam_role` **also** default `false` — all three must be `true` for working CloudWatch flow logs. |
| karpenter | `create_instance_profile` | `false` | **Correct — leave it.** Karpenter v1 creates the instance profile itself from the node role. Pass `node_iam_role_name` into the EC2NodeClass `role` field; do **not** use the `instance_profile_name` output (it is empty). |
| karpenter | `create_access_entry` | `true` | **Correct — leave it.** This is what lets Karpenter nodes join under `authentication_mode = "API"`. Setting it `false` produces nodes that boot and never register. |

Note also the VPC module's inconsistent flow-log prefixes: IAM role/policy variables use
`vpc_flow_log_*`, everything else uses `flow_log_*`.

And in the karpenter submodule, the controller permissions-boundary variable is
`iam_role_permissions_boundary_arn` (with `_arn`) while the node one is
`node_iam_role_permissions_boundary` (without). Not a typo in this document.

---

## 6. Sources

- `https://registry.terraform.io/v1/modules/terraform-aws-modules/eks/aws`
- `https://registry.terraform.io/v1/modules/terraform-aws-modules/vpc/aws`
- `https://registry.terraform.io/v1/providers/hashicorp/{aws,helm,kubernetes,tls,time,random}`
- `https://api.releases.hashicorp.com/v1/releases/terraform`
- `https://api.github.com/repos/aws/karpenter-provider-aws/releases/latest`
- `https://raw.githubusercontent.com/terraform-aws-modules/terraform-aws-eks/v21.24.2/{variables,outputs,versions}.tf`
- `https://raw.githubusercontent.com/terraform-aws-modules/terraform-aws-eks/v21.24.2/modules/karpenter/{variables,outputs}.tf`
- `https://raw.githubusercontent.com/terraform-aws-modules/terraform-aws-eks/v21.24.2/docs/UPGRADE-21.0.md`
- `https://raw.githubusercontent.com/terraform-aws-modules/terraform-aws-vpc/v6.6.1/{variables,outputs}.tf`
- `https://raw.githubusercontent.com/hashicorp/terraform-provider-helm/main/docs/guides/v3-upgrade-guide.md`
- `https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions-standard.html`
