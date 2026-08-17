# Post-delivery review — findings and remediation plan

**Reviewed:** commit `7c94db3` (2026-08-17), everything under `terraform/`, against
[`assessment.md`](assessment.md), the plan in [`README.md`](README.md) / phase docs, the
[interface contract](contracts/interface-contract.md), the
[security checklist](contracts/security-checklist.md), the team's own [`AUDIT.md`](AUDIT.md), and
mainstream Terraform / EKS / Karpenter practice. **Line numbers below are as of `7c94db3`.**

**Method.** Six independent read-only reviews (assignment & version freshness, Terraform practice,
security-vs-AUDIT, Karpenter/K8s config, first-apply blockers, docs/scripts drift), merged, then
every finding was checked by a second reviewer trying to refute it and a third judging whether the
fix stays inside the plan (for F-06, F-20 to F-24, F-26 and F-27 the refutation pass was done by the
review author directly against the sources cited). Version and AWS-behaviour claims were verified against primary sources
(AWS docs, provider source at the pinned `hashicorp/aws` 6.60.0, Karpenter v1.14.0 source, chart
values) — not from memory. Local gates re-run: `terraform fmt/validate/test`, `helm lint`,
`shellcheck`, plus **`tflint` and `trivy config`, which `AUDIT.md` §"Static security scan" records
as never run** (results in §7). No AWS credentials were used; nothing was applied.

**Headline.** The deliverable satisfies the assignment (R1–R8) and the plan is implemented as
described — pins are current, the security checklist rows are truthfully reported, and the static
gates are green. What the review found is **four apply-path / control defects** that static checks
cannot see and that a first real apply would hit, plus a set of small doc/script inaccuracies.
None require redesign; all fixes are one-file or one-line changes inside the existing plan.

| Severity | Count | IDs |
|---|---|---|
| High | 4 | F-01 CE-tag resource fails first apply · F-02 quota resource fails on non-fresh accounts · F-03 teardown "prove it" queries a tag Karpenter v1 no longer sets · F-04 KMS-danger alarm can never deliver (SNS on `alias/aws/sns`) |
| Medium | 3 | F-05 tfvars.example contradicts README · F-06 EBS-CSI policy ARN path unverifiable, may 404 · F-07 `tf.plan` not gitignored |
| Low | 20 | F-08 … F-27 (docs accuracy, script robustness, small hygiene) |

---

## 1. Assignment compliance (docs/assessment.md)

| # | Requirement | Verdict | Where |
|---|---|---|---|
| R1 | EKS on the latest available version | ✅ `kubernetes_version` default `1.36` is the newest EKS standard-support minor as of 2026-08-17 | `variables.tf:136` |
| R2 | New dedicated VPC | ✅ `terraform-aws-modules/vpc` 6.6.1 creates it; no existing-VPC lookup | `modules/network` |
| R3 | Karpenter deployed by the same Terraform | ✅ `karpenter-crd` + `karpenter` 1.14.0 Helm releases in the same root apply | `modules/karpenter/helm.tf` |
| R4 | NodePool(s) for x86 **and** arm64 | ✅ `amd64` and `arm64` NodePools, both on by default | `modules/cluster-resources/chart` |
| R5 | Graviton and Spot leveraged | ✅ `[spot, on-demand]` on both pools, arm64 weight 50 vs 10, bootstrap MNG on `t4g.medium` | same |
| R6 | Short README explaining repo usage | ⚠️ Present and correct, but 478 lines vs the phase's own 250–450 band (F-08) | `README.md` |
| R7 | Developer can run a pod on x86 or Graviton | ✅ `nodeSelector: kubernetes.io/arch`, both examples, arch-check Job | `README.md`, `examples/` |
| R8 | Everything under `terraform/` | ✅ | — |

Version freshness (primary sources, 2026-08-17): Karpenter latest = **v1.14.0** (pinned; K8s 1.36
requires ≥ 1.13 — supported pair); `terraform-aws-modules/eks` latest 21.25.0 vs pinned 21.24.2
(feature-only delta, not material); `vpc` 6.6.1 = latest; `hashicorp/aws` 6.60.0 = lockfile;
`hashicorp/helm` 3.2.0 = lockfile. Both OCI charts resolve at 1.14.0.

## 2. What checks out (so nobody re-audits it)

- All 61 `AUDIT.md` rows were opened against the cited file: every "Implemented in" claim matches
  the code, and every Appendix-A command reproduces. The two accepted deviations (S-12, S-27) are
  factually correct against the pinned upstream source.
- Every upstream module input used exists in the pinned `.terraform/modules` source (eks 21.24.2,
  its karpenter submodule, vpc 6.6.1). Contract §3/§4/§5 names match the code exactly (46/46
  variables, all outputs).
- `depends_on = [var.karpenter_helm_release_name]` is a real dependency edge (reproduced with
  `terraform graph`). No `count`/`for_each` derives from cluster state (ADR-6 holds).
- Karpenter v1 API usage is valid for 1.14.0 (field placement, requirement keys/operators, tag
  merge, `role` not `instanceProfile`); chart defaults tolerate `CriticalAddonsOnly`; the
  taint/toleration matrix on the tainted bootstrap nodes leaves nothing Pending (karpenter, coredns,
  ebs-csi controller + node DS, kube-proxy, aws-node, pod-identity-agent).
- Examples satisfy PSA `restricted`, sit inside the LimitRange/ResourceQuota, and use multi-arch
  images. Every `terraform output` read by `verify.sh`/`teardown.sh` exists. Makefile `demo`
  names match the manifests.
- S3 backend + bootstrap bucket policy: Terraform sets SSE-KMS on both the state object and the
  `use_lockfile` lock object, so `DenyUnencryptedObjectUploads` does not break init/locking.
- No `0.0.0.0/0` ingress, no keys, no real account IDs/IPs anywhere tracked.

---

## 3. Findings

Format: **what is wrong → why it matters → the minimal fix**. "Docs to sync" lists every place that
states the old behaviour, so the fix does not leave the docs contradicting the code.

### High

**F-01 · `aws_ce_cost_allocation_tag` (ungated) fails the first apply on a fresh account, and every apply in an AWS Organizations member account** — `budget.tf:79-87`
- Both resources are unconditional (every other budget resource is gated by `enable_budget_alarm`).
  In provider 6.60.0, `UpdateCostAllocationTagsStatus` errors for unknown keys are discarded and the
  post-create Read then fails with `empty result` when the tag key has never appeared in billing
  data — which takes up to 24 h after the first tagged resource exists, i.e. always on the README's
  `make bootstrap → make apply` path (bootstrap creates no `Project`/`Environment` tags). In an
  Organizations member account (Control Tower / sandbox), only the management account can manage
  cost-allocation tags → permanent `Linked account doesn't have access` failure. Terraform still
  creates the VPC/EKS/Karpenter, but `make apply` exits 1 with two tainted resources; converges only
  after 24 h in a standalone/management account, never in a member account. `phase-00` §0.7b
  ("do not document it as a manual step") and `operator-runbook.md:446` are wrong on this point;
  `interface-contract.md:136` already says the opposite.
