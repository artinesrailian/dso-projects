# Phase 00 — Pre-flight, scope & three-tier framing

> Answers requirements **R16**, **R28**, and seeds **R26/R27** for every later phase.
> Read [`../AGENT-PROTOCOL.md`](../AGENT-PROTOCOL.md), [`../brief.md`](../brief.md),
> [`../contract.md`](../contract.md), [`../decision-register.md`](../decision-register.md),
> [`../well-architected.md`](../well-architected.md), and [`../style-guide.md`](../style-guide.md)
> first.

---

## Goal

Verify the working directory, then write the opening of the deliverable: what is being designed, for
whom, **as what kind of architecture**, under what assumptions, and how every requirement maps to a
section. At the end of this phase every later phase can start without re-deriving scope, and the
reviewer has a traceability table proving nothing was dropped.

This phase writes **no infrastructure design**. It writes the frame the design goes into — and the
frame includes the single structural decision the rest of the document hangs off: this is a
**three-tier architecture**.

---

## Dependencies

None. This is the first phase.

## Inputs

| File | Use it for |
|---|---|
| `_plan/brief.md` | The client's words and the R1–R28 requirements register |
| `../docs/assessment.md` | The original brief, if you want to confirm `brief.md` matches it |
| `_plan/contract.md` | §1 locked decisions, **§1a the three-tier model**, §3 regions |
| `_plan/decision-register.md` | ADR template; **your block is ADR-001 – ADR-003** |
| `_plan/well-architected.md` | Pillar tagging convention |
| `_plan/style-guide.md` | Voice and Markdown rules |

## Files you own

- `_plan/drafts/00-scope.md` — create
- `_plan/STATE.md` — update, including the ADR ledger
- `_plan/contract.md` §12 — append only if you invent a name

Nothing else. In particular you do **not** create `../README.md` — that is Phase 11.

## Word budget

**~900 words** (±20%) for the body, excluding tables, plus **3 ADRs** (ADR-001 – ADR-003).

---

## Step 1 — Pre-flight checks

Run exactly these checks. Do not explore beyond them.

1. **Confirm the plan directory is intact.** These must all exist: `_plan/README.md`,
   `_plan/AGENT-PROTOCOL.md`, `_plan/STATE.md`, `_plan/brief.md`, `_plan/contract.md`,
   `_plan/decision-register.md`, `_plan/well-architected.md`, `_plan/style-guide.md`,
   `_plan/rubric.md`, and `_plan/phases/` with 14 files (phase-00 through phase-13). If any is
   missing, stop and report.
2. **Confirm `../docs/assessment.md` exists** and that its four assessment areas match the ones
   listed in `brief.md`. If they differ in substance, stop and report — the assessment file is the
   authority and a divergence means the plan is built on the wrong requirements.
3. **Confirm the output directories exist**, creating them only if absent: `_plan/drafts/` and
   `../diagrams/`.
4. **Confirm `../README.md` does not already exist.** If it does, a prior run got further than
   `STATE.md` claims — stop and report rather than overwriting.

A single `ls` scoped to `architecture/` is sufficient. Do not run repository-wide searches, and do
not look at `terraform/`.

---

## Step 2 — Write `_plan/drafts/00-scope.md`

Exactly these sections, in order, each starting with `##`. Every `##` section closes its opening
paragraph with a `> **Well-Architected pillars.**` line — except the executive summary marker and the
traceability table, which have none.

### `## Executive Summary` — **leave a marker, do not write it**

Write only this line:

```text
<!-- EXEC-SUMMARY: written in Phase 12 after all sections exist. Do not fill here. -->
```

**Rationale:** a summary written before the content it summarises is always wrong. Phase 12 writes it
from the finished document.

### `## 1. Scope and Objectives` (~250 words)

- One paragraph naming Innovate Inc., the application (Python/Flask REST API, React single-page
  application, PostgreSQL), and the four characteristics that drive every decision in the document:
  growth from a few hundred to potentially millions of users, sensitive user data, a small team with
  limited cloud experience, and a CI/CD-first delivery model. Every later section justifies itself
  against one of these four, so state them as the design's evaluation criteria, not as background.
- One paragraph on the cloud decision: **AWS**, with the reason in two sentences. GCP is a legitimate
  alternative and saying so plainly is more credible than pretending otherwise — but no more than two
  sentences, and the full reasoning goes in ADR-001.
- The guiding principle, stated as the design's thesis: **managed services first**, because the
  constraint that binds hardest here is not money, it is a small team's operational capacity.
  Every hour spent operating a database or a CI runner is an hour not spent on the product.

### `## 2. Architecture Overview — a three-tier design` (~250 words + table)

**The structural section.** The entire document is organised around this model, so establish it
properly here rather than mentioning it in passing.

- Introduce the three tiers by name — **presentation**, **application**, **data** — and reproduce the
  tier table from `contract.md` §1a exactly: what each contains, what it runs on, where it sits in
  the network, and how it scales.
- Then the three load-bearing properties from `contract.md` §1a, each given a sentence or two of
  explanation rather than just listed:
  1. **Each tier is reachable only from the tier above it**, enforced by security-group references
     rather than by convention or CIDR ranges.
  2. **The tier boundary is the security boundary** — subnet tier, route table, security group, and
     Kubernetes NetworkPolicy all align to the same three lines, so there is one model to reason
     about instead of four overlapping ones. Say why that matters for a team with limited cloud
     experience: a simple model is one they can hold in their heads and therefore one they will not
     misconfigure.
  3. **Each tier scales independently, by a different mechanism** — which is the entire point of the
     separation, and why a traffic spike can be absorbed at the edge without the application tier
     noticing.
- Close with why a three-tier model is the right choice *here* rather than a set of microservices:
  the application is one API and one worker, the team is small, and premature decomposition
  buys distributed-systems problems in exchange for organisational benefits a small team does
  not need yet. Note the door left open — the tiers scale independently, so extracting a service
  later is a change within the model, not a rewrite of it.

### `## 3. Design Principles` (~200 words + table)

Seven principles as a table (`Principle | What it means here`). Use exactly these — later phases
reference them:

| Principle | Meaning |
|---|---|
| Managed over self-hosted | Buy back the undifferentiated work; a small team should not run PostgreSQL failover |
| Isolate by account | The strongest boundary AWS enforces, and it costs almost nothing |
| Least privilege, mechanised | Deny-first guardrails, per-workload identities, no long-lived credentials — enforced by policy, not by review |
| Everything as code | Terraform for infrastructure, Git for cluster state; no console changes, so `git log` always answers "what changed" |
| Secure and cost-aware by construction | Security and cost are properties of each decision, not chapters appended at the end |
| Start simple, leave the door open | A day-1 footprint a small team can run; no choice that blocks the 100× version |
| Design for failure, then rehearse it | Multi-AZ by default, tested restores, explicit recovery objectives — an untested plan has an unknown recovery time |

Add one sentence after the table: where two principles conflict, the trade-off is stated explicitly
rather than resolved silently, and the accepted trade-offs are collected in §9.7.

### `## 4. Assumptions` (~200 words)

A numbered list of **10–12** assumptions, one sentence each. These protect the design from being
judged against unstated requirements. Include at least:

1. Primary user base and data residency are US-based at launch, driving `us-east-1`; an EU expansion
   path is reserved in the address plan but not built.
2. No existing AWS footprint — this is a greenfield landing zone.
3. A small, lean engineering team at launch — typical of a startup at this stage — with no dedicated
   site reliability or security staff.
4. Source control is GitHub; on GitLab or Bitbucket the CI mechanics change but the architecture does
   not.
5. Application code is stateless and can run as multiple replicas — a prerequisite this design assumes
   and the team must honour, since Spot capacity and rolling deployments both depend on it.
6. Sensitive data means personally identifiable information; no payment card data and no protected
   health information at launch, either of which would add specific controls noted where relevant.
7. No hybrid or on-premises connectivity requirement.
8. A single production region is acceptable at launch; cross-region is a disaster-recovery posture,
   not active-active.
9. Compliance target is SOC 2 readiness and GDPR alignment rather than a certified audit on day 1.
10. Budget tolerance is roughly four figures per month at launch, scaling with revenue.
11. The application can tolerate abrupt pod termination with graceful shutdown handling — required
    for Spot capacity.
12. Schema changes can follow an expand/contract pattern — required for zero-downtime deployment.

Close with one sentence: where an assumption proves wrong, the section it affects is noted, and no
part of the design depends on any of them being permanently true.

### `## 5. Out of Scope` (~120 words)

A short bulleted list, each with one clause of why. Include: application source code and schema
design; end-user authentication implementation (recommended, not designed); marketing and product
analytics; email and notification delivery; mobile clients; data warehouse and business
intelligence; active-active multi-region; formal compliance certification; capacity and load testing
plans; and the Terraform implementation itself — this is a design document, and the infrastructure
code follows from it.

### `## 6. Requirement Traceability`

Reproduce the R1–R28 table from `brief.md` with a fourth column, **`Answered in`**, naming the
section of the final document that satisfies it. Use these final section names:

| Final document section | Covers |
|---|---|
| §0 Scope, Assumptions and Design Principles | R28 |
| §1 Cloud Environment Structure | R1, R2 |
| §2 Network Design | R3, R4 |
| §3 Compute Platform | R5–R11, R23 |
| §4 Database | R12–R15 |
| §5 Security and Data Protection | R4, R21 |
| §6 Observability and Operations | R19 |
| §7 Cost Optimization | R22 |
| §8 Growth Roadmap | R20 |
| §9 Well-Architected Framework Alignment | R25, R27 |
| Executive Summary + diagrams | R17, R18, R24 |
| Appendix — Decision Records | R26 |
| Document location | R16 |

Add a closing sentence: every row is verified against the assembled document in Phase 13.

---

## Decision Records — ADR-001 to ADR-003

End the draft with `## Decision Records` containing exactly three ADRs, using the exact template in
`decision-register.md`:

- **ADR-001 — AWS as the cloud provider.** Options: AWS, Google Cloud Platform, multi-cloud. Give GCP
  a genuinely fair hearing — GKE Autopilot is less operational work than EKS, project-based isolation
  is simpler than AWS Organizations, and Cloud SQL is easier to reason about than Aurora. The reason
  to choose AWS is breadth of managed services at every stage of the growth curve, the depth of the
  security and governance tooling that a company handling sensitive data will need for SOC 2, and the
  size of the hiring pool for a startup that will need to recruit. Reject multi-cloud outright: for a
  small team it multiplies operational surface for a portability benefit they will never
  exercise.
- **ADR-002 — Three-tier architecture rather than microservices or a monolith on a single host.**
  Options: single-host monolith, three-tier, microservices from day one. The reasoning is team size
  against the benefit of independent scaling per tier.
- **ADR-003 — Managed services first.** Options: managed services, self-hosted on EC2, self-hosted in
  Kubernetes. The reasoning is that a small team's scarcest resource is attention, and that
  every self-hosted component converts a fixed monthly fee into an unbounded operational liability.

Remember the mandatory **"Why this is the right choice for Innovate Inc."** field in each: three to
five sentences, plain language, no unexplained acronyms, written for the founder paying the bill.
ADR-001 in particular will be read by a non-technical reader — explain it the way you would explain
choosing a bank.

---

## Decisions already made for you

Everything in `contract.md` §1, §1a, and §3. Do not re-open the AWS-versus-GCP question beyond the
two sentences in §1 and the reasoning in ADR-001. Do not choose regions — they are fixed. Do not
change the three-tier model.

## Acceptance criteria

- [ ] `_plan/drafts/00-scope.md` exists, 750–1 100 words excluding tables and ADRs.
- [ ] Exactly the seven `##` headings named above, in order.
- [ ] The `Executive Summary` section contains **only** the HTML-comment marker — no prose.
- [ ] §2 establishes the three-tier model with the tier table from `contract.md` §1a reproduced
      exactly, all three load-bearing properties explained, and the "why not microservices" argument.
- [ ] Every `##` section except the summary marker and the traceability table closes its opening
      paragraph with a pillar line carrying 2–4 pillars.
- [ ] Design principles table has all seven rows, worded as above.
- [ ] Assumptions are numbered, 10–12, each one sentence.
- [ ] The traceability table has all 28 rows (R1–R28) and every row names a section.
- [ ] The GCP discussion in §1 is two sentences or fewer; the full argument is in ADR-001.
- [ ] `## Decision Records` present with exactly ADR-001, ADR-002, ADR-003, full template, no fields
      missing.
- [ ] Each ADR's options table contains at least one genuinely reasonable rejected alternative,
      argued fairly.
- [ ] Each ADR's plain-language field is readable by a non-engineer; each *Accepts* list contains a
      real downside; each *Revisit when* names an observable trigger.
- [ ] No `TODO`, `TBD`, or placeholder text; no banned words; no emoji.
- [ ] `_plan/drafts/` and `../diagrams/` both exist.
- [ ] `_plan/STATE.md` shows Phase 00 `done`, next phase `01`, a filled completion report, and the
      ADR ledger row for Phase 00.

## Common failure modes

| Failure | Avoid it by |
|---|---|
| Writing the executive summary here | It is a marker only. Phase 12 writes it. |
| Writing architecture content | Scope and framing only. No VPCs, no clusters, no database design. |
| Treating the three-tier model as a passing mention | It is §2, with a table and an argument. The whole document hangs off it. |
| Assumptions that are actually requirements | "The app is stateless" is an assumption; "must handle millions of users" is a requirement. |
| A traceability table with vague targets like "throughout" | Every row names one section. |
| ADRs that strawman GCP | GCP is a good platform. Say what it does better, then say why AWS still wins here. |
| Exploring the repository for context | Your inputs are listed. Read them and write. |

---

## Agent prompt

```text
You are executing Phase 00 of the Innovate Inc. architecture design plan: Pre-flight, scope &
three-tier framing.

Working directory boundary: architecture/ ONLY. Never read or write terraform/, .claude/, or
anything above architecture/ — terraform/ belongs to a different assignment that another agent
may be editing right now.

Read these files in full, in this order:
  architecture/_plan/AGENT-PROTOCOL.md
  architecture/_plan/brief.md
  architecture/_plan/contract.md           (§1, §1a three-tier model, §3)
  architecture/_plan/decision-register.md  (your ADR block is 001-003)
  architecture/_plan/well-architected.md
  architecture/_plan/style-guide.md
  architecture/_plan/phases/phase-00-preflight-and-scope.md

You may also read architecture/docs/assessment.md to confirm the requirements match brief.md.

Do not read any other file. No repository-wide searches. No aws/kubectl/terraform/docker/helm.
No web browsing.

Run the four pre-flight checks, then produce architecture/_plan/drafts/00-scope.md following the
content specification exactly, ending with a ## Decision Records section containing ADR-001,
ADR-002, and ADR-003.

Section 2 establishes the three-tier model (presentation / application / data) that the entire
rest of the document is organised around — give it a table and a real argument, not a mention.

Then verify every acceptance criterion line by line, fix what fails, update STATE.md including the
ADR ledger, report, and STOP. Do not begin Phase 01.
```
