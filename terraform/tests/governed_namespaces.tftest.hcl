# F-26: a negative test targeting module.cluster_resources's precondition
# (`expect_failures = [module.cluster_resources.helm_release.cluster_resources]`)
# was rejected by `terraform test` itself — `expect_failures` can't target a
# resource inside a child module, only root-module checkable objects. Dropped
# per REVIEW.md's own contingency; the precondition itself still fires,
# confirmed with an uncommitted scratch `plan` run against a mismatched
# namespace pair (errored at modules/cluster-resources/main.tf:87 as
# expected). What remains is a positive regression test with the paired-
# namespace default.

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

  mock_data "aws_partition" {
    defaults = {
      partition  = "aws"
      dns_suffix = "amazonaws.com"
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
      arn        = "arn:aws:iam::123456789012:role/mock-terraform-test"
      user_id    = "AIDACKCEVSQ6C2EXAMPLE"
    }
  }

  mock_data "aws_iam_session_context" {
    defaults = {
      issuer_arn = "arn:aws:iam::123456789012:role/mock-terraform-test"
    }
  }

  mock_data "aws_iam_policy" {
    defaults = {
      arn = "arn:aws:iam::aws:policy/AmazonEBSCSIDriverPolicyV2"
    }
  }
}

# The paired default (both lists = ["demo"]) must still plan clean.
run "accepts_paired_default_namespaces" {
  command = plan
  variables {
    cluster_endpoint_public_access_cidrs = ["203.0.113.10/32"]
    budget_notification_email            = "you@example.com"
  }
}
