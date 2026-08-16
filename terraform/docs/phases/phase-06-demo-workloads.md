# Phase 6 — Demo workloads (x86, Graviton, multi-arch)

**Depends on:** Phase 5.
**Produces:** `examples/` — plain Kubernetes YAML, not Terraform.

---

## Goal

This phase produces the artefact that answers requirement **R7**: *"demonstrates how an end-user (a
developer from the company) can run a pod/deployment on x86 or Graviton instance inside the
cluster."*

The audience is a developer at the company, not an infrastructure engineer. They should be able to
copy one file, change the image, and ship. Nothing here should require knowing what Karpenter is.

---

## Inputs

| Source | What you need |
|---|---|
| `reference/karpenter-api-reference.md` | §5 the scheduling semantics table — the manifests must match it exactly |
| `contracts/interface-contract.md` | §6 fixed object names (`demo` namespace, pool names) |
| `reference/gotchas.md` | G-16 (`exec format error`) |
| Phase 5 completion report | Confirm the NodePool names as implemented |

---

## Files to create

```
examples/README.md
examples/deployment-x86.yaml
examples/deployment-arm64.yaml
examples/deployment-multiarch.yaml
examples/job-arch-check.yaml
```

**These are not Terraform.** Do not add them to any `helm_release`, and do not reference them from
`main.tf`. The whole point is that a developer applies them with `kubectl`.

---

## Specification

### 6.1 Image choice — use public ECR, not Docker Hub

Every manifest must pull from `public.ecr.aws`. Docker Hub applies anonymous pull rate limits per
source IP, and a cluster behind a single NAT gateway presents exactly one IP — so a demo that pulls
`nginx:alpine` from Docker Hub works on your laptop and then fails with `toomanyrequests` for the
reviewer. That is a miserable way to lose marks.

Suggested images, all genuinely multi-arch:

| Purpose | Image | Runs as |
|---|---|---|
| Web workload | `public.ecr.aws/nginx/nginx-unprivileged:stable` | **uid 101, port 8080** |
| Shell / arch check | `public.ecr.aws/docker/library/busybox:latest` | uid 0 — **must set `runAsUser` explicitly** |
| Fuller OS | `public.ecr.aws/amazonlinux/amazonlinux:2023` | uid 0 — same caveat |

> ⚠️ **Do not use `public.ecr.aws/nginx/nginx:stable-alpine`.** It has no `USER` directive, so it
> runs as uid 0. Combined with S-60's mandatory `runAsNonRoot: true` — and with the
> `pod-security.kubernetes.io/enforce: restricted` label from §6.2 — the kubelet rejects the pod at
> container creation:
> `CreateContainerConfigError: container has runAsNonRoot and image will run as root`.
> The deployment never becomes available and R7 (the graded requirement) fails on the one manifest a
> reviewer actually runs.
>
> **`nginx-unprivileged` is the fix** — verified live on public ECR: `User=101`, `ExposedPorts=8080/tcp`.
>
> **Do not instead bolt `runAsUser: 101` onto plain nginx.** That image's config binds `listen 80`,
> a privileged port, which then needs `NET_BIND_SERVICE` — and `capabilities: {drop: ["ALL"]}`
> removes it. That is the trap on the obvious wrong fix.
>
> The same applies to **any** root image under a `restricted` namespace: the busybox Job in §6.6
> needs an explicit `runAsUser` (`65534`/nobody works and can still run `uname -m`).

Verify multi-arch support before committing to one:

```bash
docker manifest inspect public.ecr.aws/nginx/nginx-unprivileged:stable \
  | jq -r '.manifests[].platform | "\(.os)/\(.architecture)"'
# Expect both linux/amd64 and linux/arm64

# And confirm it does NOT run as root — this is the check that matters:
docker pull --platform linux/arm64 -q public.ecr.aws/nginx/nginx-unprivileged:stable
docker inspect --format 'User={{.Config.User}} Ports={{.Config.ExposedPorts}}' \
  public.ecr.aws/nginx/nginx-unprivileged:stable
# Verified 2026-08-11: User=101, ExposedPorts=map[8080/tcp:{}]
```

