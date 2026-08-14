# Agent Protocol — read this before every phase

**STATUS: NORMATIVE.** These rules apply to *every* phase. Phase documents add to them; they never
override them. If a phase document seems to contradict this file, this file wins.

---

## 1. Your working boundary (hard limit)

```
/home/artin/personal/git/opsfleet/architecture/          ← your entire world
```

Everything you read and everything you write lives under `architecture/`. Nothing outside it, ever —
not to look, not to "check something", not to gather context.

### Canonical layout — memorise it, do not go looking for anything else

```
architecture/
├── README.md              ← THE DELIVERABLE (created in Phase 11)
├── CLAUDE.md              ← entry point for a fresh agent
├── docs/
│   └── assessment.md      ← the client brief, verbatim, as supplied
├── diagrams/              ← Mermaid sources (created in Phase 10)
└── _plan/                 ← this plan; NOT part of the deliverable
    ├── README.md          ← phase index and workflow
    ├── AGENT-PROTOCOL.md  ← this file
    ├── STATE.md           ← progress + handoff log
    ├── brief.md           ← requirements register (R1–R28)
    ├── contract.md        ← fixed names, CIDRs, services, numbers
    ├── decision-register.md ← ADR format and allocation
    ├── well-architected.md  ← the six pillars and the tagging convention
    ├── style-guide.md     ← voice, Markdown, Mermaid rules
    ├── rubric.md          ← how a reviewer will score it
    ├── phases/            ← phase-00 … phase-13
    └── drafts/            ← section drafts, one per content phase
```

### You MUST NOT touch — read or write

| Path | Why |
|---|---|
| `terraform/` and `terraform/docs/` | A **different assignment** (Terraform / EKS + Karpenter). Another agent may be editing it right now. |
| `.claude/` | Session configuration, out of scope |
| Anything above `architecture/` in the repository | Out of scope |
| Anywhere outside the repository | Out of scope |

If a tool call would touch one of them, stop and report instead of proceeding.

### Cheap-context rule

You were given a phase document precisely so you would not have to explore. **Do not** run
repository-wide `find`, `grep -r`, or `ls -R` from the repository root. Do not read files "for
context" that your phase document did not list. Read your inputs, write your output, stop. If you
genuinely cannot proceed without a file that is not listed, say so in your completion report rather
than going looking.

---

## 2. What kind of task this is

This is a **paper design exercise**. You are writing an architecture document, not building
infrastructure. The client asked for a design; the design is the deliverable.

- **Do not** run `aws`, `gcloud`, `kubectl`, `terraform`, `helm`, or `docker`. There are no
  credentials and nothing to deploy.
- **Do not** produce Terraform, Kubernetes manifests, or application code as deliverables. Short
  *illustrative* snippets inside the document are welcome (see §5.7); a `.tf` file is not.
- **Do not** browse the web. Everything you need is in `contract.md` and your phase document. The
  single exception is Phase 13, and only for the bounded fact-check list it names.
- **Do** write in Markdown, for a competent engineer at a startup with limited AWS experience — and,
  in the plain-language fields, for the non-engineer founder paying the bill.

---

## 3. The files you always read first

Read them in this order. Together they are the intended context budget — nothing else is needed.

1. `_plan/AGENT-PROTOCOL.md` — this file. Rules of engagement.
2. `_plan/brief.md` — the client's requirements and the R1–R28 register.
3. `_plan/contract.md` — **normative** names, CIDRs, service choices, numbers, the three-tier model
   (§1a), and the locked final section map (§14) you cite when referencing other chapters.
4. `_plan/decision-register.md` — **normative** ADR format and your reserved ADR numbers.
5. `_plan/well-architected.md` — **normative** pillar tagging and what each pillar demands here.
6. `_plan/style-guide.md` — how the prose and Markdown must look.
7. `_plan/phases/phase-NN-*.md` — your specific job.

Then read only the **Inputs** listed in your phase document.

---

## 4. The execution loop

```
1. Open _plan/STATE.md.                Find the first phase whose status is not "done".
2. Confirm its dependencies are "done". If not, stop and say which one is blocking.
3. Set that phase's status to "in-progress" in STATE.md. Write it now, not later.
4. Read the files in §3, plus your phase's Inputs.
5. Write your output file(s) — only the ones in "Files you own".
6. Self-check against your phase's Acceptance criteria, one line at a time. Fix what fails.
7. Update STATE.md: status → "done", fill the completion report, record which ADR numbers
   you used, and log anything the next phase needs to know.
8. Append any invented names to contract.md §12 Extensions register.
9. Report to the human in the format in §8. Then STOP. Do not start the next phase.
```

**One phase per session.** Do not "helpfully" continue into the next phase. The human drives the
cadence by typing *do the task* or *continue with the next task*.

---

## 5. Writing rules that apply to every phase

### 5.1 The contract is law

Every account name, CIDR, cluster name, instance class, retention period, and service choice comes
from `contract.md`. Copy them exactly — including the `10.30.0.0/16`-style specifics. Never round,
rename, or "improve" them.

### 5.2 Justify everything — this is the graded skill

The brief says *justify*, and the client explicitly wants to understand **why each decision was
made**. A recommendation without a reason is a failed answer, no matter how correct the
recommendation is.

Inline, every design decision follows: **decision → why → what it beat → what it costs.**
Additionally, every *significant* decision gets a numbered Architecture Decision Record in your
draft's final `## Decision Records` section, using the exact template in `decision-register.md`,
drawn from your reserved number block. (This applies unchanged to content phases 00–08. From Phase
12 onward, only nine of these 29 records are promoted into the final Appendix B — see
`decision-register.md` §2a — but every phase still writes its full block; the promotion happens at
assembly, not at content-writing time.)

Read `decision-register.md` §4 before you write a single justification. Three tests: **specific**
(names the mechanism and the number), **comparative** (states what it beat), and **client-relevant**
(connects to growth, sensitive data, small team, or continuous delivery).

### 5.3 Write the plain-language layer for the client, not for yourself

Every ADR has a mandatory field: **"Why this is the right choice for Innovate Inc."** It is written
for a founder with no cloud background. No unexplained acronyms. No AWS product names used as if
their meaning were obvious. Explain what problem the decision solves for *them*, what would have gone
wrong otherwise, and what it means for their users' data, their engineers' time, their bill, or their
ability to keep shipping.

This is the field a reviewer reads first, and it is the one that most often reveals whether the
author actually understood the decision or was reciting a pattern.

### 5.4 Tag the Well-Architected pillars

Every `##` section ends its opening paragraph with a pillar line:

```markdown
> **Well-Architected pillars.** Security · Reliability · Cost Optimization
```

Two to four pillars, only ones the section substantively serves. Every ADR carries its pillars in the
metadata table. Convention and pillar meanings: `well-architected.md`.

### 5.5 Keep the three-tier model visible

The application is a three-tier architecture — presentation, application, data (`contract.md` §1a).
Refer to the tiers by name wherever they are relevant. The tier boundary is also the network boundary
and the security boundary; say so where it applies rather than describing four overlapping models.

### 5.6 Design like a DevSecOps engineer, not a security reviewer

Security is not a chapter that audits the design after the fact; it is a property of each decision.
Where a section makes a choice with a security consequence, state it there — the pipeline gate, the
admission policy, the identity boundary, the encryption key — rather than deferring all of it to §5.
Automate the control rather than documenting a process: a policy engine that rejects an unsigned
image beats a paragraph asking people to sign images.

### 5.7 Mechanics

1. **Name real services.** "A managed database" is worthless; "Amazon Aurora PostgreSQL-Compatible
   Edition, Serverless v2" is an answer.
2. **Tie every choice to one of the four client characteristics:** hundreds → millions of users,
   sensitive data, limited cloud experience, CI/CD. If a paragraph serves none of them, cut it.
3. **Snippets are illustrative and short.** ≤ 25 lines, fenced with a language tag, only where
   clearer than a sentence. Never a full Terraform module or Helm chart.
4. **Tables for anything enumerable.** Accounts, subnets, node pools, RPO/RTO, cost lines,
   trade-offs, options considered.
5. **No placeholders in committed output.** No `TODO`, `TBD`, `<fill me in>`, or "as discussed above"
   pointing at nothing. If you don't know, decide and say you decided.
6. **No invented facts.** Do not state a specific AWS price, quota, limit, or version number that is
   not in `contract.md`. Where a number matters and isn't fixed, describe the behaviour qualitatively
   or label it clearly as indicative.
7. **Expand each acronym on first use** in your own draft. Phase 11 removes duplicate expansions
   during assembly. Over-expanding is a cheap fix; under-expanding is not.

---

## 6. Anti-patterns that will fail review

| Anti-pattern | Do this instead |
|---|---|
| A recommendation with no stated alternative | Name what it beat, every time |
| An ADR whose plain-language field is still full of jargon | Rewrite it for someone who has never opened the AWS console |
| Copy-pasting the inline prose into the ADR | They serve different readers — see `decision-register.md` §3 |
| Tagging all six pillars on every section | Two to four, only where substantive |
| A wall of bullet points with no prose | 1–3 sentences of reasoning, then the bullets or table |
| Restating the brief back as an answer | Answer it; the brief is already in `brief.md` |
| "Best practices dictate…" with no specifics | Name the practice, the service, and the setting |
| Reciting Well-Architected Framework documentation | Map the framework to *this* design; nothing else has value |
| Designing multi-region active-active on day 1 | Design for day 1; put scale in the growth roadmap with its trigger |
| Silently dropping a sub-requirement | Check the R1–R28 register in `brief.md` before you finish |
| Merging high availability and disaster recovery | Different failure domains, different RPO/RTO. Separate headings. |
| Marketing tone ("world-class, cutting-edge, seamless") | Plain declarative engineering prose |
| Editing another phase's draft to "fix" it | Log it in `STATE.md` → *Cross-phase issues*; Phase 13 owns fixes |

---

## 7. STATE.md discipline

`STATE.md` is how a brand-new agent with zero memory knows what has happened. Treat it as the handoff
document, because it is.

- Update it **twice** per phase: once to claim the phase (`in-progress`), once to close it (`done`).
- Record **which ADR numbers you actually used**, so Phase 11 can assemble the register and Phase 12
  can check for gaps.
- The completion report must be readable by someone who never saw your session. "Wrote the network
  section" is useless. "Wrote `drafts/02-network.md`, 1 340 words, ADR-009 through ADR-013; used the
  production CIDR table verbatim; deferred Network Firewall to the growth roadmap" is useful.
- If you hit something the plan didn't anticipate, log it under **Open questions** — do not silently
  improvise a structural change.

---

## 8. Reporting back to the human

End every phase with a short, plain report:

```
Phase NN — <name> — done.

Produced:   <file>, <word count>, ADR-0NN–ADR-0NN
Key calls:  <2–4 decisions you made that weren't fully specified>
Assumed:    <anything you had to assume>
Left out:   <anything you deliberately deferred, and to where>
Next:       Phase NN+1 — <name>
```

No progress narration during the phase. No summary of files you read. No emoji.
