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
| 00 | Pre-flight, scope & three-tier framing | `todo` | — | `drafts/00-scope.md` | 001–003 |
| 01 | Cloud environment structure | `todo` | 00 | `drafts/01-cloud-environment.md` | 004–006 |
| 02 | Network design | `todo` | 00 | `drafts/02-network.md` | 007–010 |
| 03 | Compute platform — EKS | `todo` | 00 | `drafts/03-compute-eks.md` | 011–014 |
| 04 | Containerization & CI/CD | `todo` | 00 | `drafts/04-containers-cicd.md` | 015–018 |
| 05 | Database | `todo` | 00 | `drafts/05-database.md` | 019–022 |
| 06 | Security & data protection | `todo` | 00, 01–05 | `drafts/06-security.md` | 023–025 |
| 07 | Observability & operational excellence | `todo` | 00, 03, 05 | `drafts/07-observability.md` | 026–027 |
| 08 | Cost optimization & FinOps | `todo` | 00, 01–07 | `drafts/08-cost.md` | 028–029 |
| 09 | Well-Architected alignment & growth roadmap | `todo` | 01–08 | `drafts/09-wellarchitected-growth.md` | — |
| 10 | Diagrams | `todo` | 01–09 | `../diagrams/01…05` | — |
| 11 | Body assembly | `todo` | 00–10 | `../README.md` §0–§9 | — |
| 12 | Summary, decision register & appendices | `todo` | 11 | `../README.md` complete | collects all |
| 13 | QA, consistency audit & final polish | `todo` | 12 | corrected `../README.md` | — |

**Next phase to run:** `00`

---

## ADR ledger

Filled in by each phase as it completes, so Phase 12 can assemble the register in order and Phase 13
can check for gaps and duplicates. Record the numbers you **actually wrote**.

| Phase | Block (exact) | Numbers written | Titles |
|---|---|---|---|
| 00 | 001–003 | — | — |
| 01 | 004–006 | — | — |
| 02 | 007–010 | — | — |
| 03 | 011–014 | — | — |
| 04 | 015–018 | — | — |
| 05 | 019–022 | — | — |
| 06 | 023–025 | — | — |
| 07 | 026–027 | — | — |
| 08 | 028–029 | — | — |

The finished register is **ADR-001 to ADR-029, no gaps**. Counts are exact, not ranges — a phase that
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

---

## Open questions

> Things a phase agent could not resolve and did not want to silently decide. The human answers
> these; Phase 13 checks none are outstanding before the deliverable is called finished.

| Raised by | Question | Status | Answer |
|---|---|---|---|
| — | — | — | — |

---

## Cross-phase issues

> Contradictions, duplications, or gaps spotted between drafts. **Do not fix another phase's draft
> yourself** — log it here. Phase 13 owns resolution.

| Spotted by | Where | Issue | Resolved in |
|---|---|---|---|
| — | — | — | — |

---

## Deliverable location

The graded deliverable is **`architecture/README.md`**, assembled in Phase 11 (body) and Phase 12
(summary, decision register, appendices). The `architecture/`
directory is owned entirely by this assignment; the Terraform / EKS + Karpenter assignment lives
under `terraform/` and is off-limits to every agent working this plan.
