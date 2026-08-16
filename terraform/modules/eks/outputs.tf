# Exactly interface-contract.md SS5.2. Remember the asymmetry: the upstream
# module's OUTPUTS kept the v20 cluster_* names even though its INPUTS were
# renamed in v21 — module.eks.name and module.eks.kubernetes_version do not
# exist.

output "cluster_name" {
  description = "EKS cluster name (local.name at the root)."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint."
  value       = module.eks.cluster_endpoint
}

output "cluster_version" {
  description = "Actual running Kubernetes version, as reported by the module — not var.kubernetes_version."
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
  description = "Node security group — carries the karpenter.sh/discovery tag Karpenter's EC2NodeClass matches on."
  value       = module.eks.node_security_group_id
}

output "oidc_provider_arn" {
  description = "ARN of the cluster's OIDC provider, for any IRSA that remains."
  value       = module.eks.oidc_provider_arn
}

output "kms_key_arn" {
  description = "ARN of the customer-managed KMS key used for Kubernetes Secrets envelope encryption."
  value       = module.eks.kms_key_arn
}
