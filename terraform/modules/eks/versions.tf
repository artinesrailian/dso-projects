terraform {
  required_version = ">= 1.11.0"

  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.58" }
  }

  # No `provider` block here — providers are configured only at the root and
  # inherited (interface-contract.md SS1 rule 2). `tls` and `time` are pulled
  # in transitively by the nested terraform-aws-modules/eks/aws call and are
  # satisfied by the root's required_providers; this module has no resource
  # that uses either directly.
}
