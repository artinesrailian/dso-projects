# Creates the encrypted, versioned, locked S3 state backend the main stack's
# backend.tf (partial config) points at. Applied once, by hand, per account —
# safe to re-run: every resource here is idempotent create-or-noop.

locals {
  name = "${var.project_name}-${var.environment}"
}

data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------
# KMS CMK — encrypts the state bucket. A customer-managed key (not the AWS-owned
# default) so key rotation and the deletion window are under our control.
# ---------------------------------------------------------------------------

resource "aws_kms_key" "state" {
  description             = "CMK for the ${local.name} Terraform state bucket"
  enable_key_rotation     = true
  deletion_window_in_days = 30
}

resource "aws_kms_alias" "state" {
  name          = "alias/${var.project_name}-${var.environment}-tfstate"
  target_key_id = aws_kms_key.state.key_id
}

# ---------------------------------------------------------------------------
# State bucket
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "state" {
  bucket = "${local.name}-tfstate-${data.aws_caller_identity.current.account_id}"

  # Deliberately NO aws_s3_bucket_logging pointing at this same bucket:
  # self-logging a state bucket creates unbounded recursive writes. If access
  # logging is wanted, target a separate bucket.
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled" # the state recovery mechanism — without it a corrupt write is unrecoverable
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.state.arn
    }
    bucket_key_enabled = true # cuts KMS request cost ~99%
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    object_ownership = "BucketOwnerEnforced" # disables ACLs entirely
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    id     = "expire-noncurrent-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }

  rule {
    id     = "abort-incomplete-multipart-uploads"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

data "aws_iam_policy_document" "state" {
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.state.arn,
      "${aws_s3_bucket.state.arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  statement {
    sid    = "DenyUnencryptedObjectUploads"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.state.arn}/*"]

    condition {
      test     = "StringNotEquals"
      variable = "s3:x-amz-server-side-encryption"
      values   = ["aws:kms"]
    }
  }
}

resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id
  policy = data.aws_iam_policy_document.state.json
}
