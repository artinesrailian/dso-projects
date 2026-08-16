# Phase 10 *(optional)* — metrics-server and an end-to-end autoscaling demo

**Depends on:** Phase 5.
**Status:** optional. Implement only when explicitly asked.

---

## Goal

Close the autoscaling loop so it can be *demonstrated* rather than described: load rises → the HPA
adds pods → the pods do not fit → **Karpenter provisions a node** → load falls → HPA removes pods →
Karpenter consolidates the node away.

That two-level cascade is the single most convincing thing you can show a reviewer, because it
exercises Karpenter through the path a real workload takes rather than through a hand-applied
`nodeSelector`.

---

## Inputs

| Source | What you need |
|---|---|
| `reference/version-pinning.md` | The add-on table |
| `phase-02` completion report | Whether the bootstrap nodes are tainted (metrics-server needs the toleration if so) |
| `phase-05` completion report | The NodePool `limits`, so the load test cannot exceed them |

---

## Files to create

```
examples/hpa-demo.yaml
examples/loadgen.yaml
docs/DEMO.md              # the scripted walkthrough
```

Plus **edit** `modules/eks/main.tf` to add the `metrics-server` add-on, gated on
`var.enable_metrics_server` (default `false`).

---

## Specification

### 10.1 Install metrics-server as an EKS add-on

`metrics-server` is available as an EKS **community** add-on — AWS validates version compatibility
and manages the install/update/delete lifecycle, but does not support the software itself. That is
still better than another Helm release to maintain.

```hcl
    metrics-server = {
      most_recent = true
    }
```

Verify the add-on name and that it is offered in your region before relying on it:

```bash
aws eks describe-addon-versions --addon-name metrics-server \
  --kubernetes-version 1.36 --query 'addons[].addonName'
```

If it is not available, fall back to the upstream Helm chart
(`https://kubernetes-sigs.github.io/metrics-server/`) and note the deviation. metrics-server needs
no IAM identity of any kind.

**If the bootstrap nodes are tainted**, metrics-server needs the `CriticalAddonsOnly` toleration or
it stays `Pending` — supply it through `configuration_values`, and verify.

### 10.2 `examples/hpa-demo.yaml`

A deployment plus an HPA. The numbers matter: they must reliably trigger a *node* scale-up, not just
a pod scale-up, without exceeding the NodePool `limits`.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hpa-demo
  namespace: demo
spec:
  replicas: 1
  # ... standard pod spec, public.ecr.aws image, securityContext as Phase 6
      containers:
        - name: app
          # Same image as Phase 6, for the same reason: the `demo` namespace
          # enforces the `restricted` Pod Security profile, which rejects any
          # image that runs as root. Port 8080, runAsUser 101, seccompProfile
          # RuntimeDefault — copy the securityContext from Phase 6 verbatim.
          image: public.ecr.aws/nginx/nginx-unprivileged:stable
          resources:
            requests:
              cpu: 500m        # 500m x maxReplicas must exceed one node's capacity,
              memory: 128Mi    # or Karpenter never has to provision anything
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: hpa-demo
  namespace: demo
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: hpa-demo
  minReplicas: 1
  maxReplicas: 20              # 20 x 500m = 10 vCPU: forces multiple nodes.
                               # Check this against the PER-POOL limit, not the
                               # total: nodepool_cpu_limit is divided across the
                               # enabled pools, so the default 100 is 50 per pool.
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 50
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 60   # default is 300s; too slow for a live demo
```

**Sanity-check the arithmetic against the account quota (G-02).** 10 vCPU of demo load on an account
with the default 5-vCPU limit will fail, and the failure will look like a Karpenter bug. Either
confirm the quota was raised or scale `maxReplicas` down and say so.

### 10.3 `examples/loadgen.yaml`

A Job or Deployment that generates CPU load against the demo service. Keep it trivial — `wget` in a
loop from a busybox image is enough. Give it a hard time limit (`activeDeadlineSeconds`) so a
forgotten load generator cannot quietly hold 10 vCPU of Spot capacity overnight.

### 10.4 `docs/DEMO.md` — the walkthrough

The deliverable of this phase is really this file: a scripted demo someone can follow live, with
what to watch and roughly when.

```markdown
## Terminal 1 — watch nodes appear and disappear
kubectl get nodes -L kubernetes.io/arch,karpenter.sh/capacity-type -w

## Terminal 2 — watch pods and the HPA
watch -n2 'kubectl get hpa,pods -n demo'

## Terminal 3 — drive it
kubectl apply -f examples/hpa-demo.yaml
kubectl apply -f examples/loadgen.yaml

