# AWS Well-Architected Framework — alignment guide

**STATUS: NORMATIVE.** The client asked for a design that follows best practices. The AWS
Well-Architected Framework is the industry-standard articulation of what "best practice" means on
AWS, so this deliverable is explicitly structured against it. Every phase agent uses this file for
two things:

1. **Tagging** — attributing each design decision to the pillar(s) it serves.
2. **Coverage** — making sure the pillar's actual demands are answered somewhere, so the dedicated
   Well-Architected chapter (Phase 09) has real content to point at rather than assertions.

---

## 1. The six pillars, and what each one demands of *this* design

Do not write generic pillar descriptions into the deliverable. These are the pillar demands as they
apply to Innovate Inc. specifically — a five-person startup, sensitive user data, a
hundreds-to-millions growth curve, CI/CD from day one.

### OPS — Operational Excellence

*Run and monitor systems, and continuously improve processes.*

| What the pillar demands here | Where this design answers it |
|---|---|
| Infrastructure and cluster state defined as code, no console changes | §1 (Terraform, Control Tower), §3 (GitOps) |
| Small, frequent, reversible deployments | §3 (canary via Argo Rollouts, `git revert` rollback) |
| Observability that answers "are users being served", not just "is the box up" | §6 (SLOs, RED metrics, traces, synthetics) |
| Runbooks attached to every alert; failures rehearsed, not improvised | §5 (incident response), §4 (DR drills) |
| Operational burden sized to a five-person team | Everywhere — this is the binding constraint |

### SEC — Security

*Protect data, systems, and assets.*

| What the pillar demands here | Where this design answers it |
|---|---|
| Strong identity foundation; no long-lived credentials anywhere | §1 (Identity Center), §5 (Pod Identity, OIDC) |
| Traceability — immutable, tamper-evident audit trail | §5 (org CloudTrail → Log Archive with Object Lock) |
| Security at every layer, not just the perimeter | §2 (network layers), §5 (defence-in-depth table) |
| Automated security best practices, shift-left | §3 (pipeline gates, image signing, admission control) |
| Protect data in transit and at rest, classified by sensitivity | §5 (data classification, customer-managed KMS keys) |
| Keep people away from data | §4 (no direct DB access, IAM DB auth), §1 (time-boxed access) |
| Prepare for security events | §5 (incident response runbook, containment steps) |

### REL — Reliability

*Recover from failure, meet demand, mitigate disruption.*

| What the pillar demands here | Where this design answers it |
|---|---|
| Automatic recovery from failure | §3 (probes, PDBs, Karpenter replacement), §4 (Aurora failover) |
| Test recovery procedures — not just have them | §4 (monthly restore tests, quarterly DR drills) |
| Scale horizontally to reduce blast radius | §3 (multi-replica, multi-AZ, topology spread) |
| Stop guessing capacity | §3 (Karpenter, HPA/KEDA), §4 (Serverless v2) |
| Manage change through automation | §3 (GitOps, immutable digests) |
| Fault isolation boundaries | §1 (account per environment), §2 (3 AZs), §9 (cells, later) |

### PERF — Performance Efficiency

*Use computing resources efficiently as demand and technology change.*

