terraform {
  required_version = ">= 1.11.0"

  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.58" }
  }

  # No `provider` block here — providers are configured only at the root and
  # inherited (interface-contract.md SS1 rule 2). No `helm` requirement yet:
  # Phase 4 adds it here alongside helm.tf.
}