# t+0:30  HPA reports rising CPU, replicas start climbing
# t+1:00  pods go Pending — the existing nodes are full
# t+1:15  a NodeClaim appears; Karpenter has called CreateFleet
# t+2:00  the new node is Ready and the pending pods schedule
# t+X     delete the loadgen; HPA scales down after its 60s window
# t+X+5m  nodes go empty, and consolidateAfter=5m triggers removal
kubectl delete -f examples/loadgen.yaml
```

Include the one-liner that makes the point concrete:

```bash
kubectl get nodes -l karpenter.sh/nodepool -o custom-columns=\
NAME:.metadata.name,ARCH:.metadata.labels.kubernetes\\.io/arch,\
TYPE:.metadata.labels.node\\.kubernetes\\.io/instance-type,\
CAPACITY:.metadata.labels.karpenter\\.sh/capacity-type
```

---

## Security requirements owned by this phase

- **S-92** metrics-server is not exposed outside the cluster, runs with a read-only root filesystem
  and as non-root, and holds no IAM identity.
- The load generator has an `activeDeadlineSeconds` so it cannot run away.
- The HPA `maxReplicas` × CPU request stays below the NodePool `limits` (S-52), so the demo cannot
  exhaust the cluster's blast-radius cap.

---

## Acceptance criteria

```bash
kubeconform -strict -kubernetes-version 1.36.0 examples/hpa-demo.yaml examples/loadgen.yaml
grep -q 'activeDeadlineSeconds' examples/loadgen.yaml && echo "PASS: loadgen bounded"
```

With credentials — the full cascade:

```bash
terraform apply -var enable_metrics_server=true
kubectl top nodes                          # metrics-server working
kubectl apply -f examples/hpa-demo.yaml -f examples/loadgen.yaml

# within ~2 minutes
kubectl get hpa -n demo                    # REPLICAS climbing
kubectl get nodeclaims                     # a new NodeClaim
kubectl get nodes -l karpenter.sh/nodepool # a new node

kubectl delete -f examples/loadgen.yaml
sleep 300
kubectl get nodes -l karpenter.sh/nodepool # consolidated away
```

**Paste the real output of the scale-up into the completion report.** This is the phase's evidence.

---

## Agent prompt

```text
Implement Phase 10 (OPTIONAL) of the EKS + Karpenter Terraform assessment.

Working directory: /home/artin/personal/git/dso-projects/terraform

SCOPE BOUNDARY — non-negotiable, applies to every action you take:
  1. Your working directory is /home/artin/personal/git/dso-projects/terraform. You never leave it.
     Every path in this prompt and in every doc it references is RELATIVE TO THAT DIRECTORY.
  2. The sibling directory /home/artin/personal/git/dso-projects/architecture is a DIFFERENT,
     UNRELATED assessment. Do not read it, write to it, list it, grep it, or cd into it.
  3. Create NOTHING at the repository root. Everything lives under terraform/.
  4. Do not run repo-wide searches. Scope every search to terraform/.

Read, in this order:
  1. docs/phases/phase-10-optional-metrics-hpa.md   (your specification)
  2. docs/phases/phase-02-eks-cluster.md            (Completion report — are the bootstrap
                                                     nodes tainted?)
  3. docs/phases/phase-05-nodepools.md              (Completion report — the NodePool cpu limit)
  4. docs/00-architecture-and-decisions.md          (§4 P3 — the vCPU quota trap)

Add the metrics-server add-on (gated on var.enable_metrics_server, default false) and create
examples/hpa-demo.yaml, examples/loadgen.yaml and docs/DEMO.md.

Critical constraints:
  - Verify metrics-server is offered as an EKS add-on for Kubernetes 1.36 before using it;
    fall back to the upstream Helm chart and note the deviation if not.
  - If the bootstrap nodes are tainted, metrics-server needs the CriticalAddonsOnly toleration.
  - maxReplicas x cpu request must exceed one node's capacity (so Karpenter must provision)
    but stay under the NodePool cpu limit. Show your arithmetic in a comment.
  - Cross-check that arithmetic against the account's vCPU quota — on a default 5-vCPU account
    the demo will fail and look like a Karpenter bug. Scale it down and say so if needed.
  - loadgen must have activeDeadlineSeconds so it cannot run away.
  - Do NOT run terraform apply unless I have told you credentials are available.

When finished, fill in the "## Completion report" at the bottom of
docs/phases/phase-10-optional-metrics-hpa.md and stop.
```

---

## Completion report

- Status:
- Files created/changed:
- **HPA arithmetic** (replicas × request vs node capacity vs NodePool limit vs account quota):
- Deviations from spec:
- **Actual scale-up output, if applied:**
- Notes:
