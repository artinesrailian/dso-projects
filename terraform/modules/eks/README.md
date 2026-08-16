# modules/eks

A running EKS control plane on the latest supported Kubernetes minor, KMS-encrypted
Secrets, full control-plane audit logging, access-entry authentication, the
add-ons the data plane needs to come up at all, and a small On-Demand
managed node group ("bootstrap") that hosts the Karpenter controller from
Phase 4 onward. See `docs/00-architecture-and-decisions.md` ADR-3 (why a
bootstrap group), ADR-4 (access entries), ADR-5 (Pod Identity), and
`docs/contracts/interface-contract.md` §5.2 for this module's exact
input/output contract.

At the end of this phase the cluster has no autoscaling — that is correct.
Phase 3 adds Karpenter's IAM roles and SQS queue; Phase 4 installs it.

## v20 → v21

This module wraps `terraform-aws-modules/eks/aws` **21.24.2**. v21 renamed
almost every root input by stripping the `cluster_` prefix (`cluster_name` →
`name`, `cluster_version` → `kubernetes_version`, …) but left the **outputs**
on the old `cluster_*` names. See `docs/reference/version-pinning.md` §4
before changing anything in `main.tf`.

## What this module does not do

- Does not install Karpenter, and does not create its IAM roles or SQS queue
  (Phase 3 owns those).
- Does not add a `helm` or `kubernetes` provider — this stack has neither
  (ADR-6); Phase 4 adds `helm` once this module exists.
- Does not ship a default `gp3` StorageClass. The EBS CSI driver add-on is
  installed here, but EKS creates no default StorageClass, so a PVC with no
  `storageClassName` sits `Pending` forever with no explanatory error. Phase
  5's local Helm chart (already used for cluster-scoped objects, since ADR-6
  rules out a `kubernetes` provider) is where that StorageClass belongs — see
  phase-02 §2.5b.

## The KMS-key-danger alarm

Since Kubernetes 1.28, EKS encrypts all API data by default with an
AWS-owned key at no cost. The customer-managed key this module creates
(`create_kms_key = true`) buys a key whose policy, rotation and audit trail
are controllable — which is what compliance regimes ask for — at the cost of
a real availability risk: per AWS, disabling the key degrades the cluster
immediately, and deleting it makes the cluster **unrecoverable**. Because
that risk is real, this is the one alarm in the whole stack: an EventBridge
rule on CloudTrail's `DisableKey` / `ScheduleKeyDeletion` /
`DisableKeyRotation` events for this key, publishing to an SNS topic that
`var.alert_email` can subscribe to. It requires CloudTrail to be enabled in
the account and the SNS subscription to be confirmed from the inbox, or it
is silent — see the phase-02 completion report for what was and was not
verified without AWS credentials.

## The bootstrap node group is a fixed-size capacity dead end

It runs `min 2 / max 3`. Karpenter does not manage it and will not launch
capacity for itself onto it, and nothing autoscales it. As system components
accumulate on it (Karpenter, CoreDNS, the EBS CSI controller, anything a
later phase adds with a `CriticalAddonsOnly` toleration), the two
`t4g.medium` nodes fill up — the first symptom is a Karpenter replica stuck
`Pending`, which then means nothing else in the cluster scales either. Keep
the taint on, and raise `bootstrap_node_instance_types` before adding more
system controllers.

`bootstrap_node_desired_size` is in the module's own `lifecycle.ignore_changes`
— changing it in HCL after creation produces "No changes"; use
`aws eks update-nodegroup-config` or `min_size` instead.
