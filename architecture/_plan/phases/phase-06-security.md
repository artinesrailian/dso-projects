# Phase 06 — Security & Data Protection

> Answers requirements **R21** and the cross-cutting half of **R4**. The brief says "sensitive user
> data is handled, requiring strong security measures" — this section is where that is taken
> seriously.
> Read [`../AGENT-PROTOCOL.md`](../AGENT-PROTOCOL.md), [`../brief.md`](../brief.md),
> [`../contract.md`](../contract.md), [`../decision-register.md`](../decision-register.md),
> [`../well-architected.md`](../well-architected.md), and [`../style-guide.md`](../style-guide.md)
> first.

---

## Goal

Security appears in every other section — SCPs in Phase 01, network layers in Phase 02, Pod Security
Admission in Phase 03, image signing in Phase 04, encryption in Phase 05. This phase does two things
those cannot:

1. **Presents the whole posture as one coherent defence-in-depth story**, so a reviewer can see the
   layers rather than finding them scattered.
2. **Covers what has no other home**: data classification and lifecycle, key management, detection
   and response, privacy and compliance posture, and the incident-response path.

The hard constraint: **do not re-explain what another phase already covers.** Reference it in one
clause and move on. This section adds depth, not repetition.

---

## Dependencies

Phase 00 must be `done`. Read whichever of `drafts/01`–`drafts/05` exist so you can reference rather
than duplicate.

## Inputs

| File | Use it for |
|---|---|
| `_plan/decision-register.md` | ADR template and your reserved ADR block |
| `_plan/well-architected.md` | Pillar tagging convention and what each pillar demands |
| `_plan/contract.md` **§9** | The locked security baseline, KMS aliases, permission sets, tag set — **copy exactly** |
| `_plan/contract.md` §4 | SCPs and the Security Tooling / Log Archive accounts |
| `_plan/rubric.md` §2.E | The security scoring dimension |
| Existing drafts 01–05 | To reference, not repeat |

## Files you own

- `_plan/drafts/06-security.md` — create
- `_plan/STATE.md` — update
- `_plan/contract.md` §12 — append only if you invent a name

## Word budget

**~1 400 words** (±20%) for the body, excluding tables, plus **3 ADRs** (ADR-023 – ADR-025).

## Two requirements that apply to every section you write

1. **Pillar line.** Every `##` section closes its opening paragraph with
   `> **Well-Architected pillars.** …` carrying 2–4 pillars. See `well-architected.md` §2.
2. **Justification.** Inline, every decision follows decision → why → what it beat → what it costs.
   The significant ones are recorded again as ADRs at the end of the draft. See
   `decision-register.md`.

## The framing that makes this section work

Security is not a chapter that audits the design after the fact — Phases 01 through 05 already made
security decisions inside their own subject matter, which is exactly right. This section's job is to
show that those scattered controls form **one coherent posture** and to own the parts that have no
other home. If you find yourself re-explaining something another phase covered, you have drifted:
reference it in a clause and spend the words on data classification, key management, detection,
audit, compliance, and response.

The three-tier model gives you a useful structure for the defence-in-depth table: state which
controls protect each tier, and which protect the boundaries between them.

---

## Content specification

### `## Security model` (~150 words + the layer table)

Open with the operating assumption, stated plainly: the design assumes any single control will
eventually fail, so no control is load-bearing on its own. Then the defence-in-depth summary table —
one row per layer, with a pointer to where it is detailed:

| Layer | Primary controls | Detailed in |
|---|---|---|
| Organization | Service control policies, OU guardrails, Control Tower | §1 |
| Human identity | IAM Identity Center, MFA, permission sets, time-boxed production access | §1, here |
| Network | Private subnets, security groups, NetworkPolicy, WAF, no public data plane | §2 |
| Workload identity | EKS Pod Identity, one role per service account | §3 |
| Workload runtime | Pod Security Admission `restricted`, non-root, read-only rootfs, seccomp | §3 |
| Supply chain | SBOM, image signing, Kyverno admission verification, dependency and IaC scanning | §3 |
| Data at rest | Customer-managed KMS keys per environment and data class | here, §4 |
| Data in transit | TLS at the edge and on every internal hop, `rds.force_ssl` | §2, §4 |
| Secrets | Secrets Manager with rotation, External Secrets Operator, never in images or git | here |
| Detection | GuardDuty, Security Hub, Config, Inspector, Macie, Access Analyzer | here |
| Audit | Organization CloudTrail to an immutable Log Archive account | here |
| Response | Runbooks, isolation procedure, break-glass, drills | here |

### `## Identity and access management` (~200 words)

Only what Phase 01 did not cover:

- **Three identity planes, three mechanisms**: humans get federated short-lived sessions through IAM
  Identity Center; workloads get EKS Pod Identity roles scoped to a single service account;
  CI/CD gets GitHub OIDC roles scoped to a repository and branch. State the invariant it produces:
  **there is no long-lived credential anywhere in the system**, so there is nothing durable to steal.
- **Least privilege in practice**, not as a slogan: start from AWS managed policies, then narrow using
  IAM Access Analyzer's unused-access findings and CloudTrail evidence. Permission boundaries on any
  role that can create roles, so privilege escalation via IAM is closed.
- **Production access model**: read-only by default, elevated access requested and time-boxed, every
  session logged. Note that at a five-person startup this is a lightweight process, and that the
  reason to build it now is that retrofitting it after a compliance audit is far more disruptive.
- **Break-glass**: two root-credential procedures, hardware MFA, sealed, alarmed on use, tested twice
  a year.

### `## Data protection` (~300 words + table) — **the core of this section**

- **Data classification.** Table of the four levels from `contract.md` §9 — `public`, `internal`,
  `confidential`, `restricted` — with an example of Innovate Inc. data at each level and the controls
  each level requires. Personally identifiable information is `restricted` and lives only in Aurora
  and the vaulted backups.
- **Encryption at rest.** Customer-managed KMS keys, one per environment *and* per data class
  (`alias/innovate-<env>-eks`, `-rds`, `-s3`, `-secrets`, `-ebs`, `-backup`). Explain why
  customer-managed rather than AWS-managed keys: key policies become a second, independent
  authorization layer that an over-broad IAM policy cannot bypass, key usage is visible in CloudTrail,
  and a key can be disabled to revoke access to data instantly. Annual rotation enabled.
- **Encryption in transit** everywhere, including inside the VPC. One sentence on why "internal
  traffic is trusted" is not a position anyone should hold.
- **Secrets.** AWS Secrets Manager as the store, automatic rotation for database credentials,
  External Secrets Operator projecting them into Kubernetes Secrets, and Kubernetes secrets encrypted
  at rest with the cluster KMS key. State the negative rules explicitly: no secrets in container
  images, no secrets in environment files in git, no secrets in Terraform state that is not itself
  encrypted and access-controlled. Add `gitleaks` in CI as the enforcement mechanism.
- **Data lifecycle**: retention schedule per classification, S3 lifecycle to Glacier for logs,
  documented deletion path for user data, and backups as the deliberate exception to deletion — note
  the tension between "delete on request" and immutable vaulted backups, and how it is resolved
  (documented retention window plus deletion propagation on expiry). Naming that tension is a
  credibility signal.
- **Tenant and environment isolation for data**: masked or synthetic data in non-production, no
  production database copies downstream, and Macie scanning the data buckets for PII that has escaped
  into the wrong place.

### `## Detection and monitoring` (~200 words + table)

Table: Service | Scope | What it catches. Cover every item in `contract.md` §9's detection row —
GuardDuty (including EKS Runtime Monitoring, RDS Protection, S3 Protection, Malware Protection),
Security Hub with the FSBP, CIS, and PCI standards, AWS Config conformance packs, Inspector, Macie,
and IAM Access Analyzer. All findings aggregate into `innovate-security-tooling` as delegated
administrator.

