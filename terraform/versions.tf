terraform {
  required_version = ">= 1.11.0" # S3-native state locking (use_lockfile) needs >= 1.10

  required_providers {
    aws       = { source = "hashicorp/aws", version = "~> 6.58" }
    helm      = { source = "hashicorp/helm", version = "~> 3.2" }      # Karpenter chart + CRD chart releases
    tls       = { source = "hashicorp/tls", version = "~> 4.3" }       # transitive: eks module
    time      = { source = "hashicorp/time", version = "~> 0.14" }     # transitive: eks module
    null      = { source = "hashicorp/null", version = "~> 3.3" }      # transitive: eks-managed-node-group submodule
    cloudinit = { source = "hashicorp/cloudinit", version = "~> 2.4" } # transitive: eks-managed-node-group submodule
  }

  # No `kubernetes` provider at all: this stack has none, by design (ADR-6) —
  # every Kubernetes object is delivered via Helm.
}
