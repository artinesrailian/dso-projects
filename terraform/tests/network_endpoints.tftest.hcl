# module.network's enable_vpc_endpoints toggle instantiates a materially
# different resource set on each side (0 vs. 12 interface endpoints plus a
# security group, all built from a for-expression over a literal service
# list) — a mistake in either branch only shows up at plan time with concrete
# values, not at `terraform validate`. Both branches are cheap to plan against
# a mocked provider, so both get a regression test rather than relying on
# `terraform validate` alone.

mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = {
      names = ["us-east-1a", "us-east-1b", "us-east-1c"]
    }
  }

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

run "endpoints_off_plans_clean" {
  command = plan
  variables {
    cluster_endpoint_public_access_cidrs = ["203.0.113.10/32"] # RFC 5737 doc range
    budget_notification_email            = "you@example.com"
    enable_vpc_endpoints                 = false
  }
}

run "endpoints_on_plans_clean" {
  command = plan
  variables {
    cluster_endpoint_public_access_cidrs = ["203.0.113.10/32"]
    budget_notification_email            = "you@example.com"
    enable_vpc_endpoints                 = true
  }
}
