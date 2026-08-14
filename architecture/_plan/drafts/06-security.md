## Security model

Security here does not audit the design from the outside; it is a property already built into §1
through §4 — service control policies, private subnets, Pod Security Admission, image signing,
encryption at rest. We state the operating assumption behind every one of those controls plainly:
any single control eventually fails, so nothing here is load-bearing on its own.

> **Well-Architected pillars.** Security · Reliability · Operational Excellence

| Layer | Primary controls | Protects | Detailed in |
|---|---|---|---|
| Organization | Service control policies, organizational unit (OU) guardrails, Control Tower | All tiers | §1 Cloud Environment Structure |
| Human identity | AWS Identity and Access Management (IAM) Identity Center, multi-factor authentication (MFA), permission sets, time-boxed production access | All tiers | §1, and below |
| Network | Private subnets, security groups, `NetworkPolicy`, AWS Web Application Firewall (WAF), no public data plane | Presentation tier; presentation–application and application–data boundaries | §2 Network Design |
| Workload identity | Amazon EKS Pod Identity, one role per service account | Application tier | §3 Compute Platform |
| Workload runtime | Pod Security Admission `restricted`, non-root, read-only root filesystem, `seccomp` | Application tier | §3 Compute Platform |
| Supply chain | Software bill of materials (SBOM), image signing, Kyverno admission verification, dependency and infrastructure-as-code (IaC) scanning | Application tier | §3 Compute Platform |
| Data at rest | Customer-managed encryption keys per environment and data class | Data tier | §4 Database, and below |
| Data in transit | TLS at the edge and on every internal hop, `rds.force_ssl` | Every tier boundary | §2, §4 Database |
| Secrets | Secrets Manager with rotation, External Secrets Operator, never in images or git | Application tier | below |
| Detection | GuardDuty, Security Hub, Config, Inspector, Macie, Access Analyzer | All tiers | below |
| Audit | Organization CloudTrail to an immutable Log Archive account | All tiers | below |
| Response | Runbooks, isolation procedure, break-glass, drills | All tiers | below |

We deliberately exclude a service mesh and its mutual TLS from this layer set at launch —
`NetworkPolicy` and TLS-in-transit already close the gap it would close at today's service count
(ADR-025).

---

## Identity and access management

Three identity planes cover every actor that touches this system, each with its own mechanism:
humans authenticate through IAM Identity Center and receive short-lived, federated sessions (§1
Cloud Environment Structure); workloads authenticate through EKS Pod Identity, one role scoped to
one Kubernetes service account (§3 Compute Platform); and CI/CD authenticates through GitHub
OpenID Connect (OIDC), one role scoped to one repository and branch (§3.9 Deployment — CI/CD and
GitOps). The invariant that produces is worth stating on its own: **there is no long-lived
credential anywhere in this system**, human or machine, so there is nothing durable for an
attacker to steal.

> **Well-Architected pillars.** Security · Operational Excellence

Least privilege is mechanized, not asserted. Every permission set — `InnovateAdmin`,
`InnovatePlatformEngineer`, `InnovateDeveloper`, `InnovateReadOnly`, `InnovateBreakGlass` — starts
from an AWS managed policy and is narrowed using IAM Access Analyzer's unused-access findings and
CloudTrail evidence of what a role actually calls, not what it might. A permission boundary on
every role able to create roles closes the obvious path to privilege escalation through IAM itself.

Production access is read-only by default; an elevated `InnovatePlatformEngineer` or
`InnovateAdmin` session in `innovate-prod` is requested, time-boxed, and logged end to end. At a
five-person team this is a lightweight approval, not a ticketing bureaucracy — the reason to build
it now, rather than after the first compliance audit asks for it, is that retrofitting an access
model onto live production habits is far more disruptive. `InnovateBreakGlass` covers what
Identity Center itself cannot: two sealed, hardware-MFA-protected root-credential procedures,
alarmed the instant either is used, tested twice a year.

---

## Data protection

Every other section treats "secure" as an adjective; this one is where sensitive user data meets a
concrete classification, a key, and a deletion path.

> **Well-Architected pillars.** Security · Reliability · Operational Excellence

| Classification | Example at Innovate Inc. | Controls required |
|---|---|---|
| `public` | Marketing site copy, published API documentation | Standard integrity controls only |
| `internal` | Architecture diagrams, non-production configuration | Access limited to authenticated employees |
| `confidential` | Aggregated usage analytics, billing summaries | Encryption at rest and in transit, access logged |
| `restricted` | User account records, personally identifiable information (PII) | Customer-managed key, IAM database authentication, no non-production copies, Macie scanning |

Personally identifiable information is always `restricted`, and lives only inside Aurora and its
vaulted backups (§4 Database) — never in a log line, a support ticket, or a spreadsheet. Every
resource carries the mandatory tag set — `Environment`, `Application` (`innovate-web`), `Owner`,
`CostCenter`, `DataClassification`, `ManagedBy` (`terraform`), `Compliance` — enforced by AWS
Organizations tag policies and a Config rule, so classification is queryable at the account level.

**Encryption at rest.** We encrypt data at rest with a customer-managed AWS Key Management Service
(KMS) key per environment *and* per data class — `alias/innovate-<env>-eks`, `-rds`, `-s3`,
`-secrets`, `-ebs`, `-backup` — rather than the AWS-managed keys every service uses by default
(ADR-023). A customer-managed key policy is an authorization layer independent of IAM: an
over-broad IAM policy alone cannot reach the data behind it, key usage is a distinct, visible
CloudTrail event, and a key can be disabled to cut off access to everything it protects within
minutes. Keys rotate annually.

**Encryption in transit** covers every hop, including inside the virtual private cloud (VPC) —
Application Load Balancer (ALB) to pod, pod to Aurora (§2 Network Design, §4 Database). "Internal
traffic is trusted" is not a position this design takes: a network boundary stops an outsider, not
an insider already past it.

**Secrets.** We store secrets in AWS Secrets Manager, with automatic rotation for database
credentials, projected into Kubernetes as native `Secret` objects by the External Secrets
Operator, and encrypted at rest with the cluster's own KMS key from there on. The negative rules
are enforced, not requested: no secret is ever baked into a container image, committed to an
environment file in git, or written unencrypted into Terraform state. `gitleaks`, run on every pull
request (§3.9 Deployment — CI/CD and GitOps), is the mechanism that makes the git rule real.

**Data lifecycle** follows a retention schedule set by classification, logs move to S3 Glacier on a
lifecycle policy, and there is a documented deletion path for a user's own data. That path collides
with the vaulted, immutable backups in §4.4 Backups on purpose: a deletion request removes the
record from the live database and every subsequent backup, but a vaulted copy taken before the
request cannot be altered before its retention window ends. The resolution is a documented
retention window with deletion propagating on expiry — an honest limit, not a gap left unnoticed.

**Isolation between environments** keeps that same data out of reach where it should never be:
development and staging run masked or synthetic seed data only (§4 Database), no pipeline copies a
production snapshot downstream, and Macie scans every data bucket for PII that reaches a bucket it
was never meant to.

---

## Detection and monitoring

Coverage means every AWS-native detection service pointed at every account, but coverage alone is
not a posture — it is a stream of findings nobody reads.

> **Well-Architected pillars.** Security · Operational Excellence

| Service | Scope | What it catches |
|---|---|---|
| GuardDuty (incl. EKS Runtime Monitoring, Amazon Relational Database Service (RDS) Protection, S3 Protection, Malware Protection) | Every account | Anomalous API calls, compromised credentials, container and database runtime threats, malware in uploaded objects |
| Security Hub (AWS Foundational Security Best Practices (FSBP), CIS 2.0, PCI DSS standards) | Every account | Configuration drift from security best practice, aggregated into one score |
| AWS Config conformance packs | Every account | Resources drifting out of compliance after creation |
| Inspector | Amazon Elastic Compute Cloud (EC2), Amazon Elastic Container Registry (ECR), Lambda | Known software vulnerabilities in instances, container images, and functions |
| Macie | S3 data buckets | Sensitive or PII data reaching a bucket it should not be in |
| IAM Access Analyzer | Every account | External access grants and unused permissions |

Every finding aggregates into `innovate-security-tooling`, the delegated administrator (§1 Cloud
Environment Structure), so the team checks one console, not seven.

**Detection without routing is decoration.** A finding above a defined severity threshold pages a
human through the alerting path in §6 Observability and Operations; everything else lands in a
weekly review, not a void. Every alert carries a runbook link, so the response does not depend on
whoever is on call improvising it from memory. A security information and event management (SIEM)
platform and a managed detection-and-response service are both deliberately not bought yet — five
engineers' worth of findings does not yet justify either; the trigger is a headcount or a volume a
weekly review can no longer absorb.

---

## Audit and logging

We deliver organization-wide CloudTrail — including data events on the sensitive S3 buckets — EKS
control-plane audit logs, VPC Flow Logs, ALB and CloudFront access logs, and database audit logs
(§4 Database) to `innovate-log-archive` (§1 Cloud Environment Structure), into S3 with **Object
Lock in compliance mode** and 400-day retention (ADR-024).

> **Well-Architected pillars.** Security · Reliability

That buys one property worth stating plainly: an attacker who fully compromises `innovate-prod`
still cannot alter or delete the record of what they did, because the workload accounts hold no
delete permission on the sink that stores it — the evidence survives the account that generated
it. Athena queries the archive directly during an investigation, with no restore step in the way.

---

## Application-layer security

The application itself is not this document's to design, so this section states the boundary
briefly rather than the implementation.

> **Well-Architected pillars.** Security · Operational Excellence

End users authenticate through a managed identity provider — Amazon Cognito, or Innovate Inc.'s own
provider if it already has one — issuing short-lived JSON Web Tokens (JWTs); authorization is
enforced server-side on every request, never trusted from the single-page application (SPA) alone.
Parameterized queries and input validation are the primary defense against SQL injection; AWS WAF
(§2 Network Design) is the backstop, not the control, because a backstop that fails open is no
substitute for code that never builds the query wrong. A CloudFront response-headers policy sets
security headers on every response, and rate limiting applies per user identity as well as per
source IP. The OWASP Top 10 is the review checklist the application team owns from here.

---

## Compliance and privacy posture

Proportionate here means a paragraph, not a chapter — the honest position stated once rather than
implied by omission.

> **Well-Architected pillars.** Security · Operational Excellence

Innovate Inc.'s data-protection posture is aligned to the General Data Protection Regulation
(GDPR): encryption and least privilege as already described, data minimization, a documented
lawful basis for processing user data, a defined retention schedule, a subject-access and deletion
path (§5.3 Data protection), the `eu-west-1` region reserved for a future data-residency
requirement (§2 Network Design), an AWS Data Processing Addendum, and a sub-processor register kept
current as vendors change. Readiness for System and Organization Controls 2 (SOC 2) draws on
evidence this architecture already generates: an immutable audit log, a full change history in
git, periodic access reviews from Identity Center, and continuous AWS Config compliance checking.

The honest position, stated directly: this design makes a compliance audit **achievable**. It does
not, by itself, make Innovate Inc. compliant. The gap is process — written policies, staff
training, vendor security review, and an incident-response plan that has actually been rehearsed,
not merely written.

---

## Incident response

A skeleton runbook, not a comprehensive playbook, because the size that matters here is what a
five-person team can actually execute under pressure.

> **Well-Architected pillars.** Operational Excellence · Security · Reliability

**Detect** — a GuardDuty finding or an alarm crosses the paging threshold above. **Triage** — the
on-call engineer declares a severity within minutes, not after investigation completes.
**Contain** — the response specific to this architecture: isolate the workload with a deny-all
`NetworkPolicy`, revoke the affected pod's Pod Identity role, snapshot the instance or volume for
forensics before terminating anything, and rotate every credential the incident could have reached.
**Eradicate** the cause. **Recover** from a known-good image digest (§3.8 Container registry) or a
tested backup restore (§4.4 Backups), never from an assumption that the running state is
trustworthy. **Review** — blameless, written, shared with the team.

This architecture gives a responder three advantages: immutable image digests make "what was
actually running" answerable, not a guess; account boundaries (§1 Cloud Environment Structure)
bound how far a search has to go; and the immutable log archive above means the evidence survives
the incident that produced it. Tabletop exercises run twice a year, and an on-call rotation is a
real, ongoing cost for a small team — worth naming rather than treating as free.

---

## Decision Records

The three decisions below carry the full argument for Innovate Inc.'s security posture: why keys
are customer-managed rather than AWS-managed, why the audit trail lives outside every account it
describes, and why a service mesh is deliberately not part of the day-1 design. Each stands on its
own, with a plain-language justification a non-technical reader can follow without the rest of this
document.

> **Well-Architected pillars.** Security · Reliability · Operational Excellence

### ADR-023 — Customer-Managed KMS Keys Rather Than AWS-Managed Keys

| | |
|---|---|
| **Status** | Accepted |
| **Requirement** | R21 |
| **Pillars** | Security · Operational Excellence |
| **Section** | §5.3 Data protection |

**Context.** Innovate Inc. encrypts several data categories — cluster secrets, database, object
storage, secrets, block storage, backups — holding sensitive user data, with no dedicated security
engineer to manage key infrastructure by hand.

**Options considered.**

| Option | Strengths | Weaknesses | Verdict |
|---|---|---|---|
| AWS-managed keys (the default for every service) | No configuration; no added cost; no key policy to maintain | IAM is the only authorization layer — any policy broad enough to reach the resource can decrypt it; usage is not separately visible; access cannot be revoked without touching the IAM policy itself | Rejected — free, but gives up an independent control |
| Customer-managed KMS keys, one per environment and data class | An independent key policy is a second required authorization gate; usage is a distinct, auditable CloudTrail event; a key can be disabled to cut off access to everything it protects within minutes | A small per-key monthly charge and a key policy to define per environment and data class | **Chosen** |

**Decision.** Every data class in every environment is encrypted under its own customer-managed
KMS key — `alias/innovate-<env>-eks`, `-rds`, `-s3`, `-secrets`, `-ebs`, `-backup` — rotated
annually.

**Why this is the right choice for Innovate Inc.** Think of the default option as one lock on the
front door: if someone gets a copy of that key — a permission granted too broadly — they can open
everything inside. A customer-managed key is a second lock on the room holding the valuables,
needing its own key. It costs a few dollars a month. In exchange, a mistaken permission alone
cannot reach customer data, every use is visible, and something going wrong means locking one
room, not the house.

**Consequences.**
- *Gains:* An IAM mistake alone cannot decrypt protected data; key usage is auditable; a whole
  data class is revocable in minutes.
- *Accepts:* A misconfigured or deleted key can lock the team out of its own data — a real,
  self-inflicted denial-of-access risk a single-layer model does not carry.

**Cost impact.** Indicative — a small per-key monthly charge, one key per environment and data
class; see the AWS Pricing Calculator for current rates.

**Revisit when.** Compliance mandates externally held or hardware-backed key material the platform
cannot provide.

### ADR-024 — Centralized Immutable Logging in a Separate Account

| | |
|---|---|
| **Status** | Accepted |
| **Requirement** | R21 |
| **Pillars** | Security · Reliability |
| **Section** | §5.4 Detection, audit and logging |

**Context.** Innovate Inc. needs an audit trail an investigation can trust, but has no dedicated
security function to review every account's logs by hand — the guarantee must be structural, not
procedural, and survive a full compromise of production.

**Options considered.**

| Option | Strengths | Weaknesses | Verdict |
|---|---|---|---|
| Logs stored within each workload account | Simplest to set up; no cross-account delivery to configure | An attacker or a rogue administrator who fully compromises an account can also delete or edit the record of what they did in that same account | Rejected — the audit trail and the thing being audited share one failure domain |
| Centralized logging in a separate account, standard S3 (no Object Lock) | Removes the same-account risk above; one place to query everything | An administrator of the log account itself, or an attacker who reaches it, can still delete the evidence | Rejected — moves the risk, does not remove it |
| Centralized logging in `innovate-log-archive`, S3 Object Lock in compliance mode | No identity, including a log-archive administrator, can delete or alter a locked object before its retention expires; workload accounts hold no delete permission on the sink at all | A 400-day retention commitment and Object Lock's own irreversibility during that window | **Chosen** |

**Decision.** Every log source — organization CloudTrail, EKS control-plane logs, VPC Flow Logs,
load-balancer and CloudFront access logs, database audit logs — delivers to `innovate-log-archive`,
written to S3 with Object Lock in compliance mode and 400-day retention.

**Why this is the right choice for Innovate Inc.** If someone breaks into the production account,
they can do real damage — but they cannot make the record of what they did disappear. The
recordings live in a separate, locked room production has no key to, and not even an administrator
of that room can erase them before the retention period ends. That is what makes it possible to
know exactly what was taken — often the difference between a contained incident and an
unanswerable one.

**Consequences.**
- *Gains:* A tamper-evident audit trail that survives a full production compromise; one place to
  investigate instead of seven.
- *Accepts:* A 400-day commitment that cannot be shortened, and a real dependency on
  `innovate-log-archive`'s availability for investigations.

**Cost impact.** Indicative — S3 storage for 400 days of logs across seven accounts; folded into
§7 Cost Optimization.

**Revisit when.** A compliance requirement mandates a longer or shorter retention window than 400
days.

### ADR-025 — Deferring a Service Mesh and Its Mutual TLS

| | |
|---|---|
| **Status** | Accepted |
| **Requirement** | R4, R21 |
| **Pillars** | Security · Operational Excellence · Cost Optimization |
| **Section** | §5.1 Security model |

**Context.** Innovate Inc.'s application tier is one Flask API and one worker fleet (§3 Compute
Platform); traffic is already encrypted in transit (§2 Network Design), and the team has no
platform engineer to operate additional infrastructure.

**Options considered.**

| Option | Strengths | Weaknesses | Verdict |
|---|---|---|---|
| Adopt a service mesh (e.g., Istio, Linkerd) now, with mutual TLS between every workload | Cryptographic service identity in addition to network identity; uniform mTLS regardless of service count; rich per-hop traffic policy | A sidecar proxy per pod, its own control plane, and a new failure mode to operate and debug, for a service count where `NetworkPolicy` and TLS-in-transit already close the gap it would close | Rejected for day 1 — real operational cost for marginal security gain at this scale |
| No service mesh; rely on `NetworkPolicy` plus TLS-in-transit only | Nothing new to operate; existing controls already stop unencrypted or unauthorized east-west traffic | Service identity is enforced by IAM role and network policy, not a cryptographic certificate per hop | **Chosen** |

**Decision.** Innovate Inc. does not adopt a service mesh or mutual TLS at launch; east-west
traffic is protected by default-deny `NetworkPolicy` (§3 Compute Platform) and TLS on every hop
(§2 Network Design).

**Why this is the right choice for Innovate Inc.** A service mesh is a second network layered on
top of the first, built to keep many services honest with each other — valuable once there are
many. Innovate Inc. today runs one API and one worker service, already isolated by rules about who
can talk to whom and already encrypted point to point. A mesh means running a sidecar proxy next
to every pod and a second control plane — real engineering hours for a team with no platform
engineer, spent on a protection the existing rules already give for free.

**Consequences.**
- *Gains:* No sidecar infrastructure to operate at a size where it earns little.
- *Accepts:* Authorization rests on network policy and IAM, not a cryptographic identity per
  request; per-hop traffic-shaping is unavailable.

**Cost impact.** None — this is a decision not to add infrastructure.

**Revisit when.** The application tier grows past a handful of services, or compliance mandates
cryptographic proof of service identity per hop.
