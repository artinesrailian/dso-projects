# Running your workload on x86 or Graviton

You do not need to know anything about Karpenter, NodePools, or instance types.
Pick an architecture with one label, apply, and Karpenter provisions the node for you.

## 1. Get access

```bash
aws eks update-kubeconfig --region <region> --name <cluster-name>
```

Your `demo` namespace already exists — the platform team's Terraform creates it, with a
Pod Security profile, a ResourceQuota and a LimitRange already applied. Don't create it
yourself and don't ask for `kubectl create namespace`; there's nothing to set up.

## 2. Run on Graviton (arm64) — the default, cheapest option

```bash
kubectl apply -f deployment-arm64.yaml
kubectl get nodeclaims -w                     # watch a node appear, ~40-70s
kubectl get pods -n demo -o wide
kubectl get nodes -L kubernetes.io/arch,karpenter.sh/capacity-type,node.kubernetes.io/instance-type
```

> `nodeclaims` and `nodes` are cluster-scoped — your developer access is namespace-scoped and does
> not grant them, so those two commands return `Forbidden`. That's expected, not a broken cluster:
> `kubectl get pods -n demo -o wide` already tells you your pod is running; ask the platform team if
> you need to see which node/architecture it landed on.

## 3. Run on x86 (amd64)

Same file, one line different (`kubernetes.io/arch: amd64`):

```bash
kubectl apply -f deployment-x86.yaml
kubectl get nodes -L kubernetes.io/arch      # now both architectures present (needs cluster-level access, see note above)
```

## 4. The recommended pattern: build multi-arch and skip the label

`deployment-multiarch.yaml` sets no architecture constraint. Build your image for both
platforms and Karpenter picks the cheapest one (Graviton, by default here):

```bash
docker buildx build --platform linux/amd64,linux/arm64 -t <repo>:<tag> --push .
```

Need Graviton preferred but with an x86 fallback if Graviton capacity is briefly
unavailable? See `deployment-multiarch-preferred.yaml` — a soft `nodeAffinity` instead of
a hard `nodeSelector`.

## 5. Prove it

```bash
kubectl apply -f job-arch-check.yaml
kubectl wait --for=condition=complete --timeout=5m job/arch-check -n demo
kubectl logs -n demo job/arch-check          # prints aarch64 on Graviton, x86_64 on Intel/AMD
```

## 6. Clean up

```bash
kubectl delete -f .
```

Karpenter removes the nodes it provisioned automatically a few minutes after the last
pod using them is gone — no separate node cleanup step.

## The one caveat: `exec format error`

Graviton is weighted higher, so **any pod with no `kubernetes.io/arch` constraint lands
on Graviton by default** — including one running an x86-only image, which then
crash-loops with `exec format error`. Fix it one of two ways:

- Build multi-arch (§4 above) — the real fix, works everywhere.
- Pin it: `nodeSelector: { kubernetes.io/arch: amd64 }`.

## Other things worth knowing

- **Quota.** The namespace has a ResourceQuota. `exceeded quota` on `kubectl apply`
  means you hit it, not that the cluster is broken — run `kubectl describe quota -n demo`
  to see the headroom. `services.loadbalancers` is quota'd to `0`: a
  `Service type=LoadBalancer` will always be rejected. That's deliberate — it would
  provision a public load balancer into a public subnet. Ask the platform team.
- **Pod Security.** The namespace enforces the `restricted` profile. Every pod needs
  `runAsNonRoot`, a matching `runAsUser`, `seccompProfile: RuntimeDefault`, and
  `capabilities: { drop: ["ALL"] }` — copy the pattern from any file here.
- **My app needs to call AWS (S3, DynamoDB, Secrets Manager). How?**
  Not with an access key in a Secret. Ask the platform team for an **EKS Pod Identity
  association** — they create an IAM role trusted by `pods.eks.amazonaws.com` and
  associate it with your ServiceAccount, the same way this stack already does for the
  EBS CSI driver. Your pod picks the credentials up automatically through the AWS SDK:
  no annotation, no mounted secret, no code change. Nothing in this repo demonstrates it
  because no demo workload needs AWS access — it's a two-resource addition per
  application, not a redesign.
- **Application secrets.** There's no secrets-management story here (no External
  Secrets Operator, no Secrets Manager CSI driver). A plain Kubernetes `Secret` is
  readable by anyone else with pod-create rights in the same namespace — ask the
  platform team before reaching for one if that matters for your data.
