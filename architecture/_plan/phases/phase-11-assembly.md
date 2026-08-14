# Phase 11 — Body assembly

> Produces the **body** of the graded deliverable: `architecture/README.md`, chapters §0–§9, with the
> diagrams embedded. The executive summary, decision register, and appendices are **Phase 12**.
> Read [`../AGENT-PROTOCOL.md`](../AGENT-PROTOCOL.md), [`../style-guide.md`](../style-guide.md), and
> [`../rubric.md`](../rubric.md) first.

---

## Goal

Turn ten independently-written drafts into **one document that reads as though one person wrote it in
one sitting** — and a materially shorter one. That is the whole job, and it is harder than it sounds:
ten drafts concatenated is not a document. It repeats itself, it changes voice at every seam, its
headings do not form a coherent outline, and — because each draft was written to its own generous
word budget in isolation — it is roughly twice as long as the brief calls for.

This phase is **editing, not writing**. Budget most of your effort on Steps 3 and 4 — de-duplicating
the seams, normalising the voice, and cutting supporting prose down to what a decision needs to read
as sound. An agent that concatenates and stops has failed this phase even if every draft's content is
present; so has an agent that de-duplicates the exact repeats but leaves every paragraph at its
original length.

> **Amendment, 2026-08-14.** The body target below was cut from 7 000–8 500 words to 4 800–6 500 as
> part of a plan-wide leaning-down (see `STATE.md`). The outline itself — every `###` subsection and
> every required table (account inventory, subnet table, node pools, RPO/RTO, the defence-in-depth
> table, the six pillar evidence tables, the four-stage growth table) — is **unchanged**; those tables
> alone run an estimated 1 800–2 500 words, and `contract.md` §14's locked section map depends on
> every subsection staying put. The cut therefore falls entirely on prose: 1–3 sentences per
> subsection (Step 4a), not on dropping a subsection, a table, or a table row to hit the number. The
> drafts you are assembling still sum to roughly 14 000–16 000 words combined — hitting the new target
> means cutting substantially more than the de-duplication in Step 3 alone removes. See the
> strengthened Step 4a below.

Phase 12 then adds the summary, the decision register, and the appendices on top of the body you
produce. Splitting it this way means you can give the body the attention it needs, and that if the
body comes out wrong it is caught before three thousand words of appendices are built on it.

---

## Dependencies

Phases **00–10** must all be `done`. If any is not, stop and say which.

## Inputs