### 6.2 The `demo` namespace is **not** yours to create

Terraform creates it, with its Pod Security labels, ResourceQuota and LimitRange — see phase-05
§5.3c. **Do not ship an `examples/namespace.yaml`**, and do not tell anyone to
`kubectl create namespace demo`.

The reason is an ordering guarantee worth stating in `examples/README.md`: Phase 2 grants developers
edit rights on this namespace *in Terraform*. If the guardrails were a manual `kubectl apply`, then
`terraform apply` would hand out access to a namespace that might have no quota and no pod security,
and nothing would reconcile it afterwards. Both halves are Terraform, so they cannot drift apart.

What developers need to know, and what belongs in `examples/README.md`:

- The namespace already exists after `terraform apply`.
- It enforces the `restricted` Pod Security profile, so every pod needs `runAsNonRoot`, a matching
  `runAsUser`, `seccompProfile: RuntimeDefault` and `capabilities: {drop: ["ALL"]}`. The manifests
  here show exactly that — copy them.
- It has a ResourceQuota. `exceeded quota` on deploy means you hit it, not that the cluster is
  broken. `kubectl describe quota -n demo` shows the headroom.
- `services.loadbalancers` is quota'd to **0**. A `Service type=LoadBalancer` will be rejected;
  that is deliberate, because it would provision a public load balancer into the public subnets.
  Ask the platform team.

### 6.3 `deployment-arm64.yaml` — the Graviton case

The headline example. It must be **short enough to read in one screen** and heavily commented,
because this is the file a developer will actually copy.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-graviton
  namespace: demo
spec:
  replicas: 3
  selector:
    matchLabels: { app: web-graviton }
  template:
    metadata:
      labels: { app: web-graviton }
    spec:
      # ---------------------------------------------------------------
      # THIS IS THE ONLY LINE THAT PICKS THE ARCHITECTURE.
      # kubernetes.io/arch is a standard Kubernetes label that the kubelet
      # sets on every node. You do not need to know anything about
      # Karpenter, node pools, or instance types to use it.
      # ---------------------------------------------------------------
      nodeSelector:
        kubernetes.io/arch: arm64

      containers:
        - name: web
          # unprivileged variant: uid 101, listens on 8080 (not 80, which would
          # need NET_BIND_SERVICE — dropped below).
          image: public.ecr.aws/nginx/nginx-unprivileged:stable
          ports:
            - containerPort: 8080
          # Resource REQUESTS are what Karpenter does its maths on. Without
          # them Karpenter assumes the pod is ~0-cost and will happily pack
          # it onto an existing node instead of provisioning.
          resources:
            requests:
              cpu: 500m
              memory: 256Mi
            limits:
              memory: 512Mi
```

3 replicas × 500m = 1.5 vCPU, which reliably forces a new node on an otherwise idle cluster (the
bootstrap nodes are tainted) without blowing through a default account quota.

**Spread the replicas and protect them — this is a Spot-first cluster.** Without a spread
constraint, Karpenter bin-packs all three replicas onto the single node it provisions, and one Spot
reclaim (or one routine consolidation) takes the deployment to zero. Phase 7's README tells
developers to use a PodDisruptionBudget; the examples must therefore demonstrate one, or the advice
is hollow.

```yaml
      # Spread across nodes so a single Spot reclaim cannot take out every replica.
      # ScheduleAnyway, not DoNotSchedule: on a cold cluster there is exactly one
      # node, and a hard constraint would leave replicas Pending forever.
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: kubernetes.io/hostname
          whenUnsatisfiable: ScheduleAnyway
          labelSelector:
            matchLabels: { app: web-graviton }
        # ADR-1 pays for three AZs on the grounds that AZ diversity is the primary
        # Spot-availability lever. Nothing else in the stack actually spreads
        # anything across zones — no NodePool carries a topology.kubernetes.io/zone
        # requirement — so without this constraint all three replicas can sit in
        # one AZ and the third AZ is pure cost. This is the line that makes the
        # 3-AZ decision real.
        - maxSkew: 1
          topologyKey: topology.kubernetes.io/zone
          whenUnsatisfiable: ScheduleAnyway
          labelSelector:
            matchLabels: { app: web-graviton }
```

```yaml
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: web-graviton
  namespace: demo
spec:
  minAvailable: 2          # of 3 replicas
  selector:
    matchLabels: { app: web-graviton }
# Karpenter honours PDBs when it drains a node for consolidation or an
# interruption. Without one it will drain all three at once.
# A pod that must never be interrupted can also carry the annotation
#   karpenter.sh/do-not-disrupt: "true"
# — use it sparingly: it blocks consolidation and node expiry too.
```

Add the security context that any real deployment should carry, with a comment saying it is not
Karpenter-specific but is expected of production manifests:

```yaml
          securityContext:
            allowPrivilegeEscalation: false
            runAsNonRoot: true
            runAsUser: 101                     # this image's USER; required, see above
            readOnlyRootFilesystem: true
            capabilities: { drop: ["ALL"] }
            seccompProfile: { type: RuntimeDefault }   # required by PSA `restricted`
          volumeMounts:
            - { name: tmp, mountPath: /tmp }
      volumes:
        - { name: tmp, emptyDir: {} }
```

`seccompProfile: RuntimeDefault` is not optional decoration — the `restricted` Pod Security profile
applied in §6.2 rejects pods without it. Every pod in `examples/` needs it, including the Job.

**Test that this actually starts.** A `securityContext` that prevents the container from running is
worse than none: it fails at container creation, not at apply, so `kubectl apply` succeeds and the
deployment silently never becomes available.

### 6.4 `deployment-x86.yaml`

Identical, with `kubernetes.io/arch: amd64` and `name: web-x86`. The symmetry is the point: the
developer sees that exactly one line changes.

### 6.5 `deployment-multiarch.yaml` — the recommended pattern

This is the one to explain properly, because it is what the company should actually be doing.

Two things to demonstrate:

1. **No `nodeSelector` at all** → the pod is eligible for both pools, and the higher-weighted pool
   (arm64 by default) wins. Cheapest option, requires a multi-arch image.
2. **A soft preference**, for teams that want Graviton but need an x86 fallback if Graviton capacity
   is unavailable:

```yaml
      affinity:
        nodeAffinity:
          # "preferred", not "required" — if no arm64 capacity is available,
          # Karpenter falls back to amd64 rather than leaving the pod Pending.
          preferredDuringSchedulingIgnoredDuringExecution:
            - weight: 100
              preference:
                matchExpressions:
                  - key: kubernetes.io/arch
                    operator: In
                    values: ["arm64"]
```

Include the multi-arch build command in a comment, because it is the actual prerequisite:

```
docker buildx build --platform linux/amd64,linux/arm64 -t <repo>:<tag> --push .
```

### 6.6 `job-arch-check.yaml` — the proof

A tiny Job that prints where it landed. This is what someone runs to *believe* the demo:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: arch-check
  namespace: demo
spec:
  backoffLimit: 2
  template:
    spec:
      restartPolicy: Never
      nodeSelector:
        kubernetes.io/arch: arm64      # flip to amd64 to prove the other side
      containers:
        - name: arch
          image: public.ecr.aws/docker/library/busybox:latest
          command: ["sh", "-c"]
          args:
            - |
              echo "pod:          $(hostname)"
              echo "architecture: $(uname -m)"      # aarch64 on Graviton, x86_64 on Intel/AMD
              echo "node:         ${NODE_NAME}"
              echo "instance:     ${INSTANCE_TYPE}"
          env:
            - name: NODE_NAME
              valueFrom: { fieldRef: { fieldPath: spec.nodeName } }
            - name: INSTANCE_TYPE
              valueFrom: { fieldRef: { fieldPath: metadata.labels['node.kubernetes.io/instance-type'] } }
```

