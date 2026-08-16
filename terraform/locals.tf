locals {
  # e.g. "opsfleet-poc" — the single name prefix every AWS resource derives from.
  name = "${var.project_name}-${var.environment}"

  tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Component   = "eks-karpenter-poc"
    },
    var.additional_tags,
  )
}