| File | Use it for |
|---|---|
| `_plan/drafts/00-scope.md` … `09-wellarchitected-growth.md` | The content — **body only**, excluding each draft's `## Decision Records` section |
| `../diagrams/01-…` … `04-…` | The Mermaid blocks to embed (diagram 05 is Phase 12's) |
| `_plan/style-guide.md` | The voice you are normalising to |
| `_plan/contract.md` | Final name check |

## Files you own

- `../README.md` — create (**the deliverable, body only**)
- `_plan/STATE.md` — update

Do **not** edit the drafts — they stay as the record of what each phase produced. Do **not** edit the
diagram source files — copy their Mermaid blocks, leaving the sources in place. Do **not** write the
executive summary, the appendices, or the table of contents — Phase 12 owns them.

---

## The body outline — build exactly this

```
# Innovate Inc. — Cloud Architecture Design
<subtitle: Amazon Web Services · Amazon EKS · Aurora PostgreSQL · three-tier architecture>
<Prepared for Innovate Inc. | Version 1.0>

<!-- TOC: Phase 12 -->
<!-- EXEC-SUMMARY: Phase 12 -->

## 0. Scope, Assumptions and Design Principles  ← draft 00 §§1–5, demoted to ###
### 0.1 Scope and objectives
### 0.2 Architecture overview — a three-tier design
### 0.3 Design principles
### 0.4 Assumptions
### 0.5 Out of scope

## 1. Cloud Environment Structure               ← draft 01
### 1.1 Why multiple accounts
### 1.2 Account inventory
### 1.3 Organizational units and guardrails     ← embed diagram 2
### 1.4 Identity and access
### 1.5 Account provisioning and lifecycle

## 2. Network Design                            ← draft 02
### 2.1 Principles and IP address plan
### 2.2 VPC and subnet architecture             ← embed diagram 3
### 2.3 Routing, egress and private connectivity
### 2.4 Securing the network
### 2.5 Request path across the three tiers

## 3. Compute Platform                          ← drafts 03 + 04
### 3.1 Why Amazon EKS
### 3.2 Cluster topology
### 3.3 Node strategy
### 3.4 Scaling
### 3.5 Resource allocation within the cluster
### 3.6 Cluster add-ons and workload isolation
### 3.7 Containerization — image building
### 3.8 Container registry
### 3.9 Deployment — CI/CD and GitOps           ← embed diagram 4
### 3.10 Frontend deployment path

## 4. Database                                  ← draft 05
### 4.1 Recommendation and alternatives considered
### 4.2 Configuration and connection management
### 4.3 Database security
### 4.4 Backups
### 4.5 High availability
### 4.6 Disaster recovery

## 5. Security and Data Protection              ← draft 06
### 5.1 Security model
### 5.2 Identity and access management
### 5.3 Data protection
### 5.4 Detection, audit and logging
### 5.5 Application-layer security
### 5.6 Compliance and privacy posture
### 5.7 Incident response

## 6. Observability and Operations              ← draft 07
### 6.1 Observability strategy
### 6.2 The four signals
### 6.3 Service level objectives
### 6.4 Alerting and on-call
### 6.5 Operational practices

## 7. Cost Optimization                         ← draft 08
### 7.1 What this architecture costs
### 7.2 The lean-start variant
### 7.3 How cost scales with growth
### 7.4 Optimization levers
### 7.5 FinOps governance

## 8. Growth Roadmap                            ← draft 09, part TWO
### 8.1 Stages and triggers
### 8.2 What breaks first, and in what order

## 9. Well-Architected Framework Alignment      ← draft 09, part ONE
### 9.1 Operational Excellence
### 9.2 Security
### 9.3 Reliability
### 9.4 Performance Efficiency
### 9.5 Cost Optimization
### 9.6 Sustainability
### 9.7 Accepted trade-offs between pillars

<!-- SECTIONS 10+ AND APPENDICES: Phase 12 -->
```

Leave the three HTML-comment markers exactly as written — Phase 12 replaces them.

> **Note.** Draft 09 is **split** across two chapters, and they appear in the opposite order to the
> draft: its growth roadmap becomes `## 8` and its pillar alignment becomes `## 9`. Growth flows
> naturally from the cost chapter; the pillar chapter reads best as the closing synthesis. Do not
> merge them and do not reverse them.

The four assessment areas are `## 1.` through `## 4.` and must be findable at a glance.

---

## Assembly procedure

### Step 1 — Concatenate and demote

Copy each draft's body content into its slot, **excluding** its `## Decision Records` section
entirely — Phase 12 collects those from the drafts directly, so simply leave them out here.

Demote every heading one level (draft `##` becomes `###`), except where the outline already assigns a
`##`. Renumber subsections to match the outline. Where a draft's section name differs slightly from
the outline, keep the outline's name.

Preserve each section's `> **Well-Architected pillars.**` line, moving it to sit under the `##`
chapter heading rather than repeating it under every `###`. **One pillar line per numbered chapter**,
merging the pillars its subsections claimed and keeping the total to two to four.

### Step 2 — Embed diagrams 2, 3, and 4

Copy each Mermaid block, its caption paragraph, and its legend table from the diagram file into the
slot marked in the outline. Leave the source files untouched. Under each embedded diagram add:
`Source: [diagrams/0N-name.md](diagrams/0N-name.md)`.

Diagram 1 (the HLD) goes into the executive summary and diagram 5 into an appendix — both are Phase
12's. Do not place them.

### Step 3 — De-duplicate the seams

Drafts were written independently, so the same fact will appear two or three times. Keep the fullest
treatment and cut the rest to a cross-reference. Check these overlaps specifically:

| Overlap | Keep it in | Reduce elsewhere to |
|---|---|---|
| Encryption at rest and KMS keys | §5.3 | a clause + cross-reference |
| Network security controls | §2.4 | a row in §5.1's layer table |
| Pod Identity and IRSA | §3.6 | a clause in §5.2 |
| Multi-AZ and AZ failure | §4.5 | a clause in §2 and §3 |
| Spot interruption handling | §3.3 | a clause in §8 |
| Immutable image digests | §3.8 | a clause in §5.1 and §7 |
| Cost figures | §7 | never repeat the tables; cross-reference them |
| Service level objectives | §6.3 | a clause in §3.4 |
| Growth triggers | §8 | a clause wherever a ceiling is mentioned |
| The three-tier model | §0.2 | tier *names* used freely; the model explained once |
| Pillar evidence | §9 | do not restate the evidence tables in the body |
| Connection pooling / RDS Proxy | §4.2 | a clause in §3.4 and §8.2 |

Removing a duplicate means replacing it with a sentence that points at where it lives, not deleting
the idea. A reader arriving at §5 should still learn that the database is encrypted — just in one
clause rather than three paragraphs.

### Step 4 — Normalise voice and acronyms

- Every acronym expanded on **first use in the whole body**, then never again. Drafts each expanded
  independently — delete the second and third expansions.
- One consistent tense and person throughout (`style-guide.md` §1).
- Consistent callout labels (only the five allowed).
- Consistent number formatting (`99.9%` with no space, `35 days`, `$850/month`).
- Remove any sentence beginning "In this section", "As mentioned above", or "As we will see".
- Verify every cost figure is labelled indicative wherever it appears.
- Fix any sentence that reads as instructions to an agent rather than prose for a client — occasional
  phase-document language leaks into drafts.

### Step 4a — Condense every section to what the decision needs (not optional)

De-duplication (Step 3) removes exact repeats; this step removes elaboration that never repeated
anywhere but still isn't needed. For every `###` subsection, keep **decision → why → what it beat →
what it costs**, in one to three sentences each, plus any table the outline requires — and cut:

- A second or third example illustrating a point the first example already made.
- Restating a consequence that a table two lines below already states.
- Throat-clearing sentences ("It is worth noting that...", "This is an important consideration
  because...") that could be deleted with no loss of meaning.
- Background explanation of a well-known AWS/Kubernetes concept beyond what a competent engineer
  needs — this document is for someone who already knows what a VPC or a pod is; the glossary
  (Phase 12) carries the founder-facing definitions.
- A third or fourth rejected alternative in inline prose where two make the comparative case; the
  full options table, if the decision has a promoted ADR, lives in Appendix B, not here too.

Do **not** cut: the decision itself, its single strongest justification, what it beat, its cost or
consequence, its Well-Architected pillar line, or anything a Step 3 overlap row still routes here.
When in doubt, cut the explanation and keep the conclusion — a reader who wants the full reasoning for
a given decision has the phase draft under `_plan/` and, for the nine promoted decisions, Appendix B.

### Step 5 — Read it once, end to end

Before you finish, read the assembled body straight through as a reader would. You are looking for
exactly one thing: **can you see the seams?** A change of voice, a topic introduced twice, a section
that assumes something the previous section did not establish. Fix what you find.

---

## Acceptance criteria

- [ ] `architecture/README.md` exists with the title block and chapters §0 through §9.
- [ ] Exactly one `#` heading — the document title.
- [ ] The three HTML-comment markers for Phase 12 are present and untouched.
- [ ] Chapter and subsection numbering matches the outline exactly.
- [ ] `## 1. Cloud Environment Structure`, `## 2. Network Design`, `## 3. Compute Platform`,
      `## 4. Database` all present.
- [ ] Draft 09 is split correctly: growth roadmap as §8, pillar alignment as §9.
- [ ] Diagrams 2, 3, and 4 embedded with captions, legends, and source links. Diagrams 1 and 5 are
      **not** placed.
- [ ] No draft's `## Decision Records` section appears in the body.
- [ ] Exactly one `> **Well-Architected pillars.**` line per numbered chapter, 2–4 pillars each.
- [ ] Every overlap in the Step 3 table resolved — one full treatment, cross-references elsewhere.
- [ ] No acronym expanded more than once.
- [ ] Body length 4 800–6 500 words including tables. Every outline subsection and every required
      table is still present — the cut came from prose, not from dropping either.
- [ ] Step 4a's condensation applied throughout, not only where Step 3 already flagged an overlap.
- [ ] No `TODO`, `TBD`, or leftover phase-document instruction text.
- [ ] Drafts and diagram source files unmodified.
- [ ] The end-to-end read in Step 5 completed and anything it surfaced fixed.
- [ ] `STATE.md` updated.

## Common failure modes

| Failure | Avoid it by |
|---|---|
| Concatenating without editing | Steps 3, 4, and 4a **are** the phase. |
| De-duplicating exact repeats but leaving every paragraph at its original length | Step 4a — condense each subsection to decision → why → what it beat → what it costs. |
| Deleting a duplicate instead of replacing it with a cross-reference | The idea stays; the length goes. |
| Losing the Decision Records | You exclude them; Phase 12 reads them from the drafts. Do not delete them from the drafts. |
| Merging §8 and §9, or putting them in draft order | Growth is §8, pillars are §9. |
| Placing diagram 1 or 5 | They belong to Phase 12's sections. |
| A pillar line under every `###` | One per chapter. |
| Heading levels drifting | One `#`, `##` for chapters, `###` beneath. Never `####`. |
| Editing a draft to fix a problem | Fix it in `README.md`; log the underlying issue in `STATE.md`. |

---

## Agent prompt

```text
You are executing Phase 11 of the Innovate Inc. architecture design plan: Body assembly.
This phase produces the body of the graded deliverable. Phase 12 adds the summary and appendices.

Working directory boundary: architecture/ ONLY. Never read or write terraform/, .claude/, or
anything above architecture/. terraform/ belongs to a different assignment that another agent
may be editing right now.

Read in full:
  architecture/_plan/AGENT-PROTOCOL.md
  architecture/_plan/style-guide.md
  architecture/_plan/rubric.md
  architecture/_plan/contract.md
  architecture/_plan/phases/phase-11-assembly.md
  architecture/_plan/drafts/00-scope.md through drafts/09-wellarchitected-growth.md
  architecture/diagrams/02-account-topology.md, 03-network-topology.md, 04-cicd-pipeline.md

Do not read any other file. No repository-wide searches. No aws/kubectl/terraform/docker/helm.
No web browsing.

Build architecture/README.md — chapters §0 through §9 only — following the outline and the
five-step procedure exactly. Leave the three HTML-comment markers in place for Phase 12.

This phase is EDITING, not writing. Steps 3, 4, and 4a — de-duplicating the twelve named overlaps,
normalising voice and acronyms, and condensing every subsection down to decision/why/alternative/cost
— are where the value is. The drafts sum to roughly 14,000-16,000 words combined; the target body is
4,800-6,500, including the outline's required tables, which stay as they are — the cut comes from
prose only. An agent that concatenates the drafts and stops, or that only removes exact repeats
without condensing, has failed this phase.

Two things that are easy to get wrong: draft 09 SPLITS into chapter 8 (growth roadmap) and
chapter 9 (Well-Architected alignment), in that order, which is the reverse of the draft; and each
draft's ## Decision Records section is EXCLUDED from the body — Phase 12 collects them.

Do NOT write the executive summary, any appendix, or the table of contents. Do NOT place diagram 1
or diagram 5. Do NOT modify the draft files or the diagram source files.

Finish with the end-to-end read in Step 5, then verify every acceptance criterion line by line,
fix what fails, update STATE.md, report, and STOP. Do not begin Phase 12.
```
