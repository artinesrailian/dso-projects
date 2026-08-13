# Phase 4 — Karpenter Helm deployment

**Depends on:** Phase 3.
**Produces:** `modules/karpenter/helm.tf` (two Helm releases) and the `helm` provider block
in `providers.tf`.

---

## Goal

The Karpenter controller running in `kube-system`, authenticated by Pod Identity, watching the
interruption queue, with its CRDs installed by a chart that can actually upgrade them.

At the end of this phase `kubectl get pods -n kube-system -l app.kubernetes.io/name=karpenter` shows
two Running pods and `kubectl get crd | grep karpenter` shows the CRDs — but no NodePools exist yet,
so nothing is provisioned. That is correct.

---

## Inputs

| Source | What you need |
|---|---|
| `reference/version-pinning.md` | **§2.1 the two-chart requirement**, §2.2 helm provider v3 syntax, chart version `1.14.0` |
| `reference/karpenter-api-reference.md` | §6 the full Helm values reference and chart defaults |
| `contracts/interface-contract.md` | §7 provider configuration |
| `reference/gotchas.md` | The CoreDNS/`dnsPolicy` deadlock — read it before writing values |
| Phase 3 completion report | The `module.karpenter` output names as implemented |

---

## Files to create / edit

```
modules/karpenter/helm.tf     # NEW
modules/karpenter/variables.tf # EDIT — add karpenter_version, cluster_endpoint
modules/karpenter/outputs.tf   # EDIT — add helm_release_name
modules/karpenter/versions.tf  # EDIT — add the helm provider requirement
providers.tf                   # EDIT — add the helm provider block
versions.tf                    # EDIT — add hashicorp/helm ~> 3.2
```

---

## Specification

### 4.1 The `helm` provider

Add to `providers.tf` exactly as interface-contract §7 specifies. Two things to get right:

**Syntax.** The provider is v3. `kubernetes` and `exec` are **attributes**, not blocks:

```hcl
provider "helm" {
  kubernetes = {          # NOT `kubernetes { ... }`
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    exec = {              # NOT `exec { ... }`
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.region]
    }
  }
}
```

**Auth.** `exec`, never `data.aws_eks_cluster_auth`. The static token lives 15 minutes and a first
apply takes longer than that, producing intermittent `401 Unauthorized` partway through.

Add `hashicorp/helm ~> 3.2` to `versions.tf` and to the module's `versions.tf`
`required_providers` (modules declare requirements; they never configure providers).

### 4.2 Two Helm releases, in order

```hcl
# ---------------------------------------------------------------------------
# CRDs, as a SEPARATE release.
#
# The main karpenter chart ships its CRDs in charts/karpenter/crds/. Helm's
# rule for that directory: CRDs are installed on FIRST INSTALL ONLY and are
# never added or updated by any later `helm upgrade`. A stack that installs
# only the main chart therefore works on day one and then silently fails to
# pick up CRD changes forever after — which bites immediately, because 1.14.0
# introduced a brand-new CapacityBuffer CRD.
#
# The karpenter-crd chart ships the same CRDs under templates/, so Helm
# manages them normally. This is the path Karpenter's own docs prescribe.
# ---------------------------------------------------------------------------
resource "helm_release" "karpenter_crd" {
  name       = "karpenter-crd"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter-crd"
  version    = var.karpenter_version
  namespace  = var.namespace

  wait = true
}

resource "helm_release" "karpenter" {
  name       = "karpenter"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = var.karpenter_version   # MUST equal the CRD chart version
  namespace  = var.namespace

  # Block until the controller is actually Running. The upstream example uses
  # wait = false, which returns before the CRDs are established — anything
  # applying a NodePool in the same run then fails with
  # `no matches for kind "NodePool"`. Phase 5 applies exactly that.
  wait    = true
  timeout = 600

  depends_on = [helm_release.karpenter_crd]

  # helm provider v3: a LIST of objects, not repeated `set { }` blocks.
  set = [
    { name = "settings.clusterName", value = var.cluster_name },
    { name = "settings.clusterEndpoint", value = var.cluster_endpoint },

    # OPTIONAL to the chart, MANDATORY in practice. The chart guards this with
    # `{{- with }}`, so omitting it installs cleanly and silently disables ALL
    # interruption handling: Spot 2-minute notices, rebalance recommendations
    # and scheduled-change events are ignored, and nodes die undrained.
    { name = "settings.interruptionQueue", value = module.karpenter.queue_name },

    # THE DEADLOCK FIX. Karpenter defaults to dnsPolicy: ClusterFirst, i.e. it
    # resolves through in-cluster CoreDNS. If CoreDNS is itself waiting on
    # capacity, Karpenter cannot resolve sts.<region>.amazonaws.com, fails with
    # `WebIdentityErr ... i/o timeout`, and neither can proceed. `Default` uses
    # the host's VPC DNS instead. The upstream module example sets this too.
    { name = "dnsPolicy", value = "Default" },

    # The chart sets no resources at all by default. Karpenter's own install
    # command sets 1 CPU / 1Gi; an unbounded controller on a two-node bootstrap
    # group is a real noisy-neighbour risk.
    { name = "controller.resources.requests.cpu", value = "1" },
    { name = "controller.resources.requests.memory", value = "1Gi" },
    { name = "controller.resources.limits.cpu", value = "1" },
    { name = "controller.resources.limits.memory", value = "1Gi" },
  ]
}
```

