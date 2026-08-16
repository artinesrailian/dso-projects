# AZ selection. The opt-in-status filter matters: without it, accounts with Local
# Zones or Wavelength Zones enabled can have those returned in `names`, and EKS
# cannot place a control-plane ENI in them.
data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  # /19 per AZ - 8,187 usable IPs. The VPC CNI assigns a real VPC IP to every
  # pod, so this is pod capacity, not node capacity - a /24 here caps out at
  # ~250 pods per AZ and fails in a way that looks like a scheduling bug.
  private_subnets = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 3, i)]

  # /24 is plenty: only NAT gateways and public load balancers live here.
  public_subnets = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 8, 96 + i)]

  # /24, no NAT route at all - EKS control-plane ENIs only.
  intra_subnets = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 8, 99 + i)]
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.6.1"

  name = var.name
  cidr = var.vpc_cidr
  azs  = local.azs

  private_subnets = local.private_subnets
  public_subnets  = local.public_subnets
  intra_subnets   = local.intra_subnets

  # enable_nat_gateway defaults to false in this module. Without it the private
  # subnets have no egress, nodes cannot pull images, and they never join.
  enable_nat_gateway     = true
  single_nat_gateway     = var.single_nat_gateway
  one_nat_gateway_per_az = !var.single_nat_gateway

  enable_dns_hostnames = true
  enable_dns_support   = true # required for the EKS private endpoint to resolve

  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
    # Karpenter's EC2NodeClass subnetSelectorTerms matches on exactly this. If
    # this tag and the selector ever disagree, Karpenter reports "no subnets
    # found" and provisions nothing, with no other symptom.
    "karpenter.sh/discovery" = var.name
  }

  # All three of these must be true together for working CloudWatch flow logs -
  # they default false independently and each silently no-ops without the others.
  enable_flow_log                      = var.enable_flow_logs
  create_flow_log_cloudwatch_log_group = var.enable_flow_logs
  create_flow_log_cloudwatch_iam_role  = var.enable_flow_logs

  flow_log_traffic_type                           = "ALL"
  flow_log_max_aggregation_interval               = 600 # 60 costs ~10x more
  flow_log_cloudwatch_log_group_retention_in_days = var.flow_log_retention_days

  manage_default_security_group  = true
  default_security_group_ingress = []
  default_security_group_egress  = []

  # Adopted into state so it is visible and cannot drift unnoticed, but its
  # allow-all rules are NOT emptied: every subnet in this VPC uses the default
  # NACL (no dedicated NACLs are created), so blanking its rules would
  # black-hole all traffic in the entire VPC. The real network boundary here is
  # security groups plus private-subnet routing, not the NACL layer.
  manage_default_network_acl = true
  manage_default_route_table = true

  tags = var.tags
}

# Dedicated security group for interface VPC endpoints: 443 from the VPC CIDR
# only. Cannot reference the node security group here - it does not exist yet
# (EKS module, Phase 2) - and must not open to 0.0.0.0/0 (S-13).
resource "aws_security_group" "vpc_endpoints" {
  count = var.enable_vpc_endpoints ? 1 : 0

  name_prefix = "${var.name}-vpc-endpoints-"
  description = "Allow HTTPS from inside the VPC to interface VPC endpoints."
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "HTTPS from the VPC CIDR only"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # No egress block: interface endpoint ENIs only answer inbound connections
  # (security groups are stateful), and S-13 only specifies the ingress rule.

  tags = merge(var.tags, { Name = "${var.name}-vpc-endpoints" })

  lifecycle {
    create_before_destroy = true
  }
}

# S3 gateway endpoint: free, always on. Keeps ECR image-layer traffic (S3 under
# the hood) off the NAT gateway - a genuine cost saving, not just a control.
module "vpc_endpoints_gateway" {
  source  = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"
  version = "6.6.1"

  vpc_id = module.vpc.vpc_id

  endpoints = {
    s3 = {
      service         = "s3"
      service_type    = "Gateway"
      route_table_ids = module.vpc.private_route_table_ids
      tags            = { Name = "${var.name}-s3" }
    }
  }

  tags = var.tags
}

# Interface endpoints, gated on var.enable_vpc_endpoints (defaults false - see
# ADR-11: ~$263/month for 12 endpoints x 3 AZs, the largest line item in the
# stack). With NAT present these are defence-in-depth plus a data-transfer
# saving, not a requirement.
module "vpc_endpoints_interface" {
  source  = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"
  version = "6.6.1"

  count = var.enable_vpc_endpoints ? 1 : 0

  vpc_id = module.vpc.vpc_id

  endpoints = {
    for svc in [
      "ecr.api", "ecr.dkr", "ec2", "sts", "sqs", "eks", "eks-auth",
      "elasticloadbalancing", "logs", "ssm", "ssmmessages", "ec2messages",
      ] : replace(svc, ".", "_") => {
      service             = svc
      service_type        = "Interface"
      subnet_ids          = module.vpc.private_subnets
      security_group_ids  = [aws_security_group.vpc_endpoints[0].id]
      private_dns_enabled = true
      tags                = { Name = "${var.name}-${svc}" }
    }
  }

  tags = var.tags
}
