# Root composition. Module blocks only — no resources.
# Phase 4 extends module.karpenter's Helm release wiring, Phase 5 adds
# module.cluster_resources.

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

module "eks" {
  source = "./modules/eks"

  name               = local.name
  kubernetes_version = var.kubernetes_version

  vpc_id             = module.network.vpc_id
  private_subnet_ids = module.network.private_subnet_ids
  # modules/network exports this but does not root-output it (interface-contract
  # SS4 doesn't list it) — wired module-to-module per phase-01's completion report.
  control_plane_subnet_ids = module.network.intra_subnet_ids

  endpoint_public_access       = var.cluster_endpoint_public_access
  endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs
  endpoint_private_access      = var.cluster_endpoint_private_access

  enabled_log_types  = var.cluster_enabled_log_types
  log_retention_days = var.cluster_log_retention_days

  admin_principal_arns     = var.cluster_admin_principal_arns
  developer_principal_arns = var.developer_principal_arns
  developer_rbac_group     = var.developer_rbac_group

  alert_email = var.alert_email

  bootstrap_node_instance_types = var.bootstrap_node_instance_types
  bootstrap_node_ami_type       = var.bootstrap_node_ami_type
  bootstrap_node_min_size       = var.bootstrap_node_min_size
  bootstrap_node_max_size       = var.bootstrap_node_max_size
  bootstrap_node_desired_size   = var.bootstrap_node_desired_size
  taint_bootstrap_nodes         = var.taint_bootstrap_nodes

  enable_metrics_server = var.enable_metrics_server

  tags = local.tags
}

module "karpenter" {
  source = "./modules/karpenter"

  cluster_name     = module.eks.cluster_name
  cluster_endpoint = module.eks.cluster_endpoint

  karpenter_version = var.karpenter_version
  namespace         = var.karpenter_namespace

  node_security_group_id = module.eks.node_security_group_id

  create_spot_service_linked_role = var.create_spot_service_linked_role

  tags = local.tags
}
