## Well-Architected Framework alignment

The AWS Well-Architected Framework is Amazon Web Services' articulation of what a well-built cloud
workload looks like, organized into six pillars, used here as a design tool applied to decisions
already made in §0 through §8, not a checklist filled in afterward. No design maximizes all six
pillars at once, and naming them forces an honest statement of which one a decision leaned toward
and which one it gave up — the subsections below state, pillar by pillar, what this design already
does and what it deliberately does not do yet.

> **Well-Architected pillars.** All six.

### Operational Excellence

Operational Excellence asks whether the team can run and continuously improve this system without
heroics.

| What this design does | Where |
|---|---|
| Infrastructure and cluster state defined as code; Argo CD reverts console drift automatically | §1 Cloud Environment Structure; §3.9 Deployment — CI/CD and GitOps |
| Every account starts from the same guardrail baseline, provisioned by Control Tower's Account Factory, never by hand | §1 Cloud Environment Structure |
| Small, frequent, reversible deployments — an Argo Rollouts canary, one-commit `git revert` rollback | §3.9 Deployment — CI/CD and GitOps |
| Observability answers "are users being served," not only "is the box up" — request-level metrics, distributed tracing, synthetic canaries | §6.2 The four signals |
| A shared service level objective (SLO) and an automatic error-budget freeze end mid-incident severity arguments | §6.3 Service level objectives |
| Runbooks attached to every page-worthy alert; failure rehearsed in quarterly disaster-recovery (DR) drills and game days, not improvised | §6 Observability and Operations |
| A stable platform node group gives the cluster's own controllers a foundation before Karpenter can scale anything | §3.3 Node strategy |

Not yet addressed: no dedicated on-call rotation or change-advisory process exists at this team
size — DR drills and game days rehearse named failure modes, not proven 24/7 response. The trigger
is a staffed on-call rotation, the same one Architecture Decision Record (ADR)-026 names for the
observability stack.

### Security

Security asks whether data, systems, and people are protected at every layer, not only the
perimeter.

| What this design does | Where |
|---|---|
| No long-lived credential anywhere, human or machine — AWS Identity and Access Management (IAM) Identity Center, Amazon Elastic Kubernetes Service (EKS) Pod Identity, GitHub OpenID Connect (OIDC) scoped to one repository and branch | §1 Cloud Environment Structure; §5 Security and Data Protection |
| A tamper-evident audit trail — organization CloudTrail delivered to a separate, immutable account no workload can write to | §5.4 Detection, audit and logging |
| Defense in depth from the edge to the database — eleven named layers, not a shared assumption that internal traffic is safe | §2.4 Securing the network |
| Automated, shift-left supply-chain security — a software bill of materials, keyless image signing, admission control that refuses an unsigned or wrongly sourced image | §3.8 Container registry |
| Data protected in transit and at rest, classified by sensitivity — customer-managed AWS Key Management Service (KMS) keys per environment and per data class | §5.3 Data protection |
| No direct database access — IAM database authentication through Amazon Relational Database Service (RDS) Proxy, no password stored in a pod | §4.2 Configuration and connection management |
| A skeleton incident-response runbook — detect, triage, contain, eradicate, recover, review | §5 Security and Data Protection |

Not yet addressed: no service mesh with mutual TLS (mTLS) covers east-west traffic, no managed
detection-and-response service goes beyond a weekly finding review, and this document does not
design a penetration-testing program. The mesh trigger is service count growing past a handful; the
detection trigger is a finding volume a weekly review can no longer absorb.

### Reliability

Reliability asks whether the system recovers from failure automatically and meets demand without
guessing capacity.

| What this design does | Where |
|---|---|
| Automatic recovery from failure — liveness and readiness probes, `PodDisruptionBudget`s, Karpenter node replacement, Aurora automatic failover | §3.3 Node strategy; §3.5 Resource allocation within the cluster; §4.5 High availability |
| Recovery procedures are tested, not only documented — monthly automated restore tests, quarterly DR drills with a measured recovery time objective (RTO) | §4.4 Backups; §4.6 Disaster recovery |
| Fault isolation at every layer — one account and one virtual private cloud (VPC) per environment, with no interconnection between them | §1.1 Why multiple accounts; §2 Network Design |
| Horizontal scaling narrows blast radius — three Availability Zones (AZs), multi-replica topology spread, Aurora's six-copy storage | §2.2 VPC and subnet architecture; §3.5 Resource allocation within the cluster; §4.5 High availability |
| Capacity is never guessed — Karpenter provisions a right-sized node in seconds; Aurora Serverless v2 changes capacity with no restart | §3.3 Node strategy; §4.1 Recommendation and alternatives considered |
| Change happens only through automation — GitOps reconciliation, immutable digest promotion, no cluster credential held outside the cluster | §3.9 Deployment — CI/CD and GitOps |
| RDS Proxy holds client connections open through a sub-30-second Aurora failover, degrading service to slow rather than down | §4.2 Configuration and connection management |

Not yet addressed: production runs in a single AWS region with a 60-minute RTO for regional
failure, and DR drills run quarterly, not continuously. The trigger is the business finding a
60-minute RTO unacceptable — the next step is a warm standby, not active-active.

### Performance Efficiency

Performance Efficiency asks whether computing resources are used efficiently as demand and
technology change.

| What this design does | Where |
|---|---|
| Managed, purpose-built services chosen over self-built equivalents by default | §0 Scope, Assumptions and Design Principles |
| The presentation tier scales at the CloudFront edge with no origin-capacity planning at all | §0.2 Architecture overview — a three-tier design |
| Right-sized compute chosen automatically — Karpenter reads each pending pod's actual request and launches a matching instance in seconds | §3.3 Node strategy |
| A serverless, consumption-based data tier — Aurora Serverless v2 changes capacity units in place, no restart, no maintenance window | §4.1 Recommendation and alternatives considered |
| Mechanical sympathy in the connection path — RDS Proxy pools connections instead of every pod overwhelming PostgreSQL directly | §4.2 Configuration and connection management |
| No CPU limit removes Completely Fair Scheduler throttling; a pod using idle capacity on its own node is never punished for it | §3.5 Resource allocation within the cluster |

Not yet addressed: no caching tier exists at launch, no load test has validated this design at
target scale, and read/write splitting stays a manual application concern. The trigger for the
first is p95 latency drifting up with database capacity sustained high, named as the stage-2 signal
in the growth roadmap below.

### Cost Optimization

Cost Optimization asks whether the business gets the value it pays for, measured and attributed,
not merely spent.

| What this design does | Where |
|---|---|
| Cloud financial management as a named, ongoing practice, not a launch-day exercise | §7 Cost Optimization |
| Consumption-based pricing throughout — the Aurora Serverless v2 floor, Spot for stateless compute, scheduled shutdown of development outside working hours | §7 Cost Optimization |
| Managed services over undifferentiated heavy lifting — Aurora instead of a self-managed database a five-person team must operate by hand | §4.1 Recommendation and alternatives considered |
| Expenditure attributed and enforced — a mandatory tag set, AWS Budgets, Cost Anomaly Detection, per-namespace showback | §7 Cost Optimization |
| Right-sizing and the best purchasing option, taken in the right order — Graviton and Karpenter consolidation now, commitment discounts once the baseline stabilizes | §3.3 Node strategy; §7.4 Optimization levers |
| A costed, documented cheaper alternative — the lean-start variant, at ≈$400–450/month against the ≈$850–900/month fuller design, trade-offs stated plainly | §7.2 The lean-start variant |

Not yet addressed: no commitment discount is purchased until the baseline stabilizes, and
per-namespace cost visibility is showback, not enforced chargeback. The trigger is compute spend
holding within roughly 15% of trend for two consecutive quarters.

### Sustainability

Sustainability asks whether this workload's environmental impact is minimized, not treated as
someone else's problem.

| What this design does | Where |
|---|---|
| Graviton-first compute — materially better performance per watt, the same ~20% price/performance advantage Cost Optimization already captures | §3.3 Node strategy |
| Karpenter consolidation and bin-packing — fewer, busier nodes rather than many idle ones | §3.3 Node strategy |
| Scale-to-zero where load allows — KEDA idles background workers, Aurora auto-pauses in development, development shuts down outside working hours | §3.4 Scaling; §7 Cost Optimization |
| Managed services chosen over self-hosted equivalents by default, avoiding infrastructure this team otherwise owns and runs continuously | §0 Scope, Assumptions and Design Principles |
| CloudFront edge caching cuts the bytes moved and the origin work performed per request | §0.2 Architecture overview — a three-tier design |

These are the same three decisions — Graviton, consolidation, scale-to-zero — that serve Cost
Optimization above; saying so is more credible than inventing a separate sustainability program.
Not yet addressed: nothing here measures the workload's carbon footprint, and `us-east-1` was chosen
for the primary user base and data residency, not grid carbon intensity. The trigger is a customer
or investor due-diligence process asking for a figure this design does not yet produce.

### Accepted trade-offs between pillars

Ten trade-offs run through this design. Each is a position it took, stated here rather than left
for a reviewer to infer, and each has a trigger elsewhere in this document — most often an ADR's
own *Revisit when* field — so it does not quietly become permanent by default. The growth roadmap
below is the other half of that mechanism: every trigger named there is also a point on the curve
from a few hundred users to millions, not an open-ended someday.

| Trade-off | Leaned toward | At the expense of | Why, for Innovate Inc. |
|---|---|---|---|
| Seven accounts instead of one | Security, Reliability | Cost Optimization, Operational Excellence | A hard isolation boundary for sensitive data is worth ~$25–60/month per account and centralized access management |
| Three NAT Gateways in production | Reliability | Cost Optimization | An AZ-local NAT failure must not take out a third of the platform; non-production runs one and accepts the risk |
| Three separate EKS control planes | Reliability, Security | Cost Optimization | A shared cluster would undo the account isolation; the lean-start variant is offered as the explicit alternative |
| Aurora over RDS Multi-AZ | Reliability, Performance Efficiency | Cost Optimization | Faster failover, read scaling, and a cross-region DR path that RDS cannot offer without redesign |
| Spot instances for the application tier | Cost Optimization, Sustainability | Reliability | Recovered by On-Demand fallback, `PodDisruptionBudget`s, and a stateless-workloads-only rule |
| Graviton first | Cost Optimization, Sustainability, Performance Efficiency | Operational Excellence | Requires multi-architecture image builds — a one-time pipeline cost |
| Managed Prometheus/Grafana deferred to stage 2 | Cost Optimization | Operational Excellence | In-cluster monitoring is blind during a cluster incident; accepted knowingly while traffic is low |
| Pilot-light DR instead of active-active | Cost Optimization, Operational Excellence | Reliability | A 60-minute recovery time objective is acceptable at this stage; the trigger to change it is named above |
| Deferring a service mesh | Operational Excellence, Cost Optimization | Security | `NetworkPolicy` and TLS cover the current service count; mesh mTLS arrives when the count justifies the operational load |
| Deferring Compute Savings Plans to a stable baseline | Operational Excellence, reduced commitment risk | A larger, sooner Cost Optimization discount | A wasted 12-month commitment against a moving architecture costs more than the ~30% discount it would have captured |

---

## Growth roadmap — from hundreds to millions

The decisions expensive to change later were made for stage 4 on day one: the account structure
(§1.1), the address plan (§2.2), the cluster-per-environment topology (§3 Compute Platform), and the
database engine (§4.1). Everything else is meant to change, and the table below says when — priced,
at each stage, in §7 Cost Optimization.

> **Well-Architected pillars.** Reliability · Performance Efficiency · Cost Optimization ·
> Operational Excellence

| Stage | Scale | What changes | Trigger |
|---|---|---|---|
| **1 — Launch** | a few hundred daily users | The design as written | Day-1 baseline |
| **2 — Traction** | ~10 000 daily users | Aurora reader count grows via Auto Scaling toward the 15-reader ceiling; Amazon ElastiCache added for sessions and hot reads; the Serverless v2 ceiling raised; managed Prometheus and Grafana replace in-cluster monitoring | p95 latency drifting up; database capacity sustained high; monitoring blind spots during an incident |
| **3 — Scale** | ~100 000 daily users | The pre-provisioned secondary pod Classless Inter-Domain Routing (CIDR) block and prefix delegation absorb higher pod density; Shield Advanced and a tightened AWS Web Application Firewall (WAF) rule set; a service mesh if service count grows; Compute Savings Plans purchased against a now-stable baseline; Aurora Global Database begins serving regional reads; read/write splitting moves into the application | Pods approaching the per-AZ CIDR ceiling; Network Address Translation (NAT) bandwidth saturation; distributed denial-of-service (DDoS) exposure; a predictable compute baseline |
| **4 — Millions** | millions of daily users | Multi-region active-active with latency-based routing; partitioning or sharding the write path; a cell-based architecture; a dedicated platform team | Single-region recovery time no longer acceptable to the business; a single writer becomes the ceiling; blast radius of one bad deployment unacceptable |

### What breaks first, and in what order

Traced across the three tiers, the order is not obvious: the presentation tier essentially never
breaks, and everything else does, roughly in this sequence.

1. **Database connections, before database CPU.** Each gunicorn worker in each Flask pod holds its
   own connections, and PostgreSQL allocates a process per connection, so a growing pod fleet
   exhausts connections before it exhausts compute. Signal: RDS Proxy connection and CPU
   utilization climbing together. Already answered by the proxy; the next step is read/write
   splitting.
2. **Pod IP addresses.** Every pod holds a VPC address. Signal: pods stuck `Pending` with
   insufficient-IP events. The answer — prefix delegation and the `100.66.0.0/16` secondary CIDR —
   is already active from day one, so it never has to be retrofitted onto a live cluster.
3. **NAT Gateway throughput and cost.** Signal: NAT data-processing charges climbing faster than
   traffic. Answer: more VPC endpoints, then caching egress-heavy dependencies.
4. **CloudFront cache-hit ratio and origin load.** Signal: origin request rate rising faster than
   user count. Answer: cache-control discipline on API responses and asset versioning — a
   presentation-tier symptom with an application-tier fix.
5. **The single Aurora writer.** Reads scale to fifteen replicas; writes do not scale horizontally
   at all. Signal: write latency and replication lag under sustained load. The answer arrives in
   stages — batch and defer writes, move append-only data out of the primary, then partition or
   shard. This is the hardest ceiling in the design, a schema decision rather than an
   infrastructure one, and it should be considered while the schema is still soft.
6. **The team.** At some point the constraint is not the architecture but the number of people who
   can operate it. Signal: engineering time increasingly spent operating rather than building, or an
   incident only one person can resolve. Answer: a dedicated platform engineer, the same trigger
   ADR-011 and ADR-012 name. This is the honest reason this design defers a service mesh,
   active-active, and Shield Advanced rather than building them now.

None of the stage-2 through stage-4 changes require rebuilding the foundation, because the
foundation was chosen for stage 4 on day one.
