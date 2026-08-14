# Phase 09 — Well-Architected Alignment & Growth Roadmap

> Answers requirements **R20** (scalable, hundreds → millions), **R25** (best practices), and
> **R27** (Well-Architected alignment).
> Read [`../AGENT-PROTOCOL.md`](../AGENT-PROTOCOL.md),
> [`../well-architected.md`](../well-architected.md), [`../contract.md`](../contract.md), and
> [`../style-guide.md`](../style-guide.md) first.

---

## Goal

Two closing chapters that only make sense once every other section exists, because both are
syntheses rather than new design.

1. **Well-Architected Framework alignment** — demonstrate that this design was built against the
   framework rather than described and then retrofitted to it. The evidence for that is not a
   checklist; it is the **trade-off table**, where the design admits which pillar it leaned toward
   and which it gave up.
2. **Growth roadmap** — what happens between a few hundred users and a few million: what breaks
   first, in what order, what the observable signal is, and what the answer is. This is the section
   that proves the day-1 design was chosen with the 100× version in mind.

This phase writes **no new architecture**. Everything you say must already be true of the design in
drafts 01–08. If you find a genuine gap while synthesising, log it in `STATE.md` → *Cross-phase
issues* rather than quietly inventing a new component.

---

## Dependencies

Phases **01–08** must all be `done`. This phase synthesises them.

## Inputs

| File | Use it for |
|---|---|
| `_plan/well-architected.md` | **Your primary source.** §1 pillar demands, §3 trade-offs, §4 output spec |
| `_plan/contract.md` §11 | The growth-stage trajectory (cost side of the roadmap) |
| `_plan/contract.md` §14 | The locked final section map — cite chapters as `§N.M Name` |
| `_plan/contract.md` §1a | The three tiers — each scales differently and must be traced separately |
| `_plan/drafts/01`–`08` | Everything you are synthesising. Read them all. |
| `_plan/rubric.md` §2.C, §3 probes 8 and 11 | The scoring dimension and the probes |

## Files you own

- `_plan/drafts/09-wellarchitected-growth.md` — create
- `_plan/STATE.md` — update
- `_plan/contract.md` §12 — append only if you invent a name

No ADR block is reserved for this phase — you are attributing decisions already recorded, not making
new ones. If synthesis genuinely forces a new decision, that is a signal something is missing
upstream: log it as a cross-phase issue.

## Word budget

**~900 words** (±20%), excluding tables — cut from the original ~1,400 as part of a 2026-08-14
plan-wide leaning-down (see `STATE.md`). Roughly 500 for the pillar chapter (six subsections at ~60
words each plus the trade-off framing) and 400 for the roadmap. Hit this by writing tighter, not by
dropping a pillar or a roadmap stage — both are still required in full.

---

## Part one — Well-Architected Framework alignment

### `## Well-Architected Framework alignment` (~150 words intro)

Open with two things and no more. First, one short paragraph on what the framework is, for a client
who has not met it: AWS's articulation of what a well-built cloud workload looks like, organised into
six pillars, used as a design tool rather than a certification. Second, the honest statement that
makes the chapter credible: **a design cannot maximise all six pillars simultaneously, and the value
of the framework is that it forces you to say which one you gave up and why.**

> **Well-Architected pillars.** All six.

### `### Operational Excellence` through `### Sustainability` (~60 words each)

One subsection per pillar, in the framework's canonical order: Operational Excellence, Security,
Reliability, Performance Efficiency, Cost Optimization, Sustainability. Each subsection contains
exactly three things, per `well-architected.md` §4:

1. **One sentence** on what the pillar asks. Not a paragraph, not a quotation.
2. **A table** — `What this design does | Where` — of concrete decisions from this document that
   serve the pillar, each with a section reference taken from `contract.md` §14 and written as
   `§N.M Name`. Draw the rows from `well-architected.md` §1, which already maps them, but **verify
   each against the draft it claims** — an invented evidence row is the most likely failure in this
   phase. Five to eight rows each.
3. **One honest gap or deferral**, with its trigger. Formatted as a short paragraph beginning "Not
   yet addressed:". A pillar section with no gap reads as marketing and a reviewer will notice.

Suggested gaps, one per pillar, if you need a starting point — but verify each against what the
drafts actually say before using it:

| Pillar | Candidate gap |
|---|---|
| Operational Excellence | No dedicated on-call rotation or formal change-advisory process at this team size; game days are planned rather than proven |
| Security | No service mesh mTLS for east-west traffic; no managed detection and response; formal penetration testing not yet scheduled |
| Reliability | Single production region; a 60-minute recovery time objective for regional failure; disaster recovery drills quarterly rather than continuous |
| Performance Efficiency | No caching tier at launch; no load testing at target scale; database read/write splitting deferred to the application layer later |
| Cost Optimization | No commitment discounts until the baseline stabilises; per-namespace showback introduced rather than chargeback |
| Sustainability | No measurement of the workload's carbon footprint; region selection driven by latency and cost rather than grid carbon intensity |

### `### Accepted trade-offs between pillars` (~150 words + table)

**The most important part of this chapter**, and rubric probe 11. Reproduce and extend the trade-off
table from `well-architected.md` §3 — columns `Trade-off | Leaned toward | At the expense of | Why,
for Innovate Inc.` — with every row present, plus any additional trade-offs the content phases
flagged in `STATE.md`.

Then two or three sentences of framing: these are not compromises the design fell into, they are
positions it took, each with a trigger elsewhere in the document for revisiting it. Point at the
growth roadmap and the ADR *Revisit when* fields as the mechanism that keeps them from becoming
permanent by accident.

---

## Part two — Growth roadmap

### `## Growth roadmap — from hundreds to millions` (~150 words intro + stage table)

Open by naming the principle that makes the roadmap meaningful: **the decisions that are expensive to
change later were made for stage 4 on day 1** — the account structure, the address plan, the cluster
topology, the choice of database engine. Everything else is intended to change, and the roadmap says
when.

Then the four-stage table. Costs come from `contract.md` §11; do not invent any.

| Stage | Scale | What changes | Trigger |
|---|---|---|---|
| **1 — Launch** | a few hundred daily users | The design as written | — |
| **2 — Traction** | ~10 000 daily users | Aurora read replicas with reads routed to the reader endpoint; Amazon ElastiCache for Redis for sessions and hot reads; raised Serverless v2 ceiling; background work moved to SQS with KEDA-scaled workers; managed Prometheus and Grafana | p95 latency drifting up; database capacity sustained high; monitoring blind spots during an incident |
| **3 — Scale** | ~100 000 daily users | Prefix delegation and the secondary pod CIDR in earnest; Shield Advanced and tightened WAF; a service mesh if service count grows; Compute Savings Plans; Aurora Global Database serving regional reads; read/write splitting in the application | Pods pending on IP exhaustion; NAT bandwidth saturation; DDoS exposure; a predictable compute baseline |
| **4 — Millions** | millions of daily users | Multi-region active-active with latency-based routing; partitioning or sharding the write path; cell-based architecture; a dedicated platform team | Single-region recovery time no longer acceptable to the business; a single writer becomes the ceiling; blast radius of one bad deployment unacceptable |

### `### What breaks first, and in what order` (~250 words)

The part reviewers actually probe (rubric probe 8). Prose, ordered, each with **the observable
signal** and **the answer**. Trace it through the three tiers, because that framing makes the order
non-obvious in a useful way — the presentation tier essentially never breaks, and everything else
does.

1. **Database connections, before database CPU.** Each gunicorn worker in each Flask pod holds its
   own connections and PostgreSQL allocates a process per connection, so a growing pod fleet exhausts
   connections long before it exhausts compute. Signal: RDS Proxy connection-pool utilisation.
   Already answered by the proxy in the design; the next step beyond it is read/write splitting.
2. **Pod IP addresses.** Every pod holds a VPC address. Signal: pods stuck `Pending` with
   insufficient-IP events. The answer — prefix delegation and the `100.66.0.0/16` secondary CIDR — is
   already in the network design, and the point is that it must be **enabled before the ceiling is
   hit**, because retrofitting custom networking on a live cluster is disruptive.
3. **NAT Gateway throughput and cost.** Signal: NAT data-processing charges climbing faster than
   traffic. Answer: more VPC endpoints, then caching egress-heavy dependencies.
4. **CloudFront cache hit ratio and origin load.** Signal: origin request rate rising faster than
   user count. Answer: cache-control discipline on API responses and asset versioning — a
   presentation-tier problem with an application-tier fix.
5. **The single Aurora writer.** Reads scale to fifteen replicas; **writes do not scale horizontally
   at all.** Signal: write latency and replication lag under sustained load. The answer arrives in
   stages — batch and defer writes, move high-volume append-only data out of the primary, then
   partition or shard. State plainly that this is **the hardest ceiling in the entire design**, that
   it is a schema decision rather than an infrastructure one, and that it should therefore be
   considered while the schema is still soft.
