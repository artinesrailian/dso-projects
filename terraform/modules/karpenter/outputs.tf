# Exactly interface-contract.md SS5.3's Phase 3 subset (6 of its 7 outputs).
# helm_release_name is Phase 4's — it names a helm_release resource this
# module does not have yet.

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
