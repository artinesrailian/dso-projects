# Phase 5 — NodePools and EC2NodeClass (x86 + Graviton, Spot + On-Demand)

**Depends on:** Phase 4.
**Produces:** `modules/cluster-resources/`, wired into `main.tf`.

---

## Goal

This phase **is** the assignment's core requirement: *"node pool(s) that can deploy both x86 and
arm64 instances"*, leveraging *"Graviton and Spot instances for better price/performance"*.

At the end of it, `kubectl get nodepools` shows `amd64` and `arm64`, `kubectl get ec2nodeclass`
shows `default`, and a pod with `nodeSelector: {kubernetes.io/arch: arm64}` causes a Graviton
instance to appear within about a minute.

---

## Inputs

| Source | What you need |
|---|---|
| `reference/karpenter-api-reference.md` | **All of it.** §2 EC2NodeClass, §3 NodePool, §4 the exact YAML this phase implements, §5 scheduling semantics, §8 the footgun checklist |
| `contracts/interface-contract.md` | §5.4 module signature, §6 fixed Kubernetes object names |
| `reference/gotchas.md` | G-13, G-15, G-17, G-19 |
| `00-architecture-and-decisions.md` | ADR-7 (why a local Helm chart), ADR-9 (why two pools), ADR-10 (AMI alias) |
| Phase 4 completion report | `module.karpenter.helm_release_name` for the `depends_on` |

---

## Files to create

```
modules/cluster-resources/versions.tf
modules/cluster-resources/variables.tf
modules/cluster-resources/main.tf
modules/cluster-resources/outputs.tf
modules/cluster-resources/README.md
modules/cluster-resources/chart/Chart.yaml
modules/cluster-resources/chart/values.yaml
modules/cluster-resources/chart/templates/ec2nodeclass.yaml
modules/cluster-resources/chart/templates/nodepools.yaml
modules/cluster-resources/chart/templates/storageclass.yaml
modules/cluster-resources/chart/templates/namespaces.yaml
```

---

## Specification

### 5.1 Delivery mechanism — a local Helm chart

Per ADR-7. Restated because it determines the whole file layout:

| Approach | Why not |
|---|---|
| `kubernetes_manifest` | Requires the CRD to exist **at plan time**. The first `plan` against an empty account fails. Non-starter. |
| `kubectl_manifest` (third-party) | Works, but adds an unofficial provider to a security-sensitive stack. |
| **`helm_release` on a local chart** | **Chosen.** No extra provider, `depends_on` gives correct ordering, and `helm uninstall` removes the CRs cleanly on destroy — which matters, because orphaned NodePools with finalizers are a classic destroy hang. |

```hcl
resource "helm_release" "cluster_resources" {
  name      = "cluster-resources"
  chart     = "${path.module}/chart"
  namespace = var.namespace

  # Ordering is not optional: the CRDs must be established before these CRs
  # are applied, or the release fails with `no matches for kind "NodePool"`.
  depends_on = [var.karpenter_helm_release_name]

  values = [yamlencode({
    clusterName     = var.cluster_name
    nodeIamRoleName = var.node_iam_role_name
    amiAlias        = var.node_ami_alias
    capacityTypes   = var.capacity_types

    # Karpenter's spec.limits is PER-NODEPOOL. Divide the configured budget
    # across the enabled pools so that `nodepool_cpu_limit` is the real
    # cluster ceiling rather than half of it.
    cpuLimitPerPool    = floor(var.cpu_limit / local.enabled_pool_count)
    memoryLimitPerPool = floor(var.memory_limit_gi / local.enabled_pool_count)

    # Cost allocation. default_tags never reaches Karpenter-launched instances
    # (it calls ec2:CreateFleet itself), so these are the ONLY way the compute
    # spend is attributable in Cost Explorer.
    tags = var.tags
    amd64 = {
      enabled = var.enable_amd64
      weight  = local.amd64_weight
    }
    arm64 = {
      enabled = var.enable_arm64
      weight  = local.arm64_weight
    }
  })]
}
```

Prefer `values = [yamlencode({...})]` over a long `set` list — these structures are nested, and
`set` flattens badly.

### 5.2 The EC2NodeClass template

Implement `reference/karpenter-api-reference.md` §2 verbatim. Object name is `default`
(interface-contract §6). Re-read §8's checklist before you finish — every item in it is a rule this
template can violate silently.

The three that most often go wrong:

1. **`amiSelectorTerms` must contain only the alias term.** CEL rejects an alias combined with
   anything else.
2. **`role`, not `instanceProfile`.** Exactly one is allowed. Karpenter v1 builds the instance
   profile itself from the role.
3. **`volumeSize` is a quoted string with a unit** — `"50Gi"`, not `50`.

Also worth a comment in the template: Karpenter's per-family default `blockDeviceMappings` already
set `encrypted: true`, but **those defaults apply only if you omit the block entirely**. The moment
you override it to change `volumeSize`, you must re-state `encrypted: true` yourself.

### 5.3 The NodePool templates

Implement `reference/karpenter-api-reference.md` §4. Both pools share the `default` EC2NodeClass and
differ only in name, `kubernetes.io/arch`, label and weight.

**Weights come from `var.default_arch`:**

```hcl
locals {
  # Karpenter evaluates higher-weight NodePools first, so this decides where a
  # pod with NO architecture constraint lands. Defaulting to arm64 is the
  # price/performance position the assignment asks for; see §5.5 for the risk.
  arm64_weight = var.default_arch == "arm64" ? 50 : 10
  amd64_weight = var.default_arch == "amd64" ? 50 : 10

  # spec.limits is per-NodePool, so N enabled pools multiply the ceiling by N.
  # max(...,1) guards against a division by zero if both pools are disabled.
  enabled_pool_count = max(
    (var.enable_amd64 ? 1 : 0) + (var.enable_arm64 ? 1 : 0),
    1,
  )
}
```

**Every NodePool gets both a cpu and a memory limit.** A cpu-only cap lets a memory-heavy workload
pull in far more instance than intended — `r`-family nodes are 8 GiB per vCPU, so 100 vCPU of `r7g`
is 800 GiB of RAM you did not budget for.

