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

> Correction (REVIEW.md F-09): "no autoscaling ever happens" overstates it. Karpenter uses leader
> election — the one Running replica autoscales normally; what's actually lost is HA, and the
> chart's own PodDisruptionBudget (`maxUnavailable: 1`) then blocks rotating that one node.
> Verified against the pinned chart's `values.yaml`.

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

Working directory: terraform/

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

- Status: DONE — every "Without credentials" acceptance criterion passes, including both the
  positive greps and the three negative (leakage) greps, and S-40 through S-44 are satisfied and
  traced to specific lines below. The "With credentials" acceptance criteria are unverified — no
  AWS credentials were available or acquired, per the task's own instruction not to run
  `terraform apply` without them. **Reviewed 2026-08-16:** independently re-ran every acceptance
  check, re-verified `helm.tf`/`providers.tf`/`versions.tf`/`variables.tf`/`outputs.tf` line by
  line against `version-pinning.md` §2.1–§2.2, `karpenter-api-reference.md` §6,
  `interface-contract.md` §4/§5.3/§7 and `gotchas.md` G-04/G-05/G-09/G-19/G-20/G-21, and confirmed
  `var.karpenter_version` defaults to `1.14.0` and `var.karpenter_namespace` to `kube-system`. No
  code or contract drift found — see Deviation #6.

