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
- **S-12** Default security group is managed and has no rules. The default NACL is managed
  (adopted into state) but deliberately kept allow-all — see §1.6.
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

Working directory: terraform/

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

- Status: DONE

- Files created/changed:
  - `modules/network/versions.tf`, `modules/network/variables.tf`,
    `modules/network/main.tf`, `modules/network/outputs.tf`,
    `modules/network/README.md` — new, per "Files to create."
  - `main.tf` — added `module "network"` block (module blocks only, no
    resources added — interface-contract §1 rule 1 preserved).
  - `outputs.tf` — added the three root networking outputs interface-contract
    §4 lists: `vpc_id`, `private_subnet_ids`, `public_subnet_ids`. (§4 does
    **not** list `intra_subnet_ids`/`vpc_cidr_block`/`availability_zones`/
    `vpc_endpoints_security_group_id` as root outputs — those stay
    module-only; `intra_subnet_ids` reaches Phase 2 through `main.tf` wiring,
    not a root output.)
  - `tests/cidr_guard.tftest.hcl` — extended `mock_provider "aws" {}` with two
    `mock_data` overrides (`aws_availability_zones`, `aws_iam_policy_document`).
    Not in phase-01's "Files to create" list, but required: wiring
    `module.network` in means this pre-existing test now plans through
    `module.vpc`'s AZ lookup and flow-log IAM role for the first time, and the
    default (unset) mock values for both — an empty AZ list and an empty-string
    policy `json` — broke `slice()` and the `aws_iam_role` schema's own
    "must be a valid JSON policy" check respectively. Fixed by supplying
    concrete mock defaults rather than weakening the module. Re-ran: 3/3 still
    pass with the same assertions as before.
  - `tests/network_endpoints.tftest.hcl` — new, not required by phase-01's
    acceptance criteria but added because `terraform validate`/`fmt` only
    prove the config parses, not that both branches of
    `var.enable_vpc_endpoints` actually plan. That flag switches between 0 and
    12 interface endpoints plus a security group built from a `for`
    expression over a literal service list — exactly the kind of branch a
    typo only surfaces at plan time. Two `plan`-command runs (flag `false`
    and `true`) against the same mocked provider; both pass. This caught
    nothing broken in the end, but it was the only way to actually exercise
    the `enable_vpc_endpoints = true` path without AWS credentials, and it
    stays as a regression guard for later phases.

