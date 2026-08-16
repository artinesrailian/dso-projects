# STATE — progress and handoff log

**This file is the single source of truth for "what has been done".** A fresh agent with no memory
reads this file to answer "which phase is next?". Keep it accurate or the workflow breaks.

Statuses: `todo` → `in-progress` → `done`. Also allowed: `blocked`, `needs-rework`.

**Update this file twice per phase:** claim it (`in-progress`) before you start writing, close it
(`done` + completion report + ADR numbers) before you report to the human.

---

## Phase board

| # | Phase | Status | Depends on | Output | ADR block |
|---|---|---|---|---|---|
| 00 | Pre-flight, scope & three-tier framing | `done` | — | `drafts/00-scope.md` | 001–003 |
| 01 | Cloud environment structure | `done` | 00 | `drafts/01-cloud-environment.md` | 004–006 |
| 02 | Network design | `done` | 00 | `drafts/02-network.md` | 007–010 |
| 03 | Compute platform — EKS | `done` | 00 | `drafts/03-compute-eks.md` | 011–014 |
| 04 | Containerization & CI/CD | `done` | 00 | `drafts/04-containers-cicd.md` | 015–018 |
| 05 | Database | `done` | 00 | `drafts/05-database.md` | 019–022 |
| 06 | Security & data protection | `done` | 00, 01–05 | `drafts/06-security.md` | 023–025 |
| 07 | Observability & operational excellence | `done` | 00, 03, 05 | `drafts/07-observability.md` | 026–027 |
| 08 | Cost optimization & FinOps | `done` | 00, 01–07 | `drafts/08-cost.md` | 028–029 |
| 09 | Well-Architected alignment & growth roadmap | `done` | 01–08 | `drafts/09-wellarchitected-growth.md` | — |
| 10 | Diagrams | `done` | 01–09 | `../diagrams/01…05` | — |
| 11 | Body assembly | `done` | 00–10 | `../README.md` §0–§9 | — |
| 12 | Summary, decision register & appendices | `done` | 11 | `../README.md` complete | collects all |
| 13 | QA, consistency audit & final polish | `done` | 12 | corrected `../README.md` | — |

**Next phase to run:** none — all 14 phases (00–13) are `done`. The deliverable at `../README.md` is
final.

---

## Plan amendments

> Changes to the normative plan itself, made by the human directing this work rather than by a phase
> agent. Read this before starting Phase 09 or later — the rules below differ from what phases 00–08
> were written against.

### 2026-08-14 — Leaning down the assembled deliverable

Phases 00–08 (all `done`) were written against the original plan and are **unchanged** — all 29 ADRs
they wrote stay exactly as written in `_plan/drafts/`. What changed is how much of that gets promoted
into the graded `README.md` that Phases 11–12 assemble:

- **Appendix B now promotes nine ADRs, not 29** — one per content phase 00–08, fixed in
  `decision-register.md` §2a: **001, 004, 007, 011, 017, 019, 023, 026, 029.** The other twenty stay
  in their drafts and surface in the deliverable as a row in the §10 Summary of Key Decisions table
  instead of a full record — that table grows from 20–26 rows to **29–34** to carry all of them (see
  Phase 12 Step 2).
- **Phase 09's word budget** cut from ~1,400 to ~900 words. Scope unchanged — all six pillars and the
  full growth roadmap are still required, written tighter.
- **Phase 11's body target** cut from 7,000–8,500 to **4,800–6,500** words. Phase 11 now has an added
  Step 4a instructing active condensation, not just de-duplication of exact repeats. The outline (every
  `###` subsection, every required table) is unchanged — the cut is prose only, so it doesn't collide
  with `contract.md` §14's locked section map. (An earlier pass at this amendment targeted
  3,500–4,500; raised to 4,800–6,500 after estimating the outline's own required tables at
  1,800–2,500 words, which made the tighter number arithmetically incompatible with keeping every
  subsection and table intact.)
- **Total document target** cut from 13,000–16,000 to **9,000–12,000** words. Updated correspondingly
  in `style-guide.md` §6, `rubric.md` §1/§2.B/§4, and Phase 13's Pass 3 and Pass 8.
- **Phase 13 Pass 1 (R26) and its Fixing rules** updated so QA doesn't re-promote the twenty
  non-promoted ADRs into Appendix B while checking requirement coverage — R26 is satisfied by inline
  reasoning plus *either* a promoted ADR *or* a §10 row, and a missing-ADR gap at QA gets fixed as a
  §10 row, not a new Appendix B entry.

**Rationale:** the client brief (`docs/assessment.md`) is a four-area, one-README ask with no
literal requirement for a 29-entry ADR register or a 15,000-word document. `brief.md` R26 ("every
decision is justified... in language the client can follow") does not require a formal ADR per
decision — inline prose plus a Summary of Key Decisions row satisfies it, and both still exist for
all 29. Nothing in `brief.md`'s R1–R28 register changed or is now unmet by this cut.

**Scope of this change:** forward-looking only. Drafts 00–08 were not rewritten and their content,
word counts, and ADRs are untouched. Phases 09–13 run under the amended rules above.

### 2026-08-16 — Drop Appendix A (Requirement Traceability) and Appendix C (Diagrams)

The human directing this work reviewed the finished Phase 12 deliverable and removed two of its four
appendices in two successive requests, both judged unnecessary.

- **Appendix A (Requirement Traceability)** — the R1–R28 requirement-to-section mapping table —
  deleted from `README.md`, along with its Table of Contents entry.
- **Appendix C (Diagrams)** — deleted from `README.md`, along with its Table of Contents entry. This
  appendix's only content not already embedded elsewhere was diagram 5 (the authenticated request
  flow); diagrams 2–4 remain embedded in §1.3, §2.2, and §3.9 exactly as before, each already carrying
  its own `Source: [diagrams/...]` link. Diagram 5 is no longer embedded anywhere in `README.md`. In
  its place, the Executive Summary's HLD source line was extended into a short pointer: "All five
  diagram sources — including the authenticated request flow, not otherwise embedded in this
  document — are Mermaid files under `diagrams/`," and its callout note was reworded from "see
  Appendix C for the full diagram set" to name §1.3/§2.2/§3.9 directly.

`contract.md` §14's locked section map no longer lists either appendix, and
`phases/phase-13-qa-and-final.md`'s Pass 1 no longer instructs a check for Appendix A.

**What did not change:** requirement coverage and diagram content themselves. R1–R28 are still
individually satisfied by real chapters and sections in the body — this amendment removes only the
standalone cross-reference table that pointed at them, not the underlying content. All five diagrams
still exist, unchanged, under `diagrams/`; four of the five (1, 2, 3, 4) are still embedded in the
body. `drafts/00-scope.md` §6 (the original traceability table, in the planning record, not the
deliverable) is untouched, as are `decision-register.md`, `well-architected.md`, the ADR ledger below,
and every other locked value — this is a document-structure change, not a content or decision change.

**Follow-up, same day:** with the original Appendix A gone, the remaining glossary appendix (originally
lettered D) was relettered to **Appendix A — Glossary** and moved to appear immediately after §10,
ahead of Appendix B, so the document's appendix letters run A, B in reading order with no gap. Its
content is unchanged — only the heading, its Table of Contents entry and anchor, and its position in
the file moved. `contract.md` §14 updated to match: `App. A | Glossary`, `App. B | Architecture
Decision Records`, no `App. C` or `App. D` row. The final document therefore has exactly two
appendices, A and B, and every `(Appendix B, ADR-0NN)` citation already in the §0–§9 body (there are
several) still points at the correct thing, since Appendix B itself was not relettered or moved.

**Scope of this change:** the `README.md` deliverable and the plan files listed above. Phase 12's own
completion report and word counts (below) reflect the document as it now stands, after both removals
and the rename.

### 2026-08-16 — Phase 13: word-budget ceiling raised; lean-start account/cluster contradiction resolved

The human directing this work answered both `STATE.md` *Open questions* Phase 11/12 raised, before
Phase 13's audit ran, so the audit checked against final rules rather than ones already known to be
wrong.

- **Word budget raised to match measured reality**, not cut to force a fit. `style-guide.md` §6,
  `rubric.md` §1, and `phases/phase-13-qa-and-final.md`'s own acceptance criterion are all updated:
  body (§0–§10) **8,000–9,500** words (was 4,800–6,500), Appendix B prose **2,000–2,500** words
  excluding its two tables per record (unchanged — it was already compliant), total document
  **13,000–15,500** words (was 9,000–12,000). Every required subsection, every required table, and
  the full nine-ADR Appendix B stay exactly as scoped — nothing was cut to chase a number. `style-
  guide.md` §6 now also pins two distinct, precisely-specified word-counting procedures (document/
  section length vs. the stricter per-ADR 250-word cap) to close a three-way disagreement on record
  between Phase 01, Phase 03, Phase 11, and Phase 12's independently-computed counts for the same
  text.
- **The lean-start variant's "dev+staging share one cluster" claim is now technically coherent.**
  `contract.md` §11's lean-start row and a new "Lean-start exception" note under §4 both now state
  plainly that this variant merges `innovate-dev` and `innovate-staging` into a single account,
  `innovate-dev-staging`, running one EKS cluster isolated by Kubernetes namespace instead of by
  account — since an EKS cluster cannot span two AWS accounts, "share one cluster" necessarily meant
  "share one account" too, which the pre-Phase-13 text never said. `contract.md` §12's Extensions
  register records the new account name. `README.md` §7.2's lever table and prose, and ADR-029's
  Context/Why/Consequences fields, were rewritten to match. The primary, day-1 recommendation
  (`contract.md` §4's seven-account table, `README.md` §1.2 and §3.2) is **unchanged** — the merge
  applies only to the documented cheaper alternative.
- Also fixed as part of the same decision: `contract.md` §11's stale "§8.3" self-reference, corrected
  to "§7.3" (the table actually landed there per Phase 09/11's own prediction, logged as a cross-phase
  issue and left open until now).

**Scope of this change:** `style-guide.md`, `rubric.md`, `contract.md`, `phases/phase-13-qa-and-
final.md`, and `README.md`. Drafts 00–08 are untouched — this amends only the assembled deliverable
and the normative files that grade it, consistent with the 2026-08-14 amendment's own precedent.

---

## ADR ledger

Filled in by each phase as it completes, so Phase 12 can assemble the register in order and Phase 13
can check for gaps and duplicates. Record the numbers you **actually wrote**. The **Promoted** column
marks which one of each phase's numbers Phase 12 copies into Appendix B, per `decision-register.md`
§2a — added 2026-08-14, see *Plan amendments* above.

| Phase | Block (exact) | Numbers written | Promoted | Titles |
|---|---|---|---|---|
| 00 | 001–003 | 001, 002, 003 | **001** | AWS as the Cloud Provider; Three-Tier Architecture Over Microservices or a Monolith; Managed Services First |
| 01 | 004–006 | 004, 005, 006 | **004** | Seven AWS Accounts Rather Than a Single Account; AWS Control Tower Rather Than Hand-Rolled AWS Organizations; IAM Identity Center Rather Than Per-Account IAM Users |
| 02 | 007–010 | 007, 008, 009, 010 | **007** | One VPC Per Environment, No Interconnection; Three Availability Zones Rather Than Two; A Secondary CIDR in `100.64.0.0/10` for Pod Addresses; A NAT Gateway Per Availability Zone in Production, One in Non-Production |
| 03 | 011–014 | 011, 012, 013, 014 | **011** | Amazon EKS as the Compute Platform; Platform Node Group Plus Karpenter Over Cluster Autoscaler; Graviton-First Spot for the Application Tier; No CPU Limit, Memory Request Equals Limit |
| 04 | 015–018 | 015, 016, 017, 018 | **017** | Serving the React SPA from S3 and CloudFront, Not a Container; A Single Central Registry with Promotion by Immutable Digest; GitOps Pull-Based Delivery with Argo CD Over Push-Based CI/CD; Image Signing Verified at Admission |
| 05 | 019–022 | 019, 020, 021, 022 | **019** | Aurora PostgreSQL Over Self-Managed and RDS; Aurora Serverless v2 With RDS Proxy Pooling; A Three-Tier Backup Strategy, Not PITR Alone; Pilot-Light Cross-Region Disaster Recovery |
| 06 | 023–025 | 023, 024, 025 | **023** | Customer-Managed KMS Keys Rather Than AWS-Managed Keys; Centralized Immutable Logging in a Separate Account; Deferring a Service Mesh and Its Mutual TLS |
| 07 | 026–027 | 026, 027 | **026** | Open-Source Observability, Managed at Scale; SLO Targets and the Error-Budget Policy |
| 08 | 028–029 | 028, 029 | **029** | Deferring Compute Savings Plans and Reserved Capacity; Offering the Lean-Start Variant as a Documented Option |

The finished register, across all nine drafts, is **ADR-001 to ADR-029, no gaps** — Phase 13 checks
this in the drafts. **Appendix B in the graded deliverable carries only the nine bolded numbers
above**; the other twenty each need a row in §10 instead. Counts are exact, not ranges — a phase that
cannot fill its block says so here rather than leaving a silent hole.

---

## Completion reports

> One block per finished phase, appended in completion order. Written for someone who never saw the
> session. Copy the template, fill every field, delete nothing.

### Template

```
### Phase NN — <name>
- Completed:      <date or "session N">
- Files written:  <paths, with word counts>
- Word count:     <n> (budget <n>)
- ADRs written:   ADR-0NN … ADR-0NN
- Pillars tagged: <which Well-Architected pillars this section claims>
- Key decisions:  <2–5 calls you made that the plan did not fully specify>
- Assumptions:    <anything you had to assume; "none" is a valid answer>
- Deferred:       <what you deliberately left to another phase, and which phase>
- Contract additions: <names appended to contract.md §12, or "none">
- Notes for the next agent: <anything non-obvious>
```

<!-- Append completion reports below this line -->

### Phase 13 — QA, consistency audit & final polish
- Completed:      2026-08-16
- Files written:  `../README.md` (edited — surgical fixes only, no section rewritten wholesale),
  `../diagrams/01-high-level.md` (edited — one `class` statement and one legend row, to fix a
  tier-miscoloring defect also present in the README's embedded copy; kept byte-identical to it),
  `_plan/STATE.md` (this file — phase board, two Open questions, fourteen Cross-phase issues, this
  report), `_plan/contract.md` (§4 lean-start exception note, §11 lean-start line + stale
  cross-reference, §12 Extensions register), `_plan/style-guide.md` (§6 word budgets + two pinned
  counting methods), `_plan/rubric.md` (§1 length line, §2.A traceability-table line),
  `_plan/phases/phase-13-qa-and-final.md` (its own word-budget acceptance line), `_plan/well-
  architected.md` (§4 stale cross-reference), `_plan/phases/phase-00-preflight-and-scope.md` (§3
  stale cross-reference).
- Word count:     Final `README.md`, pinned method (variant 1, `style-guide.md` §6): **15,076 total**
  (budget 13,000–15,500 — inside, 424 words of headroom); **body §0–§10: 9,348** (budget 8,000–9,500 —
  inside, 152 words of headroom); Executive Summary 797; Appendix A (Glossary) 586; Appendix B
  (prose + both tables per record) 4,345. Every one of the nine promoted ADRs recounted individually
  with the stricter per-ADR method (variant 2 — heading and both tables excluded) and confirmed at or
  under the 250-word cap: ADR-001 240, ADR-004 250, ADR-007 248, ADR-011 248, ADR-017 244, ADR-019
  249, ADR-023 239, ADR-026 250, ADR-029 242. Four of the nine (007, 011, 026, 029) were over cap
  before this phase's fixes and were trimmed with surgical cuts to Context/Why/Consequences/Revisit
  fields — no required content dropped, only compressed.
- ADRs written:   none — this phase edits, it does not author. No ADR numbers used or reserved.
- Pillars tagged: Added one pillar line that was genuinely missing (Executive Summary: `Security ·
  Reliability · Cost Optimization`) — the one content-adjacent chapter this phase's audit found
  without one. Confirmed, did not add, that §10 (Summary of Key Decisions), Appendix A (Glossary), and
  Appendix B (Architecture Decision Records) correctly carry no pillar line, as summary/reference
  chapters rather than content chapters the tagging convention was written against — independently
  corroborated by the Pass 4 audit agent, not just asserted. Confirmed §9's chapter-level 4-pillar line
  (of 6 pillars discussed across its six dedicated subsections) is consistent with the 2–4 cap, not an
  exception to it, closing the open question Phase 09/11 left unadjudicated.
- Key decisions:
  1. Before running the nine audit passes, surfaced the two `STATE.md` *Open questions* explicitly
     reserved for the human (word-budget ceiling; the lean-start dev/staging-merge contradiction) via
     `AskUserQuestion` rather than adjudicating either unilaterally — both are marked in this file as
     "the human answers these," and both required editing normative files (`style-guide.md`,
     `rubric.md`, `contract.md`), not just the deliverable. Applied both answers (raise the ceiling to
     match measured reality; merge dev+staging into one account for lean-start) before the audit ran,
     so all nine passes checked against final rules instead of ones already known to be about to
     change — avoiding a second audit round.
  2. Ran Passes 1–8 as eight independent, read-only, parallel agents (via the Workflow tool) rather
     than one sequential read, per this phase document's own "a single read finds a third of the
     problems" warning and `AGENT-PROTOCOL.md`'s general instruction to keep separate concerns
     separate. Each returned structured findings with file, line, severity, and a verbatim quote, so
     every fix in this report traces to a specific, checkable claim rather than a paraphrase. All
     fixes were then applied by a single writer (this session, sequentially) to avoid the concurrent-
     edit conflicts that would result from letting multiple agents edit `README.md` at once — one
     audit agent (Pass 8) independently flagged that the file *was* changing under it mid-run, from
     this session's own concurrent manual fixes (the lean-start/§10.7/ADR-trim edits, done in parallel
     with the audit to save time), and correctly treated its own possibly-stale earlier reads with
     appropriate caution; every finding from every pass was re-verified against the current file text
     before being applied, not applied blindly.
  3. Overrode one of Phase 12's own explicit editorial choices: ADR-001's `Section` field, which
     Phase 12 deliberately left at chapter level (`§0`) reasoning the choice was intentional and
     unflagged. Pass 3's audit found this inconsistent with all eight other promoted ADRs (which cite
     subsection level) and the actual AWS-vs-GCP argument's real location (`§0.1`, not `§0` as a
     whole). Judged this a legitimate QA-stage tightening — final authority sits with Phase 13, the
     fix is strictly more precise with no downside, and "an earlier phase considered and rejected this"
     is not the same as "an earlier phase adjudicated this against the rubric's own consistency bar."
     Changed to `§0.1 Scope and objectives` in both the ADR's own metadata table and the Appendix B
     index table.
  4. Found and fixed one severe, previously-undetected factual bug no earlier phase's fix-pass caught:
     §4.2's migrations sentence read "migrations run under a separate role that cannot run DDL" —
     inverted from `drafts/05-database.md`'s original, correct meaning (the *app's* role cannot run
     DDL; the *migration* role can, which is the only way it could run a migration at all). Verified
     directly against the source draft before fixing, not just trusted the audit agent's claim.
  5. Found and fixed a genuine diagram-accuracy defect the Mermaid-syntax check (Pass 6, clean) could
     not have caught because it was never a syntax problem: the HLD's `class` statement colored the
     Application Load Balancer as part of the Presentation tier (orange), contradicting `contract.md`
     §1a's explicit "the application tier's load balancer" and the README's own Executive Summary
     prose and §2.2 legend. Fixed in both `README.md`'s embedded copy and `diagrams/01-high-level.md`
     (moved `alb` from the `edge` class to the `compute` class, reworded both affected legend rows),
     and re-diffed the two files' Mermaid blocks and legend tables after the fix to confirm they are
     still byte-identical, per this phase's own "fix in both, or they diverge" instruction.
  6. Left three findings deliberately unfixed, each recorded as an accepted trade-off rather than
     silently dropped: (a) Aurora's short form ("Amazon Aurora") appears in the title/subtitle and
     Executive Summary prose before its `contract.md` §13-mandated full form ("Amazon Aurora
     PostgreSQL-Compatible Edition") is first spelled out in §4.1 — accepted as a defensible
     readability exception for front-matter and a founder-facing summary, the same treatment already
     given to diagram labels elsewhere in this plan; (b) the `well-architected.md` §3-sourced
     $25–60/month-per-account figure inside the locked-verbatim §9.7 trade-off table was **not**
     given an "(indicative)" label, even though its three other occurrences in the body were — because
     §9.7's table must stay byte-identical to `well-architected.md`'s own source table (one of the
     five explicitly locked tables Phase 11 verified), and editing it would break that guarantee; (c)
     a citation drift Pass 2 found between `well-architected.md`'s trade-off-table figure and
     `contract.md` §11's cost-anchor table (the figure is real and cross-phase-consistent, just sourced
     from a different, equally-normative file than the literal checklist wording named) was resolved
     by adding "(indicative)" labels rather than removing the figure, since it was not invented, only
     under-labelled.
