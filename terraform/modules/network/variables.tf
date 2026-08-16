variable "name" {
  description = "Name prefix for every resource this module creates. Also the value of the karpenter.sh/discovery tag — must equal local.name at the root so the discovery contract has a single source."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the dedicated VPC. Must be /20 or larger so the computed intra subnets (a /24 slice) stay within range and cidrsubnet() cannot fail with an unhelpful error."
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0)) && tonumber(split("/", var.vpc_cidr)[1]) <= 20
    error_message = "vpc_cidr must be a valid CIDR block with a prefix length of /20 or larger (smaller number)."
  }
}

variable "az_count" {
  description = "Number of availability zones to spread the VPC across. Drives subnet slicing."
  type        = number

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3
    error_message = "az_count must be 2 or 3."
  }
}

variable "single_nat_gateway" {
  description = "true = one NAT gateway for all AZs (POC cost saver, single point of failure). false = one NAT gateway per AZ."
  type        = bool
}

variable "enable_flow_logs" {
  description = "Enable CloudWatch VPC flow logs (log group, IAM role and the flow log itself)."
  type        = bool
}

variable "flow_log_retention_days" {
  description = "CloudWatch log group retention, in days, for VPC flow logs."
  type        = number
}

variable "enable_vpc_endpoints" {
  description = "Create the interface VPC endpoints (ecr, ec2, sts, sqs, eks, elb, logs, ssm, ...). The S3 gateway endpoint is always created regardless of this flag."
  type        = bool
}

variable "tags" {
  description = "Base tag set applied to every resource this module creates. Modules merge their own resource-specific tags on top."
  type        = map(string)
  default     = {}
}
