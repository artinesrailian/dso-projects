## What gets containerized — and what does not

The **application tier** — the Python/Flask REST API and background workers, the same tier described
in §3 Compute Platform — ships as containers on Amazon Elastic Kubernetes Service (EKS). The
**presentation tier** does not. This is the section where most designs default to the familiar
answer instead of the right one, so it is worth stating first.

> **Well-Architected pillars.** Cost Optimization · Performance Efficiency · Operational Excellence

The React single-page application (SPA) is not a container; it is a build artifact. `npm run build`
produces a set of static files, uploaded to the S3 bucket `innovate-<env>-web-use1` and served by
Amazon CloudFront, exactly as fixed in §0.2 Architecture overview. Running that same bundle behind
`nginx` in a pod means paying for compute and cross-region latency to serve bytes that never change
between requests, plus a container with an operating system and a web server to patch and scan for
no benefit; a rollback means a rolling deployment instead of a re-upload and a cache invalidation.
CloudFront already solves this from an edge location with no origin server involved. A design that
runs `nginx` in Kubernetes to serve a React bundle has not thought about what a container buys
there, because the answer is nothing.

This split costs one real thing: the API and the SPA deploy through two different mechanisms, not
one. The CI pipeline covers the container path; the frontend deployment path covers the static
path. Both start at the same `git push`.

---

## Image building

Every container Innovate Inc. runs — the Flask API and the Celery-style background worker — is
built from the same multi-stage Dockerfile pattern and the same base images.

> **Well-Architected pillars.** Security · Operational Excellence · Cost Optimization

**Multi-stage build.** A builder stage installs compilers and compiles Python wheels; a separate
runtime stage copies in only the resulting virtual environment and application code. Compilers and
build-time dependencies never reach the production image, so it is smaller and its vulnerability
surface is a fraction of a single-stage build's — every package present was needed at runtime, not
merely to build it.

**Base images.** The builder stage runs `python:3.12-slim`; the runtime stage runs a distroless or
slim runtime image. Distroless has almost no attack surface: no shell, no package manager, nothing
an attacker can use beyond the application itself. Its cost is that there is no shell to debug with
— the answer is `kubectl debug`, attaching an ephemeral debug container only when a human
deliberately asks for one, not a permanently fatter image kept as a standing habit.

**Hardening**, applied to every image: a non-root user (UID `10001`), a read-only root filesystem
with an `emptyDir` volume at `/tmp` for anything that must write, no package manager at runtime,
Linux capabilities dropped to the minimum needed, a `.dockerignore` so `.git` history and secrets
never enter the build context, and the base image pinned **by digest** rather than a mutable tag,
so a base-image update cannot silently change what a build produces.

**Multi-architecture.** `docker buildx` builds both `linux/arm64` and `linux/amd64` from the same
Dockerfile and publishes them as a single manifest list under one tag, so the image resolves
correctly whether Karpenter schedules the pod onto a Graviton node or an x86 node (§3.3 Node
strategy) — what makes the Graviton-first NodePool strategy safe. Without it, an `arm64`-only image
fails to start the moment it lands on the wrong architecture.

**Reproducibility and provenance.** A build depends only on files already committed to the
repository, with no ambient state or manual step. Every build produces a software bill of materials
(SBOM) with Syft in CycloneDX format, stored in S3, plus a build-provenance attestation, so a
security review can answer "what is in this image" without re-running the build.

**Tagging.** The image tag is the **40-character git SHA of the commit it was built from**, immutable
once pushed; `latest` is never deployed, anywhere. An immutable, commit-derived tag means "what is
running in production right now" has exactly one answer, and a rollback is a known-good digest that
already exists, not a new build that might not reproduce the old one.

```dockerfile
FROM python:3.12-slim AS builder
WORKDIR /build
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

FROM gcr.io/distroless/python3
WORKDIR /app
COPY --from=builder /install /usr/local
COPY . .
USER 10001
EXPOSE 8080
HEALTHCHECK CMD ["python3", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:8080/healthz')"]
ENTRYPOINT ["gunicorn", "--bind=0.0.0.0:8080", "app:app"]
```

---

## Container registry

We store every image Innovate Inc. builds — API, worker, and any future service — in exactly one
place: **Amazon Elastic Container Registry (ECR)**, in private repositories inside the
`innovate-shared-services` account, at `<shared-acct>.dkr.ecr.us-east-1.amazonaws.com/innovate/api`
and `.../innovate/worker`, each tagged with the git SHA described above.

> **Well-Architected pillars.** Security · Operational Excellence · Reliability

**Why one central registry rather than one per environment.** This is the question a reviewer asks
directly, so the answer is explicit: an image is built once, scanned once, signed once, and then
**promoted by digest** — the same immutable artifact, referenced by its cryptographic hash — into
dev, then staging, then production. A registry per environment means rebuilding the image for each
one, and a rebuild is not the same artifact even from identical source: base-image layers may
have been repulled and transitive dependencies may have resolved to a different patch version, so
the build that passed staging's tests is, strictly, not the build reaching production. One registry
with digest promotion means what was tested is what ships. Cross-account access runs the other
direction: an ECR repository policy lets the node and pod roles in `innovate-dev`,
`innovate-staging`, and `innovate-prod` **pull only** — none of the three workload accounts can push.

**Why Amazon ECR rather than Docker Hub or GitHub Container Registry (GHCR).** ECR authenticates
through AWS Identity and Access Management (IAM) directly, so no registry credential is stored in
the cluster; it is private by default; pulls traverse the `ecr.api`/`ecr.dkr` Virtual Private Cloud
(VPC) interface endpoints from §2 Network Design rather than the NAT Gateway; it scans natively with
Amazon Inspector; and it replicates cross-region for disaster recovery. A third-party registry adds
an external dependency and a credential to rotate for no offsetting benefit.

| Setting | Value | Why |
|---|---|---|
| Tag immutability | On | A pushed tag can never be overwritten — the "what is running" question stays answerable |
| Scan on push | Amazon Inspector, enhanced scanning | Every image is scanned the moment it exists, not on a schedule |
| Encryption | AWS Key Management Service (KMS), customer-managed key | Consistent with the customer-managed-key posture set in §5 Security and Data Protection |
| Lifecycle policy | Keep the last 30 tagged images; expire untagged images after 7 days | Bounds registry growth without deleting anything still in use |
| Cross-region replication | To `us-west-2` | Images are available for the disaster-recovery region from §4.6 without a rebuild during a failover |
| Repository policy | Pull-only, scoped to `innovate-dev`, `innovate-staging`, `innovate-prod` node and pod roles | No workload account can push; only the pipeline in `innovate-shared-services` can |

**Supply chain.** Every pushed image carries an SBOM and a **cosign** signature, generated
keylessly against the GitHub Actions OpenID Connect (OIDC) identity that built it — no signing key
for anyone to steal or rotate. A **Kyverno** admission policy, enforced in every cluster, refuses to
admit any pod whose image is not signed by that expected identity and does not come from the
Innovate Inc. ECR registry. The consequence is concrete: a developer cannot run `nginx:latest`
pulled straight from Docker Hub in production, even by accident, because the cluster itself refuses
to start it.

---

## The CI pipeline

Every change to the API or worker begins with `git push` and passes through the same pipeline,
stage by stage, before a pod anywhere runs it.

> **Well-Architected pillars.** Security · Operational Excellence · Reliability