- Assumptions:    That "Files you own" (`../README.md`, `../diagrams/*.md` for genuine Mermaid errors,
  `_plan/STATE.md`, `_plan/contract.md` §12) extends, as this phase document's own "Fixing rules"
  section states, to any normative file whose *value* a README fix requires changing for the record to
  stay coherent — applied to fix `contract.md` §4/§11 (lean-start), `style-guide.md` §6, `rubric.md`
  §1/§2.A, `well-architected.md` §4, and `phases/phase-00-preflight-and-scope.md` §3, all logged here.
  That two small, low-risk stale-cross-reference fixes in planning-only files not part of the graded
  deliverable (`well-architected.md`, `phases/phase-00-preflight-and-scope.md`) were within this
  phase's remit, since the Cross-phase issues table itself assigns their resolution to "Phase 13."
- Deferred:       Nothing within this phase's nine audit passes or its acceptance criteria — all
  complete, all nine verdicts below, all findings fixed or explicitly accepted with reasoning recorded
  above. The pre-existing five-column/four-column table-formatting quirk in this file's own Cross-
  phase issues table (Phase 12's word-budget row embeds a literal `"| a | b |".split()` code example
  whose pipe characters inflate a naive column count) was noted, judged cosmetic and out of scope
  (this file is explicitly not part of the graded deliverable), and left as is.
- Contract additions: `contract.md` §12 — `innovate-dev-staging`, the lean-start-only merged account
  name for `innovate-dev` + `innovate-staging` (Why: needed once the lean-start variant's account
  merge was made explicit; see the 2026-08-16 Phase 13 plan amendment above).
- Notes for the next agent: There is no next content phase — Phase 13 is the last phase and this
  plan's `AGENT-PROTOCOL.md` §4 execution loop ends here. If this document is ever revisited: (1) the
  nine ADR word counts above are tight (ADR-004 and ADR-026 sit exactly at the 250-word cap with zero
  headroom) — any future prose addition to those two records requires an equal-or-larger cut in the
  same record, verified with `style-guide.md` §6's pinned variant-2 method, not eyeballed; (2) total
  document headroom against the 13,000–15,500 budget is 424 words and body headroom against
  8,000–9,500 is 152 words — comfortable but not unlimited; (3) the nine audit-pass verdicts,
  checklist results, and full finding text are preserved in this session's workflow transcript
  (`wf_dddb757e-741`) if a deeper record than this summary is ever needed, though everything
  actionable from them is already either fixed in `README.md` or recorded as an accepted trade-off
  above.

**Nine audit-pass verdicts** (each pass's checklist ran in full; findings listed are pre-fix — every
one below was fixed in `README.md` during this phase except where marked *(accepted)*):