**Requirements: use categories and generations, never a hardcoded instance-type list.** A narrow
type list is the single most common reason Karpenter reports it cannot find capacity — especially on
Spot, where the whole point is having many pools to choose from.

```yaml
- key: karpenter.k8s.aws/instance-category
  operator: In
  values: ["c", "m", "r"]
- key: karpenter.k8s.aws/instance-generation
  operator: Gt
  values: ["5"]                    # exactly one integer, as a string — CEL enforces this
- key: karpenter.k8s.aws/instance-cpu
  operator: In
  values: ["2", "4", "8", "16"]    # bounds node size; also excludes .metal
```

For the arm64 pool this resolves to Graviton2 and newer (`m6g`/`c6g`/`r6g` through `m8g`/`c8g`/`r8g`
where available). Breadth matters more than picking the newest generation, because Spot capacity is
what you are actually optimising for.

**Capacity types** come from `var.capacity_types`, default `["spot", "on-demand"]`. Karpenter's
price-capacity-optimized allocation picks Spot where it can and falls back to On-Demand
automatically — no extra configuration, no priority expander. A third value, `reserved`, exists in
1.14.0 (the `reservedCapacity` feature gate is beta and on by default) but this build does not use
capacity reservations, so it is simply not listed.

**`disruption` must set both `consolidationPolicy` and `consolidateAfter`** — G-17. And every pool
must carry `limits`.

### 5.3b The default StorageClass

Phase 2 specifies a default `gp3` StorageClass and hands delivery to this chart, because this is the
only Helm-delivered path for cluster-scoped objects in the stack (there is no `kubernetes` provider —
ADR-6). Copy it verbatim from phase-02 §2.5b.

The module is named `cluster-resources` and this is not a Karpenter resource. That is a small
naming compromise, taken deliberately rather than adding a second provider or a second module for a
single object. Say so in a comment at the top of the template.

The one field not to change: `volumeBindingMode: WaitForFirstConsumer`. With Karpenter, `Immediate`
binding provisions the volume before the node exists, in an AZ Karpenter may not choose, and the pod
then never schedules.

### 5.3c Governed namespaces — the guardrails must be Terraform-created

**This is the fix for an ordering bug, so understand why before you write it.**

Phase 2 creates the developer access entries in Terraform: after `terraform apply`, every principal
in `developer_principal_arns` is bound to the `developer_rbac_group` group, scoped to the namespaces
in `developer_namespaces`. If the namespace, its Pod Security labels and its ResourceQuota are a
`kubectl apply` a human is supposed to remember, then **Terraform hands out access to a namespace
whose guardrails may not exist** — and nothing reconciles them afterwards. An operator doing
`kubectl create namespace demo` by hand produces an unlabelled, unquota'd namespace that developers
already have edit rights on.

So the namespace and everything governing it are created *here*, by Terraform, through the same
chart as the StorageClass:

```yaml
{{- range .Values.governedNamespaces }}
---
apiVersion: v1
kind: Namespace
metadata:
  name: {{ . }}
  labels:
    # In-tree Pod Security Admission. Terraform-managed, so `helm upgrade` on the
    # next apply restores these if anyone strips them.
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/enforce-version: v1.36
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
---
apiVersion: v1
kind: ResourceQuota
metadata: { name: {{ . }}-quota, namespace: {{ . }} }
spec:
  hard:
    # --- compute -----------------------------------------------------------
    requests.cpu: {{ $.Values.namespaceQuota.requestsCpu | quote }}
    requests.memory: {{ $.Values.namespaceQuota.requestsMemory | quote }}
    limits.cpu: {{ $.Values.namespaceQuota.limitsCpu | quote }}
    limits.memory: {{ $.Values.namespaceQuota.limitsMemory | quote }}

    # --- storage: the expensive omission ----------------------------------
    # The EBS CSI driver is installed and §2.5b ships a DEFAULT StorageClass, so
    # a bare PVC provisions real EBS. gp3 tops out at 16 TiB (~$1,310/mo each)
    # and a pod can mount ~25. Twenty volumes is ~$26,000/month while consuming
    # 100m of the CPU quota. Worse, StatefulSet volumeClaimTemplates are RETAINED
    # on delete and teardown.sh does not sweep EBS — the spend outlives the
    # cluster. A quota with no storage dimension is not a cost control.
    persistentvolumeclaims: "10"
    requests.storage: 200Gi
    gp3.storageclass.storage.k8s.io/requests.storage: 200Gi

    # --- ephemeral storage -------------------------------------------------
    # An emptyDir with no sizeLimit fills the 50 GiB node root volume, triggers
    # DiskPressure, and the kubelet evicts OTHER developers' pods off that node.
    requests.ephemeral-storage: 20Gi
    limits.ephemeral-storage: 40Gi

    # --- object counts -----------------------------------------------------
    # count/deployments alone is trivially sidestepped: the Role also grants
    # statefulsets, bare replicasets, jobs and cronjobs. A CronJob with
    # `schedule: "* * * * *"` and concurrencyPolicy Allow is the classic
    # accident. count/pods also bounds VPC IP consumption (ADR-1 sizes subnets
    # for exactly this).
    count/pods: "100"
    count/deployments.apps: {{ $.Values.namespaceQuota.maxDeployments | quote }}
    count/statefulsets.apps: "10"
    count/replicasets.apps: "50"
    count/jobs.batch: "20"
    count/cronjobs.batch: "10"
    count/services: "20"

    # --- exposure ----------------------------------------------------------
    services.loadbalancers: "0"
    services.nodeports: "0"
---
apiVersion: v1
kind: LimitRange
metadata: { name: {{ . }}-limits, namespace: {{ . }} }
spec:
  limits:
    - type: Container
      # Karpenter sizes nodes from resource REQUESTS. A pod with none looks
      # free, so Karpenter bin-packs it and it then fights real workloads for
      # CPU and memory on a shared node. defaultRequest fixes the UNSET case.
      defaultRequest: { cpu: 100m, memory: 128Mi, ephemeral-storage: 1Gi }
      default:        { cpu: "1",  memory: 1Gi,   ephemeral-storage: 2Gi }
      max:            { cpu: "4",  memory: 8Gi,   ephemeral-storage: 4Gi }
      # `min` is what stops node-count amplification. defaultRequest applies
      # ONLY when the field is unset — an explicit `cpu: 1m` is admitted without
      # it. Combine that with a required podAntiAffinity on hostname (which
      # phase-06's own example teaches, and which every "spread isn't working"
      # answer online escalates to DoNotSchedule) and 50 replicas cost 50m of a
      # 20-CPU quota while forcing 50 NODES — which consolidation can never
      # reclaim, because the pods are structurally forbidden from sharing one.
      # The NodePool limit caps vCPU, not node count.
      min:            { cpu: 50m, memory: 64Mi }
    - type: Pod
      # The largest admissible pod must fit the largest launchable node
      # (instance-cpu tops out at 16), or it is unschedulable forever.
      max: { cpu: "8", memory: 16Gi }
    - type: PersistentVolumeClaim
      max: { storage: 50Gi }
      min: { storage: 1Gi }
{{- end }}
```

