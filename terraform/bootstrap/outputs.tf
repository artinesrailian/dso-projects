output "state_bucket_name" {
  description = "Name of the S3 state bucket."
  value       = aws_s3_bucket.state.id
}

output "state_bucket_arn" {
  description = "ARN of the S3 state bucket."
  value       = aws_s3_bucket.state.arn
}

output "kms_key_arn" {
  description = "ARN of the KMS CMK encrypting the state bucket."
  value       = aws_kms_key.state.arn
}

output "backend_config" {
  description = "Rendered, copy-pasteable backend.hcl body. Redirect to a file: terraform -chdir=bootstrap output -raw backend_config > backend.hcl"
  value       = <<-EOT
    bucket     = "${aws_s3_bucket.state.id}"
    region     = "${var.region}"
    kms_key_id = "${aws_kms_key.state.arn}"
  EOT
}
