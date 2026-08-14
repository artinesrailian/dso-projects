# Phase 07 — Observability & Operational Excellence

> Answers requirement **R19** (robust) and carries the **Operational Excellence** pillar.
> Cost is **Phase 08**; the growth roadmap is **Phase 09**. Do not write either here.
> Read [`../AGENT-PROTOCOL.md`](../AGENT-PROTOCOL.md), [`../contract.md`](../contract.md),
> [`../decision-register.md`](../decision-register.md),
> [`../well-architected.md`](../well-architected.md), and [`../style-guide.md`](../style-guide.md)
> first.

---

## Goal

Answer the question a reviewer asks about every design that claims to be robust: **how does a
small team know this system is healthy, and what do they do at 2am when it is not?**

Observability is where the Operational Excellence pillar lives, and it is the section that most
clearly signals whether the author has actually run a production system. The difference is
concrete: a weak answer lists monitoring products; a strong answer explains what question each
signal answers, which alerts wake a human, and why the alert list is deliberately short.

---

## Dependencies

Phase 00 must be `done`. Read `drafts/03-compute-eks.md` and `drafts/05-database.md` if they exist —
you reference their mechanisms rather than re-describing them.

## Inputs

| File | Use it for |
|---|---|
| `_plan/contract.md` **§10** | The observability stack and the SLO targets — **copy exactly** |
| `_plan/contract.md` §1a | The three tiers, each of which needs its own observability answer |
| `_plan/well-architected.md` OPS | What Operational Excellence demands of this design |
| `_plan/decision-register.md` | ADR template; **your block is ADR-026 – ADR-027** |
| `_plan/rubric.md` §2.C | The Well-Architected scoring dimension |

## Files you own

- `_plan/drafts/07-observability.md` — create
- `_plan/STATE.md` — update, including the ADR ledger
- `_plan/contract.md` §12 — append only if you invent a name

## Word budget

**~1 000 words** (±20%) for the body, plus **2 ADRs** (ADR-026 – ADR-027).

---

## Content specification

Each `##` section closes its opening paragraph with a `> **Well-Architected pillars.**` line.

### `## Observability strategy` (~150 words)

Open with the framing that keeps this from becoming a product catalogue: the question is not "is the
server up" but "are users getting what they asked for, quickly — and if not, which of the three
tiers is failing them". State the operating principle: **instrument for the questions you will ask
during an incident, not for the dashboards you would like to have.**

Then make the three-tier point explicitly, because it is what makes this section specific to this
design rather than generic: each tier fails differently and is observed differently — the
presentation tier through edge metrics and real-user timing, the application tier through
request-level metrics and traces, the data tier through connection, replication, and query metrics.

### `## The four signals` (~300 words + table)

| Signal | Tooling | The question it answers |
|---|---|---|
| Metrics | Amazon Managed Service for Prometheus + Amazon Managed Grafana; CloudWatch Container Insights | Is it healthy, and is it getting worse |
| Logs | Fluent Bit → CloudWatch Logs (14 days hot) → S3 in the Log Archive account, queried with Athena (400 days) | What exactly happened to this one request |
| Traces | OpenTelemetry instrumentation in Flask → ADOT Collector → AWS X-Ray | Which hop is slow |
| Synthetics | CloudWatch Synthetics canaries against the SPA and `/api/healthz` from two regions | Is it broken for a user right now, before anyone reports it |

Then, in prose:

- **What is actually measured** at the application tier: the RED method — Rate, Errors, Duration —
  per endpoint, plus saturation signals. Name the specific metrics that matter for this stack:
  request rate and latency percentiles per route, HTTP 5xx rate, gunicorn worker saturation, database
  connection-pool utilisation at the RDS Proxy, queue depth for the worker tier, and pod restart
  counts.
- **Correlation**: a trace ID propagated from CloudFront through the ALB into the Flask request
  context and emitted on every log line, so one identifier ties an edge request to an application log
  to a slow query. Say why this matters concretely — without it, debugging is grep-and-hope.
- **Log discipline**: structured JSON logs, no personally identifiable information in log bodies
  (cross-reference the data classification in §5), sampled debug logging, and retention tiers chosen
  deliberately because log volume is a real cost line.

> **Day 1 vs. at scale.** The in-cluster `kube-prometheus-stack` is materially cheaper than the
> managed services and entirely adequate for a few hundred users. The reason to move to Amazon
> Managed Prometheus and Grafana is not scale for its own sake — it is that a monitoring system
> running inside the cluster it monitors goes blind at exactly the moment it is needed. Name the
> trigger: the first incident where the cluster and its monitoring failed together, or the point at
> which an on-call rotation exists.

### `## Service level objectives` (~200 words + table)

- Reproduce the SLO table from `contract.md` §10: availability 99.9% monthly at launch rising to
  99.95%, p95 latency under 300 ms, p99 under 800 ms, error rate under 0.5%.
- Explain **why a small team should use SLOs rather than threshold alerts**: an SLO converts "is this
  bad?" into a number the team agreed on in advance, which is what stops three engineers debating
  severity during an incident. It also gives a principled answer to "should we ship this feature or
  fix reliability?" — the error budget.
- **Error budget policy** from `contract.md` §10: burn faster than 2× and feature work pauses until
  the burn rate returns to baseline. State that this is a policy the founders must actually agree to,
  or it is decoration.
- Note what the SLO does **not** cover on day 1 and why: per-customer SLOs, availability commitments
  to external parties, and a formal service level agreement all wait until there is a contract that
  requires them.

### `## Alerting and on-call` (~200 words)

- **Page on symptoms users feel** — error rate, latency, availability, and the synthetic canary.
  **Dashboard the causes** — CPU, memory, pod restarts, node count. Explain the reason: a cause alert
  fires during every deployment and every autoscaling event; a symptom alert fires when someone is
  actually being harmed.
- Every alert carries a runbook link. An alert without a runbook is an alert the person on call has
  to solve from first principles at 3am.
- Routing from Alertmanager and CloudWatch alarms through SNS to PagerDuty and Slack, with severity
  tiers deciding what pages and what waits for morning.
- The honest constraint, and it belongs here: **a small team can sustain a very short
  page-worthy list.** An alert that pages and is not actionable will be muted within two weeks, and
  a muted alert is worse than no alert because it creates false confidence. Keep the paging list to
  the handful of conditions that mean users are being harmed right now.

### `## Operational practices` (~200 words)

The rest of the Operational Excellence pillar, briefly and concretely:

- **Everything as code** — Terraform for infrastructure, Git for cluster state. No console changes;
  drift is detected and reverted by Argo CD. Say what this buys operationally: the answer to "what
  changed?" is always `git log`.
- **Small reversible changes** — canary rollouts, one-commit rollback, immutable image digests
  (cross-reference §3).
- **Rehearsed failure** — quarterly disaster recovery drills, monthly restore tests, and game days
  for the failure modes that matter: an AZ loss, a Spot capacity squeeze, a bad deployment. Rehearsed
  failure is the difference between a recovery time objective and a hope.
- **Post-incident review** without blame, with the action item tracked as work.
- **Runbook set** the team needs from day one, listed: deployment and rollback, database restore,
  scaling a sudden traffic spike, revoking a compromised credential, and the DR failover procedure.

---

## Decision Records — ADR-026 to ADR-027

End the draft with `## Decision Records` containing 2 ADRs from your reserved block, using the
exact template in `decision-register.md`. They must cover:

- **ADR-026 — The observability stack and its day-1 versus at-scale split.** Managed Prometheus and
  Grafana against in-cluster, against a commercial platform such as Datadog. The commercial option
  deserves a fair hearing: it is genuinely less work for a small team, and the reason to reject it is
  cost at scale and data residency for sensitive workloads. Say so.
