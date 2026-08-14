## What this architecture costs

"Cost-effective" is one of four adjectives Innovate Inc. used to describe what it wants, so this
section treats cost the way the rest of the document treats security: a property of the design, priced
honestly, not a paragraph bolted on at the end.

> **Well-Architected pillars.** Cost Optimization · Operational Excellence

The table below is the day-1 bill for all three environments combined — development, staging, and
production — at **indicative list prices in `us-east-1`**. It is not a quote; the AWS Pricing Calculator
is the tool for a real estimate, and every figure carries an explicit margin for that reason.

| Item | Monthly (indicative) | Note |
|---|---|---|
| EKS control planes × 3 | ~$220 | $0.10/h each. Biggest fixed cost at launch. |
| Worker nodes (Graviton, mostly Spot) | ~$120 | 2–4 small nodes per env; Karpenter consolidates aggressively |
| NAT Gateways (3 prod + 1 dev + 1 stg) | ~$170 | Hourly + data. VPC endpoints cut the data portion materially. |
| Aurora Serverless v2 (3 clusters, low ACU) | ~$130 | Prod writer+reader at min ACU; dev auto-pauses |
| ALB × 3 | ~$60 | Plus LCU |
| CloudFront + S3 | ~$15 | Low volume, free-tier-adjacent |
| ECR + backups + Secrets Manager | ~$25 | |
| CloudWatch / logs / metrics | ~$60 | Grows with log volume — set retention deliberately |
| GuardDuty / Security Hub / Config / Inspector | ~$70 | The price of the security posture; call it out honestly |
| **Total** | **≈ $850 – 900 / month** | |
| **Lean-start variant** | **≈ $400 – 450 / month** | Dev+staging share one cluster, single NAT everywhere, no reader replica in non-prod, in-cluster Prometheus instead of AMP/AMG |

The observation most cost sections skip: **at launch, almost none of this bill is driven by users.**
Three Amazon Elastic Kubernetes Service (EKS) control planes, five Network Address Translation (NAT)
Gateways, and the security baseline (GuardDuty, Security Hub, Config, Inspector) are fixed charges that
would be nearly identical with ten users or ten thousand.
`10.30.0.0/16` costs the same whether it carries one packet or one million. The consequence for a
founder is direct: the first thousand users are expensive per head, and that expense is what buying a
foundation — isolation, failover, an audit trail — costs before a single one of them logs in.

Grouping the same nine line items by tier instead of by service makes the three-tier model pay off
again here, rather than being a diagram that stops mattering once the design turns into a bill.

| Tier | What lands there | Cost behavior |
|---|---|---|
| Presentation | CloudFront + S3 | Nearly free at this volume, and scales at the edge without any action required |
| Application | EKS control planes, worker nodes, Application Load Balancers (ALBs) | The largest variable cost line, and the one Graviton, Spot, and Karpenter consolidation attack directly |
| Data | Aurora Serverless v2 | Small at launch; the tier that grows fastest as capacity units and read replicas are added |
| Platform and security baseline | NAT Gateways, ECR/backups/Secrets Manager, CloudWatch, the security tooling stack | A fixed cost of running three isolated, secured environments, not attributable to any single tier |

---

## The lean-start variant

A good consultant gives a client a choice, not only a bill. The lean-start variant is the same
architecture with five changes applied, reaching the **≈$400–450/month** figure reproduced above —
again **indicative**, again worth confirming against the AWS Pricing Calculator.

> **Well-Architected pillars.** Cost Optimization · Reliability

