## Why managed Kubernetes, and why EKS

Innovate Inc.'s **application tier** — the Python/Flask REST API and its background workers,
introduced in §0.2 Architecture overview — runs in full on Amazon Elastic Kubernetes Service (EKS)
inside this section: the Private — App subnets of the Virtual Private Cloud (VPC) in §2.2 VPC and
subnet architecture, reachable only from the Application Load Balancer (ALB), with pod addresses from
the secondary Classless Inter-Domain Routing (CIDR) block described there. Its scaling mechanism,
covered later here, is distinct from the CloudFront edge above and the Aurora Serverless v2 capacity
below.

> **Well-Architected pillars.** Operational Excellence · Reliability

The brief specifies managed Kubernetes, so the live question is how, not whether. EKS removes the
highest-consequence operational work from the team's plate: control-plane availability across three
Availability Zones (AZs), `etcd` backups, control-plane patching, and TLS certificate rotation. It
does not remove worker-node management, add-on version currency, or workload reliability — those
remain the team's job, designed below. Kubernetes is more operational surface than a small team
strictly needs for a few hundred daily users; the reason to accept it now is that migrating later
costs far more than learning it today.

AWS also offers **EKS Auto Mode**, managing nodes, storage, and load-balancer integration with less
configuration. This design specifies node groups, add-ons, and scaling explicitly instead: an
explicit design can be simplified into Auto Mode later, but the reverse cannot happen. ADR-011
records the full comparison against Amazon Elastic Container Service (ECS) on AWS Fargate and
unmanaged Amazon Elastic Compute Cloud (EC2).

---

## Cluster topology

Innovate Inc. runs one Amazon EKS cluster per environment account, never a shared cluster with
per-environment namespaces. The table below lists all four clusters, including the pilot-light
disaster-recovery cluster carried in production's second region.

> **Well-Architected pillars.** Security · Reliability · Operational Excellence

| Cluster | Account | Region | Purpose |
|---|---|---|---|
| `innovate-dev-eks-use1` | `innovate-dev` | us-east-1 | Development — loosest guardrails, synthetic data only |
| `innovate-stg-eks-use1` | `innovate-staging` | us-east-1 | Pre-production mirror of production's topology, reduced size |
| `innovate-prod-eks-use1` | `innovate-prod` | us-east-1 | Production |
| `innovate-prod-eks-usw2` | `innovate-prod` | us-west-2 | Pilot-light disaster recovery — stood up by the same Terraform apply that rebuilds the region during a failover (§4.6 Disaster recovery), not continuously running |

A shared cluster with per-environment namespaces looks cheaper — one control plane instead of four —
but it reintroduces the shared blast radius separate AWS accounts (§1.1 Why multiple accounts) were
built to remove: a bad node-group change or add-on upgrade could degrade every environment at once.
One cluster per account keeps that boundary intact at the compute layer too, at the cost of a small,
fixed control-plane fee per environment (§7 Cost Optimization).

Each control plane runs a private VPC endpoint plus a public endpoint restricted to a narrow, named
set of source addresses (§2.4 Securing the network); secrets are envelope-encrypted with a
customer-managed AWS Key Management Service (KMS) key; and all five control-plane log types ship to
CloudWatch and on to `innovate-log-archive`. Innovate Inc. tracks the latest EKS-supported Kubernetes
minor version, staying at that version or one behind, upgrading within thirty days of general
availability, always dev then staging then production — never a specific version number, stale before
a reader opened it.

No engineer authenticates to a cluster's API with a long-lived credential. EKS **access entries** map
AWS Identity and Access Management (IAM) Identity Center permission sets directly to Kubernetes
role-based access control, so a developer's laptop reaches even the private endpoint through the same
single sign-on session used everywhere else (§1 Cloud Environment Structure) — no `aws-auth`
`ConfigMap` to hand-edit, no kubeconfig to leak, and access revoked in Identity Center takes effect
immediately, everywhere.

---

## Node strategy

Application capacity in every environment comes from two distinct mechanisms, and the reason there
are two rather than one is a real technical constraint, not a stylistic choice.

> **Well-Architected pillars.** Cost Optimization · Reliability · Performance Efficiency · Sustainability

A small **EKS Managed Node Group**, `innovate-<env>-mng-platform`, runs two to four `m7g.large`
Graviton instances On-Demand, spread across three AZs and tainted `dedicated=platform:NoSchedule` so
no application pod lands there by accident. It hosts CoreDNS, the Karpenter controller, the AWS Load
Balancer Controller, and the logging and metrics agents. This tier exists because **Karpenter cannot
provision the node it runs on**: something must be reliably present first, must not be reclaimed on
two minutes' notice like Spot capacity, and must not be evicted by the consolidation logic it runs.

**Karpenter** provisions every application-tier node. Unlike the Cluster Autoscaler, which scales
pre-defined, fixed-shape node groups up and down, Karpenter watches for pods stuck `Pending`, reads
what each requests, and launches a right-sized instance from a broad instance-family list within
seconds — no pre-committed instance shape to get wrong months in advance. For a workload going from
hundreds of users to potentially millions, with a still-unknown final shape, not guessing the
instance type ahead of time is the point.

| NodePool | Architecture | Capacity type | Instance families | Weight | Used for |
|---|---|---|---|---|---|
| `app-arm64-spot` | arm64 (Graviton) | Spot | `m7g`, `c7g`, `r7g`, `m8g`, `c8g` | 100 | All application workloads, preferred |
| `app-amd64-spot` | amd64 | Spot | `m7i`, `c7i`, `m7a`, `c7a` | 50 | Fallback when arm64 Spot is unavailable, or an image is x86-only |
| `app-ondemand` | Mixed | On-Demand | Same families as the Spot pools | 10 | Last-resort fallback so a Spot squeeze never causes an outage |

**Graviton first.** `arm64` instances run roughly 20% better on price/performance than the equivalent
`amd64` instance for typical web and API workloads, and Python/Flask is architecture-agnostic — the
only requirement it adds is a multi-architecture build, covered later in this chapter (§3.8 Container
registry, §3.9 Deployment). The `amd64` `NodePool` is a fallback for the rare dependency that is
x86-only; never the default.

**Spot for every stateless workload.** Spot capacity costs 70–90% less than On-Demand, in exchange for
AWS being able to reclaim it on two minutes' notice. Karpenter subscribes to an Amazon Simple Queue
Service (SQS) interruption queue fed by Amazon EventBridge rebalance and interruption notifications;
the moment a notice arrives, Karpenter cordons that node, drains it, and starts provisioning a
replacement, while `PodDisruptionBudget`s (below) keep enough replicas serving throughout. Spreading
capacity across five instance families per `NodePool` also reduces the odds one family's capacity
crunch interrupts a large share of the fleet. The `app-ondemand` `NodePool`'s low weight means it is
used only when Spot capacity genuinely is not available anywhere Karpenter looked. The rule:
**stateless workloads run on Spot; anything holding state, and the platform tier itself, runs
On-Demand.**

> **Trade-off.** Spot means a pod can be killed on someone else's schedule, not the application's.
> Every application deployment must handle `SIGTERM` gracefully within its termination grace period,
> treat every request as safely retryable, and hold no session state in memory — real engineering
> discipline the team carries in exchange for the discount, not a free lunch.

**Node lifecycle.** Karpenter continuously bin-packs and removes underused nodes
(`consolidationPolicy: WhenEmptyOrUnderutilized`, `consolidateAfter: 1m`), and `expireAfter: 720h`
forces every node to be replaced within 30 days regardless of utilization — keeping the fleet patched
without a separate patching process. Nodes run Bottlerocket or the EKS-optimized Amazon Machine Image
(AMI), replaced rather than patched in place.

---

## Scaling

Four distinct mechanisms scale different parts of the application tier, at different layers, on
different signals — collapsing them into one story is the mistake this section is graded against.

> **Well-Architected pillars.** Reliability · Performance Efficiency · Cost Optimization

| Mechanism | Scales | Signal | Used for |
|---|---|---|---|
| Horizontal Pod Autoscaler (HPA) | Pod replica count | CPU at 65% plus a requests-per-pod custom metric | The Flask API |
| KEDA | Pod replica count, including scale-to-zero | An external event source — Amazon SQS queue depth | Background Celery workers |
| Karpenter | Nodes | Pending pods that cannot be scheduled | All application capacity |
| Vertical Pod Autoscaler (VPA), **recommender mode only** | Recommends requests and limits | Historical usage | Right-sizing advice for humans; never auto-applied alongside HPA on the same metric |

**The chain, traced in sequence:** traffic rises, the HPA adds Flask API replicas against CPU and the
requests-per-pod metric, those new pods go `Pending` because no node has room, Karpenter reads their
requirements and provisions a right-sized node in well under a minute, and the pods schedule onto it.
Scale-down runs in reverse: the HPA removes replicas as load drops, and Karpenter's consolidation
removes the now-underused node behind them.

**Burst headroom.** Low-priority `overprovision` pause pods hold a standing reservation that real
workloads preempt instantly, so the first burst of a traffic spike does not wait for a new node to
boot. The cost is explicit: Innovate Inc. pays for idle capacity, continuously, to buy that latency
back.

The presentation and data tiers scale by their own mechanisms, one sentence each: CloudFront and S3
absorb the presentation tier's load without any action from this design, and Aurora PostgreSQL scales
through Serverless v2 capacity units and read replicas (§4 Database). The ALB scales itself, though a
step-change launch — a press mention, a marketing push — benefits from pre-warming it ahead of time.

**Where the limits are.** Aurora's connection ceiling — mitigated but not removed by Amazon Relational
Database Service (RDS) Proxy — third-party API rate limits, and Network Address Translation (NAT)
Gateway bandwidth are the first ceilings this design meets, each with its trigger and remedy named in
§8.2 What breaks first, and in what order.

---

## Resource allocation within the cluster

Resource allocation is distinct from scaling: scaling decides how many pods and nodes exist, while
this decides how much of each node's CPU and memory any single pod gets, and what happens when
demand exceeds supply.

> **Well-Architected pillars.** Reliability · Performance Efficiency · Operational Excellence

**Requests and limits.** Every workload sets a CPU **request** — the number the scheduler and
Karpenter size against — and no CPU **limit**. A CPU limit invokes the kernel's Completely Fair
Scheduler (CFS) throttling the instant usage crosses it, even on an otherwise idle node; the pod is
doing useful work and is punished for it, surfacing as unexplained p99 latency with no obvious cause.
The CPU request alone already tells the scheduler and Karpenter how much capacity to reserve, so
removing the limit costs nothing on placement. Memory is handled differently: every workload sets its
memory **request equal to its limit**, because memory cannot be reclaimed the way CPU time can — a
fixed ceiling keeps one pod's memory growth from starving its neighbors. The Flask API's baseline is
`250m` CPU request, `512Mi` memory request and limit, three replicas minimum in production; starting
points, refined by VPA recommendations and load testing.

This places pods in the `Burstable` quality-of-service (QoS) class, not `Guaranteed` — `Guaranteed`
requires a matching limit for every resource including CPU, exactly the throttling this design
avoids. That is not a downgrade: a `Burstable` pod whose memory stays within its request — guaranteed
by the request-equals-limit setting — ranks well below any pod exceeding its request when Kubernetes
reclaims under memory pressure, and its CPU is never throttled while spare cycles exist. Nothing here
intentionally runs `BestEffort`; every namespace's `LimitRange` caps how large an unset request or
limit can default to, so a pod without explicit values still lands in `Burstable`, never in
`BestEffort` — the class that would be reclaimed first under pressure.

| Namespace | Purpose |
|---|---|
| `innovate-api` | Flask REST API pods |
| `innovate-jobs` | Celery background workers and scheduled jobs |
| `platform-argocd` | Argo CD GitOps controller |
| `platform-ingress` | AWS Load Balancer Controller, ExternalDNS |
| `platform-monitoring` | Metrics, logging, and alerting agents |
| `platform-karpenter` | Karpenter controller |
| `platform-secrets` | External Secrets Operator |
| `platform-certs` | cert-manager |

Each namespace carries a `ResourceQuota` capping total CPU, memory, pod count, and
persistent-volume-claim (PVC) count, so one runaway deployment cannot consume the cluster's whole
budget; a `LimitRange` supplies the default request and ceiling a pod needs to be admitted at all.

