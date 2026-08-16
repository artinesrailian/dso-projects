# Root composition. Module blocks only — no resources.
# Phase 2 adds module.eks, Phases 3-4 module.karpenter, Phase 5 module.cluster_resources.

module "network" {
  source = "./modules/network"

  name = local.name

  vpc_cidr                = var.vpc_cidr
  az_count                = var.az_count
  single_nat_gateway      = var.single_nat_gateway
  enable_flow_logs        = var.enable_vpc_flow_logs
  flow_log_retention_days = var.flow_log_retention_days
  enable_vpc_endpoints    = var.enable_vpc_endpoints

  tags = local.tags
}
