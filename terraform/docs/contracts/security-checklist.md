# Security Checklist

Every requirement is owned by exactly one phase, and that phase may not report DONE until its items
are satisfied. Phase 8 signs the whole list off in `docs/AUDIT.md`.

Each row states the **concrete setting** that implements it — a checklist that only says "encrypt
things" is a wish list.

**Threat model, briefly.** This is a POC for a startup's first cluster. The realistic threats are:
credentials leaking through a public API endpoint or a committed `tfvars`; a compromised pod
escalating via node IAM credentials; an over-broad IAM policy turning a container breakout into
account compromise; and unmanaged spend or orphaned resources after teardown. Nation-state
adversaries and multi-tenant hostile workloads are explicitly **not** in scope — a cluster designed
for those would need network policy, runtime detection and namespace-level isolation, none of which
is here. That boundary is stated in `00-architecture-and-decisions.md` §6.

---

## Phase 0 — Repository and state

| ID | Requirement | Implemented by |
|---|---|---|
| **S-01** | Terraform state bucket is versioned, encrypted with a customer-managed KMS key with rotation, has all four public-access blocks, ACLs disabled, and a bucket policy denying non-TLS requests | `bootstrap/main.tf` |
| **S-00** | The operator authenticates with short-lived credentials | IAM Identity Center (SSO) or an assumed role. **No IAM user with long-lived access keys**, and no AWS credentials in any variable, tfvars or repository secret — the provider uses the standard credential chain. CI uses OIDC federation (Phase 11). See `operator-runbook.md` §1.1. |
| **S-02** | No secrets in committed files | `terraform/.gitignore` covers `*.tfvars` (except `*.example`) and `backend.hcl`; the bucket name is supplied via partial backend config, not committed |
| **S-03** | Every provider and module pinned; `.terraform.lock.hcl` committed | `versions.tf` uses `~>` for providers and exact versions for modules |
| **S-04** | `0.0.0.0/0` on the API endpoint is impossible, enforced by code rather than convention | `validation` block on `cluster_endpoint_public_access_cidrs` |

## Phase 1 — Network

| ID | Requirement | Implemented by |
|---|---|---|
| **S-10** | Nodes and pods have no public IP and exist only in private subnets | Nodes placed in `private_subnets`; `map_public_ip_on_launch` off |
| **S-11** | Control-plane ENIs cannot egress | `intra_subnets` — route tables with no NAT route |
| **S-12** | The VPC's **default security group** carries no rules, so nothing can accidentally use it | `manage_default_security_group = true` with `default_security_group_ingress = []` and `_egress = []`. **The default NACL is deliberately left allow-all** — every subnet uses it, so emptying it black-holes the VPC. See phase-01 §1.6. |
| **S-13** | VPC endpoint security group allows 443 from the VPC CIDR only | Dedicated SG on the interface endpoints |
| **S-14** | VPC flow logs on by default with defined retention | `enable_flow_log` + `create_flow_log_cloudwatch_log_group` + `create_flow_log_cloudwatch_iam_role`, all three |
| **S-15** | No security group in the network module has `0.0.0.0/0` ingress | Reviewed; asserted by a grep in the phase acceptance criteria |

## Phase 2 — Cluster

