# Operator Runbook — Platform / DevOps Engineer

**Audience:** the engineer who stands the cluster up and keeps it running. Not the application
developer — they get [`README.md`](../README.md), which is deliberately short and only covers running
a pod on x86 or Graviton.

| You are… | Read |
|---|---|
| A developer wanting to deploy a pod | `terraform/README.md` → *Running a pod on Graviton or x86* |
| The platform engineer standing this up | **This file**, top to bottom |
| An agent implementing a phase | `docs/phases/phase-NN-*.md` |

Two things this runbook exists to answer, because nothing else in the repo does:

1. **What has to exist in the AWS account before `terraform apply` can work at all** — credentials,
   permissions, the state backend, account-level quotas.
2. **How to bring it up in stages** so a failure tells you *which layer* broke, instead of dumping
   200 resources of error after 20 minutes.

---

## 0. The two ways to test

Be clear which one you are doing. They have very different costs.

| | **Static checks** | **Live bring-up** |
|---|---|---|
| Needs AWS credentials | No | Yes |
| Costs money | No | Yes — see §5 |
| Time | seconds | ~25 min cold, ~20 min to tear down |
| What it proves | The code is valid, formatted, lint-clean, policy-clean, and the security guards actually fire | It really works on AWS |
| Command | `make check` | `make bootstrap` → staged applies → `make verify` |

**Run the static checks constantly. Run the live bring-up deliberately.** Every phase's acceptance
criteria is written so that the static half works with no credentials — that is not an accident, it
is so you can validate the whole repo for free before spending anything.

```bash
make check     # fmt + validate + terraform test + tflint + checkov + helm lint + kubeconform
```

---

## 1. Day 0 — Credentials

### 1.1 How the operator should authenticate

Ranked. Use the highest one your organisation supports.

**① IAM Identity Center (SSO) — recommended**

No long-lived secret ever touches the machine. Credentials expire on their own.

```bash
aws configure sso --profile opsfleet-poc
aws sso login --profile opsfleet-poc
export AWS_PROFILE=opsfleet-poc
aws sts get-caller-identity
```

**② An assumed role**

If you have a shared account with a `PlatformAdmin`-style role:

```ini
# ~/.aws/config
[profile opsfleet-poc]
role_arn       = arn:aws:iam::111122223333:role/PlatformEngineer
source_profile = default
mfa_serial     = arn:aws:iam::111122223333:mfa/your.name
region         = us-east-1
```

```bash
export AWS_PROFILE=opsfleet-poc && aws sts get-caller-identity
```

**③ An IAM user with access keys — last resort**

> **Do not do this if you can avoid it,** and do not do it because a tutorial said to. Long-lived
> access keys are the single most common source of AWS credential compromise: they do not expire,
> they end up in `~/.aws/credentials`, in shell history, in a `.env`, and eventually in a git repo.
> This deliverable is graded partly on security posture, and "we created an IAM user with static
> keys" is a finding, not a setup step.

If you genuinely have no alternative (a personal sandbox account with no SSO):

```bash
aws iam create-user --user-name opsfleet-poc-operator
aws iam attach-user-policy --user-name opsfleet-poc-operator \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess     # see §1.2 on why
aws iam create-access-key --user-name opsfleet-poc-operator    # store in a password manager, not a file
```

Then **enforce MFA**, **rotate within 90 days**, and delete the user the moment the POC is done.
Never put the keys in `terraform.tfvars` — the AWS provider reads the standard environment and
profile chain, and this stack has no variable for credentials by design.

**For CI, none of the above.** Use GitHub OIDC federation — Phase 11 covers it. There should be no
AWS secret in any repository.

### 1.2 What permissions the deploying principal needs

Honest answer first: **most teams use `AdministratorAccess` to bring up a POC account**, and for a
throwaway sandbox that is a defensible choice. What is not defensible is doing it without knowing
why.

The stack creates resources in: EC2/VPC, EKS, IAM, KMS, SQS, EventBridge, CloudWatch Logs, S3,
Auto Scaling, and Budgets.

The part that matters:

> **A principal that can create IAM roles and pass them to EC2 is effectively an administrator.**
> This stack must create the Karpenter node role and pass it to instances (`iam:CreateRole` +
> `iam:PassRole`). Anyone holding those two permissions can create a role with
> `AdministratorAccess`, pass it to an instance they control, and read its credentials. So a
> "least-privilege deploy policy" that grants them is not meaningfully less privileged than
> `AdministratorAccess` — it just looks like it is.
>
> The real mitigation is an **IAM permissions boundary** on every role the stack creates. The
> Karpenter submodule exposes `iam_role_permissions_boundary_arn` (controller) and
> `node_iam_role_permissions_boundary` (node) — note the inconsistent naming — and the EKS module
> has equivalents. Set them in any environment that is not a sandbox. Doing so is out of scope for
> this POC and is listed under *Deliberately not done*.

If you want a scoped deploy policy anyway, grant these services and be prepared to iterate:
`ec2:*`, `eks:*`, `iam:*Role*`, `iam:*InstanceProfile*`, `iam:PassRole`, `iam:*Policy*`, `kms:*`,
`sqs:*`, `events:*`, `logs:*`, `s3:*` (state bucket only), `autoscaling:*`, `budgets:*`,
`servicequotas:Get*`. Run `terraform plan` and add what it complains about.

### 1.3 Account-level prerequisites

These are not Terraform's job and they will each fail in a way that looks like a different problem.

```bash
# 1. EC2 Spot service-linked role. Absent on accounts that have never used Spot.
#    Symptom if missing: pods Pending forever, Karpenter logs
#    "AuthFailure.ServiceLinkedRoleCreationNotPermitted" — looks like an IAM bug.
aws iam get-role --role-name AWSServiceRoleForEC2Spot >/dev/null 2>&1 \
  || aws iam create-service-linked-role --aws-service-name spot.amazonaws.com

# 2. vCPU quotas. BOTH default to 5 on a new account, and they are SEPARATE.
#    The bootstrap node group alone eats 4 of the 5 On-Demand vCPUs.
#    Symptom if too low: "VcpuLimitExceeded" — looks like a Karpenter misconfiguration.
aws service-quotas get-service-quota --service-code ec2 --quota-code L-1216C47A \
  --query 'Quota.Value'   # Running On-Demand Standard
aws service-quotas get-service-quota --service-code ec2 --quota-code L-34B43A08 \
  --query 'Quota.Value'   # All Standard Spot Requests

# Request increases (takes minutes to hours). Ask for MORE than nodepool_cpu_limit
# (default 100) plus the bootstrap group's 4 vCPU, or the account quota — not the
# NodePool limit — becomes your real ceiling, and hitting it produces exactly the
# VcpuLimitExceeded that gotchas.md G-02 teaches you to read as "fresh account".
aws service-quotas request-service-quota-increase \
  --service-code ec2 --quota-code L-1216C47A --desired-value 128
aws service-quotas request-service-quota-increase \
  --service-code ec2 --quota-code L-34B43A08 --desired-value 128

# 3. Graviton availability in your region.
aws ec2 describe-instance-type-offerings --region "$AWS_REGION" \
  --filters Name=instance-type,Values=m7g.large,c7g.large,t4g.medium \
  --query 'InstanceTypeOfferings[].InstanceType'
```

There is **no separate Graviton quota** — arm64 families (`t4g`, `m7g`, `c7g`, `r8g`) are all
T/M/C/R and draw from the same Standard pool as x86. Adding an arm64 NodePool buys no headroom.

---

## 2. Day 0 — Remote state backend

State holds the cluster CA data and every resource ID. It is encrypted, versioned and locked.

There is a bootstrapping problem: the thing that creates the state bucket cannot itself store state
in that bucket. Three ways to resolve it — pick one deliberately.

### Option A — `bootstrap/` Terraform (recommended)

A separate root module with **local state**, applied once per account. It creates the S3 bucket, a
KMS key with rotation, versioning, a full public-access block, ACLs disabled, a TLS-only bucket
policy, and lifecycle rules.

```bash
cd terraform
make bootstrap          # == terraform -chdir=bootstrap init && apply
# copy the printed values:
cp backend.hcl.example backend.hcl && $EDITOR backend.hcl
make init               # == terraform init -backend-config=backend.hcl
```

Commit `bootstrap/`'s own state file nowhere. It describes one bucket and one key; if you lose it,
`terraform import` takes two minutes.

### Option B — Create the bucket by hand

If your organisation provisions state buckets centrally, or you want the backend outside Terraform:

```bash
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
REGION=us-east-1
BUCKET="opsfleet-poc-tfstate-${ACCOUNT}"

aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" \
  $([ "$REGION" = us-east-1 ] || echo "--create-bucket-configuration LocationConstraint=$REGION")

aws s3api put-bucket-versioning --bucket "$BUCKET" \
  --versioning-configuration Status=Enabled
aws s3api put-public-access-block --bucket "$BUCKET" --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
aws s3api put-bucket-encryption --bucket "$BUCKET" \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"},"BucketKeyEnabled":true}]}'
aws s3api put-bucket-ownership-controls --bucket "$BUCKET" \
  --ownership-controls 'Rules=[{ObjectOwnership=BucketOwnerEnforced}]'
```

Then write `backend.hcl` by hand. **No DynamoDB table is needed** — this stack uses S3-native
locking (`use_lockfile = true`), which is why `required_version` is `>= 1.11.0`. If a tutorial tells
you to create a `terraform-locks` DynamoDB table, it predates that feature.

### Option C — Local state (POC / review only)

The fastest path for someone who just wants to look at the code work:

```bash
# comment out the whole terraform { backend "s3" {...} } block in backend.tf
terraform init
```

Fine for a single operator on a throwaway cluster. **Not fine** for anything two people touch —
there is no locking, and the state file (containing the cluster CA) sits unencrypted on disk.
Document which option you used; a reviewer will ask.

---

## 3. Day 1 — Staged bring-up

This is the part that makes the stack testable rather than all-or-nothing.

Terraform will print a warning that `-target` is "for exceptional circumstances". That warning is
about using it as a *routine workflow* to work around bad module design. Using it for **staged
first-time bring-up and for isolating a failure** is exactly the exceptional circumstance it means.

**The rule: after any targeted apply, you must finish with a full `terraform apply` to converge.**
A targeted apply deliberately skips resources; the stack is not in its declared state until an
untargeted apply runs clean.

| # | Stage | Command | ~Time | Running cost from here | Gate |
|---|---|---|---|---|---|
| 0 | State backend | `make bootstrap` | 1 min | ~$0 | Bucket exists, versioning on |
| 1 | Network | `make stage-network` | 3–5 min | **~$99/mo** (3 NAT) | 9 subnets, 3 NAT, tags present |
| 2 | Cluster | `make stage-cluster` | 12–18 min | **+~$130/mo** | `kubectl get nodes` → 2 Ready arm64 |
| 3 | Karpenter | `make stage-karpenter` | 2–4 min | +$0 | 2 controller pods on 2 nodes |
| 4 | NodePools | `make apply` *(full, converges)* | <1 min | +$0 idle | `kubectl get nodepools` → amd64, arm64 |
| 5 | Demo | `make demo` | 1–2 min | pay-per-use | Graviton node appears, pod Running |

Stage 1 is where the meter starts. If you only want to see the code work and not pay for a control
plane, stop after stage 1 and `make destroy`.

### The commands behind the Makefile

```bash
# Stage 1 — network only.
terraform plan  -target=module.network -out=tf.plan && terraform apply tf.plan

# Stage 2 — cluster. Implicitly includes module.network as a dependency.
terraform plan  -target=module.eks -out=tf.plan && terraform apply tf.plan

# Stage 3 — Karpenter controller (IAM/SQS + both Helm releases).
terraform plan  -target=module.karpenter -out=tf.plan && terraform apply tf.plan

# Stage 4 — everything, untargeted. REQUIRED to converge.
terraform plan -out=tf.plan && terraform apply tf.plan
```

Always `plan -out` then `apply <planfile>`. Applying a saved plan is the only way to be certain you
applied what you reviewed.

### Why this ordering is safe

The `helm` provider's configuration references `module.eks` outputs, which do not exist during
stage 1. That is fine, and it is the rule from ADR-6:

> Provider *configuration* may reference values unknown until apply. Resource `count`/`for_each` may
> not.

During stage 1 no Helm resource is in scope, so the unknown provider config is never evaluated. This
is also why nothing in this stack gates a `count` on cluster state.

### Verification gates

Do not move to the next stage until the current one passes.