| Change | Saves | Gives up |
|---|---|---|
| Development and staging share one EKS cluster | A third control plane's fixed hourly charge and a duplicated worker-node fleet | Staging stops being an isolated single-tenant rehearsal — a noisy or broken development deployment now shares infrastructure with the staging release-candidate gate |
| One non-production NAT Gateway instead of two | The second of the two non-production NAT Gateways' fixed and data-processing charges | An Availability Zone-local NAT failure now stops outbound traffic for the whole non-production environment rather than only one of two |
| No reader replica in non-production | A reader instance's compute charge in dev and staging | Read-replica failover and read-scaled query patterns are no longer rehearsed before production; a read-heavy regression is caught for the first time in production |
| In-cluster `kube-prometheus-stack` permanently, not only at launch | The gap between self-hosted monitoring and Amazon Managed Service for Prometheus (AMP) and Amazon Managed Grafana (AMG) | Observability never migrates off the cluster it monitors — the single point of failure ADR-026 accepts temporarily becomes permanent |
| Shorter CloudWatch Logs retention | Storage and query cost on the cold tier | Less history for an audit or forensic investigation to look back through |

**State plainly what is lost**: this variant is cheaper because it removes rehearsal fidelity, not
because it removes waste. A staging environment that shares infrastructure with development is no
longer a faithful dress rehearsal of production, and that is the whole point of having a staging
environment in the first place.

We recommend taking these trades in a specific order, not all five at once. Shorter log retention, no
non-production reader replica, and staying in-cluster on Prometheus are close to free — they cost
fidelity nowhere that a founder or an engineer would notice day to day. Going to one non-production NAT
Gateway is a reasonable second step once the team accepts a shared non-production failure domain. The
**last** trade to take, and the one to avoid unless the budget genuinely has no other option, is
sharing the development and staging cluster — because it is the one change that makes staging stop
resembling production, and a staging environment that does not resemble production has stopped doing
its job.

---

## How cost scales with growth

The client asked for a design that survives growth from a few hundred users to potentially millions;
this table is what that growth costs, **indicatively**, at four points on that curve — again a shape to
plan around rather than a quote, and again worth checking against the AWS Pricing Calculator at each
stage.

> **Well-Architected pillars.** Cost Optimization · Performance Efficiency

| Stage | Daily active users | Indicative monthly spend | What is driving it |
|---|---|---|---|
| 1 — Launch | a few hundred | **≈ $850** (lean ≈ $420) | Almost entirely fixed: EKS control planes, NAT Gateways, security baseline |
| 2 — Traction | ~10 000 | **≈ $2 000 – 3 000** | Aurora capacity units and read replicas, a cache tier, larger node fleet, log volume |
| 3 — Scale | ~100 000 | **≈ $8 000 – 15 000** | Node fleet and Aurora dominate; Savings Plans start to bend the curve; CloudFront data transfer becomes visible |
| 4 — Millions | millions | **six figures, but sub-linear per user** | Multi-region, sharding or partitioning, dedicated platform capacity; commitment discounts and cell efficiency hold cost per user well below stage 1 |

The shape of this curve matters more than any single number in it. Fixed cost dominates at launch, so
cost per user falls steeply through the first order of magnitude of growth — stage 1's few hundred
users are carrying nearly the same bill stage 2's ten thousand users carry. Past that point, compute
and data transfer take over and the curve flattens into roughly linear, because those costs genuinely
scale with traffic. Commitment discounts and better utilization then bend it back down: cost per user
at stage 3 sits roughly **two orders of magnitude below stage 1**. That single comparison is the honest
answer to "is this expensive?" — at launch, per user, it is, and that is what buying a foundation costs.

**Unit economics.** We recommend Innovate Inc. track cost per monthly active user and cost per
thousand API requests starting on day one, not once the bill becomes large enough to worry about. A
total cloud bill never tells a founder whether the business works; cost per user compared against
revenue per user does, and it is far cheaper to build the habit of watching it early than to
reconstruct the history later.

> **Trade-off.** What would break this curve: an unbounded log or metric retention policy, a chatty
> third-party integration whose traffic crosses a NAT Gateway on every call, or cross-Availability
> Zone (AZ) data transfer from a workload that ignores which AZ its dependencies run in. All three are
> cheap to prevent with a deliberate retention policy, a virtual private cloud (VPC) endpoint, or a
> topology-aware deployment, and expensive to discover after months of unbounded growth.

---

## Optimization levers

Twelve levers cover most of what this design already spends money to avoid spending more of it.

