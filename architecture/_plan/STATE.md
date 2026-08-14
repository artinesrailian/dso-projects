# STATE — progress and handoff log

**This file is the single source of truth for "what has been done".** A fresh agent with no memory
reads this file to answer "which phase is next?". Keep it accurate or the workflow breaks.

Statuses: `todo` → `in-progress` → `done`. Also allowed: `blocked`, `needs-rework`.

**Update this file twice per phase:** claim it (`in-progress`) before you start writing, close it
(`done` + completion report + ADR numbers) before you report to the human.

---

## Phase board

| # | Phase | Status | Depends on | Output | ADR block |
|---|---|---|---|---|---|
| 00 | Pre-flight, scope & three-tier framing | `done` | — | `drafts/00-scope.md` | 001–003 |
| 01 | Cloud environment structure | `done` | 00 | `drafts/01-cloud-environment.md` | 004–006 |
| 02 | Network design | `done` | 00 | `drafts/02-network.md` | 007–010 |
| 03 | Compute platform — EKS | `todo` | 00 | `drafts/03-compute-eks.md` | 011–014 |
| 04 | Containerization & CI/CD | `todo` | 00 | `drafts/04-containers-cicd.md` | 015–018 |
| 05 | Database | `todo` | 00 | `drafts/05-database.md` | 019–022 |
| 06 | Security & data protection | `todo` | 00, 01–05 | `drafts/06-security.md` | 023–025 |
| 07 | Observability & operational excellence | `todo` | 00, 03, 05 | `drafts/07-observability.md` | 026–027 |
| 08 | Cost optimization & FinOps | `todo` | 00, 01–07 | `drafts/08-cost.md` | 028–029 |
| 09 | Well-Architected alignment & growth roadmap | `todo` | 01–08 | `drafts/09-wellarchitected-growth.md` | — |
| 10 | Diagrams | `todo` | 01–09 | `../diagrams/01…05` | — |
| 11 | Body assembly | `todo` | 00–10 | `../README.md` §0–§9 | — |
| 12 | Summary, decision register & appendices | `todo` | 11 | `../README.md` complete | collects all |
| 13 | QA, consistency audit & final polish | `todo` | 12 | corrected `../README.md` | — |

**Next phase to run:** `03`

---

## ADR ledger

Filled in by each phase as it completes, so Phase 12 can assemble the register in order and Phase 13
can check for gaps and duplicates. Record the numbers you **actually wrote**.

| Phase | Block (exact) | Numbers written | Titles |
|---|---|---|---|
| 00 | 001–003 | 001, 002, 003 | AWS as the Cloud Provider; Three-Tier Architecture Over Microservices or a Monolith; Managed Services First |
| 01 | 004–006 | 004, 005, 006 | Seven AWS Accounts Rather Than a Single Account; AWS Control Tower Rather Than Hand-Rolled AWS Organizations; IAM Identity Center Rather Than Per-Account IAM Users |
| 02 | 007–010 | 007, 008, 009, 010 | One VPC Per Environment, No Interconnection; Three Availability Zones Rather Than Two; A Secondary CIDR in `100.64.0.0/10` for Pod Addresses; A NAT Gateway Per Availability Zone in Production, One in Non-Production |
| 03 | 011–014 | — | — |
| 04 | 015–018 | — | — |
| 05 | 019–022 | — | — |
| 06 | 023–025 | — | — |
| 07 | 026–027 | — | — |
| 08 | 028–029 | — | — |

The finished register is **ADR-001 to ADR-029, no gaps**. Counts are exact, not ranges — a phase that
cannot fill its block says so here rather than leaving a silent hole.

---

## Completion reports

> One block per finished phase, appended in completion order. Written for someone who never saw the
> session. Copy the template, fill every field, delete nothing.

### Template

```
### Phase NN — <name>
- Completed:      <date or "session N">
- Files written:  <paths, with word counts>
- Word count:     <n> (budget <n>)
- ADRs written:   ADR-0NN … ADR-0NN
- Pillars tagged: <which Well-Architected pillars this section claims>
- Key decisions:  <2–5 calls you made that the plan did not fully specify>
- Assumptions:    <anything you had to assume; "none" is a valid answer>
- Deferred:       <what you deliberately left to another phase, and which phase>
- Contract additions: <names appended to contract.md §12, or "none">
- Notes for the next agent: <anything non-obvious>
```

<!-- Append completion reports below this line -->

### Phase 00 — Pre-flight, scope & three-tier framing
- Completed:      2026-08-14
- Files written:  `_plan/drafts/00-scope.md` (1,090 words body excluding tables and ADRs; ADR-001 –
  ADR-003, each 245–247 words excluding tables, all under the 250-word cap)
- Word count:     1,090 (acceptance band 750–1,100; drafted at 1,165, trimmed §1/§2/§5 prose and
  ADR-002 to land inside the band with margin)
- ADRs written:   ADR-001 … ADR-003
- Pillars tagged: Operational Excellence, Security, Cost Optimization, Reliability, Performance Efficiency
- Key decisions:  Used "Operational Excellence · Security · Cost Optimization · Reliability" as the
  `## Decision Records` section's pillar line, covering the pillars carried by ADR-001–003 combined;
  kept the GCP discussion in §1 to two sentences per the contract.md cap, with the full argument in
  ADR-001; reproduced the tier table from `contract.md` §1a verbatim (byte-identical, diff-checked)
  in §2; cited ADR-002's Section field as `§0.2 Architecture overview — a three-tier design` and
  ADR-001/003 as `§0 Scope, Assumptions and Design Principles`, both drawn from contract.md §14's
  locked reference table rather than invented.
- Assumptions:    none
- Deferred:       Executive Summary left as the marker only, per this phase's instructions; all
  design content for §1–§9 of the final document is deferred to Phases 01–09.
- Contract additions: none
- Notes for the next agent: `## Decision Records` did not originally carry the required orientation
  paragraph and pillar line — both were added on a round-2 review pass, then independently
  re-verified. §6 Requirement Traceability covers all 28 rows (R1–R28). §3's closing sentence and
  well-architected.md §4 both cite `§10.7` for the accepted-trade-offs table, but contract.md §14's
  locked reference table fixes it at `§9.7 Accepted trade-offs between pillars` — the draft uses
  `§9.7` per contract.md's normative authority; logged below under Cross-phase issues for Phase 13.

### Phase 01 — Cloud environment structure
- Completed:      2026-08-14
- Files written:  `_plan/drafts/01-cloud-environment.md` (1,511 words body excluding tables and
  ADRs; ADR-004 – ADR-006 at 248, 243, and 250 words respectively, excluding both tables, all at or
  under the 250-word cap)
- Word count:     1,511 (acceptance band 1,050–1,550; drafted at 1,577, trimmed "Why multiple
  accounts" and "Account inventory" prose to land inside the band with margin)
- ADRs written:   ADR-004 … ADR-006
- Pillars tagged: Security, Reliability, Operational Excellence (this phase's three ADRs and seven
  sections draw only on these three pillars — matches the §1 attribution in `well-architected.md`
  §1's OPS/SEC/REL demand tables, which are the only pillars that table maps to this chapter;
  Cost Optimization is discussed as a trade-off the structure costs, not one it serves, consistent
  with `well-architected.md` §3's own framing of "seven accounts" as leaning toward Security/
  Reliability at the expense of Cost Optimization/Operational Excellence)
- Key decisions:  Drafted the full section set and all three ADRs directly (not via subagent
  fan-out) to preserve voice continuity with `00-scope.md` and contract fidelity on the single
  shared account table; then ran three independent read-only verification passes (contract
  fidelity, style/mechanics, ADR quality against rubric.md) via the Workflow tool and fixed every
  finding they raised. Fixes included: naming the AWS Organization `innovate-inc` explicitly (was
  present in `contract.md` §4 but never stated in the draft); removing a derived "$100–240/month"
  figure in ADR-004 that multiplied the legitimate `well-architected.md` §3 figure ($25–60/month
  per account) in a way `contract.md` §11's "do not derive new figures" rule reads as prohibited,
  replaced with qualitative marginal-cost reasoning; de-duplicating ADR-004's options table from the
  inline body prose per `decision-register.md` §3's explicit ban and this phase document's own
  instruction for that exact ADR; making ADR-004's Decision field self-contained (removed a
  positional "listed in the inventory above" reference, since Phase 12 reassembles ADRs into
  Appendix B out of body order); shortening ADR-006's title from 9 to 8 words to satisfy
  `decision-register.md` §1's template cap; correcting eight future/conditional-tense instances
  ("will"/"would") to present tense per `style-guide.md` §1; and adding first-person-plural "We"
  framing to the recommendation-bearing sentences (Recommendation in one line, the "Why multiple
  accounts" opening, and all three ADR Decision fields), matching `style-guide.md` §1's explicit
  rule, though `00-scope.md` itself uses "We" only once — noted as a judgment call below.
- Assumptions:    none
- Deferred:       VPC/subnet design is Phase 02's; this draft stays at the account/identity layer
  per this phase document's "Common failure modes" table. Application-tier detail (Kubernetes
  namespaces, node groups) is named only as a rejected alternative to account separation, not
  designed here.
- Contract additions: none
- Notes for the next agent: (1) This draft now uses first-person-plural "We" in five places
  (Recommendation in one line; "Why multiple accounts" opening; ADR-004/005/006 Decision fields) to
  satisfy `style-guide.md` §1's literal rule, which is more than `00-scope.md`'s single instance —
  both are defensible readings of the style guide; Phase 11 should pick one density and normalize
  across all ten drafts during assembly rather than treating either as the house style by default.
  (2) The `AGENT-PROTOCOL.md` §1 working-boundary path (`/home/artin/personal/git/opsfleet/
  architecture/`) does not match this repository's actual path
  (`/home/artin/personal/git/dso-projects/architecture/`) — treated as a stale path artifact from a
  prior repo name, not a scope question; the relative boundary ("stay inside `architecture/`") is
  what was honored. (3) The account inventory table's locked Purpose text for `innovate-shared-services`
  starts with the bare acronym "ECR"; since that text must be reproduced verbatim per this phase's
  acceptance criteria, the acronym is instead expanded at its first *prose* occurrence, one paragraph
  below the table, rather than inside the table itself. (4) Did not touch the `§10.7`/`§9.7`
  cross-phase issue Phase 00 logged — out of this phase's scope, still open for Phase 13.

### Phase 02 — Network design
- Completed:      2026-08-14
- Files written:  `_plan/drafts/02-network.md` (1,896 words body excluding tables and ADRs;
  ADR-007 – ADR-010 all within decision-register.md §2's 250-word cap after a fix-pass trim)
- Word count:     1,896 (acceptance band 1,300–1,900; drafted at ~1,960–2,006 depending on counting
  method, trimmed during the fix pass to land inside the band without cutting a required
  sub-requirement, justification, or plain-language field)
- ADRs written:   ADR-007 … ADR-010
- Pillars tagged: Security, Reliability, Performance Efficiency, Cost Optimization, Operational
  Excellence (five of six pillars across the section's nine `##` headings, 2–4 per heading;
  Sustainability not tagged — not substantively served by this chapter)
- Key decisions:  Drafted directly (not fanned out) to preserve voice continuity, then ran three
  independent read-only verification passes via the Workflow tool (contract fidelity, style/
  mechanics, ADR quality against rubric.md), which raised 18 findings (5 contract, 9 style, 4 ADR),
  and a fix pass that resolved them. Fixes of note: removed two invented/unlabelled cost figures — a
  per-unit NAT Gateway price and a Shield Advanced "$3,000/month" figure — that violated
  `contract.md` §11's no-derived-figures rule, replacing them with the contract's aggregated
  indicative NAT figure and a Pricing Calculator pointer; removed a fifth AWS WAF managed rule group
  ("anonymous IP") not present in `contract.md` §9's fixed list of four; corrected a dropped "pod"
  in the RDS Proxy security-group description (contract §8 says "node/pod SG"); fixed a
  self-contradictory claim that every security group in the request path "references another
  security group" — the ALB's own inbound rule is sourced from the CloudFront managed prefix list,
  not a security group, so the claim was rescoped and the one exception named; expanded five
  under-expanded acronyms (SG, HSTS, CSP, XSS, DDoS) and three acronyms used before their first
  prose expansion (VPC, ALB, CIDR); removed R19 and R20 from ADR-008/009/010's Requirement fields
  after checking `brief.md` directly — those requirements belong to phases 03/05/07/09, not 02, only
  R3/R4 are this phase's; and registered the VPC CNI `/28` prefix-delegation block size in
  `contract.md` §12, since `contract.md` §6 fixes prefix delegation as a feature but not its block
  size, and the number is needed to explain pod density in `## IP address plan`.
- Assumptions:    Phrased the EKS API public-endpoint restriction as covering CI/CD egress addresses
  and, conditionally, "where Innovate Inc. operates one, a corporate VPN range" — consistent with
  draft 00's assumption of no confirmed hybrid/on-prem connectivity requirement.
- Deferred:       Service mesh mTLS, AWS Network Firewall, Shield Advanced, PrivateLink to partner
  services, and IPv6 are named in `## What is deliberately not here` with their revisit triggers, not
  designed further. Hybrid/partner connectivity via a Transit Gateway in `innovate-network` is named
  as the future answer, not designed. An indicative cost line for interface VPC endpoint spend (16
  endpoints × 3 AZs) is explicitly not derived here — `contract.md` §11's cost table has no such line
  and one wasn't fabricated — flagged below for Phase 08.
- Contract additions: `_plan/contract.md` §12 — VPC CNI prefix-delegation block size, `/28` per ENI.
- Notes for the next agent: (1) Phase 08 (Cost Optimization) should add an indicative interface-VPC-
  endpoint cost line to its cost table; this draft deliberately did not derive one. (2) Phases 03
  (compute) and 06 (security) should keep pods governed by the node's security group plus
  `NetworkPolicy`, not an individually assigned per-pod security group — this draft was written to
  avoid implying EKS `SecurityGroupPolicy`/trunk-ENI per-pod SGs, a feature `contract.md` §6 does not
  adopt. (3) ADR-007 and ADR-010 cite their Section field at chapter level (`§2 Network Design`)
  rather than a subsection, because `contract.md` §14 only pre-registers `§2.2` and `§2.4` for this
  chapter and no subsection number yet exists for "Connectivity between environments" or "Routing and
  internet egress" — logged below under Cross-phase issues for Phase 11 to resolve once it numbers
  those headings. (4) Did not touch the open `§10.7`/`§9.7` cross-phase issue from Phase 00 — out of
  scope here, still open for Phase 13.

---

## Open questions

> Things a phase agent could not resolve and did not want to silently decide. The human answers
> these; Phase 13 checks none are outstanding before the deliverable is called finished.

| Raised by | Question | Status | Answer |
|---|---|---|---|
| — | — | — | — |

---

## Cross-phase issues

> Contradictions, duplications, or gaps spotted between drafts. **Do not fix another phase's draft
> yourself** — log it here. Phase 13 owns resolution.

| Spotted by | Where | Issue | Resolved in |
|---|---|---|---|
| Phase 00 | `phases/phase-00-preflight-and-scope.md` §3 closing line and `well-architected.md` §4 both say the accepted-trade-offs table lives at `§10.7`, but `contract.md` §14's locked section map and reference table fix it at `§9.7 Accepted trade-offs between pillars` (there is no `§10.7` — `§10` is `Summary of Key Decisions`). `00-scope.md` §3 cites `§9.7`, following contract.md as normative. | Phase 13 should correct the stale `§10.7` references in the two source docs, or confirm `§9.7` is the intended target. |
| Phase 02 | `drafts/02-network.md`, ADR-007 and ADR-010 Section fields | `contract.md` §14 pre-registers only `§2.2` and `§2.4` for the Network Design chapter; ADR-008/009 cite `§2.2`, but ADR-007 ("Connectivity between environments...") and ADR-010 ("Routing and internet egress") have no pre-registered subsection number, so both cite the chapter level `§2 Network Design` instead. | Phase 11 should assign subsection numbers to those two headings during assembly and update the two ADR Section fields to match, if it numbers them. |
| Phase 02 | `contract.md` §11 cost table | No line item exists for interface VPC endpoint spend (16 endpoints × 3 AZs); `drafts/02-network.md` describes the per-endpoint charge qualitatively rather than deriving a total, per §11's no-derived-figures rule. | Phase 08 (Cost optimization) should add an indicative line item. |

---

## Deliverable location

The graded deliverable is **`architecture/README.md`**, assembled in Phase 11 (body) and Phase 12
(summary, decision register, appendices). The `architecture/`
directory is owned entirely by this assignment; the Terraform / EKS + Karpenter assignment lives
under `terraform/` and is off-limits to every agent working this plan.
