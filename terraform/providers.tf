provider "aws" {
  region = var.region

  default_tags {
    tags = local.tags
  }
}

# There is no `kubernetes` provider in this stack, ever — see ADR-6.
# There is no `helm` provider block here — Phase 4 adds it once module.eks exists;
# adding it now would break `terraform validate` for phases 0-3.