**Add a precondition tying the two lists together**, because the whole point is that access and
governance cannot drift apart:

```hcl
lifecycle {
  precondition {
    # Every concrete namespace developers are granted access to must also be
    # governed. Wildcards (team-*) cannot be created, so they are excluded from
    # the check and must be governed by adding their real names here.
    condition = length(setsubtract(
      [for ns in var.developer_namespaces : ns if !strcontains(ns, "*")],
      var.governed_namespaces,
    )) == 0
    error_message = "Every non-wildcard entry in developer_namespaces must appear in governed_namespaces, or developers get edit rights on an ungoverned namespace."
  }
}
```

### 5.3d The developer ClusterRole — what "zero trust" actually means here

Phase 2 binds developers to the group `var.developer_rbac_group` and associates **no** AWS access
policy. This chart supplies the permissions. Grant only what deploying and operating an application
requires; everything omitted is omitted on purpose, and the omissions are the point.

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: {{ .Values.developerRbacGroup | replace ":" "-" }}
rules:
  # --- The job: ship and run a workload -------------------------------------
  - apiGroups: ["apps"]
    # deployments/rollback is deliberately absent — the subresource was removed
    # from Kubernetes in 1.16 and granting it is dead weight.
    resources: [deployments, replicasets, statefulsets,
                deployments/scale, statefulsets/scale, replicasets/scale]
    verbs: [get, list, watch, create, update, patch, delete]
  - apiGroups: ["batch"]
    resources: [jobs, cronjobs]
    verbs: [get, list, watch, create, update, patch, delete]
  - apiGroups: [""]
    resources: [pods, services, configmaps]
    verbs: [get, list, watch, create, update, patch, delete]

  # --- Observe your own workload --------------------------------------------
  - apiGroups: [""]
    resources: [pods/log, pods/status, events]
    verbs: [get, list, watch]
  - apiGroups: ["metrics.k8s.io"]
    resources: [pods]             # NOT nodes — cluster-scoped, see below
    verbs: [get, list]            # kubectl top pods

  # --- Follow the guidance we give them -------------------------------------
  # The README tells developers to set a PodDisruptionBudget on a Spot cluster
  # and phase-10 demos an HPA. Both must therefore be grantable.
  - apiGroups: ["policy"]
    resources: [poddisruptionbudgets]
    verbs: [get, list, watch, create, update, patch, delete]
  - apiGroups: ["autoscaling"]
    resources: [horizontalpodautoscalers]
    verbs: [get, list, watch, create, update, patch, delete]

  # --- Diagnose your own limits without opening a ticket ---------------------
  - apiGroups: [""]
    resources: [resourcequotas, limitranges]
    verbs: [get, list, watch]

  # --- Storage --------------------------------------------------------------
  - apiGroups: [""]
    resources: [persistentvolumeclaims]
    verbs: [get, list, watch, create, update, patch, delete]
  # NOTE: storageclasses and metrics.k8s.io/nodes are CLUSTER-SCOPED. A
  # ClusterRole bound by a RoleBinding cannot grant them — RBAC silently ignores
  # such rules, so `kubectl get storageclass` is denied however it is written
  # here. They are omitted rather than listed-and-dead. If developers need to
  # read StorageClasses, that requires a separate, narrowly-scoped
  # ClusterRoleBinding — a deliberate decision, not a line in this Role.
  # The default StorageClass means they never have to name one.

  # --- Debugging: a deliberate, bounded exception ---------------------------
  # exec is genuinely needed to debug a container and is scoped to this
  # namespace. Accept it knowingly: it lets a developer read any secret MOUNTED
  # into any pod here, which is why per-team namespaces matter as soon as this
  # carries more than one team's work.
  - apiGroups: [""]
    resources: [pods/exec, pods/portforward]
    verbs: [create, get]
```

**Bound to the group, per governed namespace** — a RoleBinding, so it cannot leak cluster-wide:

```yaml
{{- range .Values.governedNamespaces }}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata: { name: developers, namespace: {{ . }} }
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole                       # cluster-scoped definition...
  name: {{ $.Values.developerRbacGroup | replace ":" "-" }}
subjects:
  - kind: Group                           # ...namespace-scoped binding
    name: {{ $.Values.developerRbacGroup }}
    apiGroup: rbac.authorization.k8s.io
{{- end }}
```

#### What is deliberately NOT granted, and why

| Not granted | Reason |
|---|---|
| `secrets` (any verb) | Stops casual and accidental exposure: no `kubectl get secret`, no `-o yaml`, nothing in a shell history. **It does not stop a deliberate user** — see the boundary note below. AWS access comes from a Pod Identity association an operator creates; app secrets come from the platform team. |
| `serviceaccounts` create / **impersonate** | `impersonate` is a direct escalation to any workload identity in the namespace. Pods use `default` or an operator-created SA. |
| `daemonsets` | One pod per node, growing with the cluster; contrary to the intent of a per-namespace quota. |
| `ingresses`, `services/proxy` | Exposure is an operator decision, consistent with `services.loadbalancers: 0` in the quota. |
| `networkpolicies` | A developer must not be able to edit isolation. |
| `roles`, `rolebindings` | Self-escalation. `AmazonEKSAdminPolicy` *does* grant these — though it withholds `escalate` and `bind`, so the API server's escalation-prevention check confines its holder to granting only what they already hold. Still more than a developer needs. |
| Anything cluster-scoped — `nodes`, `namespaces`, `nodepools`, `ec2nodeclasses`, CRDs, webhooks | A RoleBinding cannot grant them, by construction. |

#### What RBAC cannot reach — read this before trusting the table above

Two things this Role **does not** prevent, both flowing from one grant: `pods: create` with an
arbitrary pod spec.

**1. A determined developer can read every Secret in the namespace.** Not via `kubectl get secret` —
that is denied and the assertion below genuinely passes. Via the pod spec:

```bash
# Deployments are readable (granted), so secret NAMES are discoverable from
# secretKeyRef / secretRef / volumes[].secret.secretName. `list` on secrets is
# not needed.
kubectl create -f - <<'EOF'   # then: kubectl logs exfil
apiVersion: v1
kind: Pod
metadata: { name: exfil, namespace: demo }
spec:
  containers:
    - name: c
      image: public.ecr.aws/docker/library/busybox:latest
      envFrom: [{ secretRef: { name: db-creds } }]
      command: ["sh","-c","env"]
EOF
```

Two minutes, no `exec`, no secrets verb. **There is no RBAC rule that fixes this**, because the
authorization decision is on the *pod*, and the pod is legitimately theirs to create.

**2. A Pod Identity association is namespace-wide, and keyed by ServiceAccount *name*.** The
association is `(cluster, namespace, serviceAccountName)`. `spec.serviceAccountName` is an ordinary
pod-spec field — there is **no authorization check** on a pod's reference to a ServiceAccount.
Withholding `serviceaccounts: create` and `impersonate` does not close it. So the moment an operator
creates the first Pod Identity association in a namespace, **every principal with pod-create rights
in that namespace holds that IAM role.**

**The boundary is the namespace, not the Role.** Consequences that are now non-negotiable:

- A shared `demo` namespace is fine for a POC demo where nothing sensitive exists.
- **One namespace per team** is required the moment two teams' work coexists — add each to *both*
  `developer_namespaces` and `governed_namespaces` (the precondition enforces the pairing) and each
  gets its own quota, LimitRange and PSA labels automatically.
- **A dedicated namespace is a precondition for the first Pod Identity association**, not an
  afterthought. Phase-06 §6.8 and operator-runbook §4 must say so.
- If you must share a namespace and still constrain this, the in-tree tool is a
  `ValidatingAdmissionPolicy` (GA since 1.30, no controller, no cost) restricting which Secrets a pod
  may reference — the same reasoning that made PSA preferable to Kyverno.

One property worth stating in the Role's favour: this design **fails closed**. If the chart has not
applied, the access entry names a group with no RBAC and developers get nothing. The
`AmazonEKSEditPolicy` design failed **open** — the association granted access whether or not the
guardrails existed.

**Verify the boundary rather than trusting it** — `kubectl auth can-i` evaluates real RBAC (unlike
with AWS access policies, where it reports nothing):

```bash
kubectl auth can-i --as-group=opsfleet:developers --as=dev create deployments -n demo   # yes
kubectl auth can-i --as-group=opsfleet:developers --as=dev get secrets        -n demo   # no
kubectl auth can-i --as-group=opsfleet:developers --as=dev create daemonsets  -n demo   # no
kubectl auth can-i --as-group=opsfleet:developers --as=dev create rolebindings -n demo  # no
kubectl auth can-i --as-group=opsfleet:developers --as=dev list pods          -n kube-system  # no
kubectl auth can-i --as-group=opsfleet:developers --as=dev list nodes                    # no
```

Phase 8's `verify.sh` must assert all six. A permission boundary with no test is a claim.

### 5.4 What NOT to put in the pools

- **`Balanced`** as a `consolidationPolicy`. The enum value exists but is undocumented in 1.14.0.
- **`terminationGracePeriod`.** It overrides pod grace periods and evicts through blocked PDBs and
  the `karpenter.sh/do-not-disrupt` annotation. Powerful; not a POC default.
- **`spec.replicas`.** Alpha static-capacity mode, gated off.
- **Taints.** Tempting for arch separation, but it would force every developer to add tolerations —
  the opposite of the simple `nodeSelector` story this deliverable is selling.

### 5.5 Document the default-arch trade-off in the module README

With `arm64` weighted higher, a pod with **no** arch constraint and an **x86-only image** will land
on Graviton and `CrashLoopBackOff` with `exec format error` (G-16).

That is a deliberate trade: it makes Graviton the default and surfaces non-portable images loudly,
rather than quietly paying x86 prices forever. Write it down — with the multi-arch build command and
the `default_arch = "amd64"` escape hatch — so it reads as a decision rather than a bug.

---

## Security requirements owned by this phase

- **S-50** Node root volumes encrypted (`encrypted: true` explicitly re-stated in
  `blockDeviceMappings`).
- **S-51** IMDSv2 required, `httpPutResponseHopLimit: 1`, so containers cannot reach IMDS and steal
  node credentials. Safe because workloads use Pod Identity. *(Caveat to note in the README:
  `hostNetwork: true` pods reach IMDS regardless of hop limit — this is a strong control, not an
  absolute boundary.)*
- **S-52** Every NodePool has `limits`, capping blast radius.
- **S-53** `disruption.budgets` present, so consolidation cannot churn the whole fleet at once.
- **S-54** `expireAfter` set, so nodes are rotated and patched rather than running for years.
- **S-55** Subnet and security-group selection is tag-based and cluster-scoped — no wildcard that
  could select another cluster's resources.

---

## Acceptance criteria

Without credentials:

```bash
terraform fmt -check -recursive
terraform validate

cd modules/cluster-resources
helm lint ./chart --set clusterName=test --set nodeIamRoleName=test-role

# Render and eyeball the output — this catches most of the §8 footguns.
helm template ./chart --set clusterName=test --set nodeIamRoleName=test-role \
  --set amiAlias=al2023@latest --set cpuLimit=100

# Static assertions on the rendered output:
R=$(helm template ./chart --set clusterName=test --set nodeIamRoleName=test-role \
     --set amiAlias=al2023@latest --set cpuLimit=100)
echo "$R" | grep -q 'karpenter.sh/v1'      && echo "PASS: NodePool API version"
echo "$R" | grep -q 'karpenter.k8s.aws/v1' && echo "PASS: EC2NodeClass API version"
echo "$R" | grep -q 'consolidateAfter'     && echo "PASS: G-17 avoided"
echo "$R" | grep -q 'httpTokens: required' && echo "PASS: IMDSv2"
echo "$R" | grep -q 'encrypted: true'      && echo "PASS: EBS encryption"
echo "$R" | grep -q 'limits'               && echo "PASS: blast radius capped"
echo "$R" | grep -qE 'volumeSize: *"?[0-9]+Gi' && echo "PASS: volumeSize has a unit"

# Must find NOTHING. Strip YAML comments first — the chart templates are
# required to carry comments that mention `instanceProfile` (explaining why we
# use `role` instead), which an unanchored grep would match.
echo "$R" | grep -vE '^[[:space:]]*#' | grep -i 'Balanced'
echo "$R" | grep -vE '^[[:space:]]*#' | grep 'instanceProfile'
```

With credentials — this is the phase that proves the assignment:

```bash
terraform apply

kubectl get ec2nodeclass          # default
kubectl get nodepools -o wide     # amd64, arm64
kubectl describe nodepool arm64 | tail -20   # Status must NOT report subnet/SG discovery errors

# --- The actual proof -----------------------------------------------------
#
# The `demo` namespace already exists — THIS module created it (§5.3c) with its
# PSA labels, ResourceQuota and LimitRange. Confirm, do not create:
kubectl get ns demo -o jsonpath='{.metadata.labels}' | grep -q restricted \
  && echo "PASS: governed namespace exists" || echo "FAIL: namespace missing or unlabelled"
kubectl describe quota -n demo

# Do NOT run `kubectl create namespace demo`. That produces an UNLABELLED,
# unquota'd namespace and silently disables the control S-64 calls
# API-server-enforced. If a pod below is rejected, fix the POD, not the namespace.

# The `restricted` profile rejects any pod without this securityContext, and
# busybox runs as root by default — hence runAsUser. A bare `kubectl run` with
# only a nodeSelector WILL be rejected with
#   violates PodSecurity "restricted:v1.36"
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata: { name: graviton-test, namespace: demo }
spec:
  restartPolicy: Never
  nodeSelector: { kubernetes.io/arch: arm64 }
  securityContext:
    runAsNonRoot: true
    runAsUser: 65534
    seccompProfile: { type: RuntimeDefault }
  containers:
    - name: t
      image: public.ecr.aws/docker/library/busybox:latest
      command: ["sleep", "3600"]
      resources:
        requests: { cpu: 500m, memory: 128Mi }
      securityContext:
        allowPrivilegeEscalation: false
        capabilities: { drop: ["ALL"] }
EOF

# Watch a Graviton node appear (typically 40-70s)
kubectl get nodeclaims -w      # ctrl-c once Ready

kubectl get nodes -L kubernetes.io/arch,karpenter.sh/capacity-type,node.kubernetes.io/instance-type
# Expect a new node: arm64, spot (usually), an m7g/c7g/r7g-class type

# Same again for x86 — only the nodeSelector and the name change.
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata: { name: x86-test, namespace: demo }
spec:
  restartPolicy: Never
  nodeSelector: { kubernetes.io/arch: amd64 }
  securityContext:
    runAsNonRoot: true
    runAsUser: 65534
    seccompProfile: { type: RuntimeDefault }
  containers:
    - name: t
      image: public.ecr.aws/docker/library/busybox:latest
      command: ["sleep", "3600"]
      resources:
        requests: { cpu: 500m, memory: 128Mi }
      securityContext:
        allowPrivilegeEscalation: false
        capabilities: { drop: ["ALL"] }
EOF
kubectl get nodes -L kubernetes.io/arch   # now both architectures present

# --- Consolidation works too ----------------------------------------------
kubectl delete pod graviton-test x86-test -n demo
sleep 120
kubectl get nodes   # the Karpenter nodes should be gone or going
```

If a NodeClaim stays `Pending`, read its status first — Karpenter puts the real reason there:

```bash
kubectl describe nodeclaim <name>
kubectl logs -n kube-system -l app.kubernetes.io/name=karpenter --tail=100
```

Match the message against `reference/gotchas.md` — G-02 (quota), G-03 (access entry), G-07 (Spot
SLR) and G-13 (discovery tags) cover nearly every real case.

---

## Notes for the implementing agent

- Do not create the `demo` namespace or any demo workload in Terraform. Phase 6 ships them as plain
  YAML, because the assignment asks to show what a *developer* does — and developers run `kubectl
  apply`, not `terraform apply`.
- Keep the chart minimal. It is a delivery mechanism for four objects, not a product.
- `helm lint` and `helm template` need no cluster. Run them even when you cannot apply.

---

## Agent prompt

```text
Implement Phase 5 of the EKS + Karpenter Terraform assessment.

Working directory: terraform/

Read these files first, in this order:
  1. docs/reference/karpenter-api-reference.md   (READ IT ALL — §4 is the YAML you are
                                                          implementing, §8 is the checklist you
                                                          must satisfy)
  2. docs/contracts/interface-contract.md        (NORMATIVE — §5.4, §6 object names)
  3. docs/reference/gotchas.md                   (G-13, G-15, G-17, G-19)
  4. docs/00-architecture-and-decisions.md       (ADR-7, ADR-9, ADR-10)
  5. docs/phases/phase-05-nodepools.md           (your specification)
  6. docs/phases/phase-04-karpenter-helm.md      (read its Completion report only)

Implement modules/cluster-resources/ (a local Helm chart plus a helm_release that
installs it) exactly as phase-05 specifies, then wire it into main.tf.

