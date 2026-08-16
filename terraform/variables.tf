### General ##################################################################

variable "project_name" {
  description = "Name prefix component. Combined with environment to form local.name, which is the EKS cluster name."
  type        = string
  default     = "opsfleet"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,20}$", var.project_name))
    error_message = "project_name must start with a lowercase letter and contain only lowercase letters, digits and hyphens (2-21 chars)."
  }
}

variable "environment" {
  description = "Name prefix component. Combined with project_name to form local.name."
  type        = string
  default     = "poc"

  validation {
    condition     = contains(["poc", "dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: poc, dev, staging, prod."
  }
}

variable "region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.region))
    error_message = "region must look like a valid AWS region, e.g. us-east-1."
  }
}

variable "additional_tags" {
  description = "Merged over the base tag set (Project, Environment, ManagedBy, Component)."
  type        = map(string)
  default     = {}
}

### Cost controls #############################################################

variable "enable_budget_alarm" {
  description = "Creates an AWS Budget scoped to this stack's tags. The only automated guard against a forgotten cluster."
  type        = bool
  default     = true
}

variable "monthly_budget_usd" {
  description = <<-EOT
    Monthly budget threshold in USD. Must sit clearly ABOVE the idle band
    (~$255-295 at defaults including log ingest), or the 80% alert fires every
    normal month and gets muted. Raise it, do not lower it, if you enable
    VPC endpoints (+$263).
  EOT
  type        = number
  default     = 450
}

variable "budget_notification_email" {
  description = "Required when enable_budget_alarm is true. Alerts at 80% actual and 100% forecast spend."
  type        = string
  default     = ""

  validation {
    condition     = !var.enable_budget_alarm || length(var.budget_notification_email) > 0
    error_message = "budget_notification_email must be set when enable_budget_alarm is true — a budget with no subscriber is silent, which is worse than none because it looks like a control."
  }
}

variable "alert_email" {
  description = "Subscribed to the SNS topic that receives the KMS-key-danger alarm (Phase 2). Empty means no subscriber, i.e. the alarm is silent."
  type        = string
  default     = ""
}

### Networking #################################################################

variable "vpc_cidr" {
  description = <<-EOT
    CIDR block for the dedicated VPC. Must be /18 or larger: at /20 the computed
    intra subnets are /28 (11 usable IPs), against AWS's >=6 requirement and >=16
    recommendation for cluster subnets. /18 yields /26 intra subnets (59 usable).
  EOT
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0)) && tonumber(split("/", var.vpc_cidr)[1]) <= 18
    error_message = "vpc_cidr must be a valid CIDR block with a prefix length of /18 or larger (smaller number)."
  }
}

variable "az_count" {
  description = "Number of availability zones to spread the VPC and node groups across. Drives subnet slicing."
  type        = number
  default     = 3

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3
    error_message = "az_count must be 2 or 3."
  }
}

variable "single_nat_gateway" {
  description = "true = one NAT gateway for all AZs (POC cost saver, single point of failure)."
  type        = bool
  default     = false
}

variable "enable_vpc_flow_logs" {
  description = "Enable CloudWatch VPC flow logs."
  type        = bool
  default     = true
}

variable "flow_log_retention_days" {
  description = "CloudWatch log group retention, in days, for VPC flow logs."
  type        = number
  default     = 30
}

variable "enable_vpc_endpoints" {
  description = <<-EOT
    Controls the interface VPC endpoints only (~$263/month for 12 endpoints x 3
    AZs — the largest line item in the stack). Off by default; see ADR-11. The S3
    gateway endpoint is free and is always created regardless of this flag.
  EOT
  type        = bool
  default     = false
}

### Cluster #####################################################################

variable "kubernetes_version" {
  description = "EKS Kubernetes minor version, e.g. \"1.36\". See reference/version-pinning.md."
  type        = string
  default     = "1.36"

  validation {
    condition     = can(regex("^1\\.(3[0-9]|[4-9][0-9])$", var.kubernetes_version))
    error_message = "kubernetes_version must look like \"1.NN\", e.g. \"1.36\"."
  }
}

