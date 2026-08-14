## Executive Summary

<!-- EXEC-SUMMARY: written in Phase 12 after all sections exist. Do not fill here. -->

---

## 1. Scope and Objectives

This document designs the cloud infrastructure for Innovate Inc., a small startup building a web
application with a Python/Flask REST API backend, a React single-page application (SPA) frontend,
and a PostgreSQL database. Four characteristics of Innovate Inc.'s situation are the design's
evaluation criteria, not background: the application must grow from a few hundred daily users at
launch to potentially millions, it handles sensitive user data, the engineering team is small with
limited cloud experience, and the team wants to ship continuously through continuous integration
and continuous delivery (CI/CD) from day one.

> **Well-Architected pillars.** Operational Excellence · Security · Cost Optimization

We recommend Amazon Web Services (AWS) as the cloud provider, though Google Cloud Platform (GCP) is
a strong contender — its managed Kubernetes offering demands less day-to-day operation and its
project-based isolation is simpler to stand up than AWS Organizations. AWS earns the recommendation
on the breadth of managed services across the growth curve, the depth of governance tooling
sensitive data will need, and the size of the hiring pool a growing startup can recruit from; the
full comparison is recorded in ADR-001.

The design's guiding principle is managed services first: the hardest constraint here is not the
monthly bill but a small team's operational capacity, and every hour spent operating a
database or a CI runner is an hour not spent building the product. Where a managed AWS service
exists, this document chooses it over a self-hosted equivalent; the reasoning is recorded in
ADR-003.

---

## 2. Architecture Overview — a three-tier design

Innovate Inc.'s application is designed throughout this document as a classic three-tier
architecture — presentation, application, and data — each tier with a distinct relationship to the
virtual private cloud (VPC) containing the workload. The network, compute, and security designs
align to these same three lines.

> **Well-Architected pillars.** Security · Reliability · Performance Efficiency

| Tier | Contains | Runs on | Network placement | Scales by |
|---|---|---|---|---|
| **Presentation tier** | React single-page application, static assets | Amazon S3 origin behind Amazon CloudFront, with AWS WAF at the edge | Outside the VPC entirely — served from CloudFront edge locations | CloudFront; effectively unbounded, no action required |
| **Application tier** | Python/Flask REST API, background workers | Pods on Amazon EKS | **Private — App** subnets; pod IPs from the secondary CIDR. No inbound internet route. | Horizontal Pod Autoscaler and KEDA for pods, Karpenter for nodes |
| **Data tier** | PostgreSQL, and later a cache | Aurora PostgreSQL behind Amazon RDS Proxy | **Private — Data** subnets. No internet route, inbound only from the application tier. | Aurora Serverless v2 capacity units, then read replicas |

Three properties of this mapping recur throughout the document. First, **each tier is reachable
only from the tier above it**, enforced by security-group references rather than Classless
Inter-Domain Routing (CIDR) ranges: the internet reaches the presentation tier through the AWS Web
Application Firewall (WAF); only Amazon CloudFront reaches the application tier's load balancer;
only the application tier reaches the data tier. Second, **the tier boundary is also the security
boundary** — subnet tier, route table, security group, and Kubernetes `NetworkPolicy` align to the
same three lines, one model instead of four, which matters for a team with limited cloud experience
because a simple model does not get misconfigured. Third, **each tier scales independently, by a
different mechanism**: CloudFront's edge network for the presentation tier, the Horizontal Pod
Autoscaler, KEDA, and Karpenter for the application tier, then Aurora Serverless v2 capacity units
and read replicas for the data tier — so a spike in cached-asset requests is absorbed entirely at
the edge, without the application tier noticing.

A three-tier model, not microservices, is the right shape for Innovate Inc. today: the application
is one API and one worker fleet built by a small team, and decomposing it now would trade benefits
this team does not need for distributed-systems problems it lacks the headcount to own. The door
stays open: because each tier scales independently, extracting a piece of it later is a change
within this model, not a rewrite. ADR-002 records the comparison in full.

---

## 3. Design Principles

The following seven principles are the standard every later design decision is checked against;
later chapters cite them by name rather than restate them.

> **Well-Architected pillars.** Operational Excellence · Security · Cost Optimization · Reliability

