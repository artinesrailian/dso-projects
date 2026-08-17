# modules/network

A new, dedicated VPC across up to three AZs with a private data plane: nodes and
pods live only in private subnets, NAT gateways and public load balancers live
in public subnets, and EKS control-plane ENIs get their own intra subnets with
no NAT route at all. See `docs/00-architecture-and-decisions.md` ADR-1 for the
full rationale and `docs/contracts/interface-contract.md` §5.1 for this
module's exact input/output contract.

Every CIDR is derived from `var.vpc_cidr` with `cidrsubnet()` — nothing is
hardcoded, so the module works for any `vpc_cidr` of `/18` or larger — the
same bound the root module enforces, so the computed intra subnets never fall
below `/24` (251 usable IPs, above AWS's recommended >=16-per-subnet floor).

## Subnet plan for the default CIDR (`10.0.0.0/16`, `az_count = 3`)

| Tier | Purpose | Size | AZ-a | AZ-b | AZ-c |
|---|---|---|---|---|---|
| Private | nodes, pods (VPC CNI gives every pod a real IP) | `/19` (8,187 usable) | `10.0.0.0/19` | `10.0.32.0/19` | `10.0.64.0/19` |
| Public | NAT gateways, public load balancers | `/24` (251 usable) | `10.0.96.0/24` | `10.0.97.0/24` | `10.0.98.0/24` |
| Intra | EKS control-plane ENIs only, no NAT route | `/24` (251 usable) | `10.0.99.0/24` | `10.0.100.0/24` | `10.0.101.0/24` |

No overlap; `10.0.102.0/24` and above are left free for future use. Private
subnets are sized as *pod* capacity, not node capacity — a `/24` here would cap
out at ~250 pods per AZ and fail in a way that looks like a scheduling bug, not
a networking one.

## Discovery tags

`karpenter.sh/discovery = var.name` on every private subnet is what lets
Karpenter's `EC2NodeClass.spec.subnetSelectorTerms` find them. `var.name` must
be the same value passed as the EKS cluster name (`local.name` at the root) —
if the tag value and the selector ever disagree, Karpenter reports `no subnets
found` and provisions nothing, with no other symptom.

The node security group also needs this tag, but that security group is
created by `modules/eks` (Phase 2), not this module — see
`node_security_group_tags` there.

## What this module does not do

- Does not create or tag the EKS node security group (Phase 2 owns it).
- Does not reference EKS or Karpenter resources.
- Does not empty the default network ACL's rules — every subnet in this VPC
  uses the default NACL, so doing so would black-hole all traffic in the VPC.
  See the warning in `main.tf` and phase-01 §1.6.
