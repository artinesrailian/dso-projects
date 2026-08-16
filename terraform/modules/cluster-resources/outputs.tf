output "storage_class_name" {
  description = "Name of the default gp3 StorageClass this chart delivers (phase-02 §2.5b). Literal — the template hardcodes the StorageClass name."
  value       = "gp3"
}

output "governed_namespace_names" {
  description = "Namespaces created with PSA restricted labels, a ResourceQuota and a LimitRange."
  value       = var.governed_namespaces
}

output "nodepool_names" {
  description = "Names of the NodePools actually rendered by the chart, based on enable_amd64/enable_arm64."
  value       = compact([var.enable_arm64 ? "arm64" : "", var.enable_amd64 ? "amd64" : ""])
}

output "ec2nodeclass_name" {
  description = "Name of the EC2NodeClass this chart delivers. Literal — the template hardcodes the object name (interface-contract.md §6)."
  value       = "default"
}