> ⚠️ **Verify the `INSTANCE_TYPE` fieldRef actually works.** Downward-API `fieldRef` on
> `metadata.labels` exposes the **pod's** labels, not the node's — so this may render empty. If it
> does, drop that line and get the instance type from the acceptance-criteria `kubectl` command
> instead. Do not ship an example whose output is blank.

### 6.7 `examples/README.md`

Short, task-oriented, written for a developer. It must cover:

1. Get access: `aws eks update-kubeconfig --region <region> --name <cluster>`
3. Run on Graviton — apply, then **watch a node get created**:
   ```bash
   kubectl apply -f deployment-arm64.yaml
   kubectl get nodeclaims -w                     # a node appears in ~40-70s
   kubectl get pods -n demo -o wide
   kubectl get nodes -L kubernetes.io/arch,karpenter.sh/capacity-type,node.kubernetes.io/instance-type
   ```
4. Run on x86 — same, with the other file.
5. Prove it: `kubectl logs -n demo job/arch-check`
6. Clean up, and note that Karpenter removes the nodes automatically after consolidation.
7. **The one caveat**: if your image is x86-only and you set no `nodeSelector`, you land on Graviton
   and get `exec format error`. Show the fix (multi-arch build, or pin to `amd64`).

Keep it to about one screen. The full story lives in the top-level README.

---

### 6.8 What is deliberately NOT demonstrated — say so

The IMDS hop-limit control (S-51) is justified by "workloads use Pod Identity, so they have no
legitimate need for IMDS". That justification is only honest if a developer can actually *get* a Pod
Identity — and nothing in this POC shows them how, because no demo workload needs AWS access.

Add a short section to `examples/README.md` rather than leaving the gap silent:

> **My app needs to call AWS (S3, DynamoDB, Secrets Manager). How?**
> Not with an access key in a Secret. Ask the platform team for an **EKS Pod Identity association**:
> they create an IAM role trusted by `pods.eks.amazonaws.com` and associate it with your
> ServiceAccount, exactly as this stack already does for the EBS CSI driver
> (`modules/eks/iam.tf`). Your pod then picks the credentials up automatically through the AWS SDK —
> no annotation, no mounted secret, no code change.
> This POC ships no example of it because no demo workload needs AWS access. It is a
> two-resource addition per application, not a redesign.

Same for application secrets: there is no secrets-management story here (no External Secrets
Operator, no Secrets Manager CSI driver). A developer will otherwise reach for a plain Kubernetes
Secret, which every other developer in the shared namespace can read. Say that plainly.

---

## Security requirements owned by this phase

- **S-60** Manifests set `runAsNonRoot`, `allowPrivilegeEscalation: false`, drop all capabilities.
- **S-61** Resource requests and limits on every container — an unbounded pod can drive Karpenter to
  provision an enormous instance.
- **S-62** Images pulled from a registry with an explicit tag. No `:latest` on the workload images
  (the busybox job is the pragmatic exception; call it out).
- **S-63** No hostPath, no hostNetwork, no privileged containers.

---

## Acceptance criteria

Without a cluster:

`kubectl apply --dry-run=client` is **not** an offline check — it still contacts the API server for
the RESTMapper and the OpenAPI schema, and fails with `failed to download openapi: ... connection
refused` when no cluster is reachable. Use a real offline validator:

```bash
cd examples
# Schema-aware and genuinely offline. Preferred.
kubeconform -strict -summary -kubernetes-version 1.36.0 *.yaml

# Fallback if kubeconform is unavailable — parse-only: catches YAML errors but
# not schema errors. Still better than a check that cannot run at all.
python3 -c "import yaml,sys; [list(yaml.safe_load_all(open(f))) for f in sys.argv[1:]]; print('PASS: all files parse')" *.yaml

# The namespace belongs to Terraform (phase-05 §5.3c). A namespace.yaml here
# would be a second source of truth, and following it yields an unlabelled,
# unquota'd namespace that silently voids S-64 and S-28a.
[ -e namespace.yaml ] && echo "FAIL: delete namespace.yaml — phase-05 owns the namespace"

# Every workload image must come from public ECR (Docker Hub rate limits).
grep -h 'image:' *.yaml | grep -v 'public.ecr.aws' && echo "FAIL: non-ECR image" || echo "PASS: all images from public ECR"

# Arch selection is present and symmetric
grep -l 'kubernetes.io/arch: arm64' *.yaml
grep -l 'kubernetes.io/arch: amd64' *.yaml

# CREDENTIAL-FREE GUARD for the failure above. Any manifest asserting
# runAsNonRoot must also pin runAsUser, or it will CreateContainerConfigError
# at runtime on a root image. The runtime gate (kubectl wait) only fires when
# credentials exist, which is not the default state of this repo.
for f in *.yaml; do
  if grep -q 'runAsNonRoot: true' "$f" && ! grep -q 'runAsUser:' "$f"; then
    echo "FAIL: $f asserts runAsNonRoot without runAsUser"; fi
done

# PSA `restricted` also requires a seccomp profile on every pod.
for f in deployment-*.yaml job-*.yaml; do
  grep -q 'seccompProfile' "$f" || echo "FAIL: $f missing seccompProfile (PSA restricted will reject it)"
done
```

With a cluster — **this is the assignment's acceptance test, run it properly**:

```bash

# --- Graviton ---
kubectl apply -f deployment-arm64.yaml
kubectl wait --for=condition=available --timeout=5m deployment/web-graviton -n demo
kubectl get pods -n demo -o wide
kubectl get nodes -L kubernetes.io/arch,karpenter.sh/capacity-type,node.kubernetes.io/instance-type
# The pods' node must show arch=arm64 and a g-suffixed instance type.

# --- x86 ---
kubectl apply -f deployment-x86.yaml
kubectl wait --for=condition=available --timeout=5m deployment/web-x86 -n demo
kubectl get nodes -L kubernetes.io/arch     # both amd64 and arm64 now present

# --- Proof ---
kubectl apply -f job-arch-check.yaml
kubectl wait --for=condition=complete --timeout=5m job/arch-check -n demo
kubectl logs -n demo job/arch-check          # must print aarch64

# --- Multi-arch defaults to Graviton ---
kubectl apply -f deployment-multiarch.yaml
kubectl get pods -n demo -o wide -l app=web-multiarch
kubectl get nodes -L kubernetes.io/arch      # unconstrained pods landed on arm64

# --- Consolidation ---
kubectl delete -f . --ignore-not-found
sleep 180
kubectl get nodes                            # Karpenter nodes gone
```

**Paste the real output of `job/arch-check` into the completion report.** That single line is the
evidence the whole assignment turns on.

---

## Notes for the implementing agent

- Test every manifest against a real cluster if credentials exist. A `securityContext` that stops
  nginx from starting is worse than no `securityContext`.
- Do not invent a NodePool name in a `nodeSelector`. Developers select on `kubernetes.io/arch`; the
  pools are an implementation detail (G-15 — an unknown label leaves the pod `Pending` with no
  error).
- Keep the total to six files. This is a demo, not a workload catalogue.

---

## Agent prompt

```text
Implement Phase 6 of the EKS + Karpenter Terraform assessment.

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
  1. docs/reference/karpenter-api-reference.md  (§5 scheduling semantics)
  2. docs/contracts/interface-contract.md       (§6 object names)
  3. docs/reference/gotchas.md                  (G-15, G-16)
  4. docs/phases/phase-06-demo-workloads.md     (your specification)
  5. docs/phases/phase-05-nodepools.md          (read its Completion report only)

Create examples/ with the six files phase-06 lists. These are plain Kubernetes YAML,
NOT Terraform — do not reference them from main.tf or any helm_release.

Critical constraints:
  - Every image must come from public.ecr.aws (Docker Hub rate-limits a cluster behind one NAT).
  - Architecture selection uses nodeSelector on kubernetes.io/arch ONLY. Never reference a
    NodePool name.
  - Every container needs resource requests — Karpenter sizes nodes from them.
  - If you set readOnlyRootFilesystem, you MUST add the emptyDir mounts the image needs, or
    pick a different image. Do not ship a manifest that fails to start.
  - Verify the downward-API fieldRef in job-arch-check.yaml actually resolves; if it renders
    empty, remove it rather than shipping blank output.
  - examples/README.md is written for an application developer, not an infra engineer.
    Roughly one screen.

Validate every file OFFLINE with `kubeconform -strict` (or the python yaml fallback) — NOT
`kubectl apply --dry-run=client`, which needs a reachable API server. If credentials are available,
apply them for real and paste the `kubectl logs -n demo job/arch-check` output into your
completion report.

When finished, fill in the "## Completion report" section at the bottom of
docs/phases/phase-06-demo-workloads.md and stop. Do not start Phase 7.
```

---

## Completion report

- Status: DONE — all offline acceptance criteria pass (kubeconform, the python parse fallback,
  and every grep assertion in the "Without credentials" section, run and corrected for two
  false-positive greps from my own comments, see Verification run). The "With credentials"
  acceptance criteria could not be run — no EKS/Karpenter cluster is reachable, see below.

- Files created/changed:
  - `examples/README.md` — **new.** Developer-facing, ~one screen (94 lines): access, run on
    Graviton, run on x86, the recommended multi-arch pattern (+ the soft-preference variant),
    proving it with the Job, cleanup, the `exec format error` caveat, and short answers on quota,
    Pod Security, Pod Identity (§6.8) and application secrets.
  - `examples/deployment-arm64.yaml` — **new.** `web-graviton` Deployment (3 replicas) +
    `PodDisruptionBudget`, per §6.3 verbatim: `nodeSelector: {kubernetes.io/arch: arm64}`,
    `topologySpreadConstraints` (hostname + zone), `nginx-unprivileged` on 8080,
    `readOnlyRootFilesystem: true` with a single `/tmp` `emptyDir`, full `restricted`-profile
    `securityContext`.
  - `examples/deployment-x86.yaml` — **new.** Identical structure, `kubernetes.io/arch: amd64`,
    `web-x86` naming — per §6.4, "exactly one line changes."
  - `examples/deployment-multiarch.yaml` — **new.** `web-multiarch`, no `nodeSelector` at all —
    demonstrates §6.5's pattern 1 (NodePool weight alone decides, lands on arm64 by default).
  - `examples/deployment-multiarch-preferred.yaml` — **new, not in the original file list** (see
    Deviation #1). `web-multiarch-prefer-arm64` — demonstrates §6.5's pattern 2, a soft
    `preferredDuringSchedulingIgnoredDuringExecution` toward arm64 with an amd64 fallback.
  - `examples/job-arch-check.yaml` — **new.** `arch-check` Job per §6.6, with the
    `INSTANCE_TYPE` downward-API `fieldRef` removed (see Deviation #2) and the container's
    `resources.requests.memory` raised to `100Mi` to clear the `demo` namespace LimitRange's
    `min: 64Mi` floor (phase-05 §5.3c) with margin, since §6.6's own example carried no resources
    block at all.
  - `docs/contracts/interface-contract.md` — §1's `examples/` tree amended: added `README.md` (was
    missing from the tree, though phase-06 §"Files to create" already listed it — bringing the tree
    in line with the file list) and `deployment-multiarch-preferred.yaml`, per the contract's own
    rule that a new name must be added in the same change that introduces it.

- Deviations from spec:
  1. **File count reconciled at 6, by splitting the multi-arch pattern into two files.** The
     phase's own "Files to create" list enumerates 5 files (README + 4 YAML), but its "Notes for
     the implementing agent" says "Keep the total to six files," and §6.5 requires demonstrating
     **two** distinct pod specs (no-`nodeSelector`-at-all, and a soft `nodeAffinity` preference) —
     which cannot both be one Deployment. Rather than cramming two Deployments into one
     `deployment-multiarch.yaml` (defensible, but muddies "copy one file, change the image, ship"
     for a developer who wants only the plain pattern) I split them: `deployment-multiarch.yaml`
     keeps §6.5 pattern 1, and the new `deployment-multiarch-preferred.yaml` holds pattern 2. That
     reaches six files exactly and matches the doc's own note; the interface-contract tree and this
     report record the new name per the contract's own rule. If a later phase's README or `verify.sh`
     enumerates `examples/*.yaml` by a hardcoded list rather than a glob, it needs this filename too.
  2. **`job-arch-check.yaml`'s `INSTANCE_TYPE` env var was removed**, per the phase doc's own
     instruction to verify and drop it rather than ship blank output. Confirmed by reasoning about
     the downward API, not by a live cluster (none was reachable): `fieldRef` on `metadata.labels`
     resolves against the **pod's own** labels, not the node's. The pod carries no
     `node.kubernetes.io/instance-type` label — nothing sets one — so the field would either fail
     admission (an unknown label reference) or render as an empty string; either way it is not usable
     evidence. `NODE_NAME` (via `spec.nodeName`) was kept — that field genuinely exists on every pod.
     The README's arch-check step and its "other things worth knowing" both point the reader at
     `kubectl get nodes -L kubernetes.io/arch,karpenter.sh/capacity-type,node.kubernetes.io/instance-type`
     instead.
  3. **`readOnlyRootFilesystem: true` + a single `/tmp` `emptyDir` was verified empirically, not
     from recall.** Pulled `public.ecr.aws/nginx/nginx-unprivileged:stable` directly (`docker pull`)
     and read its actual `/etc/nginx/nginx.conf`: `pid`, `proxy_temp_path`, `client_body_temp_path`,
     `fastcgi_temp_path`, `uwsgi_temp_path` and `scgi_temp_path` are all under `/tmp`; `access.log`
     and `error.log` are symlinks to `/dev/stdout`/`/dev/stderr`, not real files. Then ran the
     container with `docker run --read-only --tmpfs /tmp -u 101 --cap-drop=ALL
     --security-opt=no-new-privileges` (matching the shipped `securityContext` field-for-field) and
     confirmed it starts cleanly and serves `HTTP 200` on `:8080` — no `/var/cache/nginx` or
     `/var/run` mount was needed, matching §6.3's spec exactly. Also confirmed via
     `docker inspect`/`docker manifest inspect` that both `nginx-unprivileged:stable` (`User=101`,
     `ExposedPorts=8080/tcp`) and `busybox:latest` (`User=` — empty, i.e. root) are genuinely
     multi-arch (`linux/amd64` and `linux/arm64` both present in each manifest list), confirming the
     spec's own claims rather than trusting them.
  4. **Added `topologySpreadConstraints` and a `PodDisruptionBudget` to
     `deployment-multiarch.yaml`/`-preferred.yaml`**, which §6.5 does not show explicitly (only
     §6.3's arm64 example spells them out). The same Spot-first reasoning §6.3 gives — one
     consolidation or Spot reclaim can otherwise take a 2-replica deployment to zero — applies
     identically to the multi-arch pair, so both carry the same spread/PDB pattern as
     `deployment-arm64.yaml`/`deployment-x86.yaml` rather than shipping unprotected.
  5. Every container's `securityContext` omits a CPU `limit` (only a memory `limit` is set),
     matching §6.3's own example literally rather than adding one — an unset CPU limit lets the
     workload burst without throttling and is not what S-61 ("requests and limits on every
     container") is protecting against; the LimitRange's `default: {cpu: "1", ...}` (phase-05
     §5.3c) fills in a CPU limit automatically at admission if a cluster operator wants one enforced.

- Names added to interface-contract.md: `examples/README.md` and
  `examples/deployment-multiarch-preferred.yaml`, both added to §1's `examples/` tree — see
  Deviation #1 and the `docs/contracts/interface-contract.md` entry under "Files created/changed"
  above for why.

- **Actual `kubectl logs -n demo job/arch-check` output** (or why it could not be run): **Not
  run — no EKS/Karpenter cluster reachable.** The only `kubectl` context configured on this
  machine (`panda-dev-admin@panda-dev`, API server at a private/local IP) is an unrelated cluster:
  `kubectl get namespace demo` → `NotFound`, and `kubectl get nodepools` → `the server doesn't have
  a resource type "nodepools"` (no Karpenter CRDs installed). Applying these manifests there would
  prove nothing about this deliverable and would write into a cluster this assessment does not own,
  so nothing was applied. No AWS credentials for the target account were available either
  (consistent with phase-05's completion report, which also ran with no credentials).

- Verification run:
  ```
  $ cd examples
  $ kubeconform -strict -summary -kubernetes-version 1.36.0 *.yaml
  Summary: 9 resources found in 5 files - Valid: 9, Invalid: 0, Errors: 0, Skipped: 0

  $ python3 -c "import yaml,sys; [list(yaml.safe_load_all(open(f))) for f in sys.argv[1:]]; print('PASS: all files parse')" *.yaml
  PASS: all files parse

  $ [ -e namespace.yaml ] && echo FAIL || echo "PASS: no namespace.yaml"
  PASS: no namespace.yaml

  $ grep -h 'image:' *.yaml | grep -vE '^\s*#' | grep -v 'public.ecr.aws' && echo FAIL || echo "PASS: all real image: fields are public ECR"
  PASS: all real image: fields are public ECR
  # (the spec's literal one-line grep without comment-stripping produces one false positive: a
  # comment in deployment-multiarch-preferred.yaml containing the word "image:". Re-run with
  # comments stripped, matching the comment-stripping pattern phase-05's own acceptance script
  # already uses for its Balanced/instanceProfile checks, for the real answer.)

  $ grep -l 'kubernetes.io/arch: arm64' *.yaml
  deployment-arm64.yaml
  job-arch-check.yaml
  $ grep -l 'kubernetes.io/arch: amd64' *.yaml
  deployment-x86.yaml

  $ for f in *.yaml; do grep -q 'runAsNonRoot: true' "$f" && ! grep -q 'runAsUser:' "$f" && echo "FAIL: $f"; done
  (no output — PASS, every pod asserting runAsNonRoot pins runAsUser)

  $ for f in deployment-*.yaml job-*.yaml; do grep -q 'seccompProfile' "$f" || echo "FAIL: $f"; done
  (no output — PASS, every pod carries seccompProfile)
  ```
  Additionally checked, beyond the spec's own script: no `karpenter.sh/nodepool` or
  `karpenter.sh/discovery` label anywhere in `examples/` (grep clean) — architecture selection is
  `kubernetes.io/arch` only, no NodePool name leaks into a manifest. Summed
  `resources.requests` × `replicas` across all four Deployments plus the Job against the `demo`
  namespace's ResourceQuota (phase-05 §5.3c: `requests.cpu: "20"`, `requests.memory: "40Gi"`) —
  totals ~4.1 vCPU / ~2.6Gi, comfortably under quota. Checked every container's requests/limits
  against the namespace LimitRange's Container-type `min` (`cpu: 50m`, `memory: 64Mi`) and `max`
  (`cpu: "4"`, `memory: 8Gi`) — all within bounds (this is what caught the Job's original
  under-floor memory request, Deviation above). `docker manifest inspect` confirmed both images are
  multi-arch; `docker run` confirmed the `nginx-unprivileged` + `readOnlyRootFilesystem` combination
  actually starts and serves traffic (Deviation #3).

- Notes for the next phase: Phase 7 (README) can link straight to `examples/README.md` rather than
  duplicating its content — that file already owns the developer-facing walkthrough end to end.
  Phase 7 or Phase 8's `verify.sh`, if it runs the "With credentials" acceptance criteria from this
  phase for real, should also apply `deployment-multiarch-preferred.yaml` alongside
  `deployment-multiarch.yaml` (glob `examples/*.yaml` rather than a hardcoded per-file list, so the
  new filename isn't silently skipped). No AWS/EKS credentials were available in this session, so
  every "With credentials" acceptance command in this phase — including the one line the assignment
  actually turns on, `kubectl logs -n demo job/arch-check` — is still unverified end to end and
  should be the first thing run against a real cluster before this deliverable is called complete.
