# Phase 7 — `README.md`, the user-facing documentation

**Depends on:** Phases 0–6.
**Produces:** `README.md`.

---

## Goal

Requirement **R6**: *"a short readme that explains how to use the Terraform repo and that also
demonstrates how an end-user (a developer from the company) can run a pod/deployment on x86 or
Graviton instance inside the cluster."*

This is the most-read file in the deliverable and quite possibly the only one read end to end. It is
graded on whether a stranger can go from `git clone` to a running Graviton pod using nothing else.

The assignment says **short**. Take that seriously: two audiences, clearly separated, no wall of
text. Depth belongs in `docs/`, which the README links to.

**Target ~150–200 lines including code blocks.** If a section already exists in `docs/`, the README
gets a one-line summary and a link — not a copy. The section that may run long is
"Running a pod on Graviton or x86", because that one *is* the assignment.

---

## Inputs

Everything. Read every phase's completion report before writing — the README must describe what was
**actually built**, including deviations, not what the plans said would be built.

Particularly:

| Source | For |
|---|---|
| All phase completion reports | Real variable names, real deviations |
| `00-architecture-and-decisions.md` | §4 prerequisites, §5 costs, the ADR rationale to summarise |
| `reference/version-pinning.md` | The version table |
| `reference/gotchas.md` | The troubleshooting section |
| Phase 6's `examples/README.md` | Do not duplicate it — link to it |

---

## Specification

### Required structure

Follow this outline. Prose in a couple of sentences per section, then a command block.

```markdown
# EKS + Karpenter on AWS

> One paragraph: what this deploys and what it is for.

[architecture diagram]

## What you get
[bullet list: dedicated VPC across 3 AZs, EKS 1.36, Karpenter 1.14.0,
 amd64 + arm64 NodePools, Spot + On-Demand, Pod Identity, encrypted everything]

## Prerequisites
[the table from 00-architecture-and-decisions §4 — including the vCPU quota
 warning and the Spot service-linked role, both with copy-pasteable commands]

## Quick start
[bootstrap state -> configure -> init -> apply -> update-kubeconfig, ~6 commands]

## ── FOR DEVELOPERS ──────────────────────────────
## Running a pod on Graviton or x86
[THE SECTION THE ASSIGNMENT ASKS FOR. See below.]

## ── FOR OPERATORS ───────────────────────────────
## Configuration
[the ~8 variables a user actually sets, not all 30. Link to
 docs/contracts/interface-contract.md §3 for the full table.
 Show the POC-cheap tfvars block.]

## Cost
[3-4 lines: the idle total, the two biggest levers (NAT, VPC endpoints),
 and that Karpenter scales to zero. Link to docs/00-architecture-and-decisions §5
 for the full table. Do NOT reproduce the table.]

## How it works
[3 short paragraphs: what happens when a pod goes Pending, what happens on a
 Spot interruption, and why there is a bootstrap node group.]

## Design decisions
[one line each, linking into docs/. No rationale prose — the ADRs have it.]

## Operations
[upgrading Kubernetes, upgrading Karpenter (BOTH charts), pinning the AMI alias.
 5-6 lines.]

## Troubleshooting
[the 4 symptoms most likely to hit a first-time user, one line each,
 linking to the matching G-NN in docs/reference/gotchas.md. Not eight.]

## Teardown
[the ordered destroy runbook from Phase 8 — with the warning about why order matters]

## Repository layout
[tree, one line per directory]
```

### The developer section — get this exactly right

This is what R7 is graded on. It must be self-contained and it must lead with the answer.

Open with the one-liner, before any explanation:

````markdown
Add one line to your pod spec:

```yaml
nodeSelector:
  kubernetes.io/arch: arm64    # Graviton.  Use "amd64" for x86.
```

That is the whole interface. `kubernetes.io/arch` is a standard Kubernetes label — you do not
need to know anything about Karpenter or node pools to use it.
````

Then, in this order:

1. **A complete, runnable example** — the `deployment-arm64.yaml` from Phase 6, inline, so the
   reader does not have to open another file. **Copy it verbatim from the file Phase 6 actually
   shipped and tested** — do not retype it from this document or from memory. It uses
   `nginx-unprivileged` on port 8080 with `runAsUser: 101` for a specific reason (see phase-06 §6.1);
   a README example that reverts to plain `nginx` will not start under the `restricted` Pod Security
   profile, and the README is the copy a reviewer will paste.
2. **What happens next**, with real expected output:
   ```bash
   kubectl apply -f examples/deployment-arm64.yaml
   kubectl get nodeclaims -w     # Karpenter launches a Graviton node, ~40-70s
   kubectl get pods -n demo -o wide
   kubectl get nodes -L kubernetes.io/arch,karpenter.sh/capacity-type,node.kubernetes.io/instance-type
   ```
   Include a realistic sample of that last command's output. Readers trust output they can compare
   against.
3. **Proving it**: `kubectl logs -n demo job/arch-check` → `aarch64`.
4. **The x86 case**, showing that only one line differs.
5. **What if I do not care?** — omit the `nodeSelector` and you get Graviton, because the arm64 pool
   is weighted higher. **State the caveat plainly**: this requires a multi-arch image, and an
   x86-only image will `CrashLoopBackOff` with `exec format error`. Give the fix:
   `docker buildx build --platform linux/amd64,linux/arm64`.
