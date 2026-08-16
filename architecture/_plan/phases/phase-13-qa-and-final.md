# Phase 13 — QA, consistency audit & final polish

> The last phase. Nothing ships until this one passes.
> Read [`../AGENT-PROTOCOL.md`](../AGENT-PROTOCOL.md), [`../rubric.md`](../rubric.md),
> [`../brief.md`](../brief.md), [`../contract.md`](../contract.md),
> [`../decision-register.md`](../decision-register.md), and
> [`../well-architected.md`](../well-architected.md) first.

---

## Goal

Audit `architecture/README.md` as a hostile reviewer would, fix what fails, and record the score.
Twelve agents contributed to this document; the failures will be at the seams — a CIDR that drifted,
an acronym expanded twice, a requirement that quietly went missing, a Mermaid block with an
unbalanced `subgraph`, an ADR whose plain-language field is still full of jargon.

**You are the only phase permitted to edit the assembled README.** Fix problems here rather than
sending work back.

---

## Dependencies

Phase 12 must be `done`.

## Inputs

Everything under `architecture/`: `README.md`, all drafts, all diagram sources, `contract.md`,
`brief.md`, `rubric.md`, `style-guide.md`, `decision-register.md`, `well-architected.md`, `STATE.md`,
and `docs/assessment.md`.

## Files you own

- `../README.md` — edit
- `../diagrams/*.md` — edit, **only** to fix a genuine Mermaid syntax error
- `_plan/STATE.md` — update, and record the rubric score
- `_plan/contract.md` §12 — append if you had to fix a name

---

## Audit passes — run all nine, in order, and record each verdict

Run them as separate passes. Combining them is how things get missed.

### Pass 1 — Requirement coverage (fatal if it fails)

For each of R1–R28 in `brief.md`, find the text in `README.md` that satisfies it and note the section
number. Do not accept "it's implied". Pay particular attention to the sub-requirements that get
dropped:

- [ ] R2 — the account count is **justified** against isolation, billing, **and** management
- [ ] R6 — node groups have their own treatment
- [ ] R8 — **resource allocation within the cluster** has its own heading and is not just autoscaling
- [ ] R9, R10, R11 — image building, registry, **and** deployment each have their own heading
- [ ] R13, R14, R15 — backups, high availability, **and** disaster recovery are three separate
      headings, not two
- [ ] R18 — at least one HLD, embedded, rendering, referenced in the text, and showing the tiers
- [ ] R22 — cost has real content, with figures and levers
- [ ] R26 — every significant decision has inline reasoning, plus **either** a promoted Appendix B
      ADR (the nine in `decision-register.md` §2a) **or** a row in the §10 Summary of Key Decisions
      table — not necessarily both
- [ ] R27 — all six pillars covered, with tags and trade-offs
- [ ] R28 — the three-tier model is structural, not a passing mention

Appendix A (Requirement Traceability) was removed from the deliverable by explicit human instruction
on 2026-08-16 — see `STATE.md`'s Plan amendments — so do not check for it, and do not re-add it.
Requirement coverage for R1–R28 is still verified above, against the body and §10/Appendix B directly,
not against a traceability table.

### Pass 2 — Cross-section consistency (severe if it fails)

Build a fact table as you read and check for contradictions. At minimum, verify each of these appears
identically **everywhere** it appears — prose, tables, ADRs, and diagrams:

| Fact | Must be |
|---|---|
| Number of AWS accounts at launch | 7 (9 planned) |
| Production VPC CIDR | `10.30.0.0/16` |
| Pod secondary CIDR (production) | `100.66.0.0/16` |
| Number of Availability Zones | 3 |
| NAT Gateways in production | 3 |
| Primary / DR region | `us-east-1` / `us-west-2` |
| Production cluster name | `innovate-prod-eks-use1` |
| Aurora cluster identifier | `innovate-prod-aurora-pg-use1` |
| Backup retention, production | 35 days |
| Region-loss RPO / RTO | < 1 min / < 60 min |
| API availability SLO | 99.9% |
| Indicative day-1 monthly cost | ≈ $850–900 (lean ≈ $420) |
| Namespace names | `innovate-api`, `innovate-jobs`, `platform-*` |
| NodePool names | `app-arm64-spot`, `app-amd64-spot`, `app-ondemand` |
| Tier names | presentation, application, data |

Also check: the subnet table's CIDRs against diagram 3's CIDRs, character by character; every account
name against `contract.md` §4; every service name against `contract.md` §13.

### Pass 3 — Decision register integrity (severe if it fails)

- [ ] Appendix B contains **exactly** the nine ADRs fixed in `decision-register.md` §2a — 001, 004,
      007, 011, 017, 019, 023, 026, 029 — no more, no fewer, no substitutions. A promoted record
      missing means a phase under-delivered — find it in that phase's draft and add it rather than
      promoting a different number from the same block.
- [ ] The other twenty ADR numbers (recorded in the drafts but not promoted) each have a row in §10
      with the ADR column left as `—`. A number with neither a §10 row nor an Appendix B entry is a
      dropped decision — add the §10 row.
- [ ] Every promoted ADR carries every field of the template in `decision-register.md`: Status, Requirement,
      Pillars, Section, Context, Options considered, Decision, **Why this is the right choice for
      Innovate Inc.**, Consequences (Gains and Accepts), Cost impact, Revisit when.
- [ ] Every ADR's `Section` reference matches `contract.md` §14 and points at a heading that exists.
- [ ] No ADR exceeds 250 words excluding its two tables.
- [ ] Every options table has at least one **genuinely reasonable** rejected alternative — not three
      strawmen. Read them; a table where every rejected option is obviously terrible is a failure.
- [ ] Every *Accepts* list contains a real downside, not a trivial one.
- [ ] Every *Revisit when* names an observable trigger — reject "as needed", "in future", "when
      appropriate".
- [ ] **Read every "Why this is the right choice for Innovate Inc." field aloud in your head as a
      non-engineer.** Any unexplained acronym, any AWS product name used as though self-evident, any
      sentence a founder would need explained — rewrite it. This is the most commonly failed check in
      this pass and it is severe, because it is the field the client actually reads.
- [ ] No ADR is a verbatim copy of its inline body prose.

### Pass 4 — Well-Architected alignment (moderate if it fails)

- [ ] Every numbered chapter carries exactly one pillar line with 2–4 pillars.
- [ ] All six pillars have a `###` subsection in §9, **including Sustainability**.
- [ ] Each pillar subsection has a one-sentence demand, an evidence table with section references,
      and a stated gap with a trigger.
- [ ] **Spot-check three evidence rows** against the body: does the document actually say what the
      pillar table claims? An invented evidence row is the most likely correctness failure here.
- [ ] §9.7 trade-off table is present with the pillar being sacrificed named in each row.
- [ ] The chapter does not recite Well-Architected Framework documentation.

### Pass 5 — Three-tier coherence (moderate if it fails)

- [ ] The three tiers are named and defined in §0.2 with a table.
- [ ] The subnet tiers in §2 map to the application tiers explicitly.
- [ ] Each tier's scaling mechanism is distinct and stated.
- [ ] The tier boundary is shown to be enforced by a mechanism (security-group references,
      NetworkPolicy, CloudFront prefix list) rather than by convention.
- [ ] Diagram 1's legend maps colours to tiers.
- [ ] Tier names are used consistently — never "front-end tier" or "web tier" for presentation.

### Pass 6 — Mermaid validation (fatal if it fails)

For every Mermaid block in `README.md` **and** in each of the five diagram source files (the README
embeds copies — both must be correct), walk the eleven-item checklist from
[`phase-10-diagrams.md`](phase-10-diagrams.md) *Verification*. In particular, physically count
`subgraph` keywords against closing `end` lines, and confirm every node ID matches `[a-zA-Z0-9_]+`
and every label is quoted.

A cheap mechanical aid, scoped to your own directory only:

```bash
grep -n "subgraph\|^\s*end\s*$" architecture/README.md
```

Counts must balance per diagram. If a block is broken, fix it in **both** the README and the source
file so they do not diverge.

### Pass 7 — Technical correctness (severe if it fails)

Read as a principal engineer looking for something to object to. Check specifically:

- [ ] Security groups described as **stateful**, network ACLs as **stateless**
- [ ] Horizontal Pod Autoscaler / KEDA / Karpenter / Vertical Pod Autoscaler described as four
      distinct things doing four distinct jobs
- [ ] High availability (in-region, multi-AZ) not conflated with disaster recovery (cross-region)
- [ ] AWS WAF described as an edge and application-layer control, not as protection for east-west
      traffic
- [ ] Subnet arithmetic correct and no CIDR overlaps
- [ ] No specific Kubernetes version number stated anywhere
- [ ] **No AWS price, quota, or limit stated as fact** unless it came from `contract.md` §11 and is
      labelled indicative. Search the document for `$` and check every hit.
- [ ] No hallucinated AWS service, feature, or capability — if you cannot place a claim in
      `contract.md`, either soften it to a qualitative statement or cut it
- [ ] Every claim about a service's behaviour is one you would defend in an interview

### Pass 8 — Style, placeholders and readability

- [ ] One `#` heading only; heading hierarchy never skips a level
- [ ] No banned words from `style-guide.md` §1 — search for `leverage`, `seamless`, `world-class`,
      `cutting-edge`, `best-in-class`, `simply`, `journey`, `delve`, `it is important to note`
- [ ] Each acronym expanded exactly once in the body (Appendix B may re-expand — it is
      self-contained by design)
- [ ] Percentages formatted consistently with no space
- [ ] Every `##` section opens with prose, not a bullet or a table
- [ ] All callouts use one of the five allowed labels
- [ ] No emoji
- [ ] Every table has a header and an alignment row
- [ ] Every internal anchor resolves; the table of contents matches the headings
- [ ] Total length 9 000–12 000 words: body §0–§10 at 4 800–6 500, Appendix B at 2 000–2 500
- [ ] Search for and eliminate: `TODO`, `TBD`, `XXX`, `FIXME`, `???`, `<!-- EXEC-SUMMARY`, `Lorem`,
      `placeholder`, `[insert`, `TBC`, `<fill`, any heading with no body, any "see above" pointing at
      nothing, and any leftover instruction text copied from a phase document

### Pass 9 — Rubric scoring

Score every dimension in `rubric.md` §2 (A–H) as `weak` / `adequate` / `strong`. For anything below
`strong`, either fix it now or record in `STATE.md` why it stays. Then take the twelve depth probes in
`rubric.md` §3 and, for each, locate the section that answers it and note the section number. **Any
probe with no answer is a gap — write the missing content.**

---

## Fixing rules

- Fix directly in `README.md`. Do not send work back to earlier phases.
- Keep edits surgical. Do not rewrite sections that pass.
- If a fix requires changing a `contract.md` value, change `contract.md` too so the record stays
  coherent, and note it in `STATE.md`.
- If you find a genuine gap needing more than ~200 words of new content, write it, and note in your
  report that it was added at QA rather than by its owning phase.
- If a decision that is clearly significant has neither a §10 row nor a promoted ADR, add a §10 row
  for it — do **not** add a new entry to Appendix B. Appendix B is capped at the nine records fixed
  in `decision-register.md` §2a; that cap does not change at QA. Only fix Appendix B itself if one of
  those nine specific promoted records is missing or incomplete.

---

## Final step — reviewer's-eye read

After all nine passes, read `architecture/README.md` once, top to bottom, without a checklist, as
though you were the reviewer meeting it for the first time. Ask three questions:

1. **Would a founder with no cloud background finish the executive summary knowing what was chosen
   and why?**
2. **Would a principal engineer find anything naive, hand-wavy, or factually wrong?**
3. **Does it read as one author, or can you see the seams?**

Fix what that read surfaces. This pass catches what the checklists cannot.

---

## Acceptance criteria

- [ ] All nine audit passes run, in order, each with a recorded verdict in `STATE.md`.
- [ ] Every R1–R28 requirement located in the README, by section number.
- [ ] Every fact in the Pass 2 table verified identical across prose, tables, ADRs, and diagrams.
- [ ] Decision register verified: exactly the nine records fixed in `decision-register.md` §2a, the
      other twenty each present as a §10 row, every field present on the nine, every plain-language
      field readable by a non-engineer, every options table containing a fair alternative.
- [ ] All six pillars verified, with three evidence rows spot-checked against the body.
- [ ] Three-tier coherence verified end to end.
- [ ] Every Mermaid block passes the eleven-item checklist, in both the README and the source files.
- [ ] Every `$` figure traced to `contract.md` §11 and labelled indicative.
- [ ] Zero placeholders, zero banned words, zero broken anchors.
- [ ] All twelve rubric depth probes have a located answer.
- [ ] Rubric dimensions A–H scored, with any non-`strong` justified in `STATE.md`.
- [ ] The final reviewer's-eye read completed and anything it surfaced fixed.
- [ ] `STATE.md` shows Phase 13 `done`, all *Open questions* resolved or explicitly accepted, and all
      *Cross-phase issues* closed.

## Common failure modes

| Failure | Avoid it by |
|---|---|
| Skimming instead of auditing | Nine separate passes. A single read finds a third of the problems. |
| Trusting that the diagrams parse because they look fine | Count `subgraph`/`end` by hand. |
| Accepting a plain-language ADR field that is still technical | Read it as a founder would. This is the check most often waved through. |
| Accepting a pillar evidence row without checking the body says it | Spot-check three. |
| Fixing prose but not the diagram or ADR repeating the same fact | Pass 2 checks all four places. |
| Rewriting sections that were already good | Surgical edits only. |
| Marking `done` with open questions outstanding | Resolve or explicitly accept each one. |
| Skipping the final unstructured read | It catches the seams no checklist describes. |

---

## Agent prompt

```text
You are executing Phase 13 of the Innovate Inc. architecture design plan: QA, consistency audit
and final polish. This is the last phase — nothing ships until it passes.

Working directory boundary: architecture/ ONLY. Never read or write terraform/, .claude/, or
anything above architecture/. terraform/ belongs to a different assignment.

Read in full:
  architecture/_plan/AGENT-PROTOCOL.md
  architecture/_plan/brief.md
  architecture/_plan/contract.md
  architecture/_plan/decision-register.md
  architecture/_plan/well-architected.md
  architecture/_plan/style-guide.md
  architecture/_plan/rubric.md
  architecture/_plan/STATE.md
  architecture/_plan/phases/phase-13-qa-and-final.md
  architecture/README.md
  architecture/diagrams/*.md

Run all NINE audit passes described in the phase document, in order, as separate passes. Record a
verdict for each in STATE.md. Fix every failure directly in architecture/README.md (and in a
diagram source file only for a genuine Mermaid syntax error).

Pay special attention to:
 (a) the sub-requirements most often dropped — resource allocation within the cluster, deployment
     processes, and disaster recovery as distinct from high availability;
 (b) Pass 3 — reading every "Why this is the right choice for Innovate Inc." field as a
     non-engineer would, and rewriting any that still assume technical knowledge;
 (c) counting subgraph/end pairs in every Mermaid block;
 (d) tracing every $ figure back to contract.md §11.

Finish with the unstructured reviewer's-eye read described at the end of the phase document.

Then update STATE.md with the rubric score, report, and STOP.
```
