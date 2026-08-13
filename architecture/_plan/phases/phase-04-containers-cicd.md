# Phase 04 — Containerization & CI/CD

> Answers the final third of **assessment area 3** and requirements **R9, R10, R11, R23**.
> Read [`../AGENT-PROTOCOL.md`](../AGENT-PROTOCOL.md), [`../brief.md`](../brief.md),
> [`../contract.md`](../contract.md), [`../decision-register.md`](../decision-register.md),
> [`../well-architected.md`](../well-architected.md), and [`../style-guide.md`](../style-guide.md)
> first.

---

## Goal

The brief asks for a containerization strategy "including image building, registry, and deployment
processes" — **three named things**. Answer all three, each under its own heading, and then connect
them into one pipeline that runs from `git push` to a canary in production. The client is "aiming for
CI/CD", so the pipeline is not an appendix; it is the answer.

---

## Dependencies

Phase 00 must be `done`. Read `drafts/03-compute-eks.md` if it exists so cluster and namespace
references match.

## Inputs

| File | Use it for |
|---|---|
| `_plan/decision-register.md` | ADR template and your reserved ADR block |
| `_plan/well-architected.md` | Pillar tagging convention and what each pillar demands |
| `_plan/contract.md` **§7** | Image names, tagging, base images, registry policy, supply chain, promotion flow — **copy exactly** |
| `_plan/contract.md` §1, §4, §6 | CI/CD decisions, the Shared Services account, cluster names |
| `_plan/contract.md` §9 | Pipeline security controls |
| `_plan/rubric.md` §3 probes 1, 4, 10 | Depth probes this section must survive |

## Files you own

- `_plan/drafts/04-containers-cicd.md` — create
- `_plan/STATE.md` — update
- `_plan/contract.md` §12 — append only if you invent a name

## Word budget

**~1 500 words** (±20%) for the body, excluding tables and snippets, plus **4 ADRs**
(ADR-015 – ADR-018).

## Two requirements that apply to every section you write

1. **Pillar line.** Every `##` section closes its opening paragraph with
   `> **Well-Architected pillars.** …` carrying 2–4 pillars. See `well-architected.md` §2.
2. **Justification.** Inline, every decision follows decision → why → what it beat → what it costs.
   The significant ones are recorded again as ADRs at the end of the draft. See
   `decision-register.md`.

## Write this section as a DevSecOps engineer

The pipeline is where security either becomes automatic or stays aspirational. Every gate you
describe should be a *mechanism that refuses*, not a step someone is asked to remember: a scan that
fails the build, an admission controller that rejects an unsigned image, a trust policy that will
only issue credentials to one branch of one repository. Where a control could be either a policy
document or a piece of automation, choose the automation and say why. That framing — shift-left,
enforced by machines — is what the client's "strong security measures" actually looks like in a
delivery pipeline.

---

## Content specification

### `## What gets containerized — and what does not` (~150 words)

The most valuable paragraph in this section, because it is where most designs are lazy.

- The **Flask API** and the **background worker** are containers on EKS.
- The **React SPA is not a container.** It is a build artifact: `npm run build` produces static files
  that are uploaded to the S3 bucket `innovate-<env>-web-use1` and served by CloudFront. Give the
  reasons: static assets served from a pod mean paying for compute and cross-region latency to serve
  bytes that never change; CloudFront serves them from an edge location with no origin hit; there is
  no container to patch, scale, or secure; and rollback is a re-upload plus a cache invalidation. A
  design that runs `nginx` in Kubernetes to serve a React bundle is a design that has not thought
  about it.
- Note the one thing this costs: the SPA and the API deploy through different mechanisms, so the
  pipeline has two paths. Say so, then show both.

### `## Image building` (~300 words + snippet)

- **Multi-stage Dockerfile.** Builder stage installs build dependencies and compiles wheels; the
  runtime stage copies only the virtual environment and application code. Give the concrete outcome:
  compilers and package caches never ship to production, so the image is smaller and its
  vulnerability surface is a fraction of a single-stage build.
- **Base image**: `python:3.12-slim` for the builder, a distroless or slim runtime for the final
  stage. Trade-off in one sentence: distroless has almost no attack surface and no shell, which also
  means no shell for debugging — the answer is ephemeral debug containers (`kubectl debug`), not a
  fatter image.
- **Hardening**: non-root user (UID 10001), read-only root filesystem with an `emptyDir` for `/tmp`,
  no package manager at runtime, dropped Linux capabilities, `.dockerignore` so secrets and `.git`
  never enter the build context, pinned base image **by digest** rather than by tag.
- **Multi-architecture.** `docker buildx` produces `linux/arm64` and `linux/amd64` and publishes a
  single manifest list, so the same tag resolves correctly on a Graviton node or an x86 node. This is
  what makes the Graviton-first NodePool strategy in Phase 03 safe.
- **Reproducibility and provenance**: layer caching in the registry, a build that depends only on
  committed files, an SBOM generated per build (Syft/CycloneDX) and stored in S3, and build
  provenance attestation.
- **Tagging**, stated as a rule with its reason: the tag is the **40-character git SHA**; tags are
  immutable in the registry; `latest` is never deployed. An immutable tag means the question "what is
  running in production?" has exactly one answer, and a rollback is a known-good digest rather than a
  rebuild.
- One illustrative multi-stage Dockerfile snippet, **≤ 25 lines**, showing the builder/runtime split,
  the non-root user, and the healthcheck. Do not write a full production Dockerfile.

### `## Container registry` (~250 words + table)

- **Amazon ECR**, private repositories, in the `innovate-shared-services` account. Repository paths
  from `contract.md` §7.
- **Why one central registry rather than one per environment** — this is rubric probe 1 and must be
  answered explicitly. An image built once is scanned once, signed once, and promoted by **digest**
  into dev, staging, and production. If each environment had its own registry the image would be
  rebuilt per environment, and a rebuild is a different artifact: different base-image contents,
  different transitive dependencies, and therefore a production deployment that was never actually
  tested. Cross-account pull is granted by an ECR repository policy that allows the three workload
  accounts' node and pod roles to pull — read-only, no push.
- **Why ECR rather than Docker Hub or GHCR**: IAM-native authentication (no registry credentials in
  the cluster), private by default, in-region so pulls traverse the ECR VPC endpoint rather than the
  NAT Gateway, native Amazon Inspector scanning, and cross-region replication for DR.
- **Repository configuration table** — Setting | Value | Why. Cover: tag immutability on, scan on
  push (Inspector enhanced), KMS encryption, lifecycle policy (keep the last 30 tagged images, expire
  untagged after 7 days), cross-region replication to `us-west-2`, and repository policy scoped to
  the workload accounts.
- **Supply chain**: SBOM per image; signing with **cosign** using keyless GitHub OIDC signing; a
  **Kyverno** admission policy in every cluster that refuses to admit any pod whose image is not
  signed by the expected identity and does not come from the Innovate Inc. ECR registry. State the
  consequence plainly: a developer cannot run `nginx:latest` from Docker Hub in production even by
  accident.

### `## The CI pipeline` (~250 words + table)

A stage-by-stage table — Stage | Runs on | Gate | Fails the build when — covering at minimum:

| Stage | What it does |
|---|---|
| Pull request | Lint (`ruff`, `eslint`), unit tests with coverage threshold, `gitleaks` secret scan, Semgrep/CodeQL SAST, `pip-audit`/Dependabot dependency audit, Checkov/tfsec on Terraform |
| Build | `docker buildx` multi-arch build, SBOM generation |
| Scan | Trivy against the built image; **fail on High/Critical with a fixed version available** |
| Sign & push | cosign keyless signature, push to ECR by digest |
| Deploy dev | GitOps commit updates the dev overlay digest; Argo CD syncs automatically |
| Verify dev | Smoke and integration tests against the dev environment |
| Promote staging | Automated PR bumping the staging overlay to the same digest |
| Verify staging | Integration + load test against production-shaped infrastructure |
| Promote production | **Manual approval**, then a GitOps commit to the production overlay |
| Progressive rollout | Argo Rollouts canary; automatic abort on SLO breach |

Then the identity model, which is rubric probe 4: GitHub Actions authenticates to AWS with **OIDC**,
assuming a role in `innovate-shared-services` whose trust policy is scoped to the specific repository
**and branch or GitHub environment**. No long-lived access keys exist anywhere. The CI role can push
to ECR and commit to the GitOps repository — **it cannot deploy to a cluster**, because CD is pull-
based. State why that matters: a stolen CI token can push an image, but an unsigned or unapproved
image is rejected at admission and never reaches a namespace.

### `## Deployment — GitOps with Argo CD` (~250 words)

- **Pull-based CD.** Argo CD runs *inside* each cluster and reconciles the cluster toward a Git
  repository. Consequence, stated plainly: no external system holds cluster credentials, the
  Kubernetes API does not need to be reachable from CI, and drift is corrected automatically rather
  than discovered during an incident.
- **Repository layout**: an application repository (source + Dockerfile) and a separate GitOps
  repository (Kustomize base plus `dev`/`staging`/`prod` overlays). Promotion is a commit changing an
  image digest in one overlay. Every change to production is a reviewed, signed, revertible commit —
  which is also the audit trail a SOC 2 auditor asks for.
- **Progressive delivery** with Argo Rollouts: canary at 10% → analysis against Prometheus metrics
  (error rate, p95 latency) → 50% → 100%, with automatic rollback if the analysis fails. Explain how
  it works with the ALB: the load balancer controller weights two target groups.
- **Database migrations**: Alembic run as a Kubernetes `Job` in an Argo CD PreSync hook, using the
  **expand/contract** pattern so every migration is backward-compatible with the previous application
  version. Say why this is non-negotiable with canary deploys: two versions of the application run
  simultaneously against one schema, so a destructive migration breaks the version that is still
  serving traffic. Cross-reference Phase 05.
- **Rollback**: `git revert` the GitOps commit; Argo CD reconciles back to the previous digest,
  typically in under a minute. For the SPA, re-upload the previous build and invalidate the
  CloudFront cache.
- **Environment promotion table** — Environment | Trigger | Approval | Rollout strategy.

### `## Frontend deployment path` (~100 words)

The second pipeline path, briefly: CI builds the React bundle with content-hashed filenames, syncs it
to `innovate-<env>-web-use1`, and creates a CloudFront invalidation limited to `index.html` (hashed
assets are immutable and cached for a year; only the entry point needs invalidating). The bucket is
private and reachable only through CloudFront's origin access control. Deploys are atomic enough that
a rollback is a re-sync of the previous build.

---

## Decision Records — ADR-015 to ADR-018

End the draft with `## Decision Records` containing 4 ADRs from your reserved block, using the
exact template in `decision-register.md`. They must cover:

- **ADR-015 — Serving the React SPA from S3 and CloudFront rather than from a container.** Against an
  nginx pod in the cluster, which is what most teams do by default. The clearest presentation-tier
  decision in the document.
- **ADR-016 — A single central registry with promotion by immutable digest.** Against a registry per
  environment, against a third-party registry, and against rebuilding per environment. This is the
  record that makes the "what was tested is what ships" guarantee concrete.
- **ADR-017 — GitOps pull-based delivery with Argo CD rather than push-based CD from the pipeline.**
  The alternative is simpler to set up and very widely used, so argue it fairly. The deciding factor
  is that CI never holds cluster credentials.
- **ADR-018 — Image signing verified at admission.** Against scanning alone. Name what it costs:
  another moving part, and a failure mode where a signing outage blocks deployment.

The plain-language field on the GitOps ADR is worth care: a founder will not know what "pull-based"
means. Try framing it as "the cluster fetches its own instructions from a version-controlled list,
rather than the build system being given the keys to change the cluster directly — so if the build
system is ever compromised, the attacker still cannot deploy anything."

---

## Acceptance criteria

- [ ] File is `_plan/drafts/04-containers-cicd.md`, 1 200–1 800 words excluding tables, snippets,
      ADRs.
- [ ] **Image building**, **registry**, and **deployment** each have their own top-level heading — a
      reviewer scanning headings must see all three named in the brief.
- [ ] Every `##` section closes its opening paragraph with a pillar line carrying 2–4 pillars.
- [ ] Every pipeline gate is described as a mechanism that refuses, not a step someone performs.
- [ ] `## Decision Records` present with 4 ADRs from ADR-015 – ADR-018, full template, no fields
      missing; each has a fairly-argued rejected alternative, a plain-language field a non-engineer
      can read, a real *Accepts* downside, and an observable *Revisit when* trigger.
- [ ] The SPA is explicitly *not* containerized, with reasons.
- [ ] Rubric probe 1 answered: one central registry, promotion by immutable digest, cross-account
      pull policy, and why rebuilding per environment breaks the test guarantee.
- [ ] Rubric probe 4 answered: OIDC short-lived roles scoped to repo/branch, pull-based CD so CI
      never holds cluster credentials, manual approval gate, signed images verified at admission.
- [ ] Rubric probe 10 answered: the full `git push` → running pod path is traceable from the pipeline
      table.
- [ ] Multi-architecture build is covered and tied back to the Graviton NodePool strategy.
- [ ] Image tagging is the git SHA, tags are immutable, `latest` is never deployed.
- [ ] Supply-chain controls present: SBOM, cosign signing, Kyverno admission verification.
- [ ] Database migrations addressed with the expand/contract pattern and a PreSync hook.
- [ ] Rollback is described for both the API and the SPA.
- [ ] Image paths, repository names, and base images match `contract.md` §7 exactly.
- [ ] At most **two** code snippets, each ≤ 25 lines, each with a language tag.
- [ ] No cluster/node/scaling content — that is Phase 03.
- [ ] No `TODO`/`TBD`; no banned words; no emoji.
- [ ] `STATE.md` updated.

## Common failure modes

| Failure | Avoid it by |
|---|---|
| Serving the React SPA from a container | S3 + CloudFront, with the reasoning spelled out. |
| A pipeline diagram with no security gates | Every stage names its gate. |
| Push-based CD with cluster credentials in CI | GitOps, pull-based. This is the differentiating choice — argue it. |
| Mutable tags, or deploying `latest` | Git SHA, immutable, promoted by digest. |
| Ignoring database migrations entirely | Canary + schema change is where real deployments break. |
| Writing a complete production Dockerfile | Two snippets maximum, illustrative only. |
| Forgetting that "deployment processes" is a named sub-requirement | It gets its own heading. |

---

## Agent prompt

```text
You are executing Phase 04 of the Innovate Inc. architecture design plan: Containerization & CI/CD.

Working directory boundary: architecture/ ONLY. Never read or write
terraform/, .claude/, or anything above architecture/. terraform/ belongs to a
different assignment that another agent may be editing right now.

Read in full, in order:
  architecture/_plan/AGENT-PROTOCOL.md
  architecture/_plan/brief.md
  architecture/_plan/contract.md      (§7 is your primary source — copy names exactly)
  architecture/_plan/decision-register.md
  architecture/_plan/well-architected.md
  architecture/_plan/style-guide.md
  architecture/_plan/rubric.md
  architecture/_plan/drafts/00-scope.md
  architecture/_plan/phases/phase-04-containers-cicd.md

Read architecture/_plan/drafts/03-compute-eks.md only if it exists.
Do not read any other file. No repository-wide searches. No aws/kubectl/terraform/docker/helm.
No web browsing.

Write architecture/_plan/drafts/04-containers-cicd.md following the content
specification exactly. Image building, registry, and deployment must each get their own top-level
heading — the brief names all three. Do NOT write about cluster topology, node groups, or
End the draft with a ## Decision Records section containing ADR-015 through ADR-018, using the exact
template in decision-register.md. Every ADR needs: an options table with at least one genuinely
reasonable rejected alternative argued fairly; a "Why this is the right choice for Innovate Inc."
field written in plain language for a non-engineer founder; an Accepts list naming a real
downside; and a Revisit when field naming an observable trigger.

Close every ## section's opening paragraph with a > **Well-Architected pillars.** line carrying
two to four pillars.

autoscaling — Phase 03 owns those. Then verify every acceptance criterion line by line, fix what
fails, update STATE.md, report, and STOP. Do not begin Phase 05.
```
