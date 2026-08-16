# Phase 5 — NodePools and EC2NodeClass (x86 + Graviton, Spot + On-Demand)

**Depends on:** Phase 4.
**Produces:** `modules/karpenter-resources/`, wired into `main.tf`.

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
modules/karpenter-resources/versions.tf
modules/karpenter-resources/variables.tf
modules/karpenter-resources/main.tf
modules/karpenter-resources/outputs.tf
modules/karpenter-resources/README.md
modules/karpenter-resources/chart/Chart.yaml
modules/karpenter-resources/chart/values.yaml
modules/karpenter-resources/chart/templates/ec2nodeclass.yaml
modules/karpenter-resources/chart/templates/nodepools.yaml
modules/karpenter-resources/chart/templates/storageclass.yaml
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
resource "helm_release" "karpenter_resources" {
  name      = "karpenter-resources"
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

The module is named `karpenter-resources` and this is not a Karpenter resource. That is a small
naming compromise, taken deliberately rather than adding a second provider or a second module for a
single object. Say so in a comment at the top of the template.

The one field not to change: `volumeBindingMode: WaitForFirstConsumer`. With Karpenter, `Immediate`
binding provisions the volume before the node exists, in an AZ Karpenter may not choose, and the pod
then never schedules.

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

cd modules/karpenter-resources
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
# SELF-CONTAINED ON PURPOSE. examples/namespace.yaml is a PHASE 6 artifact and
# this phase only depends on Phase 4, so it does not exist yet — the namespace
# is created inline here, WITH the Pod Security Admission labels.
#
# Do NOT substitute `kubectl create namespace demo`. That produces an
# UNLABELLED namespace, which silently disables the control S-64 calls
# API-server-enforced. If a pod below is rejected, fix the POD, not the
# namespace.
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: demo
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/enforce-version: v1.36
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
EOF

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

Working directory: /home/artin/personal/git/dso-projects/terraform

SCOPE BOUNDARY — non-negotiable, applies to every action you take:
  1. Your working directory is /home/artin/personal/git/dso-projects/terraform. You never leave it.
     Every path in this prompt and in every doc it references is RELATIVE TO THAT DIRECTORY.
  2. The sibling directory /home/artin/personal/git/dso-projects/architecture is a DIFFERENT,
     UNRELATED assessment. Do not read it, write to it, list it, grep it, or cd into it.
     There is nothing in it you need.
  3. Create NOTHING at the repository root (/home/artin/personal/git/dso-projects) — no new files,
     no new directories, no sibling of terraform/ or architecture/. Everything you produce
     lives under terraform/. That includes .gitignore, CI config, scripts and notes.
  4. Do not run commands that walk the whole repo (`find /home/artin/personal/git/dso-projects`,
     `grep -r` from the root, `git status` at the root). Scope every search to terraform/.
  If you believe you genuinely need something outside terraform/, stop and say so in your
  completion report instead of doing it.

Read these files first, in this order:
  1. docs/reference/karpenter-api-reference.md   (READ IT ALL — §4 is the YAML you are
                                                          implementing, §8 is the checklist you
                                                          must satisfy)
  2. docs/contracts/interface-contract.md        (NORMATIVE — §5.4, §6 object names)
  3. docs/reference/gotchas.md                   (G-13, G-15, G-17, G-19)
  4. docs/00-architecture-and-decisions.md       (ADR-7, ADR-9, ADR-10)
  5. docs/phases/phase-05-nodepools.md           (your specification)
  6. docs/phases/phase-04-karpenter-helm.md      (read its Completion report only)

Implement modules/karpenter-resources/ (a local Helm chart plus a helm_release that
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

*To be filled in by the implementing agent.*

- Status:
- Files created/changed:
- Deviations from spec:
- Names added to interface-contract.md:
- Verification run (paste the rendered `helm template` assertions):
- Notes for the next phase:
