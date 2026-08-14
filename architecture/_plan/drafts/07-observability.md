## Observability strategy

Innovate Inc.'s operating question is not whether a server is up; it is whether users are getting
what they asked for, quickly, and if not, which of the three tiers — presentation, application, data
— is failing them. We instrument for the questions engineers actually ask during an incident, not for
the dashboards a team likes to have sitting unused: fewer signals, each answering one specific
question, beat a wall of graphs nobody reads at 2am.

> **Well-Architected pillars.** Operational Excellence · Reliability

Each tier fails differently and is observed differently. The presentation tier, served entirely from
CloudFront outside the Virtual Private Cloud (VPC), is watched through edge metrics and real-user
timing — a falling cache-hit ratio or a rising origin-error rate tells a different story than an
application bug. The application tier, the Flask REST API and its background workers on Amazon Elastic
Kubernetes Service (EKS), is watched through request-level metrics and distributed traces. The data
tier, Aurora PostgreSQL behind Amazon Relational Database Service (RDS) Proxy, is watched through
connection, replication, and query metrics — a tier degrading silently under load looks nothing like a
tier that is down.

---

## The four signals

Four signal types answer four different incident questions; a team that collects all four but only
ever asks "is the server up" has bought tooling it does not use.

> **Well-Architected pillars.** Operational Excellence · Reliability · Performance Efficiency

| Signal | Tooling | The question it answers |
|---|---|---|
| Metrics | Amazon Managed Service for Prometheus + Amazon Managed Grafana; CloudWatch Container Insights | Is it healthy, and is it getting worse |
| Logs | Fluent Bit → CloudWatch Logs (14 days hot) → S3 in the Log Archive account, queried with Athena (400 days) | What exactly happened to this one request |
| Traces | OpenTelemetry instrumentation in Flask → AWS Distro for OpenTelemetry (ADOT) Collector → AWS X-Ray | Which hop is slow |
| Synthetics | CloudWatch Synthetics canaries against the single-page application (SPA) at `https://app.innovateinc.com` and `/api/healthz` from two regions | Is it broken for a user right now, before anyone reports it |

At the application tier, what is actually measured is the RED method — Rate, Errors, Duration, per
endpoint — plus saturation: request rate and latency percentiles per route, the HTTP 5xx rate,
gunicorn worker saturation, database connection-pool utilization at RDS Proxy, queue depth for the
background worker tier, and pod restart counts. Those seven numbers, not a generic CPU graph, tell an
engineer which of the three tiers is degrading and how.

A trace ID generated at CloudFront propagates through the Application Load Balancer (ALB) into the
Flask request context and is emitted on every structured log line the request produces, tying one
edge request to its application log lines and any slow query underneath. Without that correlation,
debugging one slow request across three tiers is grep-and-hope — searching separate log streams by
timestamp and guessing which lines belong together; with it, one identifier retrieves the whole
story.

Logs are structured JSON, carry no personally identifiable information (PII) in the log body (§5.3
Data protection classifies which fields those are), and sample debug-level logging rather than
shipping every line at full verbosity. Retention is tiered deliberately — 14 days hot for active
investigation, 400 days cold for audit and forensic work — because log volume is a real, ongoing cost
line, not a free byproduct of running the application.

> **Day 1 vs. at scale.** The in-cluster `kube-prometheus-stack` costs materially less than Amazon
> Managed Service for Prometheus and Amazon Managed Grafana and is entirely adequate for a few
> hundred users. The reason to move to the managed services is not scale for its own sake — a
> monitoring system running inside the cluster it monitors goes blind at exactly the moment it is
> needed, during a cluster-wide incident. The trigger: the first incident where the cluster and its
> monitoring fail together, or the point at which an on-call rotation exists.

---

## Service level objectives

A service level objective (SLO) converts "is this bad?" from a debate into a number the team agreed
on in advance — the single most useful thing a small team with no dedicated site reliability engineer
can do to stop people arguing about severity while a system is actually degraded.

> **Well-Architected pillars.** Operational Excellence · Reliability

| SLO | At launch | At scale |
|---|---|---|
| API availability | 99.9% monthly | 99.95%, once failover across Availability Zones (AZs) and canary deploys are proven |
| p95 latency | < 300 ms | Same |
| p99 latency | < 800 ms | Same |
| Error rate | < 0.5% | Same |

An SLO with no consequence is a wish, not a target. Innovate Inc.'s error budget policy: once the
error budget burns faster than twice its allowed rate, feature work pauses until the burn rate
returns to baseline. That is a policy the founders must actually agree to before an incident, not a
rule engineering invents unilaterally at 2am and hopes the business accepts afterward — it trades a
sprint's roadmap for reliability, and the trade only holds if it was agreed in advance.

