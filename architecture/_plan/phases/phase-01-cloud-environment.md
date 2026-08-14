# Phase 01 — Cloud Environment Structure

> Answers **assessment area 1** and requirements **R1, R2**.
> Read [`../AGENT-PROTOCOL.md`](../AGENT-PROTOCOL.md), [`../brief.md`](../brief.md),
> [`../contract.md`](../contract.md), [`../decision-register.md`](../decision-register.md),
> [`../well-architected.md`](../well-architected.md), and [`../style-guide.md`](../style-guide.md)
> first.

---

## Goal

Answer the client's first question completely: **how many AWS accounts, what is each one for, and
why is that the right number?** The brief asks specifically for justification against *isolation*,
*billing*, and *management* — the answer must address all three explicitly, not implicitly.

This is the section most candidates under-write. "Use separate accounts per environment" is the
obvious answer; the value is in the argument, the guardrails, and the honest accounting of what the
structure costs a small team.

---

## Dependencies

Phase 00 must be `done`.

## Inputs

| File | Use it for |
|---|---|
| `_plan/contract.md` **§4** | The locked account list, OU tree, and SCP list — **copy exactly** |
| `_plan/contract.md` §1, §2, §3 | Locked decisions, naming convention, regions |
| `_plan/drafts/00-scope.md` | Assumptions you may rely on (read, do not edit) |
| `_plan/decision-register.md` | ADR template and your reserved ADR block |
| `_plan/well-architected.md` | Pillar tagging convention and what each pillar demands |
| `_plan/style-guide.md` | Voice, tables, callouts |
| `_plan/rubric.md` §2.B, §3 probe 7 | What "strong justification" looks like |

## Files you own

- `_plan/drafts/01-cloud-environment.md` — create
- `_plan/STATE.md` — update
- `_plan/contract.md` §12 — append only if you invent a name

## Word budget

**~1 300 words** (±20%) for the body, excluding tables, plus **3 ADRs** (ADR-004 – ADR-006).

## Two requirements that apply to every section you write

1. **Pillar line.** Every `##` section closes its opening paragraph with
   `> **Well-Architected pillars.** …` carrying 2–4 pillars. See `well-architected.md` §2.
2. **Justification.** Inline, every decision follows decision → why → what it beat → what it costs.
   Then the significant ones are recorded again as ADRs at the end of the draft. See
   `decision-register.md`.

---

## Content specification

Write exactly these sections, in order, each `##`. Phase 11 will renumber them into the final
document as `## 1. Cloud Environment Structure` with `###` subsections — so use `##` here and it will
be demoted during assembly.

### `## Recommendation in one line`

One sentence: seven AWS accounts at launch inside a single AWS Organization managed by AWS Control
Tower, organised into four organizational units, growing to nine as the team does. Then one sentence
on why seven rather than one or twenty.

### `## Why multiple accounts` (~300 words) — **this is the graded paragraph**

Build the argument on the three axes the brief names. Give each its own short paragraph or a table
row with real substance:

1. **Isolation.** The AWS account is the *only* boundary that simultaneously bounds IAM, service
   quotas, and the blast radius of a mistake. Contrast with the alternatives the client might expect:
   separate VPCs in one account (shares IAM, shares quotas — a wildcard policy still reaches
   production), and separate Kubernetes namespaces (shares the cluster control plane, the node fleet,
   and the cluster's IAM role). Make the concrete point: **a compromised or careless credential in
   `innovate-dev` has no path to production data**, and that property does not depend on anyone
   writing a correct IAM policy in the future. For a company holding sensitive user data, that is the
   whole argument.
2. **Billing.** Consolidated billing at the management account with per-account cost attribution
   gives unambiguous answers to "what does production cost?" without depending on tag hygiene.
   Tagging still matters (see `contract.md` §9 mandatory tags) but accounts give a floor of accuracy
   that tags never do. Note also: Reserved Instances and Savings Plans purchased in the management
   account apply organization-wide, so account separation does not fragment commitment discounts.
3. **Management.** SCPs applied at the OU level let the guardrails differ by risk tier — production
   can forbid what development permits. Service quotas (EKS clusters, EC2 vCPUs, Elastic IPs, VPCs)
   are per-account, so a runaway load test in dev cannot exhaust production's headroom. Blast radius
   of an IaC mistake is bounded by the account the pipeline role can reach.

Also name the **audit and compliance** benefit: separation of duties for SOC 2, an immutable log sink
no workload account can write to or delete from.

> **Trade-off.** Use the callout to be honest: more accounts means more baseline cost (each account
> pays for its own GuardDuty, Config, and VPC endpoints — roughly $25–60/month), more Terraform
> state files, and a hard requirement that access be centralised through IAM Identity Center from day
> one, because per-account IAM users would be unmanageable. This is why the answer is seven and not
> twenty.

### `## Account inventory` (~250 words + table)

Reproduce the **exact** table from `contract.md` §4 — all nine rows, including the two marked
"later". Columns: Account | OU | Purpose | Day 1?

Then 3–5 short paragraphs expanding the non-obvious ones — do not restate the table:

- **Management account:** why it holds *nothing* but Organizations, Control Tower, billing, and the
  Identity Center directory. Root credentials locked with hardware MFA, break-glass procedure only.
- **Log Archive:** why the log sink is a separate account with S3 Object Lock — an attacker who owns
  production still cannot delete the evidence. This is the control that makes the audit trail
  trustworthy.
- **Security Tooling:** delegated administrator for GuardDuty, Security Hub, Detective, Inspector,
  Macie, and IAM Access Analyzer, with read-only cross-account roles. Findings from every account
  land in one place.
- **Shared Services:** why ECR, CI/CD identity, Route 53, and Terraform state live here rather than
  in each workload account — an image is built once and promoted by digest into three environments;
  duplicating the registry per environment would mean rebuilding per environment, which breaks the
  guarantee that what was tested is what ships.
- **Dev / Staging / Prod:** why staging is a separate account rather than a namespace in prod, and
  the rule that **no production data ever enters non-production** (masked or synthetic seeds only).

### `## Organizational unit structure` (~150 words + diagram block)

Reproduce the OU tree from `contract.md` §4 as a fenced ```text``` block. Explain that SCPs attach to
OUs, not accounts, so moving an account between OUs changes its guardrails — which is how a sandbox
graduates or a decommissioned account gets frozen in `Suspended`.

### `## Guardrails — service control policies` (~200 words + table)

Table of the six SCP families from `contract.md` §4, columns: Guardrail | Applies to | What it
prevents. Then a paragraph making the key point: SCPs are **maximum permission boundaries**, not
grants — they cannot give access, only remove it, and they apply even to the account root user. That
is what makes them the right tool for "this must never happen anywhere".

Include one short illustrative snippet — a region-restriction SCP is the clearest example — capped at
20 lines of JSON.

### `## Identity and access` (~200 words)

- **AWS IAM Identity Center** in the management account, with an external IdP (Google Workspace,
  Okta, or Entra ID) as the identity source if the client already has one.
- Permission sets from `contract.md` §9, mapped to groups, assigned per account. Table:
  Permission set | Accounts | Purpose.
- No IAM users anywhere; humans get short-lived credentials via SSO, machines get roles.
- MFA mandatory. Production access is time-boxed and, once the team is large enough, gated behind an
  approval workflow.
- **Break-glass:** two sealed root-credential procedures with hardware MFA, alarmed on use.
- Answer rubric probe 9 here or point at Phase 02: how a developer's laptop reaches a private EKS API
  — Identity Center session → EKS access entry → `aws eks update-kubeconfig`, no bastion, no
  long-lived kubeconfig.

### `## Account provisioning and lifecycle` (~150 words)

Control Tower Account Factory (or AFT / Terraform) for new accounts so every account is born with the
same baseline: CloudTrail on, Config on, GuardDuty enabled, default EBS encryption, default VPC
deleted, tag policy applied, Terraform state bucket created. Mention the `Suspended` OU as the exit
path. One sentence on why a manual account creation is a defect, not a convenience.

---

## Depth probes this section must be able to survive

From `rubric.md` §3: probe 7 ("why not just one account and namespaces?") — answer it head-on in the
*Why multiple accounts* section. Probe 1 (image promotion across accounts) — you must at least
establish that the registry is central and cross-account pull is a solved thing; Phase 04 details it.

## Decision Records — ADR-004 to ADR-006

End the draft with `## Decision Records` containing 3 ADRs from your reserved block, using the
exact template in `decision-register.md`. They must cover:

- **ADR-004 — Multiple AWS accounts rather than a single account, and seven specifically.** Options:
  one account with VPC separation, one account with namespace separation, account-per-environment.
  Cover both halves — why separate at all, and why seven rather than three or fifteen. The marginal
  value of each additional account against its marginal baseline cost is the interesting reasoning.
  This is the most-graded decision in the section; the ADR carries the full argument and the body
  carries the narrative version, and the two must not be copy-pasted from each other.
- **ADR-005 — AWS Control Tower rather than hand-rolled AWS Organizations.** The alternative is
  genuinely reasonable for a team that wants full control of its guardrails, so argue it fairly.
- **ADR-006 — IAM Identity Center rather than IAM users per account.** Why this stops being optional
  the moment there is more than one account.

The **"Why this is the right choice for Innovate Inc."** field matters most on the multi-account
ADR. A founder will ask why one small application needs seven AWS accounts; that field is the
answer, and it should be framed around what a single mistake can and cannot reach.

---

## Acceptance criteria

- [ ] File is `_plan/drafts/01-cloud-environment.md`, 1 050–1 550 words excluding tables and ADRs.
- [ ] All seven `##` sections present, in order, each opening with prose and closing that opening
      paragraph with a pillar line carrying 2–4 pillars.
- [ ] `## Decision Records` present with 3 ADRs from ADR-004 – ADR-006, full template, no fields
      missing; each has a fairly-argued rejected alternative, a plain-language field a non-engineer
      can read without asking a question, a real *Accepts* downside, and an observable *Revisit when*
      trigger.
- [ ] The account inventory table matches `contract.md` §4 **exactly** — nine rows, same names, same
      purposes. No invented accounts, no renamed accounts.
- [ ] *Isolation*, *billing*, and *management* each get an explicit, substantive treatment — the
      words appear as the structure of the argument, not in passing.
- [ ] At least two alternatives are named and rejected with reasons (single account + VPC separation;
      namespace-only separation).
- [ ] The downside of the recommendation is stated in a `> **Trade-off.**` callout with a cost figure.
- [ ] The OU tree matches `contract.md` §4 exactly.
- [ ] At least six SCP guardrails listed, with one ≤20-line JSON example.
- [ ] Permission sets named exactly as in `contract.md` §9.
- [ ] No `TODO`/`TBD`; no banned words; no emoji; percentages written without a space.
- [ ] `STATE.md` updated with status `done` and a filled completion report.

## Common failure modes

| Failure | Avoid it by |
|---|---|
| Listing accounts without justifying the count | The count *is* the question. Half the words go to the argument. |
| Justifying with "AWS best practice says so" | Justify with what it prevents for *this* client's sensitive data. |
| Inventing an eighth day-1 account (e.g. a separate network or backup account) | `contract.md` §4 is locked. Backup vault lives in Log Archive; network splits out later. |
| Ignoring the cost of the structure | The trade-off callout is mandatory. |
| Designing the network here | VPCs are Phase 02. Stay at the account/identity layer. |
| Writing SCP JSON longer than 20 lines | One illustrative policy, not a policy library. |

---

## Agent prompt

```text
You are executing Phase 01 of the Innovate Inc. architecture design plan: Cloud Environment
Structure.

Working directory boundary: architecture/ ONLY. Never read or write
terraform/, .claude/, or anything above architecture/. terraform/ belongs to a
different assignment that another agent may be editing right now.

Read in full, in order:
  architecture/_plan/AGENT-PROTOCOL.md
  architecture/_plan/brief.md
  architecture/_plan/contract.md      (§4 is your primary source — copy it exactly)
  architecture/_plan/decision-register.md
  architecture/_plan/well-architected.md
  architecture/_plan/style-guide.md
  architecture/_plan/drafts/00-scope.md
  architecture/_plan/phases/phase-01-cloud-environment.md

Do not read any other file. No repository-wide searches. No aws/kubectl/terraform/docker/helm.
No web browsing.

Write architecture/_plan/drafts/01-cloud-environment.md following the content
End the draft with a ## Decision Records section containing ADR-004 through ADR-006, using the exact
template in decision-register.md. Every ADR needs: an options table with at least one genuinely
reasonable rejected alternative argued fairly; a "Why this is the right choice for Innovate Inc."
field written in plain language for a non-engineer founder; an Accepts list naming a real
downside; and a Revisit when field naming an observable trigger.

Close every ## section's opening paragraph with a > **Well-Architected pillars.** line carrying
two to four pillars.

specification exactly. Then verify every acceptance criterion line by line, fix what fails,
update STATE.md, report, and STOP. Do not begin Phase 02.
```
