# Phase 1 — Networking (dedicated VPC)

**Depends on:** Phase 0.
**Produces:** `modules/network/`, wired into `main.tf` as `module.network`.

---

## Goal

A new, dedicated VPC across up to three AZs with a private data plane, correct EKS and Karpenter
discovery tags, optional flow logs and optional interface endpoints — and nothing EKS-specific
beyond the tags.

This is requirement **R2** ("into a new dedicated VPC") and it silently determines whether the rest
of the stack works. Almost every "my nodes won't join" and "Karpenter can't find subnets" problem is
actually a Phase 1 problem.

---

## Inputs

| Source | What you need |
|---|---|
| `contracts/interface-contract.md` | §2.3 the discovery tag table (load-bearing), §5.1 the exact `modules/network` signature |
| `reference/version-pinning.md` | VPC module `6.6.1`; §5 the defaults that break a naive copy-paste |
| `00-architecture-and-decisions.md` | ADR-1 (subnet sizing rationale), ADR-11 (cost toggles) |
| Phase 0 completion report | Confirm `local.name` and `local.tags` exist as specified |

---

## Files to create

```
modules/network/versions.tf
modules/network/variables.tf
modules/network/main.tf
modules/network/outputs.tf
modules/network/README.md
```

And **edit** `main.tf` to add the `module "network"` block, plus `outputs.tf`
for the networking outputs listed in interface-contract §4.

---

## Specification

### 1.1 AZ selection

```hcl
data "aws_availability_zones" "available" {
  state = "available"
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}
```

The `opt-in-status` filter matters: without it, accounts with Local Zones or Wavelength Zones enabled
can have those returned in `names`, and EKS cannot place a control-plane ENI in them. Take
`slice(data.aws_availability_zones.available.names, 0, var.az_count)`.

### 1.2 Subnet plan — computed, not hardcoded

Derive every CIDR from `var.vpc_cidr` so the module works for any sufficiently large VPC:

```hcl
locals {
  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  # /19 per AZ — 8,187 usable IPs. The VPC CNI gives every POD a real VPC IP,
  # so this is pod capacity, not node capacity. A /24 here caps you at ~250
  # pods per AZ and fails in a way that looks like a scheduling bug.
  private_subnets = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 3, i)]

  # /24 is plenty: only NAT gateways and public load balancers live here.
  public_subnets = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 8, 96 + i)]

  # /24, no NAT route at all — EKS control-plane ENIs only.
  intra_subnets = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 8, 99 + i)]
}
```

For the default `10.0.0.0/16` this yields private `10.0.0.0/19`, `10.0.32.0/19`, `10.0.64.0/19`;
public `10.0.96.0/24`–`10.0.98.0/24`; intra `10.0.99.0/24`–`10.0.101.0/24`. No overlap, room left
over at `10.0.102.0/24`+ for future use.

Add a `precondition` (or `validation` in Phase 0) proving the VPC is at least a `/20`, so the
`cidrsubnet` calls cannot fail with an unhelpful error.

### 1.3 The VPC module call

```hcl
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.6.1"

  name = var.name
  cidr = var.vpc_cidr
  azs  = local.azs

  private_subnets = local.private_subnets
  public_subnets  = local.public_subnets
  intra_subnets   = local.intra_subnets

  # enable_nat_gateway DEFAULTS TO FALSE in this module. Without it the private
  # subnets have no egress, nodes cannot pull images, and they never join.
  enable_nat_gateway     = true
  single_nat_gateway     = var.single_nat_gateway
  one_nat_gateway_per_az = !var.single_nat_gateway

  enable_dns_hostnames = true
  enable_dns_support   = true   # required for the EKS private endpoint to resolve

  # ...tags, flow logs — see below
}
```

`single_nat_gateway` and `one_nat_gateway_per_az` are mutually exclusive in the module; driving both
from one variable keeps them consistent.

### 1.4 Tags — the load-bearing part

```hcl
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
    # Karpenter's EC2NodeClass subnetSelectorTerms matches on exactly this.
    # If this tag and the selector disagree, Karpenter reports "no subnets found"
    # and provisions nothing, with no other symptom.
    "karpenter.sh/discovery" = var.name
  }
```

`var.name` is `local.name`, which is also the cluster name — so both sides of the discovery contract
read from a single source. Never hardcode the value.

Note what is **not** here: `kubernetes.io/cluster/<name>` subnet tags. Modern EKS does not require
them for subnet discovery, and the EKS module tags the node security group itself. Do not add them
speculatively.

The node security group also needs `karpenter.sh/discovery`, but that security group is created by
the **EKS** module — so that tag is applied in Phase 2 via `node_security_group_tags`, not here.
Phase 2 owns it; make sure your completion report says so.

### 1.5 Flow logs

Three separate variables all default to `false` and all three are required for working CloudWatch
flow logs. This trips people constantly:

```hcl
  enable_flow_log                      = var.enable_flow_logs
  create_flow_log_cloudwatch_log_group = var.enable_flow_logs
  create_flow_log_cloudwatch_iam_role  = var.enable_flow_logs

  flow_log_traffic_type                             = "ALL"
  flow_log_max_aggregation_interval                 = 600   # 60 costs ~10x more
  flow_log_cloudwatch_log_group_retention_in_days   = var.flow_log_retention_days
```

Mind the inconsistent prefixes: IAM role/policy variables use `vpc_flow_log_*`, everything else uses
`flow_log_*`.

### 1.6 Harden the default security group and NACL

The default security group of a new VPC allows all traffic between anything attached to it. Nothing
should use it, but leaving it permissive is a standard audit finding (CIS, checkov `CKV2_AWS_12`).

```hcl
  manage_default_security_group  = true
  default_security_group_ingress = []
  default_security_group_egress  = []

  # Adopt these into state so they are managed and visible, but DO NOT empty
  # their rules — see the warning below.
  manage_default_network_acl = true
  manage_default_route_table = true
```

> 🛑 **Do not "harden" the default NACL by emptying its rules.** Every subnet in this VPC is
> associated with the **default** network ACL — no dedicated NACLs are created, since the module's
> `*_dedicated_network_acl` flags all default `false`. Setting `default_network_acl_ingress = []` /
> `_egress = []` therefore black-holes **all traffic in the entire VPC**. It would present as "nodes
> never join the cluster" and get debugged as a Karpenter or IAM problem for hours.
>
> The default NACL's allow-all rules are correct here. NACLs are a stateless, coarse second layer;
> the actual network boundary in this design is security groups plus private-subnet routing. If you
> want NACL-level controls, create **dedicated** NACLs per subnet tier with explicit rules — real
> work, and out of scope for the POC.
>
> `manage_default_network_acl = true` is still worth setting: it brings the resource into Terraform
> state so it is visible and cannot drift unnoticed.

### 1.7 VPC endpoints

Gateway endpoint for S3 is **always created** — it is free and it keeps ECR image-layer traffic (S3
under the hood) off the NAT gateway, which is a genuine cost saving, not just a security control.

Interface endpoints are behind `var.enable_vpc_endpoints`, which **defaults to `false`** (ADR-11).
At $0.01/endpoint/AZ/hour, the twelve endpoints below across three AZs are ~$263/month — the single
largest line item in the stack, larger than the EKS control plane and all three NAT gateways
combined. With NAT present they are defence-in-depth and a data-transfer optimisation, not a
requirement; for a no-NAT private cluster they become mandatory. Build them, default them off, and
document turning them on.

Use the module's own submodule, which exists at this version (verified):

```hcl
module "vpc_endpoints" {
  source  = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"
  version = "6.6.1"
  # ...
}
```

The endpoint set, and why each one is here:

| Service | Type | Needed for |
|---|---|---|
| `s3` | **Gateway** | ECR image layers, and anything writing to S3. Free. Always on. |
| `ecr.api`, `ecr.dkr` | Interface | Pulling container images without NAT. |
| `ec2` | Interface | Karpenter's `CreateFleet`/`DescribeInstanceTypes` calls. |
| `sts` | Interface | Credential assumption. |
| `sqs` | Interface | **Karpenter's interruption queue.** Miss this one and Spot handling breaks in an isolated VPC. |
| `eks`, `eks-auth` | Interface | `eks-auth` is what the **Pod Identity agent** calls to exchange tokens. Without it, Pod Identity fails in a no-NAT VPC. |
| `elasticloadbalancing` | Interface | AWS Load Balancer Controller (Phase 9). |
| `logs` | Interface | Control-plane and flow logs to CloudWatch. |
| `ssm`, `ssmmessages`, `ec2messages` | Interface | Session Manager — the only way onto a node in a fully private cluster. AWS's EKS private-cluster table lists only `ssm`; `ssmmessages`/`ec2messages` are the general Session Manager requirement. Keep all three. |
| `oidc-eks` | Interface | *Optional.* New in July 2026 — privately reaches the cluster's OIDC/JWKS endpoint for IRSA. This stack uses Pod Identity, so it is not required; include it only if you add IRSA-based workloads. Note it does **not** support VPC endpoint policies. |

**Deliberately excluded:** `com.amazonaws.<region>.autoscaling`. It appears in AWS's private-cluster
guidance only under *Cluster Autoscaler*, which drives Auto Scaling groups. Karpenter calls
`ec2:RunInstances` / `ec2:CreateFleet` directly and its IAM policy contains no `autoscaling:*`
actions at all. Adding it is ~$21/month for nothing. (The managed node group's own scaling is an
AWS-side operation and does not traverse your VPC.)

All interface endpoints get `private_dns_enabled = true` and a dedicated security group allowing
**443 from the VPC CIDR only** — not `0.0.0.0/0`, and not the node security group (which does not
exist yet at this point in the graph).

Interface endpoints are placed in the **private** subnets.

### 1.8 Outputs

Exactly interface-contract §5.1. Map `module.vpc.private_subnets` → `private_subnet_ids` etc. — the
upstream module's outputs are named `*_subnets` but our contract says `*_subnet_ids`, because a bare
`private_subnets` reads like it holds CIDRs. Do the renaming here, once.

---

## Security requirements owned by this phase

- **S-10** Nodes and pods have no public IP and live only in private subnets.
- **S-11** Control-plane ENIs sit in intra subnets with no route to a NAT gateway.
- **S-12** Default security group and default NACL are managed and have no rules.
- **S-13** VPC endpoint security group allows 443 from the VPC CIDR only.
- **S-14** VPC flow logs enabled by default with a defined retention period.
- **S-15** No security group in this module has an ingress rule with `0.0.0.0/0`.

---

## Acceptance criteria

Without credentials:

```bash
terraform fmt -check -recursive
terraform init -backend=false
terraform validate
```

Static assertions — all must produce **no output**:

```bash
cd modules/network

# 1. No hardcoded CIDRs outside the computed locals.
grep -nE '"10\.[0-9]+\.' main.tf | grep -v 'cidrsubnet' | grep -v '^\s*#'

# 2. No wide-open ingress.
grep -n '0\.0\.0\.0/0' main.tf | grep -i ingress

# 3. The discovery tag is derived, never literal.
#    Strip comments first — this file is REQUIRED to contain explanatory
#    comments mentioning these very strings, and an unanchored grep would
#    match them and report a false failure.
grep -vE '^[[:space:]]*#' main.tf | grep -n 'karpenter.sh/discovery' | grep -v 'var.name'
```

Positive checks:

```bash
grep -q 'enable_nat_gateway *= *true'            main.tf && echo "PASS: NAT enabled"
grep -q 'create_flow_log_cloudwatch_log_group'   main.tf && echo "PASS: flow log group"
grep -q 'create_flow_log_cloudwatch_iam_role'    main.tf && echo "PASS: flow log role"
grep -q 'default_security_group_ingress *= *\[\]' main.tf && echo "PASS: default SG locked"
grep -q 'opt-in-not-required'                    main.tf && echo "PASS: AZ filter"
```

With credentials (optional, and the only phase where a targeted plan is genuinely useful):

```bash
terraform plan -target=module.network
# Expect ~40-60 resources with production defaults; confirm 3 NAT gateways
# (or 1 with single_nat_gateway = true) and 9 subnets.
```

---

## Notes for the implementing agent

- Do not reference `module.eks` anywhere. It does not exist yet.
- Do not create the node security group or tag it. Phase 2 owns that.
- `module.vpc.intra_subnets` is the list you hand to EKS as `control_plane_subnet_ids` in Phase 2 —
  make sure it is exported.
- Write `modules/network/README.md` with a small table of the subnet plan for the default CIDR. The
  next person to change `vpc_cidr` will thank you.

---

## Agent prompt

```text
Implement Phase 1 of the EKS + Karpenter Terraform assessment.

Working directory: /home/artin/personal/git/dso-projects/terraform

SCOPE BOUNDARY — non-negotiable, applies to every action you take:
  1. Your working directory is /home/artin/personal/git/dso-projects/terraform. You never leave it.
     Every path in this prompt and in every doc it references is RELATIVE TO THAT DIRECTORY.
  2. The sibling directory /home/artin/personal/git/dso-projects/architecture is a DIFFERENT,
     UNRELATED assessment. Do not read it, write to it, list it, grep it, or cd into it.
     There is nothing in it you need.
  3. Create NOTHING at the repository root (/home/artin/personal/git/dso-projects) — no new files,
     no new directories, no sibling of terraform/ or architecture/. Everything you produce
     lives under terraform/. That includes .gitignore, CI config, scripts and notes.
  4. Do not run commands that walk the whole repo (`find /home/artin/personal/git/dso-projects`,
     `grep -r` from the root, `git status` at the root). Scope every search to terraform/.
  If you believe you genuinely need something outside terraform/, stop and say so in your
  completion report instead of doing it.

Read these files first, in this order:
  1. docs/00-architecture-and-decisions.md          (ADR-1, ADR-11)
  2. docs/contracts/interface-contract.md           (NORMATIVE — §2.3 tags, §5.1 signature)
  3. docs/reference/version-pinning.md              (VPC module 6.6.1; §5 dangerous defaults)
  4. docs/phases/phase-01-networking.md             (your specification)
  5. docs/phases/phase-00-scaffold-and-state.md     (read its Completion report only)

Implement modules/network/ exactly as phase-01 specifies, then wire it into
main.tf as `module "network"` and add the networking outputs to outputs.tf.

Constraints:
  - Module output names must match interface-contract §5.1 exactly.
  - Derive all subnet CIDRs with cidrsubnet() from var.vpc_cidr. Do not hardcode CIDRs.
  - The karpenter.sh/discovery tag value must come from var.name, never a literal.
  - Do not reference module.eks — it does not exist until Phase 2.
  - Do not create or tag the node security group — Phase 2 owns it.
  - terraform fmt -recursive must be clean.
  - Do NOT run `terraform apply`.

When finished, run everything under "Acceptance criteria", then fill in the
"## Completion report" section at the bottom of docs/phases/phase-01-networking.md
and stop. Do not start Phase 2.
```

---

## Completion report

*To be filled in by the implementing agent.*

- Status:
- Files created/changed:
- Deviations from spec:
- Names added to interface-contract.md:
- Verification run:
- Notes for the next phase:
