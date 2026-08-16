output "vpc_id" {
  description = "ID of the dedicated VPC."
  value       = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  description = "CIDR block of the dedicated VPC."
  value       = module.vpc.vpc_cidr_block
}

output "private_subnet_ids" {
  description = "IDs of the private subnets (nodes and pods)."
  value       = module.vpc.private_subnets
}

output "public_subnet_ids" {
  description = "IDs of the public subnets (NAT gateways, public load balancers)."
  value       = module.vpc.public_subnets
}

output "intra_subnet_ids" {
  description = "IDs of the intra subnets (EKS control-plane ENIs only, no NAT route). This is Phase 2's control_plane_subnet_ids."
  value       = module.vpc.intra_subnets
}

output "availability_zones" {
  description = "Availability zones the VPC was spread across, in the order subnets were sliced."
  value       = local.azs
}

output "vpc_endpoints_security_group_id" {
  description = "Security group attached to the interface VPC endpoints. Null when enable_vpc_endpoints is false."
  value       = try(aws_security_group.vpc_endpoints[0].id, null)
}
