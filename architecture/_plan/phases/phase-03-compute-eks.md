# Phase 03 — Compute Platform (Amazon EKS)

> Answers the first two thirds of **assessment area 3** and requirements **R5, R6, R7, R8**.
> Containerization and CI/CD (R9–R11, R23) belong to **Phase 04** — do not write them here.
> Read [`../AGENT-PROTOCOL.md`](../AGENT-PROTOCOL.md), [`../brief.md`](../brief.md),
> [`../contract.md`](../contract.md), [`../decision-register.md`](../decision-register.md),
> [`../well-architected.md`](../well-architected.md), and [`../style-guide.md`](../style-guide.md)
> first.

---

## Goal

Answer three distinct questions the brief asks, and make sure a reviewer can see all three answered:

1. **How is Amazon EKS used to deploy and manage the application?** — cluster topology, control
   plane configuration, authentication, add-ons, and how workloads are laid out.
2. **What is the approach to node groups?** — a managed node group for the platform, Karpenter for
   application capacity, Graviton and Spot, and why that split.
3. **What is the approach to scaling and resource allocation within the cluster?** — HPA, KEDA,
   Karpenter, and VPA are four different mechanisms doing four different jobs; and requests, limits,
   quotas, priority classes, and spread constraints are how capacity is actually apportioned.

"Resource allocation within the cluster" is the sub-bullet candidates drop most often. It is not
autoscaling. It means requests and limits, QoS classes, `ResourceQuota`, `LimitRange`,
`PriorityClass`, and topology spread. Give it its own heading.

---

## Dependencies

Phase 00 must be `done`. Read `drafts/02-network.md` if it exists so subnet references match.

## Inputs

| File | Use it for |
|---|---|
| `_plan/decision-register.md` | ADR template and your reserved ADR block |
| `_plan/well-architected.md` | Pillar tagging convention and what each pillar demands |
| `_plan/contract.md` **§6** | Cluster names, node groups, NodePools, add-ons, sizing — **copy exactly** |
| `_plan/contract.md` §5 | Which subnets nodes and pods live in |
| `_plan/contract.md` §7 | The workload shape (Flask API, workers, SPA on S3) |
| `_plan/rubric.md` §3 probes 2, 5, 9 | Depth probes this section must survive |

## Files you own

- `_plan/drafts/03-compute-eks.md` — create
- `_plan/STATE.md` — update
- `_plan/contract.md` §12 — append only if you invent a name

## Word budget

**~1 800 words** (±20%) for the body, excluding tables and snippets, plus **4 ADRs**
(ADR-011 – ADR-014). This is the largest section — the brief weights it heaviest.

## Two requirements that apply to every section you write

1. **Pillar line.** Every `##` section closes its opening paragraph with
   `> **Well-Architected pillars.** …` carrying 2–4 pillars. See `well-architected.md` §2.
2. **Justification.** Inline, every decision follows decision → why → what it beat → what it costs.
   The significant ones are recorded again as ADRs at the end of the draft. See
   `decision-register.md`.

## This section owns the application tier

`contract.md` §1a establishes three tiers. This section is the **application tier** in full: it runs
in the Private — App subnets, it is reachable only from the load balancer, and it scales by a
mechanism (pods then nodes) that is distinct from how the other two tiers scale. Say so once, early,
and connect the scaling discussion back to it — the fact that the presentation tier absorbs spikes at
the edge is precisely why the application tier's autoscaling targets can be modest.

---

## Content specification

### `## Why managed Kubernetes, and why EKS` (~150 words)

