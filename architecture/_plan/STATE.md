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
| 03 | Compute platform — EKS | `done` | 00 | `drafts/03-compute-eks.md` | 011–014 |
| 04 | Containerization & CI/CD | `done` | 00 | `drafts/04-containers-cicd.md` | 015–018 |
| 05 | Database | `todo` | 00 | `drafts/05-database.md` | 019–022 |
| 06 | Security & data protection | `todo` | 00, 01–05 | `drafts/06-security.md` | 023–025 |
| 07 | Observability & operational excellence | `todo` | 00, 03, 05 | `drafts/07-observability.md` | 026–027 |
| 08 | Cost optimization & FinOps | `todo` | 00, 01–07 | `drafts/08-cost.md` | 028–029 |
| 09 | Well-Architected alignment & growth roadmap | `todo` | 01–08 | `drafts/09-wellarchitected-growth.md` | — |
| 10 | Diagrams | `todo` | 01–09 | `../diagrams/01…05` | — |
| 11 | Body assembly | `todo` | 00–10 | `../README.md` §0–§9 | — |
| 12 | Summary, decision register & appendices | `todo` | 11 | `../README.md` complete | collects all |
| 13 | QA, consistency audit & final polish | `todo` | 12 | corrected `../README.md` | — |

**Next phase to run:** `05`

---

## ADR ledger

Filled in by each phase as it completes, so Phase 12 can assemble the register in order and Phase 13
can check for gaps and duplicates. Record the numbers you **actually wrote**.

| Phase | Block (exact) | Numbers written | Titles |
|---|---|---|---|
| 00 | 001–003 | 001, 002, 003 | AWS as the Cloud Provider; Three-Tier Architecture Over Microservices or a Monolith; Managed Services First |
| 01 | 004–006 | 004, 005, 006 | Seven AWS Accounts Rather Than a Single Account; AWS Control Tower Rather Than Hand-Rolled AWS Organizations; IAM Identity Center Rather Than Per-Account IAM Users |
| 02 | 007–010 | 007, 008, 009, 010 | One VPC Per Environment, No Interconnection; Three Availability Zones Rather Than Two; A Secondary CIDR in `100.64.0.0/10` for Pod Addresses; A NAT Gateway Per Availability Zone in Production, One in Non-Production |
| 03 | 011–014 | 011, 012, 013, 014 | Amazon EKS as the Compute Platform; Platform Node Group Plus Karpenter Over Cluster Autoscaler; Graviton-First Spot for the Application Tier; No CPU Limit, Memory Request Equals Limit |
| 04 | 015–018 | 015, 016, 017, 018 | Serving the React SPA from S3 and CloudFront, Not a Container; A Single Central Registry with Promotion by Immutable Digest; GitOps Pull-Based Delivery with Argo CD Over Push-Based CI/CD; Image Signing Verified at Admission |
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

### Phase 03 — Compute platform — EKS
- Completed:      2026-08-14
- Files written:  `_plan/drafts/03-compute-eks.md` (2,144 words body excluding tables, snippets, and
  ADRs; ADR-011 – ADR-014 at 250, 250, 249, and 249 words respectively, excluding both tables, all at
  or under the 250-word cap)
- Word count:     2,144 (acceptance band 1,450–2,150 words per this phase's acceptance criteria;
  phase document's own ~1,800-word target ±20% gives 1,440–2,160 — both satisfied). Drafted at ~2,464,
  trimmed across all seven sections in a fix pass to land inside the band with a small margin, after
  acronym expansions added back from the style pass pushed it back over 2,150 once.
- ADRs written:   ADR-011 … ADR-014
- Pillars tagged: Operational Excellence, Reliability, Security, Cost Optimization, Performance
  Efficiency, Sustainability (all six except none omitted at the section level; five of six appear
  across the section pillar lines — Sustainability appears once, on Node strategy, where Graviton and
  Karpenter consolidation substantively serve it per `well-architected.md`'s own guidance that this is
  the same decision as the Cost Optimization story, not a separate one)
- Key decisions:  Drafted directly (not fanned out) to preserve voice continuity with drafts 00–02,
  then ran three independent read-only verification passes via the Workflow tool (contract fidelity,
  style/mechanics, ADR quality against `rubric.md`), which raised 3 contract findings, 15 style
  findings, and 9 ADR findings, and a fix pass that resolved them. Fixes of note: corrected the ADR
  template's own "Guaranteed QoS" framing — contract.md §6 and this phase's own content spec both
  describe the requests/limits policy as landing pods in `Guaranteed` QoS, but Kubernetes' actual
  semantics require every resource (CPU included) to have a matching limit for `Guaranteed`, and this
  design deliberately sets no CPU limit; the draft states the technically correct `Burstable`
  classification instead, with the accurate reasoning for why memory is still protected under pressure
  (not logged as a contract deviation since it's a factual correction, not a design change — logged
  under Assumptions below for visibility); fixed a banned word ("just") in ADR-012's options table;
  trimmed a 28-line YAML snippet to 24 lines to meet the 25-line cap; backticked every bare `NodePool`
  reference for consistency with every other Kubernetes object kind in the draft; expanded eight
  acronyms on first use (VPC, CIDR, ECS, EC2, IAM, RDS, NAT, SQS, EBS, CSI) that were used before being
  defined; added the missing `karpenter.sh/do-not-disrupt` half of contract §6's "Disruption controls"
  row (only the `PodDisruptionBudget` half was originally covered); corrected several conditional-tense
  ("would") instances to present tense per `style-guide.md` §1; and rewrote each ADR's
  "Why this is the right choice for Innovate Inc." field to gloss every AWS product name and Kubernetes
  term used within that field (EKS, Auto Mode, Kubernetes, Graviton, pod) rather than assuming the
  reader already read the Decision field above, per `decision-register.md` §3's rule that an ADR field
  must be self-contained — this pushed every ADR close to the 250-word cap and required trimming
  Context/Consequences/Cost impact/Revisit when in the same pass to make room.
- Assumptions:    The `Burstable`-not-`Guaranteed` QoS correction (above) is a factual correction to
  this phase's own content spec, not an assumption about an ambiguous requirement — flagged here in
  case Phase 06 or Phase 07 independently assert `Guaranteed` QoS elsewhere and need to be reconciled.
- Deferred:       Image building, container registry, and CI/CD pipeline mechanics are named only as
  forward references (§3.8, §3.9, and "the build pipeline") per this phase's explicit scope boundary;
  Phase 04 designs them. Database connection scaling, read replicas, and Aurora Serverless v2 capacity
  units are named once each in `## Scaling` and cross-referenced to Phase 05, not designed here.
- Contract additions: `_plan/contract.md` §12 — Kubernetes minor-version upgrade SLA, "within 30 days
  of general availability." This number appears in this phase's own instructions
  (`phases/phase-03-compute-eks.md`) but not in `contract.md` itself; logged per contract.md's own rule
  that a genuinely absent value a phase defines must be appended to §12.
- Notes for the next agent: (1) See Cross-phase issues below for two findings: ADR-011's Section field
  citing chapter level (no pre-registered subsection for its content), and an independent word-count
  finding that Phase 02's ADR-007–010 measure over the 250-word cap under the same counting method that
  exactly reproduced Phase 01's self-reported counts — flagged for Phase 13, not fixed here (not this
  phase's file). (2) Phase 06 (security) should keep citing EKS Pod Identity and the platform node
  group's taint as this draft states them — this draft's `## Workload isolation and multi-tenancy`
  section is deliberately short and defers the wider posture to §5 Security and Data Protection rather
  than repeating it. (3) Did not touch the open `§10.7`/`§9.7` issue from Phase 00 or the ADR-007/010
  Section-field issue from Phase 02 — both out of scope here, still open for Phase 13.

### Phase 04 — Containerization & CI/CD
- Completed:      2026-08-14
- Files written:  `_plan/drafts/04-containers-cicd.md` (1,793 words body excluding tables, the one
  code snippet, and ADRs; ADR-015 – ADR-018 at 249, 248, 244, and 248 words respectively, excluding
  both tables, all under the 250-word cap)
- Word count:     1,793 (acceptance band 1,200–1,800; drafted at ~1,900 across two rounds — an
  initial draft, then a fix pass responding to three independent verification agents run via the
  Workflow tool — trimmed to land inside the band with a small margin)
- ADRs written:   ADR-015 … ADR-018
- Pillars tagged: Cost Optimization, Performance Efficiency, Operational Excellence, Security,
  Reliability, Sustainability (five of six pillars across the section's six pillar lines plus the
  `## Decision Records` orientation line, 3–4 per line; Sustainability appears once, added to
  ADR-015 in the fix pass, since `well-architected.md` §1 attributes CloudFront edge caching to
  Sustainability directly and the original draft under-tagged it)
- Key decisions:  Drafted directly (not fanned out) to preserve voice continuity with drafts 00 and
  03, then ran three independent read-only verification passes via the Workflow tool (contract
  fidelity, style/mechanics, ADR quality against `rubric.md`), which raised 10 contract findings, 10
  style findings, and 8 ADR-quality findings, and a fix pass that resolved the substantive ones.
  Fixes of note: the illustrative Dockerfile snippet's runtime stage ran `pip install` inside a
  distroless image, which ships no package manager — a real correctness bug, not a style issue;
  rewrote the snippet to `pip install --prefix=/install` in the builder stage and `COPY --from`
  the resulting tree straight into `/usr/local` in the distroless stage, and corrected the base
  image tag from an invented `gcr.io/distroless/python3-debian12` back to `contract.md` §7's exact
  `gcr.io/distroless/python3`; replaced three prose citations of `contract.md §7` (a planning file
  that does not ship with the deliverable) with the actual ECR image path strings and base-image
  values rendered inline, matching how drafts 00 and 03 cite the deliverable's own section numbers
  rather than the plan; added the missing `> **Well-Architected pillars.**` line to `## Frontend
  deployment path`, the only one of six top-level sections that had shipped without one; corrected
  five instances of banned conditional tense (`would`) and two of future tense (`will`) on rejected
  alternatives and enforcement claims, per `style-guide.md` §1's present-tense rule; removed the
  banned word "just" from `"just in case"`; added three first-person-plural "We" instances to
  recommendation sentences that had zero, matching the modeled voice in `style-guide.md` §1; renamed
  the `## Deployment` heading from "GitOps with Argo CD" to "CI/CD and GitOps" to match the exact
  subsection name `contract.md` §14 pre-registers for `§3.9`; removed an unlocked staging
  load-testing gate from the CI pipeline table that `contract.md` §7's fixed pipeline flow does not
  include (`00-scope.md` §5 also lists load testing as out of scope); restructured ADR-016's options
  table to independently argue "rebuilding per environment" against its own strongest rival — same
  digest, replicated into a per-environment registry — rather than fusing it with the per-environment
  registry option, after a verification pass found the original table never tested the ADR against
  that rival; corrected ADR-015's `Section` field from `§3.8 Container registry` (wrong — that ADR is
  about not containerizing, not about the registry) to the chapter level `§3 Compute Platform`,
  matching the precedent Phases 02 and 03 set for headings with no pre-registered subsection number;
  added the missing "indicative" label and AWS Pricing Calculator pointer to ADR-015's `Cost impact`
  field per `contract.md` §11's mandatory labelling rule, and removed an unlabelled derived "order of
  magnitude" comparison; adjusted ADR-015's and ADR-016's `Requirement` fields (dropped R9 from
  ADR-015 since the ADR's whole point is that no image is built for the SPA; dropped R19 from ADR-016
  and added R23, since R19's owning phases in `brief.md` are 03/05/07 and R23 is this phase's own
  declared scope); and strengthened the *Accepts* fields on ADR-015 and ADR-017, which had named the
  fact of a second mechanism/system without naming why it costs something.
- Assumptions:    The Argo Rollouts canary traffic-weight steps (10% → analysis → 50% → analysis →
  100%) and the multi-arch, distroless-compatible dependency-install pattern in the Dockerfile
  snippet are illustrative choices `contract.md` does not fix; the canary steps are genuinely needed
  by both the body prose and the environment-promotion table, so they are registered in
  `contract.md` §12 rather than left implicit.
- Deferred:       Cluster topology, node groups, and autoscaling are Phase 03's territory and are not
  restated here beyond a cross-reference to §3.3 Node strategy. Database migration mechanics beyond
  the expand/contract pattern and the PreSync hook trigger are cross-referenced to Phase 05, not
  designed here.
- Contract additions: `_plan/contract.md` §12 — Argo Rollouts canary steps, `10% → analysis → 50% →
  analysis → 100%`.
- Notes for the next agent: (1) See Cross-phase issues below for two findings: ADR-015's `Section`
  field citing chapter level (no pre-registered subsection for "What gets containerized"), and the
  `style-guide.md` §5 vs. `contract.md` §13 conflict over whether "Amazon Elastic Kubernetes Service
  (EKS)" or "Amazon EKS" is the correct first-use expansion — both drafts 03 and 04 followed
  style-guide.md's general rule over contract.md's specific terminology lock; flagged for Phase 13,
  not fixed here since it is a pre-existing cross-draft pattern, not a defect unique to this phase.
  (2) Phase 05 (database) should keep citing the expand/contract migration pattern and the Argo CD
  PreSync hook exactly as this draft states them, since `## Deployment — CI/CD and GitOps` names
  Phase 05 as owning the storage side of that same pattern. (3) Did not touch the open `§10.7`/`§9.7`
  issue from Phase 00, the ADR-007/010 or ADR-011 Section-field issues from Phases 02/03, or the
  Phase 02 ADR word-count finding from Phase 03 — all out of scope here, still open for Phase 13.

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
| Phase 03 | `drafts/03-compute-eks.md`, ADR-011 Section field | `contract.md` §14 pre-registers no subsection number for the "Why managed Kubernetes, and why EKS" content (only `§3.3`, `§3.4`, `§3.5`, `§3.8`, `§3.9` are pre-registered for this chapter); ADR-012/013 cite `§3.3` and ADR-014 cites `§3.5`, but ADR-011 cites the chapter level `§3 Compute Platform` instead, matching the precedent Phase 02 set for ADR-007/010. | Phase 11 should assign a subsection number to that heading during assembly and update the ADR Section field to match, if it numbers it. |
| Phase 03 | `drafts/02-network.md`, ADR-007 – ADR-010 word count | A read-only verification pass in this phase, using a word-count method independently validated against Phase 01's self-reported ADR counts (exact match: 248, 243, 250 words), measured Phase 02's four ADRs at 267, 272, 265, and 269 words — each over `decision-register.md`'s 250-word cap — despite Phase 02's completion report stating all four landed within cap after a fix-pass trim. Not fixed here; it is another phase's draft. | Phase 13 should recount ADR-007 – ADR-010 against the 250-word cap (excluding the metadata and options tables) and trim if the finding holds. |
| Phase 04 | `drafts/04-containers-cicd.md`, ADR-015 Section field | `contract.md` §14 pre-registers no subsection number for "What gets containerized" (only `§3.3`, `§3.4`, `§3.5`, `§3.8`, `§3.9` are pre-registered for the Compute Platform chapter); ADR-016 and ADR-018 correctly cite `§3.8 Container registry`, but ADR-015 (the SPA-not-a-container decision) cites the chapter level `§3 Compute Platform` instead, matching the precedent Phases 02 and 03 set for ADR-007/010 and ADR-011. | Phase 11 should assign a subsection number to that heading during assembly and update the ADR Section field to match, if it numbers it. |
| Phase 04 | `drafts/03-compute-eks.md` §1, `drafts/04-containers-cicd.md` §1, both first-use expansions of Amazon EKS | `style-guide.md` §5 gives the general rule "full AWS name on first use... then the short form" with the worked example "Amazon Elastic Kubernetes Service (EKS)"; `contract.md` §13's Terminology table locks the required first-use form as "Amazon EKS (first use), then 'EKS'" and lists the fuller expansion alongside "AWS Kubernetes"/"EKS service" as a "Not" case. Drafts 03 and 04 both follow style-guide.md's general worked example over contract.md's specific lock, consistently with each other. Not fixed here since it is a pre-existing pattern shared by an earlier phase, not a defect unique to this one. | Phase 13 should decide which normative file wins per `AGENT-PROTOCOL.md`'s "this file wins" rule for direct contradictions, and correct both drafts' first-use expansions to match if `contract.md` §13 is the intended authority. |

---

## Deliverable location

The graded deliverable is **`architecture/README.md`**, assembled in Phase 11 (body) and Phase 12
(summary, decision register, appendices). The `architecture/`
directory is owned entirely by this assignment; the Terraform / EKS + Karpenter assignment lives
under `terraform/` and is off-limits to every agent working this plan.
