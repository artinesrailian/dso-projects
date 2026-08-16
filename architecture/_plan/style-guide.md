# Style Guide

**STATUS: NORMATIVE.** Fourteen agents contribute to this document. It must read as though one person wrote it
in one sitting. That only happens if everyone follows the same rules.

---

## 1. Voice

- **Person:** third person about the client ("Innovate Inc. runs three workload accounts"), first
  person plural for recommendations ("We recommend Aurora PostgreSQL because…"). Never "you".
- **Tense:** present tense describing the target state ("The production VPC spans three Availability
  Zones"), not future ("will span") and not conditional ("would span"). The document describes a
  design that exists on paper; write it as real.
- **Mood:** decisive. "We recommend X" / "X is the right choice because" — never "you might want to
  consider possibly using X".
- **Register:** plain engineering prose. A senior engineer explaining a decision to a smart colleague
  who does not know AWS yet.

### Banned words and phrases

`leverage` (as a verb), `seamless`, `cutting-edge`, `world-class`, `robust and scalable` as a
throwaway pair, `best-in-class`, `synergy`, `journey`, `simply`, `just`, `obviously`, `of course`,
`it is important to note that`, `in today's fast-paced world`, `delve`, `tapestry`, `landscape` (as
metaphor). Do not open a section with "In this section, we will…".

### Required move: decision → reason → alternative → cost

Every recommendation gets all four, in this order, usually in one short paragraph plus a table row:

> We place each environment in its own AWS account rather than separating them by VPC inside one
> account. An account is the only boundary AWS enforces for IAM, service quotas, and billing at the
> same time — a misconfigured IAM policy in `innovate-dev` cannot reach `innovate-prod` data no
> matter how wrong it is. The alternative, namespace-and-VPC separation in a single account, is
> cheaper to set up but relies on every future IAM policy being written correctly forever. The cost
> is real but small: a handful of extra baseline services per account (~$25/month each) and the
> discipline of managing access centrally through IAM Identity Center.

---

## 2. Structure

- Heading levels: `##` for a top-level section of the final README, `###` for subsections, `####`
  sparingly. **Never `#`** inside a draft — Phase 11 owns the single `#` title.
- Draft files begin directly with their `##` heading. No YAML front matter, no title block.
- Every `##` section opens with **one or two sentences** of orientation before any table or list.
  A section that starts with a bullet has failed.
- Maximum three levels of nesting in any list. Prefer a table over a nested list.
- One blank line before and after every heading, table, code fence, and blockquote.

---

## 3. Markdown conventions

| Element | Rule |
|---|---|
| Line length | Wrap prose at **100 characters**. Tables and links may overrun. |
| Tables | Always a header row and an alignment row. Keep cells short — a cell is not a paragraph. |
| Code fences | Always tagged: ` ```bash `, ` ```yaml `, ` ```hcl `, ` ```json `, ` ```text `, ` ```mermaid `. Never bare ` ``` `. |
| Emphasis | `**bold**` for the first mention of a fixed name or a decision; `*italic*` sparingly; never ALL CAPS for emphasis. |
| Inline code | Every resource name, CIDR, service-API name, file path, flag, and Kubernetes object goes in backticks: `10.30.0.0/16`, `innovate-prod`, `PodDisruptionBudget`. |
| Links | Relative, e.g. `[the network design](#network-design)` or `[HLD](diagrams/01-high-level.md)`. No bare URLs in prose. |
| Callouts | `> **Note.**`, `> **Trade-off.**`, `> **Cost.**`, `> **Day 1 vs. at scale.**`, `> **Security.**` — those five labels only. Max one per subsection. |
| Pillar line | `> **Well-Architected pillars.** Security · Reliability · Cost Optimization` — closes the opening paragraph of every `##` section. Separator is ` · ` (space, middle dot, space). Two to four pillars. |
| Emoji | None. Anywhere. |
| Horizontal rules | `---` between top-level `##` sections only. |
| Lists | `-` for bullets, `1.` for ordered. Never `*`. |
| Numbers | `$850/month`, `35 days`, `99.9 %`, `3 AZs`, `2 vCPU`. Use a thin space before `%` is *not* required — write `99.9%` consistently without a space. |

*(Consistency note: write percentages with no space — `99.9%`, `65%`, `70–90%`.)*

---

## 4. Acronyms

Expand on first use in the final document, then use the acronym: "Availability Zone (AZ)",
"single-page application (SPA)", "high availability (HA)", "disaster recovery (DR)", "recovery point
objective (RPO)", "recovery time objective (RTO)", "service control policy (SCP)", "High-Level
Diagram (HLD)", "Horizontal Pod Autoscaler (HPA)", "identity provider (IdP)".

Because drafts are written independently, **each draft should expand acronyms on its own first use**.
Phase 11 removes the duplicate expansions during assembly. Over-expanding is a cheap fix;
under-expanding is not.

Never expand universally known ones: API, CPU, DNS, HTTP, HTTPS, IP, JSON, SQL, TLS, URL, VPN, YAML.

---

## 5. Naming — copy, never paraphrase

Pull every name from `contract.md`. In particular:

- Accounts: `innovate-prod`, not "the prod account" on first use (use the real name first, then
  prose is fine).
- Services: full AWS name on first use — "Amazon Elastic Kubernetes Service (EKS)", "Amazon Aurora
  PostgreSQL-Compatible Edition", "AWS Web Application Firewall (WAF)" — then the short form.
- The client is **Innovate Inc.** Always with the period. Never "Innovate" alone.
- Write **HLD** (High-Level Diagram). The brief's "HDL" is a typo — do not reproduce it.

---

## 6. Length discipline

Each phase document states a word budget. Treat it as a ceiling with ±20% tolerance. The final
README should land at roughly **13 000–15 500 words** including tables and the decision register — of
which the **body (§0–§10) is 8 000–9 500** and **Appendix B, the nine promoted Architecture Decision
Records (`decision-register.md` §2a), is 2 000–2 500 words of prose, excluding each record's two
tables** (metadata table and options table — consistent with the per-ADR 250-word cap in
`decision-register.md` §1, which excludes the same two tables). (Amended 2026-08-16 — see `STATE.md`'s
*Plan amendments*. The 2026-08-14 amendment had cut these figures to 9 000–12 000 / 4 800–6 500 /
2 000–2 500, but that target did not close arithmetically against the locked outline: three full
compression passes across Phases 11–12 left the assembled document at ≈14 910 words with every
required subsection and table intact, and diminishing returns — 20–100 words saved per pass by the
end — showed the gap was structural, not a trimming problem. Rather than cut required content to
force a fit, the ceiling is raised to match what the locked outline and the nine-ADR appendix actually
cost in words. The outline and its required tables are unchanged.) The body is the part read start to
finish and is deliberately kept to a length a reviewer will actually finish; the register is a
**reference appendix** with an index at the top, read selectively. Keeping those two budgets separate
is what lets the document be both thorough and readable.

**Word-counting method (pinned — two variants for two different purposes; use these exact procedures
everywhere a word count is reported or checked, and do not invent a third):**

1. **Document/section length** (the total-document, body §0–§10, and Executive Summary figures
   above): strip fenced code blocks (` ``` ` to ` ``` `); on every remaining line, delete `|`
   characters but keep the cell text, and drop pure separator rows (`|---|:---:|` and the like)
   entirely; then split on whitespace and count tokens. Table *content* counts — a table is something
   a reader reads — only its Markdown decoration is removed. This reproduces Phase 12's corrected
   figure (≈14 910 total, ≈9 212 for body §0–§10 as it now stands) and resolves the earlier
   disagreement between Phase 11's 9 194 (an uncorrected count that also kept cell text, on
   byte-identical §0–§9 text) and Phase 12's 8 370 (which, on inspection, is not reproducible by
   either variant above and should be treated as superseded, not a third method to match).
2. **Per-ADR 250-word cap** (`decision-register.md` §1): strip fenced code blocks, then drop the
   `### ADR-0NN — Title` heading line and **every entire line that is part of a table** (both the
   metadata table and the options table, header and separator rows included — the cap is explicitly
   "excluding its metadata table and its options table"), then split the remainder on whitespace and
   count tokens. This is deliberately stricter than variant 1: the cap governs prose only, not table
   content. Applying variant 1 to an ADR overcounts it against this cap.

Recount with the matching variant wherever a prior figure is in question; do not average, split the
difference, or introduce a third procedure.

If you are over budget, cut in this order: (1) background explanation of things the reader can look
up, (2) repetition of a point made in another section, (3) code snippets, (4) alternatives you
already rejected in one line elsewhere. **Never** cut a required sub-requirement, a justification, or
a plain-language field to fit — those are the graded content.

---

## 6a. Voice inside an Architecture Decision Record

The ADR template is fixed in [`decision-register.md`](decision-register.md); this is how to *write*
one.

- **Context** — the client's situation, in their terms. "Innovate Inc. has no database administrator
  and expects to grow a hundredfold" beats "the workload requires a relational data store".
- **Options considered** — every row gets a real strength, not a strawman. If an option is genuinely
  reasonable, say so and explain what tipped it. A table of four options where three are obviously
  absurd is worth nothing to a reviewer.
- **Decision** — declarative, specific, and short. Name the service and the configuration.
- **Why this is the right choice for Innovate Inc.** — the field that carries the most weight, and
  the one with its own voice. Rules:
  - Written for a **founder who has never opened the AWS console**.
  - No unexplained acronyms. No AWS product name used as though its meaning were self-evident — if
    you must name one, say what it does in the same sentence.
  - Talk about *consequences to them*: their users' data, their engineers' hours, their monthly bill,
    their ability to ship on a Friday.
  - Name what would have gone wrong with the alternative, concretely.
  - Three to five sentences. Plain words. Short clauses.
  - Test: read it aloud. If a non-technical person would need to ask "what does that mean?" at any
    point, rewrite that clause.
- **Length** — 250 words maximum, excluding the two tables. Shorter is better; a simple decision
  deserves a short record. Padding a thin decision to look substantial is worse than three honest
  sentences.
- **Consequences** — two short lists, *Gains* and *Accepts*. The *Accepts* list must be real. An ADR
  whose downsides are all trivial is an ADR that has not been thought about.
- **Revisit when** — an observable trigger. A number, a threshold, a headcount, an event. Never "as
  needed", "in the future", or "when appropriate".

> **Note.** The ADR and the inline body prose cover the same decision but are written for different
> readers and must not be copy-pasted between each other. See `decision-register.md` §3.

---

## 7. Diagrams (Mermaid)

Rules that keep Mermaid rendering on GitHub instead of showing a red error box:

1. Fence with ` ```mermaid `.
2. Node IDs: alphanumeric + underscore only. `alb_prod`, not `alb-prod` or `ALB (prod)`.
3. **Always quote labels**: `alb_prod["Application Load Balancer"]`. Any label containing
   `(`, `)`, `:`, `,`, `/`, `-`, `%`, `[`, `]`, `{`, `}`, `#`, `&`, or `"` **must** be quoted.
4. Line breaks inside labels: `<br/>` only (self-closing). Never `\n`, never `<br>`.
5. Never use `end` as a node ID or bare in a label — it terminates a `subgraph`.
6. `subgraph` needs an ID and a quoted title: `subgraph vpc_prod["Production VPC 10.30.0.0/16"]`.
   Close every one with `end` on its own line.
7. Declare direction explicitly: `flowchart LR` / `flowchart TB`. Inside a subgraph, `direction TB`.
8. Use `classDef` + `class` for colour. Pick colours that survive both light and dark GitHub themes:
   use light fills with dark strokes and set `color:#111` explicitly on any filled node.
9. Keep it under ~35 nodes. If it needs more, it is two diagrams.
10. Every diagram gets a **legend** and a **one-paragraph caption** beneath it in prose. A diagram no
    one can read without the author present is not a deliverable.

Standard `classDef` palette to reuse across all diagrams:

```text
classDef edge     fill:#FFF3E0,stroke:#E65100,stroke-width:1px,color:#111
classDef compute  fill:#E3F2FD,stroke:#1565C0,stroke-width:1px,color:#111
classDef data     fill:#E8F5E9,stroke:#2E7D32,stroke-width:1px,color:#111
classDef security fill:#FCE4EC,stroke:#AD1457,stroke-width:1px,color:#111
classDef ops      fill:#EDE7F6,stroke:#4527A0,stroke-width:1px,color:#111
classDef external fill:#ECEFF1,stroke:#455A64,stroke-width:1px,color:#111
```

---

## 8. Self-check before you write your completion report

Read your own draft top to bottom and answer these out loud:

- [ ] Does every recommendation say **why**, and name what it beat?
- [ ] Does every `##` section carry a `> **Well-Architected pillars.**` line with 2–4 pillars?
- [ ] Does the `## Decision Records` section exist, with every ADR from your reserved block, in the
      exact template, no fields missing?
- [ ] Could a non-engineer read every **"Why this is the right choice for Innovate Inc."** field and
      understand the decision without asking a question?
- [ ] Does every ADR's *Accepts* list contain something that genuinely hurts?
- [ ] Does every ADR's *Revisit when* name an observable trigger rather than "as needed"?
- [ ] Are all names, CIDRs, and numbers identical to `contract.md`?
- [ ] Is there a single `TODO`, `TBD`, `XXX`, `???`, or empty section? (There must not be.)
- [ ] Does any sentence contain a banned word from §1?
- [ ] Does every `##` section open with prose, not a bullet?
- [ ] Would a founder with no AWS experience follow the argument?
- [ ] Would a principal engineer find anything naive, hand-wavy, or factually wrong?
- [ ] Is it inside the word budget?
