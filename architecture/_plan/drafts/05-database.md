## Recommendation

Innovate Inc.'s data tier — the third tier of the three-tier model in §0.2 Architecture overview —
runs on **Amazon Aurora PostgreSQL-Compatible Edition**, using **Aurora Serverless v2** capacity
units, fronted by **Amazon RDS Proxy**, inside the Private — Data subnets established in §2.2 VPC
and subnet architecture. It is the only option evaluated below that is inexpensive enough for a few
hundred daily users at launch and capable of carrying the same schema and the same running cluster
to millions of users later, without a database migration along the way.

> **Well-Architected pillars.** Reliability · Performance Efficiency · Cost Optimization

---

## Why Aurora — the alternatives considered

Four ways to run PostgreSQL are available to Innovate Inc. Each is compared below on operational
burden, availability, read scaling, and cost at launch.

> **Well-Architected pillars.** Reliability · Performance Efficiency · Cost Optimization ·
> Operational Excellence

| Option | Operational burden | High availability (HA) | Read scaling | Cost at launch | Verdict |
|---|---|---|---|---|---|
| Self-managed PostgreSQL on Amazon EC2 | Team owns patching, failover, and backup verification | Manual, built by the team | Manual replica setup | Lowest sticker price | Rejected |
| PostgreSQL in Kubernetes, via an operator | Team owns `StatefulSet` storage classes and operator upgrades | Operator-managed; only as good as its configuration | Operator-managed | Low | Rejected |
| Amazon RDS for PostgreSQL, Multi-AZ | AWS-managed patching and backups | Automatic, 60–120 s failover | Read replicas, each with independent storage | Low to moderate | Rejected for this target |
| Aurora PostgreSQL, Serverless v2 (recommended) | AWS-managed patching, backups, and storage growth | Automatic, sub-30 s failover | Up to 15 read replicas on shared storage | Moderate, scales to near-idle | **Chosen** |

**Self-managed PostgreSQL on EC2** is cheapest on paper and wrong for this team. Innovate Inc. has
five engineers and no database administrator; running PostgreSQL themselves means owning patching,
failover orchestration, backup verification, point-in-time recovery (PITR) tooling, replication-lag
monitoring, and storage growth, for data classified as sensitive. The failure mode is not an
expensive bill — it is a backup that was never tested and does not restore when it matters most.

**PostgreSQL in Kubernetes**, through an operator such as CloudNativePG, Zalando, or CrunchyData, is
genuinely good technology — it keeps the database inside the same Amazon EKS control plane as
everything else. It is rejected here because it puts the durability of Innovate Inc.'s most valuable
asset behind the team's own depth with storage classes and operator upgrades — reasonable for a team
with dedicated platform engineers, which this one is not, for savings that are small at this scale.

**Amazon RDS for PostgreSQL, Multi-AZ**, is the closest real alternative. It gives managed backups,
patching, and Multi-AZ failover for less than Aurora costs. What it does not give: sub-30-second
failover — Multi-AZ instance failover typically takes 60–120 seconds — a shared-storage read-replica
fleet, storage that grows without an operation, or a managed cross-region replication path. **RDS is
the right answer if budget were the only constraint; it is the wrong answer against a
millions-of-users target.**

**Aurora PostgreSQL (recommended)** separates compute from storage: the storage layer keeps six
copies of the data across three Availability Zones (AZs) and repairs itself, and a reader attaches to
that same shared storage rather than replaying a stream of changes, so replication lag is typically
milliseconds. Aurora Serverless v2 changes capacity in fine-grained Aurora Capacity Unit (ACU)
increments in place, with no restart and no maintenance window, so the same cluster costs little at
0.5 ACU today and absorbs a traffic spike without anyone paging an engineer.

> **Trade-off.** Aurora costs more per unit of compute than Amazon RDS, is not as portable off AWS as
> stock PostgreSQL, and Serverless v2 carries a small billing floor per instance even at minimum
> capacity. The counter-argument is engineering time: at Innovate Inc.'s size, engineering time is
> the scarcer resource, and Aurora spends the least of it.

Innovate Inc.'s data is relational — user accounts, ownership, and referential integrity are the
point — so a non-relational store such as Amazon DynamoDB is not evaluated here; the brief specifies
PostgreSQL and the workload confirms it is the right fit.

---

## Configuration

The cluster configuration differs by environment on capacity and topology, not on engine or
placement; every environment runs the identical service, encrypted and privately placed the same
way.

> **Well-Architected pillars.** Reliability · Security · Performance Efficiency

| Item | Production | Non-production |
|---|---|---|
| Engine version | PostgreSQL 16.x, upgrade path to 17.x via Blue/Green Deployments | Same |
| Instance class | Aurora Serverless v2, `0.5–16 ACU` | Aurora Serverless v2, `0.5–2 ACU` (dev only; auto-pause enabled in dev only, not staging) |
| Topology | Writer + 1 reader, separate Availability Zones | Dev: writer only. Staging: writer + reader, mirroring production at reduced capacity |
| Cluster identifier | `innovate-prod-aurora-pg-use1` | `innovate-stg-aurora-pg-use1`, `innovate-dev-aurora-pg-use1` |
| Endpoints | Writer, reader, and custom endpoints for analytics/reporting | Dev: writer only. Staging: writer and reader |
| Placement | Private — Data subnets, `publicly_accessible = false` | Same |
| Deletion protection | `deletion_protection = true` | Same |
| Encryption at rest | Customer-managed key `alias/innovate-prod-rds` | `alias/innovate-stg-rds`, `alias/innovate-dev-rds` |
| Encryption in transit | `rds.force_ssl = 1`, app uses `sslmode=verify-full` | Same |
| Schema migrations | Alembic, run as a Kubernetes `Job` in an Argo CD `PreSync` hook | Same |

**RDS Proxy, and why it is not optional here.** Each gunicorn worker in each Flask pod holds its own
small pool of PostgreSQL connections, and PostgreSQL allocates a process per connection, not a
thread — thirty pods running four workers each, each with its own pool, already adds up to several
hundred connections, and exhaustion arrives long before CPU does. Amazon RDS Proxy
`innovate-prod-aurora-pg-proxy` multiplexes that connection count onto a managed pool against the
writer and reader, so pods never connect to Aurora directly. The second benefit shows up during a
failover: the proxy holds client connections open and re-points them at the new writer, so the
application sees a brief stall, not a storm of dropped connections. Paired with retry-with-backoff
and a readiness probe that checks the database, a 30-second failover degrades to slow rather than
down.

**Access control.** No password lives in the pod. The master credential sits in AWS Secrets Manager
with automatic 30-day rotation; the application authenticates through RDS Proxy using **AWS Identity
and Access Management (IAM) database authentication**, so the pod's identity is its EKS Pod Identity
role, not a stored secret. Least privilege applies at the schema level too: the application's
database role is not the owner and cannot run data-definition-language (DDL) statements. Schema
migrations run under a separate, narrower role, using an expand/contract pattern so every migration
stays compatible with the previous app version during a rolling deployment.

---

## Security and data protection

This section covers the controls specific to the data tier; §5 Security and Data Protection covers
the organization-wide security posture.

> **Well-Architected pillars.** Security · Reliability · Operational Excellence

- **Encryption.** At rest with the customer-managed key `alias/innovate-<env>-rds`; in transit
  enforced by `rds.force_ssl = 1` on the server and `sslmode=verify-full` in the application, so a
  connection that cannot verify the server certificate refuses to send data.
- **Network placement.** Private — Data subnets only, `publicly_accessible = false`, and a security
  group chain — node/pod to proxy to Aurora, port 5432 only — so nothing reaches the database except
  through the application tier and the proxy.
- **Auditing.** `pgaudit` with `log_statement=ddl` for privileged statements, Performance Insights,
  Enhanced Monitoring at 60-second granularity, and slow-query logs shipped to
  `innovate-log-archive`.
- **No production data in non-production.** Development and staging are seeded with masked or
  synthetic data: the fastest route to a breach of sensitive user data is a copy of production sitting
  in an environment with looser controls.
- **Column-level protection** for the most sensitive fields — application-side encryption or
  `pgcrypto` — is available beyond table-level encryption, at the cost of losing the ability to query
  that column directly; a real trade-off, not a free control.

---

## Backups

One backup mechanism is not a backup strategy. Innovate Inc.'s data survives three separate,
independent failure modes, each with its own tier.

> **Well-Architected pillars.** Reliability · Security · Operational Excellence

| Tier | Mechanism | Frequency | Retention | Protects against | Restore path |
|---|---|---|---|---|---|
| Automated backups + continuous PITR | Aurora backs up continuously to S3 | Continuous | 35 days prod / 7 days non-prod | Accidental deletion, a bad deploy, a bug that corrupts rows | Restore to any second in the window, into a new cluster |
| Vaulted cross-account, cross-region copy | AWS Backup daily copy into a separate account's vault in `us-west-2`, Vault Lock compliance mode | Daily | 90 days, immutable | A malicious or compromised administrator, ransomware, account takeover | Restore from the vault into a new account and cluster |
| Weekly logical dump | `pg_dump` to S3 with Object Lock | Weekly | Set by the backup bucket's lifecycle policy | Schema-level or single-table loss; portability off Aurora | Import into any PostgreSQL-compatible engine |

The first tier protects against a mistake; the second protects against **someone who has taken over
the account**, which is a different threat and the one that ends companies. Vault Lock in compliance
mode is write-once, read-many (WORM): once written, that copy cannot be deleted by anyone, including
an account administrator, including AWS support, for the retention period.

**Restore testing.** A monthly automated job restores the latest snapshot into an isolated account,
runs a schema and row-count validation, records the elapsed time, and alarms on failure. Untested
backups are not backups, and the elapsed time from this job is where the real recovery time objective
(RTO) number comes from, not a guess.

**Deletion safety.** `deletion_protection = true` on every cluster, a service control policy denying
backup-vault and AWS Key Management Service (KMS) key deletion inside the production organizational
unit outside the pipeline role, and a final snapshot taken automatically on any deletion that does
proceed.

**If it happens.** The response to a deleted production database branches on cause.

| Step | Accidental deletion or bad deploy | Account or credential compromise |
|---|---|---|
| 1. Detect | Restore-testing alarm or application errors surface the loss | Same, plus a GuardDuty or CloudTrail anomaly alert on the compromised identity |
| 2. Contain | Revoke the deploying pipeline's credentials if a bad migration caused it | Revoke the compromised session or role immediately |
| 3. Restore | Point-in-time recovery clones Aurora to a new cluster at the timestamp before the loss | Restore from the vault-locked AWS Backup copy in the separate account — the production account's own backups may be gone too |
| 4. Validate | Schema and row-count check, the same validation the monthly drill runs | Same |
| 5. Cut over | Re-point Amazon RDS Proxy at the restored cluster; verify the application against it | Same, plus rotate every credential the compromised identity could reach |
| 6. Communicate | Incident note to the team; customer notice if user data was lost | Same, plus the breach-notification path in §5 Security and Data Protection |

---

## High availability

High availability keeps the service running when a component or an Availability Zone fails inside
one region; disaster recovery, below, is a different failure domain entirely.

> **Well-Architected pillars.** Reliability · Operational Excellence

- Aurora's storage layer keeps six copies of the data across three Availability Zones; losing one AZ
  loses no data and requires no restore.
- Production runs a writer and at least one reader in a **different Availability Zone**. Automatic
  failover promotes the reader, typically in under 30 seconds; the cluster endpoint follows the
  promotion, so the application's connection string never changes.
- Read traffic goes to the reader endpoint, write traffic to the writer. This places one constraint
  on the application: a read served from the reader can be milliseconds stale, so any read-after-write
  path — reading a value written earlier in the same request — must target the writer endpoint, not
  the reader.
- HA at the database is wasted if the application panics during the gap. Innovate Inc.'s Flask
  application makes it real with connection retry using exponential backoff, short connection
  timeouts, a readiness probe that checks the database so Kubernetes stops routing traffic to a pod
  that cannot serve it, and idempotent write handling so a retried request is safe to repeat.
- Read scaling grows the same way later: up to fifteen readers, added through Aurora Auto Scaling on
  a load metric rather than a manual change — the growth roadmap in §8 covers the trigger.

---

## Disaster recovery

Disaster recovery (DR) is not HA under a different name. HA above keeps the service running through
a component or Availability Zone failure inside `us-east-1`; DR restores the service when the
region, the account, or the data itself is lost — a different failure domain, a different mechanism,
and a different cost.

> **Well-Architected pillars.** Reliability · Cost Optimization · Operational Excellence

**Aurora Global Database** replicates production's storage to `us-west-2` continuously, with typical
cross-region replication lag under one second and no compute load added to the primary. Managed
planned failover is used for drills; an unplanned promotion is a deliberate, documented decision,
because it can lose the last second of writes that had not yet replicated.

**Pilot light** covers everything else the running region needs: Terraform for the entire stack
exists and is applied to `us-west-2` on demand, Amazon ECR replicates images continuously, and Amazon
Route 53 health checks flip DNS once the secondary is promoted. The region is not running in the
meantime — that is the cost decision, and it is why recovery time is measured in tens of minutes
rather than seconds.

The table below states the recovery point objective (RPO — how much recent data a failure can cost)
and the RTO for every scenario this design plans for.

| Failure scenario | RPO | RTO | Mechanism |
|---|---|---|---|
| Pod or node loss | 0 | < 60 s | Multiple replicas, PDB, Karpenter replacement |
| Availability Zone loss | 0 | < 5 min | 3-AZ subnets, Aurora failover to reader in another AZ |
| Aurora writer failure | 0 | < 30 s | Automatic failover + RDS Proxy connection retention |
| Accidental table/row deletion | to the second | < 4 h | Aurora PITR / clone-and-extract |
| Region loss | **< 1 min** | **< 60 min** | Aurora Global Database + pilot-light Terraform apply + Route 53 failover |
| Ransomware / credential compromise | ≤ 24 h | < 24 h | Vault-locked cross-account backup copy, immutable |

**The runbook**, once a region-level disaster is declared: (1) confirm the primary region is
genuinely unreachable, not a transient issue; (2) promote the `us-west-2` Aurora Global Database
secondary to a standalone writable cluster; (3) apply the DR Terraform stack to bring up the
application tier in `us-west-2`; (4) run smoke tests against the promoted stack before it takes
traffic; (5) flip the Route 53 health-check failover record; (6) communicate status to the team and,
if warranted, to customers. Failback — returning to `us-east-1` once it recovers — re-establishes
Global Database replication in the opposite direction and reverses the same steps; a DR plan with no
way home is half a plan.

**DR drills** run quarterly, in a scheduled window, with the measured RTO recorded against the table
above. An untested DR plan has an unknown recovery time, and an unknown recovery time is not a plan.

This posture changes when the business cannot tolerate a 60-minute RTO — the next step is a warm
standby in `us-west-2`, and beyond that, active-active, a substantial increase deferred to the
growth roadmap in §8, not built now.

---

## Decision Records

The four decisions below carry the full argument for Innovate Inc.'s data tier: which database
platform runs PostgreSQL, how it scales and pools connections, why one backup mechanism is not
enough, and how the design survives losing an entire region. Each stands on its own, with a
plain-language justification a non-technical reader can follow without the rest of this document.

> **Well-Architected pillars.** Reliability · Security · Cost Optimization

### ADR-019 — Aurora PostgreSQL Over Self-Managed and RDS

| | |
|---|---|
| **Status** | Accepted |
| **Requirement** | R12, R14, R15 |
| **Pillars** | Reliability · Performance Efficiency · Cost Optimization |
| **Section** | §4.1 Recommendation and alternatives considered |

**Context.** Innovate Inc. stores sensitive user data in PostgreSQL, runs it with five engineers and
no database administrator, and expects to grow from a few hundred daily users to potentially
millions.

**Options considered.**

| Option | Strengths | Weaknesses | Verdict |
|---|---|---|---|
| Self-managed PostgreSQL on EC2 | Lowest sticker price; full control of every layer | The team owns patching, failover, and backup verification for its most sensitive data | Rejected — the failure mode is an untested backup, not a large bill |
| PostgreSQL in Kubernetes via an operator | One control plane for everything; genuinely good technology | Durability depends on the team's depth with storage classes and operator upgrades, which it lacks | Rejected — right for a team with dedicated platform engineers, which this is not |
| Amazon RDS for PostgreSQL, Multi-AZ | Managed backups and patching; cheaper than Aurora; adequate today | 60–120 s failover; no shared-storage read replicas; no managed cross-region path | Rejected — the right answer if budget were the only constraint |
| Amazon Aurora PostgreSQL, Serverless v2 | Sub-30-second failover, up to 15 shared-storage readers, storage grows automatically, near-idle cost floor | Higher unit price than RDS; less portable off AWS | **Chosen** |

