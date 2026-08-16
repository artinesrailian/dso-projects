# Karpenter's NodePool/EC2NodeClass CRDs are the whole reason this module
# exists as a local Helm chart rather than a kubernetes_manifest resource
# (ADR-7): kubernetes_manifest needs the CRD to exist at PLAN time, which
# fails the very first plan against an empty account. helm_release has no
# such requirement, and `helm uninstall` removes the CRs cleanly on destroy —
# orphaned NodePools with finalizers are a classic terraform destroy hang.

locals {
  # Karpenter evaluates higher-weight NodePools first, so this decides where
  # a pod with NO architecture constraint lands. Defaulting to arm64 is the
  # price/performance position the assignment asks for; see README.md for
  # the risk (G-16: an x86-only image lands on Graviton and crash-loops).
  arm64_weight = var.default_arch == "arm64" ? 50 : 10
  amd64_weight = var.default_arch == "amd64" ? 50 : 10

  # spec.limits is per-NodePool, so N enabled pools multiply the ceiling by
  # N. max(...,1) guards against a division by zero if both pools are
  # disabled.
  enabled_pool_count = max(
    (var.enable_amd64 ? 1 : 0) + (var.enable_arm64 ? 1 : 0),
    1,
  )
}

resource "helm_release" "cluster_resources" {
  name      = "cluster-resources"
  chart     = "${path.module}/chart"
  namespace = var.namespace

  # Ordering is not optional: the CRDs must be established before these CRs
  # are applied, or the release fails with `no matches for kind "NodePool"`
  # (G-19). This is a valid dependency edge even though the argument is "just
  # a string" — Terraform traces it through the module-input reference graph
  # back to helm_release.karpenter in modules/karpenter.
  depends_on = [var.karpenter_helm_release_name]

  values = [yamlencode({
    clusterName     = var.cluster_name
    nodeIamRoleName = var.node_iam_role_name
    amiAlias        = var.node_ami_alias
    capacityTypes   = var.capacity_types

    # Karpenter's spec.limits is PER-NODEPOOL. Divide the configured budget
    # across the enabled pools so that nodepool_cpu_limit/
    # nodepool_memory_limit_gi are the real cluster ceiling rather than half
    # of it.
    cpuLimitPerPool    = floor(var.cpu_limit / local.enabled_pool_count)
    memoryLimitPerPool = floor(var.memory_limit_gi / local.enabled_pool_count)

    # Cost allocation. default_tags never reaches Karpenter-launched
    # instances (it calls ec2:CreateFleet itself), so these are the ONLY way
    # the compute spend is attributable in Cost Explorer.
    tags = var.tags

    amd64 = {
      enabled = var.enable_amd64
      weight  = local.amd64_weight
    }
    arm64 = {
      enabled = var.enable_arm64
      weight  = local.arm64_weight
    }

    governedNamespaces = var.governed_namespaces

    # snake_case (root variable) -> camelCase (chart template's
    # .Values.namespaceQuota.*), per interface-contract.md §3's
    # namespace_quota row.
    namespaceQuota = {
      requestsCpu    = var.namespace_quota.requests_cpu
      requestsMemory = var.namespace_quota.requests_memory
      limitsCpu      = var.namespace_quota.limits_cpu
      limitsMemory   = var.namespace_quota.limits_memory
      maxDeployments = var.namespace_quota.max_deployments
    }

    developerRbacGroup = var.developer_rbac_group
  })]

  lifecycle {
    precondition {
      # Every concrete namespace developers are granted access to must also
      # be governed. Wildcards (team-*) cannot be created, so they are
      # excluded from the check and must be governed by adding their real
      # names here. See phase-05-nodepools.md §5.3c for the ordering bug
      # this prevents: access without guardrails.
      condition = length(setsubtract(
        [for ns in var.developer_namespaces : ns if !strcontains(ns, "*")],
        var.governed_namespaces,
      )) == 0
      error_message = "Every non-wildcard entry in developer_namespaces must appear in governed_namespaces, or developers get edit rights on an ungoverned namespace."
    }
  }
}
