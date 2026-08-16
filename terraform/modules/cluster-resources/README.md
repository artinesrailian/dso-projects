# modules/cluster-resources

Delivers the objects the cluster needs after the Karpenter controller is
running but that only exist as Kubernetes custom/native resources, not AWS
resources: the `default` `EC2NodeClass`, the `amd64`/`arm64` `NodePool`s
(Phase 5, the assignment's core requirement), the default `gp3`
`StorageClass`, and the governed-namespace guardrails —
`Namespace`/`ResourceQuota`/`LimitRange` plus the developer `ClusterRole`/
`RoleBinding`. All four object families are delivered by one `helm_release`
pointed at a local chart in `chart/` (ADR-7): `kubernetes_manifest` needs the
CRD to exist at plan time, which fails the first `plan` on an empty account,
and this stack deliberately carries no `kubernetes` provider (ADR-6, see
below). `helm uninstall` also removes the CRs cleanly on destroy, which
matters — orphaned `NodePool`s with finalizers are a classic
`terraform destroy` hang.

See `docs/phases/phase-05-nodepools.md` for the full specification and
`docs/reference/karpenter-api-reference.md` for the Karpenter v1 API this
chart implements.

## The default-arch trade-off

`nodepool_default_arch` (root variable, default `"arm64"`) decides which
NodePool carries the higher `weight` and therefore which pool a pod with
**no** `kubernetes.io/arch` constraint lands on. Defaulting to `arm64` is the
price/performance position the assignment asks for — Graviton wins by
default rather than every workload quietly paying x86 prices forever.

The cost of that default: a pod with no arch constraint and an **x86-only
container image** will be scheduled onto a Graviton node and crash-loop with
`exec format error` (`reference/gotchas.md` G-16). That is a deliberate
trade, not a bug — it makes the mismatch surface loudly and immediately
instead of silently costing money. Two ways out:

1. **Multi-arch images** (the real fix):
   ```bash
   docker buildx build --platform linux/amd64,linux/arm64 -t your-image:tag --push .
   ```
   Once every image in the cluster is multi-arch, `kubernetes.io/arch` never
   needs to be set on a pod at all and the scheduler picks whichever
   architecture is available and cheapest.
2. **The escape hatch**: set `nodepool_default_arch = "amd64"` at the root.
   This swaps the weights so an unconstrained pod lands on x86 instead —
   useful while images are still being made multi-arch, or for a team not
   ready to test on Graviton yet.

Pods that already carry `nodeSelector: {kubernetes.io/arch: amd64}` or
`arm64` are unaffected either way — only the *unconstrained* case depends on
weight.

## Why the StorageClass lives in a module named `cluster-resources`

`gp3` is not a Karpenter resource, and this module's own name says
"cluster-resources", not "karpenter". That's a real naming compromise, taken
deliberately. The alternative (`phase-02-eks-cluster.md` §2.5b) — a second
Terraform provider, or a second module, just to create one `StorageClass` —
was rejected because this stack has no `kubernetes` provider by design
(ADR-6: since EKS module v21 dropped `aws-auth` ConfigMap management, the
only reason to add one would be to create Kubernetes objects, and every
Kubernetes object here is already delivered through Helm). This chart is the
**only** Helm-delivered path for cluster-scoped objects in the stack, so the
`StorageClass` rides along in it rather than justifying a second provider or
module for a single object.

The one field that must never change: `volumeBindingMode:
WaitForFirstConsumer`. With `Immediate` (the Kubernetes default), a PVC's
volume is provisioned in some AZ *before* a pod is scheduled — and Karpenter
is free to launch the node in any AZ it likes. The pod then can never
schedule, and the error message blames node affinity, not the StorageClass.

## The governed-namespace guardrails

`Namespace`/`ResourceQuota`/`LimitRange` (§5.3c) and the developer
`ClusterRole`/`RoleBinding` (§5.3d) are created here, by Terraform, rather
than left as a `kubectl apply` a human is supposed to remember — because
Phase 2 already grants `developer_namespaces` access via EKS access entries,
and access without a governed namespace to land in is the failure mode this
avoids. `helm_release.cluster_resources` carries a `lifecycle.precondition`
enforcing that every non-wildcard entry in `developer_namespaces` also
appears in `governed_namespaces`.

Full rationale for what the developer `ClusterRole` grants, what it
deliberately withholds, and — more importantly — what RBAC structurally
cannot reach even so (a determined developer can still read namespace
Secrets via a pod spec; a Pod Identity association is namespace-wide) lives
in `docs/phases/phase-05-nodepools.md` §5.3d. That is the canonical version;
it is not duplicated here.

## Helm values

Terraform always overrides `chart/values.yaml` via
`helm_release.cluster_resources`'s `yamlencode`'d `values`. The file's own
defaults exist only so the chart is independently testable with
`helm lint`/`helm template` and no `--set` flags — see phase-05's
"Acceptance criteria".

| Value | Chart default | Terraform-set value |
|---|---|---|
| `clusterName` | `""` | `module.eks.cluster_name` |
| `nodeIamRoleName` | `""` | `module.karpenter.node_iam_role_name` |
| `amiAlias` | `al2023@latest` | `var.node_ami_alias` |
| `capacityTypes` | `[spot, on-demand]` | `var.nodepool_capacity_types` |
| `cpuLimitPerPool` / `memoryLimitPerPool` | `50` / `200` | `floor(var.nodepool_cpu_limit / N)` / `floor(var.nodepool_memory_limit_gi / N)`, `N` = enabled pool count |
| `amd64.enabled` / `arm64.enabled` | `true` / `true` | `var.enable_amd64_nodepool` / `var.enable_arm64_nodepool` |
| `amd64.weight` / `arm64.weight` | `10` / `50` | derived from `var.nodepool_default_arch` |
| `governedNamespaces` | `[demo]` | `var.governed_namespaces` |
| `namespaceQuota.*` | matches root's default `namespace_quota` | `var.namespace_quota` (snake_case → camelCase) |
| `developerRbacGroup` | `opsfleet:developers` | `var.developer_rbac_group` |
| `tags` | `{}` | `local.tags` |

## What is out of scope for this module

- The `demo` namespace's *content* — actual workloads. Phase 6 ships those as
  plain `kubectl apply`-able YAML in `examples/`, deliberately outside
  Terraform, to demonstrate what a developer (not an operator) does.
  `governedNamespaces` defaulting to `["demo"]` is only the namespace shell
  (labels/quota/limits) — never a workload.
- IMDSv2 hardening, EBS encryption and node role/instance-profile mechanics
  are Karpenter/EC2NodeClass concerns documented inline in
  `chart/templates/ec2nodeclass.yaml` and in
  `reference/karpenter-api-reference.md` §2, not repeated here.
