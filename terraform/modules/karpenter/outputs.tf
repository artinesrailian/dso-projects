# interface-contract.md SS5.3's full 7-output signature: Phase 3's 6 AWS-side
# outputs plus Phase 4's helm_release_name below.

output "controller_iam_role_arn" {
  description = "ARN of the Karpenter controller IAM role, bound to the karpenter service account via Pod Identity."
  value       = module.karpenter.iam_role_arn
}

output "node_iam_role_name" {
  description = "Name of the IAM role assumed by Karpenter-launched EC2 instances."
  value       = module.karpenter.node_iam_role_name
}

output "node_iam_role_arn" {
  description = "ARN of the IAM role assumed by Karpenter-launched EC2 instances."
  value       = module.karpenter.node_iam_role_arn
}

output "interruption_queue_name" {
  description = "Name of the SQS queue carrying Spot interruption / rebalance / state-change events."
  value       = module.karpenter.queue_name
}

output "interruption_queue_arn" {
  description = "ARN of the SQS interruption queue."
  value       = module.karpenter.queue_arn
}

output "namespace" {
  description = "Kubernetes namespace the Karpenter controller's Pod Identity association targets."
  value       = module.karpenter.namespace
}

output "helm_release_name" {
  description = "Karpenter Helm release name. Phase 5 depends_on this so that NodePools are applied only after the CRDs are established."
  value       = helm_release.karpenter.name
}
