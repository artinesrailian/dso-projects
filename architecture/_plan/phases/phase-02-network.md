# Phase 02 — Network Design

> Answers **assessment area 2** and requirements **R3, R4**.
> Read [`../AGENT-PROTOCOL.md`](../AGENT-PROTOCOL.md), [`../brief.md`](../brief.md),
> [`../contract.md`](../contract.md), [`../decision-register.md`](../decision-register.md),
> [`../well-architected.md`](../well-architected.md), and [`../style-guide.md`](../style-guide.md)
> first.

---

## Goal

Two questions, two halves. **First**: design the VPC — CIDR allocation, subnet tiers, Availability
Zone spread, routing, internet egress, and private connectivity to AWS services. **Second**: explain
how the network is secured — layer by layer, from the CloudFront edge down to the database security
group, with the specific control named at each layer.

The brief lists these as two sub-bullets of one area, so they belong in one section with two clearly
separated halves. Do not merge them into a soup.

---

## Dependencies

Phase 00 must be `done`. (Phase 01 is not required, but read `drafts/01-cloud-environment.md` if it
exists so you can reference account names naturally.)

## Inputs

| File | Use it for |
|---|---|
| `_plan/decision-register.md` | ADR template and your reserved ADR block |
| `_plan/well-architected.md` | Pillar tagging convention and what each pillar demands |
| `_plan/contract.md` **§5** | The locked CIDR plan, subnet table, endpoint list — **copy exactly** |
| `_plan/contract.md` §3, §4, §9 | Regions, account names, edge/detection controls |
| `_plan/drafts/00-scope.md`, `_plan/drafts/01-cloud-environment.md` | Context (read only) |
| `_plan/rubric.md` §3 probes 2, 9 | Depth probes this section must survive |

## Files you own

- `_plan/drafts/02-network.md` — create
- `_plan/STATE.md` — update
- `_plan/contract.md` §12 — append only if you invent a name

## Word budget

**~1 600 words** (±20%) for the body, excluding tables, plus **4 ADRs** (ADR-007 – ADR-010). The
subnet and security tables carry a lot of the load.

## Two requirements that apply to every section you write

1. **Pillar line.** Every `##` section closes its opening paragraph with
   `> **Well-Architected pillars.** …` carrying 2–4 pillars. See `well-architected.md` §2.
2. **Justification.** Inline, every decision follows decision → why → what it beat → what it costs.
   The significant ones are recorded again as ADRs at the end of the draft. See
   `decision-register.md`.

## The three-tier mapping is this phase's spine

`contract.md` §1a defines a three-tier architecture; the subnet tiers in `contract.md` §5 map to it
one-to-one, and this is the section where that becomes visible. State the mapping explicitly and use
it as the organising idea for both halves:

| Application tier | Network placement | Reachable from |
|---|---|---|
| Presentation | CloudFront edge, S3 origin — outside the VPC entirely | The internet |
| Application | Private — App subnets; pod IPs from the secondary CIDR | The ALB only, which accepts only CloudFront |
| Data | Private — Data subnets | The application tier only, via RDS Proxy |

The security half of this section is then not a list of products — it is the demonstration that each
of those three arrows is enforced by a mechanism rather than by convention.

---

## Content specification

### `## Network design principles` (~120 words)

Four or five sentences, not a list of platitudes. The real ones for this design:

- One VPC per environment per region; **no** connectivity between environments — isolation is the
  default and a peering connection would have to be justified, not assumed.
- Three Availability Zones everywhere in production, because two AZs means losing 50% of capacity on
  a single AZ failure and three means losing 33%.
- Nothing that holds data or runs code is reachable from the internet. The only things in a public
  subnet are load balancers and NAT Gateways.
- Address space is allocated once, generously, from a plan — because re-CIDRing a live VPC is close
  to impossible and CIDR exhaustion is the single most common reason a Kubernetes platform has to be
  rebuilt.

### `## IP address plan` (~200 words + table)

- State the org supernet `10.0.0.0/8` and the pod overlay range `100.64.0.0/10` (RFC 6598).
- Reproduce the **environment → VPC → CIDR** table from `contract.md` §5 exactly, all six rows
  including the reserved EU range.
- Explain the two decisions that a reviewer will test:
  1. **Why /16 per VPC** — headroom for pods, future subnet tiers, and a second region, without ever
     needing to add a non-contiguous CIDR later.
  2. **Why a secondary CIDR in `100.64.0.0/10` for pods.** This is the highest-value paragraph in the
     section. With the Amazon VPC CNI every pod gets a real VPC IP address. At a few hundred users
     that is invisible; at scale a `/16` of routable RFC 1918 space disappears fast, and re-addressing
     is not an option. Carrier-grade NAT space is not routable on the internet and will never collide
     with a partner or on-premises network, so it is safe to burn tens of thousands of addresses on
     pods. Combined with **prefix delegation** on the CNI (which assigns /28 prefixes to ENIs instead
     of individual IPs), this raises pod density per node substantially and removes the "pods pending
     because the node ran out of ENIs" failure mode.
  - This is rubric probe 2. Answer it here, completely.

### `## VPC and subnet architecture` (~250 words + the big table)

- Reproduce the production subnet table from `contract.md` §5 **exactly** — every CIDR, every AZ,
  every size, every usable-IP count. This table is the literal answer to "design the VPC
  architecture" and its precision is the evidence.
- One paragraph per tier explaining *why that tier exists and why it is that size*:
  - **Public /24 ×3:** ALB and NAT ENIs only. Small on purpose — a large public subnet invites
    someone to put something in it.
  - **Private App /20 ×3:** EKS node ENIs. 4 091 usable addresses per AZ.
  - **Private Data /24 ×3:** Aurora and RDS Proxy. Deliberately tiny and separately route-tabled so a
    data-tier subnet can never accidentally get a default route to the internet.
  - **Private Endpoints /24 ×3:** interface endpoint ENIs, isolated so endpoint security groups are
    easy to reason about.
  - **Pods /18 ×3 (secondary CIDR):** 16 379 addresses per AZ.
  - **Reserved /17:** untouched, on purpose.
- State that non-production uses the same shape at the same offsets inside its own /16 — identical
  topology means a staging test is a real test.

### `## Routing and internet egress` (~200 words)

- One public route table (`0.0.0.0/0` → Internet Gateway); **one private route table per AZ**
  (`0.0.0.0/0` → that AZ's NAT Gateway). Explain both reasons: an AZ's traffic never crosses to
  another AZ's NAT (cross-AZ data charges), and a NAT failure is contained to one AZ.
- Three NAT Gateways in production, one in each non-production VPC.
  > **Cost.** NAT Gateways are one of the largest line items at low traffic — roughly $32/month each
  > plus $0.045 per GB processed. Three in production is an availability decision; one in development
  > is a cost decision. Say both out loud.
- Nodes have no public IPs (`map_public_ip_on_launch = false`); inbound internet traffic reaches
  workloads only through CloudFront → ALB.
- **VPC endpoints.** List the gateway endpoints (S3, DynamoDB — free) and the interface endpoints
  from `contract.md` §5. Three reasons, all of them real: image pulls and control-plane chatter stop
  traversing the NAT Gateway (cost), traffic stays on the AWS network (latency and reliability), and
  the workload subnets could in principle run with no internet egress at all (security). Note that
  interface endpoints cost ~$7/month each per AZ, so the list is chosen, not exhaustive.

### `## Connectivity between environments and to AWS services` (~100 words)

- No VPC peering, no Transit Gateway, no shared services VPC connectivity on day 1. Environments are
  islands.
- Cross-account ECR pulls go over the ECR interface endpoint and are authorised by a repository
  policy, not by network reachability — a good example of "identity is the perimeter".
- When hybrid or partner connectivity eventually arrives, the answer is a Transit Gateway in a
  dedicated network account (`contract.md` §4, account 9), and the CIDR plan already leaves room.

---

## Second half — network security

### `## Securing the network` (~150 words intro + the layer table)

Open with the framing: the network is one layer of defence among several, and the design assumes the
perimeter will eventually be breached. Then a table with a row per layer — this table is the spine of
the answer:

| Layer | Control | What it stops |
|---|---|---|
| Edge / DDoS | AWS Shield Standard (always on); Shield Advanced deferred | Volumetric L3/L4 attacks |
| Edge / application | AWS WAF on CloudFront: AWS managed rule groups (Common, Known Bad Inputs, SQLi, IP reputation, anonymous IP) + rate-based rule at 2 000 requests / 5 min / IP | SQL injection, XSS, scanners, credential stuffing, scraping |
| Edge / TLS | ACM certificate on CloudFront, TLS 1.2+ only, HSTS and a response-headers policy (CSP, X-Content-Type-Options, Referrer-Policy) | Downgrade, mixed content, some XSS classes |
| Origin protection | CloudFront origin access control on the S3 bucket; ALB accepts traffic only from the CloudFront managed prefix list plus a shared secret header | Origin bypass — hitting the ALB directly to skip WAF |
| Subnet | Network ACLs as a coarse stateless backstop: data-tier NACL denies all traffic that is not 5432 from the app tier | Route-table or SG misconfiguration, lateral movement |
| Instance | Security groups, default-deny, **referencing other security groups rather than CIDRs** | Broad CIDR allows that silently widen over time |
| Pod | Kubernetes NetworkPolicy, default-deny ingress and egress per namespace, enforced by the VPC CNI network-policy engine | East-west movement between workloads after a container compromise |
| Data tier | Aurora SG allows 5432 only from the RDS Proxy SG; proxy SG allows 5432 only from the node SG. `publicly_accessible = false` | Direct database exposure |
| Control plane | EKS API private endpoint; public endpoint restricted to CI egress IPs and the VPN CIDR | Internet-facing Kubernetes API |
| Egress | Interface endpoints for AWS services; NAT for the rest. AWS Network Firewall with a domain allowlist named as the next step when data-exfiltration risk justifies the cost | Unrestricted outbound, C2 callbacks, exfiltration |
| Visibility | VPC Flow Logs (`ALL`) → Log Archive in Parquet, queried with Athena; GuardDuty consuming flow logs, DNS logs, and EKS runtime events | Blind spots; detection of anomalous connections |

### `## Traffic flow — request path` (~150 words)

Trace one request end to end in prose, because it proves the design hangs together:

`User → Route 53 → CloudFront (WAF, TLS termination, static SPA served from S3 via OAC) → /api/*
behaviour → ALB in the public subnets (TLS re-encrypted with an ACM cert) → AWS Load Balancer
Controller target group in IP mode → Flask pod ENI in the private app subnet (pod IP from the
100.66.x secondary CIDR) → RDS Proxy in the data subnet → Aurora writer.`

Call out the two things this buys: TLS is never terminated in a public subnet on a host anyone can
reach, and there is exactly one internet-facing entry point to secure.

State explicitly: **traffic between the ALB and pods, and between pods and the database, is
encrypted.** "Internal" is not a security boundary.

### `## What is deliberately not here` (~80 words)

Short, honest list with the trigger for each: a service mesh with mTLS (when service count grows past
a handful), AWS Network Firewall (when exfiltration risk or compliance requires egress filtering),
Shield Advanced (when the business is a DDoS target or the $3 000/month is justified by the cost
protection), PrivateLink to partner services, and IPv6. Naming what you left out and why is a
strength, not a gap.

---

## Decision Records — ADR-007 to ADR-010

End the draft with `## Decision Records` containing 4 ADRs from your reserved block, using the
exact template in `decision-register.md`. They must cover:

- **ADR-007 — One VPC per environment with no interconnection.** Against a shared VPC with separate
  subnets, and against peering the environments for convenience.
- **ADR-008 — Three Availability Zones rather than two.** The arithmetic of losing 50% versus 33% of
  capacity, against the extra NAT Gateway and cross-AZ data cost.
- **ADR-009 — A secondary CIDR in `100.64.0.0/10` for pod addresses.** Against burning routable
  RFC 1918 space, and against an overlay network such as Calico VXLAN. Argue the overlay fairly: it
  solves address exhaustion completely, at the cost of losing native security-group and flow-log
  visibility per pod. Fold in the /16-per-VPC sizing rationale here.
- **ADR-010 — A NAT Gateway per Availability Zone in production, one in non-production.** The
  explicit availability-versus-cost trade, made differently per environment on purpose.

The **"Why this is the right choice for Innovate Inc."** field on the pod-CIDR ADR is the hardest one
to write in plain language. Try: "every application process needs its own address on the private
network; we set aside a large block of addresses that can never conflict with anything else, so the
platform will not hit an invisible ceiling two years from now that would require rebuilding it."

---

## Acceptance criteria

- [ ] File is `_plan/drafts/02-network.md`, 1 300–1 900 words excluding tables and ADRs.
- [ ] Both halves present and clearly separated: VPC architecture, then network security.
- [ ] Every `##` section closes its opening paragraph with a pillar line carrying 2–4 pillars.
- [ ] The three-tier → subnet-tier mapping is stated explicitly, and the security half demonstrates
      that each tier boundary is enforced by a named mechanism rather than by convention.
- [ ] `## Decision Records` present with 4 ADRs from ADR-007 – ADR-010, full template, no fields
      missing; each has a fairly-argued rejected alternative, a plain-language field a non-engineer
      can read, a real *Accepts* downside, and an observable *Revisit when* trigger.
- [ ] The CIDR table and the production subnet table match `contract.md` §5 **exactly** — every
      number. Re-read them character by character before you finish.
- [ ] The subnet maths is internally consistent (no overlaps; `10.30.16.0/20` really is 4 091 usable).
- [ ] Rubric probe 2 (pod IP exhaustion) is answered explicitly with secondary CIDR + prefix
      delegation.
- [ ] Per-AZ private route tables and per-AZ NAT Gateways are stated, with both reasons.
- [ ] The security layer table has at least ten rows and every row names a **specific AWS or
      Kubernetes control**, not a category.
- [ ] Security groups are described as referencing other security groups, not CIDR blocks.
- [ ] NACLs are correctly described as **stateless**; security groups as **stateful**. Getting this
      backwards is an automatic deduction.
- [ ] The end-to-end request path is traced in one continuous flow.
- [ ] Encryption in transit is stated for internal hops, not just the edge.
- [ ] A `> **Cost.**` callout covers NAT Gateways.
- [ ] Deliberate omissions listed with triggers.
- [ ] No `TODO`/`TBD`; no banned words; no emoji.
- [ ] `STATE.md` updated.

## Common failure modes

| Failure | Avoid it by |
|---|---|
| Inventing a cleaner CIDR plan | `contract.md` §5 is locked and the diagram in Phase 10 will use it. |
| Describing NACLs as stateful, or WAF as protecting east-west traffic | Both are automatic deductions in `rubric.md`. |
| One shared private route table for all AZs | Per-AZ, for cost and blast radius. |
| Forgetting the pod-IP question entirely | It is the single best signal of real Kubernetes-on-AWS experience. |
| A security section that is a list of product names | Every row must say *what it stops*. |
| Designing IAM here | Identity is Phase 01 and Phase 06. Stay on the network. |
| Putting anything but ALBs and NAT Gateways in a public subnet | Nothing else goes there. Ever. |

---

## Agent prompt

```text
You are executing Phase 02 of the Innovate Inc. architecture design plan: Network Design.

Working directory boundary: architecture/ ONLY. Never read or write
terraform/, .claude/, or anything above architecture/. terraform/ belongs to a
different assignment that another agent may be editing right now.

Read in full, in order:
  architecture/_plan/AGENT-PROTOCOL.md
  architecture/_plan/brief.md
  architecture/_plan/contract.md      (§5 is your primary source — copy every CIDR exactly)
  architecture/_plan/decision-register.md
  architecture/_plan/well-architected.md
  architecture/_plan/style-guide.md
  architecture/_plan/rubric.md
  architecture/_plan/drafts/00-scope.md
  architecture/_plan/phases/phase-02-network.md

Read architecture/_plan/drafts/01-cloud-environment.md only if it exists.
Do not read any other file. No repository-wide searches. No aws/kubectl/terraform/docker/helm.
No web browsing.

Write architecture/_plan/drafts/02-network.md following the content specification
End the draft with a ## Decision Records section containing ADR-007 through ADR-010, using the exact
template in decision-register.md. Every ADR needs: an options table with at least one genuinely
reasonable rejected alternative argued fairly; a "Why this is the right choice for Innovate Inc."
field written in plain language for a non-engineer founder; an Accepts list naming a real
downside; and a Revisit when field naming an observable trigger.

Close every ## section's opening paragraph with a > **Well-Architected pillars.** line carrying
two to four pillars.

exactly — both halves, VPC architecture then network security. Then verify every acceptance
criterion line by line, fix what fails, update STATE.md, report, and STOP. Do not begin Phase 03.
```
