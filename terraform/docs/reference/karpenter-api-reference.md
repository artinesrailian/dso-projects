# Karpenter v1 API Reference (chart 1.14.0)

Everything here was extracted from the **shipped CRD OpenAPI schemas and CEL validation rules** in
`oci://public.ecr.aws/karpenter/karpenter:1.14.0`, pulled and read directly — not from blog posts and
not from memory. Where a rule is enforced by admission, it is called out, because those are the ones
that fail your `terraform apply` rather than your review.

---

## 1. What the chart installs

| CRD | Group / Version | Scope | Notes |
|---|---|---|---|
| `NodePool` | `karpenter.sh/v1` | **Cluster** | |
| `NodeClaim` | `karpenter.sh/v1` | **Cluster** | Created by Karpenter, not by you. |
| `EC2NodeClass` | `karpenter.k8s.aws/v1` | **Cluster** | |
| `NodeOverlay` | `karpenter.sh/v1alpha1` | **Cluster** | Alpha; gated off by default. |
| `CapacityBuffer` | `autoscaling.x-k8s.io/v1beta1` | **Namespaced** ⚠️ | New in 1.14.0; gated off by default. The only namespaced Karpenter CRD — generic manifest templating that assumes cluster scope will break on it. |

Each CRD serves **exactly one** version. There is no `v1beta1` served, and there are no conversion
webhooks in the chart. If a tool tells you these are `v1beta1` it is reading the chart's stale
`artifacthub.io/crds` annotation; the CRD YAML is authoritative.

---

## 2. EC2NodeClass

### Required fields

`spec.required = [amiSelectorTerms, securityGroupSelectorTerms, subnetSelectorTerms]`

Plus two conditional rules enforced by CEL at admission:

1. **Exactly one of `role` or `instanceProfile`.**
   `(has(self.role) && !has(self.instanceProfile)) || (!has(self.role) && has(self.instanceProfile))`
   → We use `role`. Karpenter then creates and manages the instance profile itself. This is why the
   Terraform karpenter submodule's `create_instance_profile` defaults to `false` and why its
   `instance_profile_name` output is empty — **do not** try to use it.
2. **`amiFamily` is required *unless* an `alias` is used.**
   `self.amiSelectorTerms.exists(x, has(x.alias)) ? true : has(self.amiFamily)`
   → We use an alias, so `amiFamily` is omitted and inferred.

### The alias rule that catches everyone

`amiSelectorTerms` is a list whose terms are OR-ed — **except** that if any term uses `alias`, it
must be the *only* term in the list:

```
rule: !(self.exists(x, has(x.alias)) && self.size() != 1)
message: 'alias' is mutually exclusive, cannot be set with a combination of other amiSelectorTerms
```

Alias format is `family@version`, `maxLength: 30`. Valid families: `al2`, `al2023`, `bottlerocket`,
`windows2019`, `windows2022`, `windows2025`. Version is `latest` or a pinned AMI release tag —
date-form for AL2/AL2023 (`al2023@v20260701`), semver for Bottlerocket (`bottlerocket@v1.20.4`).
Windows supports only `latest`.

**Pinning.** `@latest` means a new AMI release silently marks every node `Drifted` and Karpenter
rolls the fleet. Karpenter's own schema documentation says this is "**not** recommended for
production environments". The deliverable exposes this as a variable and defaults to `al2023@latest`
so the repo works on any day it is cloned; the README documents pinning as the production step.
To find a valid pinned value:

```bash
# what the alias would resolve to today
aws ssm get-parameter --region "$REGION" \
  --name "/aws/service/eks/optimized-ami/1.36/amazon-linux-2023/arm64/standard/recommended/image_id" \
  --query 'Parameter.Value' --output text

# the release tags the alias accepts (e.g. v20260701)
# https://github.com/awslabs/amazon-eks-ami/releases
```

### Other fields worth knowing