Then the point that matters more than the product list: **detection without routing is decoration.**
Findings above a severity threshold page a human; the rest land in a weekly review. Every alert has a
runbook link. Say what is deliberately *not* bought yet (a SIEM, a managed detection and response
service) and what triggers buying it.

### `## Audit and logging` (~120 words)

Organization-wide CloudTrail including data events on the sensitive buckets, EKS control-plane audit
logs, VPC Flow Logs, ALB and CloudFront access logs, and database audit logs — all delivered to the
`innovate-log-archive` account, into S3 with **Object Lock in compliance mode** and a 400-day
retention. The property this buys, stated explicitly: an attacker who fully compromises the
production account still cannot alter or delete the record of what they did, because the workload
accounts have no delete permission on the sink. Athena over the archive for investigation.

### `## Application-layer security` (~120 words)

Brief, because the application is not this document's to design. End-user authentication with a
managed identity provider (Amazon Cognito, or the client's existing IdP) issuing short-lived JWTs;
authorization enforced server-side on every request, never in the SPA; input validation and
parameterised queries as the primary SQL-injection defence with WAF as the backstop rather than the
control; security headers set by a CloudFront response-headers policy; and rate limiting per user
identity in addition to per IP. One sentence flagging OWASP Top 10 as the review checklist for the
application team.

### `## Compliance and privacy posture` (~150 words)

Proportionate — a paragraph, not a chapter. GDPR alignment (lawful basis, data minimisation, the
subject-access and deletion paths, the EU region reserved in the CIDR plan, an AWS Data Processing
Addendum, sub-processor register); SOC 2 readiness in terms of the evidence this architecture
generates automatically — immutable audit logs, change history in Git, access reviews from Identity
Center, automated Config compliance. State the honest position: this design makes an audit
*achievable*, it does not make the company compliant, and the gap is process — policies, training,
vendor review, and an incident-response plan that has been rehearsed.

### `## Incident response` (~150 words)

A short numbered runbook skeleton: detect (GuardDuty finding or alarm), triage and declare severity,
**contain** (isolate the workload with a deny-all NetworkPolicy, revoke the pod's IAM role, snapshot
for forensics before terminating, rotate the affected credentials), eradicate, recover from a known
good digest or a tested restore, and a blameless post-incident review. Note the specific advantages
this architecture gives a responder: immutable image digests make "what was running" answerable,
account boundaries bound the search, and the immutable log archive means the evidence survives.
Mention tabletop exercises twice a year and that the on-call rotation is a real commitment for a
small team — an honest operational cost, worth naming.

---

## Decision Records — ADR-023 to ADR-025

End the draft with `## Decision Records` containing 3 ADRs from your reserved block, using the
exact template in `decision-register.md`. They must cover:

- **ADR-023 — Customer-managed KMS keys rather than AWS-managed keys.** The alternative is free and
  simpler, so argue it fairly. Deciding factors: an independent key-policy authorization layer,
  CloudTrail visibility of key usage, and the ability to revoke access to data instantly.
- **ADR-024 — Centralised immutable logging in a separate account with Object Lock.** Against logging
  to each workload account, which is simpler and cheaper. The deciding factor is that an attacker who
  fully compromises production must still be unable to erase the record.
- **ADR-025 — Deferring a service mesh and its mutual TLS.** The honest security deferral, with the
  trigger for revisiting it. Recording a decision *not* to do something, with its cost stated, is a
  strong signal to a reviewer.

The plain-language field on the immutable-logging ADR should land the point simply: if someone breaks
in, they can do damage, but they cannot make the record of what they did disappear — which is what
makes it possible to know afterwards exactly what was taken.

---

## Acceptance criteria

- [ ] File is `_plan/drafts/06-security.md`, 1 150–1 700 words excluding tables and ADRs.
- [ ] The defence-in-depth table covers at least ten layers and points each to where it is detailed.
- [ ] Every `##` section closes its opening paragraph with a pillar line carrying 2–4 pillars.
- [ ] The defence-in-depth treatment is organised so a reader can see which controls protect each of
      the three tiers and which protect the boundaries between them.
- [ ] `## Decision Records` present with 3 ADRs from ADR-023 – ADR-025, full template, no fields
      missing; each has a fairly-argued rejected alternative, a plain-language field a non-engineer
      can read, a real *Accepts* downside, and an observable *Revisit when* trigger.
- [ ] Content already covered by Phases 01–05 is **referenced, not repeated** — no paragraph
      re-explains SCPs, NetworkPolicy, or Aurora encryption at length.
- [ ] Data classification has four levels with Innovate Inc. examples and per-level controls.
- [ ] Customer-managed KMS keys are justified *against* AWS-managed keys, with a real reason.
- [ ] The "no long-lived credentials anywhere" invariant is stated with all three identity planes.
- [ ] Secrets handling names the store, the rotation, the projection mechanism, and the negative
      rules — plus the CI control that enforces them.
- [ ] The immutable log archive property is stated: a fully compromised production account cannot
      erase the audit trail.
- [ ] Detection covers routing and response, not just a product list.
- [ ] The GDPR deletion vs. immutable-backup tension is named and resolved.
- [ ] An incident-response runbook is present with a containment step that is specific to this
      architecture.
- [ ] KMS aliases, permission set names, and the mandatory tag set match `contract.md` §9 exactly.
- [ ] No `TODO`/`TBD`; no banned words; no emoji.
- [ ] `STATE.md` updated.

## Common failure modes

| Failure | Avoid it by |
|---|---|
| Repeating Phases 01–05 with the word "security" attached | Reference in a clause; spend the words on what has no other home. |
| A list of AWS security product names | Every control says what it catches or prevents. |
| Compliance theatre — pages of GDPR articles | One honest paragraph on what the architecture gives you and what it does not. |
| Claiming the design makes the company "compliant" | It makes an audit achievable. Say that. |
| No incident response at all | Detection with no response is half a posture. |
| Ignoring the deletion/backup tension | Naming a genuine conflict is a credibility signal. |

---

## Agent prompt

```text
You are executing Phase 06 of the Innovate Inc. architecture design plan: Security & Data Protection.

Working directory boundary: architecture/ ONLY. Never read or write
terraform/, .claude/, or anything above architecture/. terraform/ belongs to a
different assignment that another agent may be editing right now.

Read in full, in order:
  architecture/_plan/AGENT-PROTOCOL.md
  architecture/_plan/brief.md
  architecture/_plan/contract.md      (§9 is your primary source)
  architecture/_plan/decision-register.md
  architecture/_plan/well-architected.md
  architecture/_plan/style-guide.md
  architecture/_plan/rubric.md
  architecture/_plan/phases/phase-06-security.md

Then read whichever of these exist, to reference rather than duplicate:
  architecture/_plan/drafts/00-scope.md through drafts/05-database.md

Do not read any other file. No repository-wide searches. No aws/kubectl/terraform/docker/helm.
No web browsing.

Write architecture/_plan/drafts/06-security.md following the content specification
exactly. Your hard constraint: do NOT re-explain what Phases 01-05 already cover — reference it in
one clause and spend your words on data classification, key management, detection, audit,
End the draft with a ## Decision Records section containing ADR-023 through ADR-025, using the exact
template in decision-register.md. Every ADR needs: an options table with at least one genuinely
reasonable rejected alternative argued fairly; a "Why this is the right choice for Innovate Inc."
field written in plain language for a non-engineer founder; an Accepts list naming a real
downside; and a Revisit when field naming an observable trigger.

Close every ## section's opening paragraph with a > **Well-Architected pillars.** line carrying
two to four pillars.

compliance posture, and incident response. Then verify every acceptance criterion line by line,
fix what fails, update STATE.md, report, and STOP. Do not begin Phase 07.
```
