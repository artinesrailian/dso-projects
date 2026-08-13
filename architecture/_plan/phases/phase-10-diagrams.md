# Phase 10 — Diagrams

> Answers requirements **R18** ("at least one HDL") and **R28** (three-tier architecture made
> visible). The brief's "HDL" is a typo for HLD; write **HLD** everywhere.
> Read [`../AGENT-PROTOCOL.md`](../AGENT-PROTOCOL.md), [`../contract.md`](../contract.md), and
> [`../style-guide.md`](../style-guide.md) §7 (Mermaid rules) first.

---

## Goal

Produce five Mermaid diagrams that a reviewer can read without the author present. The first is the
required High-Level Diagram and it is the single most-looked-at artifact in the deliverable — it is
what a reviewer sees before they read a word, and it must make the **three-tier structure** visible
at a glance.

**A Mermaid block that does not parse renders as a red error box on GitHub and fails the deliverable
outright** (`rubric.md` §4, fatal). Syntax correctness is not a nice-to-have in this phase; it is the
phase.

---

## Dependencies

Phases **01–09** must all be `done`. The diagrams depict what the drafts actually say, so they come
after the content, not before.

## Inputs

| File | Use it for |
|---|---|
| `_plan/contract.md` §1a | **The three tiers** — the organising principle of diagram 1 |
| `_plan/contract.md` §4, §5, §6, §7, §8 | Every entity name, CIDR, account name, cluster name |
| `_plan/style-guide.md` §7 | The Mermaid rules and the `classDef` palette — non-negotiable |
| `_plan/drafts/01`–`09` | What to depict. **Every box must correspond to something a draft describes.** |

## Files you own

- `../diagrams/01-high-level.md` — create (the required HLD)
- `../diagrams/02-account-topology.md` — create
- `../diagrams/03-network-topology.md` — create
- `../diagrams/04-cicd-pipeline.md` — create
- `../diagrams/05-request-flow.md` — create
- `_plan/STATE.md` — update

Note the path: `architecture/diagrams/`, **not** `_plan/diagrams/`.

## Word budget

**~700 words total** across all five files — these are diagrams with captions, not essays.

---

## File format — identical for all five

````markdown
## <Diagram title>

<One paragraph, 40–80 words: what this diagram shows, what to look at first, and the single design
point it exists to make.>

```mermaid
<the diagram>
```

**Legend**

| Element | Meaning |
|---|---|
| … | … |

> **Note.** <One line naming what is deliberately simplified or omitted.>
````

Every diagram gets all four parts. A diagram with no caption and no legend is not finished.

---

## Hard Mermaid rules (violating any of these breaks the render)

1. Fence with ` ```mermaid `. Nothing else on the fence line.
2. Node IDs: `[a-zA-Z0-9_]` only. `alb_prod` — never `alb-prod`, never `ALB (prod)`.
3. **Quote every label.** `cf["Amazon CloudFront"]`. Any label containing `(`, `)`, `:`, `,`, `/`,
   `-`, `.`, `%`, `[`, `]`, `{`, `}`, `#`, `&`, `+`, or `"` **must** be quoted. Quote them all and
   the question never arises.
4. Line breaks inside a label: `<br/>` only. Never `\n`, never `<br>`.
5. Never use `end` as a node ID, and never let a label start with the word `end`.
6. `subgraph` requires an ID and a quoted title, and a matching `end` on its own line:
   `subgraph vpc_prod["Production VPC 10.30.0.0/16"]` … `end`.
7. Declare direction on the first line (`flowchart LR` / `flowchart TB`) and inside each subgraph
   (`direction TB`).
8. Edge labels are quoted too: `a -->|"pull by digest"| b`.
9. `classDef` lines go at the **bottom**, after all nodes and edges, followed by `class` assignments.
10. Keep each diagram under ~35 nodes. If it needs more, it is two diagrams.
11. No experimental syntax: no `flowchart-elk`, no `architecture-beta`, no icon packs, no
    `%%{init}%%` theme directives. Plain `flowchart` and `sequenceDiagram` only.

Use exactly the `classDef` palette from `style-guide.md` §7 in every diagram, so the five read as one
set. In diagram 1, use the palette **to encode the tiers** — presentation nodes in one class,
application nodes in another, data nodes in a third — and say so in the legend.

---

## Diagram 1 — `01-high-level.md` — **THE HLD** (required)

`flowchart LR`. The whole system on one page, **organised so the three tiers are visually obvious**.
This is the diagram embedded near the top of the README, so it must be legible at a glance.

**Must contain:** end users; Route 53; CloudFront with WAF and Shield; the S3 SPA bucket; the
`innovate-prod` account boundary; the production VPC labelled `10.30.0.0/16` with three Availability
Zones noted; the ALB in public subnets; the EKS cluster with the API and worker pods in their named
namespaces; RDS Proxy; Aurora PostgreSQL writer and reader; the `innovate-shared-services` account
with ECR and the CI pipeline; the GitOps repository and the Argo CD sync arrow; and the DR region as
a single node.

**Must not contain:** every VPC endpoint, every add-on, subnet CIDRs (that is diagram 3), or the
non-production accounts.

The tiers must be readable from the diagram itself — through the `classDef` colouring plus the
legend, and, where it does not make the layout worse, through a `subgraph` per tier.

Start from this skeleton — it parses. Extend it; do not restructure it.

> **Note.** The skeleton below is fenced as ` ```text ` so it does not render inside this plan
> document. In your output file it **must** be fenced as ` ```mermaid `. Change the fence.

```text
flowchart LR
  user["End users<br/>browser"]
  dns["Amazon Route 53"]
  cf["Amazon CloudFront<br/>AWS WAF + Shield"]
  spa["Amazon S3<br/>React SPA bundle"]

  subgraph shared["AWS account innovate-shared-services"]
    direction TB
    ci["GitHub Actions CI<br/>OIDC, build, scan, sign"]
    ecr["Amazon ECR<br/>innovate/api, innovate/worker"]
    gitops["GitOps repository<br/>Kustomize overlays"]
  end

  subgraph prod["AWS account innovate-prod"]
    direction TB
    subgraph vpc["VPC innovate-prod-vpc-use1 10.30.0.0/16, 3 AZs"]
      direction TB
      alb["Application Load Balancer<br/>public subnets"]
      subgraph eks["Amazon EKS innovate-prod-eks-use1"]
        direction TB
        argocd["Argo CD"]
        api["Flask API pods<br/>ns innovate-api"]
        worker["Worker pods<br/>ns innovate-jobs"]
      end
      proxy["Amazon RDS Proxy"]
      db[("Aurora PostgreSQL<br/>writer + reader, Multi-AZ")]
    end
  end

  dr["DR region us-west-2<br/>Aurora Global Database<br/>pilot light"]

  user --> dns
  dns --> cf
  cf -->|"static assets"| spa
  cf -->|"/api/*"| alb
  alb --> api
  api --> proxy
  worker --> proxy
  proxy --> db
  db -.->|"replication under 1s"| dr
  ci -->|"push signed image"| ecr
  ci -->|"commit image digest"| gitops
  gitops -.->|"pull-based sync"| argocd
  ecr -.->|"pull by digest"| api

  classDef edge fill:#FFF3E0,stroke:#E65100,stroke-width:1px,color:#111
  classDef compute fill:#E3F2FD,stroke:#1565C0,stroke-width:1px,color:#111
  classDef data fill:#E8F5E9,stroke:#2E7D32,stroke-width:1px,color:#111
  classDef ops fill:#EDE7F6,stroke:#4527A0,stroke-width:1px,color:#111
  classDef external fill:#ECEFF1,stroke:#455A64,stroke-width:1px,color:#111
  class user,dns external
  class cf,spa,alb edge
  class api,worker,argocd compute
  class proxy,db,dr data
  class ci,ecr,gitops ops
```

In the legend, map the classes to the tiers explicitly: `edge` = presentation tier, `compute` =
application tier, `data` = data tier, `ops` = delivery pipeline, `external` = outside the system.

---

## Diagram 2 — `02-account-topology.md`

`flowchart TB`. The AWS Organization: root, the four organizational units from `contract.md` §4, and
all nine accounts (mark the two future ones with `<br/>(future)`). Show IAM Identity Center in the
management account with a dashed edge to the workload accounts, and dashed edges from each workload
account to the Log Archive and Security Tooling accounts to represent log delivery and finding
aggregation.

Colour by role: management and security accounts in the `security` class, infrastructure in `ops`,
workloads in `compute`. The caption makes the point that service control policies attach to the
organizational unit, not the account — which is why moving an account between units changes what it
is allowed to do.

---

## Diagram 3 — `03-network-topology.md`

`flowchart TB`. One production VPC in detail, with the **three subnet tiers visibly mapped to the
three application tiers**. Three AZ subgraphs, each containing the four subnet tiers with their
**exact CIDRs from `contract.md` §5**. Show the Internet Gateway, one NAT Gateway per AZ, the ALB
spanning the public subnets, nodes in the app subnets, Aurora writer in AZ-a's data subnet and reader
in AZ-b's, and a VPC endpoints node in the endpoint subnets.

**Every CIDR in this diagram is checked against `contract.md` §5 character by character during Phase
12.** If the diagram and the table disagree, the deliverable is inconsistent.

Keep it under 35 nodes: show all three AZs but do not draw every endpoint individually — one
"Interface VPC endpoints" node per AZ is enough.

---

## Diagram 4 — `04-cicd-pipeline.md`

`flowchart LR`. Left to right: developer → pull request (with the gate list as one node) → merge →
build, scan, sign → ECR → GitOps commit → Argo CD → dev → integration tests → staging → **manual
approval** (make this node visually distinct with the `security` class) → production canary via Argo
Rollouts → an automatic rollback edge on SLO breach.

Show the Kyverno admission check as a gate node between Argo CD and the running pods — it is the
control that makes the image-signing story real, and it is easy to miss in prose. Use the `security`
class for every gate node so a reader can see, at a glance, how many refusal points sit between a
commit and production.

---

## Diagram 5 — `05-request-flow.md`

`sequenceDiagram`. One authenticated API request end to end, crossing all three tiers: Browser →
CloudFront → WAF evaluation → ALB → Flask pod → RDS Proxy → Aurora → back. Include the TLS
termination points as notes, and show a CloudFront cache hit for a static asset as a short
alternative path so the presentation tier's independence is visible.

`sequenceDiagram` syntax rules: `participant id as "Display Name"`, arrows `->>` (solid) and `-->>`
(dashed return), `Note over a,b: text`, `alt` / `else` / `end` for branches. Do not combine
`autonumber` with `par` blocks. Keep it to eight participants or fewer.

---

## Verification — mandatory before you mark this phase done

You cannot render Mermaid here, so verify by **structured inspection**. For each of the five
diagrams, check every item and state in your completion report that you did:

- [ ] Fence is exactly ` ```mermaid ` and is closed.
- [ ] First line declares a diagram type and direction.
- [ ] Count of `subgraph` keywords equals the count of standalone `end` lines that close them
      (count them; do not assume).
- [ ] Every node ID matches `[a-zA-Z0-9_]+` — no hyphens, no dots, no spaces.
- [ ] Every node label and every edge label is inside double quotes.
- [ ] No `\n` and no bare `<br>`; only `<br/>`.
- [ ] No node ID is `end`, `graph`, `subgraph`, `class`, `click`, `style`, or `direction`.
- [ ] Every `class` statement references node IDs that exist and `classDef` names that are defined.
- [ ] Every arrow's source and target IDs are declared somewhere in the diagram.
- [ ] No `%%{init}%%`, no `flowchart-elk`, no icon syntax.
- [ ] Every name, CIDR, and account in the diagram appears identically in `contract.md`.

---

## Acceptance criteria

- [ ] Five files exist at `architecture/diagrams/01-…` through `05-…`.
- [ ] Each has a title, a 40–80 word caption, one Mermaid block, a legend table, and a
      `> **Note.**` on what is simplified.
- [ ] The full verification checklist above was walked for **each** diagram, and the completion
      report says so explicitly.
- [ ] Diagram 1 contains every element listed for it, makes the three tiers visually obvious, and
      would be legible printed on one page.
- [ ] Diagram 1's legend maps the colour classes to the three tiers explicitly.
- [ ] Diagram 3's CIDRs match `contract.md` §5 exactly, and the subnet tiers are mapped to the
      application tiers.
- [ ] Diagram 4 marks every security gate with the `security` class.
- [ ] Diagram 5 crosses all three tiers and shows a cache-hit alternative path.
- [ ] All five use the same `classDef` palette from `style-guide.md` §7.
- [ ] No diagram exceeds ~35 nodes.
- [ ] The word "HDL" appears nowhere; the word "HLD" is used.
- [ ] No `TODO`/`TBD`; no emoji; no banned words.
- [ ] `STATE.md` updated.

## Common failure modes

| Failure | Avoid it by |
|---|---|
| Unquoted label containing `(`, `.`, or `/` | Quote every label without exception. |
| Hyphenated node IDs (`rds-proxy`) | Underscores only. The display name goes in the quoted label. |
| A `subgraph` without its `end` | Count them before you finish. |
| A diagram that contradicts a draft | Diagrams follow the drafts and the contract, never the reverse. |
| An HLD where the three tiers are invisible | Colour by tier and say so in the legend. It is a graded requirement. |
| Cramming the whole architecture into diagram 1 | Diagram 1 is the shape of the system. Detail lives in 2–5. |
| Skipping the legend | Half the value of a diagram is whether it can be read alone. |
| A themed `%%{init}%%` block for nicer colours | Not portable. `classDef` only. |

---

## Agent prompt

```text
You are executing Phase 10 of the Innovate Inc. architecture design plan: Diagrams.

Working directory boundary: architecture/ ONLY. Never read or write terraform/, .claude/, or
anything above architecture/. terraform/ belongs to a different assignment that another agent
may be editing right now.

Read in full, in order:
  architecture/_plan/AGENT-PROTOCOL.md
  architecture/_plan/contract.md                (§1a three tiers, §4, §5, §6, §7, §8)
  architecture/_plan/style-guide.md             (§7 Mermaid rules are mandatory)
  architecture/_plan/phases/phase-10-diagrams.md
  architecture/_plan/drafts/01-cloud-environment.md through drafts/09-wellarchitected-growth.md

Do not read any other file. No repository-wide searches. No aws/kubectl/terraform/docker/helm.
No web browsing.

Create five files in architecture/diagrams/ (NOT in _plan/), following the per-file format and
per-diagram specification exactly.

Diagram 1 is the required High-Level Diagram and must make the three-tier structure
(presentation / application / data) visually obvious through the classDef colouring, with the
legend mapping colours to tiers explicitly.

A Mermaid block that does not parse renders as a red error box on GitHub and fails the whole
deliverable. Before marking this phase done, walk the eleven-item verification checklist in the
phase document for EACH of the five diagrams, and state in your completion report that you did.

Then verify every acceptance criterion, fix what fails, update STATE.md, report, and STOP.
Do not begin Phase 11.
```
