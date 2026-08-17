# ---------------------------------------------------------------------------
# CRDs, as a SEPARATE release.
#
# The main karpenter chart ships its CRDs in charts/karpenter/crds/. Helm's
# rule for that directory: CRDs are installed on FIRST INSTALL ONLY and are
# never added or updated by any later `helm upgrade`. A stack that installs
# only the main chart therefore works on day one and then silently fails to
# pick up CRD changes forever after — which bites immediately, because 1.14.0
# introduced a brand-new CapacityBuffer CRD.
#
# The karpenter-crd chart ships the same CRDs under templates/, so Helm
# manages them normally. This is the path Karpenter's own docs prescribe. See
# reference/version-pinning.md SS2.1.
# ---------------------------------------------------------------------------
resource "helm_release" "karpenter_crd" {
  name       = "karpenter-crd"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter-crd"
  version    = var.karpenter_version
  namespace  = var.namespace

  wait = true
}

resource "helm_release" "karpenter" {
  name       = "karpenter"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = var.karpenter_version # MUST equal the CRD chart version
  namespace  = var.namespace

  # Block until the controller is actually Running. wait = false (the
  # upstream module example's default) returns before the CRDs are
  # established — anything applying a NodePool in the same run then fails
  # with `no matches for kind "NodePool"`. Phase 5 applies exactly that.
  wait    = true
  timeout = 600

  # module.karpenter carries the controller's Pod Identity association.
  # Without this edge a controller pod can be scheduled before the
  # association exists and never gets credentials. (REVIEW.md F-20.)
  depends_on = [helm_release.karpenter_crd, module.karpenter]

  # helm provider v3: a LIST of objects, not repeated `set { }` blocks.
  set = [
    { name = "settings.clusterName", value = var.cluster_name },
    { name = "settings.clusterEndpoint", value = var.cluster_endpoint },

    # OPTIONAL to the chart, MANDATORY in practice. The chart guards this with
    # `{{- with }}`, so omitting it installs cleanly and silently disables ALL
    # interruption handling: Spot 2-minute notices, rebalance recommendations
    # and scheduled-change events are ignored, and nodes die undrained.
    { name = "settings.interruptionQueue", value = module.karpenter.queue_name },

    # THE DEADLOCK FIX. Karpenter defaults to dnsPolicy: ClusterFirst, i.e. it
    # resolves through in-cluster CoreDNS. If CoreDNS is itself waiting on
    # capacity, Karpenter cannot resolve sts.<region>.amazonaws.com, fails with
    # `WebIdentityErr ... i/o timeout`, and neither can proceed. `Default` uses
    # the host's VPC DNS instead. The upstream module example sets this too.
    { name = "dnsPolicy", value = "Default" },

    # The chart sets no resources at all by default. Karpenter's own install
    # command sets 1 CPU / 1Gi; an unbounded controller on a two-node bootstrap
    # group is a real noisy-neighbour risk.
    { name = "controller.resources.requests.cpu", value = "1" },
    { name = "controller.resources.requests.memory", value = "1Gi" },
    { name = "controller.resources.limits.cpu", value = "1" },
    { name = "controller.resources.limits.memory", value = "1Gi" },
  ]

  # Several chart values are intentionally left unset — the IRSA
  # service-account annotation, serviceAccount.create/.name, affinity,
  # replicas, featureGates.* — see README.md "Helm values intentionally not
  # set" for why each one is safe to leave at its chart default here.
}
