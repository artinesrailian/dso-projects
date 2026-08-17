# Known Gotchas

Failure modes that a first-time EKS + Karpenter Terraform deployment actually hits, ordered roughly
by how likely they are to bite. Each entry: **symptom → root cause → fix**.

The common thread: almost none of these produce a useful error message. Most present as "pods stay
Pending" or "nodes never appear", which is why they cost hours.

---

## Tier 1 — will break your first apply

### G-01 · Cluster applies, then everything is `Unauthorized`

**Symptom.** `terraform apply` succeeds. Then `kubectl get nodes` returns *"error: You must be
logged in to the server (Unauthorized)"*, and any `helm_release` fails with a forbidden error.

**Root cause.** `enable_cluster_creator_admin_permissions` defaults to **`false`** in the EKS module,
and the module hardcodes the EKS API's own `bootstrap_cluster_creator_admin_permissions` to false.
The identity that created the cluster gets no Kubernetes RBAC whatsoever.

**Fix.** `enable_cluster_creator_admin_permissions = true`. This creates an access entry and can be
toggled at any time — unlike the underlying API flag, which is create-time-only.

---

### G-02 · vCPU quota wall on a fresh account

**Symptom.** Cluster and Karpenter come up healthy. The first workload stays `Pending`; Karpenter
logs `VcpuLimitExceeded`. Reads like a Karpenter misconfiguration.

**Root cause.** A new AWS account has **5 vCPUs** per region for `L-1216C47A` (On-Demand Standard)
and **5** for `L-34B43A08` (Spot Standard). The bootstrap node group — 2 × `t4g.medium` — consumes
4 of the 5 On-Demand vCPUs before Karpenter launches anything.

**Fix.** Request increases on **both** codes before the first apply. Two traps: On-Demand and Spot
are independent quotas, and there is **no separate Graviton quota** — arm64 families (t4g, m7g, c7g,
r8g…) are all T/M/C/R and share the same Standard pool as x86.

---

### G-03 · Karpenter nodes launch but never join the cluster

**Symptom.** EC2 instances are `running`. They never appear in `kubectl get nodes`. Node kubelet
logs (via SSM): `Unable to register node with API server" err="Unauthorized"`.

**Root cause.** Under `authentication_mode = "API"` a node's IAM role must have an EKS **access
entry** of type `EC2_LINUX`. Without it the node authenticates as nobody.

**The trap that doubles the debugging time:** Karpenter's own troubleshooting page tells you to
inspect the `aws-auth` ConfigMap. Under `API` mode aws-auth is **ignored entirely**, so you can edit
it all day and nothing changes — with no error to explain why.

**Fix.** Use the `eks//modules/karpenter` submodule with `create_access_entry = true` (the default)
and let it create its own node role. The real-world failure path is someone setting
`create_node_iam_role = false` and bringing their own role, or hand-rolling the IAM outside the
submodule — then no access entry exists.

---

### G-04 · Karpenter deadlocks against CoreDNS at startup

**Symptom.** Karpenter never becomes ready. Logs:
`WebIdentityErr: failed to retrieve credentials ... dial tcp: lookup sts.us-east-1.amazonaws.com: i/o timeout`.

**Root cause.** The chart defaults to `dnsPolicy: ClusterFirst`, so Karpenter resolves DNS through
in-cluster CoreDNS. If CoreDNS is itself waiting on capacity that only Karpenter can provide, neither
can proceed. A clean circular wait.

**Fix.** `--set dnsPolicy=Default` — resolve via the host's VPC DNS instead. The upstream module
example does this. Guaranteeing bootstrap capacity with correct tolerations for CoreDNS also breaks
the cycle; do both.

---

### G-05 · Only one Karpenter replica ever runs

**Symptom.** One Karpenter pod `Running`, one `Pending` forever. No autoscaling happens. Karpenter
never fixes it.

**Root cause.** The chart runs `replicas: 2` with a **required** `podAntiAffinity` on
`kubernetes.io/hostname`, so it needs two distinct nodes. And Karpenter's own node affinity requires
`karpenter.sh/nodepool` `DoesNotExist` — it structurally will not launch capacity to run itself.

**Fix.** Bootstrap node group `min_size = 2` / `desired_size = 2`. Or reduce `replicas`, losing HA.

**Related trap:** raising `desired_size` in HCL to fix this does nothing — see G-06.

---

### G-06 · Changing `desired_size` produces "No changes"

**Symptom.** You raise `desired_size` on the managed node group, `terraform apply` reports no
changes, and the extra node never appears.

**Root cause.** The EKS module deliberately puts `desired_size` in `lifecycle { ignore_changes }`,
so that autoscalers can move it without Terraform fighting them. The module documents this: *"The
setting is ignored to allow autoscaling via controllers such as cluster autoscaler or Karpenter to
work properly... Changing the desired count must be handled outside of Terraform."*

**Fix.** Change `min_size` instead, or use `aws eks update-nodegroup-config`.

---

### G-07 · Missing EC2 Spot service-linked role

**Symptom.** Spot launches fail; pods stay `Pending`. Karpenter logs
`AuthFailure.ServiceLinkedRoleCreationNotPermitted: The provided credentials do not have permission
to create the service-linked role for EC2 Spot Instances`.

**Root cause.** `AWSServiceRoleForEC2Spot` does not exist. Any account that has never launched a Spot
instance lacks it.

**Fix.** `aws iam create-service-linked-role --aws-service-name spot.amazonaws.com` (one-time, per
account). If it already exists you get `InvalidInput: ... has been taken in this account`, which is
safe to ignore — upstream scripts append `|| true`. Managing it in Terraform requires a toggle
defaulted **off**, because the resource fails on accounts that already have it.

---

### G-08 · Cluster comes up with no CNI and no DNS

**Symptom.** The cluster creates successfully. Nodes join and go `NotReady`, or go `Ready` and no
pod ever gets an IP. `kubectl get pods -n kube-system` is nearly empty — no `aws-node`, no
`coredns`, no `kube-proxy`.

**Root cause.** EKS module v21.24.2 hardcodes the cluster's `bootstrap_self_managed_addons` to
`false` (not exposed as a variable, and in `lifecycle.ignore_changes`). A console- or API-created
cluster ships `vpc-cni`, `coredns` and `kube-proxy` as self-managed components; a cluster created by
**this module ships nothing**. Whatever you do not list in `addons` simply does not exist.

**Fix.** Declare `vpc-cni`, `coredns` and `kube-proxy` explicitly in the `addons` map, plus
`eks-pod-identity-agent` (required for Karpenter's controller credentials).

**The related-but-different trap.** v21 also changed `addons.resolve_conflicts_on_create` from
`OVERWRITE` to **`NONE`**, so if a conflicting resource *does* exist — a cluster created another way,
or an add-on installed by hand — creation fails instead of adopting it. Setting `OVERWRITE` on those
three costs nothing and covers that case. It is a safety net, not the fix for the symptom above.

---

## Tier 2 — will break your `terraform destroy`

### G-09 · The destroy deadlock — orphaned nodes, then a VPC that will not delete

**This is the highest-value item in this document.** It produces a half-destroyed stack, surviving
EC2 instances that nobody is tracking, and an ongoing bill.

**Symptom.** `terraform destroy` runs for ~10 minutes and then fails with `DependencyViolation` on a
security group, or *"The subnet has dependencies and cannot be deleted"*. Meanwhile EC2 instances
are still running and are no longer in any Terraform state.

**Root cause.** A dependency chain that Terraform gets exactly backwards:

1. `helm_release.karpenter` references `module.eks` outputs → Terraform destroys the Helm release
   **first**.
2. That deletes the Karpenter controller — the only thing that reconciles the
   `karpenter.sh/termination` finalizer.
3. Live NodeClaims and their nodes now never drain and never terminate. The EC2 instances survive.
4. Their VPC CNI ENIs stay attached, referencing the node security group.
5. Those ENIs are the `DependencyViolation` that blocks deleting the security group and subnets.

Karpenter's published teardown sequence is written for eksctl/CloudFormation and does not cover this
Terraform-specific ordering at all.

**Fix — the order that works:**

```bash
# 1. Remove workloads so Karpenter consolidates its nodes away.
kubectl delete -f examples/ --ignore-not-found
kubectl delete namespace demo --ignore-not-found

# 2. Delete NodePools first — cascades to their NodeClaims via owner
#    references and blocks Karpenter from launching anything new against
#    them. Then delete NodeClaims explicitly as belt-and-braces. WAIT on
#    both; Karpenter drains and terminates while the controller is alive.
kubectl delete nodepools --all --wait=true --timeout=15m
kubectl delete nodeclaims --all --wait=true --timeout=15m

# 3. Prove nothing is left before touching Terraform.
aws ec2 describe-instances \
  --filters "Name=tag:karpenter.sh/nodepool,Values=*" \
            "Name=tag:eks:eks-cluster-name,Values=$CLUSTER" \
            "Name=instance-state-name,Values=running,pending,stopping,stopped" \
  --query 'Reservations[].Instances[].InstanceId' --output text
# Must be empty.

# 4. Now destroy.
terraform destroy
```

**On the tag in step 3 — read this before trusting an older copy of this recipe.** An earlier
version of this fix (and of `scripts/teardown.sh`) queried `karpenter.sh/managed-by`. Karpenter's own
v1 migration guide states that tag was **replaced by `eks:eks-cluster-name`** — v1.14.0 does not set
it at all. Querying it alone means step 3 always finds nothing, which reads as "safe to destroy"
whether or not instances are actually running — the exact failure this whole fix exists to prevent.
`karpenter.sh/nodepool=*` is not cluster-scoped by itself either (it matches *any* Karpenter cluster
in the region); ANDing it with a cluster-scoped tag, as above, is what makes the check real.
`scripts/teardown.sh` runs this same query two independent ways (`eks:eks-cluster-name` and
`kubernetes.io/cluster/<name>=owned`) so a gap in one tag doesn't silently pass the gate.

Phase 8 turns this into a scripted, verified runbook.

---

### G-10 · Nodes stuck `Terminating` forever

**Symptom.** Nodes hang in `Terminating`; namespace or cluster deletion blocks.

**Root cause.** Karpenter adds a `karpenter.sh/termination` finalizer to every node it provisions. If
Karpenter is gone, nothing removes it and the API server blocks deletion indefinitely.

**Fix** (Karpenter's documented one-liner):

```bash
kubectl get nodes -ojsonpath='{range .items[*].metadata}{@.name}:{@.finalizers}{"\n"}' \
  | grep "karpenter.sh/termination" | cut -d ':' -f 1 \
  | xargs kubectl patch node --type='json' -p='[{"op": "remove", "path": "/metadata/finalizers"}]'
```

⚠️ Karpenter's docs warn this strips **all** finalizers from those nodes, not just Karpenter's. It is
a recovery tool, not routine cleanup.

---

### G-11 · Orphaned launch templates

**Symptom.** Nothing visibly breaks; launch templates accumulate in the account forever.

**Root cause.** Karpenter creates launch templates outside Terraform state, tagged
`karpenter.k8s.aws/cluster`. Nothing in Terraform knows about them.

**Fix.** Sweep after destroy:

```bash
aws ec2 describe-launch-templates \
  --filters "Name=tag:karpenter.k8s.aws/cluster,Values=${CLUSTER}" \
  --query 'LaunchTemplates[].LaunchTemplateName' --output text \
  | tr '\t' '\n' | xargs -r -I{} aws ec2 delete-launch-template --launch-template-name {}
```

---

### G-12 · Load balancers created in-cluster survive the destroy

**Symptom.** ELBs/NLBs remain after `terraform destroy`; their ENIs block subnet deletion.

**Root cause.** Load balancers created by a `Service type=LoadBalancer` or an `Ingress` are made by
an in-cluster controller. Terraform never knew about them.

**Fix.** Delete Kubernetes `Service`/`Ingress` objects **before** destroying AWS resources, and give
them time to unwind. HashiCorp's own EKS example does this in explicit stages for exactly this
reason.

---

## Tier 3 — silent misbehaviour

### G-13 · Karpenter finds no subnets or no security groups

**Symptom.** `kubectl describe nodepool` / controller logs report `no subnets found` or
`no security groups found`. Pods stay `Pending`.

**Root cause.** The `karpenter.sh/discovery` tag value and the `EC2NodeClass` selector disagree — or
the node security group was never tagged, because it is created by the **EKS** module, not the VPC
module.

**Fix.** Tag private subnets in the network module and the node SG via the EKS module's
`node_security_group_tags`. Both must read from the same variable. **At most one security group in
the account may carry the tag** — the selector matches account-wide, and a second tagged SG makes
Karpenter pick the wrong one.

---

### G-14 · `expect exactly one securityGroup tagged with kubernetes.io/cluster/<name>`

**Symptom.** AWS Load Balancer Controller refuses to provision (Phase 9).

**Root cause.** `attach_cluster_primary_security_group = true` attaches both the EKS-created cluster
primary SG and the module's node SG to every node; both carry the cluster tag.

**Fix.** Leave `attach_cluster_primary_security_group` at its default `false`. Alternatively
`create_node_security_group = false`.

---

### G-15 · A pod requests a label Karpenter does not know, and waits forever

**Symptom.** Pod `Pending`. No Karpenter error. Nothing provisions.

**Root cause.** Karpenter's docs: *"If you specify a nodeSelector or a required nodeAffinity using a
label that is not well-known to Karpenter, it will not launch nodes with these labels and pods will
remain pending."*

The nastier variant is a near-miss on a real label: `karpenter.k8s.aws/instance-family` is
well-known and enforces node properties, while `node.kubernetes.io/instance-family` is **not** and is
silently treated as an arbitrary custom label. One character of difference, no error either way.

**Fix.** Only use well-known labels (listed in `karpenter-api-reference.md` §3), or add the custom
label to the NodePool `requirements` with the `Exists` operator.

---

### G-16 · x86-only image lands on Graviton

**Symptom.** `CrashLoopBackOff` with `exec format error`.

**Root cause.** A pod with no `kubernetes.io/arch` constraint is eligible for any NodePool that
matches. With arm64 weighted higher (this build's default), it lands on Graviton.

**Fix.** Publish multi-arch images
(`docker buildx build --platform linux/amd64,linux/arm64`), or pin with
`nodeSelector: {kubernetes.io/arch: amd64}`, or flip `nodepool_default_arch`. Note that EKS-managed
add-ons (VPC CNI, EBS CSI, CoreDNS, kube-proxy) are all multi-arch already and need no configuration
in a mixed cluster — the risk is entirely in application images and third-party charts.

---

### G-17 · `NodePool` rejected for a missing `consolidateAfter`

**Symptom.** `spec.disruption.consolidateAfter: Required value`.

**Root cause.** `consolidateAfter` is in the `disruption` object's `required` list, while `disruption`
itself has a default. The default applies only when the **whole block** is absent — so setting just
`consolidationPolicy` fails.

**Fix.** Always set both. See `karpenter-api-reference.md` §3.

---

### G-18 · CRD changes never land on upgrade

**Symptom.** After bumping the chart version, new fields are rejected: `strict decoding error:
unknown field ...`.

**Root cause.** CRDs in a chart's `crds/` directory are installed on first install only; `helm
upgrade` never touches them.

**Fix.** Use the separate `karpenter-crd` chart, ordered before the controller chart. See
`version-pinning.md` §2.1.

**If you are adopting CRDs that already exist**, Helm refuses with `invalid ownership metadata;
label validation error: missing key "app.kubernetes.io/managed-by"`. The documented fix:

```bash
kubectl label crd ec2nodeclasses.karpenter.k8s.aws nodepools.karpenter.sh nodeclaims.karpenter.sh \
  app.kubernetes.io/managed-by=Helm --overwrite
kubectl annotate crd ec2nodeclasses.karpenter.k8s.aws nodepools.karpenter.sh nodeclaims.karpenter.sh \
  meta.helm.sh/release-name=karpenter-crd meta.helm.sh/release-namespace=kube-system --overwrite
```

---

### G-19 · `no matches for kind "NodePool"` during apply

**Symptom.** The Helm release succeeds and then applying a NodePool in the same run fails.

**Root cause.** The upstream example sets `wait = false` on the Karpenter release, so apply returns
before the controller is Running and before its CRDs are established. The example hides this by
having you run `kubectl apply` manually afterwards; anyone automating both steps in one pipeline
hits the race.

**Fix.** `wait = true` on both releases, plus `depends_on` from the resources chart to the controller
release.

---

### G-20 · Intermittent `401 Unauthorized` partway through a long apply

**Symptom.** Apply runs for 15+ minutes, then Kubernetes-side operations start failing.

**Root cause.** `data.aws_eks_cluster_auth` produces a token with a **15-minute** lifetime, written
into state. A long apply outlives it.

**Fix.** Use `exec` auth (`aws eks get-token`), which fetches a fresh token per invocation. Requires
the AWS CLI on the Terraform runner.

---

### G-21 · Copy-pasted Helm config will not parse

**Symptom.** Type errors on `helm_release`, or `Blocks of type "set" are not expected here`.

**Root cause.** `hashicorp/helm` v3 moved to the Plugin Framework. Blocks became attributes.

**Fix.** `kubernetes = { ... }` not `kubernetes { ... }`; `set = [{name=…, value=…}]` not repeated
`set { }` blocks; `registries = [...]` not repeated `registry { }`. See `version-pinning.md` §2.2.

---

### G-22 · Following a pre-v21 example verbatim

**Symptom.** `Unsupported argument` on half your EKS module block.

**Root cause.** v21 stripped the `cluster_` prefix from most root inputs but left the outputs alone.
The karpenter submodule additionally removed all six IRSA/Pod-Identity toggles.

**Fix.** `version-pinning.md` §4 has the complete rename table.

Also note: the module's own `examples/karpenter/` pins chart `1.6.0` and Kubernetes `1.33`. Copying
it verbatim gets you a chart eight minors behind. And when upgrading Karpenter, avoid **v1.8.4** —
it carries a documented regression affecting `TopologySpreadConstraint` scheduling.

---

## Provider-ordering: the rule

The recurring "provider configuration not known until apply" problem reduces to one rule:

> **Provider *configuration* may reference values that are unknown until apply. Resource `count` and
> `for_each` may not.**

So `provider "helm" { kubernetes = { host = module.eks.cluster_endpoint ... } }` is fine, while
`count = length(data.something_from_the_cluster.x)` is not. Gate conditional resources on **static
input variables** only.

Upstream guidance genuinely disagrees on the larger question, and it is worth knowing rather than
resolving: the `terraform-aws-modules/eks` Karpenter example uses a **single** root module with only
`aws` and `helm` providers, while HashiCorp's own EKS example insists on **separate states** for
Kubernetes-side resources. Both are current as of 2026-08. This build follows the module example
(ADR-6); the recovery path if the single-stack apply ever wedges is:

```bash
terraform apply -target=module.network -target=module.eks
terraform apply
```
