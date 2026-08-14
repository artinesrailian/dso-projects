# Normative Contract — names, numbers, and decisions

**STATUS: NORMATIVE.** Every phase agent must read this file before writing a single word, and must
use these exact names, numbers, and service choices. Phases are executed by *different agents in
different sessions with no shared memory*; this file is the only thing preventing Section 2 from
saying `10.0.0.0/16` while Section 3 says `172.16.0.0/16` and the diagram draws something else again.

**You may not invent a name, CIDR, region, size, or service that is fixed here.**
If a value you need is genuinely absent, you may define it — but you must (a) follow the naming
conventions in §2, (b) append it to §12 "Extensions register" in this file, and (c) note it in your
completion report so later phases inherit it.

**You may not change a value that is already fixed here.** If you believe a fixed value is wrong,
stop, write the objection into `STATE.md` under *Open questions*, and proceed with the fixed value
anyway. A consistent document with one debatable choice beats an inconsistent document.

This file fixes **what** is built. Two companion files fix **how it is argued**, and both are equally
normative:

- [`decision-register.md`](decision-register.md) — the Architecture Decision Record format, the
  per-phase ADR number allocation, and the standard a justification must meet. The client's brief
  says *justify*; that file defines what justification means here.
- [`well-architected.md`](well-architected.md) — the six AWS Well-Architected pillars as they apply
  to this design, and the tagging convention every section and every ADR must follow.

---

## 1. Top-level decisions (locked)

| Decision | Value | One-line rationale to reuse |
|---|---|---|
| Cloud provider | **AWS** | Breadth of managed services across the whole growth curve, depth of governance tooling for sensitive data, largest hiring pool. |
| Managed Kubernetes | **Amazon EKS** | Managed control plane, deep AWS IAM/VPC integration, largest ecosystem. |
| Org management | **AWS Organizations + AWS Control Tower** | Landing-zone guardrails without building them by hand. |
| Human identity | **AWS IAM Identity Center (SSO)** | No IAM users, no long-lived keys, central permission sets. |
| Database | **Amazon Aurora PostgreSQL-Compatible Edition**, Serverless v2 instance class | One service that spans day-1 cost and million-user scale. |
| Connection pooling | **Amazon RDS Proxy** | Flask/gunicorn pod fleets exhaust Postgres connections; also masks failover. |
| SPA hosting | **Amazon S3 + Amazon CloudFront** (OAC), *not* a container | Static assets do not belong on cluster nodes; cheaper, faster, globally cached. |
| API ingress | **CloudFront → ALB → AWS Load Balancer Controller (IP target mode)** | Single edge, WAF once, TLS at edge and in-VPC. |
| Container registry | **Amazon ECR** in the Shared Services account | Cross-account pull, immutable tags, native Inspector scanning. |
| Node provisioning | **Karpenter** for app capacity + one small **EKS Managed Node Group** for platform add-ons | Bin-packing and Spot/Graviton at app tier; a stable home for the controllers that manage it. |
| CI | **GitHub Actions** with OIDC → IAM roles | No static credentials; the client's likely SCM. |
| CD | **Argo CD** (GitOps, pull-based) + **Argo Rollouts** for progressive delivery | Cluster credentials never leave the cluster; git is the audit trail. |
| IaC | **Terraform**, remote state in S3 + DynamoDB lock, one state per account/env | Provider-agnostic, the de facto standard, and the largest module ecosystem for a team that will hire. |
| Secrets | **AWS Secrets Manager** surfaced to pods via **External Secrets Operator** | Rotation is managed; no secrets in git or in the container image. |
| Pod identity | **EKS Pod Identity** (preferred) with IRSA as the documented fallback | Per-workload IAM without node-level credentials. |

### Deliberately rejected alternatives (name these when justifying, one line each)

| Rejected | Why not |
|---|---|
| Self-managed PostgreSQL on EC2 or in-cluster (StatefulSet + operator) | A 5-person startup should not own backups, failover, patching, and PITR for sensitive data. |
| Amazon RDS for PostgreSQL (Multi-AZ) | Viable and cheaper at the very bottom; loses fast storage-layer failover, 15-replica read scaling, and Global Database. Mention as the "if budget is the only constraint" option. |
| Amazon DynamoDB / other non-relational store | The brief specifies PostgreSQL; relational integrity is assumed. |
| ECS / Fargate-only / Lambda | The brief explicitly asks for managed Kubernetes. Note Fargate/EKS Auto Mode as a day-1 simplification, not the target. |
| GKE / GCP | A genuinely strong platform — GKE Autopilot is less operational work and project isolation is simpler. Loses on managed-service breadth at scale and governance depth. Give this **at most two sentences** in the body; the full argument is ADR-001. |
| A single AWS account with VPC/namespace separation | The core of R2 — this is what §1 argues against, in ADR-004. |
| Multi-region **active-active** on day 1 | Cost and complexity far exceed a few hundred users. It is the endgame in the growth roadmap, not the launch design. |

---

## 1a. The three-tier model (locked — the structural spine of the whole document)

The application is designed and described as a **classic three-tier architecture**. Every section of
the deliverable refers back to these three tiers, and the network, compute, and data designs are
deliberately aligned to them. Use these exact tier names.

| Tier | Contains | Runs on | Network placement | Scales by |
|---|---|---|---|---|
| **Presentation tier** | React single-page application, static assets | Amazon S3 origin behind Amazon CloudFront, with AWS WAF at the edge | Outside the VPC entirely — served from CloudFront edge locations | CloudFront; effectively unbounded, no action required |
| **Application tier** | Python/Flask REST API, background workers | Pods on Amazon EKS | **Private — App** subnets; pod IPs from the secondary CIDR. No inbound internet route. | Horizontal Pod Autoscaler and KEDA for pods, Karpenter for nodes |
| **Data tier** | PostgreSQL, and later a cache | Aurora PostgreSQL behind Amazon RDS Proxy | **Private — Data** subnets. No internet route, inbound only from the application tier. | Aurora Serverless v2 capacity units, then read replicas |

Three properties of this mapping are load-bearing and must be stated wherever the tiers are
discussed:

1. **Each tier is reachable only from the tier above it.** The internet reaches the presentation
   tier; only CloudFront reaches the application tier's load balancer; only the application tier
   reaches the data tier. Enforced by security-group references, not by CIDR ranges or convention.
2. **The tier boundary is also the security boundary.** Subnet tier, route table, security group, and
   Kubernetes NetworkPolicy all align to the same three lines, so there is one model to reason about
   rather than four overlapping ones.
3. **Each tier scales independently and by a different mechanism.** That is the point of the
   separation, and it is why the presentation tier can absorb a traffic spike at the edge without the
   application tier noticing.

> **Note for agents.** The three-tier model is not decoration and must not be reduced to a single
> sentence in the introduction. It is the frame: the high-level diagram is organised by tier, the
> network subnet tiers map to it one-to-one, and the growth roadmap describes what happens to each
> tier at each stage.

---

## 2. Naming conventions

```
<org>-<environment>-<resource>[-<region-short>][-<index>]
```

- `<org>` is always `innovate`.
- `<environment>` ∈ `mgmt` | `log` | `sec` | `shared` | `dev` | `stg` | `prod`.
- `<region-short>`: `use1` = us-east-1, `usw2` = us-west-2, `euw1` = eu-west-1.
- Lowercase, hyphen-separated. No underscores, no camelCase, no spaces.
- Kubernetes namespaces: `innovate-<app>` for workloads, `platform-<component>` for shared services.

---

## 3. Regions

| Role | Region | Used for |
|---|---|---|
| Primary | **us-east-1** (`use1`) | All environments, all workloads, day 1. |
| DR / secondary | **us-west-2** (`usw2`) | Pilot-light DR for production only. Backup vault copies. Aurora Global Database secondary. |
| Future EU | **eu-west-1** (`euw1`) | Reserved for GDPR data-residency expansion. Design must not block it. Do **not** build it out. |

---

## 4. Account structure (locked — this is the answer to R1)

**Seven accounts at launch**, inside one AWS Organization named `innovate-inc`, deployed via Control
Tower. Two more are pre-planned but not created on day 1.

| # | Account name | OU | Purpose | Day 1? |
|---|---|---|---|---|
| 1 | `innovate-management` | Root | Organizations, Control Tower, consolidated billing, IAM Identity Center directory. **No workloads, ever.** | Yes |
| 2 | `innovate-log-archive` | Security | Immutable sink for org CloudTrail, AWS Config, VPC flow logs, ALB/CloudFront logs. S3 Object Lock (WORM). | Yes |
| 3 | `innovate-security-tooling` | Security | Delegated administrator for GuardDuty, Security Hub, Detective, Inspector, Macie, IAM Access Analyzer. Read-only cross-account roles. | Yes |
| 4 | `innovate-shared-services` | Infrastructure | ECR registry of record, CI/CD runners & OIDC roles, Route 53 public hosted zone, ACM shared certs, Terraform state backends, artifact/SBOM store. | Yes |
| 5 | `innovate-dev` | Workloads / NonProd | Development EKS cluster + Aurora. Loosest guardrails, synthetic data only. | Yes |
| 6 | `innovate-staging` | Workloads / NonProd | Pre-production mirror of prod topology at reduced size. Release candidate gate. **No production data.** | Yes |
| 7 | `innovate-prod` | Workloads / Prod | Production only. Tightest SCPs, change-controlled, break-glass access. | Yes |
| 8 | `innovate-sandbox-<user>` | Sandbox | Per-engineer experimentation, hard budget cap, auto-nuke, no route to prod data. | Later |
| 9 | `innovate-network` | Infrastructure | Split out of Shared Services once Transit Gateway / hybrid connectivity is introduced. | Later |

### Organizational Unit tree (locked)

```
Root
├── Security                  → innovate-log-archive, innovate-security-tooling
├── Infrastructure            → innovate-shared-services   [+ innovate-network later]
├── Workloads
│   ├── NonProd               → innovate-dev, innovate-staging
│   └── Prod                  → innovate-prod
├── Sandbox                   → innovate-sandbox-*         [later]
└── Suspended                 → decommissioned accounts, deny-all SCP
```

### SCP guardrails to cite (name at least these six)

1. Deny use of the account root user except for documented break-glass.
2. Deny leaving the organization / disabling CloudTrail, Config, GuardDuty, or Security Hub.
3. Region restriction — deny all regions except `us-east-1`, `us-west-2`, and global services.
4. Deny creation of IAM users and long-lived access keys (Identity Center only).
5. Deny public S3 buckets, deny unencrypted EBS/RDS/S3, require IMDSv2.
6. Prod OU only: deny deletion of backup vaults, KMS keys, and RDS deletion-protection changes outside the pipeline role.

---

## 5. Network plan (locked — this is the answer to R3)

Supernet reserved for the whole organization: **`10.0.0.0/8`**. Pod overlay space:
**`100.64.0.0/10`** (RFC 6598 carrier-grade NAT space — routable inside the VPC as a secondary
CIDR, never advertised, never overlaps a partner network).

| Environment | Region | VPC name | Primary CIDR | Secondary CIDR (pods) |
|---|---|---|---|---|
| Dev | us-east-1 | `innovate-dev-vpc-use1` | `10.10.0.0/16` | `100.64.0.0/16` |
| Staging | us-east-1 | `innovate-stg-vpc-use1` | `10.20.0.0/16` | `100.65.0.0/16` |
| **Production** | us-east-1 | `innovate-prod-vpc-use1` | **`10.30.0.0/16`** | **`100.66.0.0/16`** |
| Production DR | us-west-2 | `innovate-prod-vpc-usw2` | `10.31.0.0/16` | `100.67.0.0/16` |
| Shared Services | us-east-1 | `innovate-shared-vpc-use1` | `10.40.0.0/16` | — |
| Reserved (EU, future) | eu-west-1 | — | `10.50.0.0/16` – `10.99.0.0/16` | — |

### Production subnet layout (the canonical example — use these exact values everywhere)

Three Availability Zones: `us-east-1a`, `us-east-1b`, `us-east-1c`.

| Tier | Purpose | AZ-a | AZ-b | AZ-c | Size | Usable IPs / AZ |
|---|---|---|---|---|---|---|
| Public | ALB, NAT Gateways. Nothing else. | `10.30.0.0/24` | `10.30.1.0/24` | `10.30.2.0/24` | /24 | 251 |
| Private — App | EKS worker nodes (ENIs) | `10.30.16.0/20` | `10.30.32.0/20` | `10.30.48.0/20` | /20 | 4 091 |
| Private — Data | Aurora, RDS Proxy, ElastiCache | `10.30.64.0/24` | `10.30.65.0/24` | `10.30.66.0/24` | /24 | 251 |
| Private — Endpoints | VPC interface endpoint ENIs | `10.30.68.0/24` | `10.30.69.0/24` | `10.30.70.0/24` | /24 | 251 |
| Private — Pods (secondary) | Pod IPs via VPC CNI custom networking | `100.66.0.0/18` | `100.66.64.0/18` | `100.66.128.0/18` | /18 | 16 379 |
| Reserved | Future tiers, do not allocate | `10.30.128.0/17` | | | /17 | 32 763 |

Non-prod environments use the identical *shape* at the same offsets inside their own /16.

### Fixed network facts

- **Route tables:** one public RT (0.0.0.0/0 → IGW); one private RT **per AZ** (0.0.0.0/0 → that AZ's NAT Gateway) so a NAT failure or AZ failure never causes cross-AZ data charges or a blast-radius jump.
- **NAT Gateways:** 3 in production (one per AZ, HA). **1** in dev and staging (cost trade-off, explicitly called out).
- **Internet Gateway:** one per VPC. Worker nodes have **no** public IPs; `map_public_ip_on_launch = false` on every private subnet.
- **Gateway VPC endpoints (free):** S3, DynamoDB.
- **Interface VPC endpoints (PrivateLink):** `ecr.api`, `ecr.dkr`, `sts`, `logs`, `monitoring`, `secretsmanager`, `kms`, `ssm`, `ssmmessages`, `ec2messages`, `ec2`, `elasticloadbalancing`, `autoscaling`, `sqs`, `eks`, `xray`. Rationale: keeps control-plane and image-pull traffic off the NAT Gateway (latency, cost, and egress-exposure win).
- **EKS API endpoint:** private access **enabled**; public access **enabled but restricted** to the CI/CD egress IPs and the corporate VPN CIDR in prod. Dev may be public-restricted for convenience.
- **Inter-environment connectivity:** **none.** No peering, no Transit Gateway between dev/staging/prod. Environments reach each other only through public, authenticated APIs — or not at all.
- **Flow logs:** every VPC, `ALL` traffic, delivered to the `innovate-log-archive` account in Parquet, queried with Athena.

---

## 6. Kubernetes plan (locked)

| Item | Value |
|---|---|
| Cluster names | `innovate-dev-eks-use1`, `innovate-stg-eks-use1`, `innovate-prod-eks-use1`, DR `innovate-prod-eks-usw2` |
| Clusters per account | Exactly one. Account is the isolation boundary, not the cluster. |
| Kubernetes version | The **latest EKS-supported minor version, or N-1**. Do not hard-code a version number anywhere in the deliverable — write "latest supported (currently N-1 policy)". |
| Control plane | Fully managed, private endpoint + restricted public, secrets envelope-encrypted with a customer-managed KMS key, audit + authenticator + controllerManager + scheduler + api logs → CloudWatch → Log Archive |
| Authentication | EKS **access entries** mapped to IAM Identity Center permission sets. No `aws-auth` ConfigMap editing. |
| Platform node group | EKS Managed Node Group `innovate-<env>-mng-platform`, 2–4 × `m7g.large` (Graviton), On-Demand, spread across 3 AZs, tainted `dedicated=platform:NoSchedule` |
| App capacity | Karpenter NodePools (see below) |
| NodePool `app-arm64-spot` | Graviton (`arm64`), **Spot** capacity type, families `m7g,c7g,r7g,m8g,c8g`, sizes 2–16 vCPU, weight 100 (preferred) |
| NodePool `app-amd64-spot` | `amd64`, **Spot**, families `m7i,c7i,m7a,c7a`, weight 50 — fallback when Spot arm64 is unavailable or an image is x86-only |
| NodePool `app-ondemand` | Mixed arch, **On-Demand**, weight 10 — last-resort fallback so a Spot squeeze never causes an outage |
| Consolidation | `WhenEmptyOrUnderutilized`, `consolidateAfter: 1m`; `expireAfter: 720h` (30 d) forces node rotation for patching |
| Disruption controls | PodDisruptionBudgets on every Deployment (`minAvailable: 50%`), `karpenter.sh/do-not-disrupt` on jobs that must not be interrupted |
| Workload namespaces | `innovate-api` (Flask), `innovate-jobs` (Celery workers / cron) |
| Platform namespaces | `platform-argocd`, `platform-ingress`, `platform-monitoring`, `platform-karpenter`, `platform-secrets`, `platform-certs` |
| Add-ons (EKS-managed) | VPC CNI (prefix delegation + custom networking + network policy), CoreDNS, kube-proxy, EBS CSI, Pod Identity Agent, CloudWatch Observability |
| Add-ons (Helm/GitOps) | Karpenter, AWS Load Balancer Controller, ExternalDNS, External Secrets Operator, cert-manager, metrics-server, kube-prometheus-stack (or AMP/AMG), Fluent Bit, Argo CD, Argo Rollouts, KEDA |
| Autoscaling | **HPA** on the API (CPU 65 % + RPS-per-pod custom metric), **KEDA** on the worker deployment (SQS queue depth), **Karpenter** for nodes, **VPA in recommender mode only** for right-sizing advice |
| Baseline API sizing | requests `250m` CPU / `512Mi` memory; limits: memory `512Mi` (= request), **no CPU limit**; 3 replicas min in prod, spread with `topologySpreadConstraints` `maxSkew: 1` over `topology.kubernetes.io/zone` |
| Guardrails | `ResourceQuota` + `LimitRange` per namespace; Pod Security Admission `restricted` enforced on all workload namespaces; `PriorityClass` `platform-critical` > `app-high` > `app-default` > `overprovision` (pause pods for burst headroom) |
| Network policy | Default-deny ingress and egress per namespace, then explicit allows. Enforced by the VPC CNI network-policy engine. |

---

## 7. Application & container plan (locked)

| Item | Value |
|---|---|
| API image | `<shared-acct>.dkr.ecr.us-east-1.amazonaws.com/innovate/api:<git-sha>` |
| Worker image | `<shared-acct>.dkr.ecr.us-east-1.amazonaws.com/innovate/worker:<git-sha>` |
| Tagging | **Immutable tags = the 40-char git SHA.** `latest` is never deployed. Promotion moves an image *digest*, never a rebuild. |
| Base image | `python:3.12-slim` builder → distroless / `gcr.io/distroless/python3` or slim runtime; non-root UID 10001, read-only root filesystem |
| App server | gunicorn with gthread/gevent workers behind the ALB; `/healthz` (liveness), `/readyz` (readiness, checks DB), `/startupz` |
| Frontend | React built in CI → static bundle → S3 bucket `innovate-<env>-web-use1` → CloudFront with OAC. Content-hashed filenames, `index.html` short TTL. |
| Multi-arch | `linux/arm64` primary, `linux/amd64` secondary, published as a single multi-arch manifest list via `docker buildx` |
| Registry policy | Immutable tags ON, scan-on-push (Inspector enhanced), lifecycle policy: keep last 30 tagged + expire untagged after 7 days, cross-region replication to `us-west-2` |
| Supply chain | SBOM (Syft/CycloneDX) per build → S3; image signed with **cosign** (keyless, GitHub OIDC) ; **Kyverno** admission policy verifies signature + registry origin before a pod is admitted |
| Environments flow | `feature branch → PR (lint, unit, SAST, IaC scan) → merge to main → build+push+sign → auto-deploy dev → automated integration tests → PR to staging overlay → deploy staging → manual approval → prod canary via Argo Rollouts` |
| Rollback | `git revert` of the GitOps commit; Argo Rollouts auto-abort on SLO breach during canary |

---

## 8. Database plan (locked — this is the answer to R12–R15)

| Item | Value |
|---|---|
| Service | **Amazon Aurora PostgreSQL-Compatible Edition** |
| Engine version | PostgreSQL **16.x**, with a documented upgrade path to 17.x via Blue/Green Deployments |
| Instance class | **Aurora Serverless v2** — prod `0.5 – 16 ACU` at launch, ceiling raised as traffic grows; dev `0.5 – 2 ACU`, auto-pause enabled in dev only |
| Cluster identifiers | `innovate-prod-aurora-pg-use1`, `innovate-stg-aurora-pg-use1`, `innovate-dev-aurora-pg-use1` |
| Topology | 1 writer + 1 reader in a **different AZ** (prod). Dev: writer only. |
| Endpoints | Writer, reader (load-balances read replicas), and custom endpoints for analytics/reporting |
| Pooling | **RDS Proxy** `innovate-prod-aurora-pg-proxy` in front of the writer and reader; pods connect only to the proxy |
| Placement | Private — Data subnets only. `publicly_accessible = false`. Security group allows 5432 **only** from the RDS Proxy SG; the proxy SG allows 5432 only from the node/pod SG. |
| Encryption | At rest with a customer-managed KMS key `alias/innovate-<env>-rds`; in transit enforced with `rds.force_ssl = 1` and `sslmode=verify-full` in the app |
| Credentials | Master secret in Secrets Manager with **automatic 30-day rotation**; app uses **IAM database authentication** through RDS Proxy — no password in the pod |
| Auditing | `pgaudit` + `log_statement=ddl`, Performance Insights (7 d free tier), Enhanced Monitoring 60 s, slow-query log → CloudWatch → Log Archive |
| Backups — automated | Retention **35 days** prod / 7 days non-prod; continuous PITR to any second in the window; backup window in the traffic trough |
| Backups — vaulted | **AWS Backup** daily copy into a **separate backup account** vault in `us-west-2`, **Vault Lock in compliance mode** (WORM, 90-day retention) — this is the ransomware / rogue-admin control |
| Backups — logical | Weekly `pg_dump` to S3 with Object Lock, for cross-engine portability and schema-level restores |
| Restore testing | Automated monthly restore into an isolated account; success/failure alarmed. Untested backups are not backups. |
| HA | Aurora storage = 6 copies across 3 AZs; automatic failover to the reader typically **< 30 s**; RDS Proxy holds client connections open across the failover; `deletion_protection = true` |
| DR | **Aurora Global Database** to `us-west-2` (typical cross-region replication lag < 1 s), plus pilot-light infra (Terraform + replicated ECR + Route 53 health-check failover). Managed planned failover for drills. |
| Schema migrations | Alembic, run as a Kubernetes `Job` in an Argo CD PreSync hook; expand/contract pattern so every migration is backward-compatible with the previous app version |

### Locked RPO / RTO table (reuse verbatim)

| Failure scenario | RPO | RTO | Mechanism |
|---|---|---|---|
| Pod or node loss | 0 | < 60 s | Multiple replicas, PDB, Karpenter replacement |
| Availability Zone loss | 0 | < 5 min | 3-AZ subnets, Aurora failover to reader in another AZ |
| Aurora writer failure | 0 | < 30 s | Automatic failover + RDS Proxy connection retention |
| Accidental table/row deletion | to the second | < 4 h | Aurora PITR / clone-and-extract |
| Region loss | **< 1 min** | **< 60 min** | Aurora Global Database + pilot-light Terraform apply + Route 53 failover |
| Ransomware / credential compromise | ≤ 24 h | < 24 h | Vault-locked cross-account backup copy, immutable |

---

## 9. Security baseline (locked)

| Control area | Fixed choices |
|---|---|
| Identity | IAM Identity Center, permission sets `InnovateAdmin`, `InnovatePlatformEngineer`, `InnovateDeveloper`, `InnovateReadOnly`, `InnovateBreakGlass`; MFA mandatory; no IAM users |
| Workload identity | EKS Pod Identity (IRSA as fallback), one role per service account, no node-role permissions beyond bootstrap |
| Encryption keys | Customer-managed KMS keys per environment **and per data class**: `alias/innovate-<env>-eks`, `-rds`, `-s3`, `-secrets`, `-ebs`, `-backup`. Annual rotation on. |
| Edge protection | CloudFront + **AWS WAF** (AWS managed rule groups: Common, Known Bad Inputs, SQLi, IP reputation) + rate-based rule (2 000 req / 5 min / IP) + AWS Shield Standard; **Shield Advanced** deferred to the growth roadmap |
| Detection | GuardDuty (incl. **EKS Runtime Monitoring**, **RDS Protection**, S3 Protection, Malware Protection), Security Hub (AWS FSBP + CIS 2.0 + PCI DSS standards), AWS Config conformance packs, Inspector (EC2, ECR, Lambda), Macie on data buckets, IAM Access Analyzer (external + unused access) |
| Logging | Organization CloudTrail (management + data events on the data buckets) → Log Archive S3, Object Lock compliance mode, 400-day retention; EKS control-plane logs; VPC flow logs; ALB + CloudFront access logs |
| App-layer auth | End-user authN/Z is the app's concern — recommend Amazon Cognito (or a managed IdP) with short-lived JWTs; note it, do not design it |
| Data classification tag | `DataClassification` ∈ `public` | `internal` | `confidential` | `restricted`; PII lives only in `restricted` stores |
| Privacy posture | GDPR-oriented: encryption, least privilege, retention schedule, deletion/DSAR path, EU region reserved, DPA with AWS, no prod PII in non-prod (masked/synthetic seeds) |
| Pipeline security | Branch protection + required reviews, signed commits, `gitleaks`, Semgrep/CodeQL SAST, `pip-audit`/Dependabot, Trivy image scan, Checkov/tfsec on Terraform, cosign signing, Kyverno admission verification |

### Mandatory tag set (every resource)

`Environment`, `Application` (= `innovate-web`), `Owner`, `CostCenter`, `DataClassification`,
`ManagedBy` (= `terraform`), `Compliance`. Enforced with AWS Organizations tag policies and a
Config rule.

---

## 10. Observability & SLOs (locked)

| Item | Value |
|---|---|
| Metrics | Amazon Managed Service for Prometheus + Amazon Managed Grafana (day 1: in-cluster kube-prometheus-stack is an acceptable cheaper start — say so) |
| Logs | Fluent Bit → CloudWatch Logs (14 d hot) → S3 in Log Archive (Athena, 400 d) |
| Traces | OpenTelemetry SDK in Flask → ADOT Collector → AWS X-Ray |
| Synthetic | CloudWatch Synthetics canary on `https://app.innovateinc.com` and `/api/healthz` from 2 regions |
| Alert routing | Alertmanager / CloudWatch Alarms → SNS → PagerDuty + Slack; runbook link mandatory on every alert |
| SLOs at launch | API availability **99.9 %** monthly, p95 latency **< 300 ms**, p99 **< 800 ms**, error rate **< 0.5 %** |
| SLOs at scale | 99.95 % once multi-AZ + canary deploys are proven |
| Error budget policy | Budget burn > 2× → feature freeze until burn returns to baseline |

---

## 11. Cost anchors (indicative — always label them as such)

> **Read this before using any number below.** These are **order-of-magnitude anchors reconstructed
> from memory, not verified AWS list prices.** They exist for one reason: so that eight independently
> written drafts quote the same figures instead of eight different ones. They are not a quote and
> must never be presented as one. Every place they appear in the deliverable must be labelled
> *indicative* and must point the reader at the AWS Pricing Calculator for a real estimate. Do not
> harden them, do not add precision they do not have, and do not derive new figures from them.

List price basis, `us-east-1`, day-1 footprint (a few hundred users/day), **all three environments**.

| Item | Monthly (indicative) | Note |
|---|---|---|
| EKS control planes × 3 | ~$220 | $0.10/h each. Biggest fixed cost at launch. |
| Worker nodes (Graviton, mostly Spot) | ~$120 | 2–4 small nodes per env; Karpenter consolidates aggressively |
| NAT Gateways (3 prod + 1 dev + 1 stg) | ~$170 | Hourly + data. VPC endpoints cut the data portion materially. |
| Aurora Serverless v2 (3 clusters, low ACU) | ~$130 | Prod writer+reader at min ACU; dev auto-pauses |
| ALB × 3 | ~$60 | Plus LCU |
| CloudFront + S3 | ~$15 | Low volume, free-tier-adjacent |
| ECR + backups + Secrets Manager | ~$25 | |
| CloudWatch / logs / metrics | ~$60 | Grows with log volume — set retention deliberately |
| GuardDuty / Security Hub / Config / Inspector | ~$70 | The price of the security posture; call it out honestly |
| **Total** | **≈ $850 – 900 / month** | |
| **Lean-start variant** | **≈ $400 – 450 / month** | Dev+staging share one cluster, single NAT everywhere, no reader replica in non-prod, in-cluster Prometheus instead of AMP/AMG |

### Cost trajectory anchors (for the growth-stage projections in §8.3)

Same caveat as above — these are **shape, not precision**. What matters to the client is the *curve*:
fixed costs dominate at launch, so cost per user falls steeply through the first order of magnitude
of growth, then flattens into roughly linear once compute and data transfer take over.

| Stage | Daily active users | Indicative monthly spend | What is driving it |
|---|---|---|---|
| 1 — Launch | a few hundred | **≈ $850** (lean ≈ $420) | Almost entirely fixed: EKS control planes, NAT Gateways, security baseline |
| 2 — Traction | ~10 000 | **≈ $2 000 – 3 000** | Aurora capacity units and read replicas, a cache tier, larger node fleet, log volume |
| 3 — Scale | ~100 000 | **≈ $8 000 – 15 000** | Node fleet and Aurora dominate; Savings Plans start to bend the curve; CloudFront data transfer becomes visible |
| 4 — Millions | millions | **six figures, but sub-linear per user** | Multi-region, sharding or partitioning, dedicated platform capacity; commitment discounts and cell efficiency hold cost per user well below stage 1 |

Cost per user falls by roughly **two orders of magnitude** between stage 1 and stage 3. That single
observation is the honest answer to "is this expensive?" — at launch it is, per user, and that is
what buying a foundation costs.

**Named cost levers** (every phase that touches cost must draw from this list, not invent its own):
Graviton (~20 % better price/performance), Spot for stateless (up to 70–90 % off), Karpenter
consolidation + `expireAfter`, Aurora Serverless v2 minimum-ACU floor, single NAT in non-prod, VPC
endpoints to cut NAT data processing, S3 lifecycle to IA/Glacier, CloudWatch log retention tiers,
right-sizing from VPA recommendations, Compute Savings Plans once the baseline is stable (12-month,
~30 %), Reserved capacity for the Aurora floor, `AWS Budgets` + `Cost Anomaly Detection` + per-tag
cost allocation, OpenCost/Kubecost for per-namespace chargeback, scheduled shutdown of dev outside
working hours.

---

## 12. Extensions register

Values invented by phase agents because they were absent above. **Append only.** Format:
`| phase | name | value | why it was needed |`

| Phase | Name | Value | Why |
|---|---|---|---|
| 02 | VPC CNI prefix-delegation block size | `/28` per ENI | §6's Add-ons row fixes "VPC CNI (prefix delegation + custom networking + network policy)" but not the delegated prefix size; `/28` is the AWS VPC CNI's actual prefix-delegation unit and is needed to explain pod density per node in `## IP address plan`. |
| 03 | Kubernetes minor-version upgrade SLA | Within 30 days of a new minor reaching general availability | §6 fixes the version *policy* (latest EKS-supported minor, or N-1) but not a cadence for acting on it; this phase's own instructions (`phases/phase-03-compute-eks.md`) specify the 30-day figure, needed so `## Cluster topology` states an operational commitment rather than an open-ended one. |
| 04 | Argo Rollouts canary steps | 10% → analysis → 50% → analysis → 100% | §7 fixes "prod canary via Argo Rollouts" as the mechanism but not its traffic-weight steps; a concrete step sequence is needed so `## Deployment — CI/CD and GitOps` can describe how the AWS Load Balancer Controller's two target-group weighting actually progresses, rather than asserting a canary exists without saying what it does. |

---

## 13. Terminology — use these exact words

| Use | Not |
|---|---|
| Availability Zone (AZ) | "zone", "datacenter" |
| managed node group / Karpenter NodePool | "ASG", "worker pool" |
| Amazon Aurora PostgreSQL-Compatible Edition (first use), then "Aurora PostgreSQL" | "Aurora DB", "RDS Aurora" |
| Amazon EKS (first use), then "EKS" | "AWS Kubernetes", "EKS service" |
| High-Level Diagram (HLD) | "HDL" — the brief's typo; do not repeat it in the deliverable |
| Innovate Inc. | "the client", "Innovate", "InnovateInc" |
| single-page application (SPA) | "front-end app" |

---

## 14. Final document section map (locked)

The assembled deliverable uses this chapter numbering. It is fixed here — not invented during
assembly — so that a phase writing in session 3 can cite a section that will not exist until session
12, and be right.

**Cite sections as number *and* name**: `§4.6 Disaster recovery`. The number lets a reader jump; the
name survives if anything ever shifts.

| § | Chapter | Built from |
|---|---|---|
| — | Executive Summary (with the High-Level Diagram) | Phase 12 |
| **§0** | Scope, Assumptions and Design Principles | draft 00 |
| **§1** | Cloud Environment Structure | draft 01 |
| **§2** | Network Design | draft 02 |
| **§3** | Compute Platform | drafts 03 + 04 |
| **§4** | Database | draft 05 |
| **§5** | Security and Data Protection | draft 06 |
| **§6** | Observability and Operations | draft 07 |
| **§7** | Cost Optimization | draft 08 |
| **§8** | Growth Roadmap | draft 09, part two |
| **§9** | Well-Architected Framework Alignment | draft 09, part one |
| **§10** | Summary of Key Decisions | Phase 12 |
| **App. A** | Requirement Traceability | Phase 12 |
| **App. B** | Architecture Decision Records | Phase 12, from the drafts |
| **App. C** | Diagrams | Phase 12 |
| **App. D** | Glossary | Phase 12 |

Subsection numbering within each chapter is fixed in
[`phases/phase-11-assembly.md`](phases/phase-11-assembly.md). The ones most often cited from
elsewhere:

| Reference | Subsection |
|---|---|
| `§0.2` | Architecture overview — a three-tier design |
| `§1.1` | Why multiple accounts |
| `§2.2` | VPC and subnet architecture |
| `§2.4` | Securing the network |
| `§3.3` | Node strategy |
| `§3.4` | Scaling |
| `§3.5` | Resource allocation within the cluster |
| `§3.8` | Container registry |
| `§3.9` | Deployment — CI/CD and GitOps |
| `§4.1` | Recommendation and alternatives considered |
| `§4.4` | Backups |
| `§4.5` | High availability |
| `§4.6` | Disaster recovery |
| `§5.3` | Data protection |
| `§6.3` | Service level objectives |
| `§7.1` | What this architecture costs |
| `§8.2` | What breaks first, and in what order |
| `§9.7` | Accepted trade-offs between pillars |