- **ADR-027 — SLO targets and the error-budget policy.** Why 99.9% and not 99.99%, and what the extra
  nine would cost in architecture and in team discipline.

Remember: the **"Why this is the right choice for Innovate Inc."** field is written for a
non-engineer founder. For the SLO ADR, that means explaining what 99.9% means in minutes of downtime
per month and why chasing more would slow their team down.

---

## Acceptance criteria

- [ ] File is `_plan/drafts/07-observability.md`, 800–1 250 words excluding tables and ADRs.
- [ ] Five `##` sections, each opening with prose and closing that paragraph with a pillar line.
- [ ] All four signals covered, each with the question it answers.
- [ ] The three tiers are each given a distinct observability treatment.
- [ ] RED metrics named specifically for this stack, including RDS Proxy connection-pool utilisation.
- [ ] Trace-ID correlation across tiers is explained with its concrete benefit.
- [ ] SLO numbers and the error-budget policy match `contract.md` §10 exactly.
- [ ] Symptom-alerts-page versus cause-alerts-dashboard is stated with its reason.
- [ ] The small-team constraint on alert volume is named honestly.
- [ ] Operational practices cover as-code, reversible changes, rehearsed failure, and post-incident
      review.
- [ ] `## Decision Records` present with 2 ADRs from ADR-026 – ADR-027, full template, no fields
      missing.
- [ ] Every ADR's plain-language field is readable by a non-engineer; every *Accepts* list contains a
      real downside; every *Revisit when* names an observable trigger.
- [ ] **No cost figures** — that is Phase 08. **No growth roadmap** — that is Phase 09.
- [ ] No `TODO`/`TBD`; no banned words; no emoji.
- [ ] `STATE.md` updated, including the ADR ledger row for Phase 07.

## Common failure modes

| Failure | Avoid it by |
|---|---|
| A list of monitoring products | Every row of the signals table has an "answers" column. |
| Alerting on CPU and pod restarts | Page on symptoms; dashboard the causes. Say why. |
| SLOs with no error-budget policy | A target with no consequence is a wish. |
| Writing the cost of the observability stack | Phase 08 owns cost. One qualitative clause is the limit. |
| Bleeding into the growth roadmap | Phase 09 owns it. Name a trigger and stop. |
| Ignoring that this team has no dedicated SRE | It is the constraint that shapes the whole section. |

---

## Agent prompt

```text
You are executing Phase 07 of the Innovate Inc. architecture design plan: Observability &
Operational Excellence.

Working directory boundary: architecture/ ONLY. Never read or write terraform/, .claude/, or
anything above architecture/ — terraform/ belongs to a different assignment that another agent
may be editing right now.

Read in full, in order:
  architecture/_plan/AGENT-PROTOCOL.md
  architecture/_plan/brief.md
  architecture/_plan/contract.md           (§10 and §1a are your primary sources)
  architecture/_plan/decision-register.md  (your ADR block is 026-027)
  architecture/_plan/well-architected.md
  architecture/_plan/style-guide.md
  architecture/_plan/rubric.md
  architecture/_plan/phases/phase-07-observability.md

Then read whichever of these exist, to reference rather than duplicate:
  architecture/_plan/drafts/03-compute-eks.md
  architecture/_plan/drafts/05-database.md

Do not read any other file. No repository-wide searches. No aws/kubectl/terraform/docker/helm.
No web browsing.

Write architecture/_plan/drafts/07-observability.md following the content specification exactly,
ending with a ## Decision Records section containing ADR-026 through ADR-027.

Do NOT write cost figures (Phase 08 owns cost) or a growth roadmap (Phase 09 owns it).

Then verify every acceptance criterion line by line, fix what fails, update STATE.md including the
ADR ledger, report, and STOP. Do not begin Phase 08.
```
