# Architecture & Decision Record

Read this before any phase. It defines *what* is being built and, more importantly, *why* each
non-obvious choice was made. The exact names live in
[`contracts/interface-contract.md`](contracts/interface-contract.md); the exact version numbers live
in [`reference/version-pinning.md`](reference/version-pinning.md).

---

## 1. Requirements, restated

| # | Requirement (from the assignment) | Where it is satisfied |
|---|---|---|
| R1 | Terraform deploys an EKS cluster on the latest available version | Phase 2 |
| R2 | Into a **new dedicated VPC** | Phase 1 |
| R3 | Karpenter deployed by the same Terraform | Phases 3–4 |
| R4 | NodePool(s) that can launch **both x86 and arm64** | Phase 5 |
| R5 | Leverage **Graviton** and **Spot** for price/performance | Phase 5 |
| R6 | Short README explaining how to use the repo | Phase 7 |
| R7 | README demonstrates a developer running a pod on x86 **or** Graviton | Phases 6–7 |
| R8 | Everything under `terraform/` in the repo root | All phases |

Implicit requirements a reviewer will check even though they are not written down: least-privilege
IAM, no public data planes, encrypted state and secrets, pinned versions, a clean `terraform
destroy`, and code that a stranger can run from a cold start.

---

## 2. Target architecture

```
                                    ┌───────────────────────────────────────────┐
                                    │  AWS account · region: var.region         │
                                    │                                           │
   ┌────────────┐                   │   ┌─────────────────────────────────────┐ │
   │ Developer  │──kubectl─────────────►│  EKS control plane (AWS-managed)    │ │
   │ workstation│  (IAM auth via       │  · KMS-encrypted secrets            │ │
   └────────────┘   access entries)  │   │  · audit + api logs → CloudWatch    │ │
         │                            │   │  · private endpoint (+ optional    │ │
         │ terraform apply            │   │    CIDR-restricted public)         │ │
         ▼                            │   └───────────────┬─────────────────────┘ │
   ┌────────────┐                     │                   │ ENIs                  │
   │ S3 backend │                     │   ┌───────────────▼──────────────────────┐│
   │ + KMS      │                     │   │ VPC 10.0.0.0/16  (dedicated, new)    ││
   │ + locking  │                     │   │                                      ││
   └────────────┘                     │   │  AZ-a          AZ-b          AZ-c    ││
                                      │   │ ┌──────────┐ ┌──────────┐ ┌────────┐ ││
                                      │   │ │ public   │ │ public   │ │ public │ ││
                                      │   │ │ /24 NAT  │ │ /24 NAT  │ │/24 NAT │ ││
                                      │   │ └────┬─────┘ └────┬─────┘ └───┬────┘ ││
                                      │   │ ┌────▼─────┐ ┌────▼─────┐ ┌───▼────┐ ││
                                      │   │ │ private  │ │ private  │ │private │ ││
                                      │   │ │ /19      │ │ /19      │ │ /19    │ ││
                                      │   │ │          │ │          │ │        │ ││
                                      │   │ │ ┌──────┐ │ │ ┌──────┐ │ │        │ ││
                                      │   │ │ │boot- │ │ │ │boot- │ │ │        │ ││
                                      │   │ │ │strap │ │ │ │strap │ │ │        │ ││
                                      │   │ │ │ MNG  │ │ │ │ MNG  │ │ │        │ ││
                                      │   │ │ │t4g.md│ │ │ │t4g.md│ │ │        │ ││
                                      │   │ │ └──┬───┘ │ │ └──────┘ │ │        │ ││
                                      │   │ │    │Karpenter controller pods    │ ││
                                      │   │ │    ▼     │ │          │ │        │ ││
                                      │   │ │ ┌─────────────────────────────┐  │ ││
                                      │   │ │ │ Karpenter-provisioned nodes │  │ ││
                                      │   │ │ │  amd64 pool │ arm64 pool    │  │ ││
                                      │   │ │ │  spot+OD    │ spot+OD       │  │ ││
                                      │   │ │ └─────────────────────────────┘  │ ││
                                      │   │ └────────────┘ └──────────┘ └──────┘││
                                      │   │  intra /24 ×3  ← control-plane ENIs ││
                                      │   └──────────────────────────────────────┘│
                                      │                                           │
                                      │   SQS interruption queue ◄── EventBridge  │
                                      │   (spot ITN, rebalance, health, state)    │
                                      └───────────────────────────────────────────┘
```

**Flow of control for a scale-up:** a pod goes Pending → Karpenter (running on the bootstrap node
group) evaluates its requirements against every NodePool → picks the cheapest instance type that
satisfies arch/capacity-type constraints → calls `ec2:CreateFleet` → the node boots with the
Karpenter node IAM role, joins via its EKS access entry, and the pod schedules. Typical time to
ready: 40–70 seconds.

**Flow of control for a Spot interruption:** EC2 emits the 2-minute interruption notice →
EventBridge rule → SQS queue → Karpenter dequeues → cordons and drains the node → provisions a
replacement before the instance is reclaimed.

---

## 3. Decision record

Each decision states the alternatives that were rejected, because that is what a reviewer actually
reads for.

### ADR-1 — Dedicated VPC, three AZs, private-only data plane

Nodes and pods live exclusively in private subnets; only NAT gateways and (optionally) public load
balancers sit in public subnets. Control-plane ENIs get their own **intra** subnets — route tables
with no NAT route at all — so the cluster's own network interfaces cannot egress even by accident.

Private subnets are `/19` (8,187 usable IPs each). This is deliberate: the VPC CNI assigns a real
VPC IP to every pod, so subnet sizing is *pod* sizing, not node sizing. A `/24` looks tidy and then
exhausts at ~250 pods per AZ.

*Rejected:* two AZs (cheaper, but Spot diversification across AZs is a primary availability lever —
three AZs materially reduces the chance of a correlated Spot reclaim); reusing a default VPC (the
assignment explicitly says dedicated).

### ADR-2 — Classic Karpenter, not EKS Auto Mode

EKS Auto Mode would deliver a working autoscaled cluster in a fraction of the code. It is rejected
here because it *hides* exactly the mechanisms the assignment is asking about: the controller IAM
policy, the SQS interruption path, the node role and its access entry, and the NodePool/EC2NodeClass
objects that express the x86-vs-arm64 choice. The deliverable is partly an artefact of
understanding, so the wiring stays visible.

Phase 7's README carries a short section on when Auto Mode *would* be the better call (small teams,
no need for custom AMIs or fine-grained pool policy), so the choice reads as a decision rather than
an omission.

### ADR-3 — A small managed node group hosts the Karpenter controller

Karpenter cannot provision the node it runs on. Something must exist first. Options were a Fargate
profile, a managed node group, or Auto Mode's system pool.

**Chosen:** a 2-node On-Demand managed node group of `t4g.medium` (Graviton — cheaper, and it makes
the point that the control tier itself runs on arm64), spread across AZs, running only Karpenter and
the cluster add-ons.

*Why not Fargate:* it works, but it adds a second compute model to reason about, has slower cold
starts, cannot run DaemonSets, and complicates the add-on story.

*Why On-Demand and not Spot:* if the controller's node is reclaimed while it is the only thing that
can provision replacements, recovery depends on the managed node group's own ASG. Two On-Demand
nodes in different AZs is the cheap insurance policy. Cost: roughly **$49/month** for the two
instances ($0.0336/hr each) plus ~$8 for their EBS root volumes.

The Karpenter deployment carries a `karpenter.sh/nodepool: DoesNotExist`-style anti-affinity so it
never migrates onto a node it manages. Phase 4 specifies this exactly.

### ADR-4 — EKS access entries with `authentication_mode = "API"`

The `aws-auth` ConfigMap is legacy: it was a shared mutable ConfigMap with no IAM audit trail, and
one bad edit locked everyone out. Access entries are an AWS API with proper IAM semantics.

Two consequences the phases must honour:

1. The Karpenter node IAM role needs an access entry of type `EC2` (Linux) or nodes boot, fail
   authentication, and never join — with no obvious error message. The `eks//modules/karpenter`
   submodule creates this for you; the phase doc says so explicitly because it is the single most
   common silent failure in this stack.
2. Whoever runs `terraform apply` gets admin via `enable_cluster_creator_admin_permissions`, and
   any additional operators come from `var.cluster_admin_principal_arns`.

### ADR-5 — EKS Pod Identity in preference to IRSA

Pod Identity replaces the OIDC-federation dance with a direct association between a Kubernetes
service account and an IAM role. It is simpler, does not require an OIDC provider per cluster, and
the trust policy is a fixed one-liner instead of a templated `sub` condition.

The `eks//modules/karpenter` submodule (v21.x) already uses `aws_eks_pod_identity_association` for
the controller. The `eks-pod-identity-agent` add-on is therefore **mandatory**, not optional.

IRSA is still enabled at the cluster level (`enable_irsa`) because some add-ons and third-party
charts have not migrated — but nothing in the core deliverable depends on it.

### ADR-6 — One root module, local child modules, `aws` + `helm` providers only

A reviewer must be able to run `cd terraform && terraform init && terraform apply` and get a working
cluster. That rules out a multi-stack layout that needs two applies in the right order.

Note that upstream guidance genuinely disagrees with itself here, and it is worth knowing rather
than papering over: HashiCorp's own EKS example splits bootstrap / cluster / Kubernetes-config into
three separate root modules and separate states, on the grounds that "provider configurations must
be known before a configuration can be applied". The `terraform-aws-modules/eks` Karpenter example
does the opposite — a single root module. Both are current. This build follows the module example,
because a single `apply` is worth more for a POC than the marginal robustness of split states, and
because the specific hazard is avoidable.

**There is no `kubernetes` provider.** Since v21 the EKS module dropped `aws-auth` ConfigMap
management, so it no longer needs one. Every Kubernetes object in this stack is delivered through
Helm (ADR-7), so `aws` and `helm` are the only two providers. That removes a whole category of
plan-time failure.

The residual rule that keeps the single-stack layout safe:

> Provider *configuration* may reference unknown values. Resource `count`/`for_each` may not.

So no resource in this stack uses `count`/`for_each` derived from cluster state; conditional Helm
releases are gated on static input variables. The fallback — `terraform apply -target=module.eks`
first — is documented in the README as a recovery path, not as the happy path.

Auth uses the `exec` plugin (`aws eks get-token`), never a `data.aws_eks_cluster_auth` token: that
token is persisted into state, expires in 15 minutes, and causes intermittent 401s on long applies.

### ADR-7 — Karpenter CRs are delivered by a local Helm chart

`NodePool` and `EC2NodeClass` are CRDs, which creates a bootstrapping problem for Terraform.

| Approach | Verdict |
|---|---|
| `kubernetes_manifest` (hashicorp/kubernetes) | **Rejected.** Requires the CRD to exist *at plan time*, so the first `plan` on an empty account fails. |
| `kubectl_manifest` (third-party provider) | **Rejected.** Works, but adds an unofficial provider dependency to a security-sensitive stack. |
| `helm_release` pointing at a local chart | **Chosen.** No extra provider, ordering handled by `depends_on` the Karpenter release, and `helm uninstall` removes the CRs cleanly on destroy — which matters, because orphaned NodePools with finalizers are a classic `terraform destroy` hang. |

The chart is a thin wrapper: `modules/cluster-resources/chart/` with templates for the NodePools
and the EC2NodeClass, and values fed from Terraform.

### ADR-8 — S3 backend with native locking

State contains the cluster CA data and every resource ID; it is encrypted at rest with a customer-
managed KMS key, versioned, and public-access-blocked. Locking uses S3 conditional writes
(`use_lockfile = true`) — **no DynamoDB table.** DynamoDB-based locking is the pattern most people
still reach for by reflex, and it is now redundant.

`bootstrap/` creates the bucket and key with local state and is applied once. The main
stack uses a **partial backend config** so the bucket name is not hardcoded into a committed file.

### ADR-9 — Two arch-specific NodePools, Spot-first with On-Demand fallback

One NodePool per architecture (`amd64`, `arm64`) rather than a single pool spanning both.

*Why split:* a single pool can express both architectures, but two pools give per-architecture
control of limits, weights, disruption budgets and taints, and they make the demo legible — a
developer reading `kubectl get nodepools` immediately sees the choice they are making. It also lets
the arm64 pool carry a higher weight, so **an unconstrained pod lands on Graviton by default**,
which is the price/performance behaviour the company asked for.

Each pool offers `spot` and `on-demand`. Karpenter's price-capacity-optimized allocation picks Spot
when it can and falls back to On-Demand when Spot is unavailable, without any extra configuration.
Both pools deliberately list *families and generations* rather than named instance types — a narrow
type list is the number-one cause of "Karpenter can't find capacity".

Each pool carries a vCPU and memory `limits` value to cap the blast radius of a runaway deployment,
and disruption budgets cap how much of the fleet **consolidation and drift** may churn at once.

Be precise about that scope: budgets throttle `Underutilized`, `Empty` and `Drifted` only. **Node
expiration and Spot interruption are not throttled by any budget** — see
`reference/karpenter-api-reference.md` §3. On a Spot-first cluster that is the honest position:
availability under interruption comes from PodDisruptionBudgets and replica spread in the workload,
not from anything Karpenter throttles.

Note that Karpenter's `spec.limits` is **per NodePool, not cluster-wide** — there is no cluster-level
limit in the API. With both pools enabled at `nodepool_cpu_limit = 100`, the true ceiling is
**200 vCPU**. Phase 5 therefore divides the configured budget across the enabled pools, so the
variable means what its name implies.

### ADR-10 — AL2023 node AMIs, pinned by alias

Amazon Linux 2 is end-of-life for EKS. `EC2NodeClass` uses the AL2023 family through an
`amiSelectorTerms[].alias`.

On pinning, the honest position: `alias: al2023@latest` means that when AWS publishes a new AMI,
every node is marked `Drifted` and Karpenter rolls the fleet — Karpenter's own schema documentation
says `latest` is "**not** recommended for production environments". But a hardcoded release tag goes
stale, and a repo that fails to apply the day someone clones it is worse for an assessment. So the
alias is a **variable** (`node_ami_alias`) defaulting to `al2023@latest`, and the README documents
pinning as the explicit production step, with the command to find a valid tag. The trade-off is
stated rather than silently taken.

Bottlerocket is a reasonable alternative and is noted in the README, but AL2023 keeps debugging
familiar for a team new to this.

Root volumes are encrypted `gp3`, and IMDS is locked to IMDSv2 with a hop limit that blocks
containerised access to node credentials — pods use Pod Identity, so they have no legitimate need
for IMDS.

### ADR-11 — Production shape by default, with one deliberate exception

Defaults are the production-correct choice — NAT per AZ, flow logs on, private endpoint available —
and every expensive default has a documented variable to turn it down, with the monthly saving stated
next to it in §5.

**The exception is `enable_vpc_endpoints`, which defaults to `false`.** Twelve interface endpoints
across three AZs is ~36 endpoint-AZs at ~$7.30 each, or **~$263/month** — by a wide margin the single
largest line item in the whole stack, larger than the EKS control plane and all three NAT gateways
combined. Defaulting it on would make the "production shape" default cost roughly double what a
reviewer expects, for a POC that already has NAT egress and therefore does not *need* the endpoints.

They remain a genuine control — required for a no-NAT private cluster, and defence-in-depth plus a
data-transfer saving otherwise — so the variable, the full endpoint list and the rationale all stay.
Turning it on is documented as the production step. The S3 **gateway** endpoint is free and is
created unconditionally regardless of this flag.

This is the one place where cost optimisation is allowed to beat the production default, and it is
called out here so it reads as a decision rather than an oversight.

---

## 4. Prerequisites

The implementing agent must state these in the README; the operator must satisfy them before apply.

| # | Prerequisite | Check |
|---|---|---|
| P1 | AWS credentials with permissions to create VPC, EKS, IAM, KMS, SQS, EventBridge | `aws sts get-caller-identity` |
| P2 | The **EC2 Spot service-linked role** exists in the account | `aws iam get-role --role-name AWSServiceRoleForEC2Spot`; create with `aws iam create-service-linked-role --aws-service-name spot.amazonaws.com`. Missing on brand-new accounts. Its absence surfaces as `AuthFailure.ServiceLinkedRoleCreationNotPermitted` in the Karpenter log and pods that sit `Pending` forever — it does not look like a permissions problem. |
| P3 | **EC2 vCPU quota.** This is the most likely thing to break a first deploy — read the note below. | `aws service-quotas get-service-quota --service-code ec2 --quota-code L-1216C47A` (On-Demand Standard) and `--quota-code L-34B43A08` (Spot Standard) |
| P4 | Terraform, AWS CLI v2, `kubectl`, `helm` installed | versions in `reference/version-pinning.md` |
| P5 | The chosen region offers the Graviton generations the NodePool requests | `aws ec2 describe-instance-type-offerings --filters Name=instance-type,Values=m7g.large --region <r>` |

> **The vCPU quota trap, in detail.** On a fresh AWS account both relevant quotas default to
> **5 vCPUs per region**:
>
> - `L-1216C47A` — Running On-Demand Standard (A, C, D, H, I, M, R, T, Z) instances
> - `L-34B43A08` — All Standard (A, C, D, H, I, M, R, T, Z) Spot Instance Requests
>
> The bootstrap node group alone is 2 × `t4g.medium` = **4 of those 5 On-Demand vCPUs.** The cluster
> and the Karpenter controller then come up perfectly, and the first Karpenter On-Demand node fails
> with `VcpuLimitExceeded` — which reads like a Karpenter misconfiguration and sends people
> debugging NodePools for an afternoon.
>
> Two further points people get wrong: On-Demand and Spot are **separate** quotas, so raising one
> does nothing for the other; and there is **no separate Graviton quota** — arm64 families (t4g,
> m7g, c7g, r8g …) all start with T/M/C/R and draw from the *same* Standard pool as x86. Adding an
> arm64 NodePool buys no extra headroom.
>
> Request increases on both quota codes **before** the first apply.

---

## 5. Cost envelope

Monthly figures, **`us-east-1`, rates verified 2026-08-11**, idle cluster (no Karpenter nodes
running). These are the basis of the README's cost section, so an error here propagates straight into
the graded artefact — check the arithmetic, not just the numbers.

| Component | Rate | **Default cost** | Toggle | Toggled cost |
|---|---|---|---|---|
| EKS control plane | $0.10/hr | **~$73** | not optional | ~$73 |
| NAT gateways | $0.045/hr + $0.045/GB | **~$99** (3 AZ) | `single_nat_gateway = true` | ~$33 |
| Bootstrap node group | 2 × `t4g.medium` @ $0.0336/hr | **~$49** | none — 2 nodes required by Karpenter podAntiAffinity (G-05) | ~$49 |
| Bootstrap EBS | 2 × 50 GiB gp3 @ $0.08/GiB | **~$8** | 20 GiB volumes | ~$3 |
| VPC flow logs | ingest + storage | **~$5–20** | `enable_vpc_flow_logs = false` | $0 |
| Control-plane logs | CloudWatch ingest | **~$5–30**, workload-dependent | `cluster_enabled_log_types = ["audit"]`, retention 7d | ~$2–10 |
| KMS CMK | $1 + requests | **~$1** | `encryption_config = null` (uses the AWS-owned key) | $0 |
| Interface VPC endpoints | $0.01/endpoint/AZ/hr | **$0 — off by default** | `enable_vpc_endpoints = true` → 12 endpoints × `az_count` × $7.30/mo = **+$263** at `az_count = 3` | +$263 |
| S3 gateway endpoint | free | $0 | always on | $0 |
| Karpenter nodes | pay-per-use | **~$0 idle** (consolidates to zero) | Spot ~70% off On-Demand | — |
| **Idle total** | | **~$245** *(excl. log ingest)* | all POC toggles on | **~$165** |
| **With VPC endpoints on** | | **~$508** | | |

Three things worth stating plainly:

1. **Interface endpoints are the largest single line item** — larger than the control plane and all
   three NAT gateways combined. That is why they default to `false` (ADR-11), unlike every other
   production default.
2. **These are idle figures.** The variable cost is Karpenter nodes, and that is the number the
   Graviton + Spot design exists to minimise: Spot runs ~70% below On-Demand, and Graviton adds
   roughly 20% better price/performance on top. A NodePool `limits.cpu` of 100 is a ceiling of very
   roughly **$3,000/month** if it were ever fully consumed on On-Demand — which is why the limit
   exists and why §5 is not the whole cost story.
3. **Cross-AZ pod-to-pod traffic is not in this table** and is a commonly-missed EKS cost ($0.01/GB
   each way). A three-AZ cluster with chatty services can spend more on inter-AZ transfer than on
   compute. Not modelled here because the POC has no real traffic; flagged so it is not a surprise.

