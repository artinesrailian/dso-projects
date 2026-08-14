# Review Rubric — how this deliverable will be judged

Written from the reviewer's seat. Phase 13 scores the finished README against this file and fixes
everything below "strong". Content phases should read it before writing, because it is easier to
score well by design than by repair.

The reviewer is a senior or principal cloud engineer at a consultancy. They have read dozens of
these. They will skim first, then dig into two or three areas at random to see whether the depth is
real.

---

## 1. What gets checked first (the 90-second skim)

| Check | Pass looks like |
|---|---|
| Is there a diagram, and does it render? | An HLD near the top of `architecture/README.md`, rendered, legible, organised by tier |
| Are the four assessment areas obvious headings? | `## 1. Cloud Environment Structure`, `## 2. Network Design`, `## 3. Compute Platform`, `## 4. Database` — findable in the table of contents |
| Does it open with a summary a founder could read? | An executive summary with no unexplained jargon |
| Is the reasoning visible, not just the conclusions? | A decision register appendix, and alternatives named inline |
| Is it recognisably a Well-Architected design? | A pillar chapter, and pillar tags on the sections |
| Is it the right length? | Substantial but finite. Filler scores worse than a tight document |
| Does it look like one author wrote it? | Consistent names, consistent voice, no seams |

**Failure modes that end the review early:** a broken Mermaid block; a missing assessment area; two
different VPC CIDRs in two sections; `TODO` markers; obvious filler prose.

---

## 2. Scored dimensions

Each is scored `weak` / `adequate` / `strong`. Phase 13 must reach `strong` on every row or record in
`STATE.md` why not.

### A. Requirement coverage (fatal if weak)

- [ ] All four assessment areas present, in order, as top-level sections.
- [ ] **Every sub-bullet** of every area answered — including the ones that get dropped most often:
      *justify the account count*, *secure the network*, *resource allocation within the cluster*,
      *image building AND registry AND deployment*, *backups AND high availability AND disaster
      recovery as three distinct things*.
- [ ] Deliverable at `architecture/README.md`; the HLD requirement satisfied.
- [ ] The traceability table (R1–R28) is present and every row points at a real section.

### B. Justification quality — **the dimension that separates candidates**

- [ ] Each major choice states the alternative it beat and why, inline.
- [ ] The decision register runs ADR-001 to ADR-029 with no gaps, and every significant decision is
      either a record or a row in the Summary of Key Decisions table.
- [ ] Every ADR's options table contains at least one **genuinely reasonable** rejected alternative,
      argued fairly rather than strawmanned.
- [ ] Every ADR's **"Why this is the right choice for Innovate Inc."** field is readable by a
      non-engineer and connects the decision to a business consequence.
- [ ] Every ADR names real consequences it accepts, not only benefits.
- [ ] Every ADR has an observable revisit trigger.
- [ ] Reasoning is tied to Innovate Inc.'s specifics — a small, lean team, sensitive data, a
      hundreds-to-millions growth curve — not to generic best practice.
- [ ] Nothing is justified purely by "AWS recommends it".

### C. Well-Architected alignment

- [ ] All six pillars addressed, including Sustainability, with content specific to this design.
- [ ] Every `##` section carries a pillar attribution line with 2–4 pillars.
- [ ] Each ADR carries its pillars.
- [ ] The pillar chapter maps to *this* design rather than reciting framework documentation.
- [ ] **Pillar trade-offs are stated explicitly** — where the design leaned toward one pillar at
      another's expense, and why. A pillar chapter with no trade-offs reads as marketing.
- [ ] Each pillar section names at least one honest gap or deferral with its trigger.

### D. Three-tier architecture

- [ ] The design is explicitly framed as presentation / application / data.
- [ ] Network subnet tiers map to the application tiers one-to-one.
- [ ] Each tier's scaling mechanism is distinct and named.
- [ ] The tier boundary is shown to be the security boundary — enforced by security-group references
      and NetworkPolicy, not by convention.
- [ ] The HLD is organised by tier so the model is visible, not just asserted.

### E. Technical correctness

- [ ] No factually wrong statements about how an AWS service behaves.
- [ ] CIDRs do not overlap and the subnet arithmetic is right.
- [ ] Kubernetes concepts used correctly — Horizontal Pod Autoscaler, Cluster Autoscaler, Karpenter,
      and Vertical Pod Autoscaler are four different things doing four different jobs.
- [ ] High availability and disaster recovery are not conflated. Multi-AZ is HA. Cross-region is DR.
- [ ] Security controls correctly attributed — AWS WAF is not a control for east-west traffic;
      network ACLs are stateless; security groups are stateful.
- [ ] No hallucinated service names, quotas, prices, or version numbers.

### F. Security depth — the brief calls out sensitive data, so expect scrutiny

- [ ] Defence in depth across at least: identity, network, data at rest, data in transit, workload
      runtime, supply chain, detection, and response.
- [ ] Encryption story is specific — customer-managed KMS keys, per environment and per data class.
- [ ] Secrets never in images, environment files, or git, and the enforcing mechanism is named.
- [ ] Least privilege is mechanised (service control policies, permission sets, Pod Identity), not
      asserted.
- [ ] Security is present *inside* the other sections — pipeline gates, admission control, identity
      boundaries — not quarantined into one chapter.
- [ ] Audit and detection covered, not just prevention, and the audit trail is shown to be tamper-evident.
- [ ] Compliance posture addressed proportionately — a section, not a chapter, and honest about what
      the architecture does not deliver.

### G. Cost and appropriateness to stage

- [ ] Day-1 cost broken down by service, clearly labelled indicative, pointing at the AWS Pricing
      Calculator.
- [ ] A cheaper variant is offered with an explicit statement of what it gives up.
- [ ] Cost projected across growth stages, with the shape of the curve explained.
- [ ] At least ten optimization levers, each with its trade-off.
- [ ] Cost governance is mechanised — tagging enforced, budgets, anomaly detection, attribution.
- [ ] The day-1 design is something a small team can actually run.
- [ ] Complexity that only pays off at scale is deferred to an explicit growth roadmap, and the
      roadmap says *what triggers* each step.

### H. Communication

- [ ] A founder with limited cloud experience can read the summary and the diagrams and understand
      the shape of the system.
- [ ] Acronyms expanded on first use.
- [ ] Tables used where tables help.
- [ ] No marketing tone, no filler, no repetition between sections.
- [ ] Diagrams have legends and captions.

---

## 3. Depth probes the reviewer is likely to run

If the document survives the skim, the reviewer picks two or three of these and looks for a real
answer. Content phases should make sure the answer is present *somewhere*.

1. "You have three environments in three accounts — how does an image built once get to production
   without being rebuilt?" → immutable digest promotion, cross-account ECR pull policy.
2. "Your pods have VPC IP addresses. What happens to your /16 when you have 5 000 pods?" → prefix
   delegation, secondary CIDR in `100.64.0.0/10`, custom networking.
3. "Aurora failover takes 30 seconds. What does your Flask app do during those 30 seconds?" → RDS
   Proxy holds connections, retry with backoff, readiness probe, graceful degradation.
4. "How do you stop a compromised CI token from deploying to production?" → OIDC short-lived roles
   scoped to repository and branch, pull-based GitOps so CI never holds cluster credentials, manual
   approval gate, signed images verified at admission.
5. "Spot instances for a production API — what happens on a two-minute interruption notice?" →
   Karpenter interruption handling via the SQS queue, cordon and drain, disruption budgets, On-Demand
   fallback pool, stateless-only rule.
6. "Someone deletes the production database. Walk me through the next hour." → deletion protection,
   point-in-time recovery, vault-locked cross-account copy, the RPO/RTO table, restore-test evidence.
7. "Why not just one account and namespaces?" → the R2 justification.
8. "What breaks first when you go from 1 000 to 1 000 000 users?" → the growth roadmap with triggers:
   database connections, read replicas, caching, pod IP addresses, NAT bandwidth, single writer.
9. "How does a developer's laptop reach the EKS API if it's private?" → IAM Identity Center → EKS
   access entries; restricted public endpoint.
10. "What is in your CI pipeline between `git push` and a running pod?" → the pipeline table, end to
    end, with the security gates named.
11. "Which Well-Architected pillar did you sacrifice, and where?" → the trade-off table. A candidate
    who cannot answer this has applied the framework as a checklist rather than a design tool.
12. "Your three-tier diagram shows the application tier in private subnets. What exactly stops
    someone reaching it directly?" → CloudFront prefix list on the ALB security group, shared secret
    header, no public IPs, no inbound route.

---

## 4. Automatic deductions

| Issue | Severity |
|---|---|
| A Mermaid diagram that does not parse | Fatal |
| A missing assessment area or sub-bullet | Fatal |
| A decision presented with no alternative and no reason | Severe |
| Contradictory facts between two sections | Severe |
| `TODO` / `TBD` / placeholder text | Severe |
| Hallucinated AWS service, feature, or price stated as fact | Severe |
| A plain-language ADR field that is still full of jargon | Severe |
| Well-Architected chapter that recites framework documentation instead of mapping this design | Moderate |
| High availability and disaster recovery conflated | Moderate |
| No cost discussion, or cost figures presented as authoritative | Moderate |
| Generic content that would apply to any client | Moderate |
| Gaps or duplicates in ADR numbering | Minor but visible |
| Banned marketing words | Minor but cumulative |
| Inconsistent naming between prose and diagram | Minor but cumulative |
