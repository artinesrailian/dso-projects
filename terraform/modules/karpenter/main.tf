# AWS-side Karpenter resources only: controller IAM role (Pod Identity), node
# IAM role, EKS access entry, and the SQS/EventBridge interruption path. No
# Kubernetes objects are created and nothing talks to the cluster API — Phase
# 4 adds helm.tf to this same module for the Helm releases; Phase 5's separate
# modules/cluster-resources owns the NodePool / EC2NodeClass objects.
#
# v21's karpenter submodule is Pod-Identity-only: create_pod_identity_association
# creates both the controller's IAM role and its aws_eks_pod_identity_association
# in one step. There is no OIDC-federation path and nothing else to turn on —
# see reference/version-pinning.md SS4 before adding any argument not already
# in this file.
module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "21.24.2" # keep identical to the parent eks module version

  cluster_name = var.cluster_name

  # --- Controller identity -----------------------------------------------------
  create_pod_identity_association = true
  namespace                       = var.namespace
  service_account                 = "karpenter"

  # --- Node identity -------------------------------------------------------------
  # EC2NodeClass.spec.role (Phase 5) must match this name exactly — a random
  # name_prefix suffix would break that reference.
  node_iam_role_use_name_prefix = false
  node_iam_role_name            = "${var.cluster_name}-karpenter-node"

  # The VPC CNI already has its own Pod Identity role (modules/eks, Phase 2),
  # so the node role does not need the CNI policy — see S-32 and phase-02's
  # "AmazonEKS_CNI_Policy problem".
  node_iam_role_attach_cni_policy = false

  node_iam_role_additional_policies = {
    # Session Manager is the only supported way onto a node — no SSH key
    # anywhere in this stack.
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  # --- Node cluster access -------------------------------------------------------
  # THE most important two lines in this phase. Under modules/eks's
  # authentication_mode = "API", a node whose role has no access entry boots,
  # fails to register, and is invisible in `kubectl get nodes` — no obvious
  # error message.
  create_access_entry = true
  access_entry_type   = "EC2_LINUX"

  # --- Interruption handling -------------------------------------------------------
  enable_spot_termination   = true
  queue_managed_sse_enabled = true

  tags = var.tags
}

# Least-privilege, for a reviewer asking "why does this have ec2:RunInstances
# / iam:PassRole?" (see phase-03.md SS3.5). Enforced by the submodule's own
# policy.tf, not re-implemented here:
#   - RunInstances / CreateFleet / CreateLaunchTemplate require
#     aws:RequestTag/kubernetes.io/cluster/<cluster> = owned AND
#     aws:RequestTag/eks:eks-cluster-name = <cluster> — Karpenter cannot
#     launch an untagged instance.
#   - iam:PassRole is scoped to the single node role ARN above, with
#     iam:PassedToService restricted to ec2.amazonaws.com.
#   - SQS is DeleteMessage/GetQueueUrl/ReceiveMessage on the interruption
#     queue only; the queue policy itself denies non-TLS access and allows
#     SendMessage only from events.amazonaws.com / sqs.amazonaws.com.
#   - ec2:Describe* is Resource: * (unavoidable — EC2 describe calls have no
#     resource-level permissions) but conditioned on aws:RequestedRegion.

# Creates AWSServiceRoleForEC2Spot (prerequisite P2). Defaults to false — an
# adopt-or-create path was evaluated and rejected because it hard-fails
# terraform apply on precisely the fresh-account case it was meant to cover.
# See this module's README for the full reasoning.
resource "aws_iam_service_linked_role" "spot" {
  count            = var.create_spot_service_linked_role ? 1 : 0
  aws_service_name = "spot.amazonaws.com"
}
