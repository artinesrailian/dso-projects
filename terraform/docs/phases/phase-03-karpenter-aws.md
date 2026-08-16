# Phase 3 — Karpenter, AWS side (IAM, SQS, EventBridge, access entry)

**Depends on:** Phases 0, 2.
**Produces:** `modules/karpenter/` (AWS resources only — the Helm release is Phase 4),
wired into `main.tf` as `module.karpenter`.

---

## Goal

Everything Karpenter needs on the AWS side before a single pod of it runs: a least-privilege
controller IAM role reachable via Pod Identity, a node IAM role, an EKS access entry that lets
Karpenter-launched nodes actually join, and the SQS queue plus EventBridge rules that carry Spot
interruption notices.

No Kubernetes objects are created in this phase. Nothing talks to the cluster API.

---

## Inputs

| Source | What you need |
|---|---|
| `contracts/interface-contract.md` | §5.3 the `modules/karpenter` signature |
| `reference/version-pinning.md` | Karpenter submodule `21.24.2`; **§4 "Karpenter submodule: variables removed in v21"** |
| `reference/karpenter-api-reference.md` | §7 IAM notes |
| `00-architecture-and-decisions.md` | ADR-4 (access entries), ADR-5 (Pod Identity) |
| Phase 2 completion report | The `module.eks` outputs as actually implemented |

---

## Files to create

```
modules/karpenter/versions.tf
modules/karpenter/variables.tf
modules/karpenter/main.tf       # the AWS-side submodule call
modules/karpenter/outputs.tf
modules/karpenter/README.md
```

Phase 4 will add `helm.tf` to this same module. Do not create it now.

Also **edit** `main.tf` to add `module "karpenter"`, and `outputs.tf`.

---

## Specification

### 3.1 The submodule call

```hcl
module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "21.24.2"   # keep identical to the parent eks module version

  cluster_name = var.cluster_name

  # --- Controller identity -------------------------------------------------
  # v21's karpenter submodule is Pod-Identity-ONLY. It creates the controller
  # role AND the aws_eks_pod_identity_association for you.
  # create_pod_identity_association defaults to true.
  create_pod_identity_association = true
  namespace                       = var.namespace       # kube-system
  service_account                 = "karpenter"

  # --- Node identity -------------------------------------------------------
  # The EC2NodeClass spec.role must match this name EXACTLY. Leaving the default
  # name_prefix on generates a random suffix; if anything then hardcodes the
  # role name, node launch fails. We pass the output through to Phase 5 rather
  # than hardcoding, but a stable name is still worth having for debugging.
  node_iam_role_use_name_prefix = false
  node_iam_role_name            = "${var.cluster_name}-karpenter-node"

  # The VPC CNI gets its own Pod Identity role in Phase 2, so the NODE role does
  # not need AmazonEKS_CNI_Policy. Leaving this at its default of `true` grants
  # every Karpenter node ENI/IP-manipulation rights, which any hostNetwork pod
  # inherits regardless of the IMDS hop limit — and makes S-32's least-privilege
  # claim false. See phase-02 "the AmazonEKS_CNI_Policy problem".
  node_iam_role_attach_cni_policy = false

  node_iam_role_additional_policies = {
    # Session Manager is the supported way onto a node. There is no SSH key
    # anywhere in this stack, and there should not be.
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  # --- Node cluster access -------------------------------------------------
  # THE most important two lines in this phase. Under authentication_mode = "API"
  # a node whose role has no access entry boots, fails to register, and is
  # invisible in `kubectl get nodes` — see the acceptance criteria for how that
  # failure actually presents.
  create_access_entry = true
  access_entry_type   = "EC2_LINUX"

  # --- Interruption handling ----------------------------------------------
  enable_spot_termination  = true
  queue_managed_sse_enabled = true

  tags = var.tags
}
```

### 3.2 Variables you must NOT pass

These were valid in v20 and appear in essentially every Karpenter-on-Terraform blog post written
before mid-2025. In v21 they do not exist, and passing them is a hard error:

`enable_v1_permissions` · `enable_pod_identity` · `enable_irsa` · `irsa_oidc_provider_arn` ·
`irsa_namespace_service_accounts` · `irsa_assume_role_condition_test`

There is nothing to enable. v21's submodule is Pod-Identity-only and always installs the Karpenter
v1 policy.

### 3.3 What the submodule creates, so you can verify it

| Resource | Purpose |
|---|---|
| `aws_iam_role` (controller) + scoped policy | Least-privilege Karpenter permissions |
| `aws_eks_pod_identity_association` | Binds the `karpenter` SA in `kube-system` to that role |
| `aws_iam_role` (node) | Assumed by every Karpenter-launched instance |
| `aws_eks_access_entry` (type `EC2_LINUX`) | Lets those nodes join the cluster |
| `aws_sqs_queue` + queue policy | Interruption events |
| `aws_cloudwatch_event_rule` × 5 + targets | Spot interruption, rebalance recommendation, scheduled change, instance state change, capacity-reservation interruption |

It does **not** create an instance profile (`create_instance_profile` defaults to `false`), and that
is correct: Karpenter v1 generates the instance profile itself from `EC2NodeClass.spec.role`. The
`instance_profile_name` output is empty — do not wire it anywhere.

### 3.4 Access-entry type — get this right

`EC2_LINUX` is correct. There is a newer `EC2` type, and it is tempting to assume it supersedes the
older one; it does not. Per AWS, `EC2` is scoped specifically to *"EKS Auto Mode custom node
classes"*. Karpenter nodes are self-managed EC2 nodes, so `EC2_LINUX` applies. The submodule's own
default agrees.

Two constraints on non-`STANDARD` entry types: the caller needs `iam:PassRole`, and you cannot
attach an access policy or `--kubernetes-groups` to them. The type is immutable after creation.

### 3.5 Least-privilege — what the policy actually does

Worth understanding rather than trusting, because "Karpenter needs `ec2:RunInstances`" sounds
alarming until you see the conditions. The module implements the same statement set as AWS's
official CloudFormation, which as of v1.14.0 is split into six managed policies (node lifecycle, IAM
integration, EKS integration, interruption, resource discovery, zonal shift).

The constraints that matter:

- `ec2:RunInstances` / `CreateFleet` / `CreateLaunchTemplate` require
  `aws:RequestTag/kubernetes.io/cluster/<cluster>` = `owned` **and**
  `aws:RequestTag/eks:eks-cluster-name` = `<cluster>`. Karpenter cannot launch untagged instances.
- `iam:PassRole` is scoped to the **single node role ARN**, with `iam:PassedToService` restricted to
  `ec2.amazonaws.com`. This is the statement that would otherwise be a privilege-escalation path.
- `ssm:GetParameter` is scoped to `parameter/aws/service/*` (AMI lookups only).
- `eks:DescribeCluster` is scoped to the one cluster ARN.
- SQS is limited to `DeleteMessage`, `GetQueueUrl`, `ReceiveMessage` on the interruption queue only.
- `ec2:Describe*` is `Resource: *` — unavoidable, as EC2 describe calls do not support resource-level
  permissions — but conditioned on `aws:RequestedRegion`.

Add a comment in `main.tf` pointing at this section. A reviewer asking "why does this thing have
RunInstances?" should find the answer in the code.

One residual risk worth knowing: because Karpenter keys off instance tags, anyone with
`ec2:CreateTags`/`DeleteTags` on `i-*` can induce Karpenter to create or delete machines. In a real
environment, constrain those actions.

### 3.6 Outputs

Exactly interface-contract §5.3. Map from the submodule's actual output names:

| Our output | Submodule output |
|---|---|
| `controller_iam_role_arn` | `iam_role_arn` |
| `node_iam_role_name` | `node_iam_role_name` |
| `node_iam_role_arn` | `node_iam_role_arn` |
| `interruption_queue_name` | `queue_name` |
| `interruption_queue_arn` | `queue_arn` |
| `namespace` | `namespace` |

