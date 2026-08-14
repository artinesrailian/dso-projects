## Recommendation in one line

We start Innovate Inc.'s cloud environment as **seven AWS accounts** inside a single AWS
Organization (`innovate-inc`) managed by AWS Control Tower, organized into four organizational
units (OUs), with two further accounts pre-planned to arrive as the team and its network topology
grow. Seven is the number where isolation, billing, and management each get a real boundary rather
than a shared one, without adding an account for every future concept the team has not yet built.

> **Well-Architected pillars.** Security · Reliability · Operational Excellence

---

## Why multiple accounts

We isolate Innovate Inc.'s environments in separate AWS accounts rather than inside shared virtual
private clouds (VPCs) or Kubernetes namespaces in one account, because the account is the only AWS
boundary that bounds identity and access management (IAM), service quotas, and the blast radius of
a mistake at the same time.

> **Well-Architected pillars.** Security · Reliability · Operational Excellence

**Isolation.** The alternatives a client might expect look cheaper on paper. Separate VPCs in one
account still share IAM and service quotas, so a wildcard policy written for development can still
reach production if worded wrong. Separate Kubernetes namespaces share the cluster control plane,
the node fleet, and the cluster's own IAM role, so an over-broad role binding in one namespace
reaches every namespace beside it. **A compromised or careless credential in `innovate-dev` has no
path to production data** under account separation, and that holds without anyone writing a correct
IAM policy in the future — for a company handling sensitive user data, that is close to the whole
argument.

**Billing.** Consolidated billing at `innovate-management` answers "what does production cost this
month?" without depending on every engineer tagging every resource correctly — accounts give a
floor of billing accuracy tags never reach, though mandatory tagging still matters for cost inside
an account. Reserved Instances and Savings Plans purchased centrally still apply organization-wide,
so separation does not fragment the commitment discounts the client wants once traffic is
predictable.

**Management.** SCPs attach at the OU level, so guardrails differ by risk — production can forbid
what development permits, without a second rulebook maintained by hand. Service quotas — Amazon
Elastic Kubernetes Service (EKS) clusters, EC2 vCPUs, Elastic IPs, VPCs — are counted per account,
so a runaway load test in `innovate-dev` cannot exhaust production's headroom during a real traffic
spike. Because a broken Terraform apply's blast radius is bounded by the account its pipeline role
can reach, a mistake in the staging pipeline cannot touch production even if the mistake is in the
pipeline code itself.

The same separation buys an audit benefit the client did not name but needs: **separation of
duties**. An attacker who fully compromises `innovate-prod` still cannot reach the log sink in
`innovate-log-archive` or disable the security-findings pipeline in `innovate-security-tooling`,
because neither account grants the other write access — exactly what a SOC 2 audit, or a customer's
security questionnaire, asks for.

> **Trade-off.** More accounts is not free. Each of the seven pays for its own baseline —
> GuardDuty, AWS Config, VPC endpoints — at roughly **$25–60/month per account**, plus a Terraform
> state file to manage and centralized access through IAM Identity Center from day one, since
> per-account IAM users become unmanageable past two or three accounts. That cost is why the answer
> is seven, not twenty.

---

## Account inventory

Each row in the account inventory below exists for a specific isolation, audit, or delivery
reason, not as a template checklist filled in for its own sake.

> **Well-Architected pillars.** Security · Reliability · Operational Excellence

| Account | OU | Purpose | Day 1? |
|---|---|---|---|
| `innovate-management` | Root | Organizations, Control Tower, consolidated billing, IAM Identity Center directory. **No workloads, ever.** | Yes |
| `innovate-log-archive` | Security | Immutable sink for org CloudTrail, AWS Config, VPC flow logs, ALB/CloudFront logs. S3 Object Lock (WORM). | Yes |
| `innovate-security-tooling` | Security | Delegated administrator for GuardDuty, Security Hub, Detective, Inspector, Macie, IAM Access Analyzer. Read-only cross-account roles. | Yes |
| `innovate-shared-services` | Infrastructure | ECR registry of record, CI/CD runners & OIDC roles, Route 53 public hosted zone, ACM shared certs, Terraform state backends, artifact/SBOM store. | Yes |
| `innovate-dev` | Workloads / NonProd | Development EKS cluster + Aurora. Loosest guardrails, synthetic data only. | Yes |
| `innovate-staging` | Workloads / NonProd | Pre-production mirror of prod topology at reduced size. Release candidate gate. **No production data.** | Yes |
| `innovate-prod` | Workloads / Prod | Production only. Tightest SCPs, change-controlled, break-glass access. | Yes |
| `innovate-sandbox-<user>` | Sandbox | Per-engineer experimentation, hard budget cap, auto-nuke, no route to prod data. | Later |
| `innovate-network` | Infrastructure | Split out of Shared Services once Transit Gateway / hybrid connectivity is introduced. | Later |

**`innovate-management`** holds nothing but AWS Organizations, Control Tower, consolidated
billing, and the IAM Identity Center directory — no application workload is ever deployed here, so
a mistake in application infrastructure can never touch the account that controls every other
account. Its root credentials stay behind hardware MFA, used only through a documented break-glass
procedure.

**`innovate-log-archive`** is the reason the audit trail can be trusted rather than merely present:
organization CloudTrail, AWS Config history, VPC flow logs, and load-balancer access logs all land
here with S3 Object Lock in WORM mode. An attacker who fully compromises `innovate-prod` still
cannot delete or edit the evidence of what happened, because production has no delete permission on
this account.

**`innovate-security-tooling`** is the delegated administrator for GuardDuty, Security Hub,
Detective, Inspector, Macie, and IAM Access Analyzer, reaching every other account through
read-only cross-account roles — findings from all seven accounts land in one place instead of
seven consoles nobody checks daily.

**`innovate-shared-services`** holds Amazon Elastic Container Registry (ECR) as the registry of
record, the CI/CD identity and runners, the public Route 53 hosted zone, and the Terraform state
backends. An image is built and scanned once here and promoted by digest into `innovate-dev`,
`innovate-staging`, and `innovate-prod` in turn; duplicating the registry per environment means
rebuilding per environment, which breaks the guarantee that what was tested in staging is what
ships to production.

**`innovate-dev`** and **`innovate-staging`** are both workload accounts, but staging is a separate
account rather than a namespace inside `innovate-prod` for the same isolation reason as everything
else here, and it exists as the release-candidate gate before production. No production data ever
enters either non-production account — synthetic or masked seed data only.

---

## Organizational unit structure

Service control policies attach to organizational units, not to individual accounts, so an
account's guardrails are a function of where it sits in the tree below — moving an account between
OUs is how its guardrails change, deliberately, rather than by editing a policy directly.

> **Well-Architected pillars.** Security · Operational Excellence

```text
Root
├── Security                  → innovate-log-archive, innovate-security-tooling
├── Infrastructure            → innovate-shared-services   [+ innovate-network later]
├── Workloads
│   ├── NonProd               → innovate-dev, innovate-staging
│   └── Prod                  → innovate-prod
├── Sandbox                   → innovate-sandbox-*         [later]
└── Suspended                 → decommissioned accounts, deny-all SCP
```

Two entries look ahead of day one. `innovate-network` splits out of Infrastructure once the client
needs Transit Gateway or hybrid connectivity that a single shared-services account should not also
own; `innovate-sandbox-<user>` gives each engineer a hard-capped, auto-nuked account for
experimentation once the team is large enough that shared experimentation space in `innovate-dev`
starts to collide with real work. The `Suspended` OU is the exit path: an account that is
decommissioned or fails a security review moves here under a deny-all SCP rather than being deleted
immediately, giving time to confirm nothing still depends on it.

---

## Guardrails — service control policies

Six SCP families apply org-wide or to a specific OU, enforced at the AWS Organizations layer, where
no account — including the account root user — can override them.

> **Well-Architected pillars.** Security · Operational Excellence

| Guardrail | Applies to | What it prevents |
|---|---|---|
| Root user restriction | All accounts | Any action taken as the account root user outside a documented break-glass procedure |
| Organization and logging protection | All accounts | Leaving the organization, or disabling CloudTrail, AWS Config, GuardDuty, or Security Hub |
| Region restriction | All accounts | Resource creation outside `us-east-1`, `us-west-2`, and AWS global services |
| No local IAM identities | All accounts | Creating IAM users or long-lived access keys — access exists only through IAM Identity Center |
| Baseline encryption and exposure | All accounts | Public S3 buckets, unencrypted EBS/RDS/S3 resources, EC2 instances without IMDSv2 |
| Production change protection | Prod OU only | Deleting backup vaults or KMS keys, or changing RDS deletion-protection settings, outside the pipeline role |

SCPs are **maximum permission boundaries**, not grants: they can only remove what an IAM policy
otherwise allows, never add to it, and they bind even the account root user. That is exactly
the property a rule like "this must never happen anywhere in the organization" needs — it does not
rely on every future IAM policy in every future account being written correctly, only on the SCP
existing once at the OU level. The region-restriction guardrail is representative of the pattern:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "DenyOutsideApprovedRegions",
    "Effect": "Deny",
    "NotAction": ["iam:*", "organizations:*", "route53:*", "support:*"],
    "Resource": "*",
    "Condition": {
      "StringNotEquals": {
        "aws:RequestedRegion": ["us-east-1", "us-west-2"]
      }
    }
  }]
}
```

---

## Identity and access

AWS IAM Identity Center runs from `innovate-management` as the single sign-on (SSO) point for
every account in the organization, backed by an external identity provider (IdP) — Google
Workspace, Okta, or Microsoft Entra ID — if Innovate Inc. already runs one, or Identity Center's
own built-in directory if it does not.

> **Well-Architected pillars.** Security · Operational Excellence

| Permission set | Accounts | Purpose |
|---|---|---|
| `InnovateAdmin` | `innovate-management`, `innovate-shared-services` | Full administrative access for the platform team's landing-zone and shared-infrastructure work |
| `InnovatePlatformEngineer` | All workload and infrastructure accounts | Operates EKS, networking, and CI/CD systems day to day |
| `InnovateDeveloper` | `innovate-dev`, `innovate-staging` | Deploys through GitOps, reads logs and metrics; no direct route to production |
| `InnovateReadOnly` | All accounts | Audit and on-call visibility with no ability to change anything |
| `InnovateBreakGlass` | All accounts | Sealed emergency access for when Identity Center or the CI/CD path itself is unavailable; every use is alarmed |

No account in the organization holds IAM users for people: humans authenticate once through single
sign-on and receive short-lived credentials scoped to a permission set; machines authenticate
through IAM roles, never access keys. MFA is mandatory for every human session, and production
access is time-boxed by default — as the team grows past its first few engineers, a request for an
`InnovateAdmin` or `InnovatePlatformEngineer` session in `innovate-prod` routes through an approval
workflow rather than standing access.

The same identity model answers how a developer's laptop reaches a private Amazon EKS API server:
an Identity Center session maps to an EKS **access entry** for that cluster, and
`aws eks update-kubeconfig` exchanges the session for a scoped Kubernetes credential — no bastion
host, no long-lived kubeconfig file to leak.

---

## Account provisioning and lifecycle

New accounts are never created by hand in the AWS console.

> **Well-Architected pillars.** Operational Excellence · Security

Control Tower's Account Factory (or its Terraform-based equivalent, Account Factory for Terraform)
provisions every account from the same baseline: organization CloudTrail enabled, AWS Config
recording, GuardDuty enrolled, default Amazon EBS encryption on, the default VPC deleted, the
mandatory tag policy attached, and a Terraform state bucket created before the account does
anything else. A manually created account is a defect, not a shortcut: it is the one account in the
organization that did not start from the same guardrails as the other seven, and the gap stays
invisible until something depends on it.

Decommissioning follows the same discipline in reverse. An account leaving service moves into the
`Suspended` OU under a deny-all SCP rather than being deleted outright, so nothing that still
depends on it fails silently, and so the account's data stays retrievable for as long as an
investigation might need it.

---

## Decision Records

The three decisions below carry the full argument for Innovate Inc.'s account structure: how many
accounts and why, which landing-zone tooling builds them, and how people authenticate into them.
Each stands on its own, with a plain-language justification a non-technical reader can follow
without the rest of this document.

> **Well-Architected pillars.** Security · Reliability · Operational Excellence

### ADR-004 — Seven AWS Accounts Rather Than a Single Account

| | |
|---|---|
| **Status** | Accepted |
| **Requirement** | R1, R2 |
| **Pillars** | Security · Reliability |
| **Section** | §1.1 Why multiple accounts |

**Context.** Innovate Inc. handles sensitive data with a five-person team and expects growth from
hundreds of users toward millions — the account structure chosen now is costly to change later.

**Options considered.**

| Option | Strengths | Weaknesses | Verdict |
|---|---|---|---|
| One account, separated by VPC per environment | Cheapest and fastest to stand up; a single console and a single bill | A policy meant only for development is not technically stopped from touching production resources, because IAM and quotas are organization-wide inside one account | Rejected — the isolation R2 asks for is optional here, not enforced |
| One account, separated by Kubernetes namespace | Fastest of all to provision; no account management overhead | A namespace boundary is enforced by convention and RBAC discipline, not by the platform — the same node fleet and cluster IAM role sit underneath every namespace | Rejected — collapses exactly the boundary the client's sensitive data needs |
| Three accounts, one per environment (dev, staging, prod) | Environment isolation is genuinely enforced where the client feels it most | No separated audit sink and no delegated security-findings account — logs and findings live inside the same accounts they need to prove were not tampered with | Rejected — solves environment isolation, leaves the audit trail unprotected |
| Seven accounts: three workload plus log archive, security tooling, shared services, and management | Every axis of R2 gets its own boundary — workload isolation, an audit sink no workload can write to, one delegated security view, one place images are built once | Four more accounts than the minimum, each with its own baseline services and cost | **Chosen** |

**Decision.** We hold Innovate Inc.'s seven day-one accounts — three workload plus
`innovate-log-archive`, `innovate-security-tooling`, `innovate-shared-services`, and
`innovate-management` — with `innovate-sandbox-<user>` and `innovate-network` added later.

**Why this is the right choice for Innovate Inc.** Think of an AWS account as a locked room: what
is inside cannot be reached from another without a door opened on purpose. Three accounts lock
development, test, and production, but the camera footage and alarm system sit in those same rooms
too. Seven accounts give the footage, the alarm, and the build pipeline rooms of their own, so a
mistake elsewhere cannot erase the evidence or silence the alarm. Going further than seven adds
doors without real separation.

**Consequences.**
- *Gains:* A compromised credential in one account cannot reach another's data; a runaway process
  cannot exhaust production's quotas; the audit trail survives a compromise of production.
- *Accepts:* Seven Terraform state files and baseline services to run instead of one, plus
  centralized access through IAM Identity Center from day one.

**Cost impact.** Each account adds roughly $25–60/month in baseline services. An eighth account
today adds the same cost without a boundary any current workload needs — why the count stops at
seven.

**Revisit when.** The product decomposes into services owned by separate teams, at which point
per-service accounts become the next boundary.

### ADR-005 — AWS Control Tower Rather Than Hand-Rolled AWS Organizations

| | |
|---|---|
| **Status** | Accepted |
| **Requirement** | R2, R25 |
| **Pillars** | Operational Excellence · Security |
| **Section** | §1 Cloud Environment Structure |

**Context.** Seven accounts (ADR-004) only deliver their isolation benefit if every account starts
from the same guardrail baseline — logging on, findings routed centrally, no forgotten default VPC.
Innovate Inc.'s five engineers have no landing-zone experience to build it.

**Options considered.**

| Option | Strengths | Weaknesses | Verdict |
|---|---|---|---|
| Hand-rolled AWS Organizations with custom Terraform modules | Full control over every guardrail and default; no opinionated structure to work around | The team designs, builds, and maintains the account factory, the SCP baseline, and drift detection itself — real engineering effort before the product exists | Rejected — appropriate for a team large enough to own a landing zone as its own project, which this is not |
| AWS Control Tower | Pre-built account factory, baseline SCPs, and AWS Config conformance packs from day one; still extensible with Terraform for anything it does not cover | Slightly less flexible on some default guardrails; a small amount of Control Tower's own logging overhead per account | **Chosen** |

**Decision.** We provision and govern Innovate Inc.'s AWS Organization with AWS Control Tower,
layering Terraform on top where it does not reach.

**Why this is the right choice for Innovate Inc.** Building a safe multi-account structure by hand
is a project — deciding every guardrail and testing none of it can be bypassed. Control Tower does
that work as a managed service: a new account is born already logging, scanned, and following the
rules the team decided once. The five engineers spend their time on the product, not reinventing a
landing zone AWS already maintains. The cost is a little flexibility — a few defaults the team
cannot change — a fair trade for not building that machinery themselves.

**Consequences.**
- *Gains:* A new account reaches the same secure baseline automatically, with no manual checklist
  to forget.
- *Accepts:* Some defaults are not customizable, and the baseline evolves on AWS's schedule, not
  the team's.

**Cost impact.** Control Tower carries no separate charge; the cost is the per-account baseline
already counted in ADR-004.

**Revisit when.** Control Tower's guardrail set cannot express a compliance or data-residency
requirement the client is contractually bound to, or a platform team is hired to own a hand-rolled
alternative.

### ADR-006 — IAM Identity Center Rather Than Per-Account IAM Users

| | |
|---|---|
| **Status** | Accepted |
| **Requirement** | R2, R21 |
| **Pillars** | Security · Operational Excellence |
| **Section** | §1 Cloud Environment Structure |

**Context.** Seven accounts (ADR-004) each need a way for engineers to sign in. IAM users work
adequately inside one account; they do not extend cleanly across seven, and the client stores
sensitive user data a leaked long-lived credential could expose.

**Options considered.**

| Option | Strengths | Weaknesses | Verdict |
|---|---|---|---|
| IAM users created in each account | Simple and familiar; no additional service to configure | Seven separate credentials per engineer to provision, rotate, and revoke; long-lived access keys are exactly the credential type that ends up in a leaked laptop or a committed config file | Rejected — the credential model that scales worst as accounts multiply |
| A self-managed SAML identity broker | Central login without depending on an AWS-native service | The team builds and operates its own identity infrastructure — the opposite of managed-services-first (ADR-003) — for a problem AWS already solves | Rejected — trades a solved problem for a self-built one |
| AWS IAM Identity Center | One login for every account in the organization; permission sets defined once and assigned per account; no long-lived access keys for people at all | Requires every engineer to authenticate through Identity Center rather than a familiar per-account login | **Chosen** |

**Decision.** We route every human identity in Innovate Inc.'s organization through AWS IAM
Identity Center in `innovate-management`; no account provisions IAM users for people.

**Why this is the right choice for Innovate Inc.** A separate login for each of seven AWS accounts
is exactly what engineers write down somewhere unsafe, and a leaked credential does not expire on
its own. IAM Identity Center gives every engineer one login, protected by multi-factor
authentication, granting only the access they need — revocable in one place the moment someone
leaves, instead of hunting through seven accounts for forgotten credentials. For a company whose
product depends on user trust in how it protects data, that is worth more than a familiar
per-account login.

**Consequences.**
- *Gains:* One place to grant, review, and revoke access across every account; no long-lived
  access keys to leak; multi-factor authentication enforced centrally.
- *Accepts:* Engineers depend on Identity Center's availability, and permission sets are designed
  centrally rather than improvised per account.

**Cost impact.** No additional charge — Identity Center is included with AWS Organizations; the
cost is defining permission sets once rather than seven times over.

**Revisit when.** Innovate Inc. adopts a corporate identity provider that must federate in, or
headcount outgrows the current five permission sets.