variable "cluster_endpoint_public_access" {
  description = "Enable the public Kubernetes API endpoint. Private access is always on."
  type        = bool
  default     = true

  validation {
    condition     = !var.cluster_endpoint_public_access || length(var.cluster_endpoint_public_access_cidrs) > 0
    error_message = "cluster_endpoint_public_access_cidrs must be non-empty when public access is enabled."
  }
}

variable "cluster_endpoint_public_access_cidrs" {
  description = <<-EOT
    CIDRs allowed to reach the public Kubernetes API endpoint. Required (and must be
    non-empty) when cluster_endpoint_public_access is true. 0.0.0.0/0 is rejected: an
    internet-open API endpoint is the most commonly flagged EKS misconfiguration, and
    IAM authentication is not a substitute for network scoping.
  EOT
  type        = list(string)
  default     = []

  validation {
    condition     = !contains(var.cluster_endpoint_public_access_cidrs, "0.0.0.0/0")
    error_message = "0.0.0.0/0 is not allowed. Set your own /32, or use cluster_endpoint_public_access = false."
  }
}

variable "cluster_endpoint_private_access" {
  description = "Enable the private Kubernetes API endpoint. Always on."
  type        = bool
  default     = true
}

variable "cluster_enabled_log_types" {
  description = "EKS control plane log types to ship to CloudWatch."
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}

variable "cluster_log_retention_days" {
  description = "CloudWatch log group retention, in days, for EKS control plane logs. 90 is the module default, not an AWS recommendation — drop to 7 for a POC."
  type        = number
  default     = 90
}

variable "cluster_admin_principal_arns" {
  description = "IAM principals granted cluster-admin via EKS access entries. Operators only."
  type        = list(string)
  default     = []
}

variable "developer_principal_arns" {
  description = <<-EOT
    IAM principals bound to the developer_rbac_group Kubernetes group via a STANDARD
    access entry with no AWS managed access policy. Permissions come from the ClusterRole
    in phase-05 SS5.3d. Prefer SSO role ARNs over IAM users.
  EOT
  type        = list(string)
  default     = []
}

variable "developer_namespaces" {
  description = "Namespaces the developer access entries are scoped to. Wildcards work (team-*); EKS does not validate they exist."
  type        = list(string)
  default     = ["demo"]
}

variable "governed_namespaces" {
  description = <<-EOT
    Namespaces Terraform creates with PSA restricted labels, a ResourceQuota and a
    LimitRange. Every non-wildcard entry in developer_namespaces must appear here —
    access without guardrails is the failure mode.
  EOT
  type        = list(string)
  default     = ["demo"]
}

variable "namespace_quota" {
  description = <<-EOT
    Per-namespace ResourceQuota applied to every entry in governed_namespaces.
    Fields match what phase-05's chart template reads from .Values.namespaceQuota
    (snake_case here, camelCase in the rendered Helm values). The quota's
    services.loadbalancers = "0" restriction is hardcoded in that template, not
    driven by this variable.
  EOT
  type = object({
    requests_cpu    = string
    requests_memory = string
    limits_cpu      = string
    limits_memory   = string
    max_deployments = number
  })
  default = {
    requests_cpu    = "20"
    requests_memory = "40Gi"
    limits_cpu      = "40"
    limits_memory   = "80Gi"
    max_deployments = 20
  }
}

### Karpenter ###################################################################

variable "karpenter_version" {
  description = "Karpenter Helm chart version — used for both the karpenter and karpenter-crd charts. See reference/version-pinning.md."
  type        = string
  default     = "1.14.0"
}

variable "karpenter_namespace" {
  description = "Kubernetes namespace the Karpenter controller and CRDs are installed into."
  type        = string
  default     = "kube-system"
}

variable "bootstrap_node_instance_types" {
  description = "Instance types for the managed node group that hosts the Karpenter controller. Graviton by default."
  type        = list(string)
  default     = ["t4g.medium"]
}

variable "bootstrap_node_ami_type" {
  description = "AMI type for the bootstrap managed node group. Must match the architecture of bootstrap_node_instance_types."
  type        = string
  default     = "AL2023_ARM_64_STANDARD"

  validation {
    condition     = contains(["AL2023_ARM_64_STANDARD", "AL2023_x86_64_STANDARD"], var.bootstrap_node_ami_type)
    error_message = "bootstrap_node_ami_type must be one of: AL2023_ARM_64_STANDARD, AL2023_x86_64_STANDARD."
  }
}

variable "bootstrap_node_min_size" {
  description = "Minimum size of the bootstrap managed node group."
  type        = number
  default     = 2
}

variable "bootstrap_node_max_size" {
  description = "Maximum size of the bootstrap managed node group."
  type        = number
  default     = 3
}

variable "bootstrap_node_desired_size" {
  description = "Desired size of the bootstrap managed node group. Note: the EKS module ignores changes to this after creation (see reference/gotchas.md G-06)."
  type        = number
  default     = 2
}

variable "taint_bootstrap_nodes" {
  description = "Taints the bootstrap group CriticalAddonsOnly=true:NoSchedule so user workloads only land on Karpenter-provisioned nodes."
  type        = bool
  default     = true
}

variable "create_spot_service_linked_role" {
  description = <<-EOT
    Creates AWSServiceRoleForEC2Spot (prerequisite P2). Defaults to false:
    aws_iam_service_linked_role fails outright if the role already exists,
    which is the common case on any account that has ever launched a Spot
    instance. A root-level `import` block was evaluated as an idempotent
    adopt-or-create alternative and rejected — it hard-fails terraform apply
    on a fresh account instead, the one case this variable exists to cover.
    See modules/karpenter/README.md for the full reasoning. Set true only
    after confirming the role does not already exist
    (`aws iam get-role --role-name AWSServiceRoleForEC2Spot`).
  EOT
  type        = bool
  default     = false
}

variable "request_service_quotas" {
  description = "Opens vCPU quota-increase requests in code (prerequisite P3). Approval is asynchronous — apply success does not mean the quota is raised."
  type        = bool
  default     = true
}

variable "vcpu_quota_target" {
  description = "Target vCPU quota value requested for both On-Demand and Spot Standard. Must exceed nodepool_cpu_limit plus the bootstrap group, or the account quota becomes the real ceiling."
  type        = number
  default     = 128
}

variable "developer_rbac_group" {
  description = "Kubernetes group bound to the developer ClusterRole. Access entries reference it via kubernetes_groups; no AWS managed access policy is associated."
  type        = string
  default     = "opsfleet:developers"
}

### NodePools ###################################################################

variable "nodepool_cpu_limit" {
  description = <<-EOT
    Total vCPU ceiling across all Karpenter NodePools. Karpenter's spec.limits is
    per-NodePool, so Phase 5 divides this by the number of enabled pools — with
    both on, each pool gets 50. The blast-radius cap.
  EOT
  type        = number
  default     = 100
}

variable "nodepool_memory_limit_gi" {
  description = "Total memory ceiling (GiB) across all Karpenter NodePools, divided the same way as nodepool_cpu_limit. A cpu-only limit lets a memory-heavy workload provision far more instances than intended."
  type        = number
  default     = 400
}

variable "nodepool_capacity_types" {
  description = "Karpenter capacity types to allow. Valid values: spot, on-demand."
  type        = list(string)
  default     = ["spot", "on-demand"]

  validation {
    condition     = alltrue([for t in var.nodepool_capacity_types : contains(["spot", "on-demand"], t)])
    error_message = "nodepool_capacity_types may only contain: spot, on-demand."
  }
}

variable "nodepool_default_arch" {
  description = "Which pool wins for a pod with no arch constraint, implemented via NodePool weight. arm64 makes Graviton the default."
  type        = string
  default     = "arm64"
}

variable "node_ami_alias" {
  description = "EC2NodeClass AMI alias. Pin to a release tag (e.g. al2023@v20260701) for production — see reference/karpenter-api-reference.md SS2."
  type        = string
  default     = "al2023@latest"
}

variable "enable_arm64_nodepool" {
  description = "Enable the arm64 (Graviton) Karpenter NodePool."
  type        = bool
  default     = true
}

variable "enable_amd64_nodepool" {
  description = "Enable the amd64 (x86) Karpenter NodePool."
  type        = bool
  default     = true
}

### Optional phases ##############################################################

variable "enable_aws_load_balancer_controller" {
  description = "Install the AWS Load Balancer Controller. Phase 9."
  type        = bool
  default     = false
}

variable "enable_metrics_server" {
  description = "Install the Kubernetes metrics-server. Phase 10."
  type        = bool
  default     = false
}