Short and non-defensive. The brief already chose Kubernetes; do not argue for it at length. Say what
EKS actually removes from the team's plate (control-plane availability across three AZs, etcd
backups, control-plane patching, certificate rotation) and what it does not (worker nodes, add-on
versions, workload reliability — all still the team's problem). One honest sentence: Kubernetes is
more operational surface than a five-person team strictly needs on day 1, and the reason to accept it
now is that the migration cost later — at the point of rapid growth — is far higher than the learning
cost today.

Note **EKS Auto Mode** in one sentence as the lower-effort variant AWS now offers, and say why the
design still specifies the components explicitly: the client asked for an architecture, and an
explicit design can be simplified into Auto Mode but not the reverse.

### `## Cluster topology` (~200 words + table)

- One cluster per account, one account per environment. Table of the four clusters from
  `contract.md` §6, columns: Cluster | Account | Region | Purpose.
- **Why one cluster per environment rather than one cluster with namespaces per environment**: the
  account boundary already separates them, so a shared cluster would reintroduce exactly the shared
  blast radius that account separation removed — a bad add-on upgrade would take down dev, staging,
  and production at once.
- Control plane configuration from `contract.md` §6: private endpoint plus CIDR-restricted public,
  envelope encryption of Kubernetes secrets with a customer-managed KMS key, all five control-plane
  log types shipped to CloudWatch and on to the Log Archive account.
- **Version policy:** track the latest EKS-supported minor version, staying at N or N-1, upgrade
  within 30 days of a new minor reaching general availability, always through dev → staging → prod.
  **Do not write a specific Kubernetes version number anywhere** — it will be stale by the time
  anyone reads it, and stating it wrong is worse than not stating it.
- **Authentication:** EKS access entries mapped to IAM Identity Center permission sets. No
  `aws-auth` ConfigMap editing, no long-lived kubeconfig files. This answers rubric probe 9.

### `## Node strategy` (~350 words + table) — **heavily graded**

Two tiers, and the reason for two tiers:

1. **Platform managed node group** `innovate-<env>-mng-platform` — 2–4 `m7g.large` On-Demand
   instances spread over three AZs, tainted `dedicated=platform:NoSchedule`. It hosts CoreDNS, the
   Karpenter controller, the AWS Load Balancer Controller, and the metrics/logging agents. The reason
   this tier exists at all: **Karpenter cannot provision the node it runs on.** Something has to be
   stably there first, it must not be on Spot, and it must not be evicted by the thing it manages.
2. **Karpenter for all application capacity.** Explain what Karpenter does differently from the
   Cluster Autoscaler: it reads pending pods' actual requirements and provisions a right-sized
   instance from a broad family list in seconds, rather than scaling a fixed-shape node group. For a
   workload going from hundreds to millions of users with unknown shape, not pre-committing to an
   instance type is the point.

Reproduce the three NodePools from `contract.md` §6 as a table: NodePool | Architecture | Capacity
type | Instance families | Weight | Used for.

Then the two decisions worth arguing:

- **Graviton first.** `arm64` instances are roughly 20% better on price/performance for typical web
  and API workloads. Python/Flask is architecture-agnostic; the only requirement is that the build
  produces a multi-architecture image (Phase 04). The `amd64` pool exists as a fallback for any
  dependency that is x86-only.
- **Spot for stateless workloads.** Up to 70–90% cheaper. Answer rubric probe 5 completely: Karpenter
  subscribes to an SQS interruption queue fed by EventBridge, receives the two-minute rebalance/
  interruption notice, cordons and drains the node, and provisions a replacement while
  PodDisruptionBudgets keep enough replicas serving. Diversifying across many instance families
  reduces the chance of a correlated interruption. The On-Demand NodePool has the lowest weight so it
  is used only when Spot capacity is genuinely unavailable. State the hard rule: **stateless
  workloads on Spot; anything holding state, or the platform tier, on On-Demand.**

Include a `> **Trade-off.**` callout: Spot means pods get killed on someone else's schedule, so the
application must tolerate abrupt termination — graceful shutdown handling, idempotent request
processing, and no in-memory session state. That is a real constraint on the application team, not a
free lunch.

- **Node lifecycle:** consolidation (`WhenEmptyOrUnderutilized`, `consolidateAfter: 1m`) continuously
  bin-packs and removes underused nodes; `expireAfter: 720h` forces every node to be replaced within
  30 days, which is how the fleet stays patched without a patching process. Bottlerocket or the
  EKS-optimised AMI, immutable and replaced rather than updated in place.

One illustrative NodePool YAML snippet, **≤ 25 lines**, showing requirements
(`karpenter.sh/capacity-type`, `kubernetes.io/arch`, `karpenter.k8s.aws/instance-family`),
`disruption`, and `expireAfter`. One snippet only.

### `## Scaling` (~250 words + table)

The four-mechanism table — this is the correctness test in `rubric.md` §2.C:

| Mechanism | Scales | Signal | Used for |
|---|---|---|---|
| Horizontal Pod Autoscaler (HPA) | Pod replica count | CPU at 65% + requests-per-pod custom metric | The Flask API |
| KEDA | Pod replica count, including scale-to-zero | External event source — SQS queue depth | Background/Celery workers |
| Karpenter | Nodes | Pending pods that cannot be scheduled | All application capacity |
| Vertical Pod Autoscaler (VPA), **recommender mode only** | Recommends requests/limits | Historical usage | Right-sizing advice for humans; never auto-applied alongside HPA on the same metric |

Then:

- **The chain**: traffic rises → HPA adds pods → pods go `Pending` because no node has room →
  Karpenter provisions a right-sized node in well under a minute → pods schedule. Scale-down runs in
  reverse, with consolidation. Make the sequencing explicit; it is what shows the mechanisms were
  understood rather than listed.
- **Burst headroom**: low-priority "overprovisioning" pause pods holding a reservation that real
  workloads preempt, so the first burst does not wait for a node to boot. Name the cost: you pay for
  idle capacity in exchange for latency.
- **Scaling the edge and data tiers** in one sentence each: CloudFront and S3 scale without action;
  Aurora scales via Serverless v2 ACUs and read replicas (Phase 05); the ALB scales itself but
  pre-warming matters for a step-change launch.
- **Where the limits are**: Aurora connections, third-party API rate limits, and the NAT Gateway are
  the first ceilings; cross-reference the growth roadmap (Phase 09).

### `## Resource allocation within the cluster` (~350 words + table) — **do not skip**

Give this its own full treatment. Cover, in order:

- **Requests and limits policy**, stated as a rule with a reason:
  - Always set CPU **requests** — they are what the scheduler and Karpenter use to place and size.
  - Set memory **request = limit** so pods land in the `Guaranteed` QoS class and are the last to be
    evicted under node pressure.
  - **Do not set CPU limits** on the API. Explain CFS throttling: a CPU limit throttles a pod that is
    doing useful work even when the node is idle, which shows up as unexplained p99 latency. Requests
    already guarantee a share.
  - Baseline from `contract.md` §6: `250m` CPU / `512Mi` memory request, memory limit `512Mi`, three
    replicas minimum in production. State plainly that these are starting points refined by VPA
    recommendations and load testing.
- **QoS classes** — `Guaranteed`, `Burstable`, `BestEffort` — and which workloads get which.
- **Namespace layout** (`contract.md` §6): `innovate-api`, `innovate-jobs`, and the `platform-*`
  namespaces, with a one-line purpose each in a table.
- **`ResourceQuota` per namespace** — total CPU, memory, pod count, and PVC count — so one runaway
  deployment cannot consume the whole cluster's budget. **`LimitRange`** to supply defaults and
  ceilings so a pod without explicit resources cannot be admitted unbounded. One combined snippet,
  ≤ 25 lines.
- **`PriorityClass` ladder** from `contract.md` §6 (`platform-critical` > `app-high` > `app-default`
  > `overprovision`) and what preemption does under contention.
- **Spread and disruption**: `topologySpreadConstraints` with `maxSkew: 1` over
  `topology.kubernetes.io/zone` so an AZ loss removes at most a third of replicas;
  `PodDisruptionBudget` `minAvailable: 50%` so voluntary disruptions (node consolidation, upgrades,
  Spot reclamation) never drain a service to zero; anti-affinity between replicas of the same
  deployment.
- **Probes**: `startupProbe`, `livenessProbe` on `/healthz`, `readinessProbe` on `/readyz` which
  checks the database connection — plus `terminationGracePeriodSeconds` and a `preStop` sleep so
  in-flight requests drain before the pod dies. This is what makes Spot interruption invisible to
  users, so tie it back explicitly.

### `## Cluster add-ons and platform services` (~150 words + table)

Table with columns: Component | Purpose | Managed how. Cover every item in `contract.md` §6's two
add-on rows. Split EKS-managed add-ons from those deployed through GitOps, and state the rule: add-on
versions are pinned and upgraded deliberately, never floating.

### `## Workload isolation and multi-tenancy` (~120 words)

Pod Security Admission `restricted` enforced on workload namespaces (non-root, no privilege
escalation, read-only root filesystem, dropped capabilities, seccomp `RuntimeDefault`); NetworkPolicy
default-deny per namespace; EKS Pod Identity giving each service account its own IAM role so a
compromised pod holds only its own permissions; the platform taint keeping application pods off
platform nodes. Cross-reference Phase 06 for the wider security posture rather than repeating it.

---

## Decision Records — ADR-011 to ADR-014

End the draft with `## Decision Records` containing 4 ADRs from your reserved block, using the
exact template in `decision-register.md`. They must cover:

- **ADR-011 — Amazon EKS as the compute platform.** Against Amazon ECS on Fargate, against EKS Auto
  Mode, and against plain EC2 behind a load balancer. Be honest: the brief asked for managed
  Kubernetes, but a reviewer respects an ADR that says "ECS would be less operational work for this
  workload today, and here is why Kubernetes still wins over the five-year horizon" far more than one
  pretending Kubernetes is obviously correct for a five-person team. Fold in one-cluster-per-account.
- **ADR-012 — A platform managed node group alongside Karpenter, and Karpenter over the Cluster
  Autoscaler.** Two related choices in one record. The key reasoning: Karpenter cannot provision the
  node it runs on, and the Cluster Autoscaler is the more conventional, better-understood option that
  Karpenter has to earn its place against.
- **ADR-013 — Graviton as the default architecture, with Spot for the application tier.** Against
  x86-only and On-Demand-everywhere. The *Accepts* list must be substantial — Spot constrains how the
  application is written, and Graviton requires multi-architecture builds.
- **ADR-014 — The requests-and-limits policy: memory request equal to limit, no CPU limit.** Against
  the more common "set both limits" convention. A genuine judgement call that competent engineers
  disagree about, so argue it properly with the CFS-throttling reasoning.

## Acceptance criteria

- [ ] File is `_plan/drafts/03-compute-eks.md`, 1 450–2 150 words excluding tables, snippets, ADRs.
- [ ] All seven `##` sections present, in order, each opening with prose and closing that opening
      paragraph with a pillar line carrying 2–4 pillars.
- [ ] The application tier is named as such and connected to the three-tier model.
- [ ] `## Decision Records` present with 4 ADRs from ADR-011 – ADR-014, full template, no fields
      missing; each has a fairly-argued rejected alternative, a plain-language field a non-engineer
      can read, a real *Accepts* downside, and an observable *Revisit when* trigger.
- [ ] **Node groups**, **scaling**, and **resource allocation** each have their own top-level heading.
      A reviewer scanning headings must see all three.
- [ ] The two-tier node strategy is explained, including *why* the platform managed node group exists
      (Karpenter cannot provision its own node).
- [ ] HPA, KEDA, Karpenter, and VPA are described as four distinct mechanisms with distinct jobs, and
      the HPA → Karpenter chain is traced in sequence.
- [ ] Rubric probe 5 (Spot interruption) answered end to end: SQS interruption queue, two-minute
      notice, cordon/drain, PDB, On-Demand fallback, stateless-only rule.
- [ ] Rubric probe 9 (private API access) answered: Identity Center → access entries.
- [ ] The requests/limits policy states memory request = limit **and** no CPU limit, each with its
      reason (QoS class; CFS throttling).
- [ ] `ResourceQuota`, `LimitRange`, `PriorityClass`, `topologySpreadConstraints`, and
      `PodDisruptionBudget` are all present.
- [ ] Cluster names, NodePool names, instance families, and namespace names match `contract.md` §6
      exactly.
- [ ] At most **three** code snippets, each ≤ 25 lines, each with a language tag.
- [ ] **No specific Kubernetes version number** appears anywhere.
- [ ] A `> **Trade-off.**` callout covers what Spot demands of the application.
- [ ] No container image building, registry, or CI/CD content — that is Phase 04.
- [ ] No `TODO`/`TBD`; no banned words; no emoji.
- [ ] `STATE.md` updated.

## Common failure modes

| Failure | Avoid it by |
|---|---|
| Treating "scaling" and "resource allocation" as the same question | Two headings, two different sets of mechanisms. |
| Calling Karpenter "the cluster autoscaler" | They are different projects with different models. Say how. |
| Setting CPU limits without discussing throttling | The throttling explanation is the signal that this was understood. |
| Writing all of Kubernetes | Only what serves this application and this brief. |
| Bleeding into CI/CD | Phase 04 owns build, registry, and deploy. Stop at "workloads run here". |
| Hard-coding "Kubernetes 1.3x" | Version policy, not a version number. |
| Six YAML snippets | Three maximum. Prose carries the argument. |
| Forgetting probes and graceful shutdown | They are what make Spot and rolling updates safe. |

---

## Agent prompt

```text
You are executing Phase 03 of the Innovate Inc. architecture design plan: Compute Platform (EKS).

Working directory boundary: architecture/ ONLY. Never read or write
terraform/, .claude/, or anything above architecture/. terraform/ belongs to a
different assignment that another agent may be editing right now.

Read in full, in order:
  architecture/_plan/AGENT-PROTOCOL.md
  architecture/_plan/brief.md
  architecture/_plan/contract.md      (§6 is your primary source — copy names exactly)
  architecture/_plan/decision-register.md
  architecture/_plan/well-architected.md
  architecture/_plan/style-guide.md
  architecture/_plan/rubric.md
  architecture/_plan/drafts/00-scope.md
  architecture/_plan/phases/phase-03-compute-eks.md

Read architecture/_plan/drafts/02-network.md only if it exists.
Do not read any other file. No repository-wide searches. No aws/kubectl/terraform/docker/helm.
No web browsing.

Write architecture/_plan/drafts/03-compute-eks.md following the content specification
exactly. Node groups, scaling, and resource allocation must each get their own top-level heading.
Do NOT write about image building, container registries, or CI/CD — Phase 04 owns those.
End the draft with a ## Decision Records section containing ADR-011 through ADR-014, using the exact
template in decision-register.md. Every ADR needs: an options table with at least one genuinely
reasonable rejected alternative argued fairly; a "Why this is the right choice for Innovate Inc."
field written in plain language for a non-engineer founder; an Accepts list naming a real
downside; and a Revisit when field naming an observable trigger.

Close every ## section's opening paragraph with a > **Well-Architected pillars.** line carrying
two to four pillars.

Then verify every acceptance criterion line by line, fix what fails, update STATE.md, report,
and STOP. Do not begin Phase 04.
```
