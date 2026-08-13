# Phase 11 *(optional)* — CI/CD and policy scanning

**Depends on:** Phase 0 (can run any time after).
**Status:** optional. Implement only when explicitly asked.

---

## Goal

Automated quality and security gates: formatting, validation, linting and policy scanning on every
change, plus pre-commit hooks so problems are caught before they reach CI. Authentication to AWS via
OIDC federation, never long-lived keys.

---

## ⚠️ A scope conflict you must handle, not ignore

GitHub Actions only executes workflows at **`.github/workflows/` in the repository root**. The
repository root is shared with an unrelated assessment, and this work is scoped strictly to
`terraform/` — so **this phase must not create `.github/` at the root.**

The resolution: ship the workflow as a ready-to-install artefact inside `terraform/`, with clear
instructions for the repository owner to place it.

```
terraform/ci/terraform-ci.yml          # the workflow, complete and correct
terraform/ci/README.md                 # says exactly where to copy it and why it is not there
terraform/.pre-commit-config.yaml      # works from terraform/ as-is
```

`ci/README.md` must state plainly:

> This workflow is **not installed**. To activate it, the repository owner copies
> `terraform/ci/terraform-ci.yml` to `.github/workflows/terraform-ci.yml` at the repository root.
> It is not placed there by this assessment because the repository root is shared with an unrelated
> submission and this work is scoped to `terraform/`.

Do not pretend the workflow is live. A CI badge for a workflow that does not run is worse than no
badge.

Pre-commit is different: `pre-commit` accepts `--config`, so
`pre-commit run --config terraform/.pre-commit-config.yaml --all-files` works without touching the
root.

---

## Files to create

```
ci/terraform-ci.yml
ci/README.md
.pre-commit-config.yaml
.tflint.hcl
```

---

## Specification

### 11.1 The workflow

Trigger on pull requests and pushes that touch `terraform/**`. Set `defaults.run.working-directory: terraform`
so every step is scoped, and set `paths: ['terraform/**']` so changes to the other assessment never
trigger this job.

Jobs:

| Job | Does | Fails the build on |
|---|---|---|
| `fmt` | `terraform fmt -check -recursive` | any unformatted file |
| `validate` | `terraform init -backend=false` then `terraform validate`, for the root **and** `bootstrap/` | invalid config |
| `lint` | `tflint --init && tflint --recursive` | tflint errors |
| `scan` | `checkov` and `trivy config` | HIGH/CRITICAL findings |
| `docs` | `terraform-docs` in check mode | module docs out of date |
| `plan` *(PR only)* | `terraform plan -no-color` posted as a PR comment | plan errors |

Pin every action to a **commit SHA**, not a tag — a mutable tag on a third-party action is a supply
chain risk, and this is a security-focused deliverable:

```yaml
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683  # v4.2.2
```

### 11.2 AWS authentication — OIDC, never keys

The `plan` job needs AWS credentials. Use GitHub's OIDC provider with a role assumed by federation.
**Never** `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` in repository secrets.

```yaml
    permissions:
      id-token: write        # required for OIDC
      contents: read
      pull-requests: write   # to comment the plan
    steps:
      - uses: aws-actions/configure-aws-credentials@<SHA>
        with:
          role-to-assume: ${{ secrets.AWS_PLAN_ROLE_ARN }}
          aws-region: us-east-1
```

Document in `ci/README.md` that the role's trust policy must restrict `token.actions.githubusercontent.com`
by **both** `aud` (`sts.amazonaws.com`) and `sub` (`repo:<org>/<repo>:*`, ideally narrowed to a
branch or environment). A trust policy with a wildcard `sub` lets **any** GitHub repository assume
the role — a well-known and severe misconfiguration.

The plan role should be **read-only**: `ReadOnlyAccess` plus state-bucket read. Do not give CI apply
rights for a POC.

### 11.3 `.tflint.hcl`

```hcl
plugin "terraform" { enabled = true, preset = "recommended" }
plugin "aws" {
  enabled = true
  version = "<pin>"                     # check github.com/terraform-linters/tflint-ruleset-aws
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}
```

Enable the naming-convention, unused-declarations, typed-variables and documented-variables rules.

### 11.4 `.pre-commit-config.yaml`

Hooks from `antonbabenko/pre-commit-terraform`, pinned by `rev`:
`terraform_fmt`, `terraform_validate`, `terraform_tflint`, `terraform_docs`, `terraform_checkov`.
Plus `detect-private-key` and `check-merge-conflict` from `pre-commit-hooks`.

Scope every hook with `files: ^terraform/` if the config is ever moved to the root.

### 11.5 Triage the scanner output — do not just add it

Running checkov on a real EKS module produces dozens of findings, many irrelevant. Part of this
phase is deciding which matter.

For each finding, either fix it or suppress it **with a stated reason**:

```hcl
# checkov:skip=CKV_AWS_79:IMDSv2 is enforced via metadata_options; this check
# misfires on the module's internal launch template.
```

A blanket `--skip-check` list with no rationale is worse than not scanning. Record the triage in
`ci/README.md` as a short table: check ID → fixed / accepted (why) / false positive (why).

---

## Security requirements owned by this phase

- **S-93** CI runs `fmt`, `validate`, `tflint` and a policy scanner on every change to `terraform/**`,
  and fails the build on HIGH/CRITICAL findings.
- **S-94** AWS authentication is OIDC federation with a `sub`-restricted trust policy. No long-lived
  keys in repository secrets.
- Third-party actions pinned to commit SHAs.
- The CI role is read-only; CI cannot apply.

---

## Acceptance criteria

```bash
# Workflow is valid YAML and correctly scoped
python3 -c "import yaml,sys; d=yaml.safe_load(open('ci/terraform-ci.yml')); print(sorted(d['jobs']))"
grep -q 'working-directory: terraform' ci/terraform-ci.yml && echo "PASS: scoped to terraform/"
grep -q "terraform/\*\*" ci/terraform-ci.yml && echo "PASS: path filter"

# No long-lived credentials anywhere
grep -nE 'AWS_SECRET_ACCESS_KEY|AWS_ACCESS_KEY_ID' ci/terraform-ci.yml && echo "FAIL" || echo "PASS: OIDC only"
grep -q 'id-token: write' ci/terraform-ci.yml && echo "PASS: OIDC permission"

# Actions pinned to SHAs, not tags
grep -oP 'uses: \K\S+' ci/terraform-ci.yml | grep -v '@[0-9a-f]\{40\}' && echo "FAIL: unpinned action" || echo "PASS: all pinned"

# Nothing was created at the repository root
[ -d ../.github ] && echo "FAIL: created .github at repo root" || echo "PASS: root untouched"

# The tools actually pass
terraform fmt -check -recursive
tflint --init && tflint --recursive
checkov -d . --framework terraform --compact
pre-commit run --config .pre-commit-config.yaml --all-files
```

---

## Agent prompt

```text
Implement Phase 11 (OPTIONAL) of the EKS + Karpenter Terraform assessment.

Working directory: /home/artin/personal/git/opsfleet/terraform

SCOPE BOUNDARY — non-negotiable, applies to every action you take:
  1. Your working directory is /home/artin/personal/git/opsfleet/terraform. You never leave it.
     Every path in this prompt and in every doc it references is RELATIVE TO THAT DIRECTORY.
  2. The sibling directory /home/artin/personal/git/opsfleet/architecture is a DIFFERENT,
     UNRELATED assessment. Do not read it, write to it, list it, grep it, or cd into it.
  3. Create NOTHING at the repository root. In particular do NOT create .github/ at the root,
     even though that is where GitHub Actions workflows normally live — phase-11 §"scope
     conflict" explains how to handle that, and you must follow it.
  4. Do not run repo-wide searches. Scope every search to terraform/.

Read: docs/phases/phase-11-optional-cicd.md (your specification), then
      docs/contracts/security-checklist.md (S-93, S-94).

Create ci/terraform-ci.yml, ci/README.md, .pre-commit-config.yaml and .tflint.hcl,
all under terraform/.

Critical constraints:
  - The workflow is shipped as an artefact under terraform/ci/, NOT installed at the repo root.
    ci/README.md must say plainly that it is not active and exactly where to copy it.
  - AWS auth is OIDC only. No AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY anywhere. Document the
    sub-restricted trust policy requirement.
  - Pin every third-party action to a 40-character commit SHA with the version in a comment.
  - The CI role must be read-only. CI does not apply.
  - Actually RUN the scanners, then TRIAGE the findings: fix, or suppress with a written
    reason. Record the triage as a table in ci/README.md. A blanket skip list is not acceptable.

When finished, fill in the "## Completion report" at the bottom of
docs/phases/phase-11-optional-cicd.md and stop.
```

---

## Completion report

- Status:
- Files created/changed:
- **Confirm nothing was created at the repository root:**
- **Scanner triage table** (or where it lives):
- Deviations from spec:
- Notes:
