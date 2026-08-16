# EKS + Karpenter on AWS

Terraform that stands up a dedicated-VPC EKS cluster with Karpenter autoscaling nodes on both
x86 and Graviton (arm64), Spot-first with On-Demand fallback — plus everything a developer needs
to run a pod on either architecture with one label.

> **Status.** This stack has not been applied against a real AWS account in this environment — no
> AWS credentials were available while it was built. Every phase was verified statically
> (`terraform validate`, `terraform test` against a mocked provider, `helm lint`/`helm template`,
> `kubeconform`) and all of that passes, but nothing below has run against a live cluster. The
> `kubectl` output shown in this README is illustrative, not captured from a real run — treat it
> as "this is the shape of the output," not a promise. **Phase 8 (`scripts/verify.sh`,
> `scripts/teardown.sh`) has not been implemented yet** — see **Teardown** below for the manual
> procedure that stands in for it.

```text
┌──────────────────────────────────────────────────────────────┐
│  Developer / operator workstation                            │
│  kubectl / terraform apply  (IAM access entries)             │
└──────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌──────────────────────────────────────────────────────────────┐
│  EKS control plane (AWS-managed)                             │
│  KMS-encrypted secrets, audit+api logs -> CloudWatch         │
└──────────────────────────────────────────────────────────────┘
                            │ ENIs
                            ▼
┌──────────────────────────────────────────────────────────────┐
│  VPC 10.0.0.0/16 -- 3 AZs, private data plane                │
│  public: NAT x3        private: bootstrap MNG (t4g x2)       │
│                                  '-- Karpenter controller    │
│  Karpenter-provisioned nodes (one pool per architecture):    │
│    amd64 NodePool            arm64 NodePool  (default)       │
│    spot + on-demand          spot + on-demand                │
└──────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌──────────────────────────────────────────────────────────────┐
│  SQS interruption queue  <-- EventBridge (Spot ITN,          │
│                               rebalance, instance health)    │
└──────────────────────────────────────────────────────────────┘
```
*(MNG = managed node group. ITN = Spot interruption notice, EC2's 2-minute warning.)*

## What you get

- Dedicated VPC across 3 AZs, private-only data plane — nodes and pods never get a public IP
- EKS 1.36, KMS-encrypted secrets, control-plane + audit logs to CloudWatch
- Karpenter 1.14.0, classic (not EKS Auto Mode) — the IAM, SQS and NodePool wiring stays visible
- One NodePool per architecture, weighted so an unconstrained pod lands on Graviton by default;
  Spot-first with automatic On-Demand fallback
- EKS Pod Identity for the Karpenter controller — no static credentials, no IRSA (the older
  OIDC-federation approach to granting a pod an IAM role) to wire up
- Everything encrypted: EKS secrets (KMS), EBS volumes (gp3), Terraform state (S3 + KMS)
- A governed `demo` namespace: Pod Security `restricted`, a ResourceQuota, a LimitRange

**Pinned** (date verified 2026-08-11 unless noted; re-verification commands in
[`docs/reference/version-pinning.md`](docs/reference/version-pinning.md)):

| Terraform | AWS provider | EKS module | VPC module | Kubernetes | Karpenter |
|---|---|---|---|---|---|
| `>= 1.11.0` | `~> 6.58` | `21.24.2` | `6.6.1` | `1.36` | `1.14.0` |

## Prerequisites

- **AWS credentials** for a principal that can create VPC/EKS/IAM/KMS/SQS/EventBridge resources —
  use IAM Identity Center or an assumed role, not the account root user or long-lived keys if you
  can avoid it. Check: `aws sts get-caller-identity`. Ranked guidance and what the deploy principal
  actually needs: [docs/operator-runbook.md §1](docs/operator-runbook.md).
- **The EC2 Spot service-linked role.** `create_spot_service_linked_role` defaults to `false`
  (creating it is not idempotent), so either confirm it already exists or set that variable to
  `true`. Check: `aws iam get-role --role-name AWSServiceRoleForEC2Spot`.
- **EC2 vCPU quota.** A fresh account's default 5-vCPU On-Demand quota is 80% consumed by the
  bootstrap node group alone — request an increase on both codes before the first apply. Check:
  `aws service-quotas get-service-quota --service-code ec2 --quota-code L-1216C47A` (and
  `L-34B43A08` for Spot).
- **Tooling.** Terraform ≥1.11, AWS CLI ≥2.30, kubectl within ±1 minor of 1.36, Helm ≥3.19 —
  see [docs/reference/version-pinning.md](docs/reference/version-pinning.md).

## Quick start

```bash
make bootstrap                                                          # S3 + KMS state backend, once per account
cp backend.hcl.example backend.hcl && $EDITOR backend.hcl               # fill in from the bootstrap output ($EDITOR unset? open it in anything)
cp terraform.tfvars.example terraform.tfvars && $EDITOR terraform.tfvars  # at minimum: your /32 and budget_notification_email
make init
make apply    # ~20 min end to end: network ~4min, cluster ~15min, karpenter ~3min — this is what starts billing
make kubeconfig
```

To bring it up in stages, or for the full platform-engineer runbook, see
[docs/operator-runbook.md](docs/operator-runbook.md). To look around without touching AWS state
at all, comment out the `backend "s3"` block in `backend.tf` and use local state instead — see
[docs/operator-runbook.md](docs/operator-runbook.md) §2, Option C.

## ── FOR DEVELOPERS ──────────────────────────────
## Running a pod on Graviton or x86

Add one line to your pod spec:

```yaml
nodeSelector:
  kubernetes.io/arch: arm64    # Graviton.  Use "amd64" for x86.
```

That is the whole interface. `kubernetes.io/arch` is a standard Kubernetes label — you do not
need to know anything about Karpenter or node pools to use it.

Get access first (your `demo` namespace already exists — Terraform creates it with a Pod Security
profile, a ResourceQuota and a LimitRange already applied; don't `kubectl create namespace`):

```bash
aws eks update-kubeconfig --region <region> --name <cluster-name>   # cluster-name: terraform output -raw cluster_name
```

(If you ran Quick start yourself, `make kubeconfig` already did this — the two are equivalent.)

Here is the complete file Phase 6 ships as `examples/deployment-arm64.yaml`, copied verbatim:

```yaml
# Run this workload on Graviton (arm64) nodes.
#
# Copy this file, change the image and the name, and ship. You do not need to
# know anything about Karpenter, NodePools, or instance types to use it.
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-graviton
  namespace: demo
spec:
  replicas: 3
  selector:
    matchLabels: { app: web-graviton }
  template:
    metadata:
      labels: { app: web-graviton }
    spec:
      # ---------------------------------------------------------------
      # THIS IS THE ONLY LINE THAT PICKS THE ARCHITECTURE.
      # kubernetes.io/arch is a standard Kubernetes label that the kubelet
      # sets on every node. You do not need to know anything about
      # Karpenter, node pools, or instance types to use it.
      # ---------------------------------------------------------------
      nodeSelector:
        kubernetes.io/arch: arm64

      # Spread across nodes so a single Spot reclaim cannot take out every
      # replica. ScheduleAnyway, not DoNotSchedule: on a cold cluster there
      # is exactly one node, and a hard constraint would leave replicas
      # Pending forever.
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: kubernetes.io/hostname
          whenUnsatisfiable: ScheduleAnyway
          labelSelector:
            matchLabels: { app: web-graviton }
        # The cluster pays for three AZs so that Spot has room to work with.
        # No NodePool carries a topology.kubernetes.io/zone requirement, so
        # without this constraint all three replicas could land in one AZ
        # and the other two AZs would be pure cost. This is the line that
        # makes the AZ spread real for this workload.
        - maxSkew: 1
          topologyKey: topology.kubernetes.io/zone
          whenUnsatisfiable: ScheduleAnyway
          labelSelector:
            matchLabels: { app: web-graviton }

      containers:
        - name: web
          # public.ecr.aws, not Docker Hub — a cluster behind one NAT gateway
          # is one source IP, and Docker Hub's anonymous pull rate limit
          # bites a shared cluster fast.
          #
          # nginx-unprivileged: uid 101, listens on 8080 (not 80, which would
          # need the NET_BIND_SERVICE capability — dropped below). Verified
          # genuinely multi-arch (linux/amd64 and linux/arm64).
          image: public.ecr.aws/nginx/nginx-unprivileged:stable
          ports:
            - containerPort: 8080
          # Resource REQUESTS are what Karpenter does its maths on. Without
          # them Karpenter assumes the pod is ~0-cost and will happily pack
          # it onto an existing node instead of provisioning a new one.
          # No CPU limit is set on purpose — a CPU limit only throttles you,
          # it buys nothing a request doesn't already give Karpenter.
          resources:
            requests:
              cpu: 500m
              memory: 256Mi
            limits:
              memory: 512Mi
          # Required by the `demo` namespace's `restricted` Pod Security
          # profile (every pod needs this, not just Karpenter workloads).
          securityContext:
            allowPrivilegeEscalation: false
            runAsNonRoot: true
            runAsUser: 101 # this image's USER; required, see above
            readOnlyRootFilesystem: true
            capabilities: { drop: ["ALL"] }
            seccompProfile: { type: RuntimeDefault } # required by PSA `restricted`
          # readOnlyRootFilesystem needs somewhere writable. This image's
          # nginx.conf already points its pidfile and all *_temp_path
          # directives at /tmp (verified against the image directly), so one
          # emptyDir is enough — no /var/cache/nginx or /var/run mount needed.
          volumeMounts:
            - { name: tmp, mountPath: /tmp }
      volumes:
        - { name: tmp, emptyDir: {} }
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: web-graviton
  namespace: demo
spec:
  minAvailable: 2 # of 3 replicas
  selector:
    matchLabels: { app: web-graviton }
# Karpenter honours PDBs when it drains a node for consolidation or an
# interruption. Without one it will drain all three replicas at once.
# A pod that must never be interrupted can also carry the annotation
#   karpenter.sh/do-not-disrupt: "true"
# — use it sparingly: it blocks consolidation and node expiry too.
```

**What happens next:**

```bash
kubectl apply -f examples/deployment-arm64.yaml
kubectl get nodeclaims -w     # Karpenter launches a Graviton node, ~40-70s
kubectl get pods -n demo -o wide
kubectl get nodes -L kubernetes.io/arch,karpenter.sh/capacity-type,node.kubernetes.io/instance-type
```

The first two commands are cluster-scoped and need the same credentials used for `terraform
apply` above — a namespace-scoped developer identity (see **Configuration** below) gets
`Forbidden` on both, which is correct RBAC, not a broken cluster; see
[examples/README.md](examples/README.md) for what a developer's access actually covers. A
realistic sample of the last command's output, once a Graviton node has joined
(**illustrative — see Status above**):

```
NAME                          STATUS   ROLES    AGE   VERSION               ARCH    CAPACITY-TYPE   INSTANCE-TYPE
ip-10-0-12-88.ec2.internal    Ready    <none>   58m   v1.36.0-eks-a1b2c3d   arm64   on-demand       t4g.medium
ip-10-0-77-142.ec2.internal   Ready    <none>   58m   v1.36.0-eks-a1b2c3d   arm64   on-demand       t4g.medium
ip-10-0-34-201.ec2.internal   Ready    <none>   1m    v1.36.0-eks-a1b2c3d   arm64   spot            m7g.large
```

**Proving it:**

```bash
kubectl apply -f examples/job-arch-check.yaml
kubectl wait --for=condition=complete --timeout=5m job/arch-check -n demo
kubectl logs -n demo job/arch-check
```

prints `architecture: aarch64` (would be `x86_64` on the amd64 pool — `job-arch-check.yaml`
targets arm64 by default; edit its `nodeSelector` to `amd64` to check the other side).

**On x86:** `examples/deployment-x86.yaml` is the same Deployment with one architectural decision
changed — `kubernetes.io/arch: amd64`. (The name and label values also change, from `web-graviton`
to `web-x86`, purely so the two can coexist in the same namespace side by side; nothing else does.)

```bash
kubectl apply -f examples/deployment-x86.yaml
```

**What if I don't set a `nodeSelector` at all?** You get Graviton — the arm64 pool is weighted
higher (see **Design decisions** below). That means an x86-only image with no
`nodeSelector` will `CrashLoopBackOff` with `exec format error` the moment it lands on an arm64
node. The real fix is a multi-arch image:

```bash
docker buildx build --platform linux/amd64,linux/arm64 -t <repo>:<tag> --push .
```

`examples/deployment-multiarch.yaml` demonstrates the no-`nodeSelector` pattern;
`examples/deployment-multiarch-preferred.yaml` shows a soft preference toward Graviton with an
x86 fallback instead of a hard constraint.

**Spot.** Both NodePools run Spot first, falling back to On-Demand only when Spot is unavailable,
so a node under your pod can be reclaimed with a 2-minute warning — Karpenter drains and replaces
it automatically. Your workload should handle `SIGTERM` and carry a `PodDisruptionBudget` (both
example Deployments already do); that is the honest cost of the price/performance win.

**Cleanup:**

```bash
kubectl delete -f examples/deployment-arm64.yaml
```

Karpenter removes the node it provisioned on its own, a few minutes after the last pod using it
is gone — no separate node-cleanup step. Shortcut for the whole walkthrough: `make demo` applies
both example Deployments and prints where each pod landed; `make demo-clean` removes them.

## ── FOR PLATFORM ENGINEERS ──────────────────────
## Operating this cluster

[docs/operator-runbook.md](docs/operator-runbook.md) is the real document here. It covers:
credentials (SSO > assumed role > access keys, and why not keys), what the deploy principal
needs, the three state-backend options, staged bring-up with per-stage cost and verification
gates, granting developers namespace-scoped access, upgrades, and the ordered teardown. This
README states what exists and links out — it does not duplicate that document.

## Configuration

The variables most people actually set (46 total; full table:
[docs/contracts/interface-contract.md §3](docs/contracts/interface-contract.md)). Also worth
setting: `alert_email` — subscribes to the KMS-key-danger CloudWatch alarm (see Known limitations
below); empty by default, meaning that alarm is silent until you set it.

| Variable | Default | What it controls |
|---|---|---|
| `cluster_endpoint_public_access_cidrs` | `[]` (required) | Your IP allowlist for the public API endpoint. `0.0.0.0/0` is rejected — *"0.0.0.0/0 is not allowed. Set your own /32, or use cluster_endpoint_public_access = false."* |
| `budget_notification_email` | required | Who gets the AWS Budget alert. |
| `create_spot_service_linked_role` | `false` | Set `true` only after confirming `AWSServiceRoleForEC2Spot` doesn't already exist. |
| `single_nat_gateway` | `false` | One NAT instead of one per AZ — cheaper, loses HA. |
| `bootstrap_node_min_size` | `2` | Drop to `1` to save cost; loses Karpenter-controller HA. |
| `nodepool_default_arch` | `"arm64"` | Which pool wins when a pod sets no `kubernetes.io/arch`. |
| `node_ami_alias` | `"al2023@latest"` | Pin to a release tag for production — see Operations below. |
| `region` | `"us-east-1"` | AWS region. |

A POC-cheap `terraform.tfvars`:

```hcl
cluster_endpoint_public_access_cidrs = ["203.0.113.10/32"] # curl -s https://checkip.amazonaws.com
budget_notification_email            = "you@example.com"

single_nat_gateway         = true      # ~$33/mo instead of ~$99/mo — single point of failure
bootstrap_node_min_size    = 1         # ~$25/mo instead of ~$49/mo — loses controller HA
enable_vpc_flow_logs       = false     # $0 instead of ~$5-20/mo
cluster_enabled_log_types  = ["audit"] # instead of all 5 log types
```

## Cost

Idle total is **~$245/mo** at the production-shape defaults above (`us-east-1`, rates verified
2026-08-11), or **~$165/mo** with every POC override in the block above applied. The two biggest
levers are NAT gateways (~$99 → ~$33/mo) and interface VPC endpoints, which default **off**
because turning them on (~$263/mo for 12 endpoints × 3 AZs) would roughly double the idle bill —
the single largest line item in the whole stack. Karpenter-provisioned nodes are pay-per-use and
consolidate to zero when idle. Full table:
[docs/00-architecture-and-decisions.md §5](docs/00-architecture-and-decisions.md).

## How it works

When a pod goes `Pending`, Karpenter — running on the bootstrap node group — evaluates its
requirements against both NodePools, picks the cheapest instance type that satisfies the
arch/capacity-type constraints, and calls `ec2:CreateFleet`. The node boots with the Karpenter
node IAM role, joins via its EKS access entry, and the pod schedules — typically 40–70 seconds.

On a Spot interruption, EC2 emits a 2-minute notice → an EventBridge rule → the SQS interruption
queue → Karpenter dequeues it, cordons and drains the node, and provisions a replacement before
the instance is actually reclaimed.

There is a small bootstrap managed node group because Karpenter cannot provision the node it runs
on itself — something has to exist first. It hosts only the Karpenter controller and cluster
add-ons, is On-Demand (not Spot) so the thing that recovers capacity isn't itself at risk of
disappearing, and Karpenter is configured never to schedule onto it.

## Design decisions

- Classic Karpenter, not EKS Auto Mode — the IAM, SQS and NodePool wiring stays visible on
  purpose; for a small team with no need for custom AMIs or fine-grained pool policy, Auto Mode
  is the better call.
- One root module, `aws` + `helm` providers only, no `kubernetes` provider, single `apply`.
- `NodePool`/`EC2NodeClass` are delivered by a local Helm chart, not `kubernetes_manifest` —
  avoids the CRD-must-exist-at-plan-time bootstrapping problem.
- S3 backend with native locking (`use_lockfile = true`) — no DynamoDB table.
- Two arch-specific NodePools, Spot-first with On-Demand fallback, arm64 weighted higher.
- AL2023 node AMIs, pinned by alias rather than a hardcoded release tag.
- Spot-to-spot consolidation is not enabled — noted as future work in
  [modules/karpenter/README.md](modules/karpenter/README.md).

Full record, including rejected alternatives:
[docs/00-architecture-and-decisions.md §3](docs/00-architecture-and-decisions.md).

## Operations

- **Kubernetes:** bump `kubernetes_version` one minor at a time. The control plane upgrades in
  place; nodes are replaced by Karpenter as they drift.
- **Karpenter:** bump `karpenter_version` — this upgrades **both** Helm releases (`karpenter` and
  `karpenter-crd`), which must stay in lockstep. Only the CRD chart actually updates the CRDs.
- **Node AMI:** `node_ami_alias` defaults to `al2023@latest`, so every new AWS AMI release marks
  nodes `Drifted` and Karpenter rolls the fleet, unannounced. Pin it for production — command and
  reasoning in [docs/operator-runbook.md §5](docs/operator-runbook.md).

## Troubleshooting

Full list: [docs/reference/gotchas.md](docs/reference/gotchas.md). The four most likely to hit a
first deploy:

- Set `bootstrap_node_min_size = 1` to save cost (see Configuration) and Karpenter itself gets
  stuck: it needs two distinct nodes for its own required `podAntiAffinity`, so the second
  replica sits `Pending` forever and nothing autoscales (gotchas G-05).
- Pods stay `Pending`, Karpenter logs `VcpuLimitExceeded` → the account's default 5-vCPU quota
  (gotchas G-02, see Prerequisites).
- Spot launches fail with `AuthFailure.ServiceLinkedRoleCreationNotPermitted` → the Spot
  service-linked role is missing (gotchas G-07, see Prerequisites).
- Pod `CrashLoopBackOff`s with `exec format error` → an x86-only image landed on the default
  Graviton pool (gotchas G-16, see the developer section above).

## Teardown

Phase 8 (`scripts/verify.sh`, `scripts/teardown.sh`) has not been implemented in this repository
yet — `make destroy` knows this and refuses to fall back to a bare `terraform destroy` rather than
doing the dangerous thing silently. Until that script exists, tear down by hand, in this order:

```bash
# 1. Remove workloads so Karpenter consolidates its nodes away. Deleting the
#    demo namespace directly is fine here specifically because the whole
#    stack is coming down next — it is not what the developer section means
#    by "don't create your own namespace" (that's about day-to-day use).
kubectl delete -f examples/ --ignore-not-found
kubectl delete namespace demo --ignore-not-found

# 2. Delete NodeClaims explicitly and wait — Karpenter drains and terminates them.
kubectl delete nodeclaims --all --wait=true --timeout=15m

# 3. Confirm nothing is left before touching Terraform. Must print nothing.
#    <cluster-name>: terraform output -raw cluster_name
aws ec2 describe-instances \
  --filters "Name=tag:karpenter.sh/managed-by,Values=<cluster-name>" "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].InstanceId' --output text

# 4. Now destroy.
terraform destroy
```

**Why the order matters:** a bare `terraform destroy` removes `helm_release.karpenter` first,
deleting the only controller that reconciles the `karpenter.sh/termination` finalizer on live
nodes. Steps 1–3 make sure nothing still depends on Karpenter before that happens — skip them and
the result is orphaned, still-billing EC2 instances and a VPC that will not delete. Full
mechanism: [docs/reference/gotchas.md](docs/reference/gotchas.md) G-09. The state bucket in
`bootstrap/` is a separate stack, untouched by any of this — destroy it with
`terraform -chdir=bootstrap destroy` only when finished with the account entirely.

## Repository layout

```
terraform/
├── main.tf, variables.tf, outputs.tf, ...   root composition — module blocks only, no resources
├── modules/network/            VPC, subnets, flow logs, endpoints         (Phase 1)
├── modules/eks/                 EKS control plane, bootstrap node group    (Phase 2)
├── modules/karpenter/           Karpenter IAM, SQS, both Helm releases     (Phases 3-4)
├── modules/cluster-resources/   NodePools, EC2NodeClass, namespaces        (Phase 5, local Helm chart)
├── bootstrap/                   One-time S3 + KMS state backend
├── examples/                    Developer-facing demo workloads            (Phase 6)
├── tests/                       terraform test suites
└── docs/                        Design record, runbook, reference, phase specs
```

## Known limitations

- **KMS CMK availability.** Cluster secrets are encrypted with a customer-managed key; if that key
  is disabled or scheduled for deletion, the control plane loses access to its own secrets. A
  CloudWatch alarm on key state exists (subscribe it via `alert_email`, see Configuration), but
  there is no automated recovery.
- **`hostNetwork` pods bypass the IMDS hop limit.** IMDSv2's hop limit blocks containerised access
  to node credentials for ordinary pods; a pod with `hostNetwork: true` reaches IMDS directly.
- **`node_ami_alias` defaults to `al2023@latest`**, so nodes drift on every new AMI release rather
  than on a schedule you control — see Operations above for pinning it.

## Not included / possible extensions

Phases 9–11 were not implemented: an AWS Load Balancer Controller, metrics-server + HPA, and
CI/CD. `enable_aws_load_balancer_controller` and `enable_metrics_server` exist as variables
(wired as far as `modules/eks`) but nothing consumes them yet — setting either to `true` currently
changes nothing observable.
