# Decision Register — format, allocation, and required decisions

**STATUS: NORMATIVE.**

The client's brief uses the word **justify**. The reasoning behind each decision is not commentary on
the design — it *is* the deliverable. A reviewer who cannot find out *why* Aurora rather than RDS,
*why* seven accounts rather than one, *why* Spot instances for a production API, has not received an
architecture document; they have received a shopping list.

So every significant decision is recorded twice, on purpose:

1. **Inline**, in the body section where it belongs, argued in prose.
2. **Either as a numbered Architecture Decision Record (ADR)** in Appendix B, **or as a row** in the
   Summary of Key Decisions table (§10) — see the promotion rule in §2a below. Every decision gets one
   of the two; the nine most consequential get both a table row and a full ADR.

The duplication is deliberate and it is not padding. The inline prose carries a reader who is going
through the document in order; the register lets a reviewer scan the decisions that matter most, and
their reasoning, in two minutes without reading the whole body. They are written differently — see §3.

> **Amendment, 2026-08-14.** This file originally specified a full ADR for all 29 records phases
> 00–08 wrote. Appendix B in the graded deliverable now promotes only nine of them — see §2a. All 29
> records still exist, unchanged, in `_plan/drafts/00-scope.md` through `08-cost.md`; nothing already
> written was deleted. This changes what Phase 12 assembles into `README.md`, not what phases 00–08
> produced. Rationale: at 29 full records the appendix alone ran 5,500–7,500 words against a body of
> similar size, for a brief that asks for one README with justified decisions, not an audit-grade
> register. R26 ("every decision is justified... in language the client can follow") does not require
> a formal ADR per decision — inline prose plus a Summary of Key Decisions row satisfies it, and both
> survive for every decision either way.

---

## 1. The ADR format — copy this exactly

Every ADR uses this template. No fields omitted, no fields added.

```markdown
### ADR-0NN — <Short decision title, no more than 8 words>

| | |
|---|---|
| **Status** | Accepted |
| **Requirement** | R12, R13 |
| **Pillars** | Reliability · Performance Efficiency |
| **Section** | §4.1 Recommendation and alternatives considered |

**Context.** What situation forces a decision here? Two to four sentences, framed in terms of
Innovate Inc.'s actual constraints — team size, sensitive data, growth curve, budget — not in
abstract terms.

**Options considered.**

| Option | Strengths | Weaknesses | Verdict |
|---|---|---|---|
| … | … | … | Rejected — … |
| … | … | … | **Chosen** |

**Decision.** One or two sentences. What we are doing, stated plainly and specifically.

**Why this is the right choice for Innovate Inc.** *(This field is mandatory and is the one a
reviewer reads first.)* Three to five sentences, in **plain language a non-engineer founder can
follow**. No unexplained acronyms, no AWS product jargon that has not been introduced. Explain the
decision the way you would explain it to the person paying for it: what problem it solves for them,
what would have gone wrong with the alternative, and what it means for their business — risk to
their users' data, hours of their engineers' time, dollars on their bill, or their ability to keep
shipping.

**Consequences.** What the team now lives with, positive and negative, as two short lists:
- *Gains:* …
- *Accepts:* …

**Cost impact.** One sentence. Qualitative, or an indicative figure clearly labelled as such.

**Revisit when.** The specific, observable trigger that should reopen this decision — a metric
crossing a threshold, a headcount, a compliance requirement, a user count. Never "as needed".
```

### Worked example — the standard to match

