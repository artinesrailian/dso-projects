# Phase 05 — Database

> Answers **assessment area 4** and requirements **R12, R13, R14, R15**.
> Read [`../AGENT-PROTOCOL.md`](../AGENT-PROTOCOL.md), [`../brief.md`](../brief.md),
> [`../contract.md`](../contract.md), [`../decision-register.md`](../decision-register.md),
> [`../well-architected.md`](../well-architected.md), and [`../style-guide.md`](../style-guide.md)
> first.

---

## Goal

Two questions. **First**: which AWS service runs PostgreSQL, and why that one rather than the
alternatives. **Second**: backups, high availability, and disaster recovery — which the brief lists
as three items and which are three genuinely different things.

The most common failure in this section is collapsing HA and DR into one paragraph about Multi-AZ.
They are different failure domains, with different mechanisms, different RPO/RTO, and different
costs. Give each its own heading.

---

## Dependencies

Phase 00 must be `done`. Read `drafts/02-network.md` if it exists so subnet references match.

## Inputs

| File | Use it for |
|---|---|
| `_plan/decision-register.md` | ADR template and your reserved ADR block |
| `_plan/well-architected.md` | Pillar tagging convention and what each pillar demands |
| `_plan/contract.md` **§8** | Engine, instance class, topology, backup retention, the RPO/RTO table — **copy exactly** |
| `_plan/contract.md` §1 | Rejected alternatives and the one-line reasons |
| `_plan/contract.md` §5, §9 | Data subnets, KMS keys, secrets handling |
| `_plan/rubric.md` §3 probes 3, 6 | Depth probes this section must survive |

## Files you own

- `_plan/drafts/05-database.md` — create
- `_plan/STATE.md` — update
- `_plan/contract.md` §12 — append only if you invent a name

## Word budget

**~1 600 words** (±20%) for the body, excluding tables, plus **4 ADRs** (ADR-019 – ADR-022).

## Two requirements that apply to every section you write

1. **Pillar line.** Every `##` section closes its opening paragraph with
   `> **Well-Architected pillars.** …` carrying 2–4 pillars. See `well-architected.md` §2.
2. **Justification.** Inline, every decision follows decision → why → what it beat → what it costs.
   The significant ones are recorded again as ADRs at the end of the draft. See
   `decision-register.md`.

## This section owns the data tier

`contract.md` §1a establishes three tiers; this is the **data tier**. It sits in the Private — Data
subnets with no route to the internet, it is reachable only from the application tier through RDS
Proxy, and it scales by capacity units and read replicas rather than by adding instances. Name it as
the tier once, early, and let the security discussion lean on the boundary already established in §2
rather than re-deriving it.

---

## Content specification

### `## Recommendation` (~80 words)

One paragraph: **Amazon Aurora PostgreSQL-Compatible Edition** running on **Aurora Serverless v2**
instances, fronted by **Amazon RDS Proxy**, in the private data subnets of each workload account.
State the headline reason: it is the only option that is both cheap enough for a few hundred users
per day and capable of carrying the same application to millions without a migration.

### `## Why Aurora — the alternatives considered` (~400 words + table) — **heavily graded**

The brief says *justify*, so this is the section that earns the marks. Compare four options in a
table (Option | Operational burden | HA | Read scaling | Cost at launch | Verdict), then argue in
prose:

1. **Self-managed PostgreSQL on EC2** — cheapest on paper, and wrong. The team would own patching,
   failover orchestration, backup verification, PITR tooling, replication lag monitoring, and storage
   growth. For a small team holding sensitive user data, the failure mode is not "expensive",
   it is "the backup was never tested and the restore does not work". Reject.
2. **PostgreSQL in Kubernetes via an operator (CloudNativePG, Zalando, CrunchyData)** — attractive
   because everything is then in one control plane, and genuinely good technology. Still rejected
   here: it puts the durability of the company's most valuable asset behind the team's own
   understanding of StatefulSets, storage classes, and operator upgrade semantics, in exchange for
   savings that are small at this scale. Name it as a reasonable choice for a team with dedicated
   platform engineers, which this one does not have.
3. **Amazon RDS for PostgreSQL, Multi-AZ** — a legitimate and cheaper answer, and it should be
   presented as such rather than strawmanned. It gives managed backups, patching, and Multi-AZ
   failover. What it does not give: failover in the tens of seconds (Multi-AZ instance failover is
   typically 60–120 seconds versus Aurora's sub-30), fifteen read replicas sharing one storage layer,
   storage that grows without an operation, Global Database for cross-region DR, or Serverless v2's
   ability to sit near-idle and then scale. Verdict: **the right answer if budget is the only
   constraint; the wrong answer given a millions-of-users target.** Say exactly that — acknowledging
   a close alternative is more credible than pretending it does not exist.
4. **Aurora PostgreSQL (recommended)** — explain the architecture that makes it different: compute
   and storage are separated, the storage layer keeps six copies across three Availability Zones and
   is self-healing, replicas read from that shared storage rather than replaying a log, so adding a
   reader is fast and replication lag is typically milliseconds. Serverless v2 scales capacity in
   fine-grained ACU increments in-place, so the same cluster costs little at 0.5 ACU on day 1 and
   absorbs a growth spike without a maintenance window.

Close with a `> **Trade-off.**` callout that is honest: Aurora costs more per unit of compute than
RDS, is not portable off AWS in the way stock PostgreSQL is, and Serverless v2 has a billing floor
per instance. The counter-argument is engineering time, and at this team size engineering time is the
scarcer resource.

Add one sentence rejecting a non-relational store: the brief specifies PostgreSQL and the data is
relational.

### `## Configuration` (~200 words + table)

Table straight from `contract.md` §8 — Item | Production | Non-production. Cover engine version
(PostgreSQL 16.x with an upgrade path to 17.x via Blue/Green Deployments), instance class and ACU
range, writer/reader topology, cluster identifiers, endpoints, placement, deletion protection, and
parameter-group settings that matter (`rds.force_ssl = 1`, `pgaudit`, `log_min_duration_statement`).

Then two paragraphs:

- **RDS Proxy, and why it is not optional here.** Each gunicorn worker in each Flask pod opens its
  own PostgreSQL connections. Thirty pods × four workers × a small pool is already several hundred
  connections, and PostgreSQL allocates a process per connection — connection exhaustion arrives long
  before CPU does. RDS Proxy multiplexes pod connections onto a managed pool. The second benefit is
  the answer to rubric probe 3: during a failover the proxy holds client connections open and
  re-points them at the new writer, so the application sees a brief stall rather than a storm of
  dropped connections. Pair it with retry-with-backoff in the application and a readiness probe that
  checks the database, and a 30-second failover degrades to slow rather than down.
- **Access control**: no password in the pod. The master credential lives in AWS Secrets Manager with
  30-day automatic rotation; the application authenticates through RDS Proxy using **IAM database
  authentication**, so the pod's identity is its EKS Pod Identity role. Least privilege at the schema
  level too — the application role is not the owner and cannot run DDL; migrations run under a
  separate role.

### `## Security and data protection` (~150 words)

Keep it to what is database-specific; Phase 06 owns the general posture.

- Encryption at rest with the customer-managed key `alias/innovate-<env>-rds`; encryption in transit
  enforced by `rds.force_ssl = 1` with the application using `sslmode=verify-full`.
- Network placement: private data subnets, `publicly_accessible = false`, security group chain
  node SG → proxy SG → Aurora SG on 5432 only.
- Auditing: `pgaudit` for DDL and privileged statements, Performance Insights, Enhanced Monitoring,
  slow-query logs shipped to the Log Archive account.
- **No production data in non-production.** Non-production is seeded with masked or synthetic data.
  Say why plainly: the fastest route to a breach of sensitive user data is a copy of production sitting
  in a development environment with looser controls.
- Column-level protection for the most sensitive fields (application-side encryption or `pgcrypto`),
  noting that it costs queryability — a real trade-off, not a free control.

### `## Backups` (~250 words + table) — **its own heading**

Three tiers, because one backup mechanism is not a backup strategy. Table: Tier | Mechanism |
Frequency | Retention | Protects against | Restore path.

1. **Automated backups + continuous PITR.** Aurora backs up continuously to S3; restore to any second
   within the retention window. Retention 35 days in production, 7 in non-production.
2. **Vaulted cross-account, cross-region copy.** AWS Backup copies a daily snapshot into a vault in a
   *different account* in `us-west-2`, with **Vault Lock in compliance mode** — write-once,
   read-many, undeletable even by an account administrator, even by AWS support. State what this is
   for explicitly: PITR protects against mistakes; a vault lock protects against a **malicious or
   compromised administrator**, which is a different threat and the one that ends companies.
3. **Weekly logical dump** (`pg_dump`) to S3 with Object Lock, for schema-level or single-table
   restores and for portability off Aurora.

Then two points that separate a real answer from a checklist:

- **Restore testing.** A monthly automated job restores the latest snapshot into an isolated account,
  runs a schema and row-count validation, records the elapsed time, and alarms on failure. Untested
  backups are not backups, and the elapsed time is where the real RTO number comes from.
- **Deletion safety**: `deletion_protection = true`, an SCP preventing backup-vault and KMS-key
  deletion in the production OU, and a final snapshot on any deletion.

### `## High availability` (~200 words) — **its own heading, in-region only**

- Aurora's storage layer keeps six copies across three AZs; a single AZ loss does not lose data and
  does not require a restore.
- Production runs a writer and at least one reader in a **different AZ**. Automatic failover promotes
  the reader, typically in under 30 seconds; the cluster endpoint follows the promotion so the
  application does not change its connection string.
- Read traffic goes to the reader endpoint; write traffic to the writer. Note the constraint this
  places on the application: reads served from a replica may be very slightly stale, so read-after-
  write paths must target the writer.
- What the application must do to make HA real: connection retry with exponential backoff, short
  connection timeouts, a readiness probe that checks the database so Kubernetes stops routing traffic
  to a pod that cannot serve, and idempotent write handling. HA at the database is wasted if the
  application panics.
- One sentence on scaling reads later: up to fifteen readers, and Aurora Auto Scaling to add them on
  a metric — cross-reference the growth roadmap in Phase 09.

### `## Disaster recovery` (~250 words + the RPO/RTO table) — **its own heading, cross-region**

Open by defining the distinction in one sentence: HA keeps the service running when a component or an
Availability Zone fails inside one region; DR restores the service when the region, the account, or
the data itself is lost. Different failure domain, different mechanism, different cost.

- **Aurora Global Database** replicates to `us-west-2` at the storage layer, with typical cross-region
  lag under a second and no load on the primary's compute. Managed planned failover is used for
  drills; unplanned promotion is a deliberate, documented decision because it may lose the last
  second of writes.
- **Pilot light** for everything else: Terraform for the whole stack exists and is applied to
  `us-west-2` on demand; ECR replicates images continuously; Route 53 health checks flip DNS. The
  region is not running — that is the cost decision, and it is why RTO is measured in tens of minutes
  rather than seconds.
- Reproduce the **RPO/RTO table from `contract.md` §8 verbatim**, all six rows. This table is the
  literal answer to "outline your approach to disaster recovery".
- **The runbook**, as a short numbered list — this is rubric probe 6: declare the disaster, promote
  the secondary cluster, apply the DR Terraform stack, verify the application, flip Route 53, then
  communicate. Include the failback plan, because a DR plan with no way home is half a plan.
- **DR drills**: quarterly, in a scheduled window, with the measured RTO recorded. State the honest
  point: an untested DR plan has an unknown RTO, and an unknown RTO is not a plan.
- One sentence on when this posture should change: multi-region active-active when the business
  cannot tolerate a 60-minute RTO, and it is a substantial cost and complexity step — deferred to the
  growth roadmap, not built now.

---

## Decision Records — ADR-019 to ADR-022

End the draft with `## Decision Records` containing 4 ADRs from your reserved block, using the
exact template in `decision-register.md`. They must cover:

- **ADR-019 — Amazon Aurora PostgreSQL over the alternatives.** A worked version of this exact record
  is given in `decision-register.md` §1 as the standard to match — read it, then write your own rather
  than copying it. Everything else in this phase should meet that bar.
- **ADR-020 — Aurora Serverless v2 with RDS Proxy.** Two related choices: automatic capacity scaling
  against a per-instance billing floor, and pooled connections against connecting pods directly or
  running PgBouncer as a sidecar. PgBouncer deserves a fair hearing — cheaper and more configurable,
  rejected because it becomes one more thing the team operates.
- **ADR-021 — A three-tier backup strategy rather than automated backups alone.** Specifically why the
  vault-locked cross-account copy exists, which addresses a different threat from point-in-time
  recovery.
- **ADR-022 — Pilot-light cross-region disaster recovery.** Against backup-and-restore only, and
  against a warm standby. The recovery-time consequence of each decides it; say which one Innovate
  Inc. should move to first as they grow.

The plain-language field on the backup ADR should make the distinction a founder needs to
understand: one kind of backup protects you from your own mistakes, and another protects you from
someone who has taken over your account. They are not the same thing and one does not substitute for
the other.

---

## Acceptance criteria

- [ ] File is `_plan/drafts/05-database.md`, 1 300–1 900 words excluding tables and ADRs.
- [ ] **Backups**, **high availability**, and **disaster recovery** have three separate top-level
      headings. Conflating HA and DR is an automatic deduction in `rubric.md`.
- [ ] Every `##` section closes its opening paragraph with a pillar line carrying 2–4 pillars.
- [ ] The data tier is named as such and connected to the three-tier model.
- [ ] `## Decision Records` present with 4 ADRs from ADR-019 – ADR-022, full template, no fields
      missing; each has a fairly-argued rejected alternative, a plain-language field a non-engineer
      can read, a real *Accepts* downside, and an observable *Revisit when* trigger.
- [ ] At least three alternatives are compared in a table and rejected in prose with real reasons,
      including RDS Multi-AZ presented fairly as the budget-constrained answer.
- [ ] The Aurora storage architecture (compute/storage separation, six copies, three AZs) is
      explained, not just named.
- [ ] RDS Proxy is justified with the connection-count arithmetic and the failover behaviour.
- [ ] Rubric probe 3 answered: what the Flask app does during a 30-second failover.
- [ ] Rubric probe 6 answered: the "someone deleted the production database" hour, end to end.
- [ ] The backup strategy has three tiers, and the vault-lock tier explicitly names the
      malicious-administrator / ransomware threat.
- [ ] Restore testing is present with a cadence and an alarm.
- [ ] The RPO/RTO table matches `contract.md` §8 exactly — all six rows.
- [ ] "No production data in non-production" is stated.
- [ ] A `> **Trade-off.**` callout gives the honest downside of Aurora.
- [ ] Identifiers, retention periods, ACU ranges, and KMS aliases match `contract.md` §8.
- [ ] No `TODO`/`TBD`; no banned words; no emoji.
- [ ] `STATE.md` updated.

## Common failure modes

| Failure | Avoid it by |
|---|---|
| "Multi-AZ gives us HA and DR" | Multi-AZ is HA. DR is cross-region. Two headings. |
| Listing backup retention and calling it a backup strategy | Three tiers, a threat each tier addresses, and restore testing. |
| Strawmanning RDS | Present it as the honest budget answer, then say what it costs you. |
| Ignoring connection pooling | Connection exhaustion is the first thing that breaks a Flask fleet on Postgres. |
| No RPO/RTO numbers | The table is the answer. Copy it. |
| Recommending multi-region active-active on day 1 | Pilot light now; active-active in the roadmap with its trigger. |
| Writing the general security posture here | Phase 06 owns it. Stay database-specific. |

---

## Agent prompt

```text
You are executing Phase 05 of the Innovate Inc. architecture design plan: Database.

Working directory boundary: architecture/ ONLY. Never read or write
terraform/, .claude/, or anything above architecture/. terraform/ belongs to a
different assignment that another agent may be editing right now.

Read in full, in order:
  architecture/_plan/AGENT-PROTOCOL.md
  architecture/_plan/brief.md
  architecture/_plan/contract.md      (§8 is your primary source — copy the RPO/RTO table verbatim)
  architecture/_plan/decision-register.md
  architecture/_plan/well-architected.md
  architecture/_plan/style-guide.md
  architecture/_plan/rubric.md
  architecture/_plan/drafts/00-scope.md
  architecture/_plan/phases/phase-05-database.md

Read architecture/_plan/drafts/02-network.md only if it exists.
Do not read any other file. No repository-wide searches. No aws/kubectl/terraform/docker/helm.
No web browsing.

Write architecture/_plan/drafts/05-database.md following the content specification
exactly. Backups, high availability, and disaster recovery MUST be three separate top-level
End the draft with a ## Decision Records section containing ADR-019 through ADR-022, using the exact
template in decision-register.md. Every ADR needs: an options table with at least one genuinely
reasonable rejected alternative argued fairly; a "Why this is the right choice for Innovate Inc."
field written in plain language for a non-engineer founder; an Accepts list naming a real
downside; and a Revisit when field naming an observable trigger.

Close every ## section's opening paragraph with a > **Well-Architected pillars.** line carrying
two to four pillars.

headings — conflating HA and DR is an automatic deduction. Then verify every acceptance criterion
line by line, fix what fails, update STATE.md, report, and STOP. Do not begin Phase 06.
```