A `PriorityClass` ladder — `platform-critical` > `app-high` > `app-default` > `overprovision` —
decides who yields first under contention: platform pods preempt application pods before the
burst-headroom pause pods, which always give way first.

**Spread and disruption.** `topologySpreadConstraints` spread each `Deployment`'s replicas evenly
across all three AZs, so losing one AZ costs at most a third of capacity, not half. A
`PodDisruptionBudget` on every `Deployment` keeps voluntary disruption — node consolidation, an
add-on upgrade, Spot reclamation — from ever draining a service to zero; long-running `innovate-jobs`
tasks are exempted from consolidation until they finish rather than being cut off mid-task.

**Probes and graceful shutdown** make all of the above invisible to a user: liveness and readiness
checks restart a hung pod and pull one that cannot yet serve traffic (for example, a lost database
connection) out of rotation before it receives a request, and a termination grace period lets
in-flight requests finish before a pod actually stops. The result is that a Spot interruption, a
rolling deploy, and a consolidation event all look the same to a user — nothing.

---

## Cluster add-ons and platform services

Every cluster runs the same fixed set of add-ons, split into two groups by how each is upgraded:
those Amazon manages as EKS add-ons, and those the platform team manages itself through GitOps,
matching the deployment model the rest of this design uses everywhere else.

> **Well-Architected pillars.** Operational Excellence · Security

| Component | Purpose | Managed how |
|---|---|---|
| VPC Container Network Interface (CNI) | Pod networking; prefix delegation, custom networking, `NetworkPolicy` enforcement | EKS-managed add-on |
| CoreDNS | Cluster DNS | EKS-managed add-on |
| kube-proxy | Service networking | EKS-managed add-on |
| Amazon Elastic Block Store (EBS) Container Storage Interface (CSI) driver | Persistent volume provisioning | EKS-managed add-on |
| Pod Identity Agent | Vends per-pod IAM credentials | EKS-managed add-on |
| CloudWatch Observability | Ships node and pod metrics and logs | EKS-managed add-on |
| Karpenter | Node provisioning | Helm chart via Argo CD |
| AWS Load Balancer Controller | Provisions the ALB and target groups from Kubernetes `Ingress` objects | Helm chart via Argo CD |
| ExternalDNS | Keeps Route 53 records in sync with cluster services | Helm chart via Argo CD |
| External Secrets Operator | Syncs AWS Secrets Manager into Kubernetes `Secret`s | Helm chart via Argo CD |
| cert-manager | Issues and rotates in-cluster TLS certificates | Helm chart via Argo CD |
| metrics-server | Serves the resource-metrics API the HPA reads | Helm chart via Argo CD |
| kube-prometheus-stack (day 1) / Amazon Managed Prometheus and Grafana (at scale) | Metrics collection and dashboards | Helm chart via Argo CD |
| Fluent Bit | Ships logs to CloudWatch | Helm chart via Argo CD |
| Argo CD | GitOps continuous delivery controller | Bootstrapped once; manages itself thereafter |
| Argo Rollouts | Progressive delivery — canary releases | Helm chart via Argo CD |
| KEDA | Event-driven autoscaling for the worker deployment | Helm chart via Argo CD |

Add-on versions are pinned in git and upgraded deliberately through the same dev-then-staging-then-
production sequence as everything else in this design — never left to float to "latest," which is how
a routine upgrade becomes an incident.

---

## Workload isolation and multi-tenancy

Multiple workloads share every cluster, so the last layer of this section is what stops one from
reaching or resembling another.

> **Well-Architected pillars.** Security · Reliability

Pod Security Admission enforces the `restricted` profile on every workload namespace: no root user,
no privilege escalation, a read-only root filesystem, every Linux capability dropped, and the default
`seccomp` profile — a non-compliant pod is not admitted, not merely flagged. Kubernetes
`NetworkPolicy`, default-deny for ingress and egress per namespace, means a pod reaches only what an
explicit policy names, so a compromised container has no default path into another namespace. EKS
Pod Identity gives each service account its own IAM role, so a compromised pod holds only that
workload's AWS permissions. The platform node group's taint keeps every application pod off the nodes
running cluster-critical controllers. §5 Security and Data Protection covers the wider security
posture these controls sit inside.

---

## Decision Records

The four decisions below carry the full argument for how Innovate Inc.'s application tier is built:
whether to run Amazon EKS at all, how node capacity is provisioned, why Graviton and Spot lead the
application tier's compute mix, and how CPU and memory are apportioned to each pod. Each stands on
its own, with a plain-language justification a non-technical reader can follow without the rest of
this document.

> **Well-Architected pillars.** Operational Excellence · Reliability · Cost Optimization · Performance Efficiency

### ADR-011 — Amazon EKS as the Compute Platform

| | |
|---|---|
| **Status** | Accepted |
| **Requirement** | R5, R19 |
| **Pillars** | Operational Excellence · Reliability · Performance Efficiency |
| **Section** | §3 Compute Platform |

**Context.** Innovate Inc.'s brief asks for managed Kubernetes; the company expects to grow to
millions of users, with a small engineering team and no platform team.

**Options considered.**

| Option | Strengths | Weaknesses | Verdict |
|---|---|---|---|
| Amazon ECS on AWS Fargate | No cluster or node management at all; fastest path to a running container; a smaller learning curve for a small team | Orchestration locks to AWS-specific APIs and tooling; Kubernetes' larger ecosystem of ready-made components and the wider hiring pool of engineers who already know it are unavailable | Rejected — genuinely less operational work today, but trades away exactly what the brief asked for and what the five-year horizon rewards |
| EC2 instances behind a load balancer, no orchestrator | Full control, simplest mental model | The team hand-builds scheduling, health-checked replacement, and rolling deploys as scripts and runbooks — everything an orchestrator already provides | Rejected — reinvents an orchestrator rather than adopting one |
| EKS Auto Mode | AWS manages node provisioning, storage classes, and load-balancer integration; meaningfully less operational work than a self-specified cluster | Trades away the ability to choose Karpenter's exact `NodePool` shape, the Graviton and Spot mix, and add-on versions this design specifies deliberately | Rejected for day 1 — the natural simplification once the team wants to hand back that control, not the starting point for a document meant to show the reasoning |
| Amazon EKS, self-specified node groups and `NodePool`s | The managed control plane removes the highest-consequence operational burden — `etcd`, API server availability, certificate rotation; the team keeps full control over node shape, scaling, and add-on versions; Kubernetes' ecosystem and hiring pool are the largest available | More operational surface than Fargate or Auto Mode — worker nodes, add-ons, and `NodePool`s stay the team's responsibility | **Chosen** |

**Decision.** Innovate Inc. runs Amazon EKS, one cluster per environment account, rather than Amazon
ECS on Fargate, EKS Auto Mode, or unmanaged EC2.

**Why this is the right choice for Innovate Inc.** A fully automated platform, Amazon ECS on AWS
Fargate, is less work to run today — worth saying plainly rather than pretending Kubernetes, the
system that runs and restarts an application's containers, is the only sensible choice for five
people. The reason to accept the extra work is what happens after launch succeeds: most cloud
engineers already know Kubernetes, and it does not lock deployment tooling to one provider the way
Fargate does. EKS, Amazon's managed version of Kubernetes, hands back the hardest part — keeping the
control plane that runs it patched — while leaving Innovate Inc. free to decide how nodes and scaling
work. A more automated Auto Mode option would make those decisions for the team instead, hiding the
reasoning this document exists to show.

**Consequences.**
- *Gains:* A managed, multi-AZ control plane with automatic patching; the wider Kubernetes ecosystem
  and hiring pool.
- *Accepts:* More operational surface than Fargate or Auto Mode — worker nodes and add-ons stay the
  team's job.

**Cost impact.** Indicative EKS control-plane cost is ~$220/month across three environments (AWS
Pricing Calculator).

**Revisit when.** A dedicated platform engineer is hired to own Kubernetes operations full-time.

### ADR-012 — Platform Node Group Plus Karpenter Over Cluster Autoscaler

| | |
|---|---|
| **Status** | Accepted |
| **Requirement** | R6, R20 |
| **Pillars** | Cost Optimization · Reliability · Performance Efficiency |
| **Section** | §3.3 Node strategy |