6. **The team.** At some point the constraint is not the architecture but the number of people who
   can operate it. This is the honest reason the design defers a service mesh, active-active, and
   Shield Advanced rather than building them now.

Close the section with one sentence: none of the stage-2 through stage-4 changes require rebuilding
the foundation, because the foundation was chosen for stage 4.

---

## Acceptance criteria

- [ ] File is `_plan/drafts/09-wellarchitected-growth.md`, 720–1 080 words excluding tables.
- [ ] All six pillars have their own `###` subsection, in canonical order, **including
      Sustainability**.
- [ ] Each pillar subsection has exactly three parts: one-sentence demand, a 5–8 row table with
      section references, and a stated gap with a trigger.
- [ ] Every claim in a pillar table is **actually true of drafts 01–08** — you verified it, you did
      not assume it.
- [ ] The trade-off table is present with every row from `well-architected.md` §3, plus anything
      flagged in `STATE.md`.
- [ ] The chapter contains **no recitation of Well-Architected Framework documentation** — no quoted
      design principles, no review questions, no generic pillar definitions beyond one sentence each.
- [ ] The growth roadmap has four stages, each with an explicit **trigger**.
- [ ] "What breaks first" is ordered, with a signal and an answer for each, traced across the three
      tiers.
- [ ] The single-writer ceiling is named as the hardest one and framed as a schema decision.
- [ ] The team is named as a scaling constraint.
- [ ] The "foundation chosen for stage 4" point is made at both the start and the end.
- [ ] All cost figures come from `contract.md` §11.
- [ ] **No new architecture introduced.** Any gap found is logged as a cross-phase issue instead.
- [ ] No `TODO`/`TBD`; no banned words; no emoji.
- [ ] `STATE.md` updated.

## Common failure modes

| Failure | Avoid it by |
|---|---|
| A pillar chapter that quotes the framework | Map *this* design. One sentence per pillar on what it asks, then evidence. |
| Every pillar section says the design is excellent | Each one names a real gap and its trigger. |
| Claiming something in a pillar table that no draft actually says | Verify each row against the drafts. This is the most likely correctness failure in the phase. |
| Skipping Sustainability or padding it | Three genuine stories: Graviton, consolidation, scale-to-zero. Say they overlap with cost. |
| A roadmap of aspirations with no triggers | Each stage names the metric that starts it. |
| Introducing a new component while synthesising | Log it as a cross-phase issue; Phase 12 decides. |
| "It scales because Kubernetes" | Name the ceiling, the signal, and the answer. |

---

## Agent prompt

```text
You are executing Phase 09 of the Innovate Inc. architecture design plan: Well-Architected
Alignment & Growth Roadmap.

Working directory boundary: architecture/ ONLY. Never read or write terraform/, .claude/, or
anything above architecture/ — terraform/ belongs to a different assignment that another agent
may be editing right now.

Read in full, in order:
  architecture/_plan/AGENT-PROTOCOL.md
  architecture/_plan/well-architected.md    (your primary source)
  architecture/_plan/contract.md            (§1a three tiers, §11 growth-stage costs)
  architecture/_plan/style-guide.md
  architecture/_plan/rubric.md
  architecture/_plan/STATE.md               (check Cross-phase issues for flagged trade-offs)
  architecture/_plan/phases/phase-09-well-architected-growth.md
  architecture/_plan/drafts/01-cloud-environment.md through drafts/08-cost.md

Do not read any other file. No repository-wide searches. No aws/kubectl/terraform/docker/helm.
No web browsing.

Write architecture/_plan/drafts/09-wellarchitected-growth.md following the content specification
exactly: six pillar subsections each with a demand, an evidence table, and an honest gap; the
trade-off table; then the four-stage growth roadmap and the ordered "what breaks first" analysis.

This phase writes NO new architecture. Every claim in a pillar evidence table must be verifiably
true of drafts 01-08 — check each one. If you find a genuine gap, log it in STATE.md under
Cross-phase issues rather than inventing a component to fill it.

Do NOT quote or recite Well-Architected Framework documentation. The chapter's only value is the
mapping to this specific design.

Then verify every acceptance criterion line by line, fix what fails, update STATE.md, report,
and STOP. Do not begin Phase 10.
```