### 4.3 Values you must NOT set

| Value | Why not |
|---|---|
| `serviceAccount.annotations."eks.amazonaws.com/role-arn"` | That is the **IRSA** path. We use Pod Identity, which needs no chart-side configuration at all. Setting it produces two competing credential sources. |
| `serviceAccount.create` / `.name` | Defaults (`true` / `karpenter`) already match what the Phase 3 Pod Identity association was created against. Changing either breaks the binding silently. |
| `affinity` | The chart default already requires `karpenter.sh/nodepool` `DoesNotExist`, which is what stops Karpenter scheduling onto nodes it manages. Overriding it is how people break that guarantee. |
| `replicas` | Leave at `2`. See below. |
| Any `featureGates.*` | All at safe defaults. `spotToSpotConsolidation` is tempting for cost but is alpha — mention it in the README as future work, do not enable it. |

### 4.4 Why the bootstrap node group has two nodes

Worth restating here because it is where the symptom appears. The chart runs `replicas: 2` with a
**required** `podAntiAffinity` on `kubernetes.io/hostname`. Two replicas therefore need two distinct
nodes. And Karpenter structurally *cannot* fix this itself — its own node affinity excludes nodes
carrying `karpenter.sh/nodepool`, so it will not launch capacity to run itself.

The failure looks like: one Karpenter pod `Running`, one `Pending` forever, cluster otherwise
healthy, and no autoscaling ever happens. Phase 2's `min_size = 2` is what prevents it.

### 4.5 Optional: pin the controller to the bootstrap nodes

The upstream example labels its controller node group `karpenter.sh/controller = "true"` and sets a
matching `nodeSelector`. Belt-and-braces on top of the chart's built-in anti-affinity.

If Phase 2 tainted the bootstrap nodes (`taint_bootstrap_nodes = true`, the default), the chart's
default `CriticalAddonsOnly: Exists` toleration already covers it — no extra values needed. Verify
rather than assume.

### 4.6 Output

```hcl
output "helm_release_name" {
  description = "Karpenter Helm release name. Phase 5 depends_on this so that NodePools are applied only after the CRDs are established."
  value       = helm_release.karpenter.name
}
```

---

## Security requirements owned by this phase

- **S-40** Chart pinned to an exact version. No `latest`, no floating constraint.
- **S-41** Controller authenticates via Pod Identity; no IRSA annotation, no static credentials.
- **S-42** `settings.interruptionQueue` set, so Spot nodes are drained rather than killed.
- **S-43** Controller has CPU/memory requests and limits.
- **S-44** CRDs managed by the `karpenter-crd` chart, so security fixes to CRD validation actually
  land on upgrade.

---

## Acceptance criteria

Without credentials:

```bash
terraform fmt -check -recursive
terraform init -backend=false
terraform validate

cd modules/karpenter
grep -q 'karpenter-crd'                          helm.tf && echo "PASS: CRD chart present"
grep -q 'settings.interruptionQueue'             helm.tf && echo "PASS: interruption wired"
grep -q '"dnsPolicy"'                            helm.tf && echo "PASS: dnsPolicy override"
grep -q 'wait *= *true'                          helm.tf && echo "PASS: waits for readiness"
grep -q 'depends_on *= *\[helm_release.karpenter_crd\]' helm.tf && echo "PASS: ordering"

# Must find NOTHING (IRSA leakage / v2 syntax):
grep -n 'eks.amazonaws.com/role-arn' helm.tf
grep -nE '^\s*set\s*\{' helm.tf                  # v2 block syntax — will not parse under v3
grep -n 'aws_eks_cluster_auth' ../../providers.tf
```

With credentials:

```bash
terraform apply

# Two Running replicas on two DIFFERENT nodes
kubectl get pods -n kube-system -l app.kubernetes.io/name=karpenter -o wide
kubectl get pods -n kube-system -l app.kubernetes.io/name=karpenter \
  -o jsonpath='{.items[*].spec.nodeName}' | tr ' ' '\n' | sort -u | wc -l   # must be 2

# CRDs established
kubectl get crd | grep -E 'karpenter|capacitybuffer'
# Expect: ec2nodeclasses.karpenter.k8s.aws, nodepools.karpenter.sh, nodeclaims.karpenter.sh,
#         nodeoverlays.karpenter.sh, capacitybuffers.autoscaling.x-k8s.io

# Only v1 is served — proves you are not on a v1beta1-era chart
kubectl get crd nodepools.karpenter.sh -o jsonpath='{.spec.versions[*].name}'   # v1

# Pod Identity actually working: no credential errors, and it found the queue
kubectl logs -n kube-system -l app.kubernetes.io/name=karpenter --tail=100 \
  | grep -iE 'error|unauthorized|WebIdentityErr|i/o timeout' || echo "PASS: clean startup"

# Confirm the controller resolved its interruption queue
kubectl logs -n kube-system -l app.kubernetes.io/name=karpenter --tail=200 | grep -i 'interruption'
```

**If the controller logs `i/o timeout` reaching STS:** `dnsPolicy` did not take effect. Check §4.2.
**If one replica is `Pending`:** the bootstrap group has fewer than two schedulable nodes. See §4.4.

---

## Notes for the implementing agent

- Do not create NodePools or an EC2NodeClass. Phase 5.
- Both chart versions must be the same string. Drive both from `var.karpenter_version`.
- `oci://public.ecr.aws/karpenter` is anonymously pullable. If Helm asks for credentials, run
  `helm registry logout public.ecr.aws` — a stale login is the usual cause.
- If the apply fails with `no matches for kind` anywhere, `wait = true` is missing or `depends_on`
  is wrong.

---

## Agent prompt

```text
Implement Phase 4 of the EKS + Karpenter Terraform assessment.

Working directory: /home/artin/personal/git/opsfleet/terraform

SCOPE BOUNDARY — non-negotiable, applies to every action you take:
  1. Your working directory is /home/artin/personal/git/opsfleet/terraform. You never leave it.
     Every path in this prompt and in every doc it references is RELATIVE TO THAT DIRECTORY.
  2. The sibling directory /home/artin/personal/git/opsfleet/architecture is a DIFFERENT,
     UNRELATED assessment. Do not read it, write to it, list it, grep it, or cd into it.
     There is nothing in it you need.
  3. Create NOTHING at the repository root (/home/artin/personal/git/opsfleet) — no new files,
     no new directories, no sibling of terraform/ or architecture/. Everything you produce
     lives under terraform/. That includes .gitignore, CI config, scripts and notes.
  4. Do not run commands that walk the whole repo (`find /home/artin/personal/git/opsfleet`,
     `grep -r` from the root, `git status` at the root). Scope every search to terraform/.
  If you believe you genuinely need something outside terraform/, stop and say so in your
  completion report instead of doing it.

Read these files first, in this order:
  1. docs/reference/version-pinning.md          (§2.1 WHY there are two charts,
                                                         §2.2 helm provider v3 syntax)
  2. docs/reference/karpenter-api-reference.md  (§6 Helm values reference)
  3. docs/reference/gotchas.md                  (the CoreDNS/dnsPolicy deadlock)
  4. docs/contracts/interface-contract.md       (§7 provider configuration)
  5. docs/phases/phase-04-karpenter-helm.md     (your specification)
  6. docs/phases/phase-03-karpenter-aws.md      (read its Completion report only)

Implement modules/karpenter/helm.tf and add the helm provider block to
providers.tf, exactly as phase-04 specifies.

Critical constraints:
  - TWO helm_release resources: karpenter-crd first, then karpenter with depends_on.
    Both pinned to the same version string.
  - helm provider v3 syntax: `kubernetes = { ... }` and `exec = { ... }` are ATTRIBUTES,
    and helm_release `set` is a LIST OF OBJECTS. The v2 block syntax will not parse.
  - Set dnsPolicy=Default. Set settings.interruptionQueue. Set wait = true.
  - Do NOT set any serviceAccount annotation — we use Pod Identity, not IRSA.
  - Do NOT add a kubernetes provider. This stack uses only aws and helm.
  - Do NOT create NodePool or EC2NodeClass resources — Phase 5 owns those.
  - terraform fmt -recursive must be clean.
  - Do NOT run `terraform apply` unless I have told you AWS credentials are available.

When finished, run the applicable "Acceptance criteria", then fill in the
"## Completion report" section at the bottom of docs/phases/phase-04-karpenter-helm.md
and stop. Do not start Phase 5.
```

---

## Completion report

*To be filled in by the implementing agent.*

- Status:
- Files created/changed:
- Deviations from spec:
- Names added to interface-contract.md:
- Verification run:
- Notes for the next phase:
