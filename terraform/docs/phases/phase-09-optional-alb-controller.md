# Phase 9 *(optional)* — AWS Load Balancer Controller

**Depends on:** Phase 5.
**Status:** optional. Implement only when explicitly asked. The core assignment does not require it.

---

## Goal

Ingress into the cluster: an in-cluster controller that turns `Ingress` objects into ALBs and
`Service type=LoadBalancer` into NLBs, authenticated with Pod Identity, so the demo application can
actually be reached from a browser.

---

## Why it is optional

The assignment asks for a cluster, autoscaling and a scheduling demo. Nothing needs an ingress
controller. Adding it costs an ALB (~$16/month plus LCU charges) and expands the blast radius.

Where it earns its place: a reviewer who asks *"how would a developer expose this service?"* gets a
concrete answer instead of a hand-wave. If you implement it, the README gets one short section — not
a second act.

---

## Inputs

| Source | What you need |
|---|---|
| `reference/gotchas.md` | **G-14** — `expect exactly one securityGroup tagged...`; this phase is where that bites |
| `contracts/interface-contract.md` | §2.3 subnet tags (`kubernetes.io/role/elb`, `internal-elb`) — Phase 1 already applied them |
| `phase-02` completion report | Confirm `attach_cluster_primary_security_group` was left `false` |

---

## Files to create

```
modules/aws-lb-controller/versions.tf
modules/aws-lb-controller/variables.tf
modules/aws-lb-controller/main.tf
modules/aws-lb-controller/iam.tf
modules/aws-lb-controller/outputs.tf
modules/aws-lb-controller/README.md
examples/ingress-demo.yaml
```

Gate it in `main.tf` on `var.enable_aws_load_balancer_controller` (default `false`). **The count must
come from that static variable, never from cluster state** — see `gotchas.md` §Provider-ordering.

---

## Specification

### 9.1 Verify before you build

Three things change often enough that you must check them rather than trust this document:

```bash
# 1. Current chart version
helm repo add eks https://aws.github.io/eks-charts && helm repo update
helm search repo eks/aws-load-balancer-controller --versions | head -5

# 2. Does Pod Identity support exist in that version, or is IRSA still required?
#    LBC gained Pod Identity support relatively recently; confirm for the version you pin.
helm show values eks/aws-load-balancer-controller --version <X.Y.Z> | grep -A5 serviceAccount

# 3. Is there now an EKS *managed add-on* for it? If so, prefer that over Helm —
#    it removes a chart to maintain.
aws eks describe-addon-versions --query "addons[?contains(addonName,'load-balancer')].addonName"
```

Record what you found in the completion report and pin accordingly. If Pod Identity is not supported
in the version you pin, use IRSA and **say so** — the cluster has `enable_irsa` on for exactly this
kind of case.

### 9.2 IAM policy — take AWS's, do not write your own

```bash
curl -o iam-policy.json \
  https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/<TAG>/docs/install/iam_policy.json
```

Embed it as a `aws_iam_policy` with `file()` or a heredoc, with a comment recording the source URL
and tag. It is long, it is fiddly, and hand-editing it is how people end up with a controller that
can create load balancers but not delete them — which then blocks `terraform destroy` (G-12).

Trust policy is the same Pod Identity shape as Phase 2 §2.5: `pods.eks.amazonaws.com` with
`sts:AssumeRole` **and** `sts:TagSession`.

### 9.3 Helm release

```hcl
resource "helm_release" "aws_lb_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = var.chart_version
  namespace  = "kube-system"
  wait       = true

  set = [                                    # helm provider v3: list of objects
    { name = "clusterName", value = var.cluster_name },
    { name = "region", value = var.region },
    { name = "vpcId", value = var.vpc_id },
    { name = "serviceAccount.name", value = "aws-load-balancer-controller" },
    # Two replicas by default; on a tainted bootstrap group they need a toleration.
    { name = "tolerations[0].key", value = "CriticalAddonsOnly" },
    { name = "tolerations[0].operator", value = "Exists" },
  ]
}
```

**If Phase 2 tainted the bootstrap nodes** (`taint_bootstrap_nodes = true`, the default), this
controller will not schedule without that toleration — and it cannot run on Karpenter nodes reliably
before it exists. Verify with `kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller`.

### 9.4 The security-group trap

