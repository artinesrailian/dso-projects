# Requests the EC2 vCPU quota increases in code instead of leaving them as a
# runbook step (prerequisite P3 — the most likely thing to break a first deploy).
#
# Both quota codes default to 5 vCPU on a new account and are SEPARATE quotas:
# raising one does nothing for the other, and there is no separate Graviton
# quota — arm64 families draw from the same Standard pool as x86.
# nodepool_cpu_limit (100) + the bootstrap group (4) is the real requirement.
#
# IMPORTANT: this resource only OPENS a quota increase request. Approval is
# asynchronous — automatic, delayed by hours, or refused — so `terraform apply`
# succeeding does NOT mean the quota is raised. Phase 8's verify.sh must assert
# the effective quota with `get-service-quota` before declaring the cluster ready.

resource "aws_servicequotas_service_quota" "ondemand_standard" {
  count        = var.request_service_quotas ? 1 : 0
  service_code = "ec2"
  quota_code   = "L-1216C47A" # Running On-Demand Standard (A,C,D,H,I,M,R,T,Z) instances
  value        = var.vcpu_quota_target
}

resource "aws_servicequotas_service_quota" "spot_standard" {
  count        = var.request_service_quotas ? 1 : 0
  service_code = "ec2"
  quota_code   = "L-34B43A08" # All Standard (A,C,D,H,I,M,R,T,Z) Spot Instance Requests
  value        = var.vcpu_quota_target
}