**Decision.** Run PostgreSQL on Amazon Aurora PostgreSQL-Compatible Edition using Aurora Serverless
v2 instances, with a writer and one reader in separate Availability Zones, fronted by Amazon RDS
Proxy.

**Why this is the right choice for Innovate Inc.** The database is the one part of this system where
a mistake is permanent — a broken application redeploys in minutes, but lost customer data does not
come back. Aurora keeps six copies of the data across three buildings and takes over from a failed
server in under thirty seconds, unattended. It bills for capacity used, so it costs little today and
grows to millions without a migration. RDS works today but recovers in one to two minutes, not thirty
seconds, and cannot spread reads across many copies — exactly what growth needs.

**Consequences.**
- *Gains:* Sub-30-second failover; read scaling to fifteen replicas without re-architecture; a
  managed cross-region disaster-recovery path.
- *Accepts:* A higher per-unit price than RDS; a deeper AWS dependency, making a future provider
  move a migration, not a lift-and-shift.

**Cost impact.** Higher than RDS at equivalent capacity; low at launch since Serverless v2 scales to
a small floor. Indicative figure in §7 Cost Optimization.

**Revisit when.** A database administrator is hired, or sustained write throughput nears a single
writer's ceiling.

### ADR-020 — Aurora Serverless v2 With RDS Proxy Pooling

| | |
|---|---|
| **Status** | Accepted |
| **Requirement** | R12, R14, R20 |
| **Pillars** | Performance Efficiency · Reliability · Cost Optimization |
| **Section** | §4 Database |

**Context.** Innovate Inc. runs its Flask application as many pods, each opening its own PostgreSQL
connections, against a traffic pattern that is a few hundred users today and millions later.

**Options considered.**

| Option | Strengths | Weaknesses | Verdict |
|---|---|---|---|
| Provisioned Aurora instances, pods connect directly | Simplest connection model; nothing extra to operate | Capacity must be sized for peak and paid for at 3 a.m.; the pod fleet still exhausts PostgreSQL's native connection limit as it scales | Rejected |
| Serverless v2, pods connect directly | Capacity follows load automatically | The same connection-exhaustion problem remains, and connection count now spikes with capacity too | Rejected |
| Serverless v2 with a PgBouncer sidecar per pod | Cheaper and more configurable than a managed proxy | One more piece of software the team patches and debugs during an incident, replicated per pod | Rejected — becomes one more thing the team operates |
| Serverless v2 with Amazon RDS Proxy | Managed connection pooling, IAM database authentication, holds client connections open through a failover | A small additional hourly charge | **Chosen** |

**Decision.** Run Aurora on Serverless v2 capacity, routing every pod connection through Amazon RDS
Proxy `innovate-prod-aurora-pg-proxy`; no pod connects to Aurora directly.

**Why this is the right choice for Innovate Inc.** Two problems show up together as the product
grows: the database needs less capacity overnight than at noon, and dozens of running copies of the
application, each opening connections, would overwhelm it, the way too many people talking through
one doorway at once does. Serverless v2 solves the first by billing only for capacity used. RDS Proxy
solves the second by funneling those connections through one managed pool, and holding them open
through a database switch, so the app slows for a moment rather than erroring out.

**Consequences.**
- *Gains:* Capacity billed to actual use, not peak reservation; connections stay within PostgreSQL's
  limits regardless of pod count; failovers are smoothed rather than dropped.
- *Accepts:* RDS Proxy becomes the one path from every pod to the database — one more managed
  component the team depends on.

**Cost impact.** Modest; the proxy's charge is small next to the incident it prevents. See §7 Cost
Optimization.

**Revisit when.** Measured RDS Proxy spend exceeds an operated PgBouncer sidecar's cost, or
connections per pod fall low enough that pooling stops mattering.

### ADR-021 — A Three-Tier Backup Strategy, Not PITR Alone

| | |
|---|---|
| **Status** | Accepted |
| **Requirement** | R13 |
| **Pillars** | Reliability · Security |
| **Section** | §4.4 Backups |

**Context.** Innovate Inc. holds sensitive user data with no dedicated security staff. Aurora's
built-in backup protects against a mistake, but it lives under the same account and credentials as
production, so it does not protect against a threat where those credentials are the thing that
failed.

