variable "project_name" {
  description = "Name prefix component. Must match the main stack's var.project_name, since it feeds the bucket/key/alias names the main stack's backend.hcl points at."
  type        = string
  default     = "opsfleet"
}

variable "environment" {
  description = "Name prefix component. Must match the main stack's var.environment."
  type        = string
  default     = "poc"
}

variable "region" {
  description = "AWS region to create the state bucket and KMS key in. Must match the main stack's var.region."
  type        = string
  default     = "us-east-1"
}
