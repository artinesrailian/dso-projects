# Phase 0 — Repository scaffold & remote state

**Depends on:** nothing. This is the first phase.
**Produces:** the `terraform/` skeleton that every later phase writes into, plus a one-shot
`bootstrap/` root module that creates the S3 state backend.

---

## Goal

After this phase, `terraform init -backend=false && terraform validate` succeeds
against a stack that declares every variable, pins every version, and configures the AWS provider —
but creates no infrastructure yet. A separate `bootstrap/` stack can be applied by hand to
create an encrypted, versioned, locked S3 backend.

This phase is deliberately boring. Its whole value is that phases 1–8 never have to argue about
naming, tagging, versions or provider config again.

---

## Inputs

| Source | What you need from it |
|---|---|
| `docs/contracts/interface-contract.md` | §1 layout, §2 naming/tagging, §3 the complete root variable table, §8 style rules |
| `docs/reference/version-pinning.md` | §1 every version, §2 provider v3 syntax |
| `docs/00-architecture-and-decisions.md` | ADR-8 (why S3 + native locking, no DynamoDB) |

---

## Files to create

All paths are relative to `terraform/`, which is your working directory.

```
.gitignore                      # scoped to terraform/, NOT the repository root
versions.tf
providers.tf
backend.tf
backend.hcl.example
locals.tf
variables.tf
outputs.tf            # header comment only; later phases append
main.tf               # header comment only; later phases append
terraform.tfvars.example
tests/cidr_guard.tftest.hcl
bootstrap/versions.tf
bootstrap/variables.tf
bootstrap/main.tf
bootstrap/outputs.tf
budget.tf
bootstrap/README.md
```

Create nothing else. In particular **do not** create `modules/` — Phase 1 does that.

---

## Specification

### 0.1 `.gitignore` — at `terraform/.gitignore`, **not** the repository root

Git honours nested `.gitignore` files, so a file here covers everything under `terraform/` and
nothing outside it. That matters: the repository root also holds an unrelated assessment, and this
work must not change ignore rules that apply to it.

```gitignore
# Terraform
**/.terraform/*
*.tfstate
*.tfstate.*
*.tfplan
crash.log
crash.*.log

# Variable files may contain account IDs / CIDRs — never commit them
*.tfvars
*.tfvars.json
!*.tfvars.example

# Backend config carries the state bucket name
backend.hcl
!backend.hcl.example

# Local overrides
override.tf
override.tf.json
*_override.tf
*_override.tf.json
.terraformrc
terraform.rc

# Editor / OS
.DS_Store
.idea/
.vscode/
```

`.terraform.lock.hcl` is **deliberately absent** from this list — the dependency lock file must be
committed. It is what makes a colleague's `terraform init` resolve the same provider builds as
yours, and it carries checksums, not secrets.

### 0.2 `versions.tf`

Declare `required_version` and every provider, with the exact constraints from
`reference/version-pinning.md` §1. Include `hashicorp/time` — the eks module needs it and omitting
it is a common mistake.

Do **not** declare `helm` here — Phase 4 adds it together with its provider block, so that
`validate` passes in the interim. Do **not** declare `kubernetes` at all, in this or any later
phase: this stack has no `kubernetes` provider by design (ADR-6). Every Kubernetes object is
delivered through Helm.

```hcl
terraform {
  required_version = ">= 1.11.0"   # S3-native state locking (use_lockfile) needs >= 1.10

  required_providers {
    aws  = { source = "hashicorp/aws",  version = "~> 6.58" }
    tls  = { source = "hashicorp/tls",  version = "~> 4.3"  }  # transitive: eks module
    time = { source = "hashicorp/time", version = "~> 0.14" }  # transitive: eks module
  }
}
```

### 0.3 `backend.tf` + `backend.hcl.example`

**Partial backend configuration.** The bucket name embeds an AWS account ID, so it must not be
committed; it is supplied at `init` time.

```hcl
# backend.tf
terraform {
  backend "s3" {
    # Supplied at init:  terraform init -backend-config=backend.hcl
    #   bucket, kms_key_id
    key          = "eks-karpenter/terraform.tfstate"
    encrypt      = true
    use_lockfile = true # S3 conditional-write locking. No DynamoDB table required.
  }
}
```

```hcl
# backend.hcl.example  — copy to backend.hcl and fill in from the bootstrap outputs
bucket     = "opsfleet-poc-tfstate-123456789012"
region     = "us-east-1"
kms_key_id = "arn:aws:kms:us-east-1:123456789012:key/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
```

`region` lives in `backend.hcl`, not `backend.tf`: backend blocks cannot reference variables, and
hardcoding a region in a committed file contradicts `var.region`.

Add a comment in `backend.tf` telling the reader they can comment the whole block out to run with
local state — the Phase 7 README will explain that path for reviewers who do not want to bootstrap.

### 0.4 `providers.tf`

AWS provider only, at this phase.

```hcl
provider "aws" {
  region = var.region

  default_tags {
    tags = local.tags
  }
}
```

Do **not** add a `helm` provider block. It references `module.eks`, which does not exist until
Phase 2, and its presence would break `terraform validate` for two phases — Phase 4 adds it.

There is **no `kubernetes` provider** in this stack, ever. See ADR-6.

### 0.5 `locals.tf`

Exactly as specified in interface-contract §2.1 and §2.2 — `local.name` and `local.tags`, nothing
else yet.

### 0.6 `variables.tf`

Every variable in interface-contract §3, in that order, grouped by the same headings, each with a
`description` and `type`. Add `validation` blocks for:

| Variable | Rule | Why |
|---|---|---|
| `project_name` | `can(regex("^[a-z][a-z0-9-]{1,20}$", var.project_name))` | Feeds resource names and the cluster name. |
| `environment` | `contains(["poc","dev","staging","prod"], var.environment)` | Keeps the name prefix predictable. |
| `region` | `can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.region))` | Catches typos before a 15-minute apply. |
| `vpc_cidr` | `can(cidrhost(var.vpc_cidr, 0))` **and** `tonumber(split("/", var.vpc_cidr)[1]) <= 18` | The subnet plan needs room. At /20 the computed intra subnets are /28 — only 11 usable IPs, against AWS's ≥6 requirement and ≥16 recommendation for cluster subnets. /18 gives /26 intra subnets. |
| `az_count` | `var.az_count >= 2 && var.az_count <= 3` | |
| `kubernetes_version` | `can(regex("^1\\.(3[0-9]|[4-9][0-9])$", var.kubernetes_version))` | |
| `cluster_endpoint_public_access_cidrs` | **See below — this one is a security control, not a typo check.** | |
| `nodepool_capacity_types` | every element in `["spot","on-demand"]` | Karpenter rejects anything else. |

The endpoint-CIDR validation is the single most important line in this file:

```hcl
variable "cluster_endpoint_public_access_cidrs" {
  description = <<-EOT
    CIDRs allowed to reach the public Kubernetes API endpoint. Required (and must be
    non-empty) when cluster_endpoint_public_access is true. 0.0.0.0/0 is rejected: an
    internet-open API endpoint is the most commonly flagged EKS misconfiguration, and
    IAM authentication is not a substitute for network scoping.
  EOT
  type        = list(string)
  default     = []

  validation {
    condition     = !contains(var.cluster_endpoint_public_access_cidrs, "0.0.0.0/0")
    error_message = "0.0.0.0/0 is not allowed. Set your own /32, or use cluster_endpoint_public_access = false."
  }
}
```

Add a **cross-variable** check (Terraform supports referencing other variables inside `validation`
as of 1.9) so public access cannot be enabled with an empty allowlist:

```hcl
variable "cluster_endpoint_public_access" {
  description = "Enable the public Kubernetes API endpoint. Private access is always on."
  type        = bool
  default     = true

  validation {
    condition     = !var.cluster_endpoint_public_access || length(var.cluster_endpoint_public_access_cidrs) > 0
    error_message = "cluster_endpoint_public_access_cidrs must be non-empty when public access is enabled."
  }
}
```

If your Terraform version rejects the cross-reference, fall back to a `check` block or a `precondition`
in Phase 2 and note the deviation.

### 0.6b `tests/cidr_guard.tftest.hcl` — prove the guard works

S-04 is the only security control this phase implements, so it gets a real negative test rather than
a grep. Terraform's native test framework runs this with **no AWS credentials** and **no real API
calls**, because `mock_provider` stubs the provider out.

```hcl
mock_provider "aws" {}

# The guard must REJECT an internet-open endpoint.
run "rejects_open_endpoint" {
  command = plan
  variables {
    cluster_endpoint_public_access       = true
    cluster_endpoint_public_access_cidrs = ["0.0.0.0/0"]
  }
  expect_failures = [var.cluster_endpoint_public_access_cidrs]
}

# The guard must REJECT public access with an empty allowlist.
run "rejects_empty_allowlist" {
  command = plan
  variables {
    cluster_endpoint_public_access       = true
    cluster_endpoint_public_access_cidrs = []
  }
  expect_failures = [var.cluster_endpoint_public_access]
}

# ...and must ACCEPT a scoped allowlist. Without this run the test would pass
# even if the variable rejected everything, which is the classic missing
# negative control.
run "accepts_scoped_allowlist" {
  command = plan
  variables {
    cluster_endpoint_public_access       = true
    cluster_endpoint_public_access_cidrs = ["203.0.113.10/32"]  # RFC 5737 doc range
  }
}
```

**Why this matters beyond Phase 0:** every later phase that "asserts" a security control with a
shell one-liner should be read with the same suspicion. A check that cannot fail is worse than no
check, because it prints PASS.

### 0.7 `terraform.tfvars.example`

Committed, and it must be honest: two clearly-labelled blocks, one production-shaped and one
POC-cheap, with the monthly cost delta in comments. Copy the figures from
`00-architecture-and-decisions.md` §5. Leave `cluster_endpoint_public_access_cidrs` as an obvious
placeholder (`["203.0.113.10/32"] # <-- your public IP: curl -s https://checkip.amazonaws.com`) so
nobody applies it unchanged.

### 0.7b `budget.tf` — the only automated cost guard in the stack

Cost Optimization is a Well-Architected pillar, and for a POC the most likely real incident is not a
breach — it is a cluster someone forgot to destroy. `terraform destroy` is a manual control; this is
the automated one.

```hcl
resource "aws_budgets_budget" "monthly" {
  count = var.enable_budget_alarm ? 1 : 0

  name         = "${local.name}-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  # Scope to THIS stack's resources, not the whole account. Requires the cost
  # allocation tags to have been activated in Billing — see the note below.
  cost_filter {
    name   = "TagKeyValue"
    values = ["user:Project$${var.project_name}"]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_notification_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"   # warns BEFORE you spend it
    subscriber_email_addresses = [var.budget_notification_email]
  }
}
```

Add a `validation` on `budget_notification_email` requiring a non-empty value when
`enable_budget_alarm` is true — a budget with no subscriber is silent, which is worse than none
because it looks like a control.

Two things to document in the README rather than pretend Terraform handles:

1. **Cost allocation tags must be activated in Billing** before `Project`/`Environment` work as a
   budget filter or a Cost Explorer dimension. It is a one-time per-account step
   (`aws ce update-cost-allocation-tags-status`, or the Billing console) and it can take up to 24
   hours to take effect. Until then the filter matches nothing.
2. **Karpenter-launched instances only carry these tags because Phase 5 puts them in
   `EC2NodeClass.spec.tags`.** The provider's `default_tags` never sees them.

### 0.8 `main.tf` and `outputs.tf`

Header comment only. Something like:

```hcl
# Root composition. Module blocks only — no resources.
# Phase 1 adds module.network, Phase 2 module.eks, Phases 3-4 module.karpenter,
# Phase 5 module.karpenter_resources.
```

### 0.9 `bootstrap/` — the state backend

A standalone root module with **local state** (it cannot store its state in the bucket it creates).
Applied once, by hand. It must be safe to run in an account that already has it.

Resources:

| Resource | Configuration |
|---|---|
| `aws_kms_key` | `description`, `enable_key_rotation = true`, `deletion_window_in_days = 30` |
| `aws_kms_alias` | `alias/${var.project_name}-${var.environment}-tfstate` |
| `aws_s3_bucket` | name `${project}-${env}-tfstate-${account_id}` via `data.aws_caller_identity` |
| `aws_s3_bucket_versioning` | `Enabled` — this is the state recovery mechanism; without it a corrupt write is unrecoverable |
| `aws_s3_bucket_server_side_encryption_configuration` | `aws:kms` with the CMK above, `bucket_key_enabled = true` (cuts KMS request cost ~99%) |
| `aws_s3_bucket_public_access_block` | all four settings `true` |
| `aws_s3_bucket_ownership_controls` | `BucketOwnerEnforced` — disables ACLs entirely |
| `aws_s3_bucket_lifecycle_configuration` | expire noncurrent versions after 90 days; abort incomplete multipart uploads after 7 days |
| `aws_s3_bucket_policy` | deny any request where `aws:SecureTransport = false`; deny `s3:PutObject` without `s3:x-amz-server-side-encryption = aws:kms` |

