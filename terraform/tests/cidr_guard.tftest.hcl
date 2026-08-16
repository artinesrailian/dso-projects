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
