# EKS control plane, add-ons and the bootstrap managed node group that will
# host the Karpenter controller (Phase 4). No autoscaling exists yet — that
# is correct at the end of this phase. See docs/00-architecture-and-decisions.md
# ADR-3 (bootstrap group), ADR-4 (access entries), ADR-5 (Pod Identity).
#
# v21 renamed almost every root input of this module by stripping the
# cluster_ prefix, but left the OUTPUTS on the old cluster_* names — see
# reference/version-pinning.md SS4. Inputs below are v21 names; comments call
# out the v20 name only where a stale example is likely to be found online.
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.24.2"

  # v20 called this cluster_name.
  name = var.name
  # v20 called this cluster_version.
  kubernetes_version = var.kubernetes_version

  vpc_id                   = var.vpc_id
  subnet_ids               = var.private_subnet_ids
  control_plane_subnet_ids = var.control_plane_subnet_ids

  endpoint_private_access      = var.endpoint_private_access
  endpoint_public_access       = var.endpoint_public_access
  endpoint_public_access_cidrs = var.endpoint_public_access_cidrs

  # "API" disables the legacy aws-auth ConfigMap path entirely. This is a
  # one-way door — once access entries are enabled they cannot be disabled,
  # and the module's own default (API_AND_CONFIG_MAP) is not what we want.
  authentication_mode = "API"
  # Defaults to false. Without this the identity that ran `terraform apply`
  # has zero Kubernetes RBAC and the first `kubectl get nodes` is
  # "Unauthorized".
  enable_cluster_creator_admin_permissions = true

  access_entries = merge(
    # Operators: full cluster admin via the AWS managed access policy.
    {
      for arn in var.admin_principal_arns : "admin-${basename(arn)}" => {
        principal_arn = arn
        policy_associations = {
          admin = {
            policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
            access_scope = { type = "cluster" }
          }
        }
      }
    },
    # Developers: STANDARD entry, kubernetes_groups only, NO policy
    # association. Permissions come from a ClusterRole phase-05 SS5.3d owns —
    # AmazonEKSEditPolicy is rejected as too broad (secrets get/list/watch,
    # serviceaccounts impersonate, pods/exec). See phase-02 SS2.2.
    {
      for arn in var.developer_principal_arns : "dev-${basename(arn)}" => {
        principal_arn     = arn
        type              = "STANDARD"
        kubernetes_groups = [var.developer_rbac_group]
      }
    },
  )

  # Envelope-encrypts Kubernetes Secrets with a customer-managed, rotating
  # CMK. create_kms_key defaults true; stated explicitly because it is a real
  # trade (SS2.3): the key's disable/delete failure mode is unrecoverable,
  # which is why the alarm below exists.
  create_kms_key                = true
  kms_key_enable_default_policy = true
  # In v21, passing null here disables the CMK; the v20 idiom of {} does not.
  encryption_config = {
    resources = ["secrets"]
  }

  # v20 called this cluster_enabled_log_types.
  enabled_log_types                      = var.enabled_log_types
  create_cloudwatch_log_group            = true
  cloudwatch_log_group_retention_in_days = var.log_retention_days

  # This module hardcodes bootstrap_self_managed_addons to false (verified
  # against v21.24.2's main.tf — it is in lifecycle.ignore_changes, not a
  # variable), so nothing is installed unless listed here. Omitting vpc-cni,
  # coredns or kube-proxy leaves every node with no pod networking or DNS.
  addons = {
    vpc-cni = {
      before_compute = true
      most_recent    = true
      # Usually redundant with this module (no self-managed addon exists to
      # conflict with), kept anyway per phase-02 SS2.4.
      resolve_conflicts_on_create = "OVERWRITE"
      configuration_values = jsonencode({
        env = {
          ENABLE_PREFIX_DELEGATION = "true"
          WARM_PREFIX_TARGET       = "1"
        }
      })
      # Own Pod Identity role instead of the node role's AmazonEKS_CNI_Policy
      # — see iam.tf.
      pod_identity_association = [{
        role_arn        = aws_iam_role.vpc_cni.arn
        service_account = "aws-node"
      }]
    }

    kube-proxy = {
      most_recent                 = true
      resolve_conflicts_on_create = "OVERWRITE"
    }

    coredns = {
      most_recent                 = true
      resolve_conflicts_on_create = "OVERWRITE"
    }

    # NON-OPTIONAL: the Karpenter controller (Phase 4) authenticates via Pod
    # Identity; without this agent it cannot obtain credentials.
    eks-pod-identity-agent = {
      before_compute = true
      most_recent    = true
    }

    aws-ebs-csi-driver = {
      most_recent = true
      pod_identity_association = [{
        role_arn        = aws_iam_role.ebs_csi.arn
        service_account = "ebs-csi-controller-sa"
      }]
    }
  }

  eks_managed_node_groups = {
    bootstrap = {
      # Graviton: cheaper, and it demonstrates the control tier itself runs
      # on arm64 (ADR-3). ami_type is derived from a variable rather than
      # hardcoded so a non-Graviton instance_types override cannot silently
      # mismatch.
      ami_type       = var.bootstrap_node_ami_type
      instance_types = var.bootstrap_node_instance_types
      capacity_type  = "ON_DEMAND" # not Spot — see ADR-3

      # The Karpenter chart defaults to replicas=2 with a REQUIRED
      # podAntiAffinity on kubernetes.io/hostname (karpenter-api-reference.md
      # SS6) — fewer than 2 nodes leaves a Karpenter replica Pending forever.
      min_size     = var.bootstrap_node_min_size
      max_size     = var.bootstrap_node_max_size
      desired_size = var.bootstrap_node_desired_size

      subnet_ids = var.private_subnet_ids

      labels = {
        "node-role" = "bootstrap"
      }

      taints = var.taint_bootstrap_nodes ? {
        critical_addons = {
          key    = "CriticalAddonsOnly"
          value  = "true"
          effect = "NO_SCHEDULE"
        }
      } : {}

      # Own Pod Identity role covers CNI credentials (see iam.tf), so this
      # node role does not need AmazonEKS_CNI_Policy — that policy grants
      # ENI/IP manipulation that any hostNetwork pod would otherwise inherit.
      iam_role_attach_cni_policy = false

      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size           = 50
            volume_type           = "gp3"
            encrypted             = true
            delete_on_termination = true
          }
        }
      }

      metadata_options = {
        http_endpoint               = "enabled"
        http_tokens                 = "required" # IMDSv2 only
        http_put_response_hop_limit = 1
      }
    }
  }

  # Karpenter's EC2NodeClass securityGroupSelectorTerms matches on this tag.
  # At most one SG in the account may carry it — this module creates the
  # node SG, so it is the only place that can safely set it.
  node_security_group_tags = {
    "karpenter.sh/discovery" = var.name
  }

  # attach_cluster_primary_security_group stays at its default (false):
  # setting it true attaches both SGs to every node, and the AWS Load
  # Balancer Controller (Phase 9) then fails with "expect exactly one
  # securityGroup tagged with kubernetes.io/cluster/<name>".

  tags = var.tags
}

# --- SS2.3: the one detector this stack has ---------------------------------
#
# KMS publishes no "key disabled" metric. Disabling or scheduling deletion of
# the cluster CMK degrades the cluster immediately and, if deletion
# completes, makes it unrecoverable — the one failure in this design with no
# rollback, so it gets the one alarm. Depends on CloudTrail being enabled in
# the account; that is not verified here (no AWS credentials in this
# environment) — see the completion report.

resource "aws_sns_topic" "alerts" {
  name              = "${var.name}-alerts"
  kms_master_key_id = "alias/aws/sns"
  tags              = var.tags
}

resource "aws_sns_topic_subscription" "alerts_email" {
  count     = var.alert_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email # confirm the subscription from your inbox, or this is silent
}

# The topic policy must allow EventBridge to publish, or the rule below
# fires into a topic nothing can write to. Scoped to this one rule's ARN
# rather than a bare Allow-all-of-events.amazonaws.com.
data "aws_iam_policy_document" "alerts_topic" {
  statement {
    sid       = "AllowEventBridgePublish"
    effect    = "Allow"
    actions   = ["SNS:Publish"]
    resources = [aws_sns_topic.alerts.arn]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_cloudwatch_event_rule.kms_key_danger.arn]
    }
  }
}

resource "aws_sns_topic_policy" "alerts" {
  arn    = aws_sns_topic.alerts.arn
  policy = data.aws_iam_policy_document.alerts_topic.json
}

resource "aws_cloudwatch_event_rule" "kms_key_danger" {
  name        = "${var.name}-kms-key-danger"
  description = "EKS CMK disabled or scheduled for deletion"
  event_pattern = jsonencode({
    source        = ["aws.kms"]
    "detail-type" = ["AWS API Call via CloudTrail"]
    detail = {
      eventSource       = ["kms.amazonaws.com"]
      eventName         = ["DisableKey", "ScheduleKeyDeletion", "DisableKeyRotation"]
      requestParameters = { keyId = [module.eks.kms_key_id, module.eks.kms_key_arn] }
    }
  })

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "kms_key_danger" {
  rule      = aws_cloudwatch_event_rule.kms_key_danger.name
  target_id = "sns"
  arn       = aws_sns_topic.alerts.arn
}
