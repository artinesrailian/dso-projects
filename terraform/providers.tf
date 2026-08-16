provider "aws" {
  region = var.region

  default_tags {
    tags = local.tags
  }
}

# helm provider v3: `kubernetes` and `exec` are ATTRIBUTES (= { ... }), not
# blocks. The v2 block syntax found in most examples does not parse under v3.
provider "helm" {
  kubernetes = {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    # exec fetches a fresh token at call time. NEVER fall back to a static
    # cluster-auth-token data source: that token is written into state and
    # expires after 15 minutes, producing intermittent 401s on long applies.
    # See reference/gotchas.md G-20.
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.region]
    }
  }
}

# There is no `kubernetes` provider in this stack, ever — see ADR-6. Every
# Kubernetes object is delivered via the `helm` provider above instead.
