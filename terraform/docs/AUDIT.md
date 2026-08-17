# Hardening audit

**This stack has never been applied to an AWS account.** No credentials were available in any
phase's implementation session, there is no Terraform state, and no `terraform apply`, `kubectl` or
`aws` command has ever run against real infrastructure — so **no row below is marked ✅ Verified**.
What is recorded instead is the concrete setting that implements each requirement, and, where a
requirement can be checked without an account, the output of the offline command that checks it.

One row per item in [`contracts/security-checklist.md`](contracts/security-checklist.md) — 61 in
total, in the checklist's own order.

---

## How to read the Status column

| Status | Means |
|---|---|
| ✅ **Verified** | A command was run against real AWS and its output confirms the requirement. **Nothing in this document carries this status.** |
| 📝 **Implemented, not verified** | The code implements the requirement and it has been read and cross-checked against the pinned upstream source, but no apply happened. |
| ⚠️ **Deviation** | Done differently from the checklist, or only partly. What and why is stated. |
| ❌ **Not done** | Not implemented. Why, and whether it matters, is stated. |

**Offline evidence does not upgrade a row to ✅.** Several requirements are genuinely provable
without an account — `.gitignore` coverage, version pins, the absence of `0.0.0.0/0` ingress, the
example manifests' security context, the rendered Helm chart's PSA labels and quotas. Those commands
were run and their output is in [Appendix A](#appendix-a--offline-evidence), but ✅ is reserved for
what §8.3 defines it as: evidence from real AWS. A reviewer should be able to disprove nothing here
in five minutes.

To reproduce the live half, see [Appendix B](#appendix-b--what-verification-would-actually-look-like).

---

## Phase 0 — Repository and state

| ID | Requirement | Implemented in | Status | Evidence |
|---|---|---|---|---|
| S-01 | State bucket versioned, CMK-encrypted with rotation, all four public-access blocks, ACLs disabled, non-TLS denied | `bootstrap/main.tf` | 📝 Implemented, not verified | `aws_s3_bucket_versioning` `status = "Enabled"`; `aws_kms_key.state` with `enable_key_rotation = true`, `deletion_window_in_days = 30`; `aws_s3_bucket_public_access_block` sets all four flags `true`; `aws_s3_bucket_ownership_controls` = `BucketOwnerEnforced`; bucket policy `DenyInsecureTransport` on `aws:SecureTransport = false` plus `DenyUnencryptedObjectUploads`. Never applied — `bootstrap/` has no state either. |
| S-00 | Operator authenticates with short-lived credentials; no long-lived keys anywhere | `operator-runbook.md` §1.1; provider uses the default credential chain | 📝 Implemented, not verified | No `access_key`/`secret_key` argument in any `provider "aws"` block; no credential variable in `variables.tf`. Appendix A.1. Cannot be verified further without an account — S-00 is a property of the *operator*, not the code. |
| S-02 | No secrets in committed files | `.gitignore`; partial backend config | 📝 Implemented, not verified | `*.tfvars`, `backend.hcl`, `*.tfstate`, `*.plan` ignored, `!*.tfvars.example` re-included; `git ls-files` shows no tracked `.tfvars` or `backend.hcl`. Appendix A.1. `*.plan` closes REVIEW.md F-07: the Makefile saves plans as `tf.plan`, which a saved plan embeds every variable value and planned attribute (CA data, ARNs, emails, allowlist CIDRs) into — the prior `*.tfplan`-only pattern did not match it. |
| S-03 | Every provider and module pinned; `.terraform.lock.hcl` committed | `versions.tf`, `modules/*/versions.tf` | 📝 Implemented, not verified | Providers pinned with `~>` (aws `~> 6.58`, helm `~> 3.2`, tls `~> 4.3`, time `~> 0.14`, null `~> 3.3`, cloudinit `~> 2.4`); modules pinned exactly (`eks` `21.24.2`, `vpc` `6.6.1`); two lockfiles tracked in git. Appendix A.2. |
| S-04 | `0.0.0.0/0` on the API endpoint impossible, enforced by code | `variables.tf` `validation` on `cluster_endpoint_public_access_cidrs` | 📝 Implemented, not verified | `condition = !contains(var.cluster_endpoint_public_access_cidrs, "0.0.0.0/0")`. **This is the one control with a real executing test**: `tests/cidr_guard.tftest.hcl` proves the guard fires — `terraform test` → 5 passed, 0 failed. Appendix A.3. |

## Phase 1 — Network

| ID | Requirement | Implemented in | Status | Evidence |
|---|---|---|---|---|
| S-10 | Nodes and pods have no public IP, private subnets only | `modules/network/main.tf`; `modules/eks/main.tf` `subnet_ids = var.private_subnet_ids` | 📝 Implemented, not verified | Bootstrap node group and `EC2NodeClass.subnetSelectorTerms` both resolve to subnets tagged `karpenter.sh/discovery`, which is set on `private_subnet_tags` only. `map_public_ip_on_launch` is left at the VPC module's default `false` for private subnets. |
| S-11 | Control-plane ENIs cannot egress | `modules/network/main.tf` `intra_subnets`; wired to `control_plane_subnet_ids` | 📝 Implemented, not verified | `intra_subnets` get route tables with no NAT route (VPC module behaviour); `main.tf:30` wires `module.network.intra_subnet_ids` → `module.eks.control_plane_subnet_ids`. |
| S-12 | VPC default security group carries no rules | `modules/network/main.tf` | ⚠️ **Deviation** — default SG satisfied, default NACL deliberately not emptied | `manage_default_security_group = true` with `default_security_group_ingress = []` and `_egress = []` — the default SG genuinely has no rules. The default **NACL** is `manage_default_network_acl = true` but its allow-all rules are **kept**: every subnet in this VPC uses the default NACL (no dedicated NACLs are created), so blanking it would black-hole the entire VPC. This is phase-01 §1.6's explicit instruction and the checklist's own S-12 row concedes it. **Assessment: accept.** The real boundary here is security groups plus private-subnet routing, not the NACL layer. |
| S-13 | VPC endpoint SG allows 443 from the VPC CIDR only | `modules/network/main.tf` `aws_security_group.vpc_endpoints` | 📝 Implemented, not verified | Single ingress rule, `from_port`/`to_port` 443, `cidr_blocks = [var.vpc_cidr]`. No egress block — interface-endpoint ENIs only answer inbound and SGs are stateful. Only created when `enable_vpc_endpoints = true` (default `false`, S-C6). |
| S-14 | VPC flow logs on by default with defined retention | `modules/network/main.tf` | 📝 Implemented, not verified | All three flags set together (`enable_flow_log`, `create_flow_log_cloudwatch_log_group`, `create_flow_log_cloudwatch_iam_role`) — each silently no-ops without the others. Retention from `var.flow_log_retention_days`; `flow_log_max_aggregation_interval = 600` (60 costs ~10× more). |
| S-15 | No security group in the network module has `0.0.0.0/0` ingress | `modules/network/main.tf` | 📝 Implemented, not verified | `grep -n '0\.0\.0\.0/0' modules/network/main.tf \| grep -i ingress` → no output. Appendix A.4. |

## Phase 2 — Cluster

| ID | Requirement | Implemented in | Status | Evidence |
|---|---|---|---|---|
| S-20 | EKS access entries; legacy aws-auth path off | `modules/eks/main.tf` | 📝 Implemented, not verified | `authentication_mode = "API"`. A one-way door chosen at create time. Asserted live by `verify.sh` §B. |
| S-21 | Kubernetes API data envelope-encrypted with a CMK with rotation | `modules/eks/main.tf` | 📝 Implemented, not verified | `create_kms_key = true`, `encryption_config = { resources = ["secrets"] }`, plus `enable_kms_key_rotation = true` and `kms_key_deletion_window_in_days = 30` stated **explicitly** rather than inherited from module defaults (phase-02 review pass, deviation #10 — a future module major could change either default silently). `verify.sh` §B asserts the live `encryptionConfig` *and* `kms:GetKeyRotationStatus`. |
| S-29 | The one unrecoverable failure has an actual detector | `modules/eks/main.tf` `aws_cloudwatch_event_rule.kms_key_danger` → `aws_sns_topic.alerts` | 📝 Implemented, not verified | EventBridge rule on CloudTrail `DisableKey` / `ScheduleKeyDeletion` / `DisableKeyRotation` scoped to this cluster's key ID, targeting an SNS topic with an email subscription and a topic policy scoped to `events.amazonaws.com` with an `aws:SourceArn` condition on the rule. **Three prerequisites are unverifiable offline and all three can be silently dead**: CloudTrail must be enabled in the account; the email subscription must be *confirmed* (SNS returns the literal `PendingConfirmation` until someone clicks the link); and — closed by REVIEW.md F-04 — the topic's SNS-encryption key must actually be usable by EventBridge. The topic previously used `alias/aws/sns`, which cannot be edited to grant `events.amazonaws.com` access and made every publish fail silently at KMS; it now uses a dedicated `aws_kms_key.alerts` (rotation on, 30-day deletion window) whose policy grants `events.amazonaws.com` `kms:GenerateDataKey*`/`kms:Decrypt` with no `SourceArn` condition (unsupported for this delivery path per AWS's own compatibility docs). `verify.sh` §D2b asserts topic exists, subscription confirmed, CloudTrail present, rule ENABLED — REVIEW.md's WP-2 adds a fourth assertion there that the topic's key is a CMK ARN, never `alias/aws/sns`. |
| S-22 | All five control-plane log types with explicit retention | `modules/eks/main.tf` | 📝 Implemented, not verified | `enabled_log_types = var.cluster_enabled_log_types` (default: api, audit, authenticator, controllerManager, scheduler), `create_cloudwatch_log_group = true`, `cloudwatch_log_group_retention_in_days = var.cluster_log_retention_days`. `verify.sh` §B asserts each of the five individually rather than "logging is on". |
| S-23 | Public endpoint disabled, or restricted to an explicit allowlist | `modules/eks/main.tf`, guarded by S-04 | 📝 Implemented, not verified | `endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs`, whose validation rejects `0.0.0.0/0`; `cluster_endpoint_public_access_cidrs` defaults `[]` and a cross-validation requires it non-empty when public access is on. |
| S-24 | Managed node group volumes encrypted; IMDSv2 required, hop limit 1 | `modules/eks/main.tf` `eks_managed_node_groups.bootstrap` | 📝 Implemented, not verified | `block_device_mappings.xvda.ebs.encrypted = true`; `metadata_options = { http_tokens = "required", http_put_response_hop_limit = 1, http_endpoint = "enabled" }`. `verify.sh` §B asserts this on the **live instances**, which covers the bootstrap group and Karpenter nodes in one check. |
| S-25 | Workload AWS access uses Pod Identity, never static keys | `modules/eks/main.tf` addons; `modules/eks/iam.tf` | 📝 Implemented, not verified | `eks-pod-identity-agent` add-on declared; `aws-ebs-csi-driver` and `vpc-cni` each get a `pod_identity_association` pointing at a dedicated role whose trust policy grants **both** `sts:AssumeRole` and `sts:TagSession` (omitting `TagSession` lets the association create and then fails every credential fetch at runtime). |
| S-26 | Cluster admin granted only to the creating identity plus an explicit allowlist | `modules/eks/main.tf` | 📝 Implemented, not verified | `enable_cluster_creator_admin_permissions = true` (also the G-01 fix) plus one access entry per `var.cluster_admin_principal_arns` with `AmazonEKSClusterAdminPolicy` at cluster scope. |
| S-28 | Developers hold a purpose-built Role, not an AWS managed access policy | `modules/eks/main.tf` access entries; `modules/cluster-resources/chart/templates/namespaces.yaml` ClusterRole | 📝 Implemented, not verified | Developer access entries are `type = "STANDARD"` with `kubernetes_groups = [var.developer_rbac_group]` and **no `policy_associations` block at all**. Permissions come from a ClusterRole this stack owns, bound per-namespace by a RoleBinding. `AmazonEKSEditPolicy` is rejected because it grants full CRUD on `secrets`, `serviceaccounts: impersonate`, `daemonsets` and `pods/exec`. |
| S-28c | Developers cannot read secrets casually, impersonate a workload identity, or escalate via RBAC | `namespaces.yaml` ClusterRole rules | 📝 Implemented, not verified | The Role grants no verb on `secrets`, `serviceaccounts`, `roles` or `rolebindings` — confirmed by reading every rule; `ingresses` and `daemonsets` are absent too. `verify.sh` §D2 asserts this with `kubectl auth can-i --as-group`, in **both directions** (6 must-allow, 6 must-deny, plus cross-namespace and cluster-scoped). See Known limitations for what RBAC structurally cannot prevent. |
| S-28d | Cross-team credentials never share a namespace | `var.developer_namespaces` / `var.governed_namespaces` | 📝 Implemented, not verified | Paired list variables, one namespace per team. A dedicated namespace is a precondition for the first Pod Identity association, which is namespace-wide and keyed by ServiceAccount name. Default is a single `demo` namespace, so this is a *capability* the design supports rather than something the default configuration exercises. |
| S-28a | Access and guardrails created by the same apply, cannot drift apart | `modules/cluster-resources/main.tf` `lifecycle.precondition` | 📝 Implemented, not verified | Namespace, PSA labels, ResourceQuota and LimitRange are all Terraform-managed through one Helm release — not a manual `kubectl apply`. A `precondition` fails the **plan** if any non-wildcard `developer_namespaces` entry is missing from `governed_namespaces`, so Terraform refuses to grant access to an ungoverned namespace. `verify.sh` §D3 additionally asserts the live namespace carries a `meta.helm.sh/release-name` annotation, i.e. that it really is chart-owned. |
| S-28b | One developer cannot consume the cluster, bankrupt it, or expose it | `namespaces.yaml` ResourceQuota + LimitRange | 📝 Implemented, not verified | Quota covers compute (`requests`/`limits` cpu+memory), **storage** (`persistentvolumeclaims: 10`, `requests.storage: 200Gi`, per-StorageClass `gp3...requests.storage`), ephemeral storage, and object counts for every workload kind the Role grants (pods, deployments, statefulsets, replicasets, jobs, cronjobs, services) — not just deployments. LimitRange sets `min` (`cpu: 50m`, `memory: 64Mi`) as well as `defaultRequest`, which is what stops 50 anti-affine replicas at `cpu: 1m` forcing 50 unconsolidatable nodes. `services.loadbalancers` and `services.nodeports` both `"0"`. Rendered output in Appendix A.5. |
| S-27 | The **bootstrap** node role is held to the same bar as the Karpenter node role | `modules/eks/main.tf` `iam_role_attach_cni_policy = false` | ⚠️ **Deviation — one half implemented, one half not** | **Done:** `iam_role_attach_cni_policy = false`, with the VPC CNI given its own Pod Identity role instead (`modules/eks/iam.tf`). **Not done:** S-27 also asks for `AmazonEC2ContainerRegistryPullOnly` in place of `…ReadOnly`. Verified against the pinned source — `.terraform/modules/karpenter.karpenter/modules/eks-managed-node-group/main.tf:625` attaches `AmazonEC2ContainerRegistryReadOnly` **unconditionally**, inside a hardcoded map with no toggle. The only route is `create_iam_role = false` plus a hand-built role passed via `iam_role_arn`. Appendix A.6. **Assessment: accept for this POC, and record it.** The delta is `ecr:DescribeRepositories`/`ListImages`/`DescribeImages`-class read metadata beyond pull; it does not grant push or delete. The fix is cheap and well understood but means this stack taking full ownership of a third IAM role's policy surface — disproportionate for a POC, and the wrong trade to make silently. Note the *Karpenter* node role, which runs all workload capacity, already gets `PullOnly` (S-32). |

## Phase 3 — Karpenter IAM

| ID | Requirement | Implemented in | Status | Evidence |
|---|---|---|---|---|
| S-30 | Karpenter controller credentials come from Pod Identity | `modules/karpenter/main.tf` | 📝 Implemented, not verified | `create_pod_identity_association = true`, `namespace`/`service_account` set. v21's karpenter submodule is Pod-Identity-only — there is no OIDC path to disable. No IRSA, no static keys. |
| S-31 | `iam:PassRole` cannot be used to escalate | Upstream submodule `policy.tf` (v21.24.2), unmodified | 📝 Implemented, not verified | Scoped to the single node role ARN with `iam:PassedToService = ec2.amazonaws.com`. Enforced by the submodule's own policy; `modules/karpenter/main.tf` passes none of the escape-hatch variables (`iam_policy_statements`, `iam_role_policies`) that could widen it. |
| S-32 | Karpenter node role carries only the necessary policies, and **not** `AmazonEKS_CNI_Policy` | `modules/karpenter/main.tf` | 📝 Implemented, not verified | `node_iam_role_attach_cni_policy = false`; upstream attaches `AmazonEKSWorkerNodePolicy` + `AmazonEC2ContainerRegistryPullOnly` (confirmed at `.terraform/modules/karpenter.karpenter/modules/karpenter/main.tf:376-377`); `AmazonSSMManagedInstanceCore` added via `node_iam_role_additional_policies`. Appendix A.6. **Residual risk recorded below.** |
| S-33 | Interruption queue encrypted, writable only by the event services | `modules/karpenter/main.tf` | 📝 Implemented, not verified | `queue_managed_sse_enabled = true`, `enable_spot_termination = true`. The queue policy (upstream, unmodified) allows `SendMessage` only from `events.amazonaws.com` / `sqs.amazonaws.com` with an explicit deny when `aws:SecureTransport` is false. |
| S-34 | Exactly one node access entry, of the correct type | `modules/karpenter/main.tf` | 📝 Implemented, not verified | `create_access_entry = true`, `access_entry_type = "EC2_LINUX"`, and the submodule creates its own node role (no bring-your-own role, which is the real-world path to G-03). Under `authentication_mode = "API"` a node without this entry boots, fails to register, and is invisible in `kubectl get nodes` with no useful error. |

## Phase 4 — Karpenter deployment

| ID | Requirement | Implemented in | Status | Evidence |
|---|---|---|---|---|
| S-40 | Helm charts pinned to exact versions | `modules/karpenter/helm.tf` | 📝 Implemented, not verified | `version = var.karpenter_version` on **both** releases (default `1.14.0`); no floating constraint. |
| S-41 | No IRSA annotation on the service account | `modules/karpenter/helm.tf` | 📝 Implemented, not verified | The `set` list contains no `serviceAccount.*` key at all, so chart defaults apply and no `eks.amazonaws.com/role-arn` annotation is emitted. Confirmed by `grep -n 'eks.amazonaws.com/role-arn' helm.tf` → no output. |
| S-42 | Spot interruptions drain nodes rather than killing them | `modules/karpenter/helm.tf` | 📝 Implemented, not verified | `settings.interruptionQueue` set from the submodule's queue name. **The chart accepts its absence silently**, which disables all interruption handling — so `verify.sh` §C asserts the live `INTERRUPTION_QUEUE` env var is non-empty *and* matches Terraform's output, rather than trusting the manifest. |
| S-43 | Controller has resource requests and limits | `modules/karpenter/helm.tf` | 📝 Implemented, not verified | All four of `controller.resources.{requests,limits}.{cpu,memory}` set to `1` / `1Gi`. |
| S-44 | CRD security/validation fixes actually land on upgrade | `modules/karpenter/helm.tf` | 📝 Implemented, not verified | Separate `helm_release.karpenter_crd` (`karpenter-crd` chart) ordered before the controller release via `depends_on`, both with `wait = true`. CRDs in a chart's `crds/` directory are installed on first install only — `helm upgrade` never touches them (G-18). |

## Phase 5 — NodePools

| ID | Requirement | Implemented in | Status | Evidence |
|---|---|---|---|---|
| S-50 | Karpenter node root volumes encrypted | `chart/templates/ec2nodeclass.yaml` | 📝 Implemented, not verified | `blockDeviceMappings[0].ebs.encrypted: true`, **re-stated explicitly** because Karpenter's encrypted-by-default mapping applies only when the block is omitted entirely — the moment `volumeSize` is overridden the default is discarded. Rendered output in Appendix A.5. |
| S-51 | Containers cannot reach IMDS to steal node credentials | `chart/templates/ec2nodeclass.yaml` | 📝 Implemented, not verified | `metadataOptions: { httpTokens: required, httpPutResponseHopLimit: 1, httpProtocolIPv6: disabled }`. Rendered output in Appendix A.5. **Limitation:** `hostNetwork: true` pods reach IMDS regardless of hop limit — see Known limitations. |
| S-52 | A runaway workload cannot provision unbounded capacity | `chart/templates/nodepools.yaml` | 📝 Implemented, not verified | `spec.limits.cpu` **and** `spec.limits.memory` on every NodePool. `spec.limits` is per-NodePool, so `main.tf` divides `nodepool_cpu_limit` (100) and `nodepool_memory_limit_gi` (400) across the enabled pools — rendered as `cpu: "50"` / `memory: "200Gi"` each with both pools on, so the configured number is the true cluster ceiling. Appendix A.5. |
| S-53 | Consolidation cannot churn the whole fleet at once | `chart/templates/nodepools.yaml` | 📝 Implemented, not verified | `disruption.budgets: [{ nodes: "10%" }]` on both pools. Note this throttles **voluntary** disruption only — node expiration and Spot interruption are not rate-limited by it. |
| S-54 | Nodes are rotated so they stay patched | `chart/templates/nodepools.yaml` | 📝 Implemented, not verified | `expireAfter: 720h` on both pools. |
| S-55 | Resource selection cannot reach another cluster's infrastructure | `chart/templates/ec2nodeclass.yaml`; `modules/eks/main.tf` `node_security_group_tags` | 📝 Implemented, not verified | Subnet and security-group selectors both key on `karpenter.sh/discovery: <cluster name>`. The tag is set in exactly two places, both deriving from the same `local.name`. The "at most one SG in the account" condition is **account-wide state that no offline check can prove** — `verify.sh` §B asserts `describe-security-groups` returns exactly one and that it is the node SG from Terraform's output. |

## Phase 6 — Workload examples

| ID | Requirement | Implemented in | Status | Evidence |
|---|---|---|---|---|
| S-60 | Example manifests model good pod security | `examples/*.yaml` | 📝 Implemented, not verified | 5/5 manifests carry `runAsNonRoot: true`, `allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]` and `seccompProfile`; `readOnlyRootFilesystem: true` where the image supports it. Phase 6 verified the `nginx-unprivileged` + read-only-root combination empirically with `docker run --read-only --tmpfs /tmp -u 101 --cap-drop=ALL`. Appendix A.7. |
| S-61 | Every container has resource requests and limits | `examples/*.yaml` | 📝 Implemented, not verified | Every container has a `resources` block with requests and a memory limit. **CPU limits are deliberately omitted** — the namespace LimitRange defaults `cpu: "1"` onto every container at admission, so a CPU limit *is* enforced, just not authored in the manifest. Required for Karpenter to size nodes correctly. Appendix A.7. |
| S-62 | Images pinned by tag, pulled from public ECR | `examples/*.yaml` | 📝 Implemented, not verified | 0 non-`public.ecr.aws` images. Avoids Docker Hub rate limiting through a single NAT IP. Appendix A.7. |
| S-63 | No `hostPath`, no `hostNetwork`, no privileged containers | `examples/*.yaml` | 📝 Implemented, not verified | `grep -hE 'hostPath\|hostNetwork\|privileged: true'` across `examples/*.yaml` → 0 matches. Appendix A.7. |
| S-64 | Pod security **enforced by the API server and created by Terraform** | `chart/templates/namespaces.yaml` | 📝 Implemented, not verified | Every `governed_namespaces` entry gets `pod-security.kubernetes.io/enforce: restricted`, `enforce-version: latest`, plus `audit`/`warn`. In-tree Pod Security Admission — no controller, no cost. Terraform-managed, so a later apply restores the labels if stripped. `kube-system` is untouched and stays `privileged` (the CNI and Pod Identity agents require it). Rendered output in Appendix A.5. **`enforce-version` changed from the literal `v1.36` to `latest`** (REVIEW.md F-22): only that label carries a version at all, and a hardcoded literal would silently stop tracking `kubernetes_version` the moment it is bumped, with no error to say so. |

## Phase 7 — Documentation

| ID | Requirement | Implemented in | Status | Evidence |
|---|---|---|---|---|
| S-70 | Prerequisites describe least-privilege deployment credentials, not account root | `README.md` §Prerequisites | 📝 Implemented, not verified | Points at `docs/operator-runbook.md` §1.1 for the deploy principal; no instruction anywhere to use root. |
| S-71 | No real account IDs, IPs, ARNs or key material anywhere | `README.md` | 📝 Implemented, not verified | `grep -nE '[0-9]{12}'`, `grep -nE 'AKIA[0-9A-Z]{16}'`, and an IP grep excluding `203.0.113.` / `0.0.0.0` / `10.0.` all return empty. Placeholders use the RFC 5737 documentation range. Appendix A.8. |
| S-72 | The endpoint-CIDR guidance explains the control rather than just stating it | `README.md` §Configuration | 📝 Implemented, not verified | Gives the `/32` remedy **and** the rationale, added during the Phase 7 review pass when the first draft was found to give the remedy only. |
| S-73 | Known limitations stated honestly | `README.md` §Known limitations | 📝 Implemented, not verified | Covers the CMK availability risk, the `hostNetwork` IMDS bypass, `al2023@latest` drift, and — explicitly — that the stack has never been applied. That last one is restated at the top of this document. |

## Cost controls (Phase 0 / Phase 5)

| ID | Requirement | Implemented in | Status | Evidence |
|---|---|---|---|---|
| S-C1 | Spend is attributable | `locals.tf`; `chart/templates/ec2nodeclass.yaml` `spec.tags` | 📝 Implemented, not verified | `local.tags` (`Project`, `Environment`, `ManagedBy`, `Component` + `var.additional_tags`) on every module, **and** rendered into `EC2NodeClass.spec.tags` — because Karpenter calls `ec2:CreateFleet` itself, the provider's `default_tags` never reach Karpenter-launched instances, which are the entire variable cost of the cluster. Phase 5's review confirmed by rendering with a non-empty tag map that `Project`/`Environment`/`Component` reach the output and `ManagedBy: karpenter` wins the merge. **Closed by REVIEW.md F-27:** `bootstrap/`'s state bucket and KMS key — the longest-lived resources in the account — previously carried no tags at all despite this row's own claim of "every module"; `bootstrap/versions.tf`'s provider block now sets the same `default_tags`. |
| S-C2 | A forgotten cluster announces itself | `budget.tf` | 📝 Implemented, not verified | `aws_budgets_budget` filtered on the `Project` tag, alerting at 80% actual and 100% forecast; `enable_budget_alarm` defaults `true`, and `budget_notification_email` has a validation making it mandatory when the alarm is on. Phase 0 found and fixed a real defect here: the spec's own `"user:Project$${var.project_name}"` snippet renders *uninterpolated*, so the filter would have matched nothing — a cost control that looks present and is silently inert. Replaced with `format("user:Project$%s", var.project_name)`. **`aws_budgets_budget.account_backstop` is unaffected by the F-01 fix below and remains the day-zero guard** — it has no `cost_filter`, so it covers the whole account from the first apply regardless of whether cost-allocation tags are ever activated. The tag-filtered `monthly` budget and the two `aws_ce_cost_allocation_tag` resources it depends on are a separate, opt-in concern (`activate_cost_allocation_tags`, default `false` — REVIEW.md F-01): those resources were previously unconditional and failed the first apply on a fresh account (the tag key has no billing data yet) and permanently in an AWS Organizations member account (only the management account can manage cost-allocation tags). |
| S-C3 | Capacity has a hard ceiling | `chart/templates/nodepools.yaml` | 📝 Implemented, not verified | Same evidence as S-52 — `spec.limits` cpu and memory per NodePool, divided from the configured cluster total. |
| S-C4 | Idle capacity is reclaimed | `chart/templates/nodepools.yaml` | 📝 Implemented, not verified | `consolidationPolicy: WhenEmptyOrUnderutilized` with `consolidateAfter: 5m` (both required together — G-17). `verify.sh` §F asserts the cluster actually returns to **zero** Karpenter nodes after the demo workloads are removed, within a 10-minute timeout. That assertion is the only thing that would prove this; it has not been run. |
| S-C5 | Teardown is complete and verified | `scripts/teardown.sh` | 📝 Implemented, not verified | Deletes workloads and Service/Ingress load balancers, polls for the LBs to actually disappear, deletes NodeClaims **while the controller is still alive**, then queries EC2 on two Karpenter tags and **exits 1 rather than continuing** if anything survives. Only then `terraform destroy`. Sweeps EBS volumes and launch templates Terraform never knew about. Ordering assertion run and passing — Appendix A.9. Never executed against real infrastructure. |
| S-C6 | The largest line item is opt-in | `variables.tf` `enable_vpc_endpoints` | 📝 Implemented, not verified | Defaults `false` (~$263/month for 12 endpoints × 3 AZs — ADR-11). `tests/network_endpoints.tftest.hcl` proves both branches plan cleanly. |

## Phases 9–11 — Optional

| ID | Requirement | Implemented in | Status | Evidence |
|---|---|---|---|---|
| S-90 | Load balancer controller uses Pod Identity with the AWS-published policy, unmodified | — | ❌ **Not done** | Phase 9 was never requested or run. `var.enable_aws_load_balancer_controller` is declared but referenced nowhere. **Does it matter?** No for the assignment, which asks for EKS + Karpenter + dual-architecture scheduling. It matters the moment anyone creates an `Ingress` — and the `demo` namespace quota sets `services.loadbalancers: "0"`, so that cannot happen by accident. |
| S-91 | Ingresses default to internal scheme; internet-facing is explicit | — | ❌ **Not done** | Phase 9 not run. Moot while no ingress controller exists. |
| S-92 | metrics-server not exposed outside the cluster, read-only root filesystem | — | ❌ **Not done** | Phase 10 not run. `var.enable_metrics_server` is declared and wired as far as `modules/eks` but consumed by no resource. Consequence: no `kubectl top`, and no HPA. Does not affect Karpenter node autoscaling, which works from pending-pod resource requests, not metrics. |
| S-93 | CI runs `fmt`, `validate`, `tflint` and a policy scanner, failing on high-severity findings | — | ❌ **Not done** | Phase 11 not run. Partially mitigated: `make check` runs `fmt` + `validate` + `terraform test` + a `lint` target that invokes tflint/checkov when present. Nothing enforces it on a change — there is no CI. See the static-scan section below for what could and could not be run here. |
| S-94 | CI authenticates to AWS with OIDC federation, never long-lived keys | — | ❌ **Not done** | Phase 11 not run. No CI exists, so no credentials are configured anywhere — which is the safe end of this failure mode, but not the same as having implemented it. |

---

## Static security scan (§8.5)

Phase 11 was not run, so a one-off scan was attempted here. **Three of the four scanners are not
installed in this environment and nothing was installed to run them** — this is recorded as a gap,
not papered over.

| Tool | Result |
|---|---|
| `terraform fmt -check -recursive` | **Clean**, exit 0. |
| `terraform validate` (root and `bootstrap/`) | **Success**, both. |
| `terraform test` | **5 passed, 0 failed.** |
| `shellcheck scripts/*.sh` | **Clean**, exit 0 (see Appendix A.9 for the two suppressions and why each is a genuine false positive). |
| `checkov` | Not installed — **not run**. |
| `trivy config` | Not installed — **not run**. |
| `tflint` | Not installed — **not run**. |

There is deliberately **no triage table** below this: a triage table for scans that were never run
would be fabrication. The honest statement is that this stack has had no third-party policy scanner
pointed at it, and Phase 11 is where that gets fixed.

---

## Known limitations

These are design boundaries that were chosen, not defects that were missed. Each would need
addressing for a production, multi-tenant cluster.

**1. The CMK is a single point of unrecoverable failure.** The cluster's Kubernetes Secrets are
envelope-encrypted with a customer-managed key. Disabling that key degrades the cluster immediately;
allowing a scheduled deletion to complete makes it **unrecoverable** — there is no restore path.
This is the one failure in the design with no rollback, which is why it is the one thing with an
alarm (S-29). The alarm itself depends on CloudTrail being enabled and an SNS email subscription
being *confirmed*; both can be silently dead, and `verify.sh` §D2b exists specifically to catch that.
The baseline alternative — the AWS-owned key, which is on by default since Kubernetes 1.28 — trades
this availability risk away and takes controllable policy, rotation and audit with it.

**2. `hostNetwork: true` pods reach IMDS regardless of the hop limit.** S-51's
`httpPutResponseHopLimit: 1` stops a container reaching instance metadata *through the pod network
namespace*. A pod running with `hostNetwork: true` shares the node's namespace and is unaffected. It
is a strong control, not an absolute boundary. What actually holds the line is that Pod Security
Admission `restricted` forbids `hostNetwork` in every governed namespace, and the developer Role
grants no way to bypass admission. In `kube-system`, which stays `privileged` because the CNI and
Pod Identity agents require it, the control does not apply at all.

**3. `al2023@latest` drifts.** `var.node_ami_alias` defaults to `al2023@latest`, so Karpenter picks
up a new AMI whenever AWS publishes one. Combined with `expireAfter: 720h` this means nodes stay
patched automatically — which is the intent — but it also means the node image is **not
reproducible**: the same Terraform applied a month apart produces different nodes. For production,
pin a release tag (`al2023@v20260701`) and bump it deliberately.

**4. The developer boundary is the namespace, not the pod.** S-28c's stated limitation, restated
because it is the most commonly misunderstood part of this design: a developer holding `pods: create`
can read any Secret in their namespace by mounting it into a pod they own, and inherits any Pod
Identity association bound to that namespace. The Role also grants `pods/exec`, deliberately, which
lets them read any secret mounted into any pod there. **No RBAC rule prevents either** — this is a
property of Kubernetes, not a gap in the ClusterRole. The boundary that does hold is the namespace,
which is why S-28d pairs one namespace per team.

**5. No network policy — and "single-tenant" here means one company, not one workload.** Every pod
can reach every other pod, and all egress is unrestricted. The design's own developer model is 5–20
principals, so this is a real surface even without hostile workloads in scope.

**6. No GitOps, no observability stack, no cluster-upgrade automation.** There is no ArgoCD/Flux, no
Prometheus/Grafana, no log aggregation beyond the control-plane log groups, and no tested upgrade
runbook. See `00-architecture-and-decisions.md` §6. Also absent, each deliberately: runtime threat
detection (GuardDuty EKS Protection), an external policy engine (Kyverno/OPA), image scanning and
signing, a secrets manager integration, a private-only API endpoint, and automatic node repair.

**7. Nothing here has been executed.** The deepest limitation of this audit. Every "not verified"
row is a claim about code that has been read carefully and cross-checked against pinned upstream
source, but the first `terraform apply` will find things static analysis cannot. Phase 2's completion
report already flags three specifically: whether the taint/toleration matrix leaves the EBS CSI
controller Pending on the tainted bootstrap nodes, whether pod networking survives moving the CNI to
its own Pod Identity role, and whether CloudTrail is enabled in the target account.

### Residual risks the checklist requires recording

Two risks are stated as prose in `security-checklist.md` rather than as numbered rows, which is
exactly why they are easy to lose. Both are accepted, not mitigated:

**R1 — Instance tags are a control surface.** Karpenter keys off instance tags, so a principal with
`ec2:CreateTags` / `ec2:DeleteTags` on `i-*` can induce Karpenter to create or delete machines
without ever touching the cluster. Nothing in this stack constrains those actions. Constrain them in
any real environment.

**R2 — `AmazonSSMManagedInstanceCore` is broader than it looks.** It grants `ssm:GetParameter*` on
`Resource: "*"`, so anything that reaches node credentials can read **every unencrypted SSM
parameter in the account**. Accepted here because Session Manager is the only node access path and
there is no SSH key anywhere in the stack. Replace with a scoped inline policy in production. Note
this interacts with limitation 2: a `hostNetwork` pod in `kube-system` reaches IMDS, and therefore
reaches this.

---

## Appendix A — offline evidence

Commands run from `terraform/` on 2026-08-17. These prove code properties, not deployed state — see
the note at the top of this document on why they do not upgrade any row to ✅.

### A.1 · Secrets hygiene (S-02, S-00)

```console
$ for p in '*.tfvars' 'backend.hcl' '*.tfstate' '!*.tfvars.example'; do
    grep -qxF "$p" .gitignore && echo "  present: $p" || echo "  MISSING: $p"; done
  present: *.tfvars
  present: backend.hcl
  present: *.tfstate
  present: !*.tfvars.example

$ git ls-files | grep -E '\.tfvars$|^backend\.hcl$'
(no output — nothing sensitive is tracked)
```

### A.2 · Version pinning (S-03)

```console
$ git ls-files | grep -c 'terraform.lock.hcl'
2

$ grep -oE 'version = "[~>=0-9. ]+"' versions.tf
version = ">= 1.11.0"
version = "~> 6.58"     # aws
version = "~> 3.2"      # helm
version = "~> 4.3"      # tls
version = "~> 0.14"     # time
version = "~> 3.3"      # null
version = "~> 2.4"      # cloudinit

$ grep -rhoE 'version = "[0-9]+\.[0-9]+\.[0-9]+"' modules/*/main.tf | sort -u
version = "21.24.2"     # terraform-aws-modules/eks
version = "6.6.1"       # terraform-aws-modules/vpc
```

### A.3 · The endpoint guard actually fires (S-04)

```console
$ terraform test
tests/cidr_guard.tftest.hcl... in progress
  run "rejects_open_endpoint"...   pass
  run "rejects_empty_allowlist"... pass
  run "accepts_scoped_allowlist"... pass
tests/network_endpoints.tftest.hcl... in progress
  run "endpoints_off_plans_clean"... pass
  run "endpoints_on_plans_clean"...  pass

Success! 5 passed, 0 failed.
```

This is the only security control in the stack with an executing negative test — the two rejecting
runs prove the validation blocks the bad input, rather than merely existing.

### A.4 · No open ingress in the network module (S-15)

```console
$ grep -n '0\.0\.0\.0/0' modules/network/main.tf | grep -i ingress
(no output)
```

### A.5 · Rendered guardrails (S-28b, S-50, S-51, S-52, S-53, S-54, S-64)

```console
$ helm template ./chart --set clusterName=test --set nodeIamRoleName=test-role
...
    pod-security.kubernetes.io/enforce: restricted
    services.loadbalancers: "0"
    services.nodeports: "0"
        httpPutResponseHopLimit: 1
        httpTokens: required
          encrypted: true
        expireAfter: 720h
      consolidationPolicy: WhenEmptyOrUnderutilized
      consolidateAfter: 5m
        - nodes: "10%"
  limits:                    # per NodePool, both pools enabled
    cpu: "50"
    memory: "200Gi"

$ helm template ... | grep '^kind:' | sort | uniq -c
      1 kind: ClusterRole
      1 kind: EC2NodeClass
      1 kind: LimitRange
      1 kind: Namespace
      2 kind: NodePool
      1 kind: ResourceQuota
      1 kind: RoleBinding
      1 kind: StorageClass
```

### A.6 · The two node roles differ, and why (S-27, S-32)

Read from the pinned module source in `.terraform/modules/`, not from documentation:

```console
$ grep -n 'ContainerRegistry\|WorkerNodePolicy' \
    .terraform/modules/karpenter.karpenter/modules/karpenter/main.tf
376:      AmazonEKSWorkerNodePolicy          = ".../AmazonEKSWorkerNodePolicy"
377:      AmazonEC2ContainerRegistryPullOnly = ".../AmazonEC2ContainerRegistryPullOnly"

$ grep -n 'ContainerRegistry\|WorkerNodePolicy' \
    .terraform/modules/karpenter.karpenter/modules/eks-managed-node-group/main.tf
625:      AmazonEKSWorkerNodePolicy          = ".../AmazonEKSWorkerNodePolicy"
626:      AmazonEC2ContainerRegistryReadOnly = ".../AmazonEC2ContainerRegistryReadOnly"
```

Line 626 sits inside an unconditional `merge()` in `aws_iam_role_policy_attachment.this`'s
`for_each` — there is no variable that changes it. This is the whole of S-27's deviation.

### A.7 · Example manifest posture (S-60, S-61, S-62, S-63)

```console
$ grep -c 'runAsNonRoot: true' examples/*.yaml | awk -F: '{s+=$2} END{print s}'
5
$ grep -c 'allowPrivilegeEscalation: false' examples/*.yaml | awk -F: '{s+=$2} END{print s}'
5
$ grep -hE 'hostPath|hostNetwork|privileged: true' examples/*.yaml | grep -v '^\s*#' | wc -l
0
$ grep -h 'image:' examples/*.yaml | grep -vE '^\s*#' | grep -vc 'public.ecr.aws'
0
```

### A.8 · No leaked identifiers (S-71)

```console
$ grep -nE '[0-9]{12}' README.md
$ grep -nE 'AKIA[0-9A-Z]{16}' README.md
$ grep -nE '([0-9]{1,3}\.){3}[0-9]{1,3}' README.md | grep -vE '203\.0\.113|0\.0\.0\.0|10\.0\.'
(all three produce no output)
```

### A.9 · The teardown ordering assertion (S-C5)

The single assertion that matters most in this phase — NodeClaims must be deleted *before*
`terraform destroy`, or the G-09 deadlock is guaranteed:

```console
$ awk '/kubectl delete nodeclaims/{n=NR} /terraform destroy/{d=NR} END{
    if (n && d && n < d) printf "PASS: correct destroy ordering (nodeclaims line %d < destroy line %d)\n", n, d;
    else print "FAIL: ordering is wrong or a step is missing"}' scripts/teardown.sh
PASS: correct destroy ordering (nodeclaims line 124 < destroy line 172)

$ bash -n scripts/verify.sh && bash -n scripts/teardown.sh && echo OK
OK

$ shellcheck scripts/verify.sh scripts/teardown.sh && echo "shellcheck: CLEAN"
shellcheck: CLEAN
```

The four `# shellcheck disable=SC2016` directives in the two scripts are all on AWS CLI `--query`
arguments. JMESPath uses backticks for literals (`` [?enabled==`true`] ``); shellcheck reads them as
un-expanded command substitutions. Expanding them would break the queries — the suppression is
correct, and it is scoped to the individual statement rather than the file.

---

## Appendix B — what verification would actually look like

Every 📝 above becomes ✅ or a real finding by running, in order, with credentials for a target
account:

```bash
make bootstrap          # once per account: S3 + KMS state backend
cp backend.hcl.example backend.hcl   # fill from the bootstrap outputs
make init
make apply              # ~20 min

./scripts/verify.sh     # must exit 0 — this is the audit, executed
./scripts/teardown.sh   # must exit 0 and leave nothing behind
```

`verify.sh` asserts, in sections mapped to this document: cluster health (A); the configuration
claims in S-20 through S-24, S-55 and G-07's service-linked role (B); Karpenter's own health and
S-42's interruption queue (C); **both architectures actually scheduling**, which is the assignment's
real requirement (D); the S-28c RBAC boundary in both directions (D2); S-29's alarm being able to
fire at all (D2b); S-28a/S-28b/S-64's guardrails (D3); the S-C3 quota increases being *approved*
rather than merely requested (D4); Spot usage (E); and S-C4's consolidation to zero (F).

Until that has run, this document is a careful reading of the code — which is worth something, but
it is not the same thing, and the distinction is the point.
