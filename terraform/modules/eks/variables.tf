### Cluster identity ###########################################################

variable "name" {
  description = "Cluster name and resource name prefix. Passed straight through to the eks module's `name` input (v20 called this cluster_name)."
  type        = string
}

variable "kubernetes_version" {
  description = "EKS Kubernetes minor version, e.g. \"1.36\" (v20 called this cluster_version)."
  type        = string
}

### Networking ##################################################################

variable "vpc_id" {
  description = "VPC the cluster and its node groups are placed into."
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs — where nodes (and therefore pods) are placed."
  type        = list(string)
}

variable "control_plane_subnet_ids" {
  description = "Intra subnet IDs — EKS control-plane ENIs only, no NAT route. This is modules/network's intra_subnet_ids."
  type        = list(string)
}

variable "endpoint_public_access" {
  description = "Enable the public Kubernetes API endpoint. Defaults to false in the eks module itself — the caller (root) is expected to pass an explicit value."
  type        = bool
}

variable "endpoint_public_access_cidrs" {
  description = "CIDRs allowed to reach the public Kubernetes API endpoint. Ignored when endpoint_public_access is false."
  type        = list(string)
}

variable "endpoint_private_access" {
  description = "Enable the private Kubernetes API endpoint."
  type        = bool
}

### Logging ######################################################################

variable "enabled_log_types" {
  description = "EKS control plane log types to ship to CloudWatch (v20 called this cluster_enabled_log_types)."
  type        = list(string)
}

variable "log_retention_days" {
  description = "CloudWatch log group retention, in days, for EKS control plane logs."
  type        = number
}

### Access entries ###############################################################

variable "admin_principal_arns" {
  description = "IAM principals granted cluster-admin via an EKS access entry with the AmazonEKSClusterAdminPolicy access policy."
  type        = list(string)
  default     = []
}

variable "developer_principal_arns" {
  description = "IAM principals bound to developer_rbac_group via a STANDARD access entry with no AWS managed access policy. Permissions come from the ClusterRole phase-05 SS5.3d creates, not this module."
  type        = list(string)
  default     = []
}

variable "developer_rbac_group" {
  description = "Kubernetes group every developer access entry is bound to via kubernetes_groups."
  type        = string
}

### Alerting (SS2.3 — the one unrecoverable-failure detector) ###################

variable "alert_email" {
  description = "Subscribed to the SNS topic that receives the KMS-key-danger alarm. Empty means no subscriber, i.e. the alarm is silent."
  type        = string
  default     = ""
}

### Bootstrap managed node group #################################################

variable "bootstrap_node_instance_types" {
  description = "Instance types for the managed node group that hosts the Karpenter controller."
  type        = list(string)
}

variable "bootstrap_node_ami_type" {
  description = "AMI type for the bootstrap managed node group. Must match the architecture of bootstrap_node_instance_types."
  type        = string
}

variable "bootstrap_node_min_size" {
  description = "Minimum size of the bootstrap managed node group."
  type        = number
}

variable "bootstrap_node_max_size" {
  description = "Maximum size of the bootstrap managed node group."
  type        = number
}

variable "bootstrap_node_desired_size" {
  description = "Desired size of the bootstrap managed node group. Note: the eks module ignores changes to this after creation (see reference/gotchas.md G-06)."
  type        = number
}

variable "taint_bootstrap_nodes" {
  description = "Taints the bootstrap group CriticalAddonsOnly=true:NoSchedule so user workloads only land on Karpenter-provisioned nodes."
  type        = bool
}

### Optional phases ##############################################################

variable "enable_metrics_server" {
  description = "Phase 10 only; ignored by this module until then. Declared here to hold the interface-contract SS5.2 signature stable across phases."
  type        = bool
  default     = false
}

### Tags #########################################################################

variable "tags" {
  description = "Base tag set applied to every resource this module creates. Modules merge their own resource-specific tags on top."
  type        = map(string)
  default     = {}
}
