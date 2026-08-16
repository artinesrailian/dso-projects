# Root outputs. Phase 2 adds cluster outputs, Phases 3-4 add Karpenter outputs.
# See interface-contract.md SS4 for the full, final list this file must converge on.

output "vpc_id" {
  description = "ID of the dedicated VPC."
  value       = module.network.vpc_id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets (nodes and pods)."
  value       = module.network.private_subnet_ids
}

output "public_subnet_ids" {
  description = "IDs of the public subnets (NAT gateways, public load balancers)."
  value       = module.network.public_subnet_ids
}
