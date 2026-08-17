# S-04 is the only security control Phase 0 implements, so it gets a real
# negative test rather than a grep. `terraform test` with a mocked provider runs
# the plan with no AWS credentials and no real API calls.
#
# A check that cannot fail is worse than no check, because it prints PASS.

mock_provider "aws" {
  # Phase 1's module.network needs a concrete AZ list — the default mock
  # returns an empty `names`, and slice(names, 0, var.az_count) errors.
  mock_data "aws_availability_zones" {
    defaults = {
      names = ["us-east-1a", "us-east-1b", "us-east-1c"]
    }
  }

  # Default mock leaves `json` as "", which fails the aws_iam_role schema's
  # own "must be a valid JSON policy" check on the VPC module's flow-log role.
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = jsonencode({
        Version = "2012-10-17"
        Statement = [{
          Effect    = "Allow"
          Action    = "sts:AssumeRole"
          Principal = { Service = "vpc-flow-logs.amazonaws.com" }
        }]
      })
    }
  }

  # Phase 2's module.eks builds IAM managed-policy ARNs from
  # data.aws_partition.current.partition (e.g. "${partition}:iam::aws:policy/...").
  # The default mock returns a random string instead of "aws", which fails AWS
  # provider ARN validation on every aws_iam_role_policy_attachment the eks
  # module creates.
  mock_data "aws_partition" {
    defaults = {
      partition  = "aws"
      dns_suffix = "amazonaws.com"
    }
  }

  # Same failure mode, via data.aws_caller_identity.current.arn feeding
  # data.aws_iam_session_context (used to resolve the cluster-creator access
  # entry principal) — the default mock's placeholder ARN doesn't parse.
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
      arn        = "arn:aws:iam::123456789012:role/mock-terraform-test"
      user_id    = "AIDACKCEVSQ6C2EXAMPLE"
    }
  }

  # enable_cluster_creator_admin_permissions = true reads
  # data.aws_iam_session_context.current[0].issuer_arn for the cluster_creator
  # access entry's principal_arn — same "invalid ARN" failure otherwise.
  mock_data "aws_iam_session_context" {
    defaults = {
      issuer_arn = "arn:aws:iam::123456789012:role/mock-terraform-test"
    }
  }

  # F-06: EBS CSI policy is now resolved by name via data "aws_iam_policy",
  # which needs a mock or the data source fails schema validation.
  mock_data "aws_iam_policy" {
    defaults = {
      arn = "arn:aws:iam::aws:policy/AmazonEBSCSIDriverPolicyV2"
    }
  }
}

# The guard must REJECT an internet-open endpoint.
run "rejects_open_endpoint" {
  command = plan
  variables {
    cluster_endpoint_public_access       = true
    cluster_endpoint_public_access_cidrs = ["0.0.0.0/0"]
    budget_notification_email            = "you@example.com"
  }
  expect_failures = [var.cluster_endpoint_public_access_cidrs]
}

# The guard must REJECT public access with an empty allowlist.
run "rejects_empty_allowlist" {
  command = plan
  variables {
    cluster_endpoint_public_access       = true
    cluster_endpoint_public_access_cidrs = []
    budget_notification_email            = "you@example.com"
  }
  expect_failures = [var.cluster_endpoint_public_access]
}

# ...and must ACCEPT a scoped allowlist. Without this run the test would pass
# even if the variable rejected everything, which is the classic missing
# negative control.
run "accepts_scoped_allowlist" {
  command = plan
  variables {
    cluster_endpoint_public_access       = true
    cluster_endpoint_public_access_cidrs = ["203.0.113.10/32"] # RFC 5737 doc range
    budget_notification_email            = "you@example.com"
  }
}

# A bare IP with no mask must be REJECTED before it reaches the EKS API.
run "rejects_bare_ip_without_mask" {
  command = plan
  variables {
    cluster_endpoint_public_access       = true
    cluster_endpoint_public_access_cidrs = ["203.0.113.10"] # no /32 — the F-26 trap
    budget_notification_email            = "you@example.com"
  }
  expect_failures = [var.cluster_endpoint_public_access_cidrs]
}

# S-C2's cost control is sold as "budget_notification_email is mandatory when
# enable_budget_alarm is on" — assert the guard actually fires, not just that
# the validation block exists.
run "rejects_missing_budget_email" {
  command = plan
  variables {
    cluster_endpoint_public_access_cidrs = ["203.0.113.10/32"]
    enable_budget_alarm                  = true
    budget_notification_email            = ""
  }
  expect_failures = [var.budget_notification_email]
}
