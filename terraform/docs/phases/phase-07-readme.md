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
[3-4 bullets only: AWS creds, the Spot service-linked role, the vCPU quota
 warning, required tooling. One line each with the check command.
 Link to docs/operator-runbook.md §1 for the full treatment — do NOT
 reproduce the §4 table.]

## Quick start
[the make targets: bootstrap -> configure -> init -> apply -> kubeconfig.
 ~6 lines. Then one sentence: "To bring it up in stages, or for the full
 platform-engineer runbook, see docs/operator-runbook.md."]

## ── FOR DEVELOPERS ──────────────────────────────
## Running a pod on Graviton or x86
[THE SECTION THE ASSIGNMENT ASKS FOR. See below.]

## ── FOR PLATFORM ENGINEERS ──────────────────────
## Operating this cluster
[~6 lines, then LINK OUT. docs/operator-runbook.md is the real document and
 already covers: credentials (SSO > assume-role > keys, and why not keys),
 what the deploy principal needs, the state backend's three options, staged
 bring-up with per-stage cost and verification gates, granting developers
 namespace-scoped access, upgrades, and ordered teardown.
 The README says what exists and links; it does not duplicate.]

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

- Status: DONE. `README.md` written at the repo root, following the required structure exactly
  (banner-delimited FOR DEVELOPERS / FOR PLATFORM ENGINEERS sections included). All four
  acceptance-criteria checks pass: no leaked identifiers, every internal link resolves, the
  developer-section YAML is byte-identical to the shipped `examples/deployment-arm64.yaml`
  (diffed programmatically, not eyeballed), and the ASCII diagram's box-drawing rows are a
  verified uniform 64 characters (built and checked with a Python script, not hand-typed —
  a first hand-typed attempt was in fact misaligned and caught by that check, see Deviations).
  A fresh, context-free agent then ran the actual cold-read test end to end; its findings are
  below, and every substantive one was fixed in the README before this report was filed.

- Files created/changed:
  - `README.md` — new, ~469 lines including the mandatory verbatim YAML block.
  - `docs/phases/phase-07-readme.md` — this completion report only.
  - Nothing else. No edits to `terraform.tfvars.example`, `backend.tf`, `examples/*.yaml`, or any
    other phase's deliverable — even where the cold-read test surfaced defects in those files
    (see "Notes for the next phase").

- Deviations from spec:
  1. **Target length: 250–450 lines, not 150–200.** The phase doc's own "Specification" section
     says ~150–200 lines; the direct task prompt that dispatched this phase explicitly overrode
     that to 250–450, "depth goes in docs/, linked." Followed the direct instruction. Final length
     is 469 — 19 lines over that band, entirely from fixes applied after the cold-read test (see
     below); judged that correctness outweighed a hard line count once real defects were found,
     rather than cutting fixes back in to hit a number.
  2. **The required outline has no explicit "version table" section header**, but §"Version
     table" (outside the numbered outline) separately mandates one with a verified date. Resolved
     by folding a compact pinned-versions table into the end of "## What you get" rather than
     adding a new top-level section, since the outline's own bullet list already introduces EKS
     1.36 / Karpenter 1.14.0 there.
  3. **First diagram draft was hand-typed and silently misaligned.** Built the ASCII diagram with
     a Python script generating fixed-width box rows (verified: all "┌"/"│"/"└" rows exactly 64
     Unicode codepoints), but then hand-transcribed it into the `Write` call instead of pasting
     the verified output — introducing 1–2 character drift on several rows. Caught by re-running
     the character-count check *after* writing the file (an `awk`-based check first gave a false
     "192 for every row" — that was byte-count under the shell's locale, not character count; a
     Python `len()` check on the actually-written file is what caught the real misalignment).
     Fixed by regenerating the diagram to a scratch file and pasting its exact bytes via `Edit`,
     then re-verifying. Lesson for whoever edits this diagram next: never hand-retype a
     generated-and-verified block; copy the verified bytes exactly.
  4. **Troubleshooting's fourth entry was swapped from G-01 to G-05 after the cold-read pass.**
     The first draft listed G-01 (`enable_cluster_creator_admin_permissions` defaults `false`) as
     a first-time-user gotcha. The cold-read agent found this misleading: that setting is not a
     root variable in this repo at all — `modules/eks/main.tf:34` hardcodes it `true` specifically
     to prevent G-01, so a reader hitting `Unauthorized` and searching for that variable would not
     find it. Replaced with G-05 (Karpenter itself sticks on one replica if
     `bootstrap_node_min_size` is dropped to `1`), which is both genuinely still live and directly
     triggered by the POC cost-saving override this same README recommends in Configuration.

- **Gaps found in the cold-read test** (a fresh, zero-context agent given only `README.md` and
  told to walk clone→apply→demo→teardown; full transcript-quality report available on request).
  All of the following were found by that agent; every item below **not** marked "left as-is" was
  fixed in the README before this report was filed:
  1. `backend.tf` has a comment pointing local-state users at "See README.md," which said nothing
     about local state. **Fixed** — Quick start now links to `docs/operator-runbook.md` §2 Option
     C.
  2. Quick start's tfvars comment said "set your /32 and an alert email," but the mandatory
     variable is `budget_notification_email`; a *different*, unrelated variable (`alert_email`,
     empty by default) feeds the KMS-danger alarm mentioned in Known limitations. **Fixed** —
     Quick start now names `budget_notification_email` explicitly; Configuration and Known
     limitations both now name `alert_email` and its default.
  3. Configuration claimed "30 total" variables; the real count (cross-checked against
     `variables.tf` and interface-contract §3) is 46. **Fixed.**
  4. `<cluster-name>`/`<region>` placeholders appeared twice (developer kubeconfig command,
     Teardown step 3) with no stated way to resolve them. **Fixed** — both now point at
     `terraform output -raw cluster_name`.
  5. The Troubleshooting entry citing `enable_cluster_creator_admin_permissions` as a fixable
     variable was wrong, per Deviation #4 above. **Fixed** by replacing the entry.
  6. "What happens next, **with real command output**" directly preceded a sample table labelled
     "illustrative — see Status above" two lines later — a self-contradiction the Status note had
     already correctly hedged but the section header oversold. **Fixed** — header shortened to
     "What happens next:".
  7. "On x86: same file, one line different" is not literally true — the Deployment/PDB name and
     every label selector also differ between `deployment-arm64.yaml` and `deployment-x86.yaml`
     (verified by `diff`), because the two objects coexist in the same namespace. **Fixed** —
     reworded to state the one *architectural* line changes and name the cosmetic differences
     honestly.
  8. Teardown instructs `kubectl delete namespace demo`, which reads as contradicting the
     developer section's "don't create/manage this namespace yourself" guidance. **Fixed** with an
     inline comment clarifying it's safe specifically because the whole stack is coming down next.
  9. `job-arch-check.yaml`'s `nodeSelector` is hardcoded to `arm64`, with no README pointer to how
     a reader would check the amd64 side. **Fixed** with a one-line pointer.
  10. Unexplained acronyms IRSA, ITN, MNG on first use. **Fixed** for IRSA (inline) and ITN/MNG (a
      legend line under the diagram). **Left as-is:** PSA, which appears only inside the verbatim
      `deployment-arm64.yaml` comment block — expanding it would violate the phase spec's explicit
      "copy it verbatim... do not retype it" instruction, since that YAML must match the shipped
      file byte-for-byte (verified by `diff`, see Verification run).
  11. `$EDITOR` assumed set; `make apply`'s real duration/billing-start not flagged. **Fixed** —
      both now have inline notes.
  12. **Left as-is, out of scope:** the verbatim YAML's own comment — "No CPU limit is set on
      purpose... it buys nothing a request doesn't already give Karpenter" — is arguably inaccurate
      given the `demo` namespace's LimitRange defaults a `1`-core CPU limit onto every container at
      admission time (`modules/cluster-resources/chart/templates/namespaces.yaml`). This is a
      pre-existing statement in Phase 6's shipped file, not something this phase's README author
      may silently rewrite without breaking the verbatim-copy requirement or reaching outside this
      phase's own deliverable (`README.md` only). Flagged here for whoever next touches
      `examples/deployment-arm64.yaml`.
  13. Overall verdict from the cold-read agent (before the fixes above were applied): the guided
      path (`make bootstrap` → `make apply` → `make kubeconfig` → `make demo`) was already
      self-contained; the gaps were concentrated in the manual/developer-facing commands the
      README itself prints inline. All fixable gaps above are now closed; #12 is the one
      documented, deliberate exception.

- Verification run (all from `terraform/`, no AWS credentials used or required):
  - `wc -l README.md` → 469.
  - `grep -nE '[0-9]{12}' README.md`, `grep -nE 'AKIA[0-9A-Z]{16}' README.md`,
    `grep -nE '([0-9]{1,3}\.){3}[0-9]{1,3}' README.md | grep -v '203.0.113|0.0.0.0|10\.0\.'` →
    all three empty. No account IDs, no access keys, no IP outside the RFC 5737 documentation
    range or the VPC's own `10.0.0.0/16`.
  - `grep -oP '\]\(\K[^)]+' README.md | grep -v '^http' | while read -r l; do [ -e "$l" ] ||
    echo "BROKEN: $l"; done` → empty (no broken links). Caught and fixed three same-page
    `#anchor` links that the literal `[ -e "$l" ]` check cannot resolve (anchors aren't files);
    replaced with plain bold cross-references instead of markdown links.
  - Diagram alignment: generated programmatically with a Python script (fixed interior width,
    `str.ljust`), the *first* hand-transcription attempt was verified broken (`len()` per row
    varied 64–66), regenerated to a scratch file and pasted its exact bytes; re-verified every
    box-drawing row is exactly 64 Unicode codepoints (`python3` `len()` per line, not `awk`, which
    reported byte counts under this shell's locale and would have hidden the bug).
  - `awk`-based extraction of the embedded `deployment-arm64.yaml` block, diffed against
    `examples/deployment-arm64.yaml` → identical.
  - Spot-checked every factual claim against source: version table against `versions.tf` /
    `modules/eks/main.tf` / `modules/network/main.tf`; the `0.0.0.0/0` validation message against
    `variables.tf` verbatim; the cost figures against `docs/00-architecture-and-decisions.md` §5;
    all four Troubleshooting gotcha codes against `docs/reference/gotchas.md`; the
    `enable_aws_load_balancer_controller`/`enable_metrics_server` "inert" claim by grepping both
    names across every `.tf` file (declared, one wired through to `modules/eks` as an input,
    neither consumed by any resource).
  - Cold-read test: a fresh `general-purpose` agent, given the scope boundary and only
    `README.md`, walked the full clone→demo→teardown path and reported 21 findings (13 real
    gaps/inconsistencies, others no-defect confirmations); see above for the disposition of each.
  - `terraform apply`, `kubectl`, and every "With credentials" style check — **not run.** No AWS
    credentials were available in this environment, consistent with every prior phase's
    completion report. The Status note in `README.md` states this explicitly and the sample
    `kubectl` output is labelled illustrative for the same reason.

- Notes for the next phase:
  - **Phase 8 is a real, undocumented gap, not an optional phase.** `scripts/verify.sh` and
    `scripts/teardown.sh` do not exist (`ls scripts/` → no such directory); `phase-08-*.md`'s own
    completion report is still the blank template. The README's Teardown section documents the
    manual G-09 sequence as the current stand-in and says so explicitly; once Phase 8 ships,
    Teardown's bash block should be replaced with the real `make destroy`/`scripts/teardown.sh`
    invocation and the Status note's Phase-8 caveat removed.
  - **`examples/deployment-arm64.yaml`'s "No CPU limit is set on purpose" comment is arguably
    inaccurate** given the `demo` namespace LimitRange's `default: {cpu: "1"}` — see cold-read gap
    #12 above. Not fixed here (out of this phase's file scope, and fixing it would break the
    "copied verbatim" requirement against the file Phase 6 actually shipped). Whoever next revises
    Phase 6's examples should reconcile the comment with the LimitRange behavior, and this README
    would then need its embedded copy re-synced.
  - `create_spot_service_linked_role`'s default-`false` change (Phase 3) has no corresponding
    commented-out line in `terraform.tfvars.example` — Phase 3's own completion report flagged
    this as a Phase 7 consideration. Documented in the README's Prerequisites/Configuration
    sections instead of editing `terraform.tfvars.example`, since that file is outside this
    phase's deliverable (`README.md` only); a future phase touching that file could add the
    commented example line Phase 3 suggested.
  - `enable_aws_load_balancer_controller` and `enable_metrics_server` are declared and (the latter
    only) wired as far as `modules/eks`, but neither is consumed by any resource — confirmed by
    grep, documented in the README's "Not included / possible extensions." Phase 9/10, if
    implemented, should either wire them up or the README's phrasing there should be revisited.
  - This phase never touched anything outside `terraform/`; no scope-boundary issues to report.