```markdown
### ADR-019 — Amazon Aurora PostgreSQL over Amazon RDS Multi-AZ

| | |
|---|---|
| **Status** | Accepted |
| **Requirement** | R12, R14, R15 |
| **Pillars** | Reliability · Performance Efficiency · Security |
| **Section** | §4.1 Recommendation and alternatives considered |

**Context.** Innovate Inc. stores sensitive user data in PostgreSQL and expects to grow from a few
hundred daily users to potentially millions. The team has no database administrator and no
dedicated platform engineer. Whatever is chosen now will be extremely disruptive to change once
production data and a live user base depend on it.

**Options considered.**

| Option | Strengths | Weaknesses | Verdict |
|---|---|---|---|
| PostgreSQL on EC2, self-managed | Lowest sticker price; full control | Team owns patching, failover, backup verification, and point-in-time recovery tooling | Rejected — the failure mode is an untested backup, not a large bill |
| PostgreSQL in Kubernetes via an operator | One control plane for everything; good technology | Durability of the company's most valuable asset depends on the team's understanding of StatefulSets and operator upgrades | Rejected — appropriate for a team with dedicated platform engineers, which this is not |
| Amazon RDS for PostgreSQL, Multi-AZ | Managed backups and patching; cheaper; genuinely adequate today | Failover typically 60–120 seconds; no shared-storage read replicas; no cross-region managed replication | Rejected — the right answer if budget were the only constraint |
| Amazon Aurora PostgreSQL, Serverless v2 | Sub-30-second failover, up to 15 readers on shared storage, storage grows automatically, cross-region Global Database, scales down to near-idle cost | Higher unit price than RDS; less portable off AWS | **Chosen** |

**Decision.** Run PostgreSQL on Amazon Aurora PostgreSQL-Compatible Edition using Aurora Serverless
v2 instances, with a writer and one reader in separate Availability Zones, fronted by Amazon RDS
Proxy.

**Why this is the right choice for Innovate Inc.** The database is the one part of this system where
a mistake is permanent — you can redeploy a broken application in minutes, but you cannot un-lose
customer data. Aurora keeps six copies of that data across three physically separate datacenters and
takes over from a failed server in under thirty seconds, without anyone being woken up. Because it
bills by capacity consumed, it costs very little while there are only a few hundred users, and it
grows to serve millions without a migration project or a maintenance window. The cheaper option,
Amazon RDS, would work today and cost less — but it takes one to two minutes to recover from a
server failure instead of thirty seconds, and it cannot spread read traffic across many copies of
the database, which is exactly what the growth plan needs. Paying somewhat more now avoids a
database migration at the worst possible moment: while growing fast.

**Consequences.**
- *Gains:* Sub-30-second failover; read scaling to 15 replicas without re-architecture; automated
  backups with point-in-time recovery; a managed cross-region disaster recovery path.
- *Accepts:* A higher per-unit compute price than RDS; a meaningful dependency on AWS that would
  make a future move to another provider a migration project rather than a lift-and-shift.

**Cost impact.** Higher than RDS at equivalent capacity; materially lower than either at low traffic
because Serverless v2 scales down to a small floor. Indicative day-1 figure in the Cost Optimization
chapter.

**Revisit when.** Write throughput approaches the ceiling of a single writer instance, or a
contractual requirement for cloud portability appears.
```

---

## 2. ADR number allocation — reserved per phase, never reuse

Numbers are pre-allocated so that phases written in different sessions never collide, and so that
re-running a phase overwrites its own block rather than corrupting the register.

Counts are **exact, not ranges** — every reserved number is used, so the finished register runs
ADR-001 to ADR-029 with no gaps. If a phase genuinely cannot fill its block, it says so in
`STATE.md` rather than shuffling numbers.

| Phase | Block | Count | The decisions it records |
|---|---|---|---|
| 00 | ADR-001 – ADR-003 | 3 | Cloud provider (AWS over GCP); three-tier architecture as the structural model; managed-services-first |
| 01 | ADR-004 – ADR-006 | 3 | Multi-account over single-account (and why seven); AWS Control Tower over hand-rolled Organizations; IAM Identity Center over IAM users |
| 02 | ADR-007 – ADR-010 | 4 | One VPC per environment with no interconnection; three Availability Zones; the secondary pod CIDR in carrier-grade NAT space; per-AZ NAT Gateways in production and one in non-production |
| 03 | ADR-011 – ADR-014 | 4 | Amazon EKS as the platform; the two-tier node strategy (platform managed node group plus Karpenter, and Karpenter over Cluster Autoscaler); Graviton-first with Spot for the application tier; the requests-and-limits policy |
| 04 | ADR-015 – ADR-018 | 4 | SPA served from object storage rather than a container; central registry with immutable digest promotion; GitOps pull-based delivery over push; image signing enforced at admission |
| 05 | ADR-019 – ADR-022 | 4 | Aurora over RDS, self-managed, and in-cluster PostgreSQL; Serverless v2 with RDS Proxy; the three-tier backup strategy; pilot-light cross-region disaster recovery |
| 06 | ADR-023 – ADR-025 | 3 | Customer-managed KMS keys over AWS-managed; centralised immutable logging in a separate account; deferring a service mesh and its mutual TLS |
| 07 | ADR-026 – ADR-027 | 2 | The observability stack and its day-1 versus at-scale split; SLO targets and the error-budget policy |
| 08 | ADR-028 – ADR-029 | 2 | Deferring commitment discounts until the baseline stabilises; the lean-start variant as a documented option |

**Total written across the drafts: 29 ADRs**, all completed by phases 00–08 — see `STATE.md`'s ADR
ledger. They remain in the drafts as the full audit trail. Phase 11 assembles the body; Phase 12
promotes **nine of the 29** into Appendix B (§2a); Phase 13 verifies the promoted nine are correct and
complete, and that every one of the other twenty has a row in the Summary of Key Decisions table.

### §2a — Appendix B promotion: one ADR per content phase

Appendix B carries **exactly one ADR per content phase (00–08) — nine records, ADR numbers fixed
below** — rather than all 29. Each is that phase's single most consequential, hardest-to-reverse
decision, weighted toward the ones the brief itself asks to be justified (`brief.md` R1/R2, R12) and
the ones a mistake would be most expensive to walk back.

| Phase | Promoted | Title | Why this one |
|---|---|---|---|
| 00 | **ADR-001** | AWS as the Cloud Provider | The most foundational choice in the document; everything else assumes it |
| 01 | **ADR-004** | Seven AWS Accounts Rather Than a Single Account | The brief's explicit "justify the account count" ask (R1, R2) |
| 02 | **ADR-007** | One VPC Per Environment, No Interconnection | The load-bearing network-isolation decision behind "secure the network" (R3, R4) |
| 03 | **ADR-011** | Amazon EKS as the Compute Platform | The brief's explicit "leverage Kubernetes Service" ask (R5) |
| 04 | **ADR-017** | GitOps Pull-Based Delivery with Argo CD Over Push-Based CI/CD | The hardest of the three containerization/deployment sub-asks to reverse once adopted (R11) |
| 05 | **ADR-019** | Amazon Aurora PostgreSQL Over Self-Managed and RDS | The brief's explicit "recommend the database service and justify it" ask (R12) |
| 06 | **ADR-023** | Customer-Managed KMS Keys Rather Than AWS-Managed Keys | The most consequential data-protection call, given the brief's "sensitive user data" emphasis (R21) |
| 07 | **ADR-026** | Open-Source Observability, Managed at Scale | A stack choice, unlike the SLO numbers in ADR-027, which is genuinely expensive to change later |
| 08 | **ADR-029** | Offering the Lean-Start Variant as a Documented Option | The decision most directly answering "cost-effective" (R22) for a founder reading the summary |

The other twenty (002, 003, 005, 006, 008, 009, 010, 012, 013, 014, 015, 016, 018, 020, 021, 022,
024, 025, 027, 028) are **not** demoted or dropped — they stay exactly as written in their phase's
draft, which remains available under `_plan/` as the full design record. In the graded deliverable
they surface as a row in the Summary of Key Decisions table (§10) instead of a full Appendix B entry.
Phase 12 does not re-derive this table; use it as given.

### Length cap — read this before writing

**No ADR exceeds 250 words** (excluding its metadata table and its options table). Most should be
shorter; a simple decision deserves a short record.

At nine records, Appendix B runs roughly 2 000–2 500 words against a body of 4 800–6 500. That ratio
is deliberate: the body is read start to finish, the appendix is a **reference** with an index at the
top, and a reader consults only the records they care about — nine is short enough to read start to
finish too, which 29 was not.

### Where the other decisions go

Nine full records do not cover every choice in the document, and they are not meant to. Every
decision — large or small, promoted or not — is justified **inline** where it is made, and every
decision also appears as a row in the *Summary of Key Decisions* table that Phase 12 builds. Between
the three mechanisms, no decision in this design is left unexplained:

| Mechanism | Covers | Depth |
|---|---|---|
| Inline prose | Every decision | Decision → why → what it beat → what it costs |
| Summary of Key Decisions table | Every significant decision | One scannable row each |
| Appendix B — the nine promoted ADRs | The most consequential ones (§2a) | Full context, options, plain-language justification, consequences, revisit trigger |

Each content phase writes its ADRs into its **own draft file**, in a final section titled
`## Decision Records`, using the exact template above. Do not write into another phase's file, and do
not create a shared register file — Phase 12 assembles it.

### Section references

The final chapter numbering is **fixed in advance** in `contract.md` §14 — it is not invented during
assembly — so you can cite it correctly from any phase. Write the `Section` field as **number and
name**: `§4.6 Disaster recovery`, `§3.3 Node strategy`. The number lets a reader jump straight there;
the name survives if anything ever shifts. Phase 12 verifies every reference resolves.

---

## 3. Inline prose versus the ADR — how they differ

They cover the same decision and must never contradict each other, but they are not the same text.
Copy-pasting one into the other is a failure.

| | Inline body prose | ADR entry |
|---|---|---|
| **Reader** | Someone reading the document in order | Someone scanning for the reasoning behind one decision |
| **Length** | One or two paragraphs, embedded in the flow | Structured, ~250–350 words |
| **Voice** | Explanatory, technical, connected to what came before | Self-contained; assumes no surrounding context |
| **Alternatives** | Named in a clause or a sentence | Full options table with a verdict per row |
| **Plain-language layer** | Woven into the explanation | Its own mandatory field, written for a non-engineer |
| **Triggers, consequences** | Usually omitted | Always present |

The inline prose still carries **decision → why → alternative rejected → trade-off**
(`style-guide.md` §1). The ADR adds the structure, the plain-language justification, the
consequences, and the revisit trigger.

---

## 4. What makes a justification strong

The difference between an adequate and a strong answer, in the reviewer's terms
(`rubric.md` §2.B):

| Weak | Strong |
|---|---|
| "We chose Aurora because it is highly available and scalable." | "We chose Aurora because failover completes in under thirty seconds rather than one to two minutes, and because read capacity can grow to fifteen replicas without changing the schema — both of which the growth plan needs and RDS cannot provide." |
| "Multi-account follows AWS best practice." | "A mistake in a development IAM policy cannot reach production data, and that property holds without anyone having to write a correct policy in future." |
| "Spot instances reduce cost." | "Spot cuts application-tier compute by roughly 70–90%, in exchange for pods being terminated on two minutes' notice — which is acceptable only because every application workload is stateless and protected by a disruption budget, and never for the platform tier." |
| "We use least privilege." | "Every workload assumes an IAM role bound to its own Kubernetes service account, so a compromised container holds that one service's permissions and nothing else." |

Three tests every justification must pass:

1. **Specific.** Names the mechanism and, where it matters, the number.
2. **Comparative.** States what it beat and what that alternative would have cost.
3. **Client-relevant.** Connects to one of Innovate Inc.'s four characteristics: growth from
   hundreds to millions of users, sensitive user data, a small team with limited cloud experience,
   or continuous delivery.

A justification that passes only the first two is an engineering note. All three make it advice.