**Options considered.**

| Option | Strengths | Weaknesses | Verdict |
|---|---|---|---|
| Automated backups and PITR alone | Zero extra configuration; built into Aurora | Same account, same administrator credentials as production — an attacker or a rogue insider with account access can delete these too | Rejected |
| Automated backups plus a warm-standby reader only | Improves availability; needs zero extra backup configuration to add | A reader replicates every write, including a malicious or accidental delete, the moment it happens — it is not a backup | Rejected |
| Automated backups + a vaulted cross-account copy + a weekly logical dump | Vault Lock cannot be deleted by anyone, including a compromised account administrator; the logical dump adds portability and table-level restores | Three mechanisms to configure, monitor, and alarm instead of one | **Chosen** |

**Decision.** Run three backup tiers: Aurora's continuous backups with point-in-time recovery, a
daily AWS Backup copy vaulted in a separate account under Vault Lock, and a weekly logical dump to
Amazon S3.

**Why this is the right choice for Innovate Inc.** There are two different disasters, and one backup
does not cover both. An honest mistake — a bad deploy deleting rows — is fixed by rewinding to before
it happened. Someone taking over the account can delete everything reachable, including backups,
which is why the second copy sits in a separate, locked account that not even its own administrator
can erase before the retention period ends. One kind of backup protects the company from itself; the
other protects it from someone who has taken control.

**Consequences.**
- *Gains:* Protection against a mistake and, separately, a malicious administrator; a portable
  restore path independent of Aurora.
- *Accepts:* Three backup jobs to monitor, and a 90-day vault that cannot be shortened.

**Cost impact.** Modest — storage for a daily cross-account copy and a weekly dump.

**Revisit when.** A restore drill misses the recovery time objective above, or compliance mandates
longer than 90-day retention.

### ADR-022 — Pilot-Light Cross-Region Disaster Recovery

| | |
|---|---|
| **Status** | Accepted |
| **Requirement** | R15, R20 |
| **Pillars** | Reliability · Cost Optimization · Operational Excellence |
| **Section** | §4.6 Disaster recovery |

**Context.** Innovate Inc. must survive losing an entire AWS region, not only a single Availability
Zone, but is five engineers at a few hundred daily users today, and an always-on second region is a
real ongoing cost.

**Options considered.**

| Option | Strengths | Weaknesses | Verdict |
|---|---|---|---|
| Backup-and-restore only | Cheapest — no infrastructure runs in the second region | Recovery means rebuilding everything from a vaulted backup after the disaster is declared; recovery time objective (RTO) measured in hours, not minutes | Rejected — too slow given sensitive, customer-facing data |
| Warm standby | Infrastructure runs continuously at reduced size; faster recovery than pilot light | Adds continuous compute cost in the second region for capacity that sits idle unless a region is lost | Rejected for now — the cost is not yet justified by the traffic at stake |
| Pilot light — Aurora Global Database replicating continuously, application infrastructure defined but not running | Data is already in the second region before a disaster happens; the rest stands up from Terraform in tens of minutes | Recovery time objective is tens of minutes, not seconds, because compute is not pre-warmed | **Chosen** |

**Decision.** Replicate Aurora continuously to `us-west-2` with Aurora Global Database, keep the
application-tier Terraform stack ready but not running there, and fail over by promoting the
secondary and applying that stack.

**Why this is the right choice for Innovate Inc.** Losing an entire region is rare, but the company
trusts this system with real customer data. The expensive way to be ready is running a second full
copy around the clock; the cheap way is keeping the data continuously copied to a second location —
the part that cannot be rebuilt in an emergency — while the rest stays a ready-to-run plan, not a
running system. That costs almost nothing extra and still restores the business within about an
hour.

**Consequences.**
- *Gains:* Data already exists in a second region before any disaster; a drilled recovery path; no
  ongoing double compute bill.
- *Accepts:* Recovery takes tens of minutes, not seconds, since the application only starts once a
  disaster is declared.

**Cost impact.** Low relative to a warm standby — mainly replication and storage.

**Revisit when.** The business cannot tolerate a 60-minute RTO — likely once revenue or a contract
makes an hour of downtime unacceptable. The next step is a warm standby, not active-active.