| ID | Requirement | Implemented by |
|---|---|---|
| **S-20** | Authentication uses EKS access entries; the legacy aws-auth path is off | `authentication_mode = "API"` (note: a one-way door, chosen at create time) |
| **S-21** | Kubernetes API data envelope-encrypted with a customer-managed key with rotation | `create_kms_key = true` + `encryption_config = { resources = ["secrets"] }`. *Baseline encryption with an AWS-owned key exists by default since k8s 1.28; the CMK adds controllable policy/rotation/audit at the cost of an availability risk — see the Phase 2 note.* |
| **S-29** | The one unrecoverable failure has an actual detector | EventBridge rule on CloudTrail `DisableKey`/`ScheduleKeyDeletion` for the cluster CMK → SNS → email. Requires CloudTrail enabled in the account, and a **confirmed** SNS subscription. |
| **S-22** | All five control-plane log types enabled with explicit retention | `enabled_log_types` = api, audit, authenticator, controllerManager, scheduler; `cloudwatch_log_group_retention_in_days` |
| **S-23** | Public endpoint disabled, or restricted to an explicit allowlist | `endpoint_public_access_cidrs`, guarded by S-04 |
| **S-24** | Managed node group volumes encrypted; IMDSv2 required with hop limit 1 | `block_device_mappings.ebs.encrypted = true`; `metadata_options.http_tokens = "required"`, `http_put_response_hop_limit = 1` |
| **S-25** | Workload AWS access uses Pod Identity, never static keys | `eks-pod-identity-agent` add-on installed; EBS CSI driver via `pod_identity_association` with an `sts:AssumeRole` **and** `sts:TagSession` trust policy |
| **S-26** | Cluster admin is granted only to the creating identity plus an explicit allowlist | `enable_cluster_creator_admin_permissions` + `var.admin_principal_arns` |
| **S-28** | Developers hold a **purpose-built** Role, not an AWS managed access policy | Access entry is `STANDARD` type with `kubernetes_groups`, **no policy association**. Permissions come from a ClusterRole this stack owns, bound per-namespace by a RoleBinding. `AmazonEKSEditPolicy` is rejected because it grants full CRUD on `secrets`, `serviceaccounts: impersonate`, `daemonsets` and `pods/exec` — see phase-02. |
| **S-28c** | No developer can read another's credentials, impersonate a workload identity, or escalate | The Role grants **no** verb on `secrets`, `serviceaccounts`, `roles` or `rolebindings`. Asserted by six `kubectl auth can-i --as-group` checks in `verify.sh`, which evaluate real RBAC. |
| **S-28a** | Access and guardrails are created by the **same** `terraform apply`, and cannot drift apart | The namespace, its PSA labels, its ResourceQuota and its LimitRange are Terraform-managed (`modules/cluster-resources`), not a manual `kubectl apply`. A precondition fails the plan if any non-wildcard `developer_namespaces` entry is missing from `governed_namespaces` — i.e. Terraform refuses to grant access to an ungoverned namespace. |
| **S-28b** | One developer cannot consume the cluster, or expose it | Per-namespace `ResourceQuota` (cpu/memory requests and limits, deployment count) plus a `LimitRange` supplying default requests so a request-less pod cannot overcommit a shared node. `services.loadbalancers = 0` blocks self-service public load balancers. |
| **S-27** | The **bootstrap** node role is held to the same bar as the Karpenter node role | `iam_role_attach_cni_policy = false`; ECR access via `AmazonEC2ContainerRegistryPullOnly` rather than the module's default `…ReadOnly`. This role is the more privileged of the two and is easy to forget because the module configures it for you. |

## Phase 3 — Karpenter IAM

| ID | Requirement | Implemented by |
|---|---|---|
| **S-30** | Karpenter controller credentials come from Pod Identity | `create_pod_identity_association = true`; no IRSA, no static keys |
| **S-31** | `iam:PassRole` cannot be used to escalate | Scoped to the single node role ARN with `iam:PassedToService = ec2.amazonaws.com` |
| **S-32** | Karpenter node role carries only the necessary managed policies, and **not** `AmazonEKS_CNI_Policy` | `AmazonEKSWorkerNodePolicy`, `AmazonEC2ContainerRegistryPullOnly` (the tighter replacement for `…ReadOnly`), `AmazonSSMManagedInstanceCore`. Set `node_iam_role_attach_cni_policy = false` and give the `vpc-cni` add-on its own Pod Identity role instead — otherwise every node role carries ENI and IP-manipulation rights that any `hostNetwork` pod inherits, which contradicts the least-privilege claim. **Residual risk to record:** `AmazonSSMManagedInstanceCore` grants `ssm:GetParameter*` on `Resource: "*"`, so anything reaching node credentials can read every unencrypted SSM parameter in the account. Accepted here because Session Manager is the only node access path and there is no SSH key; replace with a scoped inline policy in production. |
| **S-33** | Interruption queue encrypted, and writable only by the event services | `queue_managed_sse_enabled = true`; queue policy allows `SendMessage` only from `events.amazonaws.com` / `sqs.amazonaws.com`, with an explicit deny when `aws:SecureTransport` is false |
| **S-34** | Exactly one node access entry, of the correct type | `create_access_entry = true`, `access_entry_type = "EC2_LINUX"` |

> **Residual risk to record in the audit:** because Karpenter keys off instance tags, a principal
> with `ec2:CreateTags`/`DeleteTags` on `i-*` can induce Karpenter to create or delete machines.
> Constrain those actions in any real environment.

## Phase 4 — Karpenter deployment

| ID | Requirement | Implemented by |
|---|---|---|
| **S-40** | Helm charts pinned to exact versions | `version = var.karpenter_version` on both releases; no floating constraint |
| **S-41** | No IRSA annotation on the service account | `serviceAccount.annotations` left empty |
| **S-42** | Spot interruptions drain nodes rather than killing them | `settings.interruptionQueue` set — the chart accepts its absence silently, which disables all interruption handling |
| **S-43** | Controller has resource requests and limits | `controller.resources.{requests,limits}` = 1 CPU / 1Gi |
| **S-44** | CRD security/validation fixes actually land on upgrade | CRDs managed by the separate `karpenter-crd` chart, not the main chart's `crds/` directory |

## Phase 5 — NodePools

| ID | Requirement | Implemented by |
|---|---|---|
| **S-50** | Karpenter node root volumes encrypted | `blockDeviceMappings[].ebs.encrypted: true`, re-stated explicitly because overriding the block discards Karpenter's encrypted-by-default mapping |
| **S-51** | Containers cannot reach IMDS to steal node credentials | `metadataOptions.httpTokens: required`, `httpPutResponseHopLimit: 1`. **Limitation:** `hostNetwork: true` pods reach IMDS regardless. A strong control, not an absolute boundary. |
| **S-52** | A runaway workload cannot provision unbounded capacity | `spec.limits.cpu` **and** `spec.limits.memory` on every NodePool. Note `spec.limits` is **per-NodePool** — Phase 5 divides `nodepool_cpu_limit` across the enabled pools so the configured number is the true cluster ceiling. |
| **S-53** | Consolidation cannot churn the whole fleet at once | `disruption.budgets` (`nodes: "10%"`) |
| **S-54** | Nodes are rotated so they stay patched | `expireAfter: 720h` |
| **S-55** | Resource selection cannot reach another cluster's infrastructure | Tag-based selectors keyed on the cluster name; at most one SG in the account carries `karpenter.sh/discovery` |

## Phase 6 — Workload examples

| ID | Requirement | Implemented by |
|---|---|---|
| **S-60** | Example manifests model good pod security | `runAsNonRoot`, `allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]`, `readOnlyRootFilesystem` where the image supports it |
| **S-61** | Every container has resource requests and limits | Also required for Karpenter to size nodes correctly |
| **S-62** | Images pinned by tag, pulled from public ECR | Avoids Docker Hub rate limiting through a single NAT IP |
| **S-63** | No `hostPath`, no `hostNetwork`, no privileged containers | Reviewed |
| **S-64** | Pod security is **enforced by the API server, and created by Terraform** — not modelled in an example a human has to remember to apply | `modules/cluster-resources` creates every `governed_namespaces` entry with `pod-security.kubernetes.io/enforce: restricted`, `enforce-version: v1.36`, plus `audit`/`warn`. In-tree Pod Security Admission: no controller, no cost. Terraform-managed, so a later apply restores the labels if they are stripped. `kube-system` stays `privileged` — the CNI and Pod Identity agents require it. |

## Phase 7 — Documentation

| ID | Requirement | Implemented by |
|---|---|---|
| **S-70** | Prerequisites describe least-privilege deployment credentials, not account root | README §Prerequisites |
| **S-71** | No real account IDs, IPs, ARNs or key material anywhere | Placeholders use the RFC 5737 documentation range (`203.0.113.0/24`) |
| **S-72** | The endpoint-CIDR guidance explains the control rather than just stating it | README §Configuration |
| **S-73** | Known limitations stated honestly | CMK availability risk; `hostNetwork` IMDS bypass; `al2023@latest` drift; and whether the stack was ever actually applied |

## Cost controls (Phase 0 / Phase 5)

Cost is a Well-Architected pillar and, for a POC, the failure mode most likely to actually happen.

| ID | Requirement | Implemented by |
|---|---|---|
| **S-C1** | Spend is attributable | `local.tags` on every provider-created resource **and** rendered into `EC2NodeClass.spec.tags`, because `default_tags` never reaches Karpenter-launched instances |
| **S-C2** | A forgotten cluster announces itself | `aws_budgets_budget` filtered on the `Project`/`Environment` tags, alerting at 80% actual and 100% forecast (`enable_budget_alarm`, default `true`) |
| **S-C3** | Capacity has a hard ceiling | NodePool `spec.limits` for cpu and memory (S-52) |
| **S-C4** | Idle capacity is reclaimed | `consolidationPolicy: WhenEmptyOrUnderutilized`; the cluster returns to zero Karpenter nodes when idle, verified in Phase 8 §F |
| **S-C5** | Teardown is complete and verified | `scripts/teardown.sh` refuses to proceed while instances remain, and sweeps launch templates Terraform never knew about |
| **S-C6** | The largest line item is opt-in | `enable_vpc_endpoints` defaults `false` (~$263/month) — ADR-11 |

---

## Phases 9–11 — Optional

| ID | Requirement | Phase |
|---|---|---|
| **S-90** | Load balancer controller uses Pod Identity with the AWS-published policy, unmodified | 9 |
| **S-91** | Ingresses default to internal scheme; internet-facing is explicit and deliberate | 9 |
| **S-92** | metrics-server is not exposed outside the cluster and runs with a read-only root filesystem | 10 |
| **S-93** | CI runs `fmt`, `validate`, `tflint` and a policy scanner on every change, and fails the build on high-severity findings | 11 |
| **S-94** | CI authenticates to AWS with OIDC federation, never long-lived access keys in repository secrets | 11 |

---

## Deliberately not done

Stating these makes the scope a decision rather than an omission. Each would be required for a
production, multi-tenant cluster.

| Not done | Why | What it would take |
|---|---|---|
| Network policy / pod-to-pod isolation | No hostile workloads in scope. **But be precise about the residual**: the plan's own developer model is 5-20 principals sharing a namespace (`developer_principal_arns`), so "single-tenant" means one company, not one workload. Every pod can reach every other pod and all egress is unrestricted. | Cilium, or the VPC CNI's built-in network policy support, with default-deny ingress and egress per namespace |
| Runtime threat detection | Out of scope | GuardDuty EKS Protection, or the `aws-guardduty-agent` add-on |
| **External** policy engine (Kyverno / OPA Gatekeeper) | In-tree Pod Security Admission covers the POC's needs at zero cost — see S-64. An external engine adds mutation, custom policy and non-pod resources. | Deploy Kyverno with policies enforcing image provenance, resource limits and topology rules |
| Image scanning and signing | No application images are built here | ECR enhanced scanning; cosign verification at admission |
| Secrets management | No application secrets exist | External Secrets Operator or the AWS Secrets Manager CSI driver |
| Private-only endpoint by default | A POC a reviewer must be able to reach | `endpoint_public_access = false` plus an SSM bastion; the variables already support it |
| Automatic node repair | Not required for a POC | `eks-node-monitoring-agent` add-on plus node auto-repair — supported with Karpenter |
| Cluster upgrade automation | Deliberate human action | A tested blue/green or in-place upgrade runbook |

---

## How to use this in a phase

1. Read your phase's rows before writing code.
2. Satisfy them as you go — not as a cleanup pass.
3. Assert what can be asserted in the phase's acceptance criteria.
4. In your completion report, list any row you could not satisfy and why. **Do not silently drop
   one.** A stated gap is a finding; an unstated gap is a defect.