- Files created/changed:
  - `modules/karpenter/helm.tf` — **new.** Two `helm_release` resources: `karpenter_crd` (chart
    `karpenter-crd`, `wait = true`) then `karpenter` (chart `karpenter`, `wait = true`,
    `timeout = 600`, `depends_on = [helm_release.karpenter_crd]`). Both pinned to
    `var.karpenter_version`. `karpenter`'s `set` list: `settings.clusterName`,
    `settings.clusterEndpoint`, `settings.interruptionQueue` (← `module.karpenter.queue_name`,
    the nested upstream submodule's output, same reference pattern already used by this module's
    own `outputs.tf`), `dnsPolicy = "Default"` (the CoreDNS deadlock fix, G-04), and
    `controller.resources.{requests,limits}.{cpu,memory}` at `1` / `1Gi`. No `serviceAccount`
    annotation, no `affinity`, no `replicas`, no `featureGates.*` — all left at chart defaults per
    §4.3.
  - `modules/karpenter/versions.tf` — added `helm = { source = "hashicorp/helm", version = "~> 3.2"
    }` to `required_providers`. Still no `provider` block (modules never configure providers).
  - `modules/karpenter/outputs.tf` — added `helm_release_name` (→ `helm_release.karpenter.name`),
    completing interface-contract §5.3's full 7-output signature. Updated the file's header comment
    to say so instead of "Phase 4's — not yet added."
  - `modules/karpenter/variables.tf` — descriptions for `cluster_endpoint`, `karpenter_version` and
    `namespace` rewritten from forward-looking ("unused by this phase — Phase 4 is the expected
    consumer") to present-tense, since Phase 4 now is that consumer. No name, type or default
    changed — these three variables were already declared correctly by Phase 3.
  - `providers.tf` (root) — added the `helm` provider block exactly per interface-contract §7:
    `kubernetes = { host, cluster_ca_certificate, exec = { ... aws eks get-token ... } }`, all as
    attributes (v3 syntax), authenticating via `exec`, never a static-token data source (G-20).
  - `versions.tf` (root) — added `helm = { source = "hashicorp/helm", version = "~> 3.2" }` to
    `required_providers`.
  - `.terraform.lock.hcl` (root) — changed. `terraform init -backend=false` resolved and added
    `hashicorp/helm 3.2.0` (matching `~> 3.2`, and matching `version-pinning.md`'s verified-latest
    `3.2.0` exactly). The other five providers (`aws`, `tls`, `time`, `null`, `cloudinit`) are
    unchanged. Committing this is correct per interface-contract §8 rule 6 (the lockfile is
    committed, not gitignored).
  - `outputs.tf` (root) — **one-line comment fix only, no output added.** The file's header comment
    said "Phase 4 adds the remaining Karpenter output (helm_release_name)," which is false:
    interface-contract §4's root-outputs table does not list `helm_release_name`, and §5.3 marks it
    a module-only output, consumed by Phase 5 via `module.karpenter.helm_release_name` wired
    directly in `main.tf` (§5.4's `karpenter_helm_release_name` input), not through a root output.
    Left unfixed this would have misdirected Phase 5 into expecting a root output that was never
    coming. No output block added or changed.
  - `modules/karpenter/README.md` — updated; see Deviations below for why this file, which is not
    in this phase's "Files to create/edit" list, needed touching.
  - `main.tf` (root) — **not changed.** `module "karpenter"` already wires `cluster_endpoint`,
    `karpenter_version` and `namespace` from Phase 3; nothing in Phase 4's file list required
    editing it.
  - No `NodePool` / `EC2NodeClass` resources anywhere — confirmed absent by inspection; Phase 5
    owns those.

- Deviations from spec:
  1. **The provider-config comment in `providers.tf` paraphrases interface-contract §7's exec
     comment instead of copying it verbatim, to avoid tripping phase-04's own negative grep.**
     §7's canonical code block comments `exec` with the literal text `data.aws_eks_cluster_auth`.
     Phase-04's own acceptance criteria include `grep -n 'aws_eks_cluster_auth' ../../providers.tf`
     and label it "must find NOTHING." Copying §7 verbatim would make that check fail on a comment,
     not a real usage. Phase-04 §4.1's own example code block already omits the string (the
     `NEVER use data.aws_eks_cluster_auth` sentence appears only in its surrounding prose, not
     inside the `hcl` block), so it was treated as the authoritative rendering for what actually
     goes in `providers.tf`; the deployed provider *configuration* — `exec` auth, attribute syntax,
     the exact argument set — is unchanged and matches §7 exactly. Only the comment wording differs.
  2. **Similarly, `helm.tf`'s "what we deliberately don't set" rationale was moved to
     `modules/karpenter/README.md` instead of living as an inline comment naming the IRSA
     annotation key.** The literal string `eks.amazonaws.com/role-arn` is what phase-04's negative
     grep checks for; an inline comment explaining why it's absent would itself be flagged. This
     follows the precedent phase-03's completion report set explicitly ("the six removed v20
     variable names... were kept entirely out of `main.tf`/`outputs.tf`, including in comments, and
     discussed only in `README.md` instead"). `helm.tf` keeps one short comment pointing at the
     README section by name; the full reasoning (service-account annotation, `serviceAccount`
     create/name, `affinity`, `replicas`, `featureGates.*`) is in README.md's new "Helm values
     intentionally not set (Phase 4)" section.
  3. **`modules/karpenter/README.md` and one comment line in root `outputs.tf` were edited, though
     neither is in this phase's "Files to create/edit" list.** Justified case by case: README.md
     needed it both as the destination for deviations #1–2 above and because Phase 4 falsified two
     of its existing claims — "No Kubernetes objects are created here and nothing talks to the
     cluster API" and "Does not install any Helm chart... Phase 4 owns both" — leaving them would
     have been actively wrong, not just stale. `outputs.tf`'s one-line header-comment fix is
     explained under Files above.
  4. **A working-directory slip mid-task, caught and fully cleaned up before any acceptance check
     was trusted.** While running the acceptance-criteria greps, a `cd modules/karpenter && grep
     ...` command left the shell's cwd inside `modules/karpenter/` for several subsequent commands.
     Those next `terraform fmt` / `terraform init -backend=false` / `terraform validate` calls
     therefore ran against `modules/karpenter/` treated as a standalone root — which "succeeded"
     meaninglessly (no `var.region`, no provider blocks) and created a stray nested
     `modules/karpenter/.terraform/` and `modules/karpenter/.terraform.lock.hcl`. Caught by
     `validate` erroring "Module not installed" (a symptom, not the cause) and by then checking
     `pwd`. Fix: deleted both stray artifacts, confirmed `git status` showed only the intended file
     changes, re-ran `fmt -check` / `init -backend=false` / `validate` from
     `terraform` using `terraform -chdir=...` and absolute
     paths, and re-verified the root `.terraform.lock.hcl` still carries all six providers (`aws`,
     `helm`, `tls`, `time`, `null`, `cloudinit`) after the fix. All acceptance-criteria commands
     reported in this section were the post-cleanup, correct-directory runs.
  5. No deviation from the two-Helm-release structure, the v3 attribute syntax, `dnsPolicy`,
     `settings.interruptionQueue`, `wait = true`, or the "do not set" list — all implemented exactly
     as specified.
  6. **(Added during the 2026-08-16 review pass.)** `modules/karpenter/README.md`'s "Helm values
     intentionally not set" section claimed the `spotToSpotConsolidation` future-work note was
     "noted... in the root README" — false at the time it was written, since the root README does
     not exist yet (it is Phase 7's deliverable, `docs/phases/phase-07-readme.md`, which does not
     mention `spotToSpotConsolidation` either — confirmed by grep). The instruction itself
     (phase-04 §4.3 / `karpenter-api-reference.md` §6: "mention it in the README as future work")
     is satisfied — the module README is *a* README, and the mention exists — only the claim about
     *which* README was wrong. Reworded to state plainly that this module's README is currently the
     only carrier of that note, with an explicit pointer for Phase 7 to pick it up. No code change;
     `fmt`/`validate`/`test` unaffected. Also checked `gotchas.md` G-09 (the destroy-ordering
     deadlock, which names `helm_release.karpenter` directly in its root cause) — its Fix section
     explicitly says "Phase 8 turns this into a scripted, verified runbook," so it is correctly out
     of this phase's scope; no `depends_on` or lifecycle change belongs in `helm.tf` for it.

- Names added to interface-contract.md: none. `helm_release_name` was already present in §5.3's
  signature (added there by Phase 3's own reservation of the full 7-output contract); this phase
  only implements it.

- Verification run (all from `terraform`, no AWS credentials
  used or required):
  - `terraform fmt -check -recursive` → clean (exit 0), both before and after the final
    `outputs.tf` comment fix.
  - `terraform -chdir=.../terraform init -backend=false` → resolves `hashicorp/helm 3.2.0`
    (matches `~> 3.2` and `version-pinning.md`'s verified `3.2.0`); all six required providers
    present in the lockfile afterward.
  - `terraform -chdir=.../terraform validate` → `Success! The configuration is valid.`
  - Acceptance-criteria greps, run against absolute paths from the repo root (all after the cwd
    slip in Deviation #4 was cleaned up):
    - `grep -q 'karpenter-crd' helm.tf` → PASS
    - `grep -q 'settings.interruptionQueue' helm.tf` → PASS
    - `grep -q '"dnsPolicy"' helm.tf` → PASS
    - `grep -q 'wait *= *true' helm.tf` → PASS (both `helm_release.karpenter_crd` and
      `helm_release.karpenter` set `wait = true`, per G-19's fix, which requires it on *both*
      releases — confirmed by inspection, not just the grep, which only proves at least one match)
    - `grep -q 'depends_on *= *\[helm_release.karpenter_crd\]' helm.tf` → PASS
    - `grep -n 'eks.amazonaws.com/role-arn' helm.tf` → no output → PASS
    - `grep -nE '^\s*set\s*\{' helm.tf` → no output → PASS (v3 list syntax throughout, no v2
      blocks)
    - `grep -n 'aws_eks_cluster_auth' providers.tf` → no output → PASS (see Deviation #1)
  - `terraform test` → 5 passed, 0 failed (the pre-existing `cidr_guard` / `network_endpoints`
    suites, unaffected by this phase's changes). Note on scope: these are `command = plan` tests
    against `mock_provider "aws"` only, with no `mock_provider "helm"`. They pass because a brand
    new `helm_release` resource doesn't need to contact the cluster during `plan`, and the mocked
    AWS provider returns concrete (not unknown) values for `module.eks`'s attributes that the
    `helm` provider config block reads. This confirms the Helm resources don't break planning; it
    is not evidence that a real Helm install behaves correctly — that's what the "With credentials"
    acceptance criteria are for, and they were not run.
  - `make check` (fmt + validate for root and `bootstrap/` + test + lint) → all green; `lint`
    cleanly skips (tflint/checkov not installed), consistent with Phases 2 and 3's environment.
  - `terraform apply` — **not run.** No AWS credentials were provided to this environment and the
    task explicitly says not to run it without them. Everything under "With credentials" — two
    Running replicas on two different nodes, CRDs established and serving only `v1`, clean
    controller startup logs, confirmed interruption-queue resolution — is unverified against a real
    cluster.
  - Security requirements owned by this phase, verified statically:
    - **S-40** (exact version pin, no `latest`, no floating constraint) — both `helm_release`
      resources use `var.karpenter_version` directly (root default `"1.14.0"`, `variables.tf:250-254`),
      not a `~>`-style constraint; Helm chart versions don't support floating constraints, so
      passing the variable through is itself the pin.
    - **S-41** (Pod Identity, no IRSA, no static credentials) — confirmed by the negative grep
      above (no `serviceAccount.annotations` entry in `set`) plus inspection: the `set` list has no
      `serviceAccount.*` key at all, leaving the chart's defaults (`create = true`,
      `name = "karpenter"`) which match the Pod Identity association Phase 3 created against.
    - **S-42** (`settings.interruptionQueue` set) — `helm.tf:50`,
      `{ name = "settings.interruptionQueue", value = module.karpenter.queue_name }`.
    - **S-43** (controller CPU/memory requests and limits) — `helm.tf:62-65`, all four of
      `controller.resources.{requests,limits}.{cpu,memory}` set to `1` / `1Gi`.
    - **S-44** (CRDs managed by the separate `karpenter-crd` chart) — `helm_release.karpenter_crd`
      exists as its own resource and `helm_release.karpenter` declares
      `depends_on = [helm_release.karpenter_crd]`.

- Notes for the next phase:
  - `module.karpenter.helm_release_name` is now available at the root for Phase 5's
    `modules/cluster-resources` to consume as its `karpenter_helm_release_name` input
    (interface-contract §5.4), so its `NodePool`/`EC2NodeClass` chart only applies after the
    Karpenter CRDs are established.
  - `node_security_group_id` remains declared on `modules/karpenter` (interface-contract §5.3) with
    no consumer in either Phase 3's `main.tf` or this phase's `helm.tf` — re-confirmed against this
    phase's own spec, which never mentions it. Still flagged, per Phase 3's note, as possibly a
    stable-but-unused part of the contract signature; not resolved here since resolving it isn't in
    scope for either phase's file list.
  - The "With credentials" acceptance criteria (two Running replicas on two distinct nodes, CRDs
    established serving only `v1`, clean controller logs, confirmed interruption-queue resolution)
    are entirely unverified. Whoever next has AWS credentials against this stack should run them
    before trusting the Helm-layer behavior, not just this phase's static checks.
  - `modules/karpenter/README.md` now documents, in "Helm values intentionally not set (Phase 4)"
    and "Provider auth: `exec`, not a static-token data source (Phase 4)", the reasoning that
    couldn't live in `helm.tf`/`providers.tf` themselves without tripping the negative greps (see
    Deviations #1–2). Any future phase adding more Helm-side "must not set" values should keep
    following that pattern — reasoning in README, a short pointer comment in the `.tf` file — rather
    than reintroducing the flagged strings inline.