| Stage | What it does | Fails the build when |
|---|---|---|
| Pull request | Lint (`ruff`, `eslint`), unit tests with a coverage threshold, `gitleaks` secret scan, Semgrep/CodeQL static analysis (SAST), `pip-audit`/Dependabot dependency audit, Checkov/tfsec on Terraform changes | Any check fails; a human cannot merge around it |
| Build | `docker buildx` multi-architecture build, SBOM generation | The build itself fails, or the SBOM cannot be produced |
| Scan | Trivy against the built image | A High or Critical vulnerability exists with a fixed version already available |
| Sign & push | cosign keyless signature, push to ECR by digest | Signing fails, or the push is rejected |
| Deploy dev | A GitOps commit updates the dev overlay's image digest; Argo CD syncs automatically | The commit or the sync fails |
| Verify dev | Smoke and integration tests against the dev environment | Any test fails |
| Promote staging | An automated pull request bumps the staging overlay to the same digest | The pull request cannot be opened or merged |
| Verify staging | Integration tests against production-shaped infrastructure | Any test fails |
| Promote production | **Manual approval**, then a GitOps commit to the production overlay | No approval is given |
| Progressive rollout | Argo Rollouts canary release, described in §3.9 Deployment — CI/CD and GitOps below | The rollout's own analysis fails |

**Identity.** GitHub Actions authenticates to AWS with **OIDC**, assuming an IAM role in
`innovate-shared-services` whose trust policy is scoped to one specific repository **and** one
branch or GitHub environment — no other repository, and no other branch of this one, can assume it.
No long-lived AWS access key exists anywhere in this pipeline. That role can push images to ECR and
commit to the GitOps repository; it **cannot** deploy to any cluster, because deployment is
pull-based, covered next. That separation is what actually stops a stolen CI token from reaching
production: the token can, at worst, push an unsigned or unapproved image, and that image is
rejected at admission by the Kyverno policy above before it ever reaches a namespace — a scan and a
signature check protect the cluster even when the pipeline that fed them is compromised.

---

## Deployment — CI/CD and GitOps

Deployment is the third named piece of the containerization strategy, and the one where a wrong
default — a pipeline that pushes changes into the cluster — undoes the identity boundary above.

> **Well-Architected pillars.** Operational Excellence · Security · Reliability

**Pull-based continuous delivery.** We run **Argo CD** *inside* each EKS cluster, continuously
reconciling the cluster's actual state toward what a Git repository declares it should be, rather
than letting an external CI system push changes in. No system outside the cluster holds cluster
credentials, the Kubernetes API server never needs to be reachable from GitHub's runners, and
configuration drift is corrected automatically instead of discovered during an incident. This is why
ADR-017 chooses pull over push, even though push-based delivery is simpler to set up and common.

**Repository layout.** An application repository holds the source code and the Dockerfile; a
separate GitOps repository holds a Kustomize base plus `dev`, `staging`, and `prod` overlays. A
promotion, at every stage, is exactly one commit changing an image digest reference in one overlay —
a small, reviewable, revertible change with a full audit trail in `git log`, precisely the evidence
trail a SOC 2 auditor asks for.

**Progressive delivery.** **Argo Rollouts** replaces a plain rolling update for production traffic:
a new digest starts at 10% of traffic, an automated analysis step compares its error rate and p95
latency against Prometheus metrics from §6 Observability and Operations, and only on a pass does the
rollout advance to 50% then 100%, with automatic rollback the moment analysis fails. The AWS Load
Balancer Controller implements the split by weighting two target groups behind the same Application
Load Balancer (ALB).

**Database migrations.** Schema changes run as a Kubernetes `Job`, driven by Alembic, in an Argo CD
**PreSync hook**, using the **expand/contract** pattern from §0 Assumptions: add the new column or
table, deploy code that works with either shape, backfill, then drop the old shape in a later
release. This is a requirement of canary deployment, not a style preference — two versions of the
application serve traffic against the same database at once during a canary, so a non-backward-
compatible migration breaks whichever version is still running the old code. §4 Database covers the
storage side of the same pattern.

**Rollback.** For the API and worker, a rollback is `git revert` of the GitOps commit; Argo CD
reconciles the cluster back to the previous digest automatically, and Argo Rollouts aborts on its
own if a canary's own analysis already caught the problem. For the SPA, a rollback is a re-upload
of the previous build to S3 and a CloudFront invalidation of `index.html`.

| Environment | Trigger | Approval | Rollout strategy |
|---|---|---|---|
| Dev | Merge to `main` | None — automatic | Direct sync, no canary |
| Staging | Automated PR after dev verification passes | None — automatic merge on green checks | Direct sync, no canary |
| Production | Automated PR after staging verification passes | **Manual approval**, one reviewer minimum | Argo Rollouts canary: 10% → analysis → 50% → analysis → 100% |

---

## Frontend deployment path

The presentation tier's build and deploy is the second path this pipeline runs, shorter than the
container path because there is no cluster involved.

> **Well-Architected pillars.** Cost Optimization · Performance Efficiency · Operational Excellence

Continuous integration (CI) builds the React bundle with content-hashed filenames — so
`main.a1b2c3.js` changes name whenever its content changes — and syncs the built files to the S3
bucket `innovate-<env>-web-use1`. Content-hashed assets are cached at the edge for a long,
indefinite duration because they are immutable by construction; only `index.html`, which references
the current hashes, needs a short cache time and an explicit CloudFront invalidation on every
deploy. The bucket is private, reachable only through CloudFront's origin access control (OAC),
never directly from the internet. Because the sync and invalidation are close to atomic, a rollback
is a re-sync of the previous build's files followed by another invalidation — no rebuild required.

---

## Decision Records

The four decisions below carry the full argument for how Innovate Inc. builds, stores, and ships
its containers: why the presentation tier is not one of them, how one image becomes the same
artifact in three environments, why deployment pulls rather than pushes, and why a signature is
checked before a pod ever starts. Each stands on its own, with a plain-language justification a
non-technical reader can follow without the rest of this document.

> **Well-Architected pillars.** Security · Operational Excellence · Cost Optimization · Reliability

### ADR-015 — Serving the React SPA from S3 and CloudFront, Not a Container

| | |
|---|---|
| **Status** | Accepted |
| **Requirement** | R11, R22 |
| **Pillars** | Cost Optimization · Performance Efficiency · Sustainability · Operational Excellence |
| **Section** | §3 Compute Platform |

**Context.** Innovate Inc.'s frontend is a React single-page application compiling to static HTML,
JavaScript, and CSS with no server-side logic. The team is small, and every component it runs is one
it must patch and scale.

**Options considered.**

| Option | Strengths | Weaknesses | Verdict |
|---|---|---|---|
| `nginx` container on Amazon EKS, alongside the API | One deployment model for everything; familiar to a team already running Kubernetes | Pays for compute and a container operating system to serve files that never change per request; adds a container to patch and scan for zero functional benefit; rollback needs a rolling deployment | Rejected — the most common default, and the wrong one here |
| Amazon S3 static website hosting, no CloudFront | Simpler than adding a content delivery network (CDN); very cheap | Single-region latency for every visitor; no WAF integration at that layer; bucket must be public or use a less robust access pattern | Rejected — leaves performance and edge security on the table for negligible savings |
| Amazon S3 behind Amazon CloudFront, origin access control | Served from edge locations near each visitor; the bucket stays fully private; integrates with AWS WAF from §5; scales to any traffic level with no capacity planning | A second deployment mechanism, distinct from the container pipeline | **Chosen** |

**Decision.** The React SPA is built in CI and deployed as static files to the S3 bucket
`innovate-<env>-web-use1`, served through Amazon CloudFront with origin access control, never as a
container image.

**Why this is the right choice for Innovate Inc.** The part of the product a browser downloads first
— the website's look and feel — never changes based on who is asking, so there is no reason to pay
a computer to assemble it fresh per visitor. Amazon S3 stores the files; Amazon CloudFront copies
them to locations near each visitor, so someone abroad loads it as fast as someone next door.
Running this website on the same cluster as the API means maintaining a server that only hands out
files that never change, for no benefit to the user.

**Consequences.**
- *Gains:* Materially lower cost than serving from compute; global low-latency delivery with no
  capacity planning.
- *Accepts:* Two release processes to keep in step — an SPA deploy and an API deploy — not one.

**Cost impact.** Indicative — CloudFront and S3 are the cheapest line in the day-1 cost table
(§7 Cost Optimization); see the AWS Pricing Calculator for a real estimate.