> **Well-Architected pillars.** Cost Optimization · Sustainability

| Lever | What it saves | What it costs you | When to apply |
|---|---|---|---|
| Graviton (`arm64`) as the preferred architecture | Roughly 20% better price/performance than equivalent `x86` instances | A one-time multi-architecture image build pipeline | Day 1 — this is §3.3 Node strategy's default node family |
| Spot for the stateless application tier | Up to 70–90% off On-Demand pricing for the largest variable cost line | Nodes can be reclaimed on two minutes' notice; workloads must tolerate interruption | Day 1, application tier only — never the platform node group |
| Karpenter consolidation and node expiry | Removes underused nodes continuously instead of on a fixed schedule | A small amount of pod churn as nodes are replaced | Day 1 — `consolidateAfter: 1m`, `expireAfter: 720h` |
| Aurora Serverless v2 minimum-capacity floor | Database compute scales toward near-idle cost outside peak hours | A floor above zero, since the workload is never fully paused in production | Day 1 in production; dev auto-pauses fully |
| A single NAT Gateway in non-production | Removes redundant NAT Gateway charges where a multi-AZ failure is an accepted risk | Non-production loses NAT-level Availability Zone redundancy | Day 1 in dev and staging; never in production |
| VPC endpoints reducing NAT data processing | Removes AWS API traffic from the NAT Gateway's metered data path | A per-endpoint fixed charge, offsetting most of what it saves | Day 1 — already priced into the NAT Gateways line above |
| S3 lifecycle tiering | Moves cold objects (backups, old logs, build artifacts) to cheaper storage classes automatically | Restore latency on the coldest tier if an old object is ever needed | As soon as any bucket accumulates objects older than 30 days |
| CloudWatch log retention tiers | Bounds the fastest-growing line in the cost table before it grows unbounded | Less lookback for a very old investigation | Day 1 — the 14-day-hot / 400-day-cold split already applies this |
| Right-sizing from Vertical Pod Autoscaler (VPA) recommendations | Removes over-provisioned CPU and memory requests that Karpenter is otherwise billed to carry | Engineering time to review and apply recommendations | Quarterly, once real traffic patterns exist to size against |
| Compute Savings Plans once the baseline is predictable | A roughly 30% discount against a 12-month commitment | Locks in an instance family and a quantity for the commitment term | Once compute spend is stable — see ADR-028, not day 1 |
| Reserved capacity for the Aurora floor | A discount on the capacity the database never scales below | The same commitment risk as Savings Plans, scoped to the database | Same trigger as ADR-028 — a stable baseline, not day 1 |
| Scheduled shutdown of development outside working hours | Removes most of a low-value environment's runtime cost | Development is unavailable outside the scheduled window | Day 1 — development has no uptime commitment to anyone |

Order matters more than the list does. Graviton and Karpenter consolidation are close to free wins —
neither asks the team to accept a new risk, only to configure the default correctly. Spot is a large
win that costs something real: the application must genuinely tolerate interruption, which is why
§3.3 Node strategy keeps Spot off the platform node group entirely. Savings Plans and reserved capacity
are the largest wins on the list and also the ones to buy last, because a commitment purchased against
an architecture that is still finding its instance mix locks in the wrong family or the wrong quantity,
and the waste from a bad twelve-month bet exceeds the discount it was meant to capture — a startup
should not sign a stable-baseline discount before it has a stable baseline. That is the whole argument
behind ADR-028.

The lever nobody lists as a lever is **not building things yet**. Deferring a service mesh, AWS Shield
Advanced, a second active region, and a dedicated data warehouse is the single largest saving in this
design, and unlike every lever in the table above, it also reduces the operational load on a
five-person team rather than adding a configuration to maintain. §8 Growth Roadmap names the trigger
for each of these; none of them earns its cost today.

> **Note.** Cost Optimization and Sustainability point the same way in this design rather than pulling
> apart. Graviton, Karpenter consolidation, and scaling to near-idle all reduce the bill and the energy
> a workload consumes to serve the same traffic — the same decision serves both pillars, which is more
> credible than inventing a separate sustainability programme on top of it.