| What the pillar demands here | Where this design answers it |
|---|---|
| Use advanced/managed technologies rather than building them | Managed services first, stated in §0 principles |
| Go global in minutes where it helps | §2 (CloudFront edge for the presentation tier) |
| Use serverless and right-sized compute | §4 (Aurora Serverless v2), §3 (Karpenter right-sizing, Graviton) |
| Experiment more often — cheap to try an instance family | §3 (Karpenter's broad family list, VPA recommendations) |
| Mechanical sympathy — pick the tool that fits the access pattern | §4 (relational store, RDS Proxy, read replicas, cache at stage 2) |

### COST — Cost Optimization

*Deliver business value at the lowest price point.*

| What the pillar demands here | Where this design answers it |
|---|---|
| Cloud financial management as a practice, with an owner | §8 (FinOps governance) |
| Adopt a consumption model; pay for what you use | §8 (Serverless v2 floor, Spot, dev shutdown) |
| Measure overall efficiency — cost per unit of value | §8 (unit economics, cost per user) |
| Stop spending on undifferentiated heavy lifting | §4 (managed database over self-managed) |
| Analyse and attribute expenditure | §8 (mandatory tags, per-namespace showback) |
| Right-size and use the best purchasing option | §8 (Graviton, Spot, Savings Plans at stage 3) |

### SUS — Sustainability

*Minimise the environmental impact of running cloud workloads.*

| What the pillar demands here | Where this design answers it |
|---|---|
| Maximise utilisation — fewer, busier resources | §3 (Karpenter consolidation and bin-packing) |
| Adopt more efficient hardware as it appears | §3 (Graviton — materially better performance per watt) |
| Scale infrastructure with actual user load | §3 (HPA/KEDA scale-to-zero for workers), §8 (dev shutdown) |
| Use managed services that share capacity across customers | Managed services first |
| Reduce the downstream impact of the workload | §3 (CloudFront edge caching cuts origin work and bytes moved) |

> **Note for agents.** Sustainability is the pillar most often skipped or padded with platitudes.
> This design has three genuine sustainability stories — Graviton, Karpenter consolidation, and
> scale-to-zero — and they are the *same* decisions that serve Cost Optimization. Say that
> explicitly; a pillar alignment that admits the overlap is more credible than one that invents a
> separate sustainability programme.

---

## 2. Tagging convention (used in every draft)

Two mechanisms, both mandatory.

### 2.1 Section-level attribution

Every `##` section of a draft ends its opening paragraph with a pillar line, exactly this format:

```markdown
> **Well-Architected pillars.** Security · Reliability · Cost Optimization
```

List only pillars the section *substantively* serves — two to four. Tagging all six is the same as
tagging none.

### 2.2 Decision-level attribution

Every Architecture Decision Record carries a `Pillars` row in its metadata table (see
[`decision-register.md`](decision-register.md)). Use the short names below, separated by ` · `:

`Operational Excellence` · `Security` · `Reliability` · `Performance Efficiency` ·
`Cost Optimization` · `Sustainability`

Write the full pillar name, never the `OPS`/`SEC`/`REL` abbreviations — those are for this file only.

---

## 3. Pillar trade-offs this design knowingly makes

The Well-Architected Framework is explicit that pillars pull against each other and that a good
architecture states which way it leaned and why. **Phase 09 must present these as a table.** Every
content phase should flag any additional trade-off it discovers so Phase 09 can pick it up.

| Trade-off | Leaned toward | At the expense of | Why, for Innovate Inc. |
|---|---|---|---|
| Seven accounts instead of one | Security, Reliability | Cost Optimization, Operational Excellence | A hard isolation boundary for sensitive data is worth ~$25–60/month per account and centralised access management |
| Three NAT Gateways in production | Reliability | Cost Optimization | An AZ-local NAT failure must not take out a third of the platform; non-production runs one and accepts the risk |
| Three separate EKS control planes | Reliability, Security | Cost Optimization | A shared cluster would undo the account isolation; the lean-start variant is offered as the explicit alternative |
| Aurora over RDS Multi-AZ | Reliability, Performance Efficiency | Cost Optimization | Faster failover, read scaling, and a cross-region DR path that RDS cannot offer without redesign |
| Spot instances for the application tier | Cost Optimization, Sustainability | Reliability | Recovered by On-Demand fallback, PodDisruptionBudgets, and a stateless-workloads-only rule |
| Graviton first | Cost Optimization, Sustainability, Performance Efficiency | Operational Excellence | Requires multi-architecture image builds — a one-time pipeline cost |
| Managed Prometheus/Grafana deferred to stage 2 | Cost Optimization | Operational Excellence | In-cluster monitoring is blind during a cluster incident; accepted knowingly while traffic is low |
| Pilot-light DR instead of active-active | Cost Optimization, Operational Excellence | Reliability | A 60-minute recovery time objective is acceptable at this stage; the trigger to change it is named in §9 |
| Deferring a service mesh | Operational Excellence, Cost Optimization | Security | NetworkPolicy and TLS cover the current service count; mesh mTLS arrives when the count justifies the operational load |

---

## 4. What Phase 09 produces from this file

A chapter with one subsection per pillar. Each subsection must contain:

1. **One sentence** on what the pillar asks (not a paragraph of framework quotation).
2. **A table** of the concrete design decisions in this document that serve it, each with a section
   reference — drawn from §1 above, not invented.
3. **One honest gap or deferral** — something the design does not yet do for that pillar, and the
   trigger for doing it. A pillar section with no gap reads as marketing.

Plus §10.7, the trade-off table from §3 above.

**Do not** reproduce the Well-Architected Framework's own documentation, quote its design principles
verbatim, or list the review questions. The chapter's value is the mapping to *this* design, and
nothing else.