**Revisit when.** The frontend needs server-side rendering or per-request personalization that
static hosting cannot provide.

### ADR-016 — A Single Central Registry with Promotion by Immutable Digest

| | |
|---|---|
| **Status** | Accepted |
| **Requirement** | R10, R23 |
| **Pillars** | Security · Reliability · Operational Excellence |
| **Section** | §3.8 Container registry |

**Context.** Innovate Inc. runs three workload accounts and expects an image to move from dev to
staging to production with confidence that what was tested is what ships. The team has no release
engineer to verify that by hand, so the guarantee comes from the mechanism, not a person.

**Options considered.**

| Option | Strengths | Weaknesses | Verdict |
|---|---|---|---|
| Image rebuilt fresh from source for each environment, regardless of registry topology | Simplest mental model; no dependency on a prior build artifact | A rebuild is not the same artifact — base-image layers, transitive dependencies, and timestamps can all differ between builds from identical source, so "tested in staging" no longer strictly describes what runs in production | Rejected — quietly breaks the guarantee promotion exists to provide |
| One Amazon ECR repository per environment, same digest replicated into each (no rebuild) | Keeps each environment's registry contents scoped to that environment; ECR's own cross-region replication feature already does this kind of copy | Three sets of lifecycle policies and repository configuration to keep in sync, solving nothing that repository-scoped IAM policy does not already solve on a single registry | Rejected — adds operational surface for no guarantee a shared registry with scoped pull policies does not already provide |
| A third-party registry (Docker Hub, GHCR) shared across environments | Familiar to many teams; some free tiers | Adds an external dependency and a credential to manage outside AWS IAM; no native in-VPC pull path; weaker native scanning integration than ECR | Rejected — no advantage over ECR for this team, several disadvantages |
| One central Amazon ECR registry in `innovate-shared-services`, images promoted by digest | Built once, scanned once, signed once; the exact same artifact, verified by cryptographic hash, moves through every environment; cross-account pull policy keeps write access in one account | Every workload account depends on `innovate-shared-services` being available to pull new images | **Chosen** |

**Decision.** We build and store every container image once, in Amazon ECR repositories in
`innovate-shared-services`, and promote it between dev, staging, and production by image digest —
never rebuilding per environment.

**Why this is the right choice for Innovate Inc.** A digest is a fingerprint of the exact bytes in a
container image — one changed byte changes the fingerprint. Promoting by digest means production
runs the literal file that passed every test in staging, not a rebuilt copy of the same source.
Rebuilding sounds harmless but is not: it can quietly pick up a different dependency version between
two builds minutes apart, so the tested version and the serving version become two different pieces
of software with the same name. One build per change removes that gap.

**Consequences.**
- *Gains:* A provable guarantee that the tested artifact is deployed; one scan and signature per
  image; a smaller attack surface than three registries.
- *Accepts:* Workload accounts depend on `innovate-shared-services` to pull images.

**Cost impact.** Marginally cheaper than three registries — one set of storage and scanning charges.

**Revisit when.** A compliance requirement mandates isolated image storage that scoped IAM policies
on a shared registry cannot satisfy.

### ADR-017 — GitOps Pull-Based Delivery with Argo CD Over Push-Based CI/CD

| | |
|---|---|
| **Status** | Accepted |
| **Requirement** | R11, R21, R23 |
| **Pillars** | Security · Reliability · Operational Excellence |
| **Section** | §3.9 Deployment — CI/CD and GitOps |

**Context.** Innovate Inc. is aiming for continuous delivery from day one and handles sensitive user
data. Whatever can reach a production cluster's API server is a direct line to that data.

**Options considered.**

| Option | Strengths | Weaknesses | Verdict |
|---|---|---|---|
| Push-based delivery — GitHub Actions runs `kubectl apply` or `helm upgrade` directly | Simple to set up; the most common pattern in smaller teams; one tool for build and deploy | The CI system must hold live credentials to every cluster's API server, including production; a compromised pipeline or a leaked credential is a direct, waiting path to deploy anything | Rejected — a genuinely reasonable default that trades away exactly the guarantee sensitive data needs |
| Pull-based delivery with Argo CD, running inside each cluster | The cluster's own controller reconciles state from Git; no external system ever holds a cluster credential; drift is corrected automatically, not discovered during an incident | A second tool to operate, and a mental model — desired-state-in-Git — the team must learn | **Chosen** |

**Decision.** Deployment to every EKS cluster runs through Argo CD, installed inside the cluster,
reconciling from a Git repository. No external system, GitHub Actions included, ever holds
credentials that can change cluster state.

**Why this is the right choice for Innovate Inc.** Most teams let their build system also deploy
their software — simpler to set up, but it means giving that system a key that can change anything
in production. This design does something different: the cluster fetches its own instructions from
a version-controlled list of what should be running, rather than the build system holding the keys
to change it directly. If the build system is ever compromised, the attacker can still only push a
bad image, not deploy anything, because deployment happens entirely inside the cluster.

**Consequences.**
- *Gains:* No external system holds a credential able to change a production cluster; every
  deployment is a reviewable Git commit; configuration drift self-corrects.
- *Accepts:* A second control system to operate, and a new troubleshooting habit — reading cluster
  state from Git rather than watching a pipeline run.

**Cost impact.** No meaningful direct cost; Argo CD runs inside the existing cluster.

**Revisit when.** The team needs deployment orchestration Argo CD cannot express, such as
coordinated multi-cluster releases beyond environment-by-environment promotion.

### ADR-018 — Image Signing Verified at Admission

| | |
|---|---|
| **Status** | Accepted |
| **Requirement** | R10, R11, R21 |
| **Pillars** | Security · Operational Excellence |
| **Section** | §3.8 Container registry |

**Context.** Innovate Inc.'s pipeline already scans every image for known vulnerabilities. Scanning
answers "is this image safe," not "did it come from our pipeline" — a gap that matters once anyone
with cluster access could deploy any image from anywhere.

**Options considered.**

| Option | Strengths | Weaknesses | Verdict |
|---|---|---|---|
| Vulnerability scanning alone, no signature check | Already required regardless; simpler pipeline | Scanning proves an image has no known vulnerabilities today; it proves nothing about who built it or whether it is the exact image the pipeline produced | Rejected — answers a real question, but not the one that matters at admission time |
| Image signing (cosign), checked manually or only in the pipeline | Establishes provenance at build time | A signature no one checks again at deploy time only proves provenance existed once; nothing stops an unsigned or differently-sourced image from being applied to the cluster directly | Rejected — the check has to happen where the image is actually admitted, not only where it was built |
| Cosign keyless signing plus a Kyverno admission policy that verifies the signature and registry origin before any pod starts | The cluster itself refuses to run anything that is not signed by the pipeline's own identity and does not come from the Innovate Inc. registry — enforced automatically, not documented as a process | Adds Kyverno as another moving part, and a signing-service outage can block legitimate deployments | **Chosen** |

**Decision.** Every image is signed with cosign, keyless, against the GitHub Actions OIDC identity
that built it. A Kyverno admission policy rejects any pod whose image is unsigned, wrongly signed, or
sourced from outside the ECR registry.

**Why this is the right choice for Innovate Inc.** A vulnerability scan checks whether an image is
safe; it does not check whether it is genuinely the one the pipeline built. Signing adds that check:
the pipeline stamps every image with a signature at build time, and every cluster refuses to start a
container whose signature does not match — not a rule someone might forget, but a machine that
refuses to start the wrong thing. That closes a real gap: someone with cluster access could otherwise
deploy an untested public image straight to production.

**Consequences.**
- *Gains:* A cluster-enforced guarantee that only images the pipeline built and signed can run.
- *Accepts:* Another moving part, and a failure mode where a signing outage or a Kyverno
  misconfiguration blocks a legitimate deployment.

**Cost impact.** No meaningful direct cost; both reuse existing identities and the cluster.

**Revisit when.** A signing-service outage blocks a deployment more than once, indicating the
control needs a documented break-glass bypass rather than none at all.