- **Fix:** add `variable "activate_cost_allocation_tags" { type = bool; default = false }`
  (description: "Only works from a management or standalone account, and only after the
  `Project`/`Environment` tag keys have appeared in billing (~24 h after the first apply); otherwise
  activate in the Billing console or `aws ce update-cost-allocation-tags-status
  --cost-allocation-tags-status TagKey=Project,Status=Active TagKey=Environment,Status=Active`") and
  put `count = var.activate_cost_allocation_tags ? 1 : 0` on both resources. Keep
  `aws_budgets_budget.account_backstop` as the day-zero guard.
- **Docs to sync:** `budget.tf:74-78` header comment; `docs/operator-runbook.md:446-449`;
  `docs/phases/phase-00-scaffold-and-state.md:357-370`; new row in `interface-contract.md` §3;
  one line in `README.md` §Configuration; `AUDIT.md` S-C2 evidence.
- Sources: provider `internal/service/ce/cost_allocation_tag.go` @ v6.60.0; AWS
  `UpdateCostAllocationTagsStatus` API ref; AWS "Activating user-defined cost allocation tags";
  hashicorp/terraform-provider-aws issues #31442, #37636.

**F-02 · `aws_servicequotas_service_quota` (default `request_service_quotas = true`, value 128) errors on any account whose vCPU quota is already > 128 or has an open request — including accounts that followed the README's own "request an increase before the first apply"** — `quotas.tf:14-26`, `variables.tf:319-323`
- Provider 6.60.0 Create: `if value < current → error "requesting … with value less than current"`;
  a pending manual request → `ResourceAlreadyExistsException` (only Update swallows it); a denied or
  partially granted request → perpetual in-place diff that re-requests on every apply. The default
  works only for "current quota ≤ 128 and no request open". `variables.tf:320`,
  `interface-contract.md:197` and `docs/README.md:191` describe only the async-approval caveat.
- **Fix:** flip `default = false` (same precedent as `create_spot_service_linked_role`) and extend the
  description: "Opt-in. Set true only on a fresh account whose current quota is below
  `vcpu_quota_target` and with no open increase request; the resource errors if the quota is already
  higher or a request is pending, and a denied request leaves a perpetual diff. Otherwise raise the
  quota via console/Support and leave this false." No change to `quotas.tf`.
- **Docs to sync:** `README.md:76-79` (one sentence), `interface-contract.md:197`,
  `docs/README.md:191`, `docs/phases/phase-00-scaffold-and-state.md` §0.7c.
- Sources: provider `internal/service/servicequotas/service_quota.go` @ v6.60.0; Service Quotas
  `RequestServiceQuotaIncrease` API ref.

**F-03 · `teardown.sh` "prove it" step and the G-09 recovery recipe query `karpenter.sh/managed-by`, which Karpenter v1 no longer applies** — `scripts/teardown.sh:139-149`, `docs/reference/gotchas.md:178`, `docs/phases/phase-08-verification-teardown.md:261`
- Karpenter's v1 migration guide: `karpenter.sh/managed-by` "is replaced by `eks:eks-cluster-name`";
  v1.14.0 sets `Name`, `karpenter.sh/nodeclaim`, `karpenter.sh/nodepool`,
  `karpenter.k8s.aws/ec2nodeclass`, `kubernetes.io/cluster/<name>=owned`, `eks:eks-cluster-name`.
  (`modules/karpenter/main.tf:60` already conditions the controller policy on
  `eks:eks-cluster-name`.) So the only *cluster-scoped* query is always empty and the gate rests on
  `karpenter.sh/nodepool=*`, which is not cluster-scoped: in a region with any other Karpenter
  cluster the script aborts forever; and the manual G-09 recipe returns empty on any v1 cluster, so
  an operator concludes "nothing left" and runs `terraform destroy` with instances alive — the exact
  outcome G-09 exists to prevent. The "interrupted mid-launch" comment is also inaccurate.
- **Fix:** query with cluster-scoped, launch-time tags (filters are ANDed):
  `--filters "Name=tag:karpenter.sh/nodepool,Values=*" "Name=tag:eks:eks-cluster-name,Values=$CLUSTER" "Name=instance-state-name,Values=running,pending,stopping,stopped"`
  as the primary net and `"Name=tag:karpenter.sh/nodepool,Values=*" "Name=tag:kubernetes.io/cluster/$CLUSTER,Values=owned"`
  as the second (the `nodepool` AND keeps the bootstrap MNG out). Drop the mid-launch comment.
- **Docs to sync:** `gotchas.md:178`, `phase-08:261` (and prose ~565-566, ~670), `README.md:428`,
  `AUDIT.md:132` (S-C5) — name the tags actually queried.
- Sources: karpenter.sh v1 migration guide; karpenter-provider-aws v1.14.0 `pkg/utils/utils.go`.

**F-04 · S-29 KMS-key-danger alarm is silently dead: the SNS topic is encrypted with the AWS-managed `alias/aws/sns`, which EventBridge cannot use** — `modules/eks/main.tf:215-219`, target at `:272-276`
- AWS SNS docs ("Enable compatibility between event sources from AWS services and encrypted
  topics"): step 1 **"Use a customer managed key"**, step 2 grant `events.amazonaws.com`
  `kms:GenerateDataKey*`/`kms:Decrypt` in the key policy — and `aws:SourceArn`/`SourceAccount`
  conditions are *not* supported for EventBridge→SNS. The EventBridge troubleshooting guide
  ("My rule runs, but I don't see any messages published into my Amazon SNS topic", scenario 2) says
  the same. The `alias/aws/sns` key policy cannot be edited, so every publish fails at KMS and shows
  only as `FailedInvocations`. `AUDIT.md:61` and `verify.sh` §D2b (lines 415-449) check topic /
  subscription / trail / rule state — all would pass while the stack's "one detector" for its one
  unrecoverable failure is inert. `trivy` also flags this (AWS-0136).
- **Fix (recommended):** replace `kms_master_key_id = "alias/aws/sns"` with a small
  `aws_kms_key "alerts"` (`enable_key_rotation = true`, `deletion_window_in_days = 30`, ~$1/mo) whose
  policy = the account-root `kms:*` statement **plus** `Allow` / Principal `Service:
  events.amazonaws.com` / Actions `["kms:GenerateDataKey*", "kms:Decrypt"]` / Resource `"*"` with
  **no** SourceArn/SourceAccount condition; `kms_master_key_id = aws_kms_key.alerts.arn`.
  *Acceptable minimal alternative:* delete the `kms_master_key_id` line (the payload is a CloudTrail
  event about a key ID; the checklist has no SNS-encryption row) and say so in a comment.
- **Docs to sync:** `AUDIT.md:61` (S-29 evidence — add "topic key usable by EventBridge" as the
  third silent-failure prerequisite, now closed); `docs/phases/phase-02-eks-cluster.md:213`;
  add to `verify.sh` §D2b one assertion that `aws sns get-topic-attributes … Attributes.KmsMasterKeyId`
  is a CMK ARN (or empty), never `alias/aws/sns`.
- Sources: docs.aws.amazon.com/sns/latest/dg/sns-key-management.html#compatibility-with-aws-services;
  docs.aws.amazon.com/eventbridge/latest/userguide/eb-troubleshooting.html#eb-no-messages-published-sns.

### Medium

**F-05 · `terraform.tfvars.example` "cost-saver" block recommends `bootstrap_node_min_size = 1` (~$25/mo), contradicting the README, and the saving cannot occur; `alert_email` is missing from the example** — `terraform.tfvars.example:44` (and the `~$165/mo` total on `:40`)
- `README.md:324` and `:399-401` say "leave at 2" and rank this the #1 first-deploy trap;
  `README.md:88` tells the operator to copy this file. Lowering only `min_size` does not shrink the
  group (`desired_size` stays 2 and the module ignores later changes — G-06), so "~$25/mo" cannot
  materialise. `alert_email` (S-29 subscriber, silent when empty) is absent although
  `docs/README.md:196-197` lists it among the values to set.
- **Fix:** delete line 44 (or turn it into "leave at 2 — the Karpenter chart runs 2 replicas with a
  required podAntiAffinity, see README §Configuration / gotchas G-05"), recompute or drop the
  `~$165/mo` figure on line 40, add `alert_email = "you@example.com"` next to
  `budget_notification_email` labelled "strongly recommended" with the one-line S-29 rationale.
  In `docs/00-architecture-and-decisions.md:331` change the bootstrap row's toggle to "none — 2 nodes
  required by Karpenter podAntiAffinity (G-05)". See F-09 for the wording the README should then use.

**F-06 · `AmazonEBSCSIDriverPolicyV2` is attached by a hard-coded ARN path that AWS's own sources disagree on — the first apply may fail with `NoSuchEntity`** — `modules/eks/iam.tf:43`
- Code uses `arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicyV2` (as do the EKS user
  guide and the driver's `install.md`); the IAM-generated *AWS Managed Policy Reference* lists the
  policy as type "AWS managed policy" at `arn:aws:iam::aws:policy/AmazonEBSCSIDriverPolicyV2` (V1
  is the one under `service-role/`). Exactly one path exists; cannot be resolved offline. The
  phase-02 spec's own "verify the ARN before applying" note did not make it into the code.
- **Fix:** resolve by name — `data "aws_iam_policy" "ebs_csi" { name = "AmazonEBSCSIDriverPolicyV2" }`
  and `policy_arn = data.aws_iam_policy.ebs_csi.arn` — and add
  `mock_data "aws_iam_policy" { defaults = { arn = "arn:aws:iam::aws:policy/AmazonEBSCSIDriverPolicyV2" } }`
  to the `mock_provider "aws"` block in both `tests/*.tftest.hcl` so `terraform test` keeps passing.
  Record the actual ARN in the phase-02 completion report on the first live apply.
- Sources: docs.aws.amazon.com/aws-managed-policy/latest/reference/AmazonEBSCSIDriverPolicyV2.html
  vs docs.aws.amazon.com/eks/latest/userguide/csi-iam-role.html.

**F-07 · Makefile saves plans as `tf.plan` but `.gitignore` only ignores `*.tfplan`** — `Makefile:42,45,48,51,54`, `.gitignore:5`
- `git check-ignore tf.plan` → not ignored. A saved plan embeds every variable value, prior state and
  planned attributes (CA data, ARNs, emails, allowlist CIDRs). Every documented workflow leaves it in
  the repo root, one `git add .` from being committed — a hole in the S-02 claim.
- **Fix:** add `*.plan` (or `tf.plan`) to `.gitignore` next to `*.tfplan`; mention plan files in the
  `AUDIT.md:40` S-02 evidence.

### Low

**F-08 · README is 478 lines against the assignment's "short" and the phase's 250–450 band** — `README.md`
- `phase-07-readme.md:471` claims "474 lines, still inside the 250–450 band" (false). Surplus is
  duplication of linked docs: "Design decisions" bullets (`:367-382`, restates ADR §3), "Repository
  layout" tree (`:446-459`, restates contract §1, with "(Phase N)" leakage), the six-step Teardown
  list (`:420-434`, restates `teardown.sh` + G-09).
- **Fix:** delete-and-link those three (≈45 lines) → ≤ 450. Keep the verbatim example YAML (the
  phase spec requires a complete runnable example). Drop "Phase 6 ships" (`:123`) → "the repo ships".
  Correct `phase-07-readme.md:295-299, 471`.

**F-09 · README/G-05 claim that `min_size = 1` "deadlocks Karpenter, not just its HA" is wrong** — `README.md:324, 399-401`, `gotchas.md:78-79`, `phase-04:161-162`
- Karpenter runs leader election; the single Running replica provisions normally, the Pending
  second replica only removes HA. Chart 1.14.0 has `maxUnavailable: 1`, so `helm --wait` also
  succeeds with one node. The ADR's original "loses HA" (`00-architecture…:331`) was right; the
  README "correction" inverts it (and PDB `maxUnavailable: 1` then blocks draining that one node).
- **Fix:** reword to "second replica stays Pending — HA lost and rotating that single node stalls on
  the chart's PDB; the leader still autoscales. Leave at 2." in all four places; delete the README
  sentence calling the ADR framing outdated.

**F-10 · "Karpenter picks the cheapest one / across both NodePools" misdescribes weight-based selection** — `README.md:353-354`, `examples/README.md:42`
- For an unconstrained pod Karpenter takes the highest-weight compatible NodePool, then the cheapest
  instance type *within it*; there is no cross-pool price comparison.
  (`examples/deployment-multiarch.yaml:7-11` already says this correctly.)
- **Fix:** two one-line rewordings: "…takes the highest-weight NodePool the pod fits (arm64 by
  default), then picks the cheapest instance type in that pool…".

**F-11 · Runbook §1.2 (S-70) deploy-permission list omits services the stack calls at apply time, and points at a non-existent "Deliberately not done" entry** — `docs/operator-runbook.md:108-109, 124, 126-129`
- Missing: `sns:*` (topic/policy/subscription), `ce:UpdateCostAllocationTagsStatus` +
  `ce:ListCostAllocationTags`, `servicequotas:RequestServiceQuotaIncrease` +
  `GetRequestedServiceQuotaChange` (both conditional on their variables after F-01/F-02), and
  `iam:*OpenIDConnectProvider*` (the EKS module creates the IRSA OIDC provider by default). These
  are apply-time calls, so "run `terraform plan` and add what it complains about" cannot surface them.
  `:124` points to a permissions-boundary row that does not exist in `security-checklist.md`
  "Deliberately not done" (`:145-154`).
- **Fix:** add the services/actions to `:108-109` and `:127-129`, change the advice to "apply once in
  a scratch account", and add the "Permissions boundary on stack-created IAM roles" row to the
  checklist's "Deliberately not done" table (Why: sandbox POC; What it would take:
  `iam_role_permissions_boundary_arn` / `node_iam_role_permissions_boundary`).

**F-12 · `modules/network` `vpc_cidr` validation (`<= 20`) is looser than the root's invariant (`<= 18`), and its rationale is wrong** — `modules/network/variables.tf:7-13`, `modules/network/README.md:11`
- Root refuses /19–/20 because intra subnets become /28 (11 usable IPs, below AWS's ≥16
  recommendation); the module says "/20 so cidrsubnet cannot fail" — but `cidrsubnet(…,8,101)` only
  fails at /25, and the slice is /24 only for a /16. Anyone calling the module directly gets an
  under-sized subnet with no error. Already recorded as phase-01 deviation #3, but the recorded
  rationale is inaccurate.
- **Fix:** condition `<= 18`, description/error with the root's rationale, README line 11 → "/18",
  one-line note under phase-01 deviation #3.

**F-13 · The S-04 error message and README recommend `cluster_endpoint_public_access = false` without saying Terraform must then run from inside the VPC** — `variables.tf:170`, `README.md:320`
- The `helm` provider dials `module.eks.cluster_endpoint`; with the public endpoint off the three
  Helm releases time out ~20 min in, after the VPC/cluster/NAT are billing. The caveat exists only in
  `security-checklist.md:152` and `version-pinning.md:342`.
- **Fix:** append "(then run Terraform from inside the VPC — VPN or SSM bastion — the Helm releases
  need the private API endpoint)" to the error message and the README row.

**F-14 · S-62 "images pinned by tag" is not true of the manifests, and the phase-06 exception was never called out** — `AUDIT.md:111`, `examples/job-arch-check.yaml:22` (`busybox:latest`), four deployments + `README.md:182` (`nginx-unprivileged:stable`)
- `phase-06:361-362` said "the busybox job is the pragmatic exception; call it out" — nothing does.
  Appendix A.7 greps only the registry.
- **Fix (either):** pin to version tags verified on public ECR (`busybox:1.37`, `nginx-unprivileged`
  matching current `stable`, e.g. `1.30`/`1.31`) in the five manifests + README, or keep the tags and
  mark S-62 ⚠️ Deviation with the reason. Add `grep -hE 'image:.*:(latest|stable)$' examples/*.yaml`
  to Appendix A.7. No digests, no admission policy.

**F-15 · README's recommended POC tfvars (`cluster_enabled_log_types = ["audit"]`) make `verify.sh` fail S-22** — `README.md:337`, `terraform.tfvars.example:46`, `scripts/verify.sh:150-159`
- The check is right (S-22 asks for all five); the docs recommend the toggle without saying so, and
  there is no override in the `VERIFY_*` family.
- **Fix:** one sentence beside both POC snippets ("with audit-only logging `make verify` FAILs the
  S-22 check — expected"); optionally `VERIFY_EXPECT_LOG_TYPES` (default the five) in `verify.sh`.
  Do **not** downgrade the check to WARN.

**F-16 · Runbook says `make check` runs helm lint + kubeconform; the Makefile does not** — `docs/operator-runbook.md:39`, `Makefile:11, 22-25`
- Chart and manifest validity were the only static evidence for phases 5/6 and are not re-run by
  the documented one-shot gate.
- **Fix:** append to Makefile `lint`, same guard style:
  `@command -v helm >/dev/null && helm lint modules/cluster-resources/chart || echo "helm not installed, skipping"` and
  `@command -v kubeconform >/dev/null && kubeconform -strict -summary -kubernetes-version 1.36.0 examples/*.yaml || echo "kubeconform not installed, skipping"`;
  update the `## lint:` help line.

**F-17 · Runbook "state lost" recovery gives the wrong import address** — `docs/operator-runbook.md:517`
- The upstream module is wrapped: the address is `module.eks.module.eks.aws_eks_cluster.this[0]`.
- **Fix:** correct the command; note that `terraform state list` shows the double nesting.

**F-18 · Runbook stage-3 gate expects "5 CRDs" from `kubectl get crd | grep karpenter`; the 5th is `capacitybuffers.autoscaling.x-k8s.io`** — `docs/operator-runbook.md:310`
- **Fix:** `kubectl get crd | grep -E 'karpenter|capacitybuffer'   # 5 CRDs` (matches phase-04:228).

**F-19 · Stale forward references** — `modules/karpenter/README.md:112` ("verify.sh not yet written") and `:153-156` ("root README does not exist yet"); `Makefile:76` ("teardown.sh does not exist yet (it ships in Phase 8)"); `chart/templates/namespaces.yaml:39-40` + `phase-05:237` ("teardown.sh does not sweep EBS" — see F-24); `phase-07-readme.md:471` (false line count).
- **Fix:** one-line edits each; keep the `test -x` guard in the Makefile with a plain "missing or not
  executable" message.

**F-20 · `helm_release.karpenter` has no ordering edge to the controller's Pod Identity association** — `modules/karpenter/helm.tf:39-41`
- The only reference into `module.karpenter` is `queue_name`, so the release can start while the IAM
  role / association / node access entry are still being created. Pod Identity is injected at pod
  admission — pods created before the association exists never get credentials until recreated;
  with `wait = true` the first apply can then fail after 600 s and a retry masks the cause. Window is
  short (seconds); fix is free.
- **Fix:** `depends_on = [helm_release.karpenter_crd, module.karpenter]` plus a one-line comment.

**F-21 · Listing the deploying identity in `cluster_admin_principal_arns` (or the same principal in both lists) collides with the module's `cluster_creator` entry → `ResourceInUseException`** — `variables.tf:192-206`, `modules/eks/main.tf:36`
- EKS allows one access entry per principal and path-normalises IAM role ARNs; the natural
  "make my SSO role's admin access persistent" step after the first apply hits this. Also, map keys
  use `basename(arn)`, so two ARNs sharing a final segment collide at plan time.
- **Fix:** one sentence in both variable descriptions (mirror in `interface-contract.md:182-183` and
  gotchas G-01): "Do not include the identity that runs `terraform apply` — it already gets an entry
  via `enable_cluster_creator_admin_permissions`; do not list the same principal in both lists."
  Path-safe map keys are optional.

**F-22 · PSA `enforce-version` hard-coded to `v1.36` while `kubernetes_version` is a variable** — `chart/templates/namespaces.yaml:19`
- **Fix:** `pod-security.kubernetes.io/enforce-version: latest` (only that label carries a version);
  update the literal in `security-checklist.md:102`, `AUDIT.md:113`, `phase-05:217`.

**F-23 · `teardown.sh` drains NodeClaims but leaves NodePools alive until `terraform destroy`, so Karpenter can re-provision between the "zero instances" check and destroy** — `scripts/teardown.sh:124`
- Deleting NodePools first cascades to NodeClaims (owner refs), blocks new launches, and `--wait`
  returns only when the finalizer clears. Standard Karpenter uninstall order.
- **Fix:** before line 124 add `kubectl delete nodepools --all --wait=true --timeout=15m || true`
  (keep the nodeclaims delete as belt-and-braces); update the step-2 comment, `phase-08` §8.2 (~257)
  and gotchas G-09 (~173). Side note: `:89` hard-codes the `demo` namespace though
  `governed_namespaces` is a variable — optional to parametrise.

**F-24 · `teardown.sh` EBS "sweep" delete branch relies on a tag the CSI driver only sets when `--k8s-tag-cluster-id` is configured; README/AUDIT say "sweeps EBS", the chart comment says "does not sweep"** — `scripts/teardown.sh:180-183`, `README.md:431-432`, `AUDIT.md:132`, `chart/templates/namespaces.yaml:39-40`
- Per the driver's `tagging.md`, dynamically provisioned volumes get `CSIVolumeName` and
  `ebs.csi.aws.com/cluster=true` by default; `kubernetes.io/cluster/<id>=owned` only with
  `--k8s-tag-cluster-id`. Whether the EKS-managed add-on sets that flag by default is **not
  documented** — verify on the first live run
  (`kubectl -n kube-system get deploy ebs-csi-controller -o jsonpath='{.spec.template.spec.containers[0].args}'`).
  Not dangerous (step 1 deletes `demo` while the CSI controller is alive; gp3 SC is `Delete`), but
  three documents describe three behaviours and "Karpenter created" is wrong (PVC volumes are the CSI
  driver's).
- **Fix (wording, no code):** README step 5 → "launch templates Karpenter created outside Terraform
  state; orphaned CSI EBS volumes are listed for manual review"; AUDIT S-C5 likewise; namespaces.yaml
  comment → "teardown.sh only reports orphaned EBS volumes"; comment in `teardown.sh:180` that the
  delete branch matches only if the driver tags with `kubernetes.io/cluster/<name>`. If the live run
  shows the tag is absent, the real fix is `configuration_values = jsonencode({ controller = { extraVolumeTags = { "kubernetes.io/cluster/<name>" = "owned" } } })`
  on the add-on — a follow-up, not now.

**F-25 · Dead / misleading toggle inputs** — `variables.tf:392-402` (`enable_aws_load_balancer_controller` unused; `enable_metrics_server` wired but ignored), `modules/karpenter/variables.tf:21` (`node_security_group_id` unused) — `tflint terraform_unused_declarations` flags all three
- The declarations are per contract (signature stability for optional phases), but the root
  descriptions promise "Install the …", which setting `true` does not do.
- **Fix:** reword both descriptions to "Reserved for optional Phase 9/10 — not implemented; setting
  true has no effect" (mirror `interface-contract.md:209-210`). Optionally drop
  `node_security_group_id` from `modules/karpenter` + `main.tf:66` + contract §5.3.

**F-26 · Cheap guards missing** — `variables.tf:168-171` (allowlist validation only rejects `0.0.0.0/0`; `"203.0.113.10"` without `/32` passes and fails at the EKS API ~15 min in), `tests/*.tftest.hcl` (no negative test for the mandatory budget e-mail or the governed-namespaces precondition, both sold by AUDIT A.3 as "guards that fire")
- **Fix (optional, ~20 lines):** add `alltrue([for c in var.cluster_endpoint_public_access_cidrs : can(cidrnetmask(c))])`
  to the validation; add `run "rejects_missing_budget_email"` (`enable_budget_alarm = true`,
  `budget_notification_email = ""`, `expect_failures = [var.budget_notification_email]`) and
  `run "rejects_ungoverned_developer_namespace"` (`developer_namespaces = ["team-a"]`,
  `governed_namespaces = ["demo"]`, `expect_failures` on the `helm_release.cluster_resources`
  precondition — confirm the module-nested address form is accepted by `terraform test`).

**F-27 · `bootstrap/` resources are untagged (no `default_tags`, no `tags`), contradicting S-C1 "`local.tags` on every module"** — `bootstrap/versions.tf:13-15`, `bootstrap/main.tf`
- The state bucket and KMS key are the longest-lived resources in the account and invisible to the
  tag-filtered budget / Cost Explorer grouping.
- **Fix:** `default_tags { tags = { Project = var.project_name, Environment = var.environment, ManagedBy = "terraform", Component = "tfstate-backend" } }`
  in the bootstrap provider block; one line in `bootstrap/README.md`; adjust `AUDIT.md:128` S-C1.

**Noted, not filed:** `verify.sh:542` uses GNU `timeout` (absent on stock macOS) — add a
`command -v timeout` guard or note it if macOS operators are expected; the S-10 AUDIT phrase "both
resolve to subnets tagged karpenter.sh/discovery" is imprecise (the MNG uses `subnet_ids` directly)
but the outcome is identical; `version-pinning.md` says latest aws provider is 6.58.0 (it is 6.60.0).

---

## 4. Work packages and agent prompts

Three sequential packages, one branch/PR each, in this order (each is independent of the next, but
they touch some of the same files, so run them one at a time). Every prompt tells the agent to
edit only its listed files, keep fixes minimal, run `make check`, and fill in its completion report
in §8 of this file.

### WP-1 — Apply-path and control fixes (code)

Covers **F-01, F-02, F-04, F-06, F-07, F-12, F-13 (variables.tf part), F-20, F-21 (variables.tf part), F-22, F-25 (variables.tf part), F-26 (optional), F-27.**

Files allowed: `budget.tf`, `variables.tf`, `modules/eks/main.tf`, `modules/eks/iam.tf`,
`modules/karpenter/helm.tf`, `modules/karpenter/variables.tf` (+ `main.tf` only if dropping
`node_security_group_id`), `modules/network/variables.tf`, `modules/network/README.md`,
`modules/cluster-resources/chart/templates/namespaces.yaml`, `bootstrap/versions.tf`,
`bootstrap/README.md`, `.gitignore`, `tests/*.tftest.hcl`, `docs/contracts/interface-contract.md`
(§3 rows for variables you add/change), `docs/AUDIT.md` (only the S-02, S-29, S-C1, S-C2, S-64
evidence cells), the phase docs named in each finding, and §8 of this file.

```text
You are implementing WP-1 of terraform/docs/REVIEW.md (a post-delivery review of the EKS +
Karpenter POC). Work only under terraform/. Read, in this order: docs/REVIEW.md §3 (findings
F-01, F-02, F-04, F-06, F-07, F-12, F-13, F-20, F-21, F-22, F-25, F-26, F-27) and §4 WP-1;
docs/README.md "Rules that apply to every phase"; docs/contracts/interface-contract.md §3.

Implement exactly the "Fix" of each listed finding, minimal form — no refactors, no new
features, no new tooling. For F-04 use the recommended CMK variant (aws_kms_key with rotation,
30-day window, key policy = account-root kms:* + an UNCONDITIONED Allow for Service
events.amazonaws.com on kms:GenerateDataKey* and kms:Decrypt); for F-13/F-21/F-25 change only
the variables.tf text (error message / descriptions) — the README/runbook mirrors belong to
WP-3. For F-26 implement the validation change and the two negative tests only if they pass
under the mocked provider; if the module-nested expect_failures address is rejected by
terraform test, drop that one test and say so. Touch only the files listed under WP-1 "Files
allowed"; if a fix seems to need another file, note it in the completion report instead.

Where a finding lists "Docs to sync", update those specific lines so no doc states the old
behaviour (interface-contract §3 rows for any variable you add or whose default you change;
the named AUDIT.md evidence cells; the named phase-doc lines).

Acceptance (all must pass, paste the output in the report):
  terraform fmt -check -recursive
  terraform init -backend=false && terraform validate
  terraform -chdir=bootstrap init -backend=false && terraform -chdir=bootstrap validate
  terraform test                       # 5 passed before; 5-7 after depending on F-26
  helm lint modules/cluster-resources/chart
  git check-ignore -q tf.plan && echo IGNORED
  grep -n 'kms_master_key_id' modules/eks/main.tf    # must reference aws_kms_key.alerts, not alias/aws/sns
  grep -n 'depends_on' modules/karpenter/helm.tf     # must include module.karpenter
  grep -n 'enforce-version' modules/cluster-resources/chart/templates/namespaces.yaml  # latest
  grep -n 'activate_cost_allocation_tags\|request_service_quotas' variables.tf budget.tf

Then fill in the WP-1 completion report in docs/REVIEW.md §8 (files changed, each finding's
status, deviations, anything you could not do) and STOP. Do not start WP-2 or WP-3. Do not run
terraform plan/apply against AWS.
```

### WP-2 — Teardown / verify scripts and Makefile

Covers **F-03, F-15, F-16, F-19 (Makefile line), F-23, F-24 (script comment + docs), and the
`verify.sh` assertion from F-04.**

Files allowed: `scripts/teardown.sh`, `scripts/verify.sh`, `Makefile`, `docs/reference/gotchas.md`
(G-09 block), `docs/phases/phase-08-verification-teardown.md` (the lines named in F-03/F-23),
`README.md` (only lines 420-434, the teardown step list — and only if WP-3 has not run yet;
otherwise leave README to WP-3), `docs/AUDIT.md` (S-C5 and S-22 evidence cells, S-29 verify note),
`modules/cluster-resources/chart/templates/namespaces.yaml:39-40` and
`docs/phases/phase-05-nodepools.md:237` (F-24 comment), and §8 of this file.

```text
You are implementing WP-2 of terraform/docs/REVIEW.md. Work only under terraform/. Read
docs/REVIEW.md §3 (F-03, F-04 verify.sh note, F-15, F-16, F-19, F-23, F-24) and §4 WP-2, then
docs/reference/gotchas.md G-09 and docs/phases/phase-08-verification-teardown.md §8.2.

Implement each fix minimally:
- F-03: replace the two EC2 queries in scripts/teardown.sh with the cluster-scoped, launch-time
  tag filters given in the finding (nodepool=* AND eks:eks-cluster-name=$CLUSTER; second net
  nodepool=* AND kubernetes.io/cluster/$CLUSTER=owned); delete the "interrupted mid-launch"
  comment; apply the same filter to gotchas.md G-09 and phase-08 §8.2/§8.5; make README:428 and
  AUDIT S-C5 name the tags actually queried.
- F-23: add `kubectl delete nodepools --all --wait=true --timeout=15m || true` before the
  nodeclaims delete; update the step-2 comment, phase-08 §8.2 and G-09.
- F-24: comment on the EBS delete branch that it only matches when the CSI driver tags with
  kubernetes.io/cluster/<name>; reword README step 5, AUDIT S-C5 and the namespaces.yaml /
  phase-05 comment as specified. Do NOT add add-on configuration_values.
- F-04 (verify side): in verify.sh §D2b assert `aws sns get-topic-attributes --query
  Attributes.KmsMasterKeyId` is empty or a CMK ARN, never alias/aws/sns.
- F-15: add VERIFY_EXPECT_LOG_TYPES (default "api audit authenticator controllerManager
  scheduler") to verify.sh's env-override list and loop over it; do not weaken the check.
- F-16: append the guarded helm lint and kubeconform lines to Makefile `lint`; update `## lint:`.
- F-19 (Makefile): keep the `test -x` guard in `destroy`, message → "scripts/teardown.sh is
  missing or not executable".
- Optional: guard the GNU `timeout` use in verify.sh:542 with `command -v timeout`.

Acceptance (paste output):
  bash -n scripts/verify.sh && bash -n scripts/teardown.sh && shellcheck scripts/*.sh
  awk '/kubectl delete nodepools/{p=NR} /kubectl delete nodeclaims/{n=NR} /terraform destroy/{d=NR} END{ if(p&&n&&d&&p<n&&n<d) print "PASS ordering"; else print "FAIL ordering"}' scripts/teardown.sh
  grep -c 'karpenter.sh/managed-by' scripts/teardown.sh docs/reference/gotchas.md   # 0 (except an explanatory note)
  make lint   # must run helm lint (helm is installed) and skip kubeconform gracefully if absent
  make check

Fill in the WP-2 completion report in docs/REVIEW.md §8 and STOP. Do not run against AWS.
```

### WP-3 — Documentation accuracy

Covers **F-05, F-08, F-09, F-10, F-11, F-13 (README), F-14, F-17, F-18, F-19 (READMEs / phase-07),
F-21 (contract + G-01), F-25 (contract), plus §7 of this file into `AUDIT.md`.**

Files allowed: `README.md`, `terraform.tfvars.example`, `examples/README.md`, `examples/*.yaml`
(only the `image:` lines, F-14 option 1), `modules/karpenter/README.md`, `docs/operator-runbook.md`,
`docs/00-architecture-and-decisions.md` (§5 bootstrap row), `docs/AUDIT.md` (S-62, static-scan
section, Known limitations if needed), `docs/contracts/security-checklist.md` ("Deliberately not
done" row for F-11), `docs/contracts/interface-contract.md` (rows named in F-21/F-25),
`docs/reference/gotchas.md` (G-01, G-05), `docs/phases/phase-04-karpenter-helm.md:161-162`,
`docs/phases/phase-07-readme.md` (completion-report lines), and §8 of this file.

```text
You are implementing WP-3 of terraform/docs/REVIEW.md. Work only under terraform/. Read
docs/REVIEW.md §3 (F-05, F-08, F-09, F-10, F-11, F-13, F-14, F-17, F-18, F-19, F-21, F-25), §4
WP-3 and §7, then docs/phases/phase-07-readme.md (Specification and Completion report).

Apply each fix as worded in the finding — these are text edits; do not change any .tf or
script (WP-1/WP-2 own those). Specific rules:
- F-08: trim README.md to <= 450 lines ONLY by delete-and-link of the three duplicated
  sections named in the finding; keep the verbatim examples/deployment-arm64.yaml embed; keep
  every command; drop "Phase N" annotations from user-facing prose. Then correct
  phase-07-readme.md:295-299 and :471 to the true final count.
- F-09: reword README:324 and :399-401, gotchas G-05, phase-04 §4.4 as given; leave the ADR
  cost-table row as it is and delete the README sentence calling it outdated.
- F-05: fix terraform.tfvars.example (drop/replace line 44, recompute or drop the ~$165 total,
  add alert_email as strongly recommended) and the ADR §5 bootstrap row.
- F-14: prefer option 1 (pin `image:` tags to version tags you verify exist on public ECR and
  are multi-arch: busybox 1.37; nginx-unprivileged matching current `stable`), and update
  README:182 to match; add the `:latest|:stable` grep to AUDIT Appendix A.7. If you cannot
  verify tags, do option 2 (AUDIT S-62 → ⚠️ Deviation with the reason).
- F-11, F-13, F-17, F-18, F-19, F-21, F-25: exactly the line edits given.
- §7: replace the "Not installed — not run" rows in AUDIT.md "Static security scan" with the
  tflint and trivy results and the triage table from REVIEW.md §7 (say the tools were run
  locally on 2026-08-17 during the review, versions given there).

Acceptance (paste output):
  wc -l README.md                                  # <= 450
  make check
  grep -n 'deadlocks Karpenter' README.md          # no output
  grep -n 'grep karpenter ' docs/operator-runbook.md   # no bare grep left at :310
  grep -n 'module.eks.aws_eks_cluster' docs/operator-runbook.md   # no output
  grep -hE 'image:' examples/*.yaml                # version tags, or S-62 marked Deviation
  bash -c 'for f in $(grep -oE "\]\((docs|examples|modules|scripts)/[^)#]+" README.md | cut -c3-); do test -e "$f" || echo "BROKEN LINK $f"; done'

Fill in the WP-3 completion report in docs/REVIEW.md §8 and STOP.
```

---

## 5. How to apply this review

1. **Do not fix anything by hand from the summary** — hand each package to an agent with the prompt
   above; the prompts carry the scope boundary and the acceptance commands.
2. `git checkout -b review-01-apply-path` → paste the WP-1 prompt into a fresh session → when it
   stops, read its completion report in §8, run `make check` yourself, review the diff, open the PR
   as you did for the phases, merge.
3. Repeat for `review-02-scripts` (WP-2) and `review-03-docs` (WP-3), **in that order** — WP-2 and
   WP-3 both touch `README.md`/`AUDIT.md`, and WP-3's README trim assumes WP-2's teardown wording is
   already in place.
4. After WP-3, re-run the two scanners once (§7 has the commands; both are single static binaries
   from their GitHub release pages — `tflint` needs `tflint --init` once for the AWS ruleset) so
   `AUDIT.md`'s scan section is backed by a run against the fixed tree; the expected residue is the
   by-design list in §7. `make lint` will pick `tflint` up automatically if it is on `PATH`.
5. Then, and only then, the first live apply — use `AUDIT.md` Appendix B, plus the checklist in §6,
   which lists what these findings could not settle offline.

What **not** to do, per the assessment scope: no CI pipeline (Phase 11 stays optional — `make check`
+ the two scanner commands are enough for the deliverable), no ingress controller / metrics-server,
no network policy, no multi-account. Nothing in this review needs any of them.

## 6. First live apply — checklist added by this review

Run after `make apply` succeeds, before `./scripts/verify.sh`; each item resolves an
"unverifiable offline" question above. Record the answers in the relevant phase completion report.

| # | Check | Command | Resolves |
|---|---|---|---|
| L1 | Which `AmazonEBSCSIDriverPolicyV2` ARN exists | `aws iam get-policy --policy-arn arn:aws:iam::aws:policy/AmazonEBSCSIDriverPolicyV2` and the `service-role/` form | F-06 (then optionally revert to a literal) |
| L2 | EBS CSI add-on args include `--k8s-tag-cluster-id` | `kubectl -n kube-system get deploy ebs-csi-controller -o jsonpath='{.spec.template.spec.containers[0].args}'` | F-24 — if absent, the teardown EBS delete branch is inert; consider `extraVolumeTags` |
| L3 | Karpenter pods received Pod Identity credentials on first start (no restart) | `kubectl -n kube-system get pods -l app.kubernetes.io/name=karpenter -o jsonpath='{.items[*].status.containerStatuses[*].restartCount}'` → all `0` | F-20 |
| L4 | KMS-danger alarm actually delivers | after confirming the SNS subscription: `aws events put-events` with a synthetic `aws.kms` `DisableKey` detail for the cluster key **or** watch `AWS/Events FailedInvocations` for the rule = 0 after a real `DisableKeyRotation` + re-enable on a scratch key | F-04 |
| L5 | Cost-allocation tags | ≥ 24 h after apply, from a management/standalone account: set `activate_cost_allocation_tags = true` and apply; in a member account, do it in the payer's Billing console | F-01 |
| L6 | Quota state | `aws service-quotas get-service-quota --service-code ec2 --quota-code L-1216C47A` (and `L-34B43A08`) ≥ 128 before enabling `request_service_quotas` | F-02 |
| L7 | Teardown gate sees the nodes | with the demo workloads running: `aws ec2 describe-instances --filters "Name=tag:karpenter.sh/nodepool,Values=*" "Name=tag:eks:eks-cluster-name,Values=<cluster>" --query 'Reservations[].Instances[].InstanceId'` → non-empty | F-03 |
| L8 | Access-entry duplicate rule | do **not** add the deploying principal to `cluster_admin_principal_arns`; add a second, distinct role and confirm apply succeeds | F-21 |

## 7. Static scan results (run 2026-08-17 during this review; `AUDIT.md` said "not installed — not run")

Commands (binaries downloaded to a scratch dir, nothing installed system-wide):

```bash
# tflint 0.64.0 (ruleset.terraform 0.15.0 bundled) + tflint-ruleset-aws 0.44.0
tflint --init && tflint --recursive --format compact
# trivy 0.74.0
trivy config --severity HIGH,CRITICAL,MEDIUM,LOW --skip-dirs .terraform --skip-dirs docs .
```

**tflint:** 3 warnings, all `terraform_unused_declarations` — `variables.tf:392`
`enable_aws_load_balancer_controller`, `modules/eks/variables.tf:118` `enable_metrics_server`,
`modules/karpenter/variables.tf:21` `node_security_group_id` (= F-25). No errors.

**trivy config:** 38 misconfigurations. Triage:

| ID | Where | Verdict |
|---|---|---|
| AWS-0136 SNS topic not encrypted with CMK | `modules/eks/main.tf:217` | **Real — F-04** (and the AWS-managed key is what breaks delivery) |
| AWS-0040 / AWS-0041 public EKS endpoint / open CIDR | upstream `eks` module source | By design: public endpoint is CIDR-restricted; `0.0.0.0/0` rejected by S-04 (trivy cannot see tfvars); an operator may set `cluster_endpoint_public_access = false` (see F-13) |
| AWS-0104 node SG unrestricted egress | upstream `eks` module `node_groups.tf` | Accepted for a POC — nodes need NAT egress for image pulls; would need VPC endpoints + egress rules to tighten (Known limitations 5) |
| AWS-0342 `iam:PassRole` | upstream Karpenter policy | Scoped to the node role with `iam:PassedToService = ec2.amazonaws.com` (S-31) |
| AWS-0089 S3 bucket logging | `bootstrap/main.tf:31` | Deliberate: no self-logging of the state bucket (comment in file) |
| KSV-0118 pod-level `securityContext` missing (5) | `examples/*.yaml` | Container-level context satisfies PSA `restricted`; optionally add pod-level `runAsNonRoot`/`seccompProfile` for tidiness — not required |
| KSV-0014 job root FS not read-only | `examples/job-arch-check.yaml` | Disposable diagnostic; acceptable |
| KSV-0013 `:latest` tag | `examples/job-arch-check.yaml:22` | **F-14** |
| KSV-0125 "untrusted registry" (5) | `public.ecr.aws` | By design (S-62 chose public ECR to avoid Docker Hub rate limits) |
| KSV-0053 `pods/exec`, KSV-0056 services, KSV-0048/0049 workloads/configmaps | developer ClusterRole | Deliberate, documented boundary (S-28c, Known limitations 4) |
| KSV-0011 no CPU limit (5) | `examples/*.yaml` | Deliberate: LimitRange injects `cpu: 1` (S-61) |
| KSV-0020/0021 UID/GID ≤ 10000 (9) | `examples/*.yaml` | `nginx-unprivileged` runs as uid 101; acceptable |

`checkov` was not run (needs `python3-venv`, not installed here); it overlaps trivy's ruleset for
this stack.

## 8. Completion reports

*(Filled in by the implementing agents. One block per work package: files changed; per-finding
status — done / done differently (why) / not done (why); acceptance output; anything found on the
way that belongs to another package.)*

### WP-1

**Status: DONE.** All 13 findings covered by WP-1 addressed — 12 as their stated fix, one (F-26's
second negative test) partially: the validation change and the first negative test both landed; the
second negative test was attempted exactly as specified and dropped per the prompt's own
contingency, with the reason recorded in the test file. Acceptance criteria all pass, pasted below.

**Files changed:** `budget.tf`, `variables.tf`, `modules/eks/main.tf`, `modules/eks/iam.tf`,
`modules/karpenter/helm.tf`, `modules/network/variables.tf`, `modules/network/README.md`,
`modules/cluster-resources/chart/templates/namespaces.yaml`, `bootstrap/versions.tf`,
`bootstrap/README.md`, `.gitignore`, `tests/cidr_guard.tftest.hcl`,
`tests/network_endpoints.tftest.hcl`, `tests/governed_namespaces.tftest.hcl` (**new**),
`docs/contracts/interface-contract.md`, `docs/AUDIT.md` (only the S-02, S-29, S-C1, S-C2, S-64
cells), `docs/phases/phase-00-scaffold-and-state.md`, `docs/phases/phase-01-networking.md`,
`docs/phases/phase-02-eks-cluster.md`, `docs/phases/phase-05-nodepools.md`. `modules/karpenter/
variables.tf` and root `main.tf` were **not** touched — see F-25 below.

**Per-finding status:**

| # | Status | Notes |
|---|---|---|
| F-01 | Done | `activate_cost_allocation_tags` (default `false`), `count`-gates both `aws_ce_cost_allocation_tag` resources. `aws_budgets_budget.account_backstop` untouched — it has no `cost_filter` and remains the day-zero guard regardless of this toggle. |
| F-02 | Done | `request_service_quotas` default flipped `true` → `false`, description extended with the exact failure modes. `quotas.tf` unchanged — already correctly `count`-gated on the variable. |
| F-04 | Done | Added `data.aws_caller_identity.current`, `data.aws_iam_policy_document.alerts_key` (account-root `kms:*` + unconditioned `events.amazonaws.com` `GenerateDataKey*`/`Decrypt`, no SourceArn — per the finding's explicit instruction that such a condition is unsupported for this path), `aws_kms_key.alerts` (rotation on, 30-day window), `aws_kms_alias.alerts`. `aws_sns_topic.alerts.kms_master_key_id` now points at it. |
| F-06 | Done | `data "aws_iam_policy" "ebs_csi" { name = "AmazonEBSCSIDriverPolicyV2" }` resolves the ARN by name; `aws_iam_role_policy_attachment.ebs_csi` reads `data.aws_iam_policy.ebs_csi.arn`. Added `mock_data "aws_iam_policy"` to all three `mock_provider "aws"` blocks (the two pre-existing test files plus the new one) — `terraform test` needed it the moment `module.eks` entered any plan. |
| F-07 | Done | `*.plan` added to `.gitignore`; `git check-ignore -q tf.plan` → IGNORED. AUDIT S-02 evidence updated. |
| F-12 | Done | Module's own `vpc_cidr` validation tightened `/20` → `/18`, matching the root's invariant exactly. Corrected the phase-01 deviation #3 text, which had claimed the `/20` bound was safe reasoning ("cidrsubnet cannot fail") that does not actually hold at `/20` — recorded the correction rather than silently rewriting the original claim. |
| F-13 (variables.tf part) | Done | Appended the "run Terraform from inside the VPC" caveat to the S-04 validation's own `error_message`, so it surfaces at the point of failure rather than only in a doc a reader may not open. The README row is WP-3's. |
| F-20 | Done | `depends_on = [helm_release.karpenter_crd, module.karpenter]`. Verified as a REAL edge, not just a string that parses: rendered `terraform graph` from a throwaway local-backend override (deleted after, no state committed) and confirmed `module.karpenter.helm_release.karpenter` now depends directly on `aws_eks_pod_identity_association.karpenter`, `aws_eks_access_entry.node`, and every IAM resource in the submodule — output pasted below. |
| F-21 (variables.tf part) | Done | Added the "do not include the deploying identity; do not list the same principal in both lists" sentence to both `cluster_admin_principal_arns` and `developer_principal_arns` descriptions. The `interface-contract.md`/gotchas G-01 mirrors are WP-3's. |
| F-22 | Done | `enforce-version: v1.36` → `latest` in the chart template; mirrored in `phase-05-nodepools.md`'s embedded YAML and in AUDIT S-64's evidence. **`security-checklist.md:102` was NOT touched** — it is not in WP-1's "Files allowed" list, and no WP explicitly covers it either (a gap in the review's own package boundaries, flagged below for whoever runs WP-3 or a follow-up). |
| F-25 (variables.tf part) | Done, optional half declined | Reworded both descriptions to "Reserved for optional Phase N — not implemented; setting true has no effect." **Did not** drop `node_security_group_id` from `modules/karpenter` — that half was explicitly optional, and doing it correctly touches root `main.tf:66` and `interface-contract.md` §5.3, neither of which is in WP-1's allowed-files list for this finding; the minimal, in-scope fix (the description reword) fully addresses the "promises to install something it doesn't" problem the finding actually raises. |
| F-26 | Done, second test dropped as instructed | Added the `cidrnetmask` validation as a **second** `validation` block (Terraform ≥1.9 allows multiple blocks per variable; `required_version >= 1.11.0` already exceeds that). `run "rejects_bare_ip_without_mask"` and `run "rejects_missing_budget_email"` both pass. `run "rejects_ungoverned_developer_namespace"` — the module-nested precondition test — was rejected by `terraform test` itself: `Error: Invalid 'expect_failures' reference … You cannot expect failures from module.cluster_resources.helm_release.` Per the prompt's own contingency, dropped that run and recorded why in `tests/governed_namespaces.tftest.hcl`'s header comment, including a from-scratch confirmation (a throwaway, uncommitted `command = plan` run with no `expect_failures`) that the precondition itself still fires — full error text quoted there. What ships is one positive regression test (`accepts_paired_default_namespaces`) isolating a plan through `module.cluster_resources`. |
| F-27 | Done | `bootstrap/versions.tf`'s `provider "aws"` block now sets `default_tags` (`Project`, `Environment`, `ManagedBy`, `Component = tfstate-backend`), reusing the existing `var.project_name`/`var.environment`. One-line note in `bootstrap/README.md`; AUDIT S-C1 evidence updated. |

**Deviations from the WP-1 prompt:**

1. **F-22's `security-checklist.md:102` sync has no owner across any work package.** The finding's
   own "Docs to sync" names `security-checklist.md:102`, `AUDIT.md:113` and `phase-05:217`. WP-1's
   file list omits `security-checklist.md` entirely, and WP-3's coverage line for F-22 doesn't exist
   at all — F-22 is not mentioned in WP-3's "Covers" list. So the checklist's own literal `v1.36`
   text is now stale relative to the shipped code, and no planned work package closes it. Flagging
   explicitly rather than leaving it to be rediscovered as a surprise.
2. **The same gap exists for F-01 and F-02's `docs/operator-runbook.md`/`README.md` doc syncs.**
   Both findings list `docs/operator-runbook.md` and (F-01 only) `README.md §Configuration` under
   "Docs to sync", but neither file is in WP-1's allowed list (both belong to WP-3), and WP-3's own
   "Covers" line does not name F-01 or F-02 either — only F-05/F-08/F-09/F-10/F-11/F-13/F-14/F-17/
   F-18/F-19/F-21/F-25. `operator-runbook.md` and `README.md` therefore still describe
   `request_service_quotas`/cost-allocation-tag behavior that no longer matches the code (the async
   -approval caveat is still true; the two new failure modes and the two new defaults are not
   mentioned). Since the user's plan for this session is WP-1 + WP-2 only, this is left for a
   follow-up rather than expanding WP-1's scope unilaterally.
3. **`node_security_group_id` was not dropped from `modules/karpenter`** — see F-25 above. A
   deliberate, minimal-scope decision, not an oversight.

**Acceptance criteria (all from `terraform/`):**

```console
$ terraform fmt -check -recursive
(clean, exit 0)

$ terraform init -backend=false && terraform validate
Success! The configuration is valid.

$ terraform -chdir=bootstrap init -backend=false && terraform -chdir=bootstrap validate
Success! The configuration is valid.

$ terraform test
8 passed, 0 failed
(5 pre-existing + rejects_bare_ip_without_mask + rejects_missing_budget_email +
 accepts_paired_default_namespaces)

$ helm lint modules/cluster-resources/chart
1 chart(s) linted, 0 chart(s) failed

$ git check-ignore -q tf.plan && echo IGNORED
IGNORED

$ grep -n 'kms_master_key_id' modules/eks/main.tf
272:  kms_master_key_id = aws_kms_key.alerts.arn

$ grep -n 'depends_on' modules/karpenter/helm.tf
47:  depends_on = [helm_release.karpenter_crd, module.karpenter]

$ grep -n 'enforce-version' modules/cluster-resources/chart/templates/namespaces.yaml
23:    pod-security.kubernetes.io/enforce-version: latest

$ grep -n 'activate_cost_allocation_tags\|request_service_quotas' variables.tf budget.tf
variables.tf:327:variable "request_service_quotas" {
variables.tf:344:variable "activate_cost_allocation_tags" {
budget.tf:89:  count   = var.activate_cost_allocation_tags ? 1 : 0
budget.tf:95:  count   = var.activate_cost_allocation_tags ? 1 : 0
```

**F-20's dependency edge, confirmed real (not just a string that parses)** — via a throwaway
`terraform graph`, using a local-backend `override.tf` created and deleted for this one check only;
no state was ever written to S3 and `override.tf` was never committed:

```console
$ terraform graph | grep 'module.karpenter.helm_release.karpenter" ->'
"module.karpenter.helm_release.karpenter" -> "module.karpenter.module.karpenter.aws_cloudwatch_event_target.this";
"module.karpenter.helm_release.karpenter" -> "module.karpenter.module.karpenter.aws_eks_access_entry.node";
"module.karpenter.helm_release.karpenter" -> "module.karpenter.module.karpenter.aws_eks_pod_identity_association.karpenter";
"module.karpenter.helm_release.karpenter" -> "module.karpenter.module.karpenter.aws_iam_instance_profile.this";
"module.karpenter.helm_release.karpenter" -> "module.karpenter.module.karpenter.aws_iam_role_policy.controller";
"module.karpenter.helm_release.karpenter" -> "module.karpenter.module.karpenter.aws_iam_role_policy_attachment.controller";
"module.karpenter.helm_release.karpenter" -> "module.karpenter.module.karpenter.aws_iam_role_policy_attachment.controller_additional";
"module.karpenter.helm_release.karpenter" -> "module.karpenter.module.karpenter.aws_iam_role_policy_attachment.node";
"module.karpenter.helm_release.karpenter" -> "module.karpenter.module.karpenter.aws_iam_role_policy_attachment.node_additional";
```

`aws_eks_pod_identity_association.karpenter` — the exact resource F-20 says the Helm release could
previously start ahead of — is now a direct dependency.

`make check` re-run after every edit: fmt + validate (root and `bootstrap/`) + test all green;
`lint` cleanly skips (`tflint`/`checkov` not installed in this environment, consistent with every
prior phase). No AWS credentials used or required — everything above is static.

**Anything found on the way that belongs to another package:** none beyond deviations 1–2 above,
which are gaps in the review's own package boundaries rather than defects in WP-2/WP-3's scope.

### WP-2

**Status: DONE.** All findings covered by WP-2 addressed as their stated fix. Acceptance criteria
all pass, pasted below.

**Files changed:** `scripts/teardown.sh`, `scripts/verify.sh`, `Makefile`,
`docs/reference/gotchas.md` (G-09 block), `docs/phases/phase-08-verification-teardown.md`,
`docs/AUDIT.md` (S-C5, S-22, S-29), `modules/cluster-resources/chart/templates/namespaces.yaml:39-44`,
`docs/phases/phase-05-nodepools.md:237`, `README.md` (only the Teardown step list — WP-3 has not
run).

**Per-finding status:**

| # | Status | Notes |
|---|---|---|
| F-03 | Done | The real defect, not a cosmetic one: `karpenter.sh/managed-by` was replaced by `eks:eks-cluster-name` in Karpenter v1 and is never set by v1.14.0, so the "primary net" always found nothing and the gate rested entirely on `karpenter.sh/nodepool=*` — not cluster-scoped, so this would abort forever in a region running any other Karpenter cluster, and the manual G-09 recipe would report "nothing left" on every v1 cluster (the exact false-safe the script exists to prevent). `query_instances()` now ANDs `karpenter.sh/nodepool=*` with a cluster-scoped tag, checked two independent ways (`eks:eks-cluster-name` and `kubernetes.io/cluster/<name>=owned`). The "interrupted mid-launch" comment (also inaccurate) is gone. Fixed identically in `gotchas.md` G-09's recipe, `phase-08-verification-teardown.md` §8.2's snippet, and both places phase-08's own completion report had described the old two-tag design — corrected with an explicit `> Correction (…)` block rather than silently rewriting the historical record, since the report is dated evidence of what was believed true at the time. |
| F-04 (verify.sh assertion) | Done | §D2b now asserts `aws sns get-topic-attributes --query Attributes.KmsMasterKeyId` is empty or a real ARN, never the literal `alias/aws/sns`. |
| F-15 | Done | `VERIFY_EXPECT_LOG_TYPES` env override (default the five), looped over instead of the hardcoded list. Documented plainly that the README's own POC example fails this check by design and that is not a bug. |
| F-16 | Done | `make lint` now also runs `helm lint modules/cluster-resources/chart` (ran clean: 1 chart linted, 0 failed) and `kubeconform` guarded the same way as `tflint`/`checkov` (gracefully skipped — not installed here). `## lint:` help line updated. |
| F-19 (Makefile) | Done | `destroy`'s guard message changed from "does not exist yet (it ships in Phase 8)" — stale now that it has — to "is missing or not executable". The `test -x` guard itself is unchanged. |
| F-23 | Done | `kubectl delete nodepools --all --wait=true --timeout=15m` added immediately before the NodeClaims delete, in both `scripts/teardown.sh` and the `phase-08` §8.2 spec snippet and `gotchas.md` G-09's recipe. Step 2's comment, `README.md`'s step list and `AUDIT.md` S-C5 all updated to describe NodePools-then-NodeClaims. The **new** ordering assertion (NodePools < NodeClaims < destroy) passes against the shipped script. |
| F-24 | Done, wording only | `teardown.sh`'s EBS delete-branch comment now states plainly it only matches if the CSI driver tags with `kubernetes.io/cluster/<name>=owned` (not the default per the driver's own `tagging.md`) and points at the exact `kubectl` command to check on the first live run. Mirrored in `namespaces.yaml`'s comment and `phase-05-nodepools.md:237` ("does not sweep EBS" → "only REPORTS orphaned EBS volumes"), `README.md`'s Teardown step 5, and `AUDIT.md` S-C5. No add-on `configuration_values` added, per the prompt's explicit instruction not to. |

**Acceptance criteria (all from `terraform/`):**

```console
$ bash -n scripts/verify.sh && bash -n scripts/teardown.sh && shellcheck scripts/*.sh
(all clean, exit 0)

$ awk '/kubectl delete nodepools/{p=NR} /kubectl delete nodeclaims/{n=NR} /terraform destroy/{d=NR} END{ if(p&&n&&d&&p<n&&n<d) print "PASS ordering"; else print "FAIL ordering"}' scripts/teardown.sh
PASS ordering

$ grep -c 'karpenter.sh/managed-by' scripts/teardown.sh docs/reference/gotchas.md
scripts/teardown.sh:1
docs/reference/gotchas.md:1
$ grep -n 'karpenter.sh/managed-by' scripts/teardown.sh docs/reference/gotchas.md
scripts/teardown.sh:143:# NOTE (REVIEW.md F-03): this used to query karpenter.sh/managed-by, which
docs/reference/gotchas.md:193:version of this fix (and of `scripts/teardown.sh`) queried `karpenter.sh/managed-by`. Karpenter's own
(both are explanatory notes describing what changed and why, not live usage)

$ make lint
tflint not installed, skipping
checkov not installed, skipping
==> Linting modules/cluster-resources/chart
[INFO] Chart.yaml: icon is recommended
1 chart(s) linted, 0 chart(s) failed
kubeconform not installed, skipping

$ make check
8 passed, 0 failed (unchanged from WP-1 — WP-2 touches no .tf/.hcl)
tflint/checkov: not installed, skipping (unchanged)
helm lint: 1 chart(s) linted, 0 chart(s) failed
kubeconform: not installed, skipping
```

**Anything found on the way that belongs to another package:** none. The `README.md` edit was
confirmed in-scope before making it — WP-2's file list explicitly allows the Teardown step list
"only if WP-3 has not run yet", and it has not.

### WP-3

*(pending)*