| Field | Notes |
|---|---|
| `subnetSelectorTerms` | Item fields: `id`, `tags`. **No `name` field** — unlike security groups. |
| `securityGroupSelectorTerms` | Item fields: `id`, `name`, `tags`. |
| `metadataOptions` | Defaults are **already hardened**: `httpTokens: required`, `httpPutResponseHopLimit: 1`, `httpEndpoint: enabled`, `httpProtocolIPv6: disabled`. We set them explicitly anyway — an explicit security control survives a future default change and reads as intentional. |
| `blockDeviceMappings[].ebs.volumeSize` | A **string** with a unit (`"50Gi"`), not a number. CEL: exactly one mapping may set `rootVolume: true`; `snapshotID` or `volumeSize` must be defined. |
| `tags` | Applied to launched instances. Do **not** put `kubernetes.io/cluster/<name>` or `karpenter.sh/nodepool` here — Karpenter rejects tags it manages itself. |
| `detailedMonitoring` | Off by default; costs extra. |
| `kubelet` | `maxPods`, `systemReserved`, `kubeReserved`, eviction thresholds. Leave default unless you have a reason. |
| `instanceStorePolicy` | Set `RAID0` to use NVMe instance storage. Not used here. |

### The node class used by this deliverable

```yaml
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: default
spec:
  # Karpenter creates and manages the instance profile from this role.
  # Mutually exclusive with spec.instanceProfile.
  role: ${node_iam_role_name}

  # Must be the ONLY term when an alias is used.
  amiSelectorTerms:
    - alias: ${node_ami_alias}          # e.g. al2023@latest — pin for production

  subnetSelectorTerms:
    - tags:
        karpenter.sh/discovery: ${cluster_name}

  securityGroupSelectorTerms:
    - tags:
        karpenter.sh/discovery: ${cluster_name}

  # Explicit even though these match the schema defaults.
  # hop limit 1 means a container cannot reach IMDS through the node's
  # network namespace, so pods cannot steal the node role's credentials.
  # Safe here because workloads use EKS Pod Identity, not node credentials.
  metadataOptions:
    httpEndpoint: enabled
    httpProtocolIPv6: disabled
    httpPutResponseHopLimit: 1
    httpTokens: required

  blockDeviceMappings:
    - deviceName: /dev/xvda
      rootVolume: true
      ebs:
        volumeSize: 50Gi                # string with unit, not an integer
        volumeType: gp3
        encrypted: true                 # EBS encryption at rest
        deleteOnTermination: true

  # COST ALLOCATION — this block is not decoration.
  # Karpenter calls ec2:CreateFleet itself, so the AWS provider's default_tags
  # never reach these instances. They are the entire variable cost of the
  # cluster, and without these tags none of it is attributable in Cost Explorer.
  # Phase 5 renders local.tags in here. Karpenter rejects only the tags it
  # manages itself (kubernetes.io/cluster/*, karpenter.sh/nodepool).
  tags:
    Name: ${cluster_name}-karpenter-node
    ManagedBy: karpenter
    Project: ${project_name}
    Environment: ${environment}
```

---

## 3. NodePool

### Required fields

```
spec.required                 = [template]
spec.template.required        = [spec]
spec.template.spec.required   = [nodeClassRef, requirements]
nodeClassRef.required         = [group, kind, name]     # group and kind are IMMUTABLE
```

For AWS, `nodeClassRef` is always:

```yaml
nodeClassRef:
  group: karpenter.k8s.aws
  kind: EC2NodeClass
  name: default
```

### ⚠️ The `consolidateAfter` footgun

`disruption.consolidateAfter` appears in the `disruption` object's **`required`** list, while
`disruption` *itself* carries a default of `{consolidateAfter: "0s"}`.

The practical consequence: the default applies only when you omit the **entire** `disruption` block.
The moment you write a `disruption` block to set `consolidationPolicy`, you must also set
`consolidateAfter` — or the object is rejected at admission with a confusing required-field error.

```yaml
# ❌ REJECTED
disruption:
  consolidationPolicy: WhenEmptyOrUnderutilized

# ✅ ACCEPTED
disruption:
  consolidationPolicy: WhenEmptyOrUnderutilized
  consolidateAfter: 5m
```

### `requirements` operators and rules

Operators: `In`, `NotIn`, `Exists`, `DoesNotExist`, `Gt`, `Lt`, `Gte`, `Lte`.

CEL rules that bite:

- `In` must have a `values` list.
- `Gt` / `Lt` / `Gte` / `Lte` must have **exactly one positive integer** value — as a string:
  `values: ["5"]`.
- `minValues` (1–50) requires at least that many entries in `values`.
- **Restricted keys** you may not use: the `karpenter.sh` and `karpenter.k8s.aws` label domains
  generally, `karpenter.sh/nodepool`, and `kubernetes.io/hostname`. The well-known labels below are
  explicitly exempted.

### Well-known label keys

Kubernetes-standard:

| Key | Values |
|---|---|
| `kubernetes.io/arch` | `amd64`, `arm64` |
| `kubernetes.io/os` | `linux`, `windows` |
| `node.kubernetes.io/instance-type` | e.g. `m7g.large` |
| `topology.kubernetes.io/zone` | e.g. `us-east-1a` |
| `karpenter.sh/capacity-type` | `on-demand`, `spot`, **`reserved`** |

`reserved` is new — it maps to ODCR/Capacity Blocks and is live out of the box because
`featureGates.reservedCapacity` is **beta and enabled by default** in the 1.14.0 chart. This
deliverable does not use reservations, so it is simply not listed in the pools' `values`.

AWS-specific (`karpenter.k8s.aws/*`), abbreviated to the useful ones:

`instance-category` · `instance-family` · `instance-generation` · `instance-size` · `instance-cpu` ·
`instance-cpu-manufacturer` · `instance-memory` · `instance-hypervisor` · `instance-local-nvme` ·
`instance-network-bandwidth` · `instance-gpu-name` · `instance-gpu-count` · `ec2nodeclass`

Also `topology.k8s.aws/zone-id` — zone **IDs** are stable across accounts where zone *names* are not.

### `limits`, `weight`, `expireAfter`

| Field | Notes |
|---|---|
| `spec.limits` | Map of resource → quantity, e.g. `cpu: "100"`, `memory: "400Gi"`. Also accepts `nodes`. **Per-NodePool, not cluster-wide** — N pools each with `cpu: 100` gives a 100N ceiling. This is the blast-radius cap; without it one bad `replicas: 10000` provisions until you hit an account quota. Set cpu *and* memory. |
| `spec.weight` | Integer 1–100. **NodePools with higher weight are evaluated first.** This is how an unconstrained pod gets a deterministic home. |
| `spec.template.spec.expireAfter` | Default `720h` (30 days). Forces node rotation so nodes stay patched. Accepts `Never`. |
| `spec.template.spec.terminationGracePeriod` | **No default.** When set, it takes precedence over the pod's own grace period and will evict through blocked PDBs and past the `karpenter.sh/do-not-disrupt` annotation. Powerful, and a foot-gun — left unset here. |
| `spec.replicas` | Alpha static-capacity mode, gated off (`featureGates.staticCapacity: false`). Not used. |

### `disruption.budgets`

Defaults to `[{nodes: "10%"}]`. Item requires `nodes` (a **string**: `"10%"` or `"3"`). Optional
`schedule` (5-field cron or `@daily` etc., **no timezone support**), `duration` (hours/minutes only,
e.g. `8h`, `90m` — seconds are not accepted), and `reasons` (`Underutilized`, `Empty`, `Drifted`).
`schedule` and `duration` must be set together. When several budgets are active the **most
restrictive** wins.

> ⚠️ **Budgets do not cover everything, and the enum is the proof.** `reasons` accepts only
> `Underutilized`, `Empty` and `Drifted` — so **node expiration (`expireAfter`) and Spot interruption
> are not rate-limited by any budget.** "If unset the budget applies to all methods" means all
> *budget-eligible* methods, not all disruption.
>
> That produces a trade-off you cannot configure your way out of:
>
> | | Respects PodDisruptionBudgets | Rate-limited by `disruption.budgets` |
> |---|---|---|
> | Consolidation / drift | yes | yes |
> | **Expiration** (`expireAfter`) | yes — waits indefinitely if a PDB blocks | **no** |
> | **Spot interruption** | best-effort, ~2 minutes | **no** |
>
> With `expireAfter: 720h` and no `terminationGracePeriod`, expiry is graceful but unbounded: a
> blocking PDB stalls it forever. Set `terminationGracePeriod` and it becomes bounded but evicts
> *through* PDBs. Neither setting is both. Graceful-and-unbounded is the right POC default — but say
> so, rather than implying budgets cover it.
>
> Practical consequence on a Spot-first cluster: availability under interruption comes from
> PodDisruptionBudgets and replica spread in the **workload**, not from anything Karpenter throttles.

### `consolidationPolicy`

Enum: `WhenEmpty`, `WhenEmptyOrUnderutilized`, `Balanced`. Default `WhenEmptyOrUnderutilized`.

> **Do not use `Balanced`.** The enum value exists in the CRD and in the controller source
> (`ConsolidationPolicyBalanced`, with a `BalancedK = 2` scoring constant), but the string appears
> **nowhere** in the 1.14.0 documentation. Its semantics are effectively undocumented. Not something
> to put in a reference architecture.