**`./scripts/teardown.sh` is the real cost control** — not a bare `terraform destroy`, which orphans
running instances (see `reference/gotchas.md` G-09). Phase 8 provides the verified runbook, and
Phase 0 adds an AWS Budget with an email alert so a forgotten cluster announces itself.

---

## 6. Explicit non-goals

Called out so their absence reads as a decision, not an oversight:

- **No multi-account / multi-environment structure.** One region, one environment, parameterised.
  A production build would use separate accounts per environment and a stack-per-layer layout.
- **No GitOps (Argo CD / Flux).** Application delivery is out of scope; the Terraform stack stops at
  cluster + autoscaler + demo manifests.
- **No observability stack.** Control-plane logs go to CloudWatch; Prometheus/Grafana are not
  installed. Karpenter exposes metrics on `:8080` for a future scrape.
- **No service mesh, no external policy engine, no secrets operator.** Note that in-tree **Pod
  Security Admission is** enabled on the demo namespace — it needs no controller and costs nothing,
  so excluding it would have been laziness rather than scoping.
- **No cluster upgrade automation.** The Kubernetes version is a variable; upgrades are a deliberate
  human action.
- **No Windows or GPU node pools.** Both are a small EC2NodeClass/NodePool addition if needed.
- **No backup or DR tooling.** The cluster holds nothing that is not reproducible from this
  Terraform: EKS manages etcd and its backups, and node state is disposable by design. The one real
  gap is that the EBS CSI driver *is* installed, so any `PersistentVolume` a workload creates is
  **not** backed up — production would add a `VolumeSnapshotClass` plus AWS Backup. Called out
  because installing the CSI driver makes stateful workloads look supported.
- **No detection or alerting on the logs that are collected.** All five control-plane log types and
  VPC flow logs are enabled, but nothing reads them — there is no metric filter, alarm or SNS path.
  The single exception is the CMK state alarm (Phase 2), which is load-bearing for availability
  rather than security. A production build would add audit-log alarms on `system:anonymous` and
  authorization failures.

---

## 7. What "done" looks like

Phase 8 verifies all of it, but the bar is:

```bash
cd terraform

# Once per account: create the S3 state backend (separate root module, local state).
# `terraform init` in the main stack cannot succeed until this exists.
terraform -chdir=bootstrap init && terraform -chdir=bootstrap apply
cp backend.hcl.example backend.hcl                         # fill in from bootstrap outputs

cp terraform.tfvars.example terraform.tfvars               # then set your own /32 — see below
terraform init -backend-config=backend.hcl && terraform apply

aws eks update-kubeconfig --region <r> --name opsfleet-poc
kubectl get nodes -L kubernetes.io/arch,karpenter.sh/capacity-type
kubectl apply -f examples/deployment-arm64.yaml            # Karpenter launches a Graviton node
kubectl apply -f examples/deployment-x86.yaml              # Karpenter launches an x86 node
kubectl delete -f examples/                                # Karpenter consolidates them away

./scripts/teardown.sh                                      # ordered destroy — see gotchas.md G-09
```

Three things this sequence makes explicit, because earlier drafts of this document glossed them:

- **It is not `terraform apply` with zero configuration.** `cluster_endpoint_public_access` defaults
  `true` with an empty `cluster_endpoint_public_access_cidrs`, and a validation block refuses that
  combination — by design, so nobody can accidentally expose the API to `0.0.0.0/0`. The cost is one
  mandatory step: copy the example tfvars and set your own address
  (`curl -s https://checkip.amazonaws.com`). The README must lead with this, because it is the first
  thing a reviewer hits.
- **It is not a bare `terraform destroy`.** That command orphans running Karpenter instances and
  then fails on `DependencyViolation` (G-09). `scripts/teardown.sh` is the supported path and the
  README says so.
- **`terraform init` is not the first command.** The S3 backend has to exist first, which is a
  separate one-time `apply` of `bootstrap/`. Anyone who writes "just run `terraform init &&
  terraform apply`" in the README is describing a repo that does not work. The alternative — comment
  out `backend.tf` and run on local state — is a legitimate shortcut for a reviewer who only wants
  to look, and Phase 7 documents it as such.

A reviewer who has never seen the repo should get from clone to a running Graviton pod using only
`README.md`.