`helm_release_name` comes in Phase 4.

> The submodule's instance-profile outputs are `instance_profile_arn`, `instance_profile_id`,
> `instance_profile_name` and — note the upstream typo — **`instance_profile_unique`**, not
> `instance_profile_unique_id`. We use none of them.

### 3.7 The Spot service-linked role

Prerequisite P2 says the operator creates it. You *may* manage it in Terraform:

```hcl
resource "aws_iam_service_linked_role" "spot" {
  count            = var.create_spot_service_linked_role ? 1 : 0
  aws_service_name = "spot.amazonaws.com"
}
```

Default the variable to **`true`** so a fresh account works with no manual step — this is
prerequisite P2, and leaving it to a human is how a first deploy fails with an error that looks like
an IAM problem.

The complication is that the resource **fails if the role already exists**
(`InvalidInput: Service role name AWSServiceRoleForEC2Spot has been taken in this account`), which
is the common case on any account that has ever launched a Spot instance. Handle it in code rather
than with a toggle a human has to reason about:

```hcl
# Adopt the role if it already exists; create it if it does not. `import` blocks
# are declarative and no-op when the role is absent, so this is idempotent across
# both fresh and established accounts.
import {
  to = aws_iam_service_linked_role.spot[0]
  id = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/spot.amazonaws.com/AWSServiceRoleForEC2Spot"
}
```

**Verify this actually behaves as described before relying on it** — `import` block semantics for a
resource that may not exist are the sort of thing that changes between Terraform versions. If it
does not work cleanly on both a fresh and an established account, fall back to the toggle defaulted
`false` **plus** an explicit `verify.sh` assertion that the role exists, so the gap is detected
rather than merely documented. Record which path you took in your completion report.

---

## Security requirements owned by this phase

- **S-30** Controller credentials come from EKS Pod Identity. No static keys, no IRSA trust policy.
- **S-31** `iam:PassRole` scoped to the single node role, restricted to `ec2.amazonaws.com`.
- **S-32** Node role carries only `AmazonEKSWorkerNodePolicy`,
  `AmazonEC2ContainerRegistryPullOnly` (the tighter replacement for `...ReadOnly`) and
  `AmazonSSMManagedInstanceCore`.
- **S-33** SQS queue has managed SSE enabled and a policy allowing `SendMessage` only from
  `events.amazonaws.com` / `sqs.amazonaws.com`, with an explicit deny on non-TLS.
- **S-34** Node access entry is type `EC2_LINUX`, created for exactly one node role.

---

## Acceptance criteria

Without credentials:

```bash
terraform fmt -check -recursive
terraform init -backend=false
terraform validate

cd modules/karpenter
grep -q 'create_access_entry *= *true'  main.tf && echo "PASS: node access entry"
grep -q 'EC2_LINUX'                     main.tf && echo "PASS: correct entry type"
grep -q 'enable_spot_termination'       main.tf && echo "PASS: interruption queue"
grep -q 'node_iam_role_use_name_prefix *= *false' main.tf && echo "PASS: stable node role name"

# Must find NOTHING — these are v20 variables removed in v21:
grep -nE 'enable_v1_permissions|enable_pod_identity|enable_irsa|irsa_oidc_provider_arn' main.tf

# Must find NOTHING — the empty output:
grep -n 'instance_profile_name' outputs.tf
```

With credentials:

```bash
terraform apply

CLUSTER=$(terraform output -raw cluster_name)

# Pod Identity association exists and points at the karpenter SA
aws eks list-pod-identity-associations --cluster-name "$CLUSTER" \
  --query 'associations[].{ns:namespace,sa:serviceAccount}'
# Expect: kube-system / karpenter

# The node access entry exists and is EC2_LINUX
aws eks list-access-entries --cluster-name "$CLUSTER"
aws eks describe-access-entry --cluster-name "$CLUSTER" \
  --principal-arn "$(terraform output -raw karpenter_node_iam_role_arn)" \
  --query 'accessEntry.type'
# Expect: "EC2_LINUX"

# Queue and rules
aws sqs get-queue-attributes --queue-url "$(aws sqs get-queue-url \
  --queue-name "$(terraform output -raw karpenter_interruption_queue_name)" \
  --query QueueUrl --output text)" --attribute-names All \
  --query 'Attributes.{SSE:SqsManagedSseEnabled,Retention:MessageRetentionPeriod}'

aws events list-rules --query "Rules[?contains(Name,'Karpenter')].Name"
# Expect 5 rules
```

---

## Notes for the implementing agent

- Do not install the Helm chart. Do not create NodePools. Phases 4 and 5.
- Do not add a `helm` provider block yet — Phase 4 adds it together with the release.
- If the submodule rejects an argument, check it against
  `https://raw.githubusercontent.com/terraform-aws-modules/terraform-aws-eks/v21.24.2/modules/karpenter/variables.tf`
  before changing the design. The full 46-variable list is enumerated there.

---

## Agent prompt

```text
Implement Phase 3 of the EKS + Karpenter Terraform assessment.

Working directory: /home/artin/personal/git/dso-projects/terraform

SCOPE BOUNDARY — non-negotiable, applies to every action you take:
  1. Your working directory is /home/artin/personal/git/dso-projects/terraform. You never leave it.
     Every path in this prompt and in every doc it references is RELATIVE TO THAT DIRECTORY.
  2. The sibling directory /home/artin/personal/git/dso-projects/architecture is a DIFFERENT,
     UNRELATED assessment. Do not read it, write to it, list it, grep it, or cd into it.
     There is nothing in it you need.
  3. Create NOTHING at the repository root (/home/artin/personal/git/dso-projects) — no new files,
     no new directories, no sibling of terraform/ or architecture/. Everything you produce
     lives under terraform/. That includes .gitignore, CI config, scripts and notes.
  4. Do not run commands that walk the whole repo (`find /home/artin/personal/git/dso-projects`,
     `grep -r` from the root, `git status` at the root). Scope every search to terraform/.
  If you believe you genuinely need something outside terraform/, stop and say so in your
  completion report instead of doing it.

Read these files first, in this order:
  1. docs/00-architecture-and-decisions.md          (ADR-4, ADR-5)
  2. docs/contracts/interface-contract.md           (NORMATIVE — §5.3 signature)
  3. docs/reference/version-pinning.md              (§4 — the v21 karpenter submodule
                                                             REMOVED six variables; do not use them)
  4. docs/reference/karpenter-api-reference.md      (§7 IAM notes)
  5. docs/phases/phase-03-karpenter-aws.md          (your specification)
  6. docs/phases/phase-02-eks-cluster.md            (read its Completion report only)

Implement modules/karpenter/ — AWS resources ONLY — exactly as phase-03 specifies,
then wire it into main.tf as `module "karpenter"` and add its outputs to
outputs.tf.

Critical constraints:
  - Do NOT create helm.tf, do NOT add a helm provider block, do NOT install any chart.
    Phase 4 owns all of that.
  - Do NOT create NodePool or EC2NodeClass resources. Phase 5 owns those.
  - Do NOT pass enable_v1_permissions, enable_pod_identity, enable_irsa, irsa_oidc_provider_arn,
    irsa_namespace_service_accounts, or irsa_assume_role_condition_test — all removed in v21.
  - create_access_entry must be true and access_entry_type must be "EC2_LINUX".
  - terraform fmt -recursive must be clean.
  - Do NOT run `terraform apply` unless I have told you AWS credentials are available.

When finished, run the applicable "Acceptance criteria", then fill in the
"## Completion report" section at the bottom of docs/phases/phase-03-karpenter-aws.md
and stop. Do not start Phase 4.
```

---

## Completion report

- Status: DONE — every static acceptance criterion ("Without credentials") passes, S-30 through
  S-34 are satisfied and independently re-verified against the actual pinned upstream submodule
  source (not assumed), and §3.7's own "verify before relying on it" instruction was acted on:
  the `import`-block approach it proposes was tested and found to break `terraform apply` on a
  fresh account, so this phase implements §3.7's own sanctioned fallback instead. The
  "With credentials" acceptance criteria are unverified — no AWS credentials were available or
  acquired, per the task's own instruction not to run `terraform apply` without them.

- Files created/changed:
  - `modules/karpenter/versions.tf`, `modules/karpenter/variables.tf`, `modules/karpenter/main.tf`,
    `modules/karpenter/outputs.tf`, `modules/karpenter/README.md` — new, per "Files to create."
    No `helm.tf`, no `helm` provider requirement, no `NodePool`/`EC2NodeClass` resources — all
    confirmed absent by grep, re-confirmed by an independent verification pass (see below).
  - `main.tf` — added `module "karpenter"` (module blocks only, no resources — interface-contract
    §1 rule 1 preserved). `cluster_name`/`cluster_endpoint`/`node_security_group_id` wired from
    `module.eks.*` outputs (not `local.name` or a literal), `karpenter_version`/`namespace` from
    the matching root variables, `create_spot_service_linked_role` passed through unchanged.
  - `outputs.tf` — added `karpenter_controller_iam_role_arn`, `karpenter_node_iam_role_name`,
    `karpenter_node_iam_role_arn`, `karpenter_interruption_queue_name`. `karpenter_node_iam_role_arn`
    is new relative to interface-contract §4's prior list — required by this phase's own
    "With credentials" acceptance criteria (`terraform output -raw karpenter_node_iam_role_arn`);
    added to the contract in the same change, per the contract's own rule.
  - `variables.tf` (root) — changed `create_spot_service_linked_role`'s default from `true` to
    `false` and rewrote its description. See Deviations below; this is the one place this phase
    changes an *existing* stated default rather than adding something new.
  - `docs/contracts/interface-contract.md` — §3 row for `create_spot_service_linked_role` updated
    (default `true` → `false`, reasoning stated); §4 gained the `karpenter_node_iam_role_arn` row.
    §5.3 (the `modules/karpenter` signature itself) was not changed — this phase implements exactly
    6 of its 7 outputs, `helm_release_name` being explicitly Phase 4's per §3.6 of this doc.
  - `.terraform.lock.hcl` — unchanged; the karpenter submodule needs no provider beyond `aws`,
    already pinned.

- Deviations from spec:
  1. **§3.7's `import`-block approach was evaluated and rejected; its own sanctioned fallback was
     implemented instead.** §3.7 proposes defaulting `create_spot_service_linked_role` to `true`
     and using a root-level `import` block so `aws_iam_service_linked_role.spot` is adopted (not
     recreated) on any account where it already exists — but flags this as unverified ("verify
     this actually behaves as described before relying on it"). Two things were checked, not
     assumed:
     - *Placement*: a throwaway root+child-module experiment (`terraform validate`) confirmed an
       `import` block placed in the **root** module, targeting a resource inside a **child**
       module (`module.karpenter.aws_iam_service_linked_role.spot[0]`), is syntactically legal.
       Placement was never the blocker.
     - *Semantics*: read the actual plan-time import-verification logic in
       `internal/terraform/node_resource_plan_instance.go` at the exact pinned CLI version
       (`v1.15.8`, confirmed via `terraform version` in this environment) — fetched directly from
       `raw.githubusercontent.com/hashicorp/terraform`, not recalled. Confirmed: when the import
       target's refreshed state is null (object doesn't exist), Terraform emits a hard error,
       "Cannot import non-existent remote object", and does **not** fall through to a normal create
       plan. That means the "chosen" approach would hard-fail `terraform apply` on every genuinely
       fresh account — the one case `create_spot_service_linked_role` exists to cover — which is
       worse than the failure mode it was meant to avoid.
     - Implemented §3.7's own fallback instead: a plain `count`-gated
       `aws_iam_service_linked_role.spot` resource, **no `import` block**, and
       `create_spot_service_linked_role` now defaults **`false`** (root `variables.tf` and
       `docs/contracts/interface-contract.md` §3 both updated). Full reasoning, and the exact
       source excerpt, are in `modules/karpenter/README.md` under "The AWSServiceRoleForEC2Spot
       decision."
     - This was independently re-verified by a dedicated adversarial-verification agent, which
       re-fetched the same Terraform source file and confirmed the error path fires unconditionally
       on a null refresh (not gated on any deferred-plan special case), and confirmed the deviation
       was applied consistently across every file that references the variable or its default.
  2. **`karpenter_node_iam_role_arn` added to interface-contract §4** (root outputs) — this phase's
     own "With credentials" acceptance criteria consume it via `terraform output -raw
     karpenter_node_iam_role_arn`, but it was not previously in the contract's output list. Added
     in the same change per the contract's own escape-valve rule (§9 header). Same pattern as
     phase-02's Deviation #2.
  3. **`cluster_endpoint`, `karpenter_version` and `node_security_group_id` are declared in
     `modules/karpenter/variables.tf` but unused by any resource in this phase.** This is not a
     drift from the contract — interface-contract §5.3 requires all three as inputs to
     `modules/karpenter` (a module explicitly shared by Phases 3 *and* 4) — but it is worth stating
     plainly rather than leaving a reviewer to wonder why they're unreferenced. `cluster_endpoint`
     and `karpenter_version` have an obvious Phase 4 consumer (`settings.clusterEndpoint`, and
     pinning the `karpenter`/`karpenter-crd` chart versions). `node_security_group_id` does not —
     flagged as a note for the next phase below.

- Names added to interface-contract.md:
  - `modules/eks`/root outputs §4: `karpenter_node_iam_role_arn` (`string`) — see Deviations #2.
  - §3 root variables: no new variable, but `create_spot_service_linked_role`'s stated default
    changed from `true` to `false` — see Deviations #1.

- Verification run (all from `terraform/`, no AWS credentials used or required):
  - `terraform fmt -recursive` → reformatted one alignment issue in
    `modules/karpenter/main.tf`; `terraform fmt -check -recursive` → clean (exit 0) after.
  - `terraform init -backend=false` → resolves `terraform-aws-modules/eks/aws//modules/karpenter`
    21.24.2 (matching the parent `module.eks` pin exactly, per version-pinning.md); no new
    providers required beyond the already-pinned `aws`.
  - `terraform validate` (root) → `Success! The configuration is valid.`
  - `terraform -chdir=bootstrap init -backend=false && terraform -chdir=bootstrap validate` →
    `Success!` (unaffected by this phase).
  - `terraform test` → 5 passed, 0 failed — the existing `cidr_guard`/`network_endpoints` suites
    needed no new `mock_data` overrides once `module.karpenter` entered the plan (the karpenter
    submodule's own `data.aws_region`/`aws_partition`/`aws_caller_identity` calls are satisfied by
    the mocks phase-02 already added for `module.eks`).
  - `make check` → fmt + validate (root and `bootstrap/`) + test all green; `lint` cleanly skips
    (tflint/checkov not installed) — consistent with phase-02's environment.
  - Acceptance-criteria static assertions, run verbatim from `modules/karpenter/`: all 4 positive
    greps (`create_access_entry = true`, `EC2_LINUX`, `enable_spot_termination`,
    `node_iam_role_use_name_prefix = false`) PASS; both negative greps (the four v20 names against
    `main.tf`, `instance_profile_name` against `outputs.tf`) produced **no output**, confirmed
    without needing any comment-stripping trick — the six removed v20 variable names and
    `instance_profile_name` were kept entirely out of `main.tf`/`outputs.tf`, including in
    comments, and discussed only in `README.md` instead.
  - `terraform apply` — **not run.** No AWS credentials were provided to this environment and the
    task explicitly says not to run it without them. Everything under "With credentials" in the
    Acceptance criteria (the Pod Identity association check, the access-entry type check, the SQS
    queue/EventBridge-rules check) is therefore unverified against a real account.
  - **Independent adversarial re-verification** (four parallel agents, each re-deriving from
    primary sources rather than trusting this report or `modules/karpenter/README.md`):
    1. *Interface-contract signature* — re-read §5.3, `modules/karpenter/{variables,outputs}.tf`,
       root `main.tf`/`outputs.tf`, and cross-checked every wired output name against the fetched
       upstream `outputs.tf`. Result: PASS, no discrepancies.
    2. *Security requirements S-30–S-34* — independently fetched the upstream submodule's
       `main.tf`/`policy.tf`/`variables.tf` at `v21.24.2` and traced each requirement to a specific
       upstream statement or hardcoded attachment, then confirmed no argument in
       `modules/karpenter/main.tf` overrides or widens any of them (checked
       `iam_policy_statements`, `queue_policy_statements`, `iam_role_policies`, and related
       escape-hatch variables are all absent, so upstream defaults — which are also correct — are
       what apply). Result: PASS on all five, evidence cited to exact upstream line numbers.
    3. *Acceptance criteria re-run* — independently re-ran every command and grep in this section
       and confirmed exit codes/output directly. Result: PASS on all of them. Also flagged (as a
       process gap, not a code defect) that this Completion report section was still unfilled at
       the time it ran, and that §3.7's fallback's "plus an explicit `verify.sh` assertion" half
       has not landed anywhere in-repo yet — both addressed by this section and by the note below.
    4. *Spot-role decision audit* — independently fetched and read the same Terraform source file
       and confirmed the "Cannot import non-existent remote object" error path, confirmed
       `terraform version` matches `v1.15.8`, and confirmed the default-`false` change was applied
       consistently everywhere the variable is referenced. Result: the technical decision is
       correct; recommended filling in this Completion report (now done).

