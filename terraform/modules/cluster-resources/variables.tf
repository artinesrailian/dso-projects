variable "cluster_name" {
  description = "EKS cluster name. Feeds both the karpenter.sh/discovery selectors in EC2NodeClass and the EC2NodeClass Name tag."
  type        = string
}

variable "node_iam_role_name" {
  description = "IAM role name Karpenter-launched nodes assume. Becomes EC2NodeClass.spec.role (never spec.instanceProfile — Karpenter v1 builds the instance profile itself)."
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace the helm_release.cluster_resources release targets. The chart's objects are mostly cluster-scoped; this is the release's own namespace."
  type        = string
}

variable "node_ami_alias" {
  description = "EC2NodeClass AMI alias, e.g. al2023@latest. Must be the ONLY amiSelectorTerms entry — CEL rejects an alias combined with any other term."
  type        = string
}

variable "capacity_types" {
  description = "Karpenter capacity types allowed in both NodePools' requirements. Valid values: spot, on-demand."
  type        = list(string)
}

variable "cpu_limit" {
  description = "Total vCPU ceiling across all enabled NodePools. Divided by local.enabled_pool_count because spec.limits is per-NodePool, not cluster-wide."
  type        = number
}

variable "memory_limit_gi" {
  description = "Total memory ceiling (GiB) across all enabled NodePools, divided the same way as cpu_limit. Required so every NodePool carries both a cpu AND a memory limit (S-52) — a cpu-only cap lets a memory-heavy workload provision far more instance than intended."
  type        = number
}

variable "default_arch" {
  description = "arm64 or amd64. Decides which NodePool gets the higher weight, and therefore which pool an unconstrained pod lands on."
  type        = string

  validation {
    condition     = contains(["arm64", "amd64"], var.default_arch)
    error_message = "default_arch must be either \"arm64\" or \"amd64\"."
  }
}

variable "enable_amd64" {
  description = "Render the amd64 (x86) NodePool."
  type        = bool
}

variable "enable_arm64" {
  description = "Render the arm64 (Graviton) NodePool."
  type        = bool
}

variable "governed_namespaces" {
  description = "Namespaces this chart creates with PSA restricted labels, a ResourceQuota and a LimitRange (§5.3c), and binds the developer ClusterRole into via a per-namespace RoleBinding (§5.3d)."
  type        = list(string)
}

variable "developer_namespaces" {
  description = <<-EOT
    Namespaces Phase 2's developer access entries are scoped to. Not consumed
    directly by any resource in this module — modules/eks's access entries
    carry no policy_associations, so there is no access_scope to wire this
    into. It exists solely for the lifecycle.precondition below, which is the
    real enforcement point tying access (this variable) to governance
    (governed_namespaces): every non-wildcard entry here must also appear
    there, or Terraform hands out access to a namespace whose guardrails may
    not exist.
  EOT
  type        = list(string)
}

variable "developer_rbac_group" {
  description = "Kubernetes group the developer ClusterRole is bound to via a per-namespace RoleBinding. Phase 2's access entries reference this same group with no AWS managed access policy — this chart is what actually grants Kubernetes-side permissions."
  type        = string
}

variable "namespace_quota" {
  description = "Per-namespace ResourceQuota values, applied to every entry in governed_namespaces. Snake_case here (matches the root variable); mapped to the chart's camelCase Helm values in main.tf."
  type = object({
    requests_cpu    = string
    requests_memory = string
    limits_cpu      = string
    limits_memory   = string
    max_deployments = number
  })
}

variable "karpenter_helm_release_name" {
  description = "Name of the karpenter helm_release (module.karpenter.helm_release_name). Used only as a depends_on edge, traced through the module-input reference graph, so the NodePool/EC2NodeClass CRDs are guaranteed to exist before this chart's CRs are applied (G-19)."
  type        = string
}

variable "tags" {
  description = "Base tag set. Rendered into EC2NodeClass.spec.tags — the only way Karpenter-launched instances get cost-allocation tags, since Karpenter calls ec2:CreateFleet itself and the AWS provider's default_tags never reaches them."
  type        = map(string)
  default     = {}
}