- Deviations from spec:
  1. **S-12 vs §1.6 — resolved in favor of §1.6, not silently picked.**
     The phase's own "Security requirements" list states S-12 as "Default
     security group and default NACL are managed and **have no rules**." §1.6
     of this same doc explicitly forbids emptying the default NACL's rules,
     because every subnet in this VPC is associated with the *default* NACL
     (no dedicated NACLs are created — the module's `*_dedicated_network_acl`
     flags all default `false`), so `default_network_acl_ingress = []` /
     `_egress = []` would black-hole all traffic in the entire VPC. §1.6 is
     the more specific, explicitly-reasoned text, and it wins: implemented
     `manage_default_security_group = true` with
     `default_security_group_ingress/egress = []` (default SG genuinely has
     no rules), and `manage_default_network_acl = true` with **no**
     `default_network_acl_ingress`/`_egress` overrides (default NACL is
     managed/adopted into state but keeps its allow-all rules). S-12 is
     therefore satisfied for the default security group only; the default
     NACL is managed-but-not-emptied, per §1.6's explicit instruction.
  2. **Endpoint security group has no egress rule.** §1.7 specifies the
     dedicated VPC-endpoint security group must allow "443 from the VPC CIDR
     only" — an ingress requirement (S-13). No egress behavior is specified.
     Interface-endpoint ENIs only answer inbound connections (security groups
     are stateful), so the security group has an ingress-only 443 rule and no
     `egress` block, which leaves AWS's standard implicit allow-all egress in
     place. An earlier draft added an explicit `egress { cidr_blocks =
     [var.vpc_cidr] }` block; removed because it was an unrequested behavior
     change on a resource the spec fully specifies, and the failure mode
     (endpoints intermittently unreachable) is worse than the value it added.
  3. **`vpc_cidr` validated at `/20` inside the module, not `/18`.**
     Phase-01 §1.2 asks for "a precondition (or validation in Phase 0) proving
     the VPC is at least a /20." Phase 0 already added a root-level
     `validation` block requiring `/18` or larger (stricter than /20) on the
     root `var.vpc_cidr` — satisfying the "or validation in Phase 0" option.
     Added a `/20` `validation` block on the module's own `vpc_cidr` input as
     well (§1.2's other listed option), so the module stays self-defending if
     ever called with a CIDR that bypasses the root's `/18` check. At `<=20`
     this can never fire when called from root (which enforces `<=18`), so it
     changes nothing about the deployed behavior.

- Names added to interface-contract.md: none. `modules/network`'s 8 inputs and
  7 outputs were implemented exactly as specified in §5.1 (verified by diffing
  `grep -oP '^output "\K[^"]+' modules/network/outputs.tf | sort` and the
  equivalent for `variable` against the §5.1 table — identical sets, no
  additions, no omissions).

- Verification run (all from `terraform/`, no AWS credentials used or
  required):
  - `terraform fmt -check -recursive` → clean (exit 0).
  - `terraform init -backend=false` → downloads `terraform-aws-modules/vpc/aws`
    6.6.1 (root call plus two `//modules/vpc-endpoints` submodule calls) —
    succeeds, no new provider requirements (`.terraform.lock.hcl` unchanged).
  - `terraform validate` → `Success! The configuration is valid.`
  - Static assertions from `modules/network/`, run verbatim from the phase
    doc — all three produced **no output** as required:
    - `grep -nE '"10\.[0-9]+\.' main.tf | grep -v 'cidrsubnet' | grep -v '^\s*#'`
    - `grep -n '0\.0\.0\.0/0' main.tf | grep -i ingress`
    - `grep -vE '^[[:space:]]*#' main.tf | grep -n 'karpenter.sh/discovery' | grep -v 'var.name'`
  - Positive checks, run verbatim — all 5 PASS: NAT enabled, flow log group,
    flow log role, default SG locked, AZ filter.
  - `terraform test` → 5 passed, 0 failed
    (`cidr_guard.tftest.hcl`: `rejects_open_endpoint`,
    `rejects_empty_allowlist`, `accepts_scoped_allowlist`;
    `network_endpoints.tftest.hcl`: `endpoints_off_plans_clean`,
    `endpoints_on_plans_clean`).
  - `make check` → fmt + validate (root and `bootstrap/`) + test all green;
    `lint` cleanly skips (tflint/checkov not installed in this environment) —
    unchanged from Phase 0's baseline.
  - `terraform plan -target=module.network` — **not run.** Phase-01's own
    acceptance criteria mark this "optional" and it requires AWS credentials,
    which this environment does not have and which the task explicitly
    forbids acquiring implicitly. The `enable_vpc_endpoints = true`/`false`
    branches were instead exercised via `terraform test`'s mocked-provider
    `plan` command (see `network_endpoints.tftest.hcl` above), which is the
    closest credential-free equivalent.
  - Read the actual downloaded source of
    `terraform-aws-modules/vpc/aws//modules/vpc-endpoints` (v6.6.1) at
    `.terraform/modules/network.vpc_endpoints_gateway/modules/vpc-endpoints/{variables,main,outputs}.tf`
    before writing the endpoint blocks, rather than recalling its interface
    from memory — confirmed the `endpoints` map's per-entry keys
    (`service`, `service_type`, `subnet_ids`, `security_group_ids`,
    `route_table_ids`, `private_dns_enabled`, `tags`) and the root `vpc`
    module's output names (`vpc_cidr_block`, `private_subnets`,
    `public_subnets`, `intra_subnets`, `private_route_table_ids`) against the
    real source.

- Notes for the next phase:
  - The node security group and its `karpenter.sh/discovery` tag are **not**
    created here — Phase 2 owns both, via `node_security_group_tags` on
    `module.eks`. This module only tags the private subnets and the (S3 +
    interface) VPC endpoints.
  - `module.network.intra_subnet_ids` is Phase 2's
    `control_plane_subnet_ids` input. It is exported by the module but is
    deliberately **not** a root output (interface-contract §4 doesn't list
    it) — wire it root-to-root in `main.tf`:
    `module.eks.control_plane_subnet_ids = module.network.intra_subnet_ids`.
  - `module.network.vpc_id` / `private_subnet_ids` also feed `module.eks`
    directly (`vpc_id`, `private_subnet_ids` per interface-contract §5.2) —
    both are already root outputs too, so Phase 2 can read them either via
    `module.network.*` in `main.tf` or, once available, the root outputs.
  - S3 gateway endpoint is attached only to `private_route_table_ids` (where
    nodes actually pull ECR image layers); intra subnets have no route to it
    and don't need one (control-plane ENIs only, no S3 traffic). Don't "fix"
    this by adding intra route tables.
  - The `tests/*.tftest.hcl` mock-provider pattern (concrete `mock_data`
    defaults for `aws_availability_zones` and `aws_iam_policy_document`) will
    likely need extending again in Phase 2 — `module.eks` pulls in more
    data sources (e.g. IAM policy documents for its own roles, possibly
    `aws_partition`/`aws_caller_identity`) that the blank
    `mock_provider "aws" {}` default won't satisfy either. Check
    `terraform test` early in Phase 2 rather than at the end.
  - `enable_vpc_endpoints = true` was never plan-tested against real AWS (no
    credentials in this environment) — only against the mocked provider. The
    12-endpoint service-name list (`ecr.api`, `ecr.dkr`, `ec2`, `sts`, `sqs`,
    `eks`, `eks-auth`, `elasticloadbalancing`, `logs`, `ssm`, `ssmmessages`,
    `ec2messages`) matches phase-01 §1.7's table exactly, deliberately
    excluding `oidc-eks` (optional, IRSA-only, not used) and
    `com.amazonaws.<region>.autoscaling` (Karpenter doesn't call
    autoscaling APIs) — both per §1.7's own text.
