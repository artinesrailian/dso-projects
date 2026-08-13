# EKS + Karpenter POC — Implementation Plan

This directory (`terraform/docs/`) is the **design and delivery plan** for the technical assignment.
It is documentation, not deployable code. The deliverable itself is the rest of `terraform/`.

> **Assignment recap.** Terraform code that deploys an EKS cluster (latest available version) into a
> new dedicated VPC; Karpenter with node pool(s) able to launch both x86 and arm64 instances,
> leveraging Graviton and Spot; and a README showing how a developer runs a pod on x86 or Graviton.
> *"Please place your technical assignment solution under the `terraform/` folder in the repository
> root."*

---

## 🛑 Scope boundary

The repository root holds **two unrelated assessments**:

```
opsfleet/
├── architecture/     ← A DIFFERENT ASSESSMENT. Out of scope. Never touch it.
└── terraform/        ← This assessment. The working directory for every phase.
```

Every agent that implements a phase must:

1. Use `terraform/` as its working directory and never leave it.
2. Never read, write, list, grep or `cd` into `architecture/`.
3. Create nothing at the repository root — no new files, no new sibling directories. Everything,
   including `.gitignore` and any CI config, lives under `terraform/`.
4. Never run repo-wide commands (`grep -r` from the root, `find` from the root, root `git status`).

Every phase's copy-paste prompt already carries this as a non-negotiable preamble. **All paths in
every document here are relative to `terraform/`.**

---

## How to use this plan

The work is cut into **phases**. Each phase is a self-contained unit that one agent can implement in
one sitting without having read any of the others. Every phase document contains:

| Section | Purpose |
|---|---|
| **Goal** | One paragraph — what exists at the end that did not exist at the start. |
| **Inputs** | Exactly which files and outputs from earlier phases this phase consumes. |
| **Files to create** | The complete file list. Nothing else may be touched. |
| **Specification** | The actual requirements, with rationale for the non-obvious ones. |
| **Security requirements** | Numbered items from `contracts/security-checklist.md` this phase owns. |
| **Acceptance criteria** | Runnable commands with expected output. Not vibes. |
| **Agent prompt** | A copy-paste block to hand to the implementing agent. |
| **Completion report** | Filled in by the agent when done; read by the next agent. |

**To run a phase:** open the phase document, copy the fenced block under *Agent prompt*, paste it
into a fresh agent session. That is the whole workflow — one paste per phase.

Each prompt already carries the scope boundary above, tells the agent exactly which documents to
read and in what order, and ends by instructing it to fill in that phase's *Completion report* and
**stop**. Agents do not chain into the next phase on their own; you decide when to continue.

Between phases, skim the completion report the agent wrote. It records deviations, and the next
phase's agent reads it — so a wrong or empty report propagates.

### What is already pinned for you

Versions were verified against primary sources on **2026-08-11** and are recorded in
[`reference/version-pinning.md`](reference/version-pinning.md). Headline values:

| | |
|---|---|
| Kubernetes (EKS) | `1.36` |
| Karpenter | `1.14.0` (LTS) |
| `terraform-aws-modules/eks` | `21.24.2` |
| `terraform-aws-modules/vpc` | `6.6.1` |
| `hashicorp/aws` | `~> 6.58` |

Agents are instructed never to recall a version from memory — model training data lags reality by
months. During this plan's own research the model's recollection said "EKS 1.34 is the latest"; the
AWS documentation said **1.36**. If the pins look stale, run the re-verification block in
`reference/version-pinning.md` §3 and update that file first.

### Before phase 1, read these three

1. [`00-architecture-and-decisions.md`](00-architecture-and-decisions.md) — the target architecture,
   the decisions taken and *why*, prerequisites, and the cost envelope.
2. [`contracts/interface-contract.md`](contracts/interface-contract.md) — **normative.** Exact file
   layout, variable names, output names, tags. This is what keeps independently-implemented phases
   composable.
3. [`reference/version-pinning.md`](reference/version-pinning.md) — every version to pin, with the
   command to re-verify it hasn't drifted.

---

## Phases

### Core — required for the deliverable

| # | Phase | Produces | Depends on |
|---|---|---|---|
| 0 | [Repository scaffold & remote state](phases/phase-00-scaffold-and-state.md) | `terraform/` skeleton, version pins, provider config, `bootstrap/` S3 backend | — |
| 1 | [Networking (VPC)](phases/phase-01-networking.md) | `modules/network` — 3-AZ VPC, subnet tagging, NAT, flow logs, VPC endpoints | 0 |
| 2 | [EKS control plane](phases/phase-02-eks-cluster.md) | `modules/eks` — cluster, KMS, access entries, add-ons, bootstrap node group | 0, 1 |
| 3 | [Karpenter AWS-side](phases/phase-03-karpenter-aws.md) | IAM roles, SQS interruption queue, EventBridge rules, node access entry | 0, 2 |
| 4 | [Karpenter Helm deployment](phases/phase-04-karpenter-helm.md) | Karpenter controller running in-cluster | 3 |
| 5 | [NodePools & EC2NodeClass](phases/phase-05-nodepools.md) | `amd64` + `arm64` NodePools, Spot + On-Demand, `default` EC2NodeClass | 4 |
| 6 | [Demo workloads](phases/phase-06-demo-workloads.md) | `examples/` manifests proving x86 / Graviton / multi-arch scheduling | 5 |
| 7 | [User-facing README](phases/phase-07-readme.md) | `README.md` — the graded artifact | 0–6 |
| 8 | [Verification & teardown](phases/phase-08-verification-teardown.md) | End-to-end test runbook, hardening audit, clean `destroy` | 0–7 |

### Optional — implement only if explicitly requested

| # | Phase | Produces |
|---|---|---|
| 9 | [AWS Load Balancer Controller](phases/phase-09-optional-alb-controller.md) | Ingress via ALB/NLB, Pod Identity wired |
| 10 | [metrics-server & HPA demo](phases/phase-10-optional-metrics-hpa.md) | Pod autoscaling that cascades into Karpenter node autoscaling |
| 11 | [CI/CD & policy scanning](phases/phase-11-optional-cicd.md) | GitHub Actions: `fmt`/`validate`/`tflint`/`checkov`/`trivy`, pre-commit hooks |

### Dependency graph

```
        ┌── 0 scaffold ──┐
        │                │
        ▼                ▼
    1 network ──────► 2 eks ──────► 3 karpenter-aws ──► 4 karpenter-helm ──► 5 nodepools
                          │                                                       │
                          │                                                       ▼
                          │                                                6 demo workloads
                          │                                                       │
                          └───────────────────────────────────────────────────────┤
                                                                                  ▼
                                                                             7 README
                                                                                  │
                                                                                  ▼
                                                                    8 verification & teardown

    optional: 9 alb-controller / 10 metrics-hpa  (after 5)     11 ci-cd  (after 0)
```

Phases 1 and 2 can overlap only if the phase-2 agent trusts the `modules/network` output names in
the interface contract rather than the implemented file. Everything else is strictly sequential.

---

## Rules that apply to every phase

1. **Stay in your lane.** Implement only the files your phase lists. If you believe another phase is
   wrong, note it in the completion report — do not fix it.
2. **The interface contract wins.** If the phase text and the contract disagree on a name, the
   contract is correct. If the contract is genuinely missing something, add it there and say so.
3. **Never invent a version number.** Take it from `reference/version-pinning.md`. If it looks stale,
   re-run the verification command in that file and update the file.
4. **Do not `terraform apply` without being told credentials exist.** The default deliverable state
   is: `terraform init` + `validate` + `fmt -check` clean, and `plan` clean where credentials allow.
   Applying costs real money.
5. **Security is not a later phase.** Each phase owns numbered items from
   [`contracts/security-checklist.md`](contracts/security-checklist.md) and must satisfy them before
   reporting DONE.
6. **Leave the completion report filled in.** The next agent reads it instead of guessing.

---

## Status tracker

Update as phases land.

| Phase | Status | Notes |
|---|---|---|
| 0 Scaffold & state | ☐ Not started | |
| 1 Networking | ☐ Not started | |
| 2 EKS cluster | ☐ Not started | |
| 3 Karpenter AWS | ☐ Not started | |
| 4 Karpenter Helm | ☐ Not started | |
| 5 NodePools | ☐ Not started | |
| 6 Demo workloads | ☐ Not started | |
| 7 README | ☐ Not started | |
| 8 Verification | ☐ Not started | |
| 9 ALB controller *(opt)* | ☐ Not started | |
| 10 metrics/HPA *(opt)* | ☐ Not started | |
| 11 CI/CD *(opt)* | ☐ Not started | |