G-14 in full: if `attach_cluster_primary_security_group = true`, nodes carry both the EKS cluster
primary SG and the module's node SG, both tagged `kubernetes.io/cluster/<name>`, and the controller
refuses with `expect exactly one securityGroup tagged with kubernetes.io/cluster/<CLUSTER_NAME>`.

Phase 2 leaves it at the default `false`. Confirm that is still true before debugging anything else.

### 9.5 `examples/ingress-demo.yaml`

An `Ingress` for the Phase 6 `web-graviton` deployment. **Default it to `internal`**:

```yaml
  annotations:
    alb.ingress.kubernetes.io/scheme: internal          # internet-facing is a deliberate choice
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}]'
```

Include a commented internet-facing variant with a warning that it needs an ACM certificate and
should carry `alb.ingress.kubernetes.io/inbound-cidrs` rather than defaulting open.

---

## Security requirements owned by this phase

- **S-90** IAM policy is AWS's published document, unmodified, with the source URL and tag recorded.
- **S-91** Example ingress defaults to `internal`; internet-facing is opt-in, with TLS and a CIDR
  restriction.
- Credentials via Pod Identity where the pinned version supports it; IRSA otherwise, documented.

---

## Acceptance criteria

```bash
terraform fmt -check -recursive && terraform validate

# The toggle is static, not cluster-derived
grep -n 'count.*enable_aws_load_balancer_controller' main.tf

# Default off
grep -A3 'variable "enable_aws_load_balancer_controller"' variables.tf | grep 'default *= *false'
```

With credentials:

```bash
terraform apply -var enable_aws_load_balancer_controller=true
kubectl get deploy -n kube-system aws-load-balancer-controller     # 2/2 Ready

kubectl apply -f examples/namespace.yaml -f examples/deployment-arm64.yaml -f examples/ingress-demo.yaml
kubectl get ingress -n demo -w        # ADDRESS populates in 2-3 minutes
aws elbv2 describe-load-balancers --query 'LoadBalancers[].{Name:LoadBalancerName,Scheme:Scheme}'
# Scheme must be "internal"

# CLEAN UP BEFORE DESTROYING — G-12
kubectl delete ingress -n demo --all
sleep 60
aws elbv2 describe-load-balancers --query 'length(LoadBalancers)'   # back to 0
```

---

## Agent prompt

```text
Implement Phase 9 (OPTIONAL) of the EKS + Karpenter Terraform assessment.

Working directory: /home/artin/personal/git/opsfleet/terraform

SCOPE BOUNDARY — non-negotiable, applies to every action you take:
  1. Your working directory is /home/artin/personal/git/opsfleet/terraform. You never leave it.
     Every path in this prompt and in every doc it references is RELATIVE TO THAT DIRECTORY.
  2. The sibling directory /home/artin/personal/git/opsfleet/architecture is a DIFFERENT,
     UNRELATED assessment. Do not read it, write to it, list it, grep it, or cd into it.
  3. Create NOTHING at the repository root. Everything lives under terraform/.
  4. Do not run repo-wide searches. Scope every search to terraform/.

Read, in this order:
  1. docs/reference/gotchas.md                          (G-12, G-14)
  2. docs/contracts/interface-contract.md               (§2.3 subnet tags, §7 providers)
  3. docs/phases/phase-09-optional-alb-controller.md    (your specification)
  4. docs/phases/phase-02-eks-cluster.md                (Completion report — confirm
                                                         attach_cluster_primary_security_group
                                                         is false and whether nodes are tainted)

Implement modules/aws-lb-controller/ and examples/ingress-demo.yaml.

Critical constraints:
  - FIRST run the three verification commands in §9.1 and report what you found. Pin the chart
    version you verified; do not assume Pod Identity is supported until you have checked.
  - Use AWS's published iam_policy.json verbatim. Record its source URL and tag in a comment.
  - Gate everything on var.enable_aws_load_balancer_controller, default false. The count must
    derive from that STATIC variable, never from cluster state.
  - The example ingress defaults to scheme: internal.
  - If the bootstrap nodes are tainted, add the CriticalAddonsOnly toleration.
  - terraform fmt -recursive must be clean.
  - Do NOT run terraform apply unless I have told you credentials are available.

When finished, fill in the "## Completion report" at the bottom of
docs/phases/phase-09-optional-alb-controller.md and stop.
```

---

## Completion report

- Status:
- **Chart version pinned, and whether Pod Identity or IRSA was used (with evidence):**
- Files created/changed:
- Deviations from spec:
- Verification run:
- Notes:
