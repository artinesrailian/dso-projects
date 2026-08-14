# Phase 12 — Executive summary, decision register & appendices

> Completes the graded deliverable. Answers **R17, R24, R26** and closes **R18**.
> Read [`../AGENT-PROTOCOL.md`](../AGENT-PROTOCOL.md),
> [`../decision-register.md`](../decision-register.md), [`../style-guide.md`](../style-guide.md),
> and [`../brief.md`](../brief.md) first.

---

## Goal

Phase 11 built the body. This phase adds the four things that could only be written once the body
existed, and one of them — **Appendix B, the decision register** — is the artifact the client
specifically asked for: the reasoning behind every decision, in language they can follow.

1. The **executive summary**, with the High-Level Diagram, for a reader who may read nothing else.
2. The **Summary of Key Decisions** table, scannable in thirty seconds.
3. **Appendix B — Architecture Decision Records**, the 29 records collected from the drafts, ordered,
   completed, indexed, and with their section references converted to final chapter numbers.
4. **Appendices A, C, and D** — traceability, diagrams, glossary — plus the table of contents.

Your context is bounded: you read the assembled body plus the drafts' `## Decision Records` sections,
not the ten full drafts.

---

## Dependencies

Phase 11 must be `done` and `architecture/README.md` must contain chapters §0–§9 with its three
HTML-comment markers intact.

## Inputs

| File | Use it for |
|---|---|
| `../README.md` | The assembled body — your source for the summary and for final section numbers |
| `_plan/drafts/00-scope.md` … `08-cost.md` | **Only** the `## Decision Records` section of each |
| `_plan/drafts/00-scope.md` §6 | The R1–R28 traceability table |
| `_plan/decision-register.md` | The ADR template, for verifying every record is complete |
| `_plan/STATE.md` | The ADR ledger — which numbers should exist |
| `../diagrams/01-high-level.md`, `05-request-flow.md` | The two diagrams still to place |

## Files you own

- `../README.md` — edit (replace the markers, append sections 10 and the appendices)
- `_plan/STATE.md` — update

Do **not** edit the drafts or the diagram source files. Do **not** restructure chapters §0–§9 — if
you find a problem there, log it in `STATE.md` → *Cross-phase issues* and let Phase 13 fix it.

## Word budget

Roughly **1 200 words** of new prose (summary, key-decisions table, appendix introductions,
glossary), plus the ~5 500–7 500 words of collected decision records.

---

## Step 1 — Write the Executive Summary (~500 words)

Replace the `<!-- EXEC-SUMMARY: Phase 12 -->` marker with a `## Executive Summary` section, written
for a reader who may read nothing else — a founder, or a reviewer skimming.

1. **What this document is** — one sentence.
2. **The recommendation in one paragraph** — AWS, seven accounts, a three-tier design with the
   single-page application on CloudFront, the Flask API on Amazon EKS with Karpenter, and Aurora
   PostgreSQL, delivered by GitOps. Name the services plainly.
3. **The three tiers**, one sentence each, so the structural model is established before the diagram.
4. **`### High-Level Architecture`** — embed diagram 1 with its caption and legend, then
   `Source: [diagrams/01-high-level.md](diagrams/01-high-level.md)`.
5. **The six decisions that matter most**, as a table: Decision | Why | What it costs | ADR. Choose
   the six with the largest consequences — account separation, the three-tier structure, managed
   Kubernetes with Karpenter on Graviton and Spot, Aurora over RDS or self-managed, GitOps pull-based
   delivery, and the security baseline (immutable audit trail, no long-lived credentials). Link each
   to its Appendix B record.
6. **What it costs** — the indicative day-1 figure and the lean variant, one sentence each, clearly
   labelled indicative.
7. **How it grows** — two sentences: what stays the same from hundreds to millions of users
   (accounts, address plan, cluster topology, database engine) and what changes (replicas, caching,
   regions).
8. **What is deliberately not built yet** — one sentence naming multi-region active-active, a service
   mesh, and Shield Advanced, with the reason: complexity a small team cannot yet operate.

No jargon the document has not yet expanded. A non-engineer should finish this section knowing the
shape of the answer and why it was chosen. This is the single most-read part of the deliverable —
give it the time it deserves.