Three things the day-1 SLO deliberately does not cover: per-customer SLOs, an availability commitment
to an external party, and a formal service level agreement (SLA). All three wait until a contract
exists that actually requires them; building them earlier spends effort on a promise nobody has asked
for yet.

---

## Alerting and on-call

We page a human only on symptoms users feel — error rate, latency, availability, and the synthetic
canary failing — and dashboard the causes: CPU, memory, pod restarts, node count. A cause alert fires
during every deployment and every autoscaling event, which are normal; a symptom alert fires only
when someone is actually being harmed, which is the one condition worth waking a person for.

> **Well-Architected pillars.** Operational Excellence · Reliability

Every alert that can page carries a runbook link, no exceptions. An alert with no runbook hands the
person on call a problem to solve from first principles at 3am, on a system they may not have touched
that week — the opposite of what an alert is for. Alerts route from Prometheus Alertmanager and
CloudWatch Alarms through Amazon Simple Notification Service (SNS) to PagerDuty and Slack, with
severity tiers deciding what pages immediately and what waits for the next working morning.

The honest constraint that shapes this whole section: a small team can sustain only a very short
page-worthy list. An alert that pages and is not actionable gets muted within two weeks by whoever is
tired of it, and a muted alert is worse than no alert at all — it creates the false confidence that
someone is watching when no one is. The paging list stays limited to the handful of conditions that
mean users are being harmed right now.

---

## Operational practices

The rest of the Operational Excellence pillar is concrete practice, not aspiration.

> **Well-Architected pillars.** Operational Excellence · Reliability

**Everything as code.** Terraform defines infrastructure; Git defines cluster state; no console change
is made by hand, and Argo CD detects and reverts drift automatically (§3.9 Deployment — CI/CD and
GitOps). The operational payoff is concrete: the answer to "what changed?" is always `git log`, not a
memory of who clicked what.

**Small, reversible changes.** Canary rollouts, immutable image digests, and a one-commit rollback
(`git revert`) keep every production change small enough to undo in minutes, not hours (§3.9).

**Rehearsed failure.** Quarterly disaster recovery drills, monthly automated restore tests (§4.4
Backups), and game days for the failure modes that matter most here — an AZ loss, a Spot capacity
squeeze, a bad deployment — turn a recovery time objective from a number on paper into a rehearsed,
measured procedure.

**Post-incident review**, without blame, with every action item tracked as real, scheduled work
rather than a note nobody revisits.

**The runbook set** the team needs from day one: deployment and rollback, database restore, scaling a
sudden traffic spike, revoking a compromised credential, and the disaster-recovery failover procedure
(§4.6 Disaster recovery).

---

## Decision Records

The two decisions below carry the full argument for how Innovate Inc. observes its own system: which
observability stack it runs and when it changes, and what "good enough" means well enough to act on
during an incident. Each stands on its own, with a plain-language justification a non-technical
reader can follow without the rest of this document.

> **Well-Architected pillars.** Operational Excellence · Reliability · Cost Optimization

### ADR-026 — Open-Source Observability, Managed at Scale

| | |
|---|---|
| **Status** | Accepted |
| **Requirement** | R19, R7 |
| **Pillars** | Operational Excellence · Reliability · Cost Optimization |
| **Section** | §6.2 The four signals |

**Context.** Innovate Inc. has a small engineering team, no dedicated site reliability function, and a
target of millions of users from a few hundred today. The stack must stay affordable and not fail
during an incident.

**Options considered.**

| Option | Strengths | Weaknesses | Verdict |
|---|---|---|---|
| In-cluster `kube-prometheus-stack`, permanently | Materially cheaper; a single Helm chart to deploy; the team already needs to know Prometheus | Runs inside the cluster it monitors — a cluster-wide incident can take the monitoring stack down with the thing it is meant to observe | Rejected as the permanent answer — right for day 1, wrong once an incident actually matters |
| Amazon Managed Service for Prometheus and Amazon Managed Grafana, from day 1 | Survives a cluster-wide failure; no Prometheus server to operate or scale | Materially more expensive than in-cluster monitoring while traffic is still a few hundred users a day | Rejected for day 1 — the expense buys resilience the team does not yet need |
| A commercial platform such as Datadog | Meaningfully less operational work than either open-source path; strong dashboards out of the box | Pricing grows steeply with hosts and log volume; routes telemetry adjacent to sensitive user data through a third-party platform, a data-residency question the rest of this design otherwise avoids | Rejected — a fair option today, the wrong one once volume and data sensitivity both grow |
| In-cluster at launch, migrate to Amazon Managed Service for Prometheus and Amazon Managed Grafana at a named trigger | Cheap where the team needs cheap, resilient once resilience is worth paying for; the same metrics port across without being redefined | Requires a deliberate migration at the trigger point rather than one stack chosen once | **Chosen** |