```bash
# After stage 1
terraform output vpc_id
aws ec2 describe-subnets --filters "Name=vpc-id,Values=$(terraform output -raw vpc_id)" \
  --query 'length(Subnets)'                                    # 9
aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$(terraform output -raw vpc_id)" \
  --query 'length(NatGateways[?State==`available`])'           # 3 (or 1 if single_nat_gateway)

# After stage 2
aws eks update-kubeconfig --region "$(terraform output -raw region)" \
  --name "$(terraform output -raw cluster_name)"
kubectl get nodes                                              # 2 Ready
kubectl get pods -A --field-selector=status.phase=Pending      # must be empty

# After stage 3
kubectl get pods -n kube-system -l app.kubernetes.io/name=karpenter -o wide   # 2/2 on 2 nodes
kubectl get crd | grep karpenter                               # 5 CRDs
kubectl logs -n kube-system -l app.kubernetes.io/name=karpenter --tail=50 | grep -i error

# After stage 4
kubectl get nodepools                                          # amd64, arm64
kubectl get ec2nodeclass default -o yaml | grep -A5 conditions # Ready, no discovery errors

# Full check
make verify
```

### When a stage fails

1. Read the error, then match the symptom in [`reference/gotchas.md`](reference/gotchas.md) — G-01
   through G-22 cover nearly every real first-deploy failure, symptom-first.
2. Do **not** immediately `terraform destroy` and retry. A partial apply is recoverable and rebuilding
   the control plane costs 15 minutes.
3. `terraform plan` after a fix shows exactly what remains.

The four that account for most first-time failures:

| Symptom | Cause | Fix |
|---|---|---|
| `kubectl` → `You must be logged in to the server` | `enable_cluster_creator_admin_permissions` is false | G-01 |
| Pods `Pending`, Karpenter logs `VcpuLimitExceeded` | Account vCPU quota is 5 | G-02, §1.3 |
| Instances running, never join the cluster | Missing `EC2_LINUX` access entry | G-03 |
| Karpenter logs `i/o timeout` reaching STS | `dnsPolicy` deadlock against CoreDNS | G-04 |

---

## 4. Day 1 — Handing the cluster to developers

The point of the platform is that developers can use it without you. Three things to give them.

### 4.1 Cluster access

```bash
terraform output configure_kubectl
# aws eks update-kubeconfig --region us-east-1 --name opsfleet-poc
```

That command only works for an IAM principal with an **access entry**. By default the only principal
with access is whoever ran `terraform apply`.

**Do not hand out cluster-admin.** Add developers with a namespace-scoped access entry instead —
EKS supports scoping an access policy to specific namespaces, including wildcards like `team-*`:

```hcl
# terraform.tfvars
developer_principal_arns = [
  "arn:aws:iam::111122223333:role/AWSReservedSSO_Developer_abc123",
]
```

which produces an access entry associated with `AmazonEKSEditPolicy` scoped to `type = "namespace"`,
`namespaces = ["demo"]`. The four available policies:

| Policy | Grants |
|---|---|
| `AmazonEKSViewPolicy` | read-only |
| `AmazonEKSEditPolicy` | create/update/delete workloads — **the right one for developers** |
| `AmazonEKSAdminPolicy` | admin within scope |
| `AmazonEKSClusterAdminPolicy` | full cluster admin — operators only |

Prefer SSO **roles** over IAM users in that list, so access follows your identity provider.

Two caveats worth knowing before someone reports them as bugs:

- `kubectl auth can-i --list` shows **nothing** from access-policy-granted permissions. It only
  reports permissions from Kubernetes `Role`/`ClusterRole` bindings. The access is real; the
  introspection command just cannot see it.
- Access policies are **not** a privilege-escalation boundary *within* their scope. A developer with
  edit access to a namespace can create a pod that mounts a service account. Namespace scoping
  limits blast radius; it does not sandbox a hostile user.
- **Everyone sharing a namespace can see and change everyone else's work.** `AmazonEKSEditPolicy`
  grants full CRUD on `secrets` plus `pods/exec`, `pods/attach` and `pods/port-forward` within
  scope. Five developers sharing `demo` can each read the others' Secrets, exec into their pods, and
  delete their Deployments. For a POC demo that is fine. **The moment this carries more than one
  team's work, give each team its own namespace** — set `developer_namespaces` per group (the
  wildcard form `team-*` works), and give each namespace its own ResourceQuota and the same Pod
  Security labels as `demo`.
- There is **no NetworkPolicy**, so any pod can reach any other pod and the whole VPC. That is a
  documented non-goal, but read it against the access model above: the exclusion is justified as
  "single-tenant", and a namespace shared by 5-20 developers is only single-tenant in the sense that
  they all work for you.

### 4.2 What to tell them

Point them at `terraform/README.md`. The entire interface is one line:

```yaml
nodeSelector:
  kubernetes.io/arch: arm64    # or amd64
```

They do not need to know Karpenter exists.

### 4.3 What to warn them about

- **Spot.** Nodes can be reclaimed with a 2-minute warning. Handle `SIGTERM`, set a
  PodDisruptionBudget, spread replicas across nodes. `examples/deployment-arm64.yaml` demonstrates
  all three.
- **Multi-arch images.** With no `nodeSelector` a pod lands on Graviton (the arm64 pool is weighted
  higher). An x86-only image will `CrashLoopBackOff` with `exec format error`. Fix:
  `docker buildx build --platform linux/amd64,linux/arm64`.
- **Pod Security.** The `demo` namespace enforces the `restricted` profile. Pods need
  `runAsNonRoot`, a matching `runAsUser`, `seccompProfile: RuntimeDefault`, and all capabilities
  dropped.

---

## 5. Day 2 — Operations

### Cost

Idle: **~$245/month** at defaults, ~$165 with POC toggles. Full table in
[`00-architecture-and-decisions.md`](00-architecture-and-decisions.md) §5.

```bash
# What is actually running right now
kubectl get nodes -L kubernetes.io/arch,karpenter.sh/capacity-type,node.kubernetes.io/instance-type

# Spend attributed to this stack (needs cost allocation tags ACTIVATED — see below)
aws ce get-cost-and-usage --time-period Start=2026-08-01,End=2026-08-31 \
  --granularity MONTHLY --metrics UnblendedCost \
  --filter '{"Tags":{"Key":"Project","Values":["opsfleet"]}}'
```

> **One manual step Terraform cannot do for you:** cost allocation tags must be **activated** in
> Billing before `Project`/`Environment` work as a Cost Explorer dimension or a budget filter. It is
> once per account and takes up to 24 hours to take effect. Until then the budget filter matches
> nothing and the spend looks untagged.
>
> ```bash
> aws ce update-cost-allocation-tags-status --cost-allocation-tags-status \
>   TagKey=Project,Status=Active TagKey=Environment,Status=Active
> ```

The biggest levers: `single_nat_gateway = true` (−$66/mo, single point of failure) and leaving
`enable_vpc_endpoints = false` (the default — turning it on is +$263/mo).

### Upgrades

**Kubernetes:** bump `kubernetes_version`, one minor at a time, and read the release notes in
[`reference/version-pinning.md`](reference/version-pinning.md) first. The control plane upgrades
in place (~10 min); nodes are replaced by Karpenter as they drift.

**Karpenter:** bump `karpenter_version` — this upgrades **both** Helm releases, and they must stay on
the same version. The `karpenter-crd` chart is what makes CRD changes actually land; the main chart's
`crds/` directory never updates on `helm upgrade`. Check the upstream upgrade notes: v1.12.0 added a
required `ec2:DescribeInstanceStatus` permission and marked all nodes drifted; **v1.8.4 has a known
scheduling regression — do not land on it.**

**Add-ons:** `most_recent = true` re-resolves at *every* plan, so an apply you ran to change
something unrelated can also propose upgrading `vpc-cni`, `coredns`, `kube-proxy` and the EBS CSI
driver — the four components whose failure takes the data plane down. **Read every plan diff for
`aws_eks_addon` version changes.**

**Node AMI:** `node_ami_alias` defaults to `al2023@latest`, which means a new AWS AMI release marks
every node `Drifted` and Karpenter rolls the fleet — unannounced. Pin it for production:

```bash
# find the release tag the alias would resolve to
aws ssm get-parameter --region "$AWS_REGION" \
  --name "/aws/service/eks/optimized-ami/1.36/amazon-linux-2023/arm64/standard/recommended/image_id"
# valid alias values: https://github.com/awslabs/amazon-eks-ami/releases
# then set node_ami_alias = "al2023@v20260701"
```

### Break-glass

**You locked yourself out of the API endpoint.** Your IP changed, and now every `kubectl` *and*
every `terraform apply` fails (the helm provider talks to the API too). Your IAM access is fine —
only the network allowlist is wrong, and it is fixable from anywhere:

```bash
MYIP=$(curl -s https://checkip.amazonaws.com)
aws eks update-cluster-config --name "$CLUSTER" \
  --resources-vpc-config "publicAccessCidrs=${MYIP}/32,endpointPublicAccess=true"
# then reconcile Terraform so it does not revert you on the next apply:
#   set cluster_endpoint_public_access_cidrs = ["<newip>/32"] in terraform.tfvars
```

**The Terraform state is locked** after an interrupted apply — likely here, because applies run
15–20 minutes:

```bash
terraform force-unlock <LOCK_ID>     # the ID is printed in the error
```

Only do this once you are certain no other apply is running. With S3-native locking the lock is a
`.tflock` object beside the state file; you can confirm nothing is live by checking its timestamp.

**The state file is corrupted or lost.** The bucket has versioning on precisely for this:

```bash
aws s3api list-object-versions --bucket "$BUCKET" \
  --prefix eks-karpenter/terraform.tfstate --query 'Versions[:5].[VersionId,LastModified]' --output table
aws s3api get-object --bucket "$BUCKET" --key eks-karpenter/terraform.tfstate \
  --version-id <VERSION> restored.tfstate
terraform state push restored.tfstate
```

If the state is gone entirely, the cluster still exists — reimport rather than rebuild. Start with
`terraform import module.eks.aws_eks_cluster.this[0] <cluster-name>` and work outward; it is tedious
but far cheaper than a rebuild.

### Routine checks

> **What a dead Karpenter controller actually costs you.** Nothing existing breaks — running pods
> keep running and the control plane is unaffected — but no new nodes are provisioned, pending pods
> stay pending, consolidation stops, and, least obviously, **the interruption queue stops being
> drained**. The queue retains messages for 300 seconds, so Spot interruption notices that arrive
> while the controller is down are lost: those nodes are reclaimed without being drained. Nothing in
> this build alerts on it. Check the controller first whenever pods are inexplicably Pending:
>
> ```bash
> kubectl get pods -n kube-system -l app.kubernetes.io/name=karpenter
> kubectl logs -n kube-system -l app.kubernetes.io/name=karpenter --tail=100
> ```

```bash
make verify                                    # full assertion suite
kubectl get nodeclaims                         # what Karpenter currently owns
kubectl get nodes -L karpenter.sh/capacity-type # Spot vs On-Demand mix
kubectl logs -n kube-system -l app.kubernetes.io/name=karpenter --tail=100
```

---

## 6. Teardown

```bash
make destroy      # == ./scripts/teardown.sh
```

**Never run a bare `terraform destroy`.** Terraform destroys `helm_release.karpenter` before the
nodes it manages, which removes the only controller that reconciles the `karpenter.sh/termination`
finalizer. Live nodes then never terminate, their ENIs stay attached, and those ENIs block deleting
the security groups and subnets — leaving a half-destroyed stack and running instances nobody is
tracking. Full mechanism in [`reference/gotchas.md`](reference/gotchas.md) G-09.

`teardown.sh` does it in the order that works and **refuses to continue** if instances remain.

Afterwards:

```bash
# Karpenter creates launch templates outside Terraform state — nothing else cleans them up
aws ec2 describe-launch-templates \
  --filters "Name=tag:karpenter.k8s.aws/cluster,Values=$CLUSTER" \
  --query 'LaunchTemplates[].LaunchTemplateName' --output text

# The state bucket and its KMS key are NOT destroyed — bootstrap/ is a separate stack.
# Destroy it only when you are finished with the account entirely.
terraform -chdir=bootstrap destroy
```

---

## 7. Quick reference

```bash
# ---- free, no credentials ----
make check              # everything static: fmt, validate, test, lint, scan

# ---- day 0, once per account ----
make bootstrap          # S3 + KMS state backend
cp backend.hcl.example backend.hcl && $EDITOR backend.hcl
cp terraform.tfvars.example terraform.tfvars && $EDITOR terraform.tfvars   # set your /32
make init

# ---- day 1, staged ----
make stage-network      # ~4 min   -> meter starts
make stage-cluster      # ~15 min
make stage-karpenter    # ~3 min
make apply              # converge (REQUIRED after targeted applies)
make verify

# ---- prove it ----
make demo               # Graviton + x86 pods, prints where each landed
make demo-clean

# ---- stop paying ----
make destroy
```

`make help` lists every target.
