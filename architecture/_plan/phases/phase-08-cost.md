# Phase 08 — Cost Optimization & FinOps

> Answers requirement **R22** ("cost-effective") and carries the **Cost Optimization** pillar.
> Read [`../AGENT-PROTOCOL.md`](../AGENT-PROTOCOL.md), [`../contract.md`](../contract.md),
> [`../decision-register.md`](../decision-register.md),
> [`../well-architected.md`](../well-architected.md), and [`../style-guide.md`](../style-guide.md)
> first.

---

## Goal

The client is a small startup. "Cost-effective" is not a nice-to-have in their brief; it is one of
four adjectives they used to describe what they want. This section has to do three things a
one-paragraph cost note cannot:

1. **Tell them what it costs**, broken down, honestly labelled, with a cheaper variant.
2. **Tell them how it changes** as they grow, and why cost per user falls before it rises.
3. **Tell them how to keep control of it** — the FinOps practices that stop a cloud bill becoming a
   month-end surprise.

The reviewer's test is whether cost was treated as a design constraint that shaped decisions, or as
an afterthought appended to a design that was made without it. The evidence for the former is that
this section can point at choices elsewhere in the document — Graviton, Spot, Serverless v2, a single
NAT Gateway in development — and say "that was a cost decision, and here is what it traded away".

---

## Dependencies

Phase 00 must be `done`. Phases 01–07 should be `done` — you are pricing the design they describe,
and you reference their decisions rather than re-arguing them.

## Inputs

| File | Use it for |
|---|---|
| `_plan/contract.md` **§11** | Cost anchors, the growth-stage trajectory, the named levers — **use these figures and invent none** |
| `_plan/contract.md` §1a | The three tiers, each with a different cost profile |
| `_plan/well-architected.md` COST, SUS | What the Cost Optimization and Sustainability pillars demand |
| `_plan/decision-register.md` | ADR template; **your block is ADR-028 – ADR-029** |
| `_plan/drafts/01`–`07` | The design you are pricing |

## Files you own

- `_plan/drafts/08-cost.md` — create
- `_plan/STATE.md` — update, including the ADR ledger
- `_plan/contract.md` §12 — append only if you invent a name

## Word budget

**~1 300 words** (±20%) for the body, plus **2 ADRs** (ADR-028 – ADR-029).

---

## The one rule that matters most

**Every dollar figure in this section comes from `contract.md` §11. You invent nothing.**

Read the warning at the top of `contract.md` §11 before you write a number. Those figures are
order-of-magnitude anchors, not verified list prices. They exist so that the whole document quotes
the same numbers, not so that they can be presented as a quote. Every table of figures you write must
carry the word **indicative** and a pointer to the AWS Pricing Calculator, and you must not derive
new figures by arithmetic on them beyond simple totals that already appear in the contract.

Where you want to say something quantitative that `contract.md` does not fix, say it **relatively**:
"NAT Gateway hourly charges dominate fixed cost at low traffic" is safe and useful; "NAT Gateways
cost $0.045 per GB" is a fact you must not assert.

---

## Content specification

Each `##` section closes its opening paragraph with a `> **Well-Architected pillars.**` line.

### `## What this architecture costs` (~250 words + table)

- Reproduce the day-1 cost table from `contract.md` §11 exactly, every line item and both totals.
  Label it in the sentence above the table: **indicative list prices in `us-east-1` for the day-1
  footprint across all three environments**, not a quote, with a pointer to the AWS Pricing
  Calculator.
- Then the observation that is genuinely useful to a founder and that most designs omit: **at launch,
  almost none of this cost is driven by users.** Three EKS control planes, NAT Gateways, and the
  security baseline are fixed charges that would be nearly identical with ten users or ten thousand.
  Name the consequence: the first thousand users are expensive per head, and that is what buying a
  foundation costs.
- Break the cost down **by tier** as a short table, because it makes the three-tier model pay off
  again here: the presentation tier is nearly free and scales almost for free; the application tier
  is the largest variable cost and the one Spot and Graviton attack; the data tier is small at launch
  and becomes dominant at scale.

### `## The lean-start variant` (~200 words + table)

A second costed option, because a good consultant gives the client a choice rather than a bill.

- Reproduce the lean figure from `contract.md` §11.
- Table: Change | Saves | Gives up. Cover at minimum: development and staging sharing one EKS
  cluster; a single NAT Gateway in every non-production VPC; no reader replica in non-production;
  in-cluster Prometheus instead of the managed services; shorter log retention.
- **State clearly what is lost**, because this is where honesty shows: a staging environment that
  shares a cluster with development is no longer a faithful rehearsal of production, and a
  single-NAT non-production environment stops working when its AZ has a bad day.
- Give a recommendation rather than a menu: which trades to take first, and which one to take last.
  The last one to take is anything that makes staging stop resembling production, because the whole
  value of staging is fidelity.

### `## How cost scales with growth` (~250 words + table)

- Reproduce the growth-stage trajectory table from `contract.md` §11 — four stages, indicative
  monthly spend, and what drives it at each.
- Explain **the shape of the curve** in prose, which is the part a founder actually needs: fixed
  costs dominate at launch, so cost per user falls steeply through the first order of magnitude of
  growth; once compute and data transfer take over it becomes roughly linear; commitment discounts
  and better utilisation then bend it back down. Cost per user at stage 3 is roughly two orders of
  magnitude below stage 1.
- **Unit economics**: recommend they track cost per monthly active user and cost per thousand API
  requests from the beginning, because those are the numbers that tell them whether the business
  works — a total cloud bill on its own never does.
- One sentence on what would break the curve: an unbounded log or metric retention policy, a
  chatty third-party integration crossing the NAT Gateway, or cross-AZ data transfer from a workload
  that ignores topology. All three are cheap to prevent and expensive to discover.

### `## Optimization levers` (~300 words + table)

A table with columns **Lever | What it saves | What it costs you | When to apply**, drawn **only**
from the named list in `contract.md` §11. At minimum, all of these:

Graviton; Spot for the stateless application tier; Karpenter consolidation and node expiry;
Aurora Serverless v2 minimum-capacity floor; a single NAT Gateway in non-production; VPC endpoints
reducing NAT data processing; S3 lifecycle tiering; CloudWatch log retention tiers; right-sizing from
Vertical Pod Autoscaler recommendations; Compute Savings Plans once the baseline is predictable;
reserved capacity for the Aurora floor; scheduled shutdown of development outside working hours.

Then two paragraphs of judgement, which is what separates this from a list:

- **Order matters.** The levers with the best ratio of saving to risk come first: Graviton and
  Karpenter consolidation are close to free wins; Spot is a large win that requires the application
  to tolerate interruption; Savings Plans are a large win that requires a stable baseline and
  therefore must *not* be bought on day one. Say why buying a commitment early is a trap for a
  startup whose architecture is still moving.
- **The lever nobody lists**: not building things yet. Deferring a service mesh, Shield Advanced,
  multi-region, and a data warehouse is the largest single cost saving in this design, and it is the
  one that also reduces operational load. Cross-reference the growth roadmap in §9.

> **Note.** Cost Optimization and Sustainability point the same way here. Graviton, consolidation,
> and scale-to-zero reduce both the bill and the energy consumed. Say so once, plainly — it is more
> credible than inventing a separate sustainability programme.

### `## FinOps governance` (~300 words + table)

The practices that keep cost under control once the architecture is built. This is the Cost
Optimization pillar's actual demand — cloud financial management as an ongoing practice with an
owner, not a one-time sizing exercise.

- **Attribution first.** The mandatory tag set from `contract.md` §9, enforced by an AWS
  Organizations tag policy and an AWS Config rule so untagged resources are visible immediately.
  Account-level separation already gives a floor of accurate attribution that tags alone never do —
  cross-reference §1.
- **Visibility.** AWS Cost Explorer with per-account and per-tag views; per-namespace showback inside
  the cluster with OpenCost or Kubecost so a team can see what its own workload costs.
- **Guardrails.** AWS Budgets with alerts at 80% and 100% of the monthly target, per account. AWS
  Cost Anomaly Detection for the spike that no budget threshold would catch in time. A hard budget
  cap and automatic teardown on sandbox accounts.
- **Cadence.** A short monthly review with one named owner; a cost line in the definition of done for
  any change that adds infrastructure; the AWS Compute Optimizer and Vertical Pod Autoscaler
  recommendations reviewed quarterly.
- **Culture**, stated in one sentence without preaching: cost is an engineering metric with an owner,
  not a finance surprise at month end. The engineers who create cost are the only ones who can
  remove it.

Close with a short table: Control | Mechanism | Cadence.

---

## Decision Records — ADR-028 to ADR-029

End the draft with `## Decision Records` containing 2 ADRs from your reserved block. They must
cover:

- **ADR-028 — Deferring Compute Savings Plans and Reserved Instances until the baseline is stable.**
  Options: buy now for the discount, buy later, never commit. Explain the trap: a one- or three-year
  commitment bought against an architecture that is still changing locks in the wrong instance family
  or the wrong quantity, and the waste exceeds the discount.
- **ADR-029 — Offering the lean-start variant as a documented option rather than the default.** Why
  the fuller design is the recommendation, what would make the lean variant the right call, and how
  cost is attributed either way.

The **"Why this is the right choice for Innovate Inc."** field matters especially here, because cost
is the topic a founder understands best and is most likely to challenge. Write it as you would say it
across a table: what they will pay, what they get, and what you would cut first if they asked you to.

---

## Acceptance criteria

- [ ] File is `_plan/drafts/08-cost.md`, 1 050–1 600 words excluding tables and ADRs.
- [ ] Five `##` sections, each opening with prose and closing that paragraph with a pillar line.
- [ ] **Every dollar figure traces to `contract.md` §11.** No invented numbers, no derived rates, no
      per-GB or per-hour prices asserted as fact.
- [ ] Every figure table is labelled **indicative** and points at the AWS Pricing Calculator.
- [ ] The day-1 breakdown is present, plus a per-tier breakdown.
- [ ] The "fixed cost dominates at launch" insight is stated explicitly.
- [ ] The lean-start variant is costed **and** its losses are stated, with a recommendation on
      ordering.
- [ ] The four-stage growth trajectory is present with the shape of the curve explained.
- [ ] Unit economics recommended, with the specific metrics to track.
- [ ] At least **twelve** optimization levers, each with what it costs you and when to apply it.
- [ ] The ordering judgement is present — free wins first, commitments last, and why.
- [ ] The Cost/Sustainability overlap is acknowledged rather than duplicated.
- [ ] FinOps governance covers attribution, visibility, guardrails, cadence, and ownership.
- [ ] `## Decision Records` present with 2 ADRs from ADR-028 – ADR-029, full template.
- [ ] No re-designing of infrastructure — you are pricing and governing the design, not changing it.
- [ ] No `TODO`/`TBD`; no banned words; no emoji.
- [ ] `STATE.md` updated, including the ADR ledger row for Phase 08.

## Common failure modes

| Failure | Avoid it by |
|---|---|
| Inventing a per-GB or per-hour price | Only `contract.md` §11 figures. Otherwise speak relatively. |
| Presenting indicative anchors as a quote | Label every table, every time. |
| A lever list with no trade-offs | Every lever costs something. Name it. |
| Recommending Savings Plans on day one | It is the classic startup cost trap. Make it an ADR. |
| Cost governance as a paragraph of good intentions | Named mechanisms, named cadence, named owner. |
| Re-arguing architecture decisions | You price the design; Phases 01–07 make it. |
| Forgetting sustainability entirely | It overlaps this section. One honest paragraph. |

---

## Agent prompt

```text
You are executing Phase 08 of the Innovate Inc. architecture design plan: Cost Optimization & FinOps.

Working directory boundary: architecture/ ONLY. Never read or write terraform/, .claude/, or
anything above architecture/ — terraform/ belongs to a different assignment that another agent
may be editing right now.

Read in full, in order:
  architecture/_plan/AGENT-PROTOCOL.md
  architecture/_plan/brief.md
  architecture/_plan/contract.md           (§11 is your ONLY source of figures — read its warning)
  architecture/_plan/decision-register.md  (your ADR block is 028-029)
  architecture/_plan/well-architected.md
  architecture/_plan/style-guide.md
  architecture/_plan/rubric.md
  architecture/_plan/phases/phase-08-cost.md

Then skim whichever drafts exist (01-07) for the decisions you are pricing.

Do not read any other file. No repository-wide searches. No aws/kubectl/terraform/docker/helm.
No web browsing.

Write architecture/_plan/drafts/08-cost.md following the content specification exactly, ending
with a ## Decision Records section containing ADR-028 through ADR-029.

THE HARD RULE: every dollar figure must come from contract.md §11, every figure table must be
labelled indicative and point at the AWS Pricing Calculator, and you must not assert any per-GB,
per-hour, or per-request price that is not fixed there. Where you want to be quantitative and the
contract does not fix a number, speak relatively instead.

Then verify every acceptance criterion line by line, fix what fails, update STATE.md including the
ADR ledger, report, and STOP. Do not begin Phase 09.
```