---

## 4. The two NodePools used by this deliverable

### `arm64` — Graviton, preferred

```yaml
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: arm64
spec:
  # Higher weight = evaluated first. This is what makes an unconstrained pod
  # land on Graviton by default, which is the price/performance ask.
  weight: 50

  template:
    metadata:
      labels:
        arch: arm64
    spec:
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: default

      requirements:
        - key: kubernetes.io/arch
          operator: In
          values: ["arm64"]
        - key: kubernetes.io/os
          operator: In
          values: ["linux"]
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["spot", "on-demand"]      # Spot first; Karpenter falls back automatically
        # Categories, not named instance types. A narrow type list is the
        # number-one cause of "Karpenter cannot find capacity".
        - key: karpenter.k8s.aws/instance-category
          operator: In
          values: ["c", "m", "r"]
        - key: karpenter.k8s.aws/instance-generation
          operator: Gt
          values: ["5"]                       # Graviton2 (6g) and newer
        - key: karpenter.k8s.aws/instance-cpu
          operator: In
          values: ["2", "4", "8", "16"]      # bounds size; also excludes .metal

      expireAfter: 720h                       # rotate nodes monthly so they stay patched

  # spec.limits is PER-NODEPOOL — there is no cluster-wide limit in the API.
  # Phase 5 divides the configured budget across the enabled pools so that
  # nodepool_cpu_limit means what its name says. Memory is limited too: a
  # cpu-only cap lets a memory-heavy workload provision far more instance
  # than intended.
  limits:
    cpu: "${cpu_limit_per_pool}"
    memory: "${memory_limit_per_pool}Gi"

  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    # REQUIRED whenever this block exists (see the footgun in section 3).
    # 5m, not 1m: an emptied node is deleted this long after it drains, taking
    # `kubectl logs --previous`, the kubelet journal and any crash artefacts
    # with it. Container logs are not shipped anywhere in this build, so this
    # window IS the post-mortem window. Still fast enough to demo.
    consolidateAfter: 5m
    budgets:
      # Throttles VOLUNTARY disruption only. The `reasons` enum in the CRD is
      # exactly [Underutilized, Empty, Drifted] — expiration and Spot
      # interruption are NOT in it and are NOT rate-limited by this. Do not
      # write "never churn more than 10%": that is false for the two cases
      # most likely to churn the fleet.
      - nodes: "10%"
```

### `amd64` — x86, opt-in

Identical except:

```yaml
metadata:
  name: amd64
spec:
  weight: 10                                  # lower than arm64
  template:
    metadata:
      labels:
        arch: amd64
    spec:
      requirements:
        - key: kubernetes.io/arch
          operator: In
          values: ["amd64"]
        # ...everything else the same
```

---

## 5. How scheduling actually resolves

This is the part the README has to explain to a developer, so get it right.

| Pod spec | Result |
|---|---|
| `nodeSelector: {kubernetes.io/arch: arm64}` | Only the `arm64` pool can satisfy it → Graviton node. |
| `nodeSelector: {kubernetes.io/arch: amd64}` | Only the `amd64` pool can satisfy it → x86 node. |
| **No arch constraint** | Both pools match. Karpenter evaluates higher `weight` first → **`arm64` (weight 50) wins** → Graviton node. |

`kubernetes.io/arch` is a label the kubelet sets on every node in every Kubernetes cluster. A
developer targeting it needs to know nothing about Karpenter, which is exactly the property you
want.

> ⚠️ **The consequence of `arm64` having the higher weight:** a pod with no arch constraint and an
> **x86-only container image** will be scheduled onto a Graviton node and crash-loop with
> `exec format error`. That is a deliberate trade — it makes Graviton the default and surfaces
> non-portable images loudly instead of quietly paying x86 prices forever. Teams that are not ready
> for it flip `nodepool_default_arch` to `amd64`, which swaps the weights.
>
> The right long-term fix is multi-arch images: `docker buildx build --platform linux/amd64,linux/arm64`.
> Then `kubernetes.io/arch` never needs to be set at all and the scheduler picks whatever is cheapest.

`nodeSelector` vs `nodeAffinity`: `nodeSelector` is a hard requirement and is what the demo uses for
clarity. `nodeAffinity` with `preferredDuringSchedulingIgnoredDuringExecution` expresses "prefer
arm64, tolerate amd64" and is shown in the multi-arch example.

---

## 6. Helm values reference (chart 1.14.0)

### Required vs optional — verified against the chart templates

| Value | Status | Consequence of omitting |
|---|---|---|
| `settings.clusterName` | **Hard required.** `deployment.yaml` wraps it in Helm's `required` function. | Install fails with "Chart cannot be installed without a valid settings.clusterName!" |
| `settings.interruptionQueue` | Optional, guarded by `{{- with }}`. | **Silently disables all interruption handling** — Spot 2-minute notices, rebalance recommendations and scheduled-change events are ignored. Nodes get killed without draining. Always set it. |
| `settings.clusterEndpoint` | Optional; auto-discovered on EKS. | — |

Nothing else is enforced.

### Chart defaults you should not override

| Value | Default | Why it matters |
|---|---|---|
| `replicas` | `2` | With the default `podAntiAffinity` (required, `topologyKey: kubernetes.io/hostname`) this needs **two distinct nodes**. That is why the bootstrap managed node group has `min_size = 2`. One node → one Karpenter pod stuck `Pending` forever. |
| `affinity.nodeAffinity` | requires `karpenter.sh/nodepool` `DoesNotExist` | Stops Karpenter from scheduling itself onto a node it manages. **Already the chart default** — no override needed. |
| `tolerations` | `CriticalAddonsOnly: Exists` | Lets it run on tainted system nodes. |
| `priorityClassName` | `system-cluster-critical` | Karpenter is evicted last. |
| `podDisruptionBudget` | `maxUnavailable: 1` | |

`controller.resources` is **empty by default**. The docs' own install command sets
`requests/limits = 1 CPU / 1Gi`; do the same — an unbounded controller is a noisy-neighbour risk on
a two-node bootstrap group.

### Feature gates (1.14.0 defaults)

| Gate | Default | Stage |
|---|---|---|
| `reservedCapacity` | **`true`** | beta |
| `nodeRepair` | `false` | alpha |
| `nodeOverlay` | `false` | alpha |
| `spotToSpotConsolidation` | `false` | alpha |
| `staticCapacity` | `false` | alpha |
| `capacityBuffer` | `false` | alpha |

Leave all at their defaults. `spotToSpotConsolidation` is tempting for cost but is alpha; note it in
the README as a future optimisation.

### Other `settings.*` defaults

`batchMaxDuration: 10s`, `batchIdleDuration: 1s` (how long Karpenter waits to batch pending pods
before provisioning — raising these improves bin-packing at the cost of latency),
`vmMemoryOverheadPercent: 0.075`, `amiRefreshInterval: 1m`, `subnetRefreshInterval: 1m`,
`isolatedVPC: false` (set `true` only for a VPC with no internet route at all),
`enableZonalShift: false`.

---

## 7. IAM notes

- **Karpenter 1.12.0 added a required controller permission: `ec2:DescribeInstanceStatus`.** If you
  hand-roll the policy instead of using the Terraform submodule, this is the one people miss.
  Upgrading past 1.12.0 also marks existing nodes `Drifted` because the CA-bundle hashing changed —
  expect a fleet roll on that upgrade.
- Upstream CloudFormation now splits the controller policy into six managed policies
  (node-lifecycle, IAM-integration, EKS-integration, interruption, resource-discovery, zonal-shift)
  rather than one monolith. The Terraform submodule composes the equivalent set for you; this is
  context for anyone comparing the two.
- Five EventBridge rules feed the interruption queue: spot interruption, rebalance recommendation,
  scheduled change, instance state change, and capacity-reservation interruption.

---

## 8. Footgun checklist

Verify each before declaring a phase done.

- [ ] `disruption` block sets **both** `consolidationPolicy` and `consolidateAfter`.
- [ ] `amiSelectorTerms` contains **only** the alias term.
- [ ] Exactly one of `role` / `instanceProfile` — we use `role`.
- [ ] `volumeSize` is a quoted string with a unit (`"50Gi"`), not a number.
- [ ] `nodeClassRef` has all three of `group`, `kind`, `name`.
- [ ] `Gt`/`Lt` requirements carry exactly one integer, as a string.
- [ ] `settings.interruptionQueue` is set, or Spot handling is silently off.
- [ ] The `karpenter-crd` chart is installed **and** upgraded alongside the controller chart.
- [ ] Bootstrap node group has ≥ 2 nodes for the 2 anti-affine Karpenter replicas.
- [ ] Subnets **and** the node security group carry `karpenter.sh/discovery = <cluster name>`.
- [ ] `limits` is set on every NodePool.
