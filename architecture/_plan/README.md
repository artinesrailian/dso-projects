# Innovate Inc. Architecture — Delivery Plan

**You are an agent and someone just told you to "do the task" or "continue with the next task".
This file is where you start. Read it completely, then go to §3.**

This directory is the **plan**. It is not the deliverable and it is not graded. The deliverable is
`architecture/README.md`, assembled in Phases 11 and 12 from the drafts that Phases 00–10 produce.

---

## 1. What is being built

An architecture design document for **Innovate Inc.**, a small startup deploying a Python/Flask REST
API and a React single-page application backed by PostgreSQL, on **AWS**. The client brief is
[`../docs/assessment.md`](../docs/assessment.md); the requirements register is [`brief.md`](brief.md).

The document must answer four assessment areas — cloud environment structure, network design,
compute platform, database — and must do so as a **senior architect's design**: every decision
justified with its alternatives and consequences, aligned to the **AWS Well-Architected Framework**,
structured as a **three-tier architecture**, and built with a **DevSecOps** posture where security
and cost are properties of each decision rather than chapters bolted on at the end.

Target output:

```
architecture/
├── README.md                       ← THE DELIVERABLE (Phases 11–12)
├── CLAUDE.md                       ← entry point for a fresh agent
├── docs/assessment.md              ← the client brief as supplied
├── diagrams/
│   ├── 01-high-level.md            ← the required HLD, organised by tier
│   ├── 02-account-topology.md
│   ├── 03-network-topology.md
│   ├── 04-cicd-pipeline.md
│   └── 05-request-flow.md
└── _plan/                          ← this plan (not graded)
```

---

## 2. Rules that override everything else

1. **Stay inside `architecture/`.** Never read or write `terraform/` (a different assignment, being
   worked on concurrently), `.claude/`, or anything above `architecture/`. Full boundary in
   [`AGENT-PROTOCOL.md`](AGENT-PROTOCOL.md) §1.
2. **One phase per session.** Finish your phase, update `STATE.md`, report, stop.
3. **`contract.md` is law** for *what* is built. [`decision-register.md`](decision-register.md) and
   [`well-architected.md`](well-architected.md) are law for *how it is argued*.
4. **Justify everything.** Inline prose plus a numbered Architecture Decision Record from your
   reserved block, including the mandatory plain-language field written for a non-engineer.
5. **This is a writing task.** No `aws`/`kubectl`/`terraform`/`docker` commands, no web browsing, no
   infrastructure code as a deliverable.

---

## 3. How to run a phase (the whole workflow)

```
Step 1  Read _plan/STATE.md → find the first phase not marked "done".
Step 2  Check its dependencies are all "done". If not, stop and say which one blocks.
Step 3  Mark it "in-progress" in STATE.md and save.
Step 4  Read, in order:
          AGENT-PROTOCOL.md      (rules)
          brief.md               (requirements)
          contract.md            (normative names/numbers/tiers)
          decision-register.md   (ADR format + YOUR reserved numbers)
          well-architected.md    (pillar tagging)
          style-guide.md         (how to write)
          phases/phase-NN-*.md   (your job)
        …then the Inputs your phase document lists. Nothing else.
Step 5  Write only the files under "Files you own".
Step 6  Walk your phase's Acceptance criteria line by line and fix failures.
Step 7  Mark it "done" in STATE.md, fill the completion report, record ADR numbers used.
Step 8  Report to the human in the format in AGENT-PROTOCOL.md §8. Stop.
```

**The human's cue phrases:**

| They type | You do |
|---|---|
| "do the task" / "start the task" | The first phase in `STATE.md` not marked `done` |
| "continue with the next task" | The same — the first phase not marked `done` |
| "redo phase N" | Set phase N back to `todo` in `STATE.md`, then run it |

---

## 4. Phases

Content phases (01–09) each write a **draft section** to `_plan/drafts/`, ending with a
`## Decision Records` section containing that phase's ADRs.

| # | Phase | Produces | Depends on | Words | ADRs |
|---|---|---|---|---|---|
| 00 | [Pre-flight, scope & three-tier framing](phases/phase-00-preflight-and-scope.md) | `drafts/00-scope.md` | — | ~900 | 001–003 |
| 01 | [Cloud environment structure](phases/phase-01-cloud-environment.md) | `drafts/01-cloud-environment.md` | 00 | ~1 300 | 004–006 |
| 02 | [Network design](phases/phase-02-network.md) | `drafts/02-network.md` | 00 | ~1 600 | 007–010 |
| 03 | [Compute platform — EKS](phases/phase-03-compute-eks.md) | `drafts/03-compute-eks.md` | 00 | ~1 800 | 011–014 |
| 04 | [Containerization & CI/CD](phases/phase-04-containers-cicd.md) | `drafts/04-containers-cicd.md` | 00 | ~1 500 | 015–018 |
| 05 | [Database](phases/phase-05-database.md) | `drafts/05-database.md` | 00 | ~1 600 | 019–022 |
| 06 | [Security & data protection](phases/phase-06-security.md) | `drafts/06-security.md` | 00, 01–05 | ~1 400 | 023–025 |
| 07 | [Observability & operational excellence](phases/phase-07-observability.md) | `drafts/07-observability.md` | 00, 03, 05 | ~1 000 | 026–027 |
| 08 | [Cost optimization & FinOps](phases/phase-08-cost.md) | `drafts/08-cost.md` | 00, 01–07 | ~1 300 | 028–029 |
| 09 | [Well-Architected alignment & growth roadmap](phases/phase-09-well-architected-growth.md) | `drafts/09-wellarchitected-growth.md` | 01–08 | ~900 | — |
| 10 | [Diagrams](phases/phase-10-diagrams.md) | `../diagrams/01…05` | 01–09 | ~700 | — |
| 11 | [Body assembly](phases/phase-11-assembly.md) | `../README.md` §0–§9 | 00–10 | assembles | — |
| 12 | [Summary, decision register & appendices](phases/phase-12-frontmatter-and-register.md) | `../README.md` complete | 11 | ~1 200 | collects |
| 13 | [QA, consistency audit & final polish](phases/phase-13-qa-and-final.md) | corrected `../README.md` | 12 | audits | — |

**29 Architecture Decision Records** in total, ADR-001 to ADR-029, allocated per phase in
[`decision-register.md`](decision-register.md) §2 — all written into the phase drafts as the full
design record. Phase 12 promotes **nine of them** into the graded document's Appendix B (the
selection is fixed in §2a); the other twenty surface only as a row in the Summary of Key Decisions
table. Phase 13 verifies the promoted nine are exactly right and the other twenty each have a row.
*(Amended 2026-08-14 — originally all 29 were promoted; see `STATE.md` for why.)*

> **Note.** Phases 01–05 hard-depend only on Phase 00 and can be re-run in isolation. Run everything
> in numeric order anyway: Phases 06–09 are written to *reference rather than repeat* the earlier
> drafts and can only do that if those drafts exist, and Phase 09 synthesises all of 01–08. Phases 10
> through 13 are strictly sequential and must come last.
>
> Assembly is deliberately split across two phases. Phase 11 does the editing work — de-duplicating
> the seams and normalising the voice across ten drafts — and Phase 12 adds the executive summary,
> the decision register, and the appendices on top. One agent doing both would run out of attention
> before reaching the part the client cares most about.

---

## 5. Supporting documents

| File | Status | What it is |
|---|---|---|
| [`AGENT-PROTOCOL.md`](AGENT-PROTOCOL.md) | Normative | Boundaries, execution loop, writing rules, anti-patterns |
| [`brief.md`](brief.md) | Normative | The client brief verbatim + the R1–R28 requirements register |
| [`contract.md`](contract.md) | Normative | Fixed names, CIDRs, services, numbers, the three-tier model (§1a), cost anchors (§11), the final section map (§14) |
| [`decision-register.md`](decision-register.md) | Normative | ADR template, the 29-record allocation, the nine-record Appendix B promotion rule (§2a), the standard a justification must meet |
| [`well-architected.md`](well-architected.md) | Normative | The six pillars applied to this design; tagging convention; accepted trade-offs |
| [`style-guide.md`](style-guide.md) | Normative | Voice, Markdown conventions, Mermaid rules, banned words |
| [`rubric.md`](rubric.md) | Reference | How a reviewer will score it; the depth probes they will run |
| [`STATE.md`](STATE.md) | Living | Progress, completion reports, ADR ledger, open questions, cross-phase issues |

---

## 6. If something goes wrong

| Situation | What to do |
|---|---|
| A dependency phase is not `done` | Stop. Tell the human which phase must run first. Do not do its work. |
| `contract.md` is missing a value you need | Invent one following the naming convention, record it in `contract.md` §12, flag it in your report. |
| You think a `contract.md` value is wrong | Use it anyway. Log the objection in `STATE.md` → *Open questions*. Consistency beats correctness on a debatable call. |
| You need more ADR numbers than your block allows | Use the top of your block and log it. Never take a number from another phase's range. |
| A prior draft contradicts yours | Do **not** edit their file. Log it in `STATE.md` → *Cross-phase issues*. Phase 13 resolves it. |
| Your phase document seems to contradict `brief.md` or `docs/assessment.md` | The assessment wins, then `brief.md`. Log it. |
| You are asked to do two phases at once | Do the first, report, stop. Explain why. |
