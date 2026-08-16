# Partial backend configuration. The bucket name embeds an AWS account ID, so it is
# never committed here — it is supplied at init time:
#   terraform init -backend-config=backend.hcl
# (copy backend.hcl.example to backend.hcl and fill it in from the bootstrap/ outputs)
#
# To run against local state instead — e.g. a reviewer who only wants to look, or
# before bootstrap/ has been applied — comment out this entire block and re-run
# `terraform init`. See README.md.
terraform {
  backend "s3" {
    key          = "eks-karpenter/terraform.tfstate"
    encrypt      = true
    use_lockfile = true # S3 conditional-write locking. No DynamoDB table required.
  }
}
