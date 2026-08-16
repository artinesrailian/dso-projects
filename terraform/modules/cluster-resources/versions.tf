terraform {
  required_version = ">= 1.11.0"

  required_providers {
    helm = { source = "hashicorp/helm", version = "~> 3.2" }
  }

  # No `provider` block here — providers are configured only at the root and
  # inherited (interface-contract.md §1 rule 2). This module has no AWS
  # resources of its own, so `aws` is not declared here.
}