A note the agent must include as a comment in `main.tf`: **do not** add
`aws_s3_bucket_logging` pointing at the same bucket — self-logging a state bucket creates unbounded
recursive writes. If access logging is wanted, target a separate bucket.

Outputs: `state_bucket_name`, `state_bucket_arn`, `kms_key_arn`, and `backend_config` — a rendered,
copy-pasteable `backend.hcl` body, so the operator does not have to assemble it by hand.

`bootstrap/README.md` documents the three commands: apply it, copy the outputs into `backend.hcl`,
then `terraform init -backend-config=backend.hcl` in the parent directory.

---

## Security requirements owned by this phase

From [`contracts/security-checklist.md`](../contracts/security-checklist.md):

- **S-01** State bucket: versioning, KMS CMK with rotation, full public-access block, TLS-only
  bucket policy, ACLs disabled.
- **S-02** No secrets in committed files. `.gitignore` covers `*.tfvars` and `backend.hcl`.
- **S-03** Every provider and module pinned; `.terraform.lock.hcl` committed.
- **S-04** `0.0.0.0/0` on the API endpoint is rejected by a `validation` block, not by convention.

---

## Acceptance criteria

Run from the repo root. All must pass with **no AWS credentials**:

```bash
terraform fmt -check -recursive          # exit 0
terraform init -backend=false            # succeeds
terraform validate                       # "Success! The configuration is valid."

terraform -chdir=bootstrap fmt -check -recursive
terraform -chdir=bootstrap init -backend=false
terraform -chdir=bootstrap validate
```

Then these behavioural checks:

```bash
# 1. The 0.0.0.0/0 guard actually fires — via `terraform test`, NOT `validate`.
#
#    `terraform validate` accepts -var-file but does NOT evaluate variable
#    validation blocks against supplied values: it prints "Success!" and exits 0.
#    A check built on it can never fail, which would leave S-04 — the only
#    security control this phase implements — completely untested while printing
#    PASS. Variable validation is only exercised at plan time.
#
#    `terraform test` with a mocked provider runs the plan with no AWS
#    credentials and no real API calls.
terraform test

# 2. The gitignore covers the sensitive filenames. (This repo may not be a git
#    repo yet — check the patterns directly rather than shelling out to git,
#    and never run git commands against the repository root.)
for p in '*.tfvars' 'backend.hcl' '*.tfstate' '.terraform'; do
  grep -qF "$p" .gitignore && echo "PASS: .gitignore covers $p" || echo "FAIL: missing $p"
done
grep -q '!\*.tfvars.example' .gitignore && echo "PASS: example tfvars still tracked"
grep -q '\.terraform\.lock\.hcl' .gitignore && echo "FAIL: lock file must NOT be ignored"

# 3. Every variable has a description.
[ "$(grep -c '^variable ' variables.tf)" = "$(grep -c '  description' variables.tf)" ] \
  && echo "PASS: every variable documented"
```

**Do not run `terraform apply`.** The bootstrap stack is applied by the operator, not by you.

---

## Notes for the implementing agent

- `terraform validate` on a stack with zero resources is expected to pass; that is the point.
- Resist adding `modules/` stubs "to be helpful". An empty module directory makes Phase 1's diff
  unreadable and `validate` will complain about modules with no configuration.
- Do not set `region` inside `backend.tf`. Backend blocks cannot use variables, and a second
  hardcoded region is exactly the kind of drift that bites six months later.

---

## Agent prompt

```text
Implement Phase 0 of the EKS + Karpenter Terraform assessment.

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
  1. docs/00-architecture-and-decisions.md      (context and decisions)
  2. docs/contracts/interface-contract.md       (NORMATIVE — exact names)
  3. docs/reference/version-pinning.md          (exact versions — never recall from memory)
  4. docs/phases/phase-00-scaffold-and-state.md (your specification)

Implement exactly the files listed under "Files to create" in phase-00. Create nothing else —
in particular do not create modules/, and do not add a helm provider
blocks (Phase 4 adds those).

Constraints:
  - Take every version number from reference/version-pinning.md. Do not use remembered versions.
  - Take every variable and output name from contracts/interface-contract.md verbatim.
  - Every variable needs a description and a type. Add the validation blocks the phase doc lists.
  - terraform fmt -recursive must be clean.
  - Do NOT run `terraform apply`. There are no AWS credentials in this environment.

When finished, run the commands under "Acceptance criteria", then fill in the
"## Completion report" section at the bottom of docs/phases/phase-00-scaffold-and-state.md
and stop. Do not start Phase 1.
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