---

## Step 2 — Write §10, Summary of Key Decisions (~250 words + table)

Append `## 10. Summary of Key Decisions` after §9. One table, **20–26 rows**, scannable in thirty
seconds:

| # | Decision | Chosen | Alternative rejected | Primary reason | ADR |
|---|---|---|---|---|---|

Every row draws from a decision actually argued in the body. Rows that correspond to one of the 29
records link to it; rows for smaller decisions leave the ADR column as `—`. This is the mechanism
that makes the register's 29 records sufficient — **every** significant decision in the document
appears here, whether or not it earned a full record.

Cover at least: cloud provider, three-tier structure, account count, Control Tower, IAM Identity
Center, VPC-per-environment, three Availability Zones, per-AZ NAT, secondary pod CIDR, private EKS
endpoint, Karpenter over Cluster Autoscaler, Graviton-first, Spot for stateless workloads, central
ECR, GitOps over push CD, image signing at admission, SPA on S3 and CloudFront, Aurora over RDS,
Serverless v2, RDS Proxy, three-tier backups, pilot-light DR, customer-managed KMS keys, immutable
log archive, deferred service mesh, deferred commitment discounts.

Add one sentence above the table: it is a map, and the full reasoning for the consequential ones is
in Appendix B.

---

## Step 3 — Assemble Appendix B, the Decision Records

**The most important step in this phase.** Work carefully.

1. **Collect.** Open each of `drafts/00-scope.md` through `drafts/08-cost.md` and copy out its
   `## Decision Records` section. Nothing else from those files.
2. **Order** all records numerically, ADR-001 first.
3. **Check the numbering** against the ADR ledger in `STATE.md` and the allocation in
   `decision-register.md` §2. The register should run ADR-001 to ADR-029 with no gaps and no
   duplicates. If a number is missing, look for it in the owning phase's draft before concluding it
   was never written; if it genuinely does not exist, note it in `STATE.md` and flag it in your
   report rather than renumbering the others.
4. **Complete every record.** Verify each has every field of the template in `decision-register.md`:
   Status, Requirement, Pillars, Section, Context, Options considered, Decision, **Why this is the
   right choice for Innovate Inc.**, Consequences (Gains and Accepts), Cost impact, Revisit when. A
   record missing a field is incomplete — fill it from the body content rather than deleting the
   field.
5. **Convert the section references.** Drafts wrote the `Section` field by name
   (`Database → Disaster recovery`) because the final numbering did not exist yet. Replace each with
   the real chapter number from the assembled body (`§4.6 Disaster recovery`). Verify each points at
   a heading that actually exists.
6. **Write the appendix introduction** (~80 words): what an Architecture Decision Record is, and why
   this document includes them — so that a future engineer inheriting this system can find out not
   just what was built, but what was considered and rejected, and under what conditions each decision
   should be reopened.
7. **Build the index table** at the top of the appendix: `ADR | Title | Section | Pillars`. This is
   what makes 29 records scannable rather than a wall.

---

## Step 4 — Appendices A, C, D

- **`## Appendix A — Requirement Traceability`**: the R1–R28 table from `drafts/00-scope.md` §6 with
  the "Answered in" column updated to the **final** chapter numbers. Every row must point at a
  heading that exists in the assembled document. Verify each one; this table is the first thing a
  requirement-focused reviewer checks.
- **`## Appendix C — Diagrams`**: embed diagram 5 (request flow) with its caption and legend, then a
  table linking all five diagram source files with a one-line description each.
- **`## Appendix D — Glossary`**: 25–30 terms a founder with limited cloud experience would need, one
  plain sentence each — Availability Zone, VPC, CIDR block, subnet, NAT Gateway, security group, IAM,
  service control policy, KMS, Amazon EKS, pod, node, namespace, Horizontal Pod Autoscaler,
  Karpenter, Spot Instance, Graviton, container image, container registry, GitOps, canary deployment,
  Aurora, point-in-time recovery, RPO, RTO, WAF, SLO, three-tier architecture, Well-Architected
  Framework, Architecture Decision Record. Write them for someone who has never opened the AWS
  console — this appendix is what makes the rest of the document readable by the client.

---

## Step 5 — Table of contents

Replace the `<!-- TOC: Phase 12 -->` marker with a linked table of contents generated from the final
headings, `##` level only. Verify **every anchor resolves** against a heading that actually exists —
GitHub anchors lowercase the heading, strip punctuation, and replace spaces with hyphens.

---

## Acceptance criteria

- [ ] All three HTML-comment markers replaced; none survive in the document.
- [ ] Executive summary present, ~500 words, readable by a non-specialist, with the three-tier
      paragraph, the embedded HLD, and the six-decision table.
- [ ] §10 key-decisions table has 20–26 rows, each traceable to the body, ADR-linked where one exists.
- [ ] **Appendix B contains every ADR from every draft, in numeric order, ADR-001 to ADR-029, no gaps
      and no duplicates against the `STATE.md` ledger.**
- [ ] Every record complete against the template — no missing fields.
- [ ] Every `Section` field converted from a name to a real chapter number that exists.
- [ ] Appendix B has an introduction and an `ADR | Title | Section | Pillars` index table.
- [ ] Appendix A's 28 rows all point at real chapter numbers.
- [ ] Appendix C embeds diagram 5 and links all five sources.
- [ ] Appendix D has 25–30 terms, each in plain language.
- [ ] Table of contents present; every anchor resolves.
- [ ] Total document length 13 000–16 000 words including the register.
- [ ] Chapters §0–§9 unmodified except for the markers being replaced.
- [ ] Drafts and diagram source files unmodified.
- [ ] `STATE.md` updated with any missing or incomplete records found.

## Common failure modes

| Failure | Avoid it by |
|---|---|
| Reading the ten full drafts | You need only their `## Decision Records` sections plus the assembled body. |
| Renumbering ADRs to close a gap | A gap is a defect to report, not to hide. |
| Leaving `Section` fields as names | Step 3.5 converts them. A reviewer following a name-only reference gets lost. |
| Accepting a record with a missing field | Fill it from the body. Incomplete records are a severe deduction. |
| Skipping the Appendix B index table | 29 records without an index is a wall, not a register. |
| A glossary written for engineers | It exists for the founder. "A VPC is your own private section of AWS's network" beats a definition. |
| Broken TOC anchors | Check each against a real heading. |
| Restructuring the body | Not yours. Log it for Phase 13. |

---

## Agent prompt

```text
You are executing Phase 12 of the Innovate Inc. architecture design plan: Executive summary,
decision register & appendices. Phase 11 built the body; you complete the deliverable.

Working directory boundary: architecture/ ONLY. Never read or write terraform/, .claude/, or
anything above architecture/. terraform/ belongs to a different assignment that another agent
may be editing right now.

Read in full:
  architecture/_plan/AGENT-PROTOCOL.md
  architecture/_plan/decision-register.md
  architecture/_plan/style-guide.md
  architecture/_plan/brief.md
  architecture/_plan/STATE.md                (the ADR ledger)
  architecture/_plan/phases/phase-12-frontmatter-and-register.md
  architecture/README.md                     (the assembled body)
  architecture/diagrams/01-high-level.md and 05-request-flow.md

From architecture/_plan/drafts/00-scope.md through drafts/08-cost.md, read ONLY the
"## Decision Records" section of each, plus drafts/00-scope.md section 6 for the R1-R28
traceability table. You do not need the full drafts.

Do not read any other file. No repository-wide searches. No aws/kubectl/terraform/docker/helm.
No web browsing.

Follow the five steps exactly: executive summary with the HLD embedded; section 10 key-decisions
table; Appendix B assembled from the drafts' decision records; Appendices A, C, D; table of
contents.

Step 3 is the most important. Collect all 29 records, order them numerically, check them against
the STATE.md ledger for gaps and duplicates, verify every record has every template field, and
CONVERT each record's Section field from a section name to the real chapter number in the
assembled body. Then write the appendix introduction and the index table.

Do NOT restructure chapters 0-9, do NOT modify the drafts or diagram sources, and do NOT
renumber an ADR to close a gap — report the gap instead.

Then verify every acceptance criterion line by line, fix what fails, update STATE.md, report,
and STOP. Do not begin Phase 13.
```
