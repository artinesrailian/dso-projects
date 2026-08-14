## Network design principles

Innovate Inc.'s network enforces the three-tier model in §0.2 Architecture overview inside a virtual
private cloud (VPC) per environment: each tier's network placement, not a label, keeps the
presentation tier public, the application tier reachable only from the Application Load Balancer
(ALB), and the data tier reachable only from the application tier. The table below restates that
mapping, including the Classless Inter-Domain Routing (CIDR) block each tier's addresses draw from.

> **Well-Architected pillars.** Security · Reliability · Operational Excellence

| Application tier | Network placement | Reachable from |
|---|---|---|
| Presentation | CloudFront edge, S3 origin — outside the VPC entirely | The internet |
| Application | Private — App subnets; pod IPs from the secondary CIDR | The ALB only, which accepts only CloudFront |
| Data | Private — Data subnets | The application tier only, via RDS Proxy |

Four principles govern every VPC here:

- **One VPC per environment per region, with no connectivity between environments.** Isolation is
  the default, mirroring the account boundary in §1 Cloud Environment Structure at the network
  layer.
- **Three Availability Zones (AZs) in every production VPC.** Losing one of two AZs removes half of
  capacity; losing one of three removes a third.
- **Nothing that holds data or runs code is reachable from the internet.** Only the ALB and NAT
  Gateways sit in a public subnet.
- **Address space is allocated once, generously, from a plan.** Re-addressing a live VPC is close to
  impossible, and CIDR exhaustion is a common reason a Kubernetes platform has to be rebuilt.

---

## IP address plan

Innovate Inc. reserves `10.0.0.0/8` as the organization's address supernet and `100.64.0.0/10` —
Carrier-Grade NAT (CGN) space, defined by RFC 6598 — as a pod overlay range outside it.

> **Well-Architected pillars.** Reliability · Performance Efficiency · Operational Excellence

| Environment | Region | VPC name | Primary CIDR | Secondary CIDR (pods) |
|---|---|---|---|---|
| Dev | us-east-1 | `innovate-dev-vpc-use1` | `10.10.0.0/16` | `100.64.0.0/16` |
| Staging | us-east-1 | `innovate-stg-vpc-use1` | `10.20.0.0/16` | `100.65.0.0/16` |
| **Production** | us-east-1 | `innovate-prod-vpc-use1` | **`10.30.0.0/16`** | **`100.66.0.0/16`** |
| Production DR | us-west-2 | `innovate-prod-vpc-usw2` | `10.31.0.0/16` | `100.67.0.0/16` |
| Shared Services | us-east-1 | `innovate-shared-vpc-use1` | `10.40.0.0/16` | — |
| Reserved (EU, future) | eu-west-1 | — | `10.50.0.0/16` – `10.99.0.0/16` | — |

**Why a /16 per VPC.** Each environment gets a full `/16` — 65 536 addresses — because
under-provisioning means bolting a second, non-contiguous CIDR onto a live VPC later, not a quick
fix. It leaves headroom for every subnet tier defined here, tiers not yet designed, and a second
region for `innovate-prod-vpc-usw2` (non-production's identical topology is covered below).

**Why a secondary CIDR in `100.64.0.0/10` for pods.** The Amazon VPC Container Network Interface
(CNI) gives every pod a real, routable VPC address — one dataplane, not two. At a few hundred users
that is invisible; at Kubernetes scale it is not: a busy node can host dozens of pods, and a `/16`
that also holds every ALB, NAT Gateway, and endpoint elastic network interface (ENI) runs out fast,
with no way to re-address a running cluster. `100.64.0.0/10` is not routable on the public internet
and, since Innovate Inc. has no on-premises network to collide with, is safe to spend tens of
thousands of addresses on. Production's range, `100.66.0.0/16`, gives each Availability Zone a `/18`
— 16 379 addresses — through VPC CNI custom networking. Prefix delegation then assigns each node's
ENI a `/28` block instead of one IP at a time, so pod density per node rises well past the default
limit, removing the failure mode where pods stay `Pending` because a node ran out of addresses
before it ran out of CPU or memory. Because pods keep real VPC addresses rather than moving to an
overlay, their traffic stays visible in VPC Flow Logs, governed by the node's security group (SG)
and the CNI's `NetworkPolicy` engine (§2.4 Securing the network) — one visibility model, not two.

---

## VPC and subnet architecture

Production's subnet layout is the concrete answer to "design the VPC architecture," reproduced below
exactly as it is built — three Availability Zones (`us-east-1a`, `us-east-1b`, `us-east-1c`), six
subnet tiers, and one reserved block held empty on purpose.

> **Well-Architected pillars.** Security · Reliability · Performance Efficiency

| Tier | Purpose | AZ-a | AZ-b | AZ-c | Size | Usable IPs / AZ |
|---|---|---|---|---|---|---|
| Public | ALB, NAT Gateways. Nothing else. | `10.30.0.0/24` | `10.30.1.0/24` | `10.30.2.0/24` | /24 | 251 |
| Private — App | EKS worker nodes (ENIs) | `10.30.16.0/20` | `10.30.32.0/20` | `10.30.48.0/20` | /20 | 4 091 |
| Private — Data | Aurora, RDS Proxy, ElastiCache | `10.30.64.0/24` | `10.30.65.0/24` | `10.30.66.0/24` | /24 | 251 |
| Private — Endpoints | VPC interface endpoint ENIs | `10.30.68.0/24` | `10.30.69.0/24` | `10.30.70.0/24` | /24 | 251 |
| Private — Pods (secondary) | Pod IPs via VPC CNI custom networking | `100.66.0.0/18` | `100.66.64.0/18` | `100.66.128.0/18` | /18 | 16 379 |
| Reserved | Future tiers, do not allocate | `10.30.128.0/17` | | | /17 | 32 763 |

The **public /24 subnets** hold only ALB and NAT Gateway ENIs — enough across three AZs, and no
more, since a spacious public subnet invites what should not be there. The **Private — App /20
subnets** hold EKS worker node ENIs; 4 091 addresses per AZ gives the node fleet room to grow
through Karpenter's Spot and On-Demand NodePools (§3.3 Node strategy) before the account's own
quotas become the ceiling. The **Private — Data /24 subnets** hold Aurora and RDS Proxy only, in
their own route table, so a data-tier subnet can never inherit a default internet route by accident
— the boundary is enforced by routing, not discipline. The **Private — Endpoints /24 subnets**
isolate endpoint ENIs from the workloads calling them. The **Private — Pods /18 subnets** hold pod
addresses, as explained above. The **Reserved /17** stays unallocated: a future tier is a new row in
this table, not a re-plan.

Non-production environments — `innovate-dev-vpc-use1` and `innovate-stg-vpc-use1` — repeat this
exact shape at the same offsets inside their own `/16`, so a staging test exercises the real
topology.

---

## Routing and internet egress

Production runs **one public route table** (`0.0.0.0/0` → the VPC's Internet Gateway) and **one
private route table per Availability Zone** (`0.0.0.0/0` → that AZ's own NAT Gateway), not one
private table shared across all three.

> **Well-Architected pillars.** Reliability · Cost Optimization · Security

Per-AZ route tables buy two things a shared table cannot: outbound traffic never crosses an AZ
boundary to reach its NAT Gateway, avoiding a cross-AZ data-transfer charge, and a NAT failure is
contained to one AZ rather than a third of egress. Production runs three NAT Gateways, one per AZ;
`innovate-dev-vpc-use1` and `innovate-stg-vpc-use1` each run one — the same trade resolved
differently: production pays for AZ-level fault isolation because an outage there is
customer-facing, and non-production accepts a single point of failure because a NAT outage costs a
delayed deploy, not a customer.

> **Cost.** NAT Gateways are one of the largest line items in this design at low traffic — an
> indicative ~$170/month combined across all five (hourly charge plus data processed;
> order-of-magnitude only — see the AWS Pricing Calculator for current rates). Three in production
> is an availability decision; one in development and staging is a cost decision. Both are stated
> here rather than left implicit.

No worker node, pod, or database instance ever receives a public IP address
(`map_public_ip_on_launch = false` on every private subnet), so inbound traffic reaches a workload
only through CloudFront and the ALB.

VPC endpoints keep AWS-service traffic off the NAT Gateway. The **gateway endpoints** — Amazon S3
and Amazon DynamoDB — cost nothing and run in every VPC. The **interface endpoints** cover the
services this design's workloads actually call: `ecr.api`, `ecr.dkr`, `sts`, `logs`, `monitoring`,
`secretsmanager`, `kms`, `ssm`, `ssmmessages`, `ec2messages`, `ec2`, `elasticloadbalancing`,
`autoscaling`, `sqs`, `eks`, and `xray` — each with its own per-AZ hourly charge, so the list is
chosen, not exhaustive: every entry keeps a frequent call off the NAT Gateway and on the AWS
network, and its avoided data-processing charge partly offsets its own cost. In principle, the
workload subnets could run with no internet egress route at all.

---

## Connectivity between environments and to AWS services

No VPC peering, no Transit Gateway, and no shared-services VPC connectivity exists between
`innovate-dev-vpc-use1`, `innovate-stg-vpc-use1`, and `innovate-prod-vpc-use1` on day one — each is
a network island, matching the account isolation in §1 Cloud Environment Structure. Environments
reach each other only through public, authenticated application programming interfaces (APIs), or
not at all.

> **Well-Architected pillars.** Security · Reliability · Operational Excellence

The one connection that looks like an exception — cross-account image pulls from
`innovate-shared-services`'s Amazon Elastic Container Registry (ECR) — is not a network exception:
pulls traverse the `ecr.api` and `ecr.dkr` interface endpoints inside the pulling account's own VPC,
authorized by an ECR repository policy, not network reachability — identity is the perimeter, not a
route. When hybrid or partner connectivity eventually arrives, the answer is a Transit Gateway
hosted in `innovate-network`; the CIDR plan already reserves the room.

---

## Securing the network

Every control above keeps traffic inside the right subnet; this section stops traffic that should
not exist at all. The design assumes the perimeter will eventually be probed and breached, so no
single layer below is trusted alone. Defense here is depth, not a wall: eleven layers, edge to
database security group, each enforced by a named mechanism, not a shared assumption that "internal"
traffic is safe.

> **Well-Architected pillars.** Security · Reliability

| Layer | Control | What it stops |
|---|---|---|
| Edge / DDoS | AWS Shield Standard (always on); Shield Advanced deferred | Volumetric L3/L4 distributed denial-of-service (DDoS) attacks |
| Edge / application | AWS WAF on CloudFront: AWS managed rule groups (Common, Known Bad Inputs, SQLi, IP reputation) + rate-based rule at 2 000 requests / 5 min / IP | SQL injection, cross-site scripting (XSS), scanners, credential stuffing, scraping |
| Edge / TLS | AWS Certificate Manager (ACM) certificate on CloudFront, TLS 1.2+ only, HTTP Strict Transport Security (HSTS) and a response-headers policy (Content Security Policy (CSP), X-Content-Type-Options, Referrer-Policy) | Downgrade, mixed content, some XSS classes |
| Origin protection | CloudFront origin access control on the S3 bucket; ALB accepts traffic only from the CloudFront managed prefix list plus a shared secret header | Origin bypass — hitting the ALB directly to skip WAF |
| Subnet | Network access control lists (NACLs) as a coarse stateless backstop: data-tier NACL permits TCP 5432 inbound from the app-tier subnet ranges and the ephemeral range outbound, nothing else | Route-table or SG misconfiguration, lateral movement |
| Instance | Security groups, default-deny, **referencing other security groups rather than CIDRs** | Broad CIDR allows that silently widen over time |
| Pod | Kubernetes `NetworkPolicy`, default-deny ingress and egress per namespace, enforced by the VPC CNI network-policy engine | East-west movement between workloads after a container compromise |
| Data tier | Aurora SG allows 5432 only from the RDS Proxy SG; proxy SG allows 5432 only from the node/pod SG. `publicly_accessible = false` | Direct database exposure |
| Control plane | EKS API private endpoint; public endpoint restricted to CI/CD egress addresses and the corporate VPN range | Internet-facing Kubernetes API |
| Egress | Interface endpoints for AWS services; NAT for the rest. AWS Network Firewall with a domain allowlist named as the next step when data-exfiltration risk justifies the cost | Unrestricted outbound, C2 callbacks, exfiltration |
| Visibility | VPC Flow Logs (`ALL`) → Log Archive in Parquet, queried with Athena; GuardDuty consuming flow logs, DNS logs, and EKS runtime events | Blind spots; detection of anomalous connections |

Two of these layers are commonly confused. **Network ACLs are stateless**: the data-tier NACL must
permit `5432` inbound from the app-tier subnet ranges and separately permit the ephemeral range
outbound, since both directions are evaluated independently. **Security groups are stateful**: a
rule need only permit the initiating direction, and the return traffic is allowed automatically.
That is also why the NACL stays a coarse backstop — the one row here keyed on a CIDR range rather
than an identity. From the ALB's security group inward, every security group in the request path —
ALB to pod, pod to RDS Proxy, proxy to Aurora — references another security group as its source, not
a CIDR block. The one exception is the ALB's own inbound rule, sourced from the CloudFront managed
prefix list, since CloudFront has no VPC security group to reference. So the tier boundary from §0.2
Architecture overview is enforced by a chain of identity from the ALB inward, not by subnet.

Day-to-day engineer access to the private EKS API uses the same IAM Identity Center session as
everywhere else, mapped to an EKS access entry (§1 Cloud Environment Structure) — no bastion host,
no kubeconfig to leak.

---

## Traffic flow — request path

One request traces the whole design end to end. A browser resolves `app.innovateinc.com` through
Amazon Route 53 to Amazon CloudFront, which terminates TLS at the edge, evaluates the AWS WAF rule
groups, and for a static asset serves the React single-page application (SPA) directly from the
Amazon S3 origin over origin access control. A request matching `/api/*` instead forwards to the ALB
in production's public subnets, where TLS is re-terminated with an ACM certificate — never passed
through unencrypted, never terminated on a reachable host. The AWS Load Balancer Controller's target
group, in IP mode, forwards it to a Flask pod's ENI in a private app subnet, carrying an address
from the `100.66.0.0/16` secondary CIDR. The pod calls Amazon RDS Proxy in the data subnet, which
holds the connection to the Aurora writer.

> **Well-Architected pillars.** Security · Performance Efficiency · Reliability

There is exactly **one** internet-facing entry point — CloudFront — so exactly one thing to harden
against direct attack. And **every hop after CloudFront is still encrypted, by a named mechanism**:
the ALB's target group reaches each pod over HTTPS using a certificate issued by `cert-manager` on
the cluster, and the pod's connection to Aurora enforces `rds.force_ssl = 1` with
`sslmode=verify-full` on the client — "never leaves AWS's network" is not the same guarantee as
"cannot be read."

---

## What is deliberately not here

Five controls are deliberately absent from day one, each with the trigger that brings it back.

> **Well-Architected pillars.** Cost Optimization · Operational Excellence · Security

A service mesh with mutual TLS (mTLS) is unnecessary while the application tier is one API and one
worker fleet — `NetworkPolicy` and TLS-in-transit already cover it — and earns its cost once service
count grows past a handful. AWS Network Firewall arrives when compliance or exfiltration risk
justifies maintaining its rules. AWS Shield Advanced arrives when Innovate Inc. becomes a plausible
DDoS target, or when its subscription cost — indicative only; confirm via the AWS Pricing Calculator
— is judged justified by the protection it buys. PrivateLink to a partner service arrives with the
first integration that needs it. IPv6 arrives when a client or partner requires it.

---

## Decision Records

The four decisions below carry the full argument for Innovate Inc.'s network shape: whether
environments connect to each other, how many Availability Zones production spans, how pod addressing
is kept from ever running out, and how many NAT Gateways each environment runs. Each stands on its
own, with a plain-language justification a non-technical reader can follow without the rest of this
document.

> **Well-Architected pillars.** Security · Reliability · Cost Optimization

### ADR-007 — One VPC Per Environment, No Interconnection

| | |
|---|---|
| **Status** | Accepted |
| **Requirement** | R3, R4 |
| **Pillars** | Security · Reliability |
| **Section** | §2 Network Design |

**Context.** Innovate Inc. runs three workload environments — development, staging, production —
plus shared services, each already isolated by its own AWS account (§1 Cloud Environment Structure).
The network layer can restate that isolation, or quietly undo it by connecting the VPCs back
together for convenience.

**Options considered.**

| Option | Strengths | Weaknesses | Verdict |
|---|---|---|---|
| Shared VPC, environments separated by subnet | One VPC to manage; a single route table and endpoint set to pay for | Every environment shares one blast radius; a misconfigured route or security group in development can reach production's subnets directly, undoing the account boundary above it | Rejected — collapses the isolation §1 already paid for |
| VPC peering between environments, added for a specific convenience (e.g., staging reads a production replica) | Solves a real integration need directly, without a public API round trip | A standing path between environments that tends to accumulate one exception at a time until the isolation is gone in practice | Rejected — the exception should be argued for when actually needed, not assumed in advance |
| One VPC per environment, no peering, no Transit Gateway | Each environment is a genuine network island; a compromise in one has no network path to another | Environments that need to share data do so over a public, authenticated API rather than a private route | **Chosen** |

**Decision.** Each of Innovate Inc.'s environments — `innovate-dev-vpc-use1`,
`innovate-stg-vpc-use1`, `innovate-prod-vpc-use1`, and `innovate-shared-vpc-use1` — is its own VPC
with no peering connection, Transit Gateway attachment, or shared route to any other environment.

**Why this is the right choice for Innovate Inc.** Think of each environment as its own building
with its own front door, not four floors connected by an internal staircase. If a mistake happens on
the development floor — a bug, a misconfigured setting, even a break-in — there is no staircase to
the production floor where real customer data lives. Information only moves between environments
through the same authenticated, logged door an outside visitor would use. It costs a little
convenience, but that inconvenience is the point.

**Consequences.**
- *Gains:* A compromised or misconfigured environment has no network path to another; the account
  isolation from §1 Cloud Environment Structure holds at the network layer too.
- *Accepts:* Cross-environment needs go through an authenticated API or an export/import step, never
  a direct route — slower than peering would be.

**Cost impact.** No direct cost; the alternative would have saved nothing meaningful and cost the
isolation guarantee.

**Revisit when.** A specific, named integration need appears that a public API genuinely cannot
serve — the connection then becomes a dedicated, reviewed exception, most likely a future Transit
Gateway in `innovate-network`.

### ADR-008 — Three Availability Zones Rather Than Two

| | |
|---|---|
| **Status** | Accepted |
| **Requirement** | R3 |
| **Pillars** | Reliability · Cost Optimization |
| **Section** | §2.2 VPC and subnet architecture |

**Context.** Production must keep serving traffic through the loss of a single data center. Innovate
Inc. has no operations team able to react within minutes of an outage, so the architecture itself
has to absorb the failure.

**Options considered.**

| Option | Strengths | Weaknesses | Verdict |
|---|---|---|---|
| Two Availability Zones (AZs) | Lowest fixed cost — one fewer NAT Gateway and subnet set per tier | Losing one AZ removes 50% of production's capacity in a single event, right when the remaining AZ is least prepared to absorb a doubling of load | Rejected — too severe a failure mode for a system handling sensitive user data |
| Four or more AZs | Losing one AZ removes only 25% or less of capacity | Diminishing reliability return for a linear cost increase — another NAT Gateway and subnet set — that a few-hundred-user workload does not need yet | Rejected — the third AZ already captures most of the benefit for a fraction of the cost |
| Three Availability Zones | Losing one AZ removes 33% of capacity, not 50%; matches Aurora's own three-AZ storage model (§4.5 High availability) so the network and database failure domains line up | One additional NAT Gateway and subnet set beyond the two-AZ option | **Chosen** |

**Decision.** Every production subnet tier spans exactly three Availability Zones — `us-east-1a`,
`us-east-1b`, `us-east-1c` — and non-production environments mirror the same shape at a reduced NAT
Gateway count.

**Why this is the right choice for Innovate Inc.** If a single AWS data center goes down — which
happens, rarely but for real — a system split across two data centers loses half its capacity right
when it needs it most. Splitting across three means the same event only takes away a third: the
difference between losing every other customer's request and losing one in three, for the cost of
one more set of background network components. Given that Innovate Inc. is trusting this system with
real user data, that trade is worth making.

**Consequences.**
- *Gains:* A single Availability Zone failure degrades capacity by a third instead of a half, and
  matches Aurora's own three-AZ redundancy so no failure domain is weaker than another.
- *Accepts:* One additional NAT Gateway and subnet per tier to provision and pay for, compared to
  two AZs.

**Cost impact.** Roughly one extra NAT Gateway's cost versus a two-AZ design; small against a fourth
or fifth AZ, which this design does not add.

**Revisit when.** `us-east-1`'s available AZ count changes, or production's traffic reaches a scale
where even a 33% capacity loss is unacceptable and the answer becomes a second active region rather
than more AZs in one.

### ADR-009 — A Secondary CIDR in `100.64.0.0/10` for Pod Addresses

| | |
|---|---|
| **Status** | Accepted |
| **Requirement** | R3 |
| **Pillars** | Reliability · Performance Efficiency |
| **Section** | §2.2 VPC and subnet architecture |

**Context.** Innovate Inc. runs on Amazon EKS, where every pod gets its own routable VPC address by
default, and expects to grow from a few hundred users to potentially millions — a Kubernetes
platform that runs out of addresses has to be rebuilt, not patched. Each VPC is already a full `/16`
for that reason, but even a `/16` disappears fast once pods share it with every ALB, NAT Gateway,
and node.

**Options considered.**

| Option | Strengths | Weaknesses | Verdict |
|---|---|---|---|
| Pods share the VPC's primary routable (RFC 1918) address space | Simplest possible setup; no secondary CIDR or custom networking configuration | A production `/16` also has to hold every ALB, NAT Gateway, node, and endpoint ENI alongside every pod — at real pod density that space is exhausted long before the business is, with no way to re-address a live cluster | Rejected — trades day-1 simplicity for a hard ceiling later |
| An overlay network (e.g., Calico VXLAN) with pod addresses outside the VPC's routing entirely | Solves address exhaustion completely — pod addresses never touch VPC address space | Pod-to-pod traffic disappears from VPC Flow Logs and loses native security-group enforcement per pod, moving to a second, separately operated dataplane the platform team must learn and run alongside the VPC CNI | Rejected — solves a real problem by introducing a second network stack this design otherwise avoids |
| A secondary CIDR in `100.64.0.0/10` (Carrier-Grade NAT space) via VPC CNI custom networking | Pods keep real, routable VPC addresses — the same VPC Flow Log visibility and `NetworkPolicy` enforcement as everything else — from a range that will never collide with RFC 1918 space or a future partner network | Requires custom networking configuration on the CNI and a second CIDR to plan around | **Chosen** |

**Decision.** Every environment's VPC carries a secondary CIDR from `100.64.0.0/10` —
`100.66.0.0/16` in production — dedicated to pod addresses via VPC CNI custom networking with prefix
delegation.

**Why this is the right choice for Innovate Inc.** Every running piece of the application needs its
own address on the private network, the same way every phone in an office needs its own extension.
We set aside a large block of addresses that can never collide with any other network, dedicated
entirely to that purpose — so the platform never hits an invisible ceiling that would force
rebuilding it once real customers depend on the system.

**Consequences.**
- *Gains:* Effectively unlimited pod address space; pods keep full security-group and VPC Flow Log
  visibility, same as everything else.
- *Accepts:* The VPC CNI must run in custom-networking mode — one more configuration the platform
  team learns once and maintains.

**Cost impact.** No direct cost — the address range is free; the cost is entirely one-time
configuration.

**Revisit when.** Pod count per environment approaches a level where even a `/18` per AZ is a real
constraint — well beyond the millions-of-users stage this design targets.

### ADR-010 — A NAT Gateway Per Availability Zone in Production, One in Non-Production

| | |
|---|---|
| **Status** | Accepted |
| **Requirement** | R3 |
| **Pillars** | Reliability · Cost Optimization |
| **Section** | §2 Network Design |

**Context.** Every private subnet needs a path to the internet for package downloads, third-party
API calls, and anything not reachable through a VPC endpoint. How many NAT Gateways to run, and
where, is a reliability-versus-cost decision made differently for production than for the
environments engineers use to build and test.

**Options considered.**

| Option | Strengths | Weaknesses | Verdict |
|---|---|---|---|
| One NAT Gateway for the whole VPC, in every environment including production | Cheapest option everywhere — roughly a third of the production NAT cost | A single NAT Gateway is a single point of failure for all outbound traffic in every AZ; its failure takes down egress for the whole environment at once | Rejected for production — an availability gap the sensitive-data, customer-facing environment should not accept |
| A NAT Gateway per AZ, in every environment including development and staging | Uniform reliability everywhere; no special-casing to remember | Triples the NAT Gateway bill in environments where a brief egress outage costs a delayed deploy, not a customer-facing incident | Rejected for non-production — reliability spend where the failure mode does not justify it |
| A NAT Gateway per AZ in production; one shared NAT Gateway in development and staging | Production gets AZ-level fault isolation where it matters; non-production accepts a bounded, low-consequence risk for materially lower cost | Non-production has a real, accepted gap: a NAT Gateway outage blocks outbound traffic for the whole environment until AWS restores it | **Chosen** |

**Decision.** Production runs three NAT Gateways, one per Availability Zone; `innovate-dev-vpc-use1`
and `innovate-stg-vpc-use1` each run one.

**Why this is the right choice for Innovate Inc.** A NAT Gateway is the door through which the
application reaches the internet — for things like a software update. In production, we install one
door per data center, so losing one never locks out the other two. In development and staging, a
jammed door costs a delayed test run, not an unhappy customer, so we install one there — three would
cost more for a risk that matters far less.

**Consequences.**
- *Gains:* A NAT Gateway or AZ failure in production degrades only that AZ's egress, never the whole
  environment's.
- *Accepts:* Development and staging each have one outbound path that, if it fails, blocks that
  environment's internet-bound traffic until AWS resolves it.

**Cost impact.** Indicative combined NAT Gateway spend across all five environments is ~$170/month
(hourly charge plus data processed; see the AWS Pricing Calculator for current rates) — production's
three cost roughly triple a single-NAT environment's share, offset against the cost of a
full-environment outbound outage.

**Revisit when.** A non-production outage caused by a single NAT Gateway blocks a release often
enough to justify the extra cost, or CI/CD deployment frequency makes even a brief non-production
egress gap expensive.