- Notes for the next phase:
  - `module.karpenter.controller_iam_role_arn` / `node_iam_role_name` / `node_iam_role_arn` /
    `interruption_queue_name` / `interruption_queue_arn` / `namespace` are all available now.
    `helm_release_name` is Phase 4's to add, to this same module's `outputs.tf`.
  - **`create_spot_service_linked_role` now defaults to `false`**, not `true` as originally
    specified — an operator deploying to a fresh account must explicitly set it `true` (having
    first confirmed the role doesn't already exist, per prerequisite P2), or create the role by
    hand. The README (root, Phase 7) must document this explicitly since it changes the
    zero-configuration story P2 originally promised. `terraform.tfvars.example` does not currently
    mention this variable at all — Phase 7 should consider whether it needs a commented-out
    example line given the default changed.
  - **Phase 8's `verify.sh`** (not yet written — out of scope for this phase, which has no file
    list entry for it) should assert `AWSServiceRoleForEC2Spot` actually exists before/after
    apply, per §3.7's fallback text ("so the gap is detected rather than merely documented"). Right
    now that gap is only documented (in `modules/karpenter/README.md` and here), not asserted in
    code anywhere. Flagging explicitly so Phase 8 doesn't have to rediscover it.
  - **`node_security_group_id`** is declared on `modules/karpenter` (interface-contract §5.3
    requires it) but has no consumer in this phase and none identified for Phase 4 either — Phase
    4's own doc (`phase-04-karpenter-helm.md`) should be checked for whether it expects this input
    to do something; if not, it may simply be a stable, intentionally-unused part of the contract
    signature. Not resolved here since Phase 4 is out of this phase's scope.
  - S-31's `iam:PassRole` condition and S-33's SQS `SendMessage` principal restriction both come
    from the upstream submodule's hardcoded policy, not from anything in this repo — a future
    submodule version bump should re-diff `policy.tf`/`main.tf` against what's asserted here and in
    `modules/karpenter/README.md`, the same way `version-pinning.md` §5 already flags for the
    parent `eks` module.