**Decision.** Innovate Inc. runs the in-cluster `kube-prometheus-stack` at launch, migrating to Amazon
Managed Service for Prometheus and Amazon Managed Grafana at the first cluster-wide incident or once
an on-call rotation exists.

**Why this is the right choice for Innovate Inc.** Watching a system for problems costs money, and how
much depends on catching one fast. Today, with a few hundred users, the cheapest option — running the
monitoring software on the same computers it watches — is reasonable and saves money for elsewhere.
Its catch: a whole-cluster problem can take the monitor down with it, exactly when it matters most. The
fix is switching once an on-call engineer depends on it, not paying up front for resilience not yet
needed. A ready-made commercial platform routes customer-adjacent data through a third company and
grows expensive with scale.

**Consequences.**
- *Gains:* A cheap start; a defined trigger to a resilient stack; no vendor holding customer data.
- *Accepts:* Running blind through one real cluster-wide incident before the trigger fires; the
  cutover carries no dashboards or history with it.

**Cost impact.** In-cluster monitoring costs less at launch; the managed services cost more but avoid
a single point of failure.

**Revisit when.** The first cluster-wide incident where in-cluster monitoring fails with the system it
watches, or an on-call rotation is staffed.

### ADR-027 — SLO Targets and the Error-Budget Policy

| | |
|---|---|
| **Status** | Accepted |
| **Requirement** | R19, R25 |
| **Pillars** | Operational Excellence · Reliability |
| **Section** | §6.3 Service level objectives |

**Context.** Innovate Inc. has a small engineering team, no dedicated site reliability function, and a
growth target of millions from a few hundred users. The team needs one shared definition of "good
enough" to act on.

**Options considered.**

| Option | Strengths | Weaknesses | Verdict |
|---|---|---|---|
| No formal SLO, alert on ad-hoc thresholds only | Nothing to define or agree on up front | Every incident starts with an argument about whether it is bad enough to page or ship around; the bar moves with whoever is on call that day | Rejected — the exact ambiguity an SLO exists to remove |
| 99.99% availability ("four nines") from launch | The strongest customer-facing promise available | About 52 minutes of downtime a year, demanding multi-region active-active infrastructure and extensive chaos testing this small team cannot yet carry, for traffic that does not yet justify it | Rejected — the cost of the extra nines lands entirely on a team too small to carry it |
| Error budget as a reporting signal only, human call at breach | No automatic disruption to the roadmap; the decision stays with whoever has business context that day | The freeze becomes negotiable exactly when it is inconvenient, reintroducing the same mid-incident argument the SLO exists to end | Rejected — an automatic rule is the only version that holds up when it is actually tested |
| 99.9% at launch, rising to 99.95% once proven, with an automatic feature freeze on budget burn | Matches what a single-region, multi-AZ design with automatic failover can honestly deliver; the automatic freeze holds even under deadline pressure | A visibly less ambitious availability number than "four nines" without the context of team size and stage | **Chosen** |

**Decision.** Innovate Inc. targets 99.9% monthly availability, p95 latency under 300 ms, p99 under
800 ms, and error rate under 0.5% at launch, rising availability to 99.95% at scale; a burn rate past
2× the allowed pace pauses feature work until it returns to baseline.

**Why this is the right choice for Innovate Inc.** A 99.9% target allows about 43 minutes of downtime
a month — what this design can honestly deliver today. The next level, 99.99%, cuts that to about 5
minutes, and costs far more than the difference suggests: multiple active regions and heavier
automated testing, for a target the business does not need yet. The error budget makes that number a
decision rule: breaking the promise pauses feature work automatically, agreed ahead of time so nobody
argues mid-incident.

**Consequences.**
- *Gains:* One agreed number ending "is this bad enough?" debates; an automatic trade-off between
  speed and reliability.
- *Accepts:* A less ambitious headline than "four nines," and a feature freeze the team must honor.

**Cost impact.** Lower than chasing 99.99% requires — no extra region or standby capacity beyond what
this design already carries.

**Revisit when.** A partner contract requires a documented external service level agreement, or the
monthly error budget finishes more than half unspent for two consecutive quarters.