---

## FinOps governance

Sizing the architecture correctly once is not the same as keeping it correctly sized. This section is
the Cost Optimization pillar's actual demand: cloud financial management as an ongoing practice with a
named owner, not a spreadsheet exercise done at launch and never repeated.

> **Well-Architected pillars.** Cost Optimization · Operational Excellence

**Attribution first.** Every resource carries the mandatory tag set defined in §5.3 Data protection —
`Environment`, `Application`, `Owner`, `CostCenter`, `DataClassification`, `ManagedBy`, `Compliance` —
enforced by an AWS Organizations tag policy and an AWS Config rule, so an untagged resource is visible
immediately rather than discovered at the end of the month. Account-level separation (§1.1 Why multiple
accounts) already gives a floor of accurate attribution that tags alone never do on their own: a charge
on `innovate-staging`'s bill cannot be misattributed to production no matter how a resource is tagged.

**Visibility.** AWS Cost Explorer, filtered per account and per tag, is the org-wide view. Inside the
cluster, OpenCost or Kubecost gives per-namespace showback, so `innovate-api` and `innovate-jobs` each
see what they individually cost — visibility a tag policy alone cannot reach once several workloads
share one cluster.

**Guardrails.** AWS Budgets on every account, with alerts at 80% and 100% of the monthly target, catch
a slow overrun. AWS Cost Anomaly Detection catches the spike a fixed threshold would not — a
misconfigured job looping in a tight retry storm, for instance — before a monthly budget alert would
ever fire. Sandbox accounts carry a hard budget cap and automatic teardown, so an experiment cannot
become a surprise line item.

**Cadence.** A short monthly cost review with one named owner keeps this from drifting into nobody's
job. Any change that adds infrastructure carries a cost line in its definition of done. AWS Compute
Optimizer and VPA recommendations are reviewed quarterly, on the same cadence as the right-sizing lever
above.

**Culture**, in one sentence: cost is an engineering metric with an owner, the same as latency or error
rate, not a finance surprise discovered at month end — and the engineers who create a cost are the only
ones positioned to remove it.

| Control | Mechanism | Cadence |
|---|---|---|
| Attribution | Mandatory tag set + AWS Organizations tag policy + AWS Config rule | Continuous |
| Visibility | AWS Cost Explorer (per account/tag) + OpenCost/Kubecost (per namespace) | Continuous, reviewed monthly |
| Guardrails | AWS Budgets (80%/100% alerts) + Cost Anomaly Detection + sandbox budget caps | Continuous |
| Right-sizing | AWS Compute Optimizer + VPA recommendations reviewed and applied | Quarterly |
| Ownership | One named cost owner; a cost line in every infrastructure change's definition of done | Monthly review |

---

## Decision Records

Two decisions carry the argument for how Innovate Inc. buys and offers its own infrastructure spend:
when a commitment discount stops being a trap and starts being free money, and why the fuller design is
the recommendation rather than the cheaper one.

> **Well-Architected pillars.** Cost Optimization · Reliability

### ADR-028 — Deferring Compute Savings Plans and Reserved Capacity

| | |
|---|---|
| **Status** | Accepted |
| **Requirement** | R22, R25 |
| **Pillars** | Cost Optimization · Operational Excellence |
| **Section** | §7.4 Optimization levers |

**Context.** Innovate Inc. is a five-person team with no dedicated FinOps function, and its compute
mix — Graviton versus `x86` share, Spot versus On-Demand split, the Aurora Serverless v2 floor — is
still moving. Runway does not forgive a wasted commitment.

**Options considered.**

| Option | Strengths | Weaknesses | Verdict |
|---|---|---|---|
| Buy Compute Savings Plans and reserved Aurora capacity now, at launch | Locks in the discount — roughly 30% — as early as possible | Commits to today's instance family and quantity for a term that outlasts today's architecture | Rejected — the classic startup cost trap: a discount on a shape that is about to change |
| Never commit to a discount, stay entirely on-demand indefinitely | No lock-in risk, ever; maximum flexibility to change instance families freely | Leaves a real, recurring discount on the table permanently once the baseline genuinely does stabilize | Rejected — refusing a real saving forever is as much a mistake as buying one too early |
| Defer the commitment until compute spend is stable, then buy it | Captures the discount once it is safe to commit, with no wasted capacity risk in the meantime | Pays On-Demand or Spot pricing during the deferral period | **Chosen** |

**Decision.** We defer Compute Savings Plans and reserved Aurora capacity until the baseline stabilizes
(see Revisit when), then buy a 12-month commitment sized to it.

**Why this is the right choice for Innovate Inc.** A savings plan is a bet to keep buying roughly the
same thing for a year, and nobody can honestly make that bet yet. Buying the discount now locks in this
month's guess, and a wrong guess wastes more capacity than the discount saves. Paying full price longer
means the eventual commitment is bought against spending that has settled — the only way it pays off
instead of becoming a mistake.

**Consequences.**
- *Gains:* No risk of a mis-sized commitment; the discount lands once it is genuinely safe.
- *Accepts:* No fixed date for the discount — if spend never stabilizes, the team pays full price
  indefinitely and re-tests the trigger every quarter.

**Cost impact.** Forgoes the roughly 30% discount a correctly sized commitment would capture, versus
locking in the wrong capacity for a year.

**Revisit when.** Compute spend stays within roughly 15% of trend for two consecutive quarters and the
Graviton-versus-`x86` node mix stops shifting month to month.

### ADR-029 — Offering the Lean-Start Variant as a Documented Option

| | |
|---|---|
| **Status** | Accepted |
| **Requirement** | R22 |
| **Pillars** | Cost Optimization · Reliability |
| **Section** | §7.2 The lean-start variant |

**Context.** Innovate Inc. is cost-sensitive at launch but asked for a design ready for rapid growth;
ignoring budget looks tone-deaf, and the cheapest setup risks under-building the foundation growth
needs.

**Options considered.**

| Option | Strengths | Weaknesses | Verdict |
|---|---|---|---|
| Recommend only the fuller design, at ≈$850–900/month, with no cheaper alternative documented | Simplest document; no ambiguity about what to build | Leaves a cost-sensitive founder with no lever to pull if the budget genuinely cannot stretch that far | Rejected — the brief explicitly names cost-effectiveness as a requirement, not an afterthought |
| Recommend the lean-start variant, at ≈$400–450/month, as the default | Matches a very early-stage budget most closely | Bakes in reduced staging fidelity and a shared non-production failure domain from day one, for a saving that stops mattering once revenue exists | Rejected — trades away rehearsal fidelity before there is a budget reason serious enough to demand it |
| Recommend the fuller design, document the lean-start variant as an explicit, costed alternative | Gives Innovate Inc. a real choice with the trade-offs stated, rather than a single number with no context | Requires maintaining and explaining two configurations instead of one | **Chosen** |

**Decision.** We recommend the fuller design at ≈$850–900/month as the default, with the lean-start
variant at ≈$400–450/month documented as a costed alternative.

**Why this is the right choice for Innovate Inc.** Innovate Inc. pays the bill, so it deserves both
numbers, not only the one recommended here. The fuller design costs roughly twice as much because it
keeps the test environment a faithful copy of production and stops a failure in one environment
reaching another — protections that matter most during an incident. While runway is short, the
lean-start variant is a real option, trade-offs stated plainly. The cheapest cuts are nearly free to
reverse; the costliest is merging the test and rehearsal environments, trading away trust in a passing
staging deployment.

**Consequences.**
- *Gains:* A documented, costed choice instead of one prescriptive number.
- *Accepts:* Two configurations to keep consistent, and a shared non-production cluster that removes
  the operational isolation two separate clusters provided.

**Cost impact.** The fuller design costs roughly double the lean-start variant; both are indicative —
see the AWS Pricing Calculator.

**Revisit when.** The business no longer needs to economize this hard, or an enterprise customer
contractually requires a staging environment that mirrors production.