**Context.** Every EKS cluster needs a stable place for its own controllers before any autoscaler can
act, for a workload whose shape at millions-of-users scale is still unknown.

**Options considered.**

| Option | Strengths | Weaknesses | Verdict |
|---|---|---|---|
| Cluster Autoscaler with fixed-shape managed node groups | Mature, widely understood, works with any node group | Scales existing, pre-defined node groups up and down rather than choosing an instance type per pending pod's actual needs — someone has to predict and pre-provision the right shapes | Rejected — a poor fit for a workload whose final shape is still unknown |
| Karpenter only, no managed node group | One provisioning mechanism, simplest mental model | Karpenter's own controller, CoreDNS, and the AWS Load Balancer Controller run on the same Karpenter-provisioned capacity Karpenter manages — a chicken-and-egg problem, and no stable, non-Spot home for cluster-critical components | Rejected — removes the one stable foundation the cluster needs |
| A platform-only managed node group, Cluster Autoscaler for everything else | Keeps the mature, conventional autoscaler | Still pre-commits application capacity to fixed instance shapes, and does not solve app-tier bin-packing or right-sizing | Rejected — the same shape-prediction problem, narrower in scope only |
| A small EKS managed node group for the platform tier, Karpenter for all application capacity | The platform tier gets a stable, non-Spot, non-Karpenter-managed home; Karpenter reads each pending pod's actual request and provisions a right-sized instance from a broad family list in seconds | Two provisioning mechanisms to understand instead of one | **Chosen** |

**Decision.** Innovate Inc. runs a small EKS Managed Node Group, `innovate-<env>-mng-platform`,
hosting CoreDNS, the Karpenter controller, the AWS Load Balancer Controller, and the logging and
metrics agents. Every application pod's capacity comes from Karpenter, never a fixed-shape node
group.

**Why this is the right choice for Innovate Inc.** Something in the cluster has to be reliably running
before any automatic scaling can happen — Karpenter cannot build the computer it runs on. A small,
always-on group of machines gives the cluster's own software a stable home, never shut down while
trying to save money. Everything that runs the product, by contrast, is provisioned by Karpenter,
which picks the right size machine automatically the moment software needs it — rather than the team
guessing months ahead which sizes a product with millions of future users will need. That matters
most during the growth this design is built for.

**Consequences.**
- *Gains:* A stable home for cluster-critical controllers; automatic right-sized provisioning.
- *Accepts:* Two provisioning mechanisms instead of one; the platform group runs regardless of load.

**Cost impact.** The platform node group is a small, fixed cost per environment; Karpenter keeps the
application fleet sized to actual demand.

**Revisit when.** The platform tier's controllers outgrow four `m7g.large` instances, or Karpenter
gains the ability to safely provision and protect its own hosting node.

### ADR-013 — Graviton-First Spot for the Application Tier

| | |
|---|---|
| **Status** | Accepted |
| **Requirement** | R6, R22 |
| **Pillars** | Cost Optimization · Sustainability · Performance Efficiency |
| **Section** | §3.3 Node strategy |

**Context.** The application tier must scale from hundreds to millions of users against real budget
constraints, running an entirely stateless fleet of API and worker replicas.

**Options considered.**

| Option | Strengths | Weaknesses | Verdict |
|---|---|---|---|
| `amd64` (x86) On-Demand only | Universally compatible; no multi-architecture build to maintain; unaffected by interruption | The highest per-vCPU price of any option here, for compute a stateless workload does not need dedicated to it | Rejected — pays the most for the least |
| `arm64` (Graviton) On-Demand | Roughly 20% better price/performance than equivalent x86 On-Demand; no interruption risk | Leaves the much larger Spot discount unused for a workload that tolerates interruption well | Rejected — On-Demand pricing is a far smaller lever than Spot for a stateless fleet |
| `amd64` Spot only | 70–90% cheaper than On-Demand | Does not combine with Graviton's per-instance efficiency gain | Rejected — leaves a second, compounding discount on the table |
| Graviton-first Spot, `amd64` Spot fallback, On-Demand last resort | Combines Graviton's ~20% price/performance gain with Spot's 70–90% discount for the large majority of capacity, while a weighted On-Demand pool guarantees capacity never actually runs out | Requires multi-architecture container images and an application that tolerates abrupt termination | **Chosen** |

**Decision.** Application capacity is Karpenter `NodePool`s weighted toward Graviton (`arm64`) Spot
first, `amd64` Spot second, and a mixed-architecture On-Demand pool last.

**Why this is the right choice for Innovate Inc.** Two discounts stack here. Graviton, Amazon's own
computer chip design, costs roughly a fifth less than the common alternative, and "Spot" capacity —
AWS's spare computers, offered cheap because AWS can reclaim them on two minutes' notice — costs up
to 70–90% less again. Innovate Inc.'s application is built so any single copy can be stopped and
restarted elsewhere without a customer noticing, exactly the condition that makes Spot safe for
production traffic and not only testing. The On-Demand pool is a backstop: if Spot capacity ever runs
short, the cluster pays full price rather than falling over. This is the largest lever here for
keeping the bill low as traffic grows a hundredfold.

**Consequences.**
- *Gains:* Materially lower compute cost than On-Demand x86, with an automatic fallback under load.
- *Accepts:* Pods can be reclaimed on two minutes' notice, requiring graceful shutdown, idempotent
  requests, and a one-time multi-architecture build cost.

**Cost impact.** Indicative worker-node spend is ~$120/month across all environments (AWS Pricing
Calculator); Graviton and Spot are why that figure is not several times higher.

**Revisit when.** A workload proves it cannot tolerate interruption, or a dependency proves
permanently x86-only.

### ADR-014 — No CPU Limit, Memory Request Equals Limit

| | |
|---|---|
| **Status** | Accepted |
| **Requirement** | R8 |
| **Pillars** | Reliability · Performance Efficiency |
| **Section** | §3.5 Resource allocation within the cluster |

**Context.** The Flask API sees bursty traffic, and the team has limited cloud experience, so the
resource policy must be safe by default.

**Options considered.**

| Option | Strengths | Weaknesses | Verdict |
|---|---|---|---|
| CPU request and CPU limit set equal (conventional guidance) | Fully predictable node bin-packing; commonly recommended default | The kernel's Completely Fair Scheduler throttles a pod's CPU the instant it exceeds its limit, even on an otherwise idle node, showing up as unexplained p99 latency that is hard to diagnose | Rejected — trades a real, hard-to-diagnose latency problem for a bin-packing guarantee Karpenter's own right-sizing already provides differently |
| No CPU request or limit at all | Simplest possible manifest | The scheduler has nothing to place pods against, so it cannot reason about node capacity, and Karpenter cannot size a replacement instance correctly | Rejected — removes the signal both the scheduler and Karpenter depend on |
| CPU request set, no CPU limit; memory request equal to limit | The scheduler and Karpenter still place and size nodes correctly from the CPU request; a pod needing a genuine burst can use idle capacity on its node instead of being throttled; the memory setting keeps memory usage capped and predictable | A CPU-hungry pod can briefly use more of a shared node's CPU than its request implies | **Chosen** |

**Decision.** Every workload sets a CPU request, no CPU limit, memory request equal to limit. The
API's baseline is `250m` CPU / `512Mi` memory, three replicas minimum.

**Why this is the right choice for Innovate Inc.** A CPU limit sounds like a safety rail, but
Kubernetes — the software running the application's containers — punishes one running copy, called a
pod, for using spare capacity sitting right on its own machine: it slows down at the exact moment it
works hardest, showing up as a page that is randomly slow for no visible reason. Removing the CPU
limit while keeping the request means Kubernetes still knows how much capacity to reserve when
placing that copy, so scheduling does not get worse. Memory is different: it cannot be reclaimed like
CPU time, so a fixed request and limit tells Kubernetes this copy's need is known, protecting it,
reclaiming others first if a machine runs short.

**Consequences.**
- *Gains:* No CFS-throttling latency spikes; a predictable memory footprint, not first reclaimed.
- *Accepts:* A CPU-hungry pod can briefly use more of a shared node's CPU than its request implies.

**Cost impact.** No direct cost difference — how capacity is shared, not purchased.

**Revisit when.** VPA data shows CPU usage consistently exceeds double its request — evidence the
request is too low, not that a limit is needed.
