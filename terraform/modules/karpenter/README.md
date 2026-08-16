# modules/karpenter

AWS-side Karpenter resources (Phase 3, `main.tf`): the controller IAM role
(bound via EKS Pod Identity, not IRSA), the node IAM role, the EKS access
entry that lets Karpenter-launched nodes actually join the cluster, and the
SQS queue plus five EventBridge rules that carry Spot interruption /
rebalance / state-change events. Plus the Helm releases that actually put the
Karpenter controller on the cluster (Phase 4, `helm.tf`): the `karpenter-crd`
chart and the `karpenter` controller chart, in that order. See
`docs/00-architecture-and-decisions.md` ADR-4 (access entries), ADR-5 (Pod
Identity), and `docs/contracts/interface-contract.md` §5.3 for this module's
exact input/output contract.

Phase 5's separate `modules/cluster-resources` owns the `NodePool` /
`EC2NodeClass` custom resources — this module stops at getting the
controller running with its CRDs installed.

## v20 → v21

This module wraps `terraform-aws-modules/eks/aws//modules/karpenter`
**21.24.2** — kept identical to the parent `modules/eks` version. v21's
submodule is **Pod-Identity-only**: `create_pod_identity_association`
(default `true`, set explicitly here) creates both the controller's IAM role
and its `aws_eks_pod_identity_association` in one step. There is no
OIDC-federation path. Six v20 variables — `enable_v1_permissions`,
`enable_pod_identity`, `enable_irsa`, `irsa_oidc_provider_arn`,
`irsa_namespace_service_accounts`, `irsa_assume_role_condition_test` — no
longer exist; passing any of them is a hard error. See
`docs/reference/version-pinning.md` §4.

## Verified against the submodule source, not assumed

Every argument this module passes to the submodule, and everything it relies
on the submodule's *defaults* to do, was checked against the actual
`v21.24.2` source (`main.tf`, `policy.tf`, `variables.tf`, `outputs.tf` —
fetched directly, not recalled), because a phase spec is a plan, not a
schema:

- **S-32** (node role carries only `AmazonEKSWorkerNodePolicy`,
  `AmazonEC2ContainerRegistryPullOnly` and `AmazonSSMManagedInstanceCore`) is
  satisfied by the submodule's own hardcoded attachment
  (`aws_iam_role_policy_attachment.node` in `main.tf` attaches exactly
  `AmazonEKSWorkerNodePolicy` + `AmazonEC2ContainerRegistryPullOnly`
  unconditionally, ref'd from the AWS-published `eks_node_group` policy list),
  combined with `node_iam_role_attach_cni_policy = false` here and the single
  `AmazonSSMManagedInstanceCore` entry in `node_iam_role_additional_policies`.
  Unlike the bootstrap node group (phase-02's Deviation #5, stuck on
  `...ReadOnly` because the `eks-managed-node-group` submodule hardcodes it),
  the karpenter submodule already uses the tighter `...PullOnly` policy — no
  gap here.
- **S-31** (`iam:PassRole` scoped to the single node role, restricted to
  `ec2.amazonaws.com`) is the `AllowPassingInstanceRole` statement in
  `policy.tf` — `resources = [aws_iam_role.node[0].arn]`,
  `iam:PassedToService` conditioned to `ec2.amazonaws.com`.
- **S-33** (SQS: SSE enabled, `SendMessage` only from `events.amazonaws.com` /
  `sqs.amazonaws.com`, explicit deny on non-TLS) is the submodule's own
  `data.aws_iam_policy_document.queue` in `main.tf` — a `SqsWrite` statement
  scoped to exactly those two principals, plus a `DenyHTTP` statement denying
  all `sqs:*` when `aws:SecureTransport = false`. `queue_managed_sse_enabled =
  true` (also the default) is set explicitly here.
- **S-30** and **S-34** are direct consequences of
  `create_pod_identity_association = true` and `create_access_entry = true` /
  `access_entry_type = "EC2_LINUX"` respectively — both set explicitly above
  even though they match the submodule's own defaults, because an explicit
  security control survives a future default change and reads as intentional.

None of the above required overriding `iam_policy_statements` or
`queue_policy_statements` — the submodule's built-in policies already satisfy
this phase's S-30–S-34 as written.

## The AWSServiceRoleForEC2Spot decision — adopt-or-create was rejected

Prerequisite P2 says the operator creates this service-linked role manually.
phase-03.md §3.7 proposes automating it with a root-level `import` block so
`create_spot_service_linked_role` can safely default `true` on *both* a fresh
account (role doesn't exist → Terraform creates it) and an established one
(role already exists → `import` adopts it instead of erroring with
`InvalidInput: ... has been taken in this account`) — but flags its own
proposal as unverified: "verify this actually behaves as described before
relying on it."

It does not behave as described. Terraform's `import` block has no
"adopt-if-present, create-if-absent" mode: if the target `id` does not
correspond to a real object, `terraform plan` hard-fails with "Cannot import
non-existent remote object" instead of falling through to a normal create
plan. Confirmed by reading the actual plan-time import-verification logic in
`internal/terraform/node_resource_plan_instance.go` at the exact pinned CLI
version (`v1.15.8`) — not assumed, and not something a plain `terraform
validate` could have caught, since `validate` never refreshes state. (A
throwaway root+child-module experiment in a scratch directory *did* confirm
the orthogonal question — that an `import` block is legal when it targets a
resource inside a child module, as long as the block itself lives in the root
module — so placement was never the blocker; runtime semantics were.)

That means the "chosen" approach would hard-fail `terraform apply` on every
genuinely fresh account — the one case P2 and this variable's whole existence
are meant to cover — which is worse than the failure mode it was designed to
avoid. So this module implements phase-03 §3.7's own sanctioned fallback
instead: a plain, unconditional `count`-gated `aws_iam_service_linked_role.spot`,
**no `import` block**, and `create_spot_service_linked_role` now defaults to
**`false`** (root `variables.tf` and `docs/contracts/interface-contract.md`
§3 both updated — a deviation from the contract's previous stated default of
`true`, recorded in phase-03's completion report).

Consequence: an operator on a fresh account must explicitly set
`create_spot_service_linked_role = true` (having confirmed the role does not
already exist — `aws iam get-role --role-name AWSServiceRoleForEC2Spot`, per
prerequisite P2), or create it by hand
(`aws iam create-service-linked-role --aws-service-name spot.amazonaws.com`).
An operator on an established account leaves the default `false` and Karpenter
Spot launches work immediately, using whatever service-linked role already
exists. Phase 8's `verify.sh` (not yet written) should assert the role's
existence directly rather than relying on either path having run correctly —
noted in phase-03's completion report for that phase.

## Variables declared here but unused

`node_security_group_id` is required by
`docs/contracts/interface-contract.md` §5.3's signature but is not referenced
by any resource in this module — not `main.tf`'s AWS-side resources, and not
`helm.tf`'s Helm releases either (checked against phase-04's own spec, which
never mentions it). It is declared for contract-signature stability only;
flagged in phase-03's completion report in case a later phase can explain it
or it should be dropped. `cluster_endpoint` and `karpenter_version`, by
contrast, were unused through Phase 3 but are consumed by `helm.tf` as of
Phase 4 (`settings.clusterEndpoint`, and pinning both chart versions).

## Helm values intentionally not set (Phase 4)

`helm_release.karpenter`'s `set` list omits several values on purpose —
each is a value a naive copy-paste example tends to include, and each would
actively break something here if set:

- **The controller's service-account annotation for IAM-Roles-for-Service-Accounts.**
  That annotation is how the *IRSA* credential path is wired; this stack uses
  EKS Pod Identity instead (`module.karpenter.create_pod_identity_association`
  in `main.tf`, Phase 3), which needs no chart-side configuration at all.
  Setting the annotation anyway would give the controller pod two competing
  credential sources.
- **`serviceAccount.create` / `serviceAccount.name`.** The chart defaults
  (`true` / `"karpenter"`) already match the service account name the Phase 3
  Pod Identity association was created against. Changing either breaks that
  binding silently — Karpenter's pod would run under a different service
  account than the one the association targets.
- **`affinity`.** The chart's default node affinity already excludes nodes
  carrying `karpenter.sh/nodepool`, which is what stops Karpenter scheduling
  itself onto capacity it manages. Overriding `affinity` is the most direct
  way to accidentally remove that guarantee.
- **`replicas`.** Left at the chart default of `2`. The chart's `2` replicas
  carry a required `podAntiAffinity` on `kubernetes.io/hostname`, so they need
  two distinct nodes — see the bootstrap group's `min_size = 2` (Phase 2).
- **`featureGates.*`.** All left at safe defaults. `spotToSpotConsolidation`
  is tempting for cost but is alpha; not enabled here. The root README does
  not exist yet (Phase 7), so this note is the only carrier of that
  instruction until Phase 7 writes it — carry it forward as a future-work
  bullet rather than dropping it silently.

## Provider auth: `exec`, not a static-token data source (Phase 4)

The root `helm` provider block (`providers.tf`) authenticates via `exec`
(`aws eks get-token`), never a static-token data source. That data source's
token is written into Terraform state and expires after 15 minutes; a first
apply of this stack (VPC + cluster + node group + two Helm releases) routinely
takes longer than that, which produces intermittent `401 Unauthorized`
partway through. `exec` fetches a fresh token per invocation instead — see
`reference/gotchas.md` G-20.

## What this module does not do

- Does not create `NodePool` or `EC2NodeClass` objects — Phase 5's
  `modules/cluster-resources` owns those, via its local Helm chart.
- Does not create an instance profile (`create_instance_profile` defaults to
  `false`, left alone). Karpenter v1 builds the instance profile itself from
  `EC2NodeClass.spec.role`; the submodule's `instance_profile_*` outputs are
  unused here and, per the submodule's own naming, one of them
  (`instance_profile_unique`) does not even carry the `_id` suffix its
  siblings use.
