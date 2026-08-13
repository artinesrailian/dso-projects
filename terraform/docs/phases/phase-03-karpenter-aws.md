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

Default the variable to **`false`**, because the resource fails on any account that already has the
role (`InvalidInput: Service role name AWSServiceRoleForEC2Spot has been taken in this account`) and
that is the common case. Document the toggle in the README. This is a judgement call, not an
oversight — say so in the code comment.

---

## Security requirements owned by this phase

- **S-30** Controller credentials come from EKS Pod Identity. No static keys, no IRSA trust policy.
- **S-31** `iam:PassRole` scoped to the single node role, restricted to `ec2.amazonaws.com`.
- **S-32** Node role carries only `AmazonEKSWorkerNodePolicy`, `AmazonEKS_CNI_Policy`,
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

Working directory: /home/artin/personal/git/opsfleet/terraform

SCOPE BOUNDARY — non-negotiable, applies to every action you take:
  1. Your working directory is /home/artin/personal/git/opsfleet/terraform. You never leave it.
     Every path in this prompt and in every doc it references is RELATIVE TO THAT DIRECTORY.
  2. The sibling directory /home/artin/personal/git/opsfleet/architecture is a DIFFERENT,
     UNRELATED assessment. Do not read it, write to it, list it, grep it, or cd into it.
     There is nothing in it you need.
  3. Create NOTHING at the repository root (/home/artin/personal/git/opsfleet) — no new files,
     no new directories, no sibling of terraform/ or architecture/. Everything you produce
     lives under terraform/. That includes .gitignore, CI config, scripts and notes.
  4. Do not run commands that walk the whole repo (`find /home/artin/personal/git/opsfleet`,
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

*To be filled in by the implementing agent.*

- Status:
- Files created/changed:
- Deviations from spec:
- Names added to interface-contract.md:
- Verification run:
- Notes for the next phase:
