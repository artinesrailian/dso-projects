variable "cluster_name" {
  description = "EKS cluster name. Feeds the Karpenter node IAM role name, the controller policy's tag-based scoping (RunInstances/CreateFleet conditions), and the pod identity association's cluster_name."
  type        = string
}

variable "cluster_endpoint" {
  description = "EKS API endpoint. Consumed by helm_release.karpenter's settings.clusterEndpoint (Phase 4); unused by this module's AWS-only resources in main.tf."
  type        = string
}

variable "karpenter_version" {
  description = "Karpenter Helm chart version. Pins both helm_release.karpenter and helm_release.karpenter_crd (Phase 4) — the two chart versions must always match."
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace the Karpenter controller runs in. Feeds the pod identity association's namespace and both Helm releases' namespace (Phase 4)."
  type        = string
}

variable "node_security_group_id" {
  description = "Node security group ID carrying the karpenter.sh/discovery tag. Declared here per interface-contract.md SS5.3; not consumed by this phase's AWS-only resources — see this module's README."
  type        = string
}

variable "create_spot_service_linked_role" {
  description = <<-EOT
    Create the AWSServiceRoleForEC2Spot service-linked role (prerequisite P2).
    Defaults to false at the root: the AWS provider's
    aws_iam_service_linked_role resource fails outright if the role already
    exists, which is the common case on any account that has ever launched a
    Spot instance. See this module's README for why an idempotent
    adopt-or-create path (a Terraform `import` block) was evaluated and
    rejected.
  EOT
  type        = bool
}

### Tags #########################################################################

variable "tags" {
  description = "Base tag set applied to every resource this module creates."
  type        = map(string)
  default     = {}
}