| Principle | Meaning |
|---|---|
| Managed over self-hosted | Buy back the undifferentiated work; a small team should not run PostgreSQL failover |
| Isolate by account | The strongest boundary AWS enforces, and it costs almost nothing |
| Least privilege, mechanised | Deny-first guardrails, per-workload identities, no long-lived credentials — enforced by policy, not by review |
| Everything as code | Terraform for infrastructure, Git for cluster state; no console changes, so `git log` always answers "what changed" |
| Secure and cost-aware by construction | Security and cost are properties of each decision, not chapters appended at the end |
| Start simple, leave the door open | A day-1 footprint a small team can run; no choice that blocks the 100× version |
| Design for failure, then rehearse it | Multi-AZ by default, tested restores, explicit recovery objectives — an untested plan has an unknown recovery time |

Where two principles conflict — isolation by account against operational simplicity, for instance —
the trade-off is stated explicitly rather than resolved silently; accepted trade-offs are collected
in §9.7 Accepted trade-offs between pillars.

---

## 4. Assumptions

The following assumptions protect the design from being judged against requirements the brief never
stated.

> **Well-Architected pillars.** Operational Excellence · Reliability

1. Primary user base and data residency are US-based at launch, driving `us-east-1`; an EU expansion
   path is reserved but not built.
2. Innovate Inc. has no existing AWS footprint — this is a greenfield landing zone.
3. The engineering team is small and lean, with no dedicated site reliability or security staff —
   typical of a startup at this stage.
4. Source control is GitHub; on GitLab or Bitbucket the CI/CD details differ, not the architecture.
5. Application code is stateless and runs as multiple replicas — Spot capacity and rolling
   deployments both depend on it.
6. Sensitive data means personally identifiable information; no payment card data and no protected
   health information at launch, either of which would add specific controls where relevant.
7. There is no hybrid or on-premises connectivity requirement.
8. A single production region is sufficient at launch; cross-region capacity is a disaster-recovery
   posture, not active-active.
9. The compliance target is SOC 2 readiness and GDPR alignment, not a certified audit at launch.
10. Budget tolerance is roughly four figures monthly at launch, scaling with revenue.
11. The application tolerates abrupt pod termination with graceful shutdown handling — required for
    Spot capacity.
12. Schema changes follow an expand/contract pattern — required for zero-downtime deployment.

Where an assumption proves wrong, the affected section notes it; no part of this design depends on
any of them holding permanently true.

---

## 5. Out of Scope

Innovate Inc.'s design deliberately excludes the following, each for a stated reason.

> **Well-Architected pillars.** Operational Excellence · Cost Optimization

- Application source code and schema design — the application, not its infrastructure.
- End-user authentication implementation — recommended, not designed; the application's concern.
- Marketing and product analytics — orthogonal to this infrastructure.
- Email and notification delivery — a product feature, not infrastructure.
- Mobile clients — the brief specifies a web application only.
- Data warehouse and business intelligence — a future need, not a launch requirement.
- Active-active multi-region deployment — cost and complexity exceed a few hundred users.
- Formal compliance certification — SOC 2 and GDPR readiness are designed for; certification is
  separate.
- Capacity and load testing plans — they validate this design once built, not designing it.
- The Terraform implementation itself — the code follows from this design document.

---

## 6. Requirement Traceability

Every requirement in the client's requirements register maps below to the section that answers it.

| ID | Requirement | Source | Answered in |
|---|---|---|---|
| R1 | Recommend the optimal number and purpose of AWS accounts | Area 1 | §1 Cloud Environment Structure |
| R2 | Justify the account choice against isolation, billing, and management | Area 1 | §1 Cloud Environment Structure |
| R3 | Design the VPC architecture | Area 2 | §2 Network Design |
| R4 | Describe how the network is secured | Area 2 | §2 Network Design; §5 Security and Data Protection |
| R5 | Detail how managed Kubernetes deploys and manages the application | Area 3 | §3 Compute Platform |
| R6 | Approach to node groups | Area 3 | §3 Compute Platform |
| R7 | Approach to scaling | Area 3 | §3 Compute Platform |
| R8 | Approach to resource allocation within the cluster | Area 3 | §3 Compute Platform |
| R9 | Containerization strategy — image building | Area 3 | §3 Compute Platform |
| R10 | Containerization strategy — registry | Area 3 | §3 Compute Platform |
| R11 | Containerization strategy — deployment processes | Area 3 | §3 Compute Platform |
| R12 | Recommend the PostgreSQL service and justify it | Area 4 | §4 Database |
| R13 | Database backups | Area 4 | §4 Database |
| R14 | Database high availability | Area 4 | §4 Database |
| R15 | Database disaster recovery (distinct from HA) | Area 4 | §4 Database |
| R16 | Deliverable lives under `architecture/` | Deliverables | Document location |
| R17 | A README architecture document | Deliverables | Executive Summary + diagrams |
| R18 | At least one High-Level Diagram | Deliverables | Executive Summary + diagrams |
| R19 | Solution is robust | Description | §6 Observability and Operations |
| R20 | Solution is scalable — hundreds → millions of users | Description | §8 Growth Roadmap |
| R21 | Solution is secure — sensitive user data | Description | §5 Security and Data Protection |
| R22 | Solution is cost-effective | Description | §7 Cost Optimization |
| R23 | CI/CD is supported | Description | §3 Compute Platform |
| R24 | Readable by a client with limited cloud experience | Description | Executive Summary + diagrams |
| R25 | Follows best practices | Description | §9 Well-Architected Framework Alignment |
| R26 | Every decision is justified, with alternatives and consequences, in language the client can follow | Engagement standard | Appendix — Decision Records |
| R27 | Design aligns to the AWS Well-Architected Framework, all six pillars | Engagement standard | §9 Well-Architected Framework Alignment |
| R28 | Design is presented as a three-tier architecture (presentation, application, data) | Engagement standard | §0 Scope, Assumptions and Design Principles |

Every row in this table is verified against the assembled document in Phase 13.

---

## Decision Records

The three decisions that frame this design — the cloud provider, the structural model, and the
managed-services default — are recorded below as Architecture Decision Records, using the template
in `decision-register.md`. Each stands on its own, with a plain-language justification a
non-technical reader can follow without the surrounding document.

> **Well-Architected pillars.** Operational Excellence · Security · Cost Optimization · Reliability

### ADR-001 — AWS as the Cloud Provider

| | |
|---|---|
| **Status** | Accepted |
| **Requirement** | R21, R25, R27 |
| **Pillars** | Operational Excellence · Security · Cost Optimization |
| **Section** | §0 Scope, Assumptions and Design Principles |

**Context.** Innovate Inc. must choose between AWS and GCP before any other decision can proceed.
The company has a small engineering team, no existing cloud footprint, handles sensitive data, and
expects to grow from hundreds of users to potentially millions.

**Options considered.**

| Option | Strengths | Weaknesses | Verdict |
|---|---|---|---|
| Google Cloud Platform (GCP) | GKE Autopilot removes most cluster operations; project-based isolation is simpler to stand up than AWS Organizations; Cloud SQL is straightforward to reason about | Narrower catalogue of managed services at the far end of the growth curve; shallower compliance and governance tooling for proving a security posture to enterprise customers; smaller regional hiring pool | Rejected — a strong platform, but AWS pulls further ahead the closer the curve gets to millions of users |
| Multi-cloud from day one | Avoids provider lock-in; each workload could run on whichever provider suits it best | Doubles the operational surface — two identity models, two networking models, two toolsets to learn — for a portability benefit a small team will not exercise for years | Rejected — the cost is certain and immediate; the benefit is hypothetical |
| Amazon Web Services (AWS) | Widest range of managed services across the whole growth curve; deepest governance and compliance tooling; largest hiring pool of engineers who already know the platform | Steeper day-one learning curve than GCP for a team with limited cloud experience; more services to choose correctly among | **Chosen** |

**Decision.** Innovate Inc.'s cloud infrastructure runs on Amazon Web Services (AWS).

**Why this is the right choice for Innovate Inc.** Both providers could run this application well
today; the question is which serves the company best while growing toward millions of users and
more sensitive data. AWS offers more of the security, compliance, and multi-environment tooling a
growing company will need, without ever switching providers to get it. Google's cloud is easier to
start with, but the company would likely outgrow its governance tooling right when it needs to prove
its data is safe to customers and auditors. AWS also widens the hiring pool. Running on both
providers at once was ruled out immediately — it doubles the learning effort for a benefit this
company will not need for years.

**Consequences.**
- *Gains:* AWS's full breadth of managed services and compliance tooling, with no future migration;
  a larger hiring pool.
- *Accepts:* A steeper learning curve than GCP, and a deepening dependency on one vendor.

**Cost impact.** Roughly comparable to GCP at launch; AWS's purchasing options become a cost
advantage as usage grows.

**Revisit when.** A signed contract requires a service or data-residency region only another
provider offers.

### ADR-002 — Three-Tier Architecture Over Microservices or a Monolith

| | |
|---|---|
| **Status** | Accepted |
| **Requirement** | R20, R28 |
| **Pillars** | Reliability · Performance Efficiency · Operational Excellence |
| **Section** | §0.2 Architecture overview — a three-tier design |

**Context.** Innovate Inc. is building one REST API and one single-page application over one
PostgreSQL database, operated by a small engineering team with no dedicated platform staff. The
design must scale from hundreds of users to millions.

**Options considered.**

| Option | Strengths | Weaknesses | Verdict |
|---|---|---|---|
| Single-host monolith | Simplest possible operating model; nothing to coordinate between services | Cannot scale the API and the database independently; a single host is a single point of failure; does not fit a managed-Kubernetes requirement | Rejected — cannot reach the stated growth target |
| Microservices from day one | Each capability scales and deploys independently; matches the target scale's eventual shape | Requires a service mesh, distributed tracing, inter-service authentication, and a release train to coordinate — operational load a small team does not have the headcount to carry | Rejected — solves a scaling problem this team does not have yet, at a cost it cannot afford yet |
| Three-tier (presentation, application, data) | Each tier already scales independently by its own mechanism; matches the team's actual codebase shape; a simple model a small team can hold in its head | Does not decompose the API itself into smaller services, so one large module inside the application tier would still need rethinking later | **Chosen** |

**Decision.** Innovate Inc.'s application is deployed as a three-tier architecture — presentation,
application, and data — with the network and security designs aligned to the same boundaries.

**Why this is the right choice for Innovate Inc.** Innovate Inc.'s product today is one website
talking to one API talking to one database, built by a small team. Splitting that into many small
services now would mean building the safety machinery large companies use to keep many services
talking safely, before a team big enough to own it exists. The three-tier model gives almost all the
scaling benefit — each layer already grows on its own — without that machinery, and it does not
block a later split; that would happen inside the application tier, not as a rebuild.

**Consequences.**
- *Gains:* A model simple enough for a small team to operate correctly; each tier scales
  independently at no microservices-platform cost.
- *Accepts:* The application tier stays one deployable unit, so any API change redeploys the whole
  service.

**Cost impact.** Materially cheaper than microservices — no service mesh or inter-service
authentication layer.

**Revisit when.** A second team is hired to own part of the API and finds itself blocked by one
shared deployable.

### ADR-003 — Managed Services First

| | |
|---|---|
| **Status** | Accepted |
| **Requirement** | R19, R22, R25 |
| **Pillars** | Operational Excellence · Cost Optimization · Reliability |
| **Section** | §0 Scope, Assumptions and Design Principles |

**Context.** Innovate Inc. has a small engineering team and no dedicated database administrator or
security specialist. Every hour spent patching a server or debugging a CI runner is an hour not
spent on the product. This document decides, as a standing default, which side of that trade-off it
takes.

**Options considered.**

| Option | Strengths | Weaknesses | Verdict |
|---|---|---|---|
| Self-hosted on EC2 | Lowest sticker price for compute; full control over every layer | The team owns patching, failover, backup verification, and capacity planning for every component it runs — an open-ended commitment that grows with the product | Rejected — trades a small cash saving for an unbounded time cost |
| Self-hosted in Kubernetes (operators for the database, CI runners, and similar) | One control plane for everything; strong technology if operated well | Durability of the company's most valuable assets depends on the team's depth with Kubernetes operators, which this team does not yet have | Rejected — appropriate for a team with dedicated platform engineers, which this is not |
| Managed AWS services throughout | AWS operates patching, failover, and much of the security baseline; the team spends its time on the product instead of the platform | Higher unit price than the self-hosted equivalent; less portable to another provider | **Chosen** |

**Decision.** Wherever a managed AWS service exists that does the job, this design chooses it,
justified in the chapter where it appears.

**Why this is the right choice for Innovate Inc.** Innovate Inc.'s scarcest resource is not money —
it is the attention of a small team also trying to ship a product. A self-hosted database looks
cheaper on a spreadsheet, but the real cost shows up later, as an engineer's weekend spent recovering
from a failed upgrade instead of shipping a feature. Managed services convert that open-ended risk
into a predictable bill, paid to a provider whose job is keeping that one thing running — costing
more per month, but the difference between shipping continuously and keeping the lights on.

**Consequences.**
- *Gains:* Engineering time goes to the product, not platform operations; undifferentiated failure
  modes become AWS's responsibility.
- *Accepts:* A higher monthly bill than self-hosting, and less control over each component's
  internals.

**Cost impact.** Higher direct spend than self-hosting; cheaper than the fully-loaded engineer time
it would otherwise take.

**Revisit when.** A managed service's bill exceeds the engineer time to run it self-hosted, or a
platform engineer is hired.