6. **Spot**: pods may be interrupted with a 2-minute warning; Karpenter drains and replaces the node
   automatically. Workloads should handle `SIGTERM` and set a PodDisruptionBudget. One short
   paragraph — this is the honest cost of the price/performance win.
7. **Cleanup**, noting Karpenter removes the nodes by itself.

### Things the README must not do

- **Do not duplicate `docs/`.** Link to it. The README is short by requirement.
- **Do not document aspirational features.** If Phase 9/10/11 were not implemented, the README does
  not mention them except under a clearly-labelled "Not included / possible extensions" line.
- **Do not paste secrets, account IDs, or a real IP** in the example `tfvars`.
- **Do not claim anything you did not verify.** If the stack was never applied against real AWS, say
  so explicitly in a "Status" note near the top. An honest limitation reads far better than a
  confident claim a reviewer can disprove in five minutes.

### The architecture diagram

ASCII, in a fenced block. Reuse the one from `00-architecture-and-decisions.md` §2, trimmed. It must
render correctly in a monospace block on GitHub — check the alignment, do not assume it.

### Version table

A short table of what is pinned (Terraform, AWS provider, EKS module, VPC module, Kubernetes,
Karpenter), with a link to `docs/reference/version-pinning.md` for the re-verification
commands. Include the **date verified**. A version table without a date is worthless six months on.

---

## Security requirements owned by this phase

- **S-70** Prerequisites document least-privilege deployment credentials, and the README does not
  suggest running as account root.
- **S-71** No real account IDs, IP addresses, ARNs or key material anywhere in the README.
- **S-72** The `cluster_endpoint_public_access_cidrs` guidance tells the reader to use their own
  `/32` and explains why `0.0.0.0/0` is rejected by a validation block.
- **S-73** The security posture is stated honestly, including the known limitations: the CMK
  availability risk, `hostNetwork` pods bypassing the IMDS hop limit, and `al2023@latest` drift if
  the AMI alias is left unpinned.

---

## Acceptance criteria

```bash
# 1. Every command in the README actually runs. Extract and eyeball them.
grep -oP '(?<=^\$ ).*' README.md
awk '/```(bash|sh)/,/```/' README.md

# 2. No leaked identifiers.
grep -nE '[0-9]{12}' README.md            # AWS account IDs
grep -nE 'AKIA[0-9A-Z]{16}' README.md     # access keys
grep -nE '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' README.md | grep -v '203.0.113\|0.0.0.0\|10\.0\.'
# 203.0.113.0/24 is the RFC 5737 documentation range — the right placeholder to use.

# 3. Every internal link resolves.
grep -oP '\]\(\K[^)]+' README.md | grep -v '^http' | while read -r l; do
  [ -e "$l" ] || echo "BROKEN LINK: $l"
done

# 4. Length sanity — the assignment says "short".
wc -l README.md    # aim for 150-200 lines including code blocks
```

**The real test, and you must actually do it:** re-read the README pretending you have never seen
this repository. Can you get from clone to a running Graviton pod using only this file? Every step
you had to guess at is a defect. List them in the completion report.

---

## Notes for the implementing agent

- Read every completion report first. Document reality, not the plan.
- If a phase deviated from spec, the README describes the deviation, silently and correctly — it
  does not explain the history.
- Prefer showing output over describing it.
- If Phases 9–11 were skipped, add one line under "possible extensions" and move on.

---

## Agent prompt

```text
Implement Phase 7 of the EKS + Karpenter Terraform assessment.

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

Read, in this order:
  1. EVERY "## Completion report" section in docs/phases/phase-0*.md and phase-1*.md
     — the README must document what was ACTUALLY built, including deviations.
  2. docs/00-architecture-and-decisions.md   (§2 diagram, §4 prerequisites, §5 costs, ADRs)
  3. docs/reference/version-pinning.md       (the version table)
  4. docs/reference/gotchas.md               (troubleshooting)
  5. examples/README.md                    (do not duplicate — link to it)
  6. docs/phases/phase-07-readme.md          (your specification)

Write README.md following the required structure in phase-07.

Critical constraints:
  - The assignment says "short". Target 250-450 lines. Depth goes in docs/, linked.
  - The developer section must LEAD with the nodeSelector one-liner, then a complete runnable
    example, then real expected output.
  - Document only what exists. If Phases 9-11 were not implemented, one line under
    "possible extensions".
  - If the stack was never applied against real AWS, say so explicitly in a Status note near
    the top. Do not claim verification you did not do.
  - No real account IDs, IPs, ARNs or keys. Use the RFC 5737 range (203.0.113.0/24) for
    example IPs.
  - Verify every internal link resolves and the ASCII diagram aligns in a monospace block.

Then do the real test: re-read it as someone who has never seen this repo, and list in your
completion report every step you had to guess at.

When finished, fill in the "## Completion report" section at the bottom of
docs/phases/phase-07-readme.md and stop. Do not start Phase 8.
```

---

## Completion report

*To be filled in by the implementing agent.*

- Status:
- Files created/changed:
- Deviations from spec:
- **Gaps found in the cold-read test:**
- Verification run:
- Notes for the next phase:
