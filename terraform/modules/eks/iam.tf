# Pod Identity trust policy shared by every role in this file that a Pod
# Identity association points at. Note the principal is pods.eks.amazonaws.com
# and BOTH sts:AssumeRole and sts:TagSession are required — omitting
# TagSession lets the association create successfully and then fails every
# credential fetch at runtime.
data "aws_iam_policy_document" "pod_identity_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

# Gives the VPC CNI (aws-node) its own identity so node roles do not need
# AmazonEKS_CNI_Policy — that policy grants ENI/IP manipulation, and any
# hostNetwork pod inherits whatever the node role holds regardless of the
# IMDS hop limit. See phase-02 SS2.4.
resource "aws_iam_role" "vpc_cni" {
  name               = "${var.name}-vpc-cni"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "vpc_cni" {
  role       = aws_iam_role.vpc_cni.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

# EBS CSI controller Pod Identity role. AmazonEBSCSIDriverPolicyV2 plus the
# cluster-scoped policy are AWS's current, tighter replacements for the
# original AmazonEBSCSIDriverPolicy and are what AWS's own examples use now.
resource "aws_iam_role" "ebs_csi" {
  name               = "${var.name}-ebs-csi"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json
  tags               = var.tags
}

# Resolved by name, not a hardcoded ARN path — AWS's own docs disagree on
# whether AmazonEBSCSIDriverPolicyV2 lives under .../service-role/ or not,
# and guessing wrong 404s the first apply. (REVIEW.md F-06.)
data "aws_iam_policy" "ebs_csi" {
  name = "AmazonEBSCSIDriverPolicyV2"
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = data.aws_iam_policy.ebs_csi.arn
}
