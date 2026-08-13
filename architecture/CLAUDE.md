# Innovate Inc. — Cloud Architecture Design Assignment

This directory is the **Innovate Inc. cloud architecture design** assignment: the deliverable and the
plan that produces it. The client brief is [`docs/assessment.md`](docs/assessment.md).

It is a **separate assignment** from the Terraform / EKS + Karpenter task, which lives under
`terraform/` and is being worked on concurrently by another agent.

## If you were asked to "do the task" or "continue with the next task"

Read [`_plan/README.md`](_plan/README.md) and execute the next phase whose status in
[`_plan/STATE.md`](_plan/STATE.md) is not `done`. That file is the entry point; everything you need
is reachable from it. **One phase per session** — finish it, update `STATE.md`, report, and stop.

## Hard boundary

Work **only** inside `architecture/`. Never read or write `terraform/`, `.claude/`, or anything above
`architecture/`. Do not run repository-wide searches — your phase document lists exactly what to
read.

## Nature of the work

A **paper design exercise**. The deliverable is an architecture *document*, not infrastructure. Do
not run `aws`, `kubectl`, `terraform`, `helm`, or `docker`; do not browse the web; do not produce
Terraform or Kubernetes manifests as deliverables. The output is Markdown with Mermaid diagrams.

## What makes this deliverable good

Four things, all enforced by the plan:

1. **Every decision is justified** — inline as decision → why → what it beat → what it costs, and
   again as a numbered Architecture Decision Record with a mandatory plain-language field written for
   a non-engineer founder. See [`_plan/decision-register.md`](_plan/decision-register.md).
2. **Aligned to the AWS Well-Architected Framework** — every section tagged with the pillars it
   serves, plus a dedicated chapter. See [`_plan/well-architected.md`](_plan/well-architected.md).
3. **Presented as a three-tier architecture** — presentation, application, data — with the network,
   compute, and security boundaries aligned to the same three lines. See `_plan/contract.md` §1a.
4. **DevSecOps by construction** — security and cost are properties of each decision, automated
   where possible, not chapters appended at the end.

## Layout

```
architecture/
├── README.md              ← THE DELIVERABLE (created in Phase 11)
├── CLAUDE.md              ← this file
├── docs/assessment.md     ← the client brief as supplied
├── diagrams/              ← Mermaid sources (Phase 10)
└── _plan/                 ← the plan; not graded
    ├── README.md          ← START HERE
    ├── AGENT-PROTOCOL.md  ← rules of engagement (normative)
    ├── STATE.md           ← progress, ADR ledger, handoff log
    ├── brief.md  contract.md  decision-register.md
    ├── well-architected.md  style-guide.md  rubric.md
    ├── phases/            ← phase-00 … phase-13
    └── drafts/            ← section drafts
```