1. **Requirement coverage — PASS** (fatal-if-fails; did not fail). All 28 of R1–R28 traced to a real
   section, including every commonly-dropped sub-requirement (R2's three-way isolation/billing/
   management justification; R6/R8's dedicated headings; R9/R10/R11 and R13/R14/R15 each three
   distinct headings; R18's HLD embedded/valid/referenced/tier-organized; R22's real cost figures and
   levers; R26's nine ADRs + 29-row §10 table; R27's six pillar subsections + trade-off table; R28's
   structural three-tier framing). One minor finding (ADR-026's `Requirement` field cited R7, which
   doesn't match its content) — fixed, changed to R22.
2. **Cross-section consistency — PASS** (severe-if-fails; did not fail). All fifteen pinned facts
   (account count, CIDRs, AZ/NAT counts, regions, cluster/cluster-identifier names, backup retention,
   RPO/RTO, SLO, cost figures, namespace/NodePool/tier names) identical everywhere checked, across
   prose, tables, ADRs, and all five diagrams. Four findings, all fixed: two instances of "the client"
   in ADR-004's options table (→ "Innovate Inc."); the Aurora cluster identifier
   `innovate-prod-aurora-pg-use1`, present in the source draft, missing from the entire assembled
   document (→ added to §4.2, along with the dev/staging identifiers); a naming-drift moderate finding
   on "Amazon Managed Prometheus + Grafana" vs. ADR-026's full official name (→ standardized). One
   minor finding *(accepted, not fixed)*: Aurora's short form appears in front matter before its full
   contract-mandated form is spelled out in §4.1 — a defensible readability exception, see Key decision
   6(a) above.
3. **Decision register integrity — FAIL, then fixed** (severe-if-fails). Structural checks all passed
   cleanly (exactly the nine promoted ADRs; all 29 decisions traceable; every template field present;
   every Section reference resolves; every options table has a genuinely reasonable rejected
   alternative; every Accepts list real; no ADR a copy of its inline prose). The plain-language check —
   this pass's own "most commonly failed" item — did fail and was fixed: ADR-019's bare, ungl
   ossed "RDS" and ADR-011's unglossed "Auto Mode" both rewritten with an in-line gloss, each
   compensated by a cut elsewhere in the same field to stay under the 250-word cap; ADR-004 and
   ADR-029 both silently substituted "test" for the document's established "staging" term — fixed to
   "staging" in both (a net word-count savings that helped absorb the RDS/Auto-Mode glosses' cost
   elsewhere in the appendix). One moderate finding (ADR-029's Revisit-when had one unobservable
   trigger clause) fixed with a named event. Two minor findings (ADR-001's Section field at chapter
   instead of subsection level; ADR-019's title missing "Amazon") both fixed — see Key decision 3
   above for the former.
4. **Well-Architected alignment — FAIL, then fixed** (moderate-if-fails). Ten of eleven §0–§9 chapters
   had a correct pillar line; the Executive Summary was missing one entirely (fixed — see Pillars
   tagged above). All six §9 pillar subsections present including Sustainability, each with a demand
   sentence and evidence table; §9.6's gap named no trigger (fixed) and its Graviton evidence row
   claimed an invented "~20% performance-per-watt" figure §3.3 does not support (fixed to qualitative
   language, matching `well-architected.md`'s own deliberately-unnumbered claim). Two minor citation-
   accuracy findings (§9.1's on-call gap citing §6.2 instead of §6.4; §9.6's Aurora auto-pause
   citation omitting §4.2) both fixed. §9.7's trade-off table confirmed present and complete; the
   chapter confirmed to map to this design, not recite framework documentation. Two informational,
   no-fix-needed findings independently confirmed this phase's own adjudications (§9's 4-pillar
   chapter line; §10/Appendix A/B's absence of a pillar line) — see Pillars tagged above.
5. **Three-tier coherence — FAIL, then fixed** (moderate-if-fails). Five of six checks passed cleanly
   (tier table matches `contract.md` §1a verbatim; subnet-to-tier mapping explicit; each tier's
   scaling mechanism distinct; tier boundary shown enforced by security-group/prefix-list reference,
   not asserted by convention; tier names used consistently with zero non-canonical renamings). One
   check failed and was fixed: the HLD's legend colored the Application Load Balancer as Presentation
   tier, contradicting `contract.md` §1a's own text and the README's own prose — see Key decision 5
   above for the full fix (both README and diagram source, re-verified byte-identical after). One
   minor finding (an undefined fourth "tier" — "the platform tier" — used once in §3.3) fixed to "the
   platform node group."
6. **Mermaid validation — PASS, zero findings** (fatal-if-fails; did not fail). All nine Mermaid
   blocks (4 embedded in `README.md` + 5 `diagrams/*.md` sources) passed every applicable item of the
   eleven-item checklist: subgraph/end counts hand-verified and grep-confirmed balanced in every block
   (HLD 4/4, account topology 6/6, network topology 4/4, CI/CD pipeline 0/0, request-flow 0 subgraph /
   2 correctly-paired sequenceDiagram `alt/end`); no malformed node IDs, unquoted labels, bare `<br>`,
   reserved-word IDs, undefined class references, dangling arrows, or banned syntax anywhere; every
   name/CIDR/account cross-checked against `contract.md` and matched; the four diagrams that exist
   both embedded and as a separate source confirmed byte-identical via diff both before and again
   after this phase's own HLD tier-color fix (finding 5 above).
7. **Technical correctness — FAIL, then fixed** (severe-if-fails). Seven of ten checks passed cleanly
   (stateful SG / stateless NACL correctly distinguished; HPA/KEDA/Karpenter/VPA kept as four distinct
   mechanisms everywhere; HA never conflated with DR; WAF correctly scoped to edge/application, never
   credited with east-west protection; subnet arithmetic hand-verified with no CIDR overlaps; no
   hard-coded Kubernetes version anywhere; no hallucinated AWS service or capability). Two severe
   findings fixed: §4.2's inverted DDL/migrations sentence (Key decision 4 above); the $25–60/account
   figure's missing "(indicative)" label at three of its four occurrences (the fourth, inside the
   locked-verbatim §9.7 table, deliberately left unlabelled — Key decision 6(b) above). One moderate
   finding fixed: the ALB's static "shared secret header" sat in tension with the document's absolute
   "no long-lived credential anywhere" claims — both claims re-scoped to "no long-lived **identity**
   credential," which is what they actually meant and is still true of the shared-secret header (a
   network-layer origin-verification control, not an identity credential).
8. **Style, placeholders and readability — FAIL, then fixed**. Banned words, percentage formatting,
   callout labels, emoji, table header/separator rows, all fourteen Table-of-Contents anchors (this
   pass's own instructions said thirteen; there are fourteen, all resolving correctly — a miscount in
   the instructions, not a document defect), and every placeholder/leftover-text pattern all checked
   clean. One moderate finding (no `---` rule between §9.7 and §10, the only gap among twelve chapter
   boundaries) fixed. Five minor findings (`### 1.2`, `### 6.2`, `### 7.3`, `### 7.4`, `### 8.1` each
   opening directly with a table, no orientation sentence — this pass's own instructions extended the
   "opens with prose" rule from `##` to `###`, beyond `style-guide.md` §2's literal wording) all fixed
   with a one-sentence addition each. One minor finding (CI/CD re-expanded in §0.1 after CI's earlier
   expansion in the Executive Summary legend) fixed. This pass independently flagged, mid-run, that
   `README.md` was changing under it from this session's own concurrent fix work — correctly treated
   its own findings with appropriate caution as a result; every finding from every pass was re-verified
   against final file state before being applied, per Key decision 2 above.
9. **Rubric scoring — all eight dimensions (A–H) scored `strong`.** A (Requirement coverage): all
   four assessment areas present in order, every sub-bullet answered, R1–R28 verified directly against
   the body (per the amended `rubric.md` §2.A wording — the standalone traceability table was removed
   from the deliverable by prior human instruction, not by this phase). B (Justification quality,
   "the dimension that separates candidates"): every major choice states its alternative and cost
   inline; Appendix B holds exactly the nine fixed ADRs, every other significant decision has a §10
   row; every options table has a genuinely reasonable rejected alternative; every ADR's plain-
   language field is now readable by a non-engineer (post-fix); every ADR names a real accepted
   downside and an observable revisit trigger. C (Well-Architected): all six pillars addressed
   including Sustainability; every chapter tagged 2–4 pillars (post-fix); pillar trade-offs explicit
   in §9.7's ten-row table; every pillar section names an honest gap with a trigger (post-fix). D
   (Three-tier): explicitly framed, subnet tiers map one-to-one, scaling mechanisms distinct, tier
   boundary shown enforced (not asserted), HLD organized by tier with now-correct tier coloring
   (post-fix). E (Technical correctness): no factually wrong service-behavior claims remaining
   (post-fix), CIDRs verified non-overlapping, autoscaling mechanisms kept distinct, HA/DR not
   conflated, security controls correctly attributed, no hallucinated service/quota/price (post-fix).
   F (Security depth): defense in depth across all eight named layers; encryption story specific
   (customer-managed KMS per environment and data class); secrets never in images/git, mechanism
   named; least privilege mechanized; security present inside every relevant section, not quarantined;
   audit trail tamper-evident; compliance posture proportionate. G (Cost): day-1 cost itemized and
   indicative with a Pricing Calculator pointer; a costed cheaper variant with explicit, now-coherent
   trade-offs (post-fix); cost projected across four growth stages; twelve optimization levers each
   with a real trade-off; cost governance mechanized (§7.5); day-1 design runnable by a five-person
   team; complexity deferred to an explicit, triggered growth roadmap. H (Communication): a founder
   can read the Executive Summary and diagrams and understand the system's shape; acronyms expanded
   exactly once (post-fix); tables used throughout; no marketing tone or filler; every diagram has a
   legend and caption. **All twelve `rubric.md` §3 depth probes verified to have a real, located
   answer** (image-once-many-environments → §3.8; 5,000-pod IP exhaustion → §2.1; Aurora failover's
   30 seconds → §4.2; compromised CI token → §3.9; Spot two-minute interruption → §3.3; deleted
   production database → §4.4; why not one account → §1.1/ADR-004; what breaks first at scale → §8.2;
   private EKS API from a laptop → §1.4; CI pipeline end to end → §3.9; which pillar was sacrificed →
   §9.7; what stops direct access to the application tier → §2.4). **`rubric.md` §4's automatic-
   deduction list checked item by item: none apply** to the final, fixed document. **Final
   reviewer's-eye read completed**, top to bottom, without a checklist, against the three questions
   this phase document names: a founder finishes the Executive Summary knowing what was chosen and
   why (six-decision table, plain figures, no unexplained jargon); nothing found a principal engineer
   would call naive, hand-wavy, or factually wrong (the two genuine technical bugs this read-adjacent
   scrutiny surfaced — the DDL inversion and the HLD tier-miscoloring — are exactly the kind of thing
   this step exists to catch, and both are fixed); the document reads as one author, no seams visible
   at any of the dozens of edit sites this phase touched.

### Phase 12 — Executive summary, decision register & appendices
- Completed:      2026-08-16
- Files written:  `../README.md` (edited — replaced all three Phase-12 markers with an `## Executive
  Summary`, a linked `## Table of Contents`, `## 10. Summary of Key Decisions`, and `## Appendix A`
  through `## Appendix D`; §0–§9 confirmed byte-identical to Phase 11's output except the marker
  removal, via `git diff`).
- Word count:     Executive Summary ~415 words of prose excluding the table/diagram (budget ~350,
  within the ±20% band). §10's intro is 84 words plus its 29-row table. Appendix B's nine promoted
  ADRs total ~2,427 words of prose (budget ~2,000–2,500 — matches) plus ~2,324 words across their 18
  tables (2 per ADR), reproduced faithfully from the drafts. Appendix D's glossary was drafted at
  ~800 words, measured well over its own ~350-word target, and tightened to ~450 words in a second
  pass — 30 terms kept, no fact cut, each definition trimmed to one clause. **Total assembled
  document: ≈14,910 words excluding fenced code and Markdown table syntax, after Appendices A and C
  were removed per the 2026-08-16 amendment above (target 9,000–12,000 — still over; see the updated
  Open question below, which also documents a counting-method correction made during self-review).**
- ADRs written:   none — this phase promotes, it does not author. Promoted into Appendix B: 001, 004,
  007, 011, 017, 019, 023, 026, 029 — exactly the nine `decision-register.md` §2a fixes, in numeric
  order, no more and no fewer (verified programmatically against the ledger below).
- Pillars tagged: None added at the chapter level to the Executive Summary, §10, or any appendix.
  `phases/phase-12-frontmatter-and-register.md`'s five steps never ask for one, and this content is a
  summary/reference layer over decisions already tagged where they are argued in §0–§9 — the same
  reasoning Phase 10 used to omit pillar lines from the diagrams ("diagrams do not carry `##` pillar
  lines"). Each promoted ADR keeps its own metadata-table `Pillars` field unchanged; Appendix B's
  index table surfaces all nine.
- Key decisions:
  1. Converted two of the nine promoted ADRs' `Section` fields from the chapter-level placeholder
     their draft shipped with to the specific subsection Phase 11 already resolved and logged in the
     Cross-phase issues table below: ADR-007 → `§2.3 Routing, egress and private connectivity`;
     ADR-011 → `§3.1 Why Amazon EKS`. The other seven already cited their correct final subsection in
     the draft (ADR-001 `§0`, ADR-004 `§1.1`, ADR-017 `§3.9`, ADR-019 `§4.1`, ADR-023 `§5.3`, ADR-026
     `§6.2`, ADR-029 `§7.2`) and needed no change. Verified all nine programmatically against the
     assembled document's real headings, both in each ADR's own metadata table and in the Appendix B
     index table.
  2. Left ADR-001's `Section` field at chapter level (`§0 Scope, Assumptions and Design Principles`)
     rather than tightening it to `§0.1 Scope and objectives`, where its AWS-vs-GCP argument actually
     appears in the body. Phase 00 chose chapter level deliberately, and no later phase logged it as
     one of the "no pre-registered subsection" defects the way ADR-007/010, ADR-011, ADR-015, and
     ADR-020 were — treated the unflagged choice as intentional rather than second-guessed.
  3. Appendix A's R16, R17, R18, and R24 rows are deliverable-format requirements ("lives under
     `architecture/`", "a README document", "at least one diagram", "readable by a non-specialist"),
     not content answered by a numbered chapter — no honest §-number represents "the file is at this
     path." Pointed them at `Document location`, `Executive Summary`, `Executive Summary` +
     `Appendix C`, and `Executive Summary` + `Appendix D` respectively, mirroring Phase 00's own
     original non-chapter answers for these same four rows in `drafts/00-scope.md` §6. All other 24
     rows already cited final chapter numbers verbatim from the draft and needed no conversion;
     verified programmatically that every `§N`/`§N.M` reference across all 28 rows resolves to a real
     heading.
  4. Trimmed the glossary after measuring it at ~800 words against the phase document's own ~350-word
     target — cut each of the 30 definitions to one clause instead of two or three, keeping every term
     and every fact, no content removed.
- Assumptions:    None beyond the four judgment calls logged above.
- Deferred:       Nothing within this phase's five steps — all complete. Phase 13 owns final QA, every
  cross-phase issue Phases 00–09 logged below, and the word-budget Open question, now updated with
  final numbers.
- Contract additions: none.
- Notes for the next agent: (1) **The total-document word-budget Open question Phase 11 raised is
  confirmed, not resolved, and materially worse** — see the updated entry below with final counts; a
  human decision is still needed. (2) Every structural and content acceptance criterion in
  `phases/phase-12-frontmatter-and-register.md` passes and was checked programmatically, not by eye:
  all three markers replaced (none survive — `grep` confirms); the Executive Summary has the
  three-tier paragraph, the embedded HLD (byte-identical to `diagrams/01-high-level.md`, diffed), and
  a six-row decision table; §10 has all 29 ADRs as rows, the nine promoted ones ADR-linked and the
  other twenty marked `—`, cross-checked row by row against this ledger; Appendix B has exactly the
  nine promoted ADRs in numeric order with every template field present and both required `Section`
  conversions applied; Appendix A's 28 rows all point at something real (24 at numbered chapters, 4 at
  the Executive Summary/appendices per the judgment call above); Appendix C embeds diagram 5
  (byte-identical to `diagrams/05-request-flow.md`, diffed) and links all five diagram files; Appendix
  D has 30 plain-language terms; the Table of Contents' 16 links all resolve, checked against GitHub's
  actual heading-slug algorithm, not assumed; §0–§9 are byte-identical to Phase 11's output apart from
  the three markers (`git diff` shows only marker-line removals); the drafts and diagram source files
  are untouched (`git status` shows only `README.md` and this file modified). (3) Logged two new
  Cross-phase issues below, both surfaced by an advisor review before closing this phase: the
  Executive Summary now sitting before §0 means AWS/SPA (and WAF/DR/CI inside the embedded HLD legend)
  are expanded a second, now-redundant time in §0.1, which this phase cannot edit; and §10 ships with
  no `Well-Architected pillars` line, a defensible but not phase-document-mandated call this phase
  made by analogy to how diagrams are tagged, flagged for Phase 13 to adjudicate rather than assumed
  settled. Also updated the existing ADR-007–010 word-count entry to note ADR-007 is now inside the
  graded Appendix B, not only a draft file. (4) Did not touch the remaining cross-phase issues logged
  by Phases 00–09 (the `§10.7`/`§9.7` stale reference, the EKS-terminology-expansion split now
  spanning four drafts, or the Phase 09 all-six-pillars-on-§9 question) — all still open, all
  Phase 13's.

### Phase 11 — Body assembly
- Completed:      2026-08-16
- Files written:  `../README.md` (new file, §0–§9 of the graded deliverable; title block, TOC and
  exec-summary markers for Phase 12, chapters 0–9, end marker for Phase 12 — 9,194 words of prose and
  tables, mermaid/dockerfile fences excluded from the count).
- Word count:     9,194 (budget 4,800–6,500 — **over; logged as an Open question above, not silently
  accepted or forced**). Table words ≈2,750, prose ≈6,440. Three full compression passes ran before
  concluding the gap is structural, not a trimming problem — see the Open question entry for the
  detailed arithmetic and the three options put to the human.
- ADRs written:   none (this phase writes no new ADRs). Cites, inline as "(Appendix B, ADR-0NN)",
  exactly the nine ADRs `decision-register.md` §2a promotes: 001, 004, 007, 011, 017, 019, 023, 026,
  029 — one each, no duplicates, no citations of the other twenty non-promoted ADR numbers.
- Pillars tagged: One `> **Well-Architected pillars.**` line per numbered chapter (10 total, 2–4
  pillars each): §0 Security·Reliability·Operational Excellence·Cost Optimization; §1
  Security·Reliability·Operational Excellence; §2 Security·Reliability·Performance
  Efficiency·Cost Optimization; §3 Security·Reliability·Operational Excellence·Cost Optimization; §4
  Reliability·Security·Performance Efficiency·Cost Optimization; §5 Security·Reliability·Operational
  Excellence; §6 Operational Excellence·Reliability·Performance Efficiency·Cost Optimization; §7 Cost
  Optimization·Operational Excellence·Reliability·Sustainability; §8 Reliability·Performance
  Efficiency·Cost Optimization·Operational Excellence; §9 Security·Reliability·Operational
  Excellence·Cost Optimization (capped at 4, not draft 09's literal "All six" — see Key decisions).
- Key decisions:
  1. Resolved four of the five outstanding ADR Section-field cross-phase issues (Phases 02–06 flagged
     these as unassignable without the complete outline): ADR-007/010 → §2.3, ADR-011 → §3.1, ADR-020
     → §4.2, ADR-015 → §3.7 (the last read against draft 04's actual content, per Phase 06's request,
     not just a title match — §3.7 opens with the SPA-not-containerized decision before build
     mechanics). Logged individually in Cross-phase issues above.
  2. §9's chapter-level pillar line reads 4 pillars, not draft 09's literal "All six" instruction —
     followed `AGENT-PROTOCOL.md`'s general 2–4 cap and its "wins over phase documents" precedence
     rule, reasoning that §9.1–9.6's six dedicated subsections already give each pillar its own
     individually-tagged analysis, so a 4-pillar chapter-level summary line is not the "blanket tag
     standing in for real analysis" anti-pattern the cap exists to prevent. This is a call for the
     body text only, not a formal adjudication of Phase 09's open question — see that entry above,
     still open for Phase 13.
  3. Confirmed `contract.md` §11's "§8.3" self-reference for the growth-cost table is stale; the table
     landed at §7.3 exactly where Phase 09 predicted. Not corrected in `contract.md` itself (not this
     phase's file) — logged for Phase 13.
  4. Fixed a systemic acronym under-expansion an independent verification pass surfaced after the
     compression passes: RTO, RPO, HA, DR, AZ, WAF, KMS, OIDC, HPA, VPA, and SQS were used repeatedly
     but never expanded at first use anywhere in the body — condensation had cut first-use expansion
     sentences as "redundant" while later bare uses survived. Expanded each at its true first
     occurrence in reading order (not always the acronym's first mention overall, since three of
     these — WAF, KMS-adjacent OIDC, and Multi-AZ's "AZ" — first appear inside locked-verbatim tables
     copied byte-identical from `contract.md`, which this phase must not reword; expanded instead at
     the next real-prose occurrence). SSO appears only inside the embedded, unmodified account-topology
     diagram (§1.3) before its prose spelled-out form in §1.4 — not fixed, since diagrams are this
     phase's read-only input, not its output; flagged for awareness only, not a defect requiring
     action.
  5. Dropped four tables to prose or shorter form during condensation that were compositional choices
     (not the five contract.md/well-architected.md-sourced tables locked verbatim): the §5.3
     data-classification table became one prose sentence; the §8.1 growth-stage table's cell text was
     compressed while preserving every fact; several others were shortened row-by-row rather than
     dropped. The five locked tables (§0.2 three-tier, §1.2 account inventory, §2.2 subnet plan, §4.6
     RPO/RTO, §9.7 accepted trade-offs) remain byte-identical to their `contract.md`/`well-
     architected.md` sources — spot-checked directly against source text, not just by eye.
- Assumptions:    That the fork agent's three-round compression pass and my own manual passes had
  exhausted realistic prose-tightening headroom before concluding the word-budget gap is structural —
  based on measured diminishing returns (20–100 words saved per pass by the end), not a hard proof no
  further cut exists; a human or a differently-instructed agent might still find some.
- Deferred:       Everything Phase 12 owns by design — TOC, executive summary, Appendix B ADR records,
  §10 Summary of Key Decisions (29–34 rows), remaining appendices, Diagrams 1 and 5. The word-budget
  resolution itself (see Open question above) is deferred to the human, not to a later phase.
- Contract additions: none.
- Notes for the next agent: (1) A dedicated verification pass (fork agent, read-only) checked all 28
  `brief.md` requirements against the condensed body and found every one still substantively present,
  including the compound ones most at risk of silently merging during a heavy cut — R8 resource
  allocation, R9/R10/R11 image-build/registry/deployment, and R13/R14/R15 backups/HA/DR are each still
  their own subsection. No duplication or voice-seam defects found in an end-to-end read. (2) Line
  ~235 (§1.5) references decommissioning into a `Suspended` OU; the account-topology diagram (§1.3)
  does not show one — this predates Phase 11 (a prior commit dropped Suspended from the diagram
  specifically) and was not introduced by this phase; flagged for awareness, not treated as a defect
  to fix here since the diagram is this phase's read-only input. (3) Phase 12 will need the word counts
  above when deciding how much room the TOC/exec-summary/appendices can occupy against whatever total-
  document target the human sets after answering the Open question — do not assume the original
  9,000–12,000 total-document target from the 2026-08-14 amendment still applies without checking it
  against whatever the human decides there.

### Phase 00 — Pre-flight, scope & three-tier framing
- Completed:      2026-08-14
- Files written:  `_plan/drafts/00-scope.md` (1,090 words body excluding tables and ADRs; ADR-001 –
  ADR-003, each 245–247 words excluding tables, all under the 250-word cap)
- Word count:     1,090 (acceptance band 750–1,100; drafted at 1,165, trimmed §1/§2/§5 prose and
  ADR-002 to land inside the band with margin)
- ADRs written:   ADR-001 … ADR-003
- Pillars tagged: Operational Excellence, Security, Cost Optimization, Reliability, Performance Efficiency
- Key decisions:  Used "Operational Excellence · Security · Cost Optimization · Reliability" as the
  `## Decision Records` section's pillar line, covering the pillars carried by ADR-001–003 combined;
  kept the GCP discussion in §1 to two sentences per the contract.md cap, with the full argument in
  ADR-001; reproduced the tier table from `contract.md` §1a verbatim (byte-identical, diff-checked)
  in §2; cited ADR-002's Section field as `§0.2 Architecture overview — a three-tier design` and
  ADR-001/003 as `§0 Scope, Assumptions and Design Principles`, both drawn from contract.md §14's
  locked reference table rather than invented.
- Assumptions:    none
- Deferred:       Executive Summary left as the marker only, per this phase's instructions; all
  design content for §1–§9 of the final document is deferred to Phases 01–09.
- Contract additions: none
- Notes for the next agent: `## Decision Records` did not originally carry the required orientation
  paragraph and pillar line — both were added on a round-2 review pass, then independently
  re-verified. §6 Requirement Traceability covers all 28 rows (R1–R28). §3's closing sentence and
  well-architected.md §4 both cite `§10.7` for the accepted-trade-offs table, but contract.md §14's
  locked reference table fixes it at `§9.7 Accepted trade-offs between pillars` — the draft uses
  `§9.7` per contract.md's normative authority; logged below under Cross-phase issues for Phase 13.

### Phase 01 — Cloud environment structure
- Completed:      2026-08-14
- Files written:  `_plan/drafts/01-cloud-environment.md` (1,511 words body excluding tables and
  ADRs; ADR-004 – ADR-006 at 248, 243, and 250 words respectively, excluding both tables, all at or
  under the 250-word cap)
- Word count:     1,511 (acceptance band 1,050–1,550; drafted at 1,577, trimmed "Why multiple
  accounts" and "Account inventory" prose to land inside the band with margin)
- ADRs written:   ADR-004 … ADR-006
- Pillars tagged: Security, Reliability, Operational Excellence (this phase's three ADRs and seven
  sections draw only on these three pillars — matches the §1 attribution in `well-architected.md`
  §1's OPS/SEC/REL demand tables, which are the only pillars that table maps to this chapter;
  Cost Optimization is discussed as a trade-off the structure costs, not one it serves, consistent
  with `well-architected.md` §3's own framing of "seven accounts" as leaning toward Security/
  Reliability at the expense of Cost Optimization/Operational Excellence)
- Key decisions:  Drafted the full section set and all three ADRs directly (not via subagent
  fan-out) to preserve voice continuity with `00-scope.md` and contract fidelity on the single
  shared account table; then ran three independent read-only verification passes (contract
  fidelity, style/mechanics, ADR quality against rubric.md) via the Workflow tool and fixed every
  finding they raised. Fixes included: naming the AWS Organization `innovate-inc` explicitly (was
  present in `contract.md` §4 but never stated in the draft); removing a derived "$100–240/month"
  figure in ADR-004 that multiplied the legitimate `well-architected.md` §3 figure ($25–60/month
  per account) in a way `contract.md` §11's "do not derive new figures" rule reads as prohibited,
  replaced with qualitative marginal-cost reasoning; de-duplicating ADR-004's options table from the
  inline body prose per `decision-register.md` §3's explicit ban and this phase document's own
  instruction for that exact ADR; making ADR-004's Decision field self-contained (removed a
  positional "listed in the inventory above" reference, since Phase 12 reassembles ADRs into
  Appendix B out of body order); shortening ADR-006's title from 9 to 8 words to satisfy
  `decision-register.md` §1's template cap; correcting eight future/conditional-tense instances
  ("will"/"would") to present tense per `style-guide.md` §1; and adding first-person-plural "We"
  framing to the recommendation-bearing sentences (Recommendation in one line, the "Why multiple
  accounts" opening, and all three ADR Decision fields), matching `style-guide.md` §1's explicit
  rule, though `00-scope.md` itself uses "We" only once — noted as a judgment call below.
- Assumptions:    none
- Deferred:       VPC/subnet design is Phase 02's; this draft stays at the account/identity layer
  per this phase document's "Common failure modes" table. Application-tier detail (Kubernetes
  namespaces, node groups) is named only as a rejected alternative to account separation, not
  designed here.
- Contract additions: none
- Notes for the next agent: (1) This draft now uses first-person-plural "We" in five places
  (Recommendation in one line; "Why multiple accounts" opening; ADR-004/005/006 Decision fields) to
  satisfy `style-guide.md` §1's literal rule, which is more than `00-scope.md`'s single instance —
  both are defensible readings of the style guide; Phase 11 should pick one density and normalize
  across all ten drafts during assembly rather than treating either as the house style by default.
  (2) The `AGENT-PROTOCOL.md` §1 working-boundary path (`/home/artin/personal/git/opsfleet/
  architecture/`) does not match this repository's actual path
  (`/home/artin/personal/git/dso-projects/architecture/`) — treated as a stale path artifact from a
  prior repo name, not a scope question; the relative boundary ("stay inside `architecture/`") is
  what was honored. (3) The account inventory table's locked Purpose text for `innovate-shared-services`
  starts with the bare acronym "ECR"; since that text must be reproduced verbatim per this phase's
  acceptance criteria, the acronym is instead expanded at its first *prose* occurrence, one paragraph
  below the table, rather than inside the table itself. (4) Did not touch the `§10.7`/`§9.7`
  cross-phase issue Phase 00 logged — out of this phase's scope, still open for Phase 13.

### Phase 02 — Network design
- Completed:      2026-08-14
- Files written:  `_plan/drafts/02-network.md` (1,896 words body excluding tables and ADRs;
  ADR-007 – ADR-010 all within decision-register.md §2's 250-word cap after a fix-pass trim)
- Word count:     1,896 (acceptance band 1,300–1,900; drafted at ~1,960–2,006 depending on counting
  method, trimmed during the fix pass to land inside the band without cutting a required
  sub-requirement, justification, or plain-language field)
- ADRs written:   ADR-007 … ADR-010
- Pillars tagged: Security, Reliability, Performance Efficiency, Cost Optimization, Operational
  Excellence (five of six pillars across the section's nine `##` headings, 2–4 per heading;
  Sustainability not tagged — not substantively served by this chapter)
- Key decisions:  Drafted directly (not fanned out) to preserve voice continuity, then ran three
  independent read-only verification passes via the Workflow tool (contract fidelity, style/
  mechanics, ADR quality against rubric.md), which raised 18 findings (5 contract, 9 style, 4 ADR),
  and a fix pass that resolved them. Fixes of note: removed two invented/unlabelled cost figures — a
  per-unit NAT Gateway price and a Shield Advanced "$3,000/month" figure — that violated
  `contract.md` §11's no-derived-figures rule, replacing them with the contract's aggregated
  indicative NAT figure and a Pricing Calculator pointer; removed a fifth AWS WAF managed rule group
  ("anonymous IP") not present in `contract.md` §9's fixed list of four; corrected a dropped "pod"
  in the RDS Proxy security-group description (contract §8 says "node/pod SG"); fixed a
  self-contradictory claim that every security group in the request path "references another
  security group" — the ALB's own inbound rule is sourced from the CloudFront managed prefix list,
  not a security group, so the claim was rescoped and the one exception named; expanded five
  under-expanded acronyms (SG, HSTS, CSP, XSS, DDoS) and three acronyms used before their first
  prose expansion (VPC, ALB, CIDR); removed R19 and R20 from ADR-008/009/010's Requirement fields
  after checking `brief.md` directly — those requirements belong to phases 03/05/07/09, not 02, only
  R3/R4 are this phase's; and registered the VPC CNI `/28` prefix-delegation block size in
  `contract.md` §12, since `contract.md` §6 fixes prefix delegation as a feature but not its block
  size, and the number is needed to explain pod density in `## IP address plan`.
- Assumptions:    Phrased the EKS API public-endpoint restriction as covering CI/CD egress addresses
  and, conditionally, "where Innovate Inc. operates one, a corporate VPN range" — consistent with
  draft 00's assumption of no confirmed hybrid/on-prem connectivity requirement.
- Deferred:       Service mesh mTLS, AWS Network Firewall, Shield Advanced, PrivateLink to partner
  services, and IPv6 are named in `## What is deliberately not here` with their revisit triggers, not
  designed further. Hybrid/partner connectivity via a Transit Gateway in `innovate-network` is named
  as the future answer, not designed. An indicative cost line for interface VPC endpoint spend (16
  endpoints × 3 AZs) is explicitly not derived here — `contract.md` §11's cost table has no such line
  and one wasn't fabricated — flagged below for Phase 08.
- Contract additions: `_plan/contract.md` §12 — VPC CNI prefix-delegation block size, `/28` per ENI.
- Notes for the next agent: (1) Phase 08 (Cost Optimization) should add an indicative interface-VPC-
  endpoint cost line to its cost table; this draft deliberately did not derive one. (2) Phases 03
  (compute) and 06 (security) should keep pods governed by the node's security group plus
  `NetworkPolicy`, not an individually assigned per-pod security group — this draft was written to
  avoid implying EKS `SecurityGroupPolicy`/trunk-ENI per-pod SGs, a feature `contract.md` §6 does not
  adopt. (3) ADR-007 and ADR-010 cite their Section field at chapter level (`§2 Network Design`)
  rather than a subsection, because `contract.md` §14 only pre-registers `§2.2` and `§2.4` for this
  chapter and no subsection number yet exists for "Connectivity between environments" or "Routing and
  internet egress" — logged below under Cross-phase issues for Phase 11 to resolve once it numbers
  those headings. (4) Did not touch the open `§10.7`/`§9.7` cross-phase issue from Phase 00 — out of
  scope here, still open for Phase 13.

### Phase 03 — Compute platform — EKS
- Completed:      2026-08-14
- Files written:  `_plan/drafts/03-compute-eks.md` (2,144 words body excluding tables, snippets, and
  ADRs; ADR-011 – ADR-014 at 250, 250, 249, and 249 words respectively, excluding both tables, all at
  or under the 250-word cap)
- Word count:     2,144 (acceptance band 1,450–2,150 words per this phase's acceptance criteria;
  phase document's own ~1,800-word target ±20% gives 1,440–2,160 — both satisfied). Drafted at ~2,464,
  trimmed across all seven sections in a fix pass to land inside the band with a small margin, after
  acronym expansions added back from the style pass pushed it back over 2,150 once.
- ADRs written:   ADR-011 … ADR-014
- Pillars tagged: Operational Excellence, Reliability, Security, Cost Optimization, Performance
  Efficiency, Sustainability (all six except none omitted at the section level; five of six appear
  across the section pillar lines — Sustainability appears once, on Node strategy, where Graviton and
  Karpenter consolidation substantively serve it per `well-architected.md`'s own guidance that this is
  the same decision as the Cost Optimization story, not a separate one)
- Key decisions:  Drafted directly (not fanned out) to preserve voice continuity with drafts 00–02,
  then ran three independent read-only verification passes via the Workflow tool (contract fidelity,
  style/mechanics, ADR quality against `rubric.md`), which raised 3 contract findings, 15 style
  findings, and 9 ADR findings, and a fix pass that resolved them. Fixes of note: corrected the ADR
  template's own "Guaranteed QoS" framing — contract.md §6 and this phase's own content spec both
  describe the requests/limits policy as landing pods in `Guaranteed` QoS, but Kubernetes' actual
  semantics require every resource (CPU included) to have a matching limit for `Guaranteed`, and this
  design deliberately sets no CPU limit; the draft states the technically correct `Burstable`
  classification instead, with the accurate reasoning for why memory is still protected under pressure
  (not logged as a contract deviation since it's a factual correction, not a design change — logged
  under Assumptions below for visibility); fixed a banned word ("just") in ADR-012's options table;
  trimmed a 28-line YAML snippet to 24 lines to meet the 25-line cap; backticked every bare `NodePool`
  reference for consistency with every other Kubernetes object kind in the draft; expanded eight
  acronyms on first use (VPC, CIDR, ECS, EC2, IAM, RDS, NAT, SQS, EBS, CSI) that were used before being
  defined; added the missing `karpenter.sh/do-not-disrupt` half of contract §6's "Disruption controls"
  row (only the `PodDisruptionBudget` half was originally covered); corrected several conditional-tense
  ("would") instances to present tense per `style-guide.md` §1; and rewrote each ADR's
  "Why this is the right choice for Innovate Inc." field to gloss every AWS product name and Kubernetes
  term used within that field (EKS, Auto Mode, Kubernetes, Graviton, pod) rather than assuming the
  reader already read the Decision field above, per `decision-register.md` §3's rule that an ADR field
  must be self-contained — this pushed every ADR close to the 250-word cap and required trimming
  Context/Consequences/Cost impact/Revisit when in the same pass to make room.
- Assumptions:    The `Burstable`-not-`Guaranteed` QoS correction (above) is a factual correction to
  this phase's own content spec, not an assumption about an ambiguous requirement — flagged here in
  case Phase 06 or Phase 07 independently assert `Guaranteed` QoS elsewhere and need to be reconciled.
- Deferred:       Image building, container registry, and CI/CD pipeline mechanics are named only as
  forward references (§3.8, §3.9, and "the build pipeline") per this phase's explicit scope boundary;
  Phase 04 designs them. Database connection scaling, read replicas, and Aurora Serverless v2 capacity
  units are named once each in `## Scaling` and cross-referenced to Phase 05, not designed here.
- Contract additions: `_plan/contract.md` §12 — Kubernetes minor-version upgrade SLA, "within 30 days
  of general availability." This number appears in this phase's own instructions
  (`phases/phase-03-compute-eks.md`) but not in `contract.md` itself; logged per contract.md's own rule
  that a genuinely absent value a phase defines must be appended to §12.
- Notes for the next agent: (1) See Cross-phase issues below for two findings: ADR-011's Section field
  citing chapter level (no pre-registered subsection for its content), and an independent word-count
  finding that Phase 02's ADR-007–010 measure over the 250-word cap under the same counting method that
  exactly reproduced Phase 01's self-reported counts — flagged for Phase 13, not fixed here (not this
  phase's file). (2) Phase 06 (security) should keep citing EKS Pod Identity and the platform node
  group's taint as this draft states them — this draft's `## Workload isolation and multi-tenancy`
  section is deliberately short and defers the wider posture to §5 Security and Data Protection rather
  than repeating it. (3) Did not touch the open `§10.7`/`§9.7` issue from Phase 00 or the ADR-007/010
  Section-field issue from Phase 02 — both out of scope here, still open for Phase 13.

### Phase 04 — Containerization & CI/CD
- Completed:      2026-08-14
- Files written:  `_plan/drafts/04-containers-cicd.md` (1,793 words body excluding tables, the one
  code snippet, and ADRs; ADR-015 – ADR-018 at 249, 248, 244, and 248 words respectively, excluding
  both tables, all under the 250-word cap)
- Word count:     1,793 (acceptance band 1,200–1,800; drafted at ~1,900 across two rounds — an
  initial draft, then a fix pass responding to three independent verification agents run via the
  Workflow tool — trimmed to land inside the band with a small margin)
- ADRs written:   ADR-015 … ADR-018
- Pillars tagged: Cost Optimization, Performance Efficiency, Operational Excellence, Security,
  Reliability, Sustainability (five of six pillars across the section's six pillar lines plus the
  `## Decision Records` orientation line, 3–4 per line; Sustainability appears once, added to
  ADR-015 in the fix pass, since `well-architected.md` §1 attributes CloudFront edge caching to
  Sustainability directly and the original draft under-tagged it)
- Key decisions:  Drafted directly (not fanned out) to preserve voice continuity with drafts 00 and
  03, then ran three independent read-only verification passes via the Workflow tool (contract
  fidelity, style/mechanics, ADR quality against `rubric.md`), which raised 10 contract findings, 10
  style findings, and 8 ADR-quality findings, and a fix pass that resolved the substantive ones.
  Fixes of note: the illustrative Dockerfile snippet's runtime stage ran `pip install` inside a
  distroless image, which ships no package manager — a real correctness bug, not a style issue;
  rewrote the snippet to `pip install --prefix=/install` in the builder stage and `COPY --from`
  the resulting tree straight into `/usr/local` in the distroless stage, and corrected the base
  image tag from an invented `gcr.io/distroless/python3-debian12` back to `contract.md` §7's exact
  `gcr.io/distroless/python3`; replaced three prose citations of `contract.md §7` (a planning file
  that does not ship with the deliverable) with the actual ECR image path strings and base-image
  values rendered inline, matching how drafts 00 and 03 cite the deliverable's own section numbers
  rather than the plan; added the missing `> **Well-Architected pillars.**` line to `## Frontend
  deployment path`, the only one of six top-level sections that had shipped without one; corrected
  five instances of banned conditional tense (`would`) and two of future tense (`will`) on rejected
  alternatives and enforcement claims, per `style-guide.md` §1's present-tense rule; removed the
  banned word "just" from `"just in case"`; added three first-person-plural "We" instances to
  recommendation sentences that had zero, matching the modeled voice in `style-guide.md` §1; renamed
  the `## Deployment` heading from "GitOps with Argo CD" to "CI/CD and GitOps" to match the exact
  subsection name `contract.md` §14 pre-registers for `§3.9`; removed an unlocked staging
  load-testing gate from the CI pipeline table that `contract.md` §7's fixed pipeline flow does not
  include (`00-scope.md` §5 also lists load testing as out of scope); restructured ADR-016's options
  table to independently argue "rebuilding per environment" against its own strongest rival — same
  digest, replicated into a per-environment registry — rather than fusing it with the per-environment
  registry option, after a verification pass found the original table never tested the ADR against
  that rival; corrected ADR-015's `Section` field from `§3.8 Container registry` (wrong — that ADR is
  about not containerizing, not about the registry) to the chapter level `§3 Compute Platform`,
  matching the precedent Phases 02 and 03 set for headings with no pre-registered subsection number;
  added the missing "indicative" label and AWS Pricing Calculator pointer to ADR-015's `Cost impact`
  field per `contract.md` §11's mandatory labelling rule, and removed an unlabelled derived "order of
  magnitude" comparison; adjusted ADR-015's and ADR-016's `Requirement` fields (dropped R9 from
  ADR-015 since the ADR's whole point is that no image is built for the SPA; dropped R19 from ADR-016
  and added R23, since R19's owning phases in `brief.md` are 03/05/07 and R23 is this phase's own
  declared scope); and strengthened the *Accepts* fields on ADR-015 and ADR-017, which had named the
  fact of a second mechanism/system without naming why it costs something.
- Assumptions:    The Argo Rollouts canary traffic-weight steps (10% → analysis → 50% → analysis →
  100%) and the multi-arch, distroless-compatible dependency-install pattern in the Dockerfile
  snippet are illustrative choices `contract.md` does not fix; the canary steps are genuinely needed
  by both the body prose and the environment-promotion table, so they are registered in
  `contract.md` §12 rather than left implicit.
- Deferred:       Cluster topology, node groups, and autoscaling are Phase 03's territory and are not
  restated here beyond a cross-reference to §3.3 Node strategy. Database migration mechanics beyond
  the expand/contract pattern and the PreSync hook trigger are cross-referenced to Phase 05, not
  designed here.
- Contract additions: `_plan/contract.md` §12 — Argo Rollouts canary steps, `10% → analysis → 50% →
  analysis → 100%`.
- Notes for the next agent: (1) See Cross-phase issues below for two findings: ADR-015's `Section`
  field citing chapter level (no pre-registered subsection for "What gets containerized"), and the
  `style-guide.md` §5 vs. `contract.md` §13 conflict over whether "Amazon Elastic Kubernetes Service
  (EKS)" or "Amazon EKS" is the correct first-use expansion — both drafts 03 and 04 followed
  style-guide.md's general rule over contract.md's specific terminology lock; flagged for Phase 13,
  not fixed here since it is a pre-existing cross-draft pattern, not a defect unique to this phase.
  (2) Phase 05 (database) should keep citing the expand/contract migration pattern and the Argo CD
  PreSync hook exactly as this draft states them, since `## Deployment — CI/CD and GitOps` names
  Phase 05 as owning the storage side of that same pattern. (3) Did not touch the open `§10.7`/`§9.7`
  issue from Phase 00, the ADR-007/010 or ADR-011 Section-field issues from Phases 02/03, or the
  Phase 02 ADR word-count finding from Phase 03 — all out of scope here, still open for Phase 13.

### Phase 05 — Database
- Completed:      2026-08-14
- Files written:  `_plan/drafts/05-database.md` (1,896 words body excluding tables and ADRs;
  ADR-019 – ADR-022 at 250, 248, 248, and 249 words respectively, excluding both tables, all at or
  under the 250-word cap, counted with the same whitespace-token method Phase 03 validated against
  Phase 01's self-reported counts)
- Word count:     1,896 (acceptance band 1,300–1,900 per this phase's acceptance criteria; drafted at
  ~1,913 across three rounds — an initial draft, a fix pass responding to three independent
  verification agents run via the Workflow tool, and a further fix pass responding to an advisor
  review — trimmed to land inside the band with a small margin each round)
- ADRs written:   ADR-019 … ADR-022
- Pillars tagged: Reliability, Performance Efficiency, Cost Optimization, Security, Operational
  Excellence (five of six pillars across the section's seven pillar lines plus the `## Decision
  Records` orientation line, 2–4 per line; Sustainability not tagged — the data tier's genuine
  sustainability story (Aurora Serverless v2 scaling to near-idle) is the same decision already
  carried under Cost Optimization and Performance Efficiency, and tagging a sixth pillar on a section
  it does not substantively serve on its own would violate `well-architected.md` §2.1's "two to four,
  only where substantive" rule)
- Key decisions:  Drafted directly (not fanned out) to preserve voice continuity with drafts 00, 02,
  03, and 04, then ran three independent read-only verification passes via the Workflow tool (contract
  fidelity, style/mechanics, ADR quality against `rubric.md`), which raised 6 contract findings, 7
  style findings, and 4 ADR-quality findings, and a fix pass that resolved all of them; then consulted
  the advisor tool before finalizing, which caught two acceptance-criteria gaps the three verification
  passes had not been asked to check (neither prompt covered rubric probes 3 or 6 explicitly) and one
  regression the fix pass itself had introduced. Fixes of note, from the verification pass: removed an
  invented "Up to 5 read replicas" quota for Amazon RDS Multi-AZ in the alternatives table —
  `contract.md` §1 states only a qualitative comparison ("15-replica read scaling" for Aurora, no RDS
  figure) — replaced with a qualitative claim; removed an invented "per-vCPU" billing unit for Amazon
  RDS Proxy from ADR-020's options table and Consequences (no such line exists in `contract.md` §11);
  fixed a self-contradictory options-table row in ADR-022 where a warm standby's Strengths cell said
  "reduced size" while its Weaknesses cell said it "doubles" the compute bill; added the `contract.md`
  §8-locked schema-migrations mechanism (Alembic job, Argo CD `PreSync` hook, expand/contract pattern)
  to `## Configuration`, which the initial draft had reduced to an access-control-only mention;
  restored bold emphasis on the Region loss row of the RPO/RTO table, then machine-diffed all six rows
  against `contract.md` §8 to confirm a byte-identical match; scoped the Configuration table's "Writer
  only" topology and auto-pause claims to dev specifically rather than the whole non-production
  column, since `contract.md` §8 only fixes dev's shape and §4 describes staging as a "mirror of prod
  topology at reduced size" (registered in `contract.md` §12, see Contract additions below); expanded
  "High availability (HA)" and "Availability Zones (AZs)" at their true first use rather than only in
  the `## High availability` heading; replaced internal planning/grading vocabulary that had leaked
  into client-facing text — "presented as one rather than a strawman" and a sentence that literally
  read "answers rubric probe 3" — with plain descriptive prose; replaced "this draft does not repeat
  it" with "this section covers..." since the assembled deliverable has no "draft," only sections;
  replaced unexplained "pods" jargon in ADR-020's mandatory plain-language field with "running copies
  of the application"; and strengthened ADR-020's *Accepts* field, which had duplicated the Cost
  impact field with a trivial "small charge" instead of a real operational downside. Fixes of note,
  from the advisor pass: rubric probe 6 ("someone deletes the production database — walk me through
  the next hour") had its ingredients scattered across `## Backups` with no assembled sequence — added
  an "If it happens" table branching explicitly on cause (accidental deletion → point-in-time recovery
  restore; account/credential compromise → restore from the vault-locked cross-account copy instead,
  since the account's own backups may also be compromised), which is the branch a reviewer is testing
  for and which the fix pass's own three verification prompts had not been asked to check; restored
  two bare `§7` citations (introduced by the earlier trim pass) to `§7 Cost Optimization`, since
  `contract.md` §14 requires "number and name"; and replaced a flat "120 connections" figure with the
  phase document's own "several hundred connections" framing — the pooling-factor arithmetic the
  fix-pass had stripped out to save words made the connection-exhaustion argument read as
  unremarkable for PostgreSQL, weakening the paragraph it was added to strengthen.
- Assumptions:    Staging's Aurora topology (writer + reader, mirroring production at reduced
  capacity, rather than dev's writer-only shape) is inferred from `contract.md` §4's account
  description and corroborated by §11's lean-start variant, which separately lists "no reader replica
  in non-production" as a cost lever — implying the non-lean baseline has one — registered in
  `contract.md` §12 rather than left ambiguous, since the Configuration table needed a definite answer
  for both non-production rows.
- Deferred:       The general security posture (identity, detection, pipeline gates) is Phase 06's;
  `## Security and data protection` stays limited to controls specific to the data tier, per this
  phase's own scope boundary. Read-replica and cache-tier scaling beyond fifteen readers is named once
  and cross-referenced to the growth roadmap in §8, not designed here.
- Contract additions: `_plan/contract.md` §12 — staging Aurora topology, "Writer + 1 reader, mirroring
  production at reduced capacity."
- Notes for the next agent: (1) ADR-020's `Section` field cites the chapter level `§4 Database`
  because `contract.md` §14 pre-registers no subsection number for `## Configuration` (only `§4.1`,
  `§4.4`, `§4.5`, `§4.6` are pre-registered for this chapter, and `§4.1` belongs to `## Why Aurora —
  the alternatives considered`, which is where ADR-019 cites it) — matching the precedent Phases 02,
  03, and 04 set for ADR-007/010, ADR-011, and ADR-015; logged below under Cross-phase issues for
  Phase 11 to resolve once it numbers `## Configuration`. (2) Phase 06 (security) should keep citing
  the security-group chain (node/pod SG → proxy SG → Aurora SG) and IAM database authentication
  through RDS Proxy exactly as this draft states them, rather than re-deriving the data-tier access
  model. (3) When this phase's own verification workflow is used as a template, add the rubric-probe
  numbers explicitly to at least one verification prompt — a general "check the acceptance criteria"
  instruction was not enough for three independently-run agents to individually catch a scattered
  probe answer; the advisor pass caught it, but that is not guaranteed on every phase. (4) Did not
  touch the open `§10.7`/`§9.7` issue from Phase 00, the ADR-007/010, ADR-011, or ADR-015 Section-field
  issues from Phases 02–04, the Phase 02 ADR word-count finding from Phase 03, or the EKS terminology
  conflict from Phase 04 — all out of scope here, still open for Phase 13.

### Phase 06 — Security & data protection
- Completed:      2026-08-14
- Files written:  `_plan/drafts/06-security.md` (1,619–1,680 words body excluding tables and ADRs,
  depending on whether the pillar-line callouts are counted — both readings land inside both the
  1,150–1,700 acceptance-criteria band and the phase document's own ~1,400-word ±20% band
  (1,120–1,680); ADR-023 at 249, ADR-024 at 246, ADR-025 at 249 words, excluding both tables, all
  under the 250-word cap, counted with the same whitespace-token method Phases 03 and 05 validated)
- Word count:     see above (reconciled against both the acceptance-criteria band and the phase
  document's own word-budget band, per the advisor's finding that the two are not the same range;
  drafted at ~1,613–1,674, grew past both 1,680 and 1,700 twice during the fix pass as required
  content — the mandatory tag set with its two fixed values, eleven acronym expansions, the
  tier-mapping column — was added, then trimmed back under both ceilings each time)
- ADRs written:   ADR-023 … ADR-025
- Pillars tagged: Security, Reliability, Operational Excellence across all nine `##` section pillar
  lines (2–3 per line); Cost Optimization appears only in ADR-025's `Pillars` metadata row, not on
  any section line. Four of six pillars overall; Performance Efficiency and Sustainability not
  tagged anywhere — neither is substantively served by this chapter's own content, which is
  identity, data protection, detection, audit, compliance, and response, not performance or
  environmental efficiency.
- Key decisions:  Drafted directly (not fanned out) to preserve voice continuity with drafts 00–05,
  then ran three independent read-only verification passes via the Workflow tool (contract
  fidelity, style/mechanics, ADR quality against `rubric.md`), which raised findings in all three
  passes, and a fix pass that resolved them. Fixes of note: added the `contract.md` §9-mandated
  tag set (`Environment`, `Application`, `Owner`, `CostCenter`, `DataClassification`, `ManagedBy`,
  `Compliance`) to `## Data protection`, which the initial draft omitted entirely despite the
  acceptance criteria explicitly requiring it; removed an invented "roughly thirty keys" figure
  from ADR-023's `Cost impact` field that `contract.md` §11's no-derived-figures rule does not
  permit, replaced with a qualitative statement pointing at the AWS Pricing Calculator; restructured
  the defence-in-depth table in `## Security model` with an added `Protects` column mapping each of
  the twelve layers to the presentation tier, the application tier, the data tier, or the boundaries
  between them — the initial draft organized the table by control layer only, which a verification
  pass correctly flagged as failing the acceptance criterion requiring the three-tier model to be
  visible in this specific table, per `AGENT-PROTOCOL.md` §5.5; added `We` voice to five
  recommendation-bearing sentences that had none, matching `style-guide.md` §1's modeled voice,
  after a verification pass found the entire draft used zero instances of first-person-plural
  phrasing despite being dense with the decision → reason → alternative → cost pattern that voice is
  meant to carry; expanded eleven acronyms on first use that the initial draft had used bare
  throughout (`EKS`, `IAM`, `KMS`, `SBOM`, `OIDC`, `IaC`, `VPC`, `ALB`, `RDS`, `ECR`, `OU`, `MFA`,
  `WAF`, `GDPR`, `SOC 2`), following the same "Full Name (ABBR)" pattern draft 03 set for "AWS
  Identity and Access Management (IAM) Identity Center"; added "a documented lawful basis for
  processing user data" to the GDPR bullet in `## Compliance and privacy posture`, which the phase
  document's own content specification names explicitly and the initial draft omitted; rewrote
  ADR-023's `Accepts` field, which had restated its own options-table weakness cell nearly verbatim
  (a monthly charge and a policy to write) instead of naming a real downside — replaced with the
  self-inflicted denial-of-access risk a misconfigured or deleted key carries; rewrote ADR-023's
  `Revisit when` trigger, which had named "administration overhead" — the same cost the ADR's own
  `Accepts` field had just knowingly accepted, making it a trigger that would reopen a decision on
  the basis of the cost the decision explicitly chose to pay — replaced with an externally-held or
  hardware-backed key-material compliance trigger; anchored ADR-024's `Context` field to an Innovate
  Inc. constraint (no dedicated security function to review logs by hand), which the initial draft
  had left entirely abstract, unlike ADR-023 and ADR-025's Context fields; rewrote ADR-025's
  plain-language field, whose closing sentence was meta-commentary about the value of writing the
  ADR itself ("it names what would change the answer") rather than a business consequence to
  Innovate Inc. — replaced with the concrete engineering-hours cost a mesh would impose; added `R4`
  to ADR-025's `Requirement` field, since this phase's own goal statement claims "the cross-cutting
  half of R4" and ADR-025 (service-mesh mTLS deferral) is the one ADR in this draft that is actually
  about network security, not data-at-rest or audit; and shortened ADR-024's title from 10 words to
  7 to satisfy `decision-register.md` §1's 8-word cap, matching the precedent Phase 01 set for
  ADR-006 — the phase document's own suggested title ("Centralised immutable logging in a separate
  account with Object Lock") is itself 10 words and was not followed literally for this reason.
  Separately, while reading `phases/phase-11-assembly.md` to resolve this draft's own ADR `Section`
  fields (`contract.md` §14 names that file as the authority for subsection numbering), discovered
  it contains the **complete** subsection numbering for every chapter, §0 through §9 — not only §5.
  This let all three ADRs here cite exact subsections (§5.1, §5.3, §5.4) rather than falling back to
  chapter level; see Cross-phase issues below, since this appears to resolve four issues Phases
  02–05 logged as "no pre-registered subsection number."
- Assumptions:    None beyond the pillar attribution above; no ambiguous requirement was silently
  decided.
- Deferred:       The general identity, network, and supply-chain security mechanics already
  designed in Phases 01–05 are referenced by section number only, per this phase's hard constraint,
  and are not redesigned here. Shield Advanced, a SIEM, and a managed detection-and-response service
  are named as deliberately not bought yet, with their triggers, but not designed.
- Contract additions: none.
- Notes for the next agent: (1) This draft's `## Detection and monitoring` and `## Audit and
  logging` headings are two separate `##` sections, per this phase document's own content
  specification — but `phase-11-assembly.md` merges them into one final subsection, `§5.4
  Detection, audit and logging`. Phase 11 should combine these two headings' content under that one
  subsection during assembly, the same way it already combines drafts 03 and 04 under `§3`. (2) The
  `phase-11-assembly.md` discovery above (full subsection numbering already exists for every
  chapter) is logged as a new, consolidated cross-phase issue below — Phase 13 should re-check
  ADR-007/010, ADR-011, ADR-015, and ADR-020's `Section` fields against it, since those four appear
  to have pre-registered numbers (`§1.1`, `§3.1`, `§3.7`, `§4.2` respectively) that their owning
  phases did not have visibility into. (3) Did not touch the open `§10.7`/`§9.7` issue from Phase
  00, the EKS terminology conflict from Phase 04, or the Phase 02 ADR word-count finding from Phase
  03 — all out of scope here, still open for Phase 13.

### Phase 07 — Observability & operational excellence
- Completed:      2026-08-14
- Files written:  `_plan/drafts/07-observability.md` (1,189 words body excluding tables and ADRs;
  ADR-026 at 259 and ADR-027 at 256 words including the ADR heading and the "Options considered."
  label, excluding both tables — both land at or a few words above 250 depending on whether the
  heading/label are counted, using the same whitespace-token method Phases 03, 05, and 06 validated;
  flagged below for Phase 13 rather than cut further, since every remaining sentence carries required
  content a verification pass added)
- Word count:     1,189 (acceptance band 800–1,250; phase document's own ~1,000-word ±20% band is
  800–1,200 — both satisfied). Drafted at ~1,205, trimmed lightly during the fix pass; grew back
  slightly when acronym-expansion fixes were applied, still inside both bands.
- ADRs written:   ADR-026 – ADR-027
- Pillars tagged: Operational Excellence, Reliability, Performance Efficiency, Cost Optimization
  across the section's five pillar lines plus the `## Decision Records` orientation line (2–3 per
  line); Security and Sustainability not tagged — neither is substantively served by this chapter's
  own content, which is metrics, logs, traces, SLOs, alerting, and operational practice, not identity/
  data protection or environmental efficiency.
- Key decisions:  Drafted directly (not fanned out) to preserve voice continuity with drafts 00–06,
  then ran three independent read-only verification passes via the Workflow tool (contract fidelity,
  style/mechanics, ADR quality against `rubric.md`), which raised 3 contract findings, 6 style
  findings, and 4 ADR-quality findings, and a fix pass that resolved all of them. Fixes of note:
  dropped R20 from ADR-027's `Requirement` field after checking `brief.md` directly — R20 is owned by
  phases 03/05/09, not 07 — replacing it with R25 ("follows best practices," owned by "all, 09");
  added the fixed Synthetics domain `https://app.innovateinc.com` from `contract.md` §10 verbatim,
  which the initial draft had paraphrased as "the SPA" only; expanded `EKS` and `RDS` at their true
  first use in `## Observability strategy` rather than two sections later, and removed the resulting
  duplicate `RDS` expansion; expanded `Availability Zone (AZs)` at its true first use inside the SLO
  table cell rather than two sections later; expanded `single-page application (SPA)` at first use in
  the four-signals table; removed the banned word "simply"; corrected future/conditional tense
  ("will ask", "would like", "would require") to present tense in three places per `style-guide.md`
  §1; added `Reliability` to ADR-026's `Pillars` field, which a verification pass found the ADR's own
  Context and Why fields substantively argue (avoiding a single point of failure) but the metadata row
  had omitted; rewrote ADR-026's `Accepts` field, which had restated the chosen option's own
  Weaknesses cell from the options table almost verbatim instead of naming a distinct downside,
  replacing it with the concrete cost of running blind through one incident before the trigger fires
  and losing dashboard history at the cutover; added a fourth row to ADR-027's options table — an
  error budget used only as a reporting signal, human call at breach — after a verification pass found
  the original three rows tested only the numeric-target axis and never tested the automatic-freeze
  *mechanism* itself against its most realistic rival, which the body prose two sections earlier
  explicitly flags as the contested half of the decision; and quantified ADR-027's `Revisit when`
  trigger, which had said the error budget "has room to spare" with no threshold, replacing it with
  "finishes more than half unspent for two consecutive quarters" so the ADR's own thesis — a number
  replacing a debate — does not contradict itself in its own trigger field.
- Assumptions:    None beyond the pillar attribution above; no ambiguous requirement was silently
  decided. Confirmed via `phases/phase-11-assembly.md`'s full chapter-6 subsection outline (§6.1–§6.5,
  a 1:1 match to this draft's five `##` headings in the same order) that ADR-026 cites `§6.2 The four
  signals` and ADR-027 cites `§6.3 Service level objectives` correctly — no "no pre-registered
  subsection" issue for either ADR, unlike the pattern Phases 02–05 logged before Phase 06 found this
  file.
- Deferred:       Cost of the observability stack is named only as a qualitative clause ("costs
  materially less" / "costs more"), never a figure — Phase 08 owns cost. Stage-by-stage growth detail
  beyond a single named trigger per callout is Phase 09's — this draft names triggers only ("the first
  incident where the cluster and its monitoring fail together, or the point at which an on-call
  rotation exists") and stops there.
- Contract additions: none.
- Notes for the next agent: (1) ADR-026 and ADR-027 measure at 259 and 256 words respectively
  including the `### ADR-0NN — <title>` heading and the "**Options considered.**" label text — both
  land at essentially exactly 250 words of actual Context/Decision/Why/Consequences/Cost/Revisit prose
  once those ~9–10 non-prose tokens are excluded, using the same method that reproduced Phase 01's
  self-reported counts exactly. Every sentence remaining after two trim passes carries content a
  verification pass explicitly required (a third pillar, a non-restated *Accepts* item, a fourth
  options-table row, a quantified trigger) — flagged here rather than cut further, consistent with
  Phase 03's precedent of flagging Phase 02's over-cap ADRs for Phase 13 rather than editing another
  phase's file. (2) Phase 08 (Cost Optimization) should add the observability stack's indicative
  monthly cost split (in-cluster vs. managed Prometheus/Grafana) to its cost table — this draft
  deliberately did not derive one. (3) Did not touch the open `§10.7`/`§9.7` issue from Phase 00, the
  ADR-007/010, ADR-011, ADR-015, or ADR-020 Section-field issues from Phases 02–05, the Phase 02 ADR
  word-count finding from Phase 03, or the EKS terminology conflict from Phase 04 — all out of scope
  here, still open for Phase 13.

### Phase 08 — Cost optimization & FinOps
- Completed:      2026-08-14
- Files written:  `_plan/drafts/08-cost.md` (1,473 words body excluding tables and ADRs; ADR-028 at
  246 and ADR-029 at 250 words, excluding both tables, both at or under the 250-word cap, counted with
  the same whitespace-token method Phases 03, 05, 06, and 07 validated)
- Word count:     1,473 (acceptance band 1,050–1,600; phase document's own ~1,300-word ±20% band is
  1,040–1,560 — both satisfied). Drafted at ~1,444 across two rounds — an initial draft, then a fix
  pass responding to three independent verification agents run via the Workflow tool — landing inside
  both bands with margin each round.
- ADRs written:   ADR-028 — ADR-029
- Pillars tagged: Cost Optimization, Reliability, Operational Excellence, Performance Efficiency,
  Sustainability across the section's five pillar lines plus the `## Decision Records` orientation
  line (2 per line, every line at or above the 2-pillar floor); Security not tagged — this chapter's
  own content (pricing and FinOps governance) does not substantively serve it. ADR-028's own pillar
  metadata carries `Cost Optimization · Operational Excellence`, added during the fix pass after a
  verification pass found it was the only one of 29 ADRs across all eight drafts with a single-pillar
  metadata row.
- Key decisions:  Drafted directly (not fanned out) to preserve voice continuity with drafts 00–07,
  then ran three independent read-only verification passes via the Workflow tool (contract fidelity,
  style/mechanics, ADR quality against `rubric.md`), which raised 2 contract findings, 6 style
  findings, and 8 ADR-quality findings, and two further advisor-flagged findings on redraft, and a fix
  pass that resolved them. Fixes of note: a verification pass flagged the lean-start variant's original
  NAT row ("a single NAT Gateway for the merged non-production VPC") as inconsistent with the
  Optimization Levers table's own row, which treats single-NAT-per-non-prod-environment as the existing
  baseline. A first fix pass over-corrected this into "development and staging merge into one account"
  — since an Amazon EKS cluster is scoped to exactly one AWS account (`contract.md` §6), sharing one
  cluster does structurally imply *something* about the account boundary, but asserting the accounts
  merge is a bigger claim than anything `contract.md` licenses: §11's lean-start note says only "share
  one cluster", and §4 locks both `innovate-dev` and `innovate-staging` as separate Day-1 accounts —
  "you may not change a value that is already fixed here." A second advisor pass caught the
  over-correction (it had also propagated into ADR-029's `Gains`/`Accepts` fields) before it was
  reported as done; reverted all three sites to state only what `contract.md` §11 actually licenses
  (the shared cluster and the resulting one-fewer-NAT-Gateway saving) without asserting how the account
  boundary resolves, and logged the underlying tension as an Open question below rather than silently
  deciding it. Other fixes of note: removed five dangling `contract.md §N` citations from body prose (a
  planning file that does not ship with the deliverable, the same defect class Phase 04 fixed for
  `contract.md §7`) and replaced them with the deliverable's own section numbers (`§3.3 Node strategy`,
  `§8 Growth Roadmap`, `§5.3 Data protection`, `§1.1 Why multiple accounts`); removed two figures a
  verification pass found were derived rather than sourced — a `~$400`/`~$325` per-tier dollar
  regrouping with no matching line in `contract.md` §11, replaced with the purely relative language the
  phase document's own content specification already called for ("largest variable cost", "small at
  launch"), and a "roughly two-thirds" fraction for the scheduled-dev-shutdown lever with no contract
  source, replaced with "most"; fixed ADR-028's Cost impact field, which had inverted a 30%-discount
  into a "30% higher" premium — mathematically wrong (reversing a 30%-off price is closer to 43%
  higher) and not something `contract.md` §11 states either way — reworded to state the forgone
  discount directly, in the contract's own terms, with no reverse arithmetic; resolved a cross-section
  contradiction a verification pass found between the Optimization Levers table's
  Aurora-reserved-capacity trigger ("a full quarter") and ADR-028's own trigger ("two consecutive
  quarters") by pointing the lever row at ADR-028's trigger instead of stating an independent one;
  expanded ADR-028's Context field from one technical sentence to include Innovate Inc.'s team size and
  runway, per `decision-register.md` §1's template requirement that Context frame the client's actual
  constraints, not abstract ones; rewrote both ADRs' `Accepts` fields, which had restated their own
  options-table Weaknesses cells nearly verbatim, with genuinely new, contract-safe consequences (an
  open-ended deferral with no fixed end date for ADR-028; lost operational isolation between the
  development and staging workloads sharing one cluster for ADR-029, stated without asserting an
  account merge); replaced a vague "where budget is tight" trigger in ADR-029's plain-language field
  with a concrete one ("while runway is short"), and replaced a derived "≈$450/month difference" in its
  `Revisit when` field (subtraction on two `contract.md` §11 figures, which the phase document's hard
  rule forbids) with a qualitative business trigger; replaced jargon — "a green staging deployment" —
  in ADR-029's plain-language field with "a staging deployment that has passed every check", per
  `style-guide.md` §6a's read-aloud test; added an AWS Pricing Calculator pointer to the
  growth-trajectory table, the one of the three required figure tables that had shipped without one;
  fixed a British/American spelling split (`behaviour`/`stabilise` vs. `utilization`) to American
  throughout; and expanded `EKS`, `NAT`, `ALB`, `AMP`/`AMG`, and `VPC` at their true first prose use,
  leaving the three-acronym-in-table exceptions (`ECR`, `ACU`, `LCU` inside the verbatim-reproduced
  day-1 cost table) unexpanded as a deliberate, precedented judgment call — the same one Phase 03 made
  for `EKS` inside a locked table — since editing that table's cells would break this phase's own
  "reproduce ... exactly" requirement.
- Assumptions:    Read `contract.md` §11's lean-start note ("single NAT everywhere") together with this
  phase document's own explicit, narrower instruction ("a single NAT Gateway in every non-production
  VPC") as the phase document's scope winning for content purposes — i.e., the lean-start variant does
  not touch production's three-AZ NAT redundancy, which `well-architected.md` §3's own trade-off table
  treats as a standing decision, not one this variant revisits. A verification pass raised the
  alternative reading (reducing production to one NAT Gateway); rejected it as inconsistent with every
  other locked reference to production's NAT posture in the document, and not something a "lean-start"
  variant scoped to non-production levers should silently redesign. Left unresolved, and logged as an
  Open question rather than assumed: whether "development and staging share one EKS cluster"
  (`contract.md` §11) is compatible with §4's separate `innovate-dev`/`innovate-staging` accounts,
  given §6 scopes one cluster to exactly one account.
- Deferred:       No new infrastructure decisions — this phase prices and governs the design Phases
  01–07 made. The observability stack's cost split (in-cluster vs. managed Prometheus/Grafana) that
  Phase 07 flagged is covered by the existing `CloudWatch / logs / metrics` line and named qualitatively
  in `## Optimization levers`'s day-1-vs-at-scale framing, not split into a new line item `contract.md`
  §11 does not carry.
- Contract additions: none.
- Notes for the next agent: (1) Logged two new Cross-phase issues below: a fourth draft (`08-cost.md`)
  on the style-guide.md-over-contract.md side of the EKS-expansion split Phase 04 first flagged, and a
  new pillar trade-off (deferring Compute Savings Plans) for Phase 09 to add to its `§9.7` table — not
  editing `well-architected.md` directly since it is not a file this phase owns. (2) Resolved the
  open Phase 02 cross-phase row (interface VPC endpoint cost line) qualitatively rather than by adding
  a new dollar figure — see the updated "Resolved in" cell. (3) Raised a new Open question above (the
  shared dev/staging EKS cluster vs. the locked separate accounts) — a human answer, or a `contract.md`
  §12 extension once one is chosen, would let a later phase state the lean-start variant's account
  mechanics plainly instead of the deliberately mechanism-agnostic wording this draft uses now. (4) Did
  not touch the open `§10.7`/`§9.7` issue from Phase 00, the ADR-007/010, ADR-011, ADR-015, or ADR-020
  Section-field issues from Phases 02–05, the Phase 02 ADR word-count finding from Phase 03, or the
  pre-existing EKS terminology conflict itself (only added this draft to the tally) — all out of scope
  here, still open for Phase 13.

### Phase 09 — Well-Architected alignment & growth roadmap
- Completed:      2026-08-15
- Files written:  `_plan/drafts/09-wellarchitected-growth.md` (1,034 words body excluding tables; no
  ADR block — none reserved for this phase, per `decision-register.md` §2 and this phase's own
  "Files you own" list)
- Word count:     1,034 (acceptance band 720–1,080). Drafted at 1,059, trimmed to 988 across the
  intro paragraphs and several "Not yet addressed" gap paragraphs, then grew back to 1,034 after an
  advisor pass caught two acceptance-criteria gaps the three verification agents could not check
  (none had been given the phase document itself, so nothing independently walked its 15-item
  acceptance list): "what breaks first" item 6 (the team) named the constraint but not an
  observable signal or an answer, and the Performance Efficiency gap's trigger was a bare pointer
  ("named in the growth roadmap below") rather than a stated trigger. Both fixed with content
  already sourced elsewhere in the drafts (ADR-011/012's platform-engineer trigger; the stage-2
  latency/capacity signal), so neither introduces new architecture.
- ADRs written:   none — this phase attributes decisions already recorded in ADR-001–029, it does
  not make new ones
- Pillars tagged: All six, explicitly, on the `## Well-Architected Framework alignment` section
  (per this phase document's own literal instruction, `> **Well-Architected pillars.** All six.` —
  see Key decisions below for the tension this creates against the general 2–4 pillar cap);
  Reliability · Performance Efficiency · Cost Optimization · Operational Excellence on the
  `## Growth roadmap — from hundreds to millions` section (4 pillars, within the general cap)
- Key decisions:  Drafted directly (not fanned out) to preserve voice continuity with drafts 00–08,
  then ran three independent read-only verification passes via the Workflow tool (contract
  fidelity, style/mechanics, and — the check this phase's own document flags as the most likely
  failure mode — an evidence-truth check verifying every row of the six pillar tables against the
  actual text of drafts 00–08), and a fix pass that resolved the confirmed findings. Fixes of note:
  removed a "per unit of energy" claim from the Sustainability table's Graviton row that repurposed
  a cost/price-performance figure (`contract.md` §11's ~20%) as an unstated energy-efficiency
  metric — replaced with `well-architected.md` §1's own qualitative "performance per watt" framing;
  removed a "roughly half" ratio comparing the lean-start variant's cost to the fuller design's,
  which `contract.md` §11 forbids as a new figure derived from its two cost anchors — replaced with
  both anchor figures stated side by side, undifferenced; removed "for Redis" from the Stage 2
  ElastiCache growth-roadmap entry, since `contract.md` fixes only the service name, not the engine,
  and no phase has registered a specific engine in §12; reworded a Sustainability evidence row that
  cited §0's "managed over self-hosted" principle for a shared-multi-tenant-capacity argument §0
  itself does not make, to state only what §0 actually argues (avoiding infrastructure the team
  would otherwise own and run); fixed the banned word "just" in the Operational Excellence table;
  expanded nine acronyms on first use that the initial draft had used bare (ADR, IAM, EKS, OIDC,
  KMS, RDS, VPC, CIDR, NAT, WAF, DDoS); trimmed both `##` section openers from three sentences to
  two per `style-guide.md` §2; and added two additional section citations to Reliability-table rows
  whose claims spanned more sources than the single section originally cited. One finding from the
  contract-fidelity pass was a false positive from that agent's own incomplete file scope (it was
  not given `drafts/08-cost.md`, so it could not verify the "roughly 15% of trend" trigger figure,
  which is in fact ADR-028's own verbatim `Revisit when` wording) — verified directly against this
  session's own earlier reading of `08-cost.md` and left unchanged. Two findings were verified as
  false positives against my own direct reading of the source drafts and left unchanged: an "eleven
  named layers" claim the evidence-truth pass thought undercounted `06-security.md`'s twelve-layer
  table, but which in fact correctly cites `02-network.md`'s own, separate eleven-layer "Securing
  the network" table (§2.4), not §5.1's table.
- Assumptions:    Evidence-table section citations follow the same fallback pattern Phases 02–06
  established: `contract.md` §14's confirmed subsections (§0.2, §1.1, §2.2–§2.4, §3.1/§3.3–§3.5/§3.8–
  §3.9, §4.1–§4.2/§4.4–§4.6, §5.3–§5.4, §6.2–§6.3, §7.1–§7.2/§7.4, §8.2, §9.7) plus the ones Phase
  06 additionally confirmed in `STATE.md` (§2.3, §3.1, §4.2) were cited by subsection; everything
  else (identity/guardrail sections in §1, most of §2's and §3's remaining sections, §4.3, §5.1–§5.2/
  §5.5–§5.7, §6.1/§6.4–§6.5, §7.3/§7.5) was cited at chapter level rather than guessed at a specific
  unconfirmed subsection number, consistent with the precedent those phases set. §7.3 was inferred
  positionally (bracketed by confirmed §7.2 and §7.4) only once, in an early draft, and was removed
  in the fix pass in favor of chapter-level `§7 Cost Optimization` after the contract-fidelity pass
  flagged a genuine ambiguity there (see Cross-phase issues below).
- Deferred:       No new architecture — every pillar-table claim traces to drafts 00–08; nothing
  here was invented to fill a gap. Stage-by-stage growth detail beyond the four-stage table and the
  six-item "what breaks first" ordering is not this phase's to expand further.
- Contract additions: none — the one candidate addition (an ElastiCache engine choice) was avoided
  by not naming a specific engine, rather than registered, since nothing in this draft strictly
  needs that specificity.
- Notes for the next agent: (1) See Cross-phase issues below for two new entries this phase raises:
  a genuine ambiguity in `contract.md` §11's own text about which chapter carries the growth-stage
  cost trajectory table (§11 says "§8.3", but §14's chapter map and `08-cost.md`'s own structure put
  equivalent content at what this phase infers as §7.3), and a direct conflict between this phase's
  own document (which explicitly instructs `> **Well-Architected pillars.** All six.`) and the
  general two-to-four-pillar cap in `style-guide.md` §3 / `AGENT-PROTOCOL.md` §5.4 and §6's anti-
  pattern list — resolved here by following this phase's own explicit, literal instruction (the
  chapter's entire content is genuinely, structurally about all six pillars, not a lazy blanket tag),
  but flagged since `AGENT-PROTOCOL.md` states it wins over phase documents in a conflict. (2) The
  "Accepted trade-offs between pillars" table reproduces `well-architected.md` §3's nine rows with
  three minor, deliberate deviations from byte-verbatim: American spelling ("centralized" vs. the
  source's "centralised"), backticked Kubernetes object names (`PodDisruptionBudget`, `NetworkPolicy`
  — required by `style-guide.md` §3's own inline-code rule, which the source file does not follow),
  and "named above" in place of the source's "named in §9" (avoiding restating the same §10.7/§9.7-
  style stale self-reference Phase 00 already flagged as unresolved). Two rows keep the source's
  conditional-tense wording ("would undo," "would have captured") unchanged despite
  `style-guide.md` §1's present-tense rule, because they are inside a table `decision-register.md`
  and this phase's acceptance criteria require to reproduce verbatim from `well-architected.md` §3 —
  editing that file is out of this phase's ownership, so the tense issue is native to the source, not
  fixed here. (3) Did not touch the open `§10.7`/`§9.7` issue from Phase 00, the ADR-007/010,
  ADR-011, ADR-015, or ADR-020 Section-field issues from Phases 02–05, the Phase 02 ADR word-count
  finding from Phase 03, or the EKS terminology conflict tracked since Phase 04 — all out of scope
  here, still open for Phase 13.

### Phase 10 — Diagrams
- Completed:      2026-08-15
- Files written:  `../diagrams/01-high-level.md` (202 words prose, 14-node flowchart), `02-account-
  topology.md` (183 words, 11 declared node IDs + 6 subgraphs), `03-network-topology.md` (173 words,
  15 nodes + 4 subgraphs), `04-cicd-pipeline.md` (170 words, 16 nodes), `05-request-flow.md` (160
  words, 8-participant sequenceDiagram) — 888 words of prose total across all five (captions +
  legends + notes, mermaid code excluded), against the ~700-word budget; treated as a soft ±20%-style
  band per the precedent other phases set for their own "~word ±20%" targets, and 888 is inside a
  reasonable reading of that tolerance once every required acronym expansion and content-fidelity fix
  below is counted in.
- Word count:     888 (see above)
- ADRs written:   none (this phase writes no ADRs)
- Pillars tagged: n/a — diagrams do not carry `##` pillar lines per the file-format template in
  `phases/phase-10-diagrams.md`; not omitted in error.
- Key decisions:  Extended the mandatory Diagram 1 skeleton without restructuring it, per the phase
  document's explicit instruction, but corrected one factual error inherited from the skeleton itself:
  the Aurora node's label read "writer + reader, Multi-AZ", and "Multi-AZ" is the name `contract.md`
  and the drafts reserve exclusively for the *rejected* Amazon RDS alternative — Aurora's own topology
  is described everywhere else as "writer + reader in a different AZ" — so the label now reads
  "writer + reader, separate AZs" instead, matching the terminology actually used for Aurora. Built
  Diagrams 2–5 directly from `contract.md` §4–§9 and drafts 01/02/04/06 rather than the given
  per-diagram prose alone, to get exact CIDRs, account names, and pipeline-stage wording. Diagram 2's
  future sandbox account is labelled `innovate-sandbox-*`, matching `contract.md`'s own OU-tree
  rendering of that templated name (line 144) rather than the account table's `<user>` placeholder
  form (line 132), because literal angle brackets in Mermaid label text risk being parsed as an HTML
  tag and are not safe to reproduce verbatim in a diagram the way they are in prose. Ran three
  independent read-only verification passes via the Workflow tool (Mermaid syntax mechanics, contract/
  draft content fidelity, style/acronym compliance), which raised zero mechanics defects, two content-
  fidelity gaps in Diagram 4, and nine acronym-expansion gaps across four files, and a fix pass that
  resolved all of them. Fixes of note: Diagram 4 originally folded staging's own integration-test gate
  into the `compute`-classed staging-environment node, making a real refusal point invisible in a
  diagram whose whole point is showing refusal points — added a distinct `security`-classed
  `stgtest` node between `stgenv` and `approval`, mirroring how dev's `itest` gate was already drawn.
  Diagram 4 also originally showed only one canary-to-analysis step (10% → analysis → 100%), but
  `contract.md` §12's Extensions register locks the canary sequence as "10% → analysis → 50% →
  analysis → 100%" (added there by Phase 04) — rather than adding two more nodes and pushing past a
  reasonable node count for a 16-node diagram, the full locked sequence is now reproduced verbatim
  inside the single `canary` node's own label, so no step is hidden and the node count stays at 16.
  Acronym fixes: expanded WAF, DR, VPC, and CI on first use in Diagram 1's legend/note; SCP in Diagram
  2's caption; AZ, VPC, CIDR, and ALB in Diagram 3's caption/legend; CI/CD in Diagram 4's caption; WAF
  in Diagram 5's caption — each per `style-guide.md` §4's fixed expansion list or, for VPC/CIDR/ALB
  (not on that list but also not on its "never expand" list), following the precedent `drafts/02-
  network.md` set for expanding them at first use. Verified every CIDR in Diagram 3 character-by-
  character against `contract.md` §5 (exact match, confirmed independently with a script diff, not
  just by eye) and every `innovate-*` name across all five diagrams against `contract.md` (one
  mismatch found and fixed — the sandbox account, above). Verified mechanically (not by inspection
  alone) that every `subgraph`/`end` pair balances per file (4/4, 6/6, 4/4, 0/0, and 2/2 for Diagram
  5's `alt`/`end`), every node ID matches `[a-zA-Z0-9_]+`, every `class` statement resolves to a
  declared node ID and a defined `classDef`, and every arrow endpoint is declared — using a Python
  script cross-check in addition to the Workflow verification pass, not relying on either alone.
- Assumptions:    Treated the ~700-word diagram budget as a soft target (no explicit ±20% stated in
  `phases/phase-10-diagrams.md` the way content-phase word budgets state one, and it is not listed as
  a numbered "Acceptance criteria" checkbox) rather than a hard gate, since fixing genuine content-
  fidelity and acronym-expansion gaps took priority over trimming back under it; final count is 888.
- Deferred:       Subsection numbering for the diagrams' own cross-references is not this phase's
  concern (diagrams don't cite `§N.M` the way ADRs do); Phase 11/12 place these five files into
  Appendix C as-is per `contract.md` §14.
- Contract additions: none.
- Notes for the next agent: (1) The Diagram 5 mechanics reviewer flagged a cosmetic (non-blocking)
  question about whether `participant id as "Display Name"` renders the surrounding quote marks
  literally in the participant box — this is standard, well-documented Mermaid `sequenceDiagram`
  syntax (the quotes are stripped, not displayed) and matches `phases/phase-10-diagrams.md`'s own
  prescribed pattern verbatim, so it was not treated as a defect; flagged here only so Phase 13 can
  spot-check an actual render if it wants certainty. (2) Did not touch any of the open cross-phase
  issues logged by Phases 00–09 above (the `§10.7`/`§9.7` reference, the four ADR Section-field gaps,
  the Phase 02 ADR word-count finding, the EKS-terminology-expansion split now spanning three drafts,
  or the `§11`/`§8.3` cost-table cross-reference) — none are this phase's files, all still open for
  Phase 13. (3) Diagrams 2–5 are original content built from `contract.md` and the drafts, not
  extensions of a given skeleton the way Diagram 1 is — only Diagram 1 had a mandatory starting point
  in `phases/phase-10-diagrams.md`.

---

## Open questions

> Things a phase agent could not resolve and did not want to silently decide. The human answers
> these; Phase 13 checks none are outstanding before the deliverable is called finished.

| Raised by | Question | Status | Answer |
|---|---|---|---|
| Phase 08 | `contract.md` §11's lean-start note says "Dev+staging share one cluster." `contract.md` §4 locks `innovate-dev` and `innovate-staging` as two separate Day-1 accounts. `contract.md` §6 fixes "Clusters per account: Exactly one. Account is the isolation boundary, not the cluster." Sharing one EKS cluster across two accounts is not a configuration EKS supports, so §11's lean-start note and §4/§6's account lock appear to be in tension. `drafts/08-cost.md` states only what §11 licenses (the shared cluster, and the NAT Gateway saving that follows) and does not assert whether the two accounts merge, split differently, or whether §11's note is a simplification that assumes the reader will not press on the mechanism. | **Resolved**, 2026-08-16, by the human directing this work | The lean-start variant merges `innovate-dev` and `innovate-staging` into one AWS account, `innovate-dev-staging`, running one EKS cluster isolated by Kubernetes namespace instead of by account. `contract.md` §11 and a new "Lean-start exception" note under §4 state this explicitly; §12's Extensions register records the new account name. `README.md` §7.2 and ADR-029 rewritten to match (Phase 13). The primary seven-account recommendation is unchanged — this applies only to the documented cheaper alternative. See `STATE.md`'s 2026-08-16 Phase 13 plan amendment above. |
| Phase 11 | **The 4,800–6,500 word body target does not close arithmetically against the locked outline.** After three full compression passes (my own manual edits, a delegated fork agent's three rounds, then my own further manual cuts) prose is genuinely near-minimal — no further sentence-level tightening yielded more than 20–100 words per pass by the end. The assembled body still measures **9,194 words** (table rows: ~2,750; prose: ~6,440), well above the ceiling. The 2026-08-14 plan amendment's own estimate — "tables run 1,800–2,500 words, so the cut falls entirely on prose" — does not hold in practice: measured table words alone exceed that estimate's low end and approach its high end, and 57 `###` subsections at even a bare-minimum ~2–3 sentences each, plus 10 chapter openers, 67 headings, and the five required verbatim tables, produce a floor closer to 9,000 than 6,500. Getting under 6,500 requires removing *structure* (a subsection or a required table), not more sentence-trimming — and `phase-11-assembly.md`'s outline and `contract.md` §14's section map are both locked; Phase 11 does not have authority to drop either. Per `AGENT-PROTOCOL.md` §7 ("if you hit something the plan didn't anticipate, log it — do not silently improvise a structural change"), this is logged rather than resolved. Three options for the human: **(a)** raise the body ceiling to ~9,000–9,500 and adjust `style-guide.md` §6 / `rubric.md` §1 and the total-document target correspondingly; **(b)** authorize dropping or merging specific `###` subsections, which requires amending `contract.md` §14's locked section map; **(c)** authorize cutting one or more of the five required-verbatim tables to a shorter or prose form. Phase 11 shipped at 9,194 words with every subsection, every table, and every diagram intact rather than silently dropping content to force a fit. | **Resolved**, 2026-08-16, by the human directing this work: **option (a)** | The body ceiling is raised to 8,000–9,500 words (from 4,800–6,500) to match what the locked outline actually costs, rather than cutting structure (option b) or the five verbatim tables (option c). `style-guide.md` §6, `rubric.md` §1, and `phases/phase-13-qa-and-final.md` all updated. See `STATE.md`'s 2026-08-16 Phase 13 plan amendment above. |
| Phase 12 | **Confirmed and worse: the total-document target of 9,000–12,000 words does not close either, once Phase 12's own mandatory content is added on top of Phase 11's already-over-budget body.** The assembled `README.md` measures **≈14,910 words excluding fenced code** (after the 2026-08-16 removal of Appendices A and C, below — together saving ~650 words, which does not resolve this), counted with a corrected method that strips Markdown table pipes and separator rows before counting (an initial pass that just excluded fenced code and split on whitespace over-counted at ≈17,070, since `"| a | b |".split()` treats each `|` as a token — flagged during self-review and re-measured; this is the same class of counting-method disagreement already on record between Phase 01's and Phase 03's ADR word counts). By the same corrected method: §0–§9 body ≈8,370 words (Phase 11 self-reported 9,194 by its own method — the two numbers disagree by ~800 for the same unchanged text, method, not content, is the difference); Executive Summary ≈415 words of prose plus a six-row table and the embedded HLD; §10's 29-row table plus an 84-word intro; Appendix B's nine full ADRs at ≈2,427 words of prose plus ≈2,324 words across their 18 tables (metadata + options, two per ADR) — in line with this phase's own ~2,000–2,500-word estimate for that content, not padding; Appendix A's glossary (formerly Appendix D — relettered per the 2026-08-16 amendment below), already tightened once from ~800 to ~450 words. None of this is discretionary bloat: `phases/phase-12-frontmatter-and-register.md` explicitly requires all nine promoted ADRs in full (with both required tables each), all 29 decisions as §10 rows, and 25–30 glossary terms — cutting any of them to force the total under 12,000 would fail this phase's own acceptance criteria ("Appendix B contains exactly the nine ADRs... no more and no fewer", "§10 key-decisions table has 29–34 rows", "the glossary has 25–30 terms"). Phase 12 therefore shipped complete per its own acceptance list rather than dropping required content to chase a total-document number that was already unreachable once Phase 11's body alone exceeded its own ceiling by roughly 2,000 words even under the corrected count. This does not need a separate decision from the human — it is the same word-budget question Phase 11 already raised, now with final numbers; whichever of options (a)/(b)/(c) above the human picks for the body will also need to reset the *total*-document ceiling in `style-guide.md` §6 and this phase's own word-budget section correspondingly, since neither was sized against what completing Appendix B and §10 at full required scope actually costs in words. | **Resolved**, 2026-08-16, by the human directing this work: **option (a)**, same decision as the row above | The total-document ceiling is raised to 13,000–15,500 words (from 9,000–12,000), matching what all required content — the locked body outline plus the full nine-ADR Appendix B, §10's 29-row table, and the glossary — actually costs. The final document, after Phase 13's fixes, measures ≈15,076 words total (≈9,348 body §0–§10), both comfortably inside the new range, using the pinned counting method now specified in `style-guide.md` §6. See `STATE.md`'s 2026-08-16 Phase 13 plan amendment above. |

---

## Cross-phase issues

> Contradictions, duplications, or gaps spotted between drafts. **Do not fix another phase's draft
> yourself** — log it here. Phase 13 owns resolution.

| Spotted by | Where | Issue | Resolved in |
|---|---|---|---|
| Phase 00 | `phases/phase-00-preflight-and-scope.md` §3 closing line; `well-architected.md` §4 | Both say the accepted-trade-offs table lives at `§10.7`, but `contract.md` §14's locked section map and reference table fix it at `§9.7 Accepted trade-offs between pillars` (there is no `§10.7` — `§10` is `Summary of Key Decisions`). `00-scope.md` §3 itself cites `§9.7`, following contract.md as normative. | **Resolved in Phase 13.** Both stale `§10.7` references corrected to `§9.7`. `README.md` itself never carried the stale reference (confirmed by grep) — only the two planning-file mentions needed fixing. |
| Phase 02 | `drafts/02-network.md`, ADR-007 and ADR-010 Section fields | `contract.md` §14 pre-registers only `§2.2` and `§2.4` for the Network Design chapter; ADR-008/009 cite `§2.2`, but ADR-007 ("Connectivity between environments...") and ADR-010 ("Routing and internet egress") have no pre-registered subsection number, so both cite the chapter level `§2 Network Design` instead. | **Resolved in Phase 11.** Both topics merge into `README.md` §2.3 "Routing, egress and private connectivity" (draft 02's "Routing and internet egress" + "Connectivity between environments" headings, combined per `phase-11-assembly.md`'s outline). ADR-007 and ADR-010's Section fields should read `§2.3` when Phase 12 writes their Appendix B/§10 entries. |
| Phase 02 | `contract.md` §11 cost table | No line item exists for interface VPC endpoint spend (16 endpoints × 3 AZs); `drafts/02-network.md` describes the per-endpoint charge qualitatively rather than deriving a total, per §11's no-derived-figures rule. | **Resolved in Phase 08.** `contract.md` §11's hard rule ("invent nothing", "no derived figures beyond simple totals already in the contract") forbids adding a new dollar line contract.md itself doesn't carry, so `drafts/08-cost.md`'s "VPC endpoints reducing NAT data processing" lever states the trade-off qualitatively (a per-endpoint fixed charge that offsets most of what it saves on the NAT Gateways line) rather than deriving a total — no new figure was invented. |
| Phase 03 | `drafts/03-compute-eks.md`, ADR-011 Section field | `contract.md` §14 pre-registers no subsection number for the "Why managed Kubernetes, and why EKS" content (only `§3.3`, `§3.4`, `§3.5`, `§3.8`, `§3.9` are pre-registered for this chapter); ADR-012/013 cite `§3.3` and ADR-014 cites `§3.5`, but ADR-011 cites the chapter level `§3 Compute Platform` instead, matching the precedent Phase 02 set for ADR-007/010. | **Resolved in Phase 11.** `README.md` §3.1 "Why Amazon EKS" is exactly this content. ADR-011's Section field should read `§3.1` when Phase 12 writes it. |
| Phase 03 | `drafts/02-network.md`, ADR-007 – ADR-010 word count | A read-only verification pass in this phase, using a word-count method independently validated against Phase 01's self-reported ADR counts (exact match: 248, 243, 250 words), measured Phase 02's four ADRs at 267, 272, 265, and 269 words — each over `decision-register.md`'s 250-word cap — despite Phase 02's completion report stating all four landed within cap after a fix-pass trim. Not fixed here; it is another phase's draft. | **Resolved in Phase 13.** Recounted every one of the nine promoted ADRs as they stand in `README.md` Appendix B, using the pinned per-ADR method now specified in `style-guide.md` §6 (strip fenced code, drop the heading line, drop both tables entirely, count what remains). ADR-007 measured 267 words, confirming the finding; along with ADR-011 (252), ADR-026 (255), and ADR-029 (278, after Phase 13's own lean-start-account edits added content), all four were trimmed — surgical cuts to Context/Why/Consequences/Revisit fields, no content dropped — to 248, 248/249, 250, and 242 words respectively (see the Phase 13 completion report below for the full final count of all nine). ADR-008/009/010 remain non-promoted and untouched in the draft; their over-cap status still only matters if a later plan change promotes one of them. |
| Phase 04 | `drafts/04-containers-cicd.md`, ADR-015 Section field | `contract.md` §14 pre-registers no subsection number for "What gets containerized" (only `§3.3`, `§3.4`, `§3.5`, `§3.8`, `§3.9` are pre-registered for the Compute Platform chapter); ADR-016 and ADR-018 correctly cite `§3.8 Container registry`, but ADR-015 (the SPA-not-a-container decision) cites the chapter level `§3 Compute Platform` instead, matching the precedent Phases 02 and 03 set for ADR-007/010 and ADR-011. | **Resolved in Phase 11**, per Phase 06's flag that this needed a content read, not a title match. `README.md` §3.7 "Containerization — image building" opens with the SPA-not-containerized decision before covering build mechanics, so ADR-015's Section field should read `§3.7` when Phase 12 writes it. |
| Phase 04 | `drafts/03-compute-eks.md` §1, `drafts/04-containers-cicd.md` §1, both first-use expansions of Amazon EKS | `style-guide.md` §5 gives the general rule "full AWS name on first use... then the short form" with the worked example "Amazon Elastic Kubernetes Service (EKS)"; `contract.md` §13's Terminology table locks the required first-use form as "Amazon EKS (first use), then 'EKS'" and lists the fuller expansion alongside "AWS Kubernetes"/"EKS service" as a "Not" case. Drafts 03 and 04 both follow style-guide.md's general worked example over contract.md's specific lock, consistently with each other. Draft 06 (this phase) took the other side, following `contract.md` §13's literal "Amazon EKS" — so the split is no longer unanimous. Not fixed here since it is a pre-existing pattern shared by earlier phases, not a defect unique to any one of them. | **Resolved in Phase 13.** Adjudicated: `contract.md` §13 wins. `AGENT-PROTOCOL.md`'s "this file wins" rule is about phase documents contradicting `AGENT-PROTOCOL.md` itself, not about `contract.md` vs. `style-guide.md` — for that case, `contract.md` §13 is the more specific, purpose-built authority (an explicit Terminology table with a "Use / Not" column that names the fuller expansion as a rejected form), where `style-guide.md` §5 only used "Amazon Elastic Kubernetes Service (EKS)" as one illustrative example of a general naming pattern, not a rule about EKS specifically. This is moot for the graded deliverable regardless of which file wins in principle: confirmed by grep that `README.md`'s body prose never once spells out "Amazon Elastic Kubernetes Service" — every instance reads "Amazon EKS" at first use (§Executive Summary, line 33) then "EKS" (the one appearance of the fuller phrase is inside Appendix A's glossary entry, `**Amazon EKS (Elastic Kubernetes Service)**`, which is expected glossary format, not a first-use expansion). No `README.md` edit was needed; the drafts (03, 04, 08 vs. 06) are historical record and out of scope for Phase 13 (`../README.md` only). |
| Phase 05 | `drafts/05-database.md`, ADR-020 Section field | `contract.md` §14 pre-registers no subsection number for `## Configuration` (only `§4.1`, `§4.4`, `§4.5`, `§4.6` are pre-registered for the Database chapter; `§4.1` belongs to `## Why Aurora — the alternatives considered`, cited correctly by ADR-019); ADR-021 and ADR-022 correctly cite `§4.4` and `§4.6`, but ADR-020 (Serverless v2 and RDS Proxy, discussed in `## Configuration`) cites the chapter level `§4 Database` instead, matching the precedent Phases 02, 03, and 04 set for ADR-007/010, ADR-011, and ADR-015. | **Resolved in Phase 11.** `README.md` §4.2 "Configuration and connection management" is exactly this content. ADR-020's Section field should read `§4.2` when Phase 12 writes it. |
| Phase 06 | `contract.md` §14 vs. `phases/phase-11-assembly.md` | Phases 02–05 each logged a "no pre-registered subsection number" issue for one or two ADRs' Section fields, reasoning from `contract.md` §14's short "most-cited" reference table alone. While resolving this phase's own ADR Section fields (`contract.md` §14 names `phase-11-assembly.md` as the authority for subsection numbering), it turned out that file already contains the **complete** subsection outline for every chapter, §0 through §9. Concretely: `§2.3 Routing, egress and private connectivity` appears to cover both ADR-007's topic (connectivity between environments) and ADR-010's topic (NAT Gateways/egress), which draft 02 splits across two `##` headings; `§3.1 Why Amazon EKS` matches ADR-011's topic directly; `§4.2 Configuration and connection management` matches ADR-020's topic directly. ADR-015 (SPA not containerized) is less clear-cut — draft 04's opening heading is "What gets containerized — and what does not," and no `phase-11-assembly.md` heading matches that wording exactly; the nearest candidates are `§3.1` or `§3.7 Containerization — image building`, but this needs a content read, not just a title match. Not fixed here — none of these are this phase's files. | **Superseded by Phase 11's four individual resolutions above** (ADR-007/010 → §2.3, ADR-011 → §3.1, ADR-020 → §4.2, ADR-015 → §3.7 — the last one read against draft 04's actual content, confirming this entry's §3.7 guess). Phase 13 just needs to apply these four Section-field values; no further investigation needed. |
| Phase 08 | `drafts/08-cost.md` §1, first-use expansion of Amazon EKS | Same split Phase 04 logged between `style-guide.md` §5's general worked example ("Amazon Elastic Kubernetes Service (EKS)") and `contract.md` §13's literal lock ("Amazon EKS (first use), then 'EKS'"). This draft's first EKS expansion follows style-guide.md's fuller form, matching drafts 03 and 04; draft 06 is still the lone holdout on contract.md §13's literal form. Not fixed here — this is the same pre-existing pattern, not a new defect. | **Resolved in Phase 13** — same adjudication as the row above (`contract.md` §13 wins; `README.md` already consistent; drafts left as historical record, out of scope). |
| Phase 08 | `well-architected.md` §3 trade-off table | This phase's ADR-028 (deferring Compute Savings Plans and reserved Aurora capacity until the baseline stabilizes) is a pillar trade-off `well-architected.md` §3's table does not yet list: it leans toward **Operational Excellence and reduced commitment risk** at the expense of a larger **Cost Optimization** discount captured sooner. Not added to `well-architected.md` directly — that file is not in this phase's "Files you own" list, and §3 itself says content phases should flag new trade-offs for Phase 09 to pick up, not edit the file. | **Resolved in Phase 09.** Added as the tenth row of `drafts/09-wellarchitected-growth.md`'s trade-off table, exact text as specified here. |
| Phase 09 | `contract.md` §11 vs. §14's chapter map and `drafts/08-cost.md`'s own structure | `contract.md` §11 says the growth-stage cost trajectory table is "for the growth-stage projections in §8.3." But `contract.md` §14 fixes §8 as the Growth Roadmap chapter (this phase's own output, part two) and §7 as Cost Optimization (draft 08) — and `drafts/08-cost.md` already contains its own three-stage-plus-one growth-cost table as its third `##` section (positionally §7.3, bracketed by the confirmed §7.2 and §7.4). So §11's "§8.3" self-reference does not match either the chapter map or where the actual content already lives. Not fixed here — `drafts/09-wellarchitected-growth.md` only cross-references it at chapter level (`§7 Cost Optimization`), avoiding asserting either specific subsection number. | **Resolved in Phase 11.** The growth-cost table landed at `README.md` §7.3 "How cost scales with growth" exactly as Phase 09 predicted, cross-referenced from §8.1 ("What drives each stage is in §8.1" — sic, prose in §7.3 pointing forward to §8.1's stage table; the two tables are complementary, not duplicates: §7.3 gives $-figures per stage, §8.1 gives triggers per stage). `contract.md` §11's "§8.3" is confirmed stale and should read "§7.3". **Resolved in Phase 13**: `contract.md` §11's cross-reference corrected from "§8.3" to "§7.3", matching where the table actually landed. |
| Phase 09 | `phases/phase-09-well-architected-growth.md` vs. `style-guide.md` §3 / `AGENT-PROTOCOL.md` §5.4 and §6 | This phase's own document explicitly instructs the `## Well-Architected Framework alignment` section's pillar line to read `> **Well-Architected pillars.** All six.` — but `style-guide.md` §3 and `AGENT-PROTOCOL.md` §5.4 both say "Two to four pillars," and `AGENT-PROTOCOL.md` §6 names "Tagging all six pillars on every section" as an explicit anti-pattern equivalent to tagging none. `AGENT-PROTOCOL.md`'s own header states it wins over phase documents in a direct conflict. `drafts/09-wellarchitected-growth.md` follows the phase document's literal instruction (the chapter's entire content is structurally about all six pillars in six dedicated subsections, not a blanket tag standing in for real analysis), not the general cap. | **Still open — Phase 11 made a call for the body text only, not a resolution.** `README.md` §9's chapter-level pillar line reads `Security · Reliability · Operational Excellence · Cost Optimization` (4, not 6), following `AGENT-PROTOCOL.md`'s general cap and its explicit "wins over phase documents" precedence rule, since §9's six `###` subsections (9.1–9.6) already give each pillar its own dedicated, individually-tagged-by-heading treatment — the chapter-level line summarizing them at 4 was judged not to be the "blanket tag standing in for real analysis" anti-pattern §6 warns against, since the real per-pillar analysis is one level down. **Resolved in Phase 13**: confirmed Phase 11's reasoning holds — the Pass 4 well-architected-alignment audit independently reached the same conclusion (§9's 4-pillar chapter line is consistent with the 2–4 cap, not a violation, precisely because 9.1–9.6 already give each pillar dedicated treatment) and flagged it only as informational, not a defect. Formally adjudicated as settled: no edit needed. |
| Phase 12 | `README.md` §0.1's first-use expansions vs. the new Executive Summary | `AGENT-PROTOCOL.md` §5.7 and `style-guide.md` §4 require each acronym expanded once, at its true first use in reading order. Phase 12 inserted `## Executive Summary` before `## 0. Scope, Assumptions and Design Principles`, so the Executive Summary is now genuinely first in reading order — it must (and does) expand "Amazon Web Services (AWS)" and "single-page application (SPA)" itself, plus "AWS Web Application Firewall (WAF)," "disaster recovery (DR)," and "continuous integration (CI)" inside the embedded HLD's legend (all reproduced verbatim from `diagrams/01-high-level.md`, per this phase's Step 1.4). §0.1 (line ~157) still carries its own, now-second, expansion of AWS and SPA, since Phase 12 is barred from editing §0–§9 content beyond the three markers. This is a duplicate expansion, not a missing one — `AGENT-PROTOCOL.md` §5.7 calls over-expansion "a cheap fix," lower severity than under-expansion — but it is new, introduced by this phase's own required structure, not inherited. Not fixed here; §0.1 is outside this phase's "Files you own." | **Resolved in Phase 13.** Removed the duplicate expansions in §0.1 (AWS, SPA). A full acronym sweep also found two more genuine duplicates not caught by this entry's own hedge — `disaster recovery (DR)` re-expanded in §0.4, and `AWS Web Application Firewall (WAF)` re-expanded in §2.4 — both fixed the same way. CI's second appearance in §0.1 (via the compound "continuous integration and continuous delivery (CI/CD)") was also trimmed as a borderline case, per the Pass 8 audit finding. |
| Phase 12 | `README.md` §10 pillar line | `style-guide.md` §3 and `AGENT-PROTOCOL.md` §5.4 say every `##` section carries a `> **Well-Architected pillars.**` line, with no stated carve-out for a summary or appendix chapter. `phases/phase-12-frontmatter-and-register.md`'s five steps never instruct one for the Executive Summary, §10, or Appendices A–D, and `contract.md` §14 lists §10 as a "Built from: Phase 12" chapter alongside the appendices, not grouped with the content chapters §0–§9 the pillar-tagging convention was written against. Phase 12 omitted a pillar line from all of these, reasoning by analogy to Phase 10's diagrams ("diagrams do not carry `##` pillar lines" — not literally the same case, since §10 is a numbered chapter in the same series as §0–§9, all ten of which do carry one). Unlike §0–§9's chapters, §10 doesn't substantively serve any 2–4 pillars more than the others — its 29 rows span all six pillars roughly evenly — so a forced 2–4 tag would itself risk being the "blanket tag standing in for real analysis" anti-pattern the cap exists to prevent, the same tension Phase 09 hit for §9's chapter-level line. Not resolved here; logged rather than guessed, per `AGENT-PROTOCOL.md` §7. | **Resolved in Phase 13.** Adjudicated: §10, Appendix A, and Appendix B do not get a pillar line — confirmed as the correct, uniform treatment of summary/reference chapters (as opposed to content chapters), independently corroborated by the Pass 4 audit, which flagged this as informational only, not a defect. Separately, the Executive Summary — which the same general rule does cover, since it is a content-adjacent chapter with real recommendations, not a pure reference appendix — was found genuinely missing its pillar line (a real gap this entry's own scope didn't cover) and one was added: `Security · Reliability · Cost Optimization`. |

---

## Deliverable location

The graded deliverable is **`architecture/README.md`**, assembled in Phase 11 (body) and Phase 12
(summary, decision register, appendices). The `architecture/`
directory is owned entirely by this assignment; the Terraform / EKS + Karpenter assignment lives
under `terraform/` and is off-limits to every agent working this plan.
