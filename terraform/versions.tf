terraform {
  required_version = ">= 1.11.0" # S3-native state locking (use_lockfile) needs >= 1.10

  required_providers {
    aws  = { source = "hashicorp/aws", version = "~> 6.58" }
    tls  = { source = "hashicorp/tls", version = "~> 4.3" }   # transitive: eks module
    time = { source = "hashicorp/time", version = "~> 0.14" } # transitive: eks module
  }

  # No `helm` provider here — Phase 4 adds it alongside module.eks/module.karpenter so
  # that `validate` keeps passing in the interim. No `kubernetes` provider at all: this
  # stack has none, by design (ADR-6) — every Kubernetes object is delivered via Helm.
}
