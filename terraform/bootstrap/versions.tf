terraform {
  required_version = ">= 1.11.0"

  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.58" }
  }

  # Deliberately local state — bootstrap/ creates the bucket the main stack
  # stores its state in, so it cannot store its own state there (chicken/egg).
  # Applied once, by hand, per account.
}

provider "aws" {
  region = var.region

  # S-C1 applied here too — untagged, the state bucket/KMS key are invisible
  # to the tag-filtered budget and Cost Explorer grouping.
  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Component   = "tfstate-backend"
    }
  }
}