Critical constraints:
  - Object names are fixed: EC2NodeClass "default", NodePools "amd64" and "arm64".
  - The disruption block MUST set both consolidationPolicy AND consolidateAfter.
  - amiSelectorTerms must contain ONLY the alias term.
  - Use spec.role (never spec.instanceProfile). volumeSize is a quoted string with a unit.
  - Requirements must use instance-category / instance-generation / instance-cpu.
    Do NOT hardcode a list of instance types.
  - depends_on the Karpenter Helm release, or the CRDs will not exist yet.
  - Do NOT use consolidationPolicy "Balanced", terminationGracePeriod, or spec.replicas.
  - Do NOT create the demo namespace or demo workloads — Phase 6 owns those.
  - Run `helm lint` and `helm template` and verify the rendered output against the checklist in
    karpenter-api-reference.md §8.
  - terraform fmt -recursive must be clean.
  - Do NOT run `terraform apply` unless I have told you AWS credentials are available.

When finished, run the applicable "Acceptance criteria", then fill in the
"## Completion report" section at the bottom of docs/phases/phase-05-nodepools.md
and stop. Do not start Phase 6.
```

---

## Completion report

- Status: DONE — every "Without credentials" acceptance criterion passes, including all seven
  positive greps and both negative (leakage) greps, which find nothing outside comments. Every
  item in `karpenter-api-reference.md` §8's footgun checklist was checked against the rendered
  output. The "With credentials" acceptance criteria are unverified — no AWS credentials were
  available, per the task's instruction not to run `terraform apply`. **Reviewed 2026-08-16:**
  an independent review re-ran the full "Without credentials" acceptance criteria and re-checked
  every item in `karpenter-api-reference.md` §8's footgun checklist against fresh `helm template`
  output, plus the §5.4 contract gap-fix and the §5.3c/§5.3d RBAC/quota objects — all PASS, zero
  code or contract changes required. The review found two reporting-only defects in this
  completion report, both corrected here: (1) Deviation #1 claimed `helm lint` enforces
  `Chart.yaml`'s `name` matching the chart directory's basename — false, empirically disproven
  with Helm v3.19.0 (`helm lint`, `helm lint --strict`, and `helm package` all pass with a
  mismatched name); the rationale is corrected below, `Chart.yaml`'s `name: chart` is unchanged
  since the deviation itself is harmless. (2) The `variables.tf` files-created bullet said "13
  inputs" when the file (and interface-contract §5.4's amended table) actually has 16; corrected
  below. No blockers found. **Reviewed 2026-08-17:** a second independent review re-ran
  `terraform fmt -check -recursive`, `terraform init -backend=false`/`validate`, `helm lint`
  (plain and `--strict`), all nine acceptance-criteria greps, the two negative-leakage greps, a
  field-by-field diff of `variables.tf`/`outputs.tf`/`main.tf`'s wiring against
  interface-contract.md §5.4 and root `main.tf`'s call site, and a repo-wide grep for
  `instanceProfile`/`Balanced`/`terminationGracePeriod`/`spec.replicas` outside comments — all
  PASS, zero code changes required. It additionally rendered `EC2NodeClass.spec.tags` with a
  **non-empty** `tags` map (every prior render, including 2026-08-16's, used the chart's default
  `tags: {}`, so the merge collision Deviation #2 describes had never actually been exercised) —
  confirmed `ManagedBy: karpenter` wins over a same-keyed `ManagedBy: terraform` from the passed-in
  map exactly as Deviation #2 claims, and `Project`/`Environment`/`Component` all reach the
  rendered output, so S-C1/interface-contract §2.2's cost-allocation requirement genuinely holds.
  No blockers found; one latent gap outside this phase's scope is recorded under "Notes for the
  next phase" below rather than fixed here.

- Files created/changed:
  - `modules/cluster-resources/versions.tf` — **new.** Only `helm` in `required_providers`
    (`~> 3.2`, matching every other module), no `provider` block, no `aws` entry — this module has
    no AWS resources of its own. Mirrors `modules/karpenter/versions.tf`'s pattern.
  - `modules/cluster-resources/variables.tf` — **new.** 16 inputs per interface-contract §5.4 as
    amended (the 13 rows the table already had, plus the three added in this change).
  - `modules/cluster-resources/main.tf` — **new.** `locals.arm64_weight`/`amd64_weight` (from
    `var.default_arch`) and `locals.enabled_pool_count`; the single `helm_release.cluster_resources`
    resource, `depends_on = [var.karpenter_helm_release_name]`, `values = [yamlencode({...})]`
    covering `clusterName`/`nodeIamRoleName`/`amiAlias`/`capacityTypes`/`cpuLimitPerPool`/
    `memoryLimitPerPool`/`tags`/`amd64.*`/`arm64.*`/`governedNamespaces`/`namespaceQuota.*`
    (snake_case→camelCase mapped here)/`developerRbacGroup`; and the §5.3c
    `lifecycle.precondition` tying `developer_namespaces` to `governed_namespaces`.
  - `modules/cluster-resources/outputs.tf` — **new.** `storage_class_name` (literal `"gp3"`),
    `governed_namespace_names` (`var.governed_namespaces`), `nodepool_names` (`compact()` over
    `enable_arm64`/`enable_amd64`), `ec2nodeclass_name` (literal `"default"`).
  - `modules/cluster-resources/README.md` — **new.** Module purpose, the default-arch trade-off
    (§5.5) with the `buildx` command and the `default_arch="amd64"` escape hatch, why the
    StorageClass lives here (ADR-6, §2.5b), a pointer to §5.3d for the RBAC boundary rather than
    duplicating it, and a Helm-values table.
  - `modules/cluster-resources/chart/Chart.yaml` — **new.** `name: chart` (see Deviation #1).
  - `modules/cluster-resources/chart/values.yaml` — **new.** Standalone-complete defaults for every
    key the templates read, so `helm lint`/`helm template` succeed with zero `--set` flags.
  - `modules/cluster-resources/chart/templates/ec2nodeclass.yaml` — **new.** §2's YAML, `role` (not
    `instanceProfile`), single `alias` term, explicit `metadataOptions`, `blockDeviceMappings` with
    re-stated `encrypted: true` and quoted `"50Gi"`, and `tags` built via a single `merge()`+`toYaml`
    (see Deviation #2).
  - `modules/cluster-resources/chart/templates/nodepools.yaml` — **new.** Both `amd64`/`arm64`
    NodePools, each guarded by `{{- if .Values.<arch>.enabled }}`, `disruption` setting both
    `consolidationPolicy` and `consolidateAfter` (G-17), `expireAfter: 720h`, `budgets: [{nodes:
    "10%"}]`, category/generation/cpu requirements (no hardcoded instance-type list).
  - `modules/cluster-resources/chart/templates/storageclass.yaml` — **new.** Copied verbatim from
    phase-02 §2.5b, `volumeBindingMode: WaitForFirstConsumer` intact, with the ADR-6 comment §5.3b
    asks for.
  - `modules/cluster-resources/chart/templates/namespaces.yaml` — **new.** §5.3c's
    Namespace/ResourceQuota/LimitRange range plus §5.3d's ClusterRole and per-namespace
    RoleBinding, copied close to verbatim (multi-doc, `---`-separated), per the file-list note that
    there is no separate `rbac.yaml`.
  - `main.tf` (root) — added the `module "cluster_resources"` block (4th module block, after
    `module.karpenter`); rewrote the header comment from forward-looking to present-tense.
  - `docs/contracts/interface-contract.md` — §5.4's input table amended in place: added
    `memory_limit_gi`, `developer_namespaces`, `tags` rows (see below).

- Deviations from spec:
  1. `Chart.yaml`'s `name` is `chart`, matching the directory the file list fixes at
     `modules/cluster-resources/chart/`. This is cosmetic, not enforced: an earlier draft of this
     report claimed `helm lint` requires `Chart.yaml`'s `name` to equal the chart directory's
     basename — that is false, and was corrected during the 2026-08-16 review (see the Reviewed
     note in Status). Verified directly with Helm v3.19.0: `helm lint`, `helm lint --strict`, and
     `helm package` all pass cleanly against this chart directory even with a mismatched
     `Chart.yaml` `name` (e.g. `name: cluster-resources` in a directory named `chart`). The Helm
     *release* name is set by Terraform (`name = "cluster-resources"` in
     `helm_release.cluster_resources`) and is what actually appears in `helm list`/`helm
     history` — nothing depends on the in-chart name.
  2. `EC2NodeClass.spec.tags` is built with `merge(dict("Name", ..., "ManagedBy", "karpenter"),
     .Values.tags)` + a single `toYaml`, not §2's literal static block followed by a separate render
     of `.Values.tags`. `local.tags` already carries `ManagedBy: terraform`; emitting §2's hardcoded
     `ManagedBy: karpenter` line *and* `.Values.tags` as two separate map fragments would produce a
     duplicate `ManagedBy` key in the same YAML map, which fails to parse. The merge produces one
     map, with `Name`/`ManagedBy=karpenter` as the merge *destination* so they win over any
     same-keyed entry from `.Values.tags` (sprig `merge` gives destination-dict keys precedence) —
     confirmed by rendering: `tags: {ManagedBy: karpenter, Name: test-karpenter-node}`, i.e. §2's
     `ManagedBy: karpenter` intent survives even though `local.tags` carries a different value for
     the same key.
  3. Noted per the task's own instruction, not something introduced here: §5.1's `yamlencode`
     example and the "Acceptance criteria" section disagree on the values key name (`cpuLimitPerPool`
     vs. `--set cpuLimit=100`). §5.1's code (the normative `helm_release` implementation) was
     followed literally — the actual template/values key is `cpuLimitPerPool`/`memoryLimitPerPool`.
     `--set cpuLimit=100` in the acceptance script is an inert unknown key Helm silently accepts; it
     does not affect any of that script's grep assertions, all confirmed passing below.
  4. §5.1's own `yamlencode` block, copied literally, emits only 9 keys (`clusterName`,
     `nodeIamRoleName`, `amiAlias`, `capacityTypes`, `cpuLimitPerPool`, `memoryLimitPerPool`, `tags`,
     `amd64`, `arm64`) — it does not emit `governedNamespaces`, `namespaceQuota`, or
     `developerRbacGroup`, even though `namespaces.yaml` (§5.3c/§5.3d, required by the same phase
     doc) reads all three. `main.tf`'s `values` block was extended with those three keys beyond
     §5.1's literal example; omitting them would render `namespaces.yaml` as an empty no-op while
     every acceptance grep (which only checks NodePool/EC2NodeClass strings) still passed.
  5. `chart/values.yaml` was given full standalone defaults for every value key the templates read
     (`governedNamespaces: [demo]`, all five `namespaceQuota.*` fields, `developerRbacGroup`, etc.),
     not only `cpuLimitPerPool`/`memoryLimitPerPool` as the task's inconsistency note called out —
     the first "Without credentials" acceptance command (`helm lint ... --set clusterName=test --set
     nodeIamRoleName=test-role`, no other flags) would otherwise nil-pointer on
     `.Values.namespaceQuota.requestsCpu` during template rendering.
  6. Each `NodePool` is wrapped in `{{- if .Values.<arch>.enabled }}` so a disabled pool is not
     rendered at all (Karpenter has no per-NodePool enable/disable field) — needed to make
     `outputs.tf`'s `nodepool_names` (driven by `enable_amd64`/`enable_arm64`) match what the chart
     actually creates. Not spelled out as a template detail in §5.3/§5.4's YAML but required for the
     module contract's `enable_amd64`/`enable_arm64` inputs to mean anything.

- Names added to interface-contract.md (§5.4's `modules/cluster-resources` input table):
  1. `memory_limit_gi` (`number`) — total memory ceiling (GiB) across all enabled NodePools, divided
     by `local.enabled_pool_count` to compute `memoryLimitPerPool`. Root variable
     `nodepool_memory_limit_gi` already existed; this wires it into the module.
  2. `developer_namespaces` (`list(string)`) — the namespaces Phase 2's access entries are scoped
     to. Not consumed by any resource attribute in this module (`modules/eks`'s access entries carry
     no `policy_associations`, hence no `access_scope`); consumed only by
     `helm_release.cluster_resources`'s `lifecycle.precondition`, which is the actual enforcement
     point tying access to governance.
  3. `tags` (`map(string)`) — every other local module (`network`, `eks`, `karpenter`) already takes
     this input per interface-contract §2.2's rule that every module receives `local.tags`; §5.4's
     table simply omitted the row for `cluster-resources` even though §5.1's own example code uses
     `tags = var.tags`.

- Verification run:
  ```
  $ terraform fmt -check -recursive
  (no output — clean)

  $ terraform init -backend=false -input=false
  Terraform has been successfully initialized!

  $ terraform validate
  Success! The configuration is valid.

  $ cd modules/cluster-resources && helm lint ./chart --set clusterName=test --set nodeIamRoleName=test-role
  ==> Linting ./chart
  [INFO] Chart.yaml: icon is recommended
  1 chart(s) linted, 0 chart(s) failed

  $ R=$(helm template ./chart --set clusterName=test --set nodeIamRoleName=test-role \
       --set amiAlias=al2023@latest --set cpuLimit=100)
  $ echo "$R" | grep -q 'karpenter.sh/v1'      && echo "PASS: NodePool API version"
  PASS: NodePool API version
  $ echo "$R" | grep -q 'karpenter.k8s.aws/v1' && echo "PASS: EC2NodeClass API version"
  PASS: EC2NodeClass API version
  $ echo "$R" | grep -q 'consolidateAfter'     && echo "PASS: G-17 avoided"
  PASS: G-17 avoided
  $ echo "$R" | grep -q 'httpTokens: required' && echo "PASS: IMDSv2"
  PASS: IMDSv2
  $ echo "$R" | grep -q 'encrypted: true'      && echo "PASS: EBS encryption"
  PASS: EBS encryption
  $ echo "$R" | grep -q 'limits'               && echo "PASS: blast radius capped"
  PASS: blast radius capped
  $ echo "$R" | grep -qE 'volumeSize: *"?[0-9]+Gi' && echo "PASS: volumeSize has a unit"
  PASS: volumeSize has a unit
  $ echo "$R" | grep -vE '^[[:space:]]*#' | grep -i 'Balanced'
  (no output — PASS)
  $ echo "$R" | grep -vE '^[[:space:]]*#' | grep 'instanceProfile'
  (no output — PASS)
  ```
  Also checked, beyond the script's own assertions: `grep -c 'kind: Namespace'` = 1,
  `grep -c 'kind: NodePool'` = 2 (`amd64` and `arm64`), `kind: RoleBinding`, `kind: ClusterRole`,
  and `kind: StorageClass` all present. Cross-checked every box in
  `karpenter-api-reference.md` §8 against the rendered output — all satisfied. Confirmed
  `grep -rn "instanceProfile|Balanced|terminationGracePeriod|spec.replicas"` across
  `modules/cluster-resources/` finds no live use, only two comment lines (`variables.tf`'s
  `node_iam_role_name` description and `ec2nodeclass.yaml`'s own explanatory comment, both of
  which mention `instanceProfile` only to say it is not used).

  The `depends_on = [var.karpenter_helm_release_name]` ordering edge (the one thing G-19 exists to
  prevent, and the one thing none of the above actually proves) was verified statically:
  ```
  $ terraform graph | grep -i cluster_resources
    "module.cluster_resources.helm_release.cluster_resources" -> "module.karpenter.helm_release.karpenter";
    "module.cluster_resources.helm_release.cluster_resources" -> "module.karpenter.module.karpenter.aws_iam_role.node";
  ```
  Confirms the string-reference `depends_on` pattern does propagate through the module-input
  reference graph to `helm_release.karpenter`, as the task specified it would — no substitute
  dependency mechanism was needed. (`terraform graph` required a real, if throwaway, backend to run
  under this Terraform version — a local `override.tf` pointing at a scratch state file, created and
  deleted for this one check only; no state was ever written for the S3 backend, and `override.tf`
  is not part of the committed change.)

- Notes for the next phase: Phase 6 (`examples/`) should target the `demo` namespace this module
  creates — do not `kubectl create namespace demo` (it would be unlabelled and unquota'd, silently
  disabling the PSA/quota/limit-range controls this phase built). `governed_namespaces` and
  `developer_namespaces` both default to `["demo"]`, so no `.tfvars` change is needed for the default
  single-namespace demo. Root outputs.tf deliberately does not surface
  `module.cluster_resources`'s four outputs (`storage_class_name`, `governed_namespace_names`,
  `nodepool_names`, `ec2nodeclass_name`) — interface-contract §4 does not list them, following the
  same precedent Phase 4 set for `helm_release_name`. If a later phase's `verify.sh` or README wants
  one of them at the root, add it to interface-contract §4 in that phase's own change rather than
  assuming it is already there.

  **(Added during the 2026-08-17 review.)** Root `outputs.tf` has no `developer_rbac_group` output,
  even though interface-contract.md §4 already lists one ("Consumed by `verify.sh`'s
  `kubectl auth can-i --as-group` assertions") and phase-08-verification-teardown.md §D2 literally
  reads `terraform output -raw developer_rbac_group`. This is a pre-existing gap, not one introduced
  by this phase — Phase 5's own "Acceptance criteria" and §5.3d's `kubectl auth can-i` commands
  hardcode `--as-group=opsfleet:developers` rather than reading the output, so nothing in this
  phase's own verification needs it, and it was correctly out of scope to add here per the same
  precedent phase-02's completion report set for the missing root `region` output (flagged, not
  fixed, because it wasn't that phase's own contract section either). `var.developer_rbac_group` is
  a plain pass-through with no module dependency, so any phase — most naturally Phase 8, when
  `verify.sh` is actually written — can add `output "developer_rbac_group" { value =
  var.developer_rbac_group }` to root `outputs.tf` in one line. Flagging now so Phase 8 does not
  discover this as a surprise mid-script.
