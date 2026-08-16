# Root outputs. Phases 3-4 add Karpenter outputs.
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

output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API endpoint."
  value       = module.eks.cluster_endpoint
}

output "cluster_version" {
  description = "Actual running Kubernetes version (from the module output, not var.kubernetes_version)."
  value       = module.eks.cluster_version
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded certificate authority data for the cluster."
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "cluster_security_group_id" {
  description = "Cluster (control-plane) security group."
  value       = module.eks.cluster_security_group_id
}

output "node_security_group_id" {
  description = "Node security group — the one carrying the karpenter.sh/discovery tag."
  value       = module.eks.node_security_group_id
}

output "oidc_provider_arn" {
  description = "ARN of the cluster's OIDC provider, for any IRSA that remains."
  value       = module.eks.oidc_provider_arn
}

output "configure_kubectl" {
  description = "Run this to point kubectl at the new cluster."
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}
