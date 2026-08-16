# Phase 2 — EKS control plane, add-ons and bootstrap compute

**Depends on:** Phases 0, 1.
**Produces:** `modules/eks/`, wired into `main.tf` as `module.eks`.

---

## Goal

A running EKS cluster on the latest supported Kubernetes version, with KMS-encrypted secrets,
control-plane audit logging, access-entry authentication, the required add-ons, and a small
On-Demand managed node group that will host the Karpenter controller in Phase 4.

At the end of this phase the cluster is usable but has no autoscaling. That is correct.

---

## Inputs

| Source | What you need |
|---|---|
| `contracts/interface-contract.md` | §5.2 the exact `modules/eks` signature |
| `reference/version-pinning.md` | EKS module `21.24.2`, Kubernetes `1.36`, **§4 the v20→v21 rename table**, §5 dangerous defaults |
| `00-architecture-and-decisions.md` | ADR-3 (why a bootstrap node group), ADR-4 (access entries), ADR-5 (Pod Identity) |
| `reference/karpenter-api-reference.md` | §6 — why the bootstrap group needs **two** nodes |
| Phase 1 completion report | The `modules/network` output names as actually implemented |

> **Before writing a single line:** read `reference/version-pinning.md` §4. The eks module's v21
> major renamed almost every root input (`cluster_name` → `name`, `cluster_version` →
> `kubernetes_version`, …) but left the **outputs** on the old `cluster_*` names. Every pre-v21
> example on the internet is now wrong in a way that produces confusing errors.

---

## Files to create

```
modules/eks/versions.tf
modules/eks/variables.tf
modules/eks/main.tf
modules/eks/iam.tf          # Pod Identity role for the EBS CSI driver
modules/eks/outputs.tf
modules/eks/README.md
```

And **edit** `main.tf` (add `module "eks"`) and `outputs.tf` (cluster outputs
plus `configure_kubectl`).

---

## Specification

### 2.1 Cluster basics

```hcl
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.24.2"

  name               = var.name               # v20 called this cluster_name
  kubernetes_version = var.kubernetes_version # v20 called this cluster_version

  vpc_id                   = var.vpc_id
  subnet_ids               = var.private_subnet_ids       # where nodes go
  control_plane_subnet_ids = var.control_plane_subnet_ids # the intra subnets

  endpoint_private_access      = var.endpoint_private_access
  endpoint_public_access       = var.endpoint_public_access
  endpoint_public_access_cidrs = var.endpoint_public_access_cidrs

  # ...
}
```

Reminder from `version-pinning.md` §5: `endpoint_public_access` **defaults to `false`** in v21. If
you rely on the default you get a private-only cluster and every subsequent `kubectl` from your
laptop hangs with no useful error.

### 2.2 Authentication — access entries only

```hcl
  authentication_mode                      = "API"
  enable_cluster_creator_admin_permissions = true   # DEFAULTS TO FALSE — you will be locked out

  access_entries = merge(
    # Operators: full cluster admin.
    {
      for arn in var.admin_principal_arns : "admin-${basename(arn)}" => {
        principal_arn = arn
        policy_associations = {
          admin = {
            policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
            access_scope = { type = "cluster" }
          }
        }
      }
    },
    # Developers: edit rights, scoped to their namespaces only.
    # This is the platform's whole point — a developer can deploy without an
    # operator, and without cluster-admin.
    {
      for arn in var.developer_principal_arns : "dev-${basename(arn)}" => {
        principal_arn = arn
        policy_associations = {
          edit = {
            policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"
            access_scope = {
              type       = "namespace"
              namespaces = var.developer_namespaces
            }
          }
        }
      }
    },
  )
```

`"API"` disables the legacy `aws-auth` ConfigMap path entirely. `manage_aws_auth_configmap` does not
exist in v21 — if you find yourself reaching for it, you are reading v20 documentation.

> ⚠️ **`authentication_mode` is a one-way door.** Per AWS: once access entries are enabled they
> cannot be disabled, and *"if the ConfigMap method is not enabled during cluster creation, it
> cannot be enabled later."* So `API` → `API_AND_CONFIG_MAP` is impossible after creation; the
> cluster must be rebuilt. This is the right choice, but it is a choice made once, at create time.
>
> Note also that the module's own default is `API_AND_CONFIG_MAP`, and the raw EKS API's default
> when called by an SDK (which is what Terraform is) is the fully legacy `CONFIG_MAP`. Leaving this
> unset does not get you the modern behaviour.

`enable_cluster_creator_admin_permissions = true` is not optional in practice: without it the IAM
identity that ran `terraform apply` has zero Kubernetes RBAC and the very first `kubectl get nodes`
returns *"error: You must be logged in to the server (Unauthorized)"*.

**On the developer entries.** EKS supports scoping an access policy to specific namespaces
(`type = "namespace"`, with wildcards like `team-*` allowed; EKS does not verify the namespaces
exist). The four policies are `AmazonEKSViewPolicy`, `AmazonEKSEditPolicy`, `AmazonEKSAdminPolicy`
and `AmazonEKSClusterAdminPolicy`. Handing every developer cluster-admin is the default failure mode
of a POC and is worth avoiding in two lines of HCL.

Two behaviours to document rather than field as bug reports later:

- `kubectl auth can-i --list` reports **nothing** granted via access policies — it only reflects
  Kubernetes `Role`/`ClusterRole` bindings. The access works; the introspection command cannot see it.
- Access policies bound the *scope*, not privilege escalation *within* that scope. A developer with
  edit rights in a namespace can still create a pod there. Namespace scoping limits blast radius; it
  is not a sandbox for a hostile user.

Access entries of type `EC2_LINUX` (the Karpenter node role, Phase 3) **cannot** take an access
policy — AWS grants those the permissions they need automatically. Only `STANDARD` entries can.

### 2.3 Encryption and logging

```hcl
  # create_kms_key defaults to true; a CMK with rotation is created for
  # envelope-encrypting Kubernetes Secrets.
  create_kms_key            = true
  kms_key_enable_default_policy = true
  encryption_config = {
    resources = ["secrets"]
  }

  enabled_log_types = var.enabled_log_types   # v20 called this cluster_enabled_log_types
  create_cloudwatch_log_group              = true
  cloudwatch_log_group_retention_in_days   = var.log_retention_days
```

> ⚠️ **Verify the exact CloudWatch log-group variable names against the tag before using them** —
> they were not in the verified name list. Read:
> `https://raw.githubusercontent.com/terraform-aws-modules/terraform-aws-eks/v21.24.2/variables.tf`
> and grep for `cloudwatch_log_group`. Correct any drift here and note it in your completion report.
> The same applies to any other variable in this document not present in
> `reference/version-pinning.md`.

Note on `encryption_config`: in v21, passing `null` **disables** the custom CMK. The v20 idiom of
`{}` no longer does that — `{}` is not `null`, so the module still emits the block with
`resources = ["secrets"]`.

> **The CMK is a real trade-off, not a free win — state it in the README.**
>
> Since Kubernetes 1.28, EKS provides *default envelope encryption for all Kubernetes API data*
> using KMS provider v2 with an AWS-owned key, at no cost and with no configuration. So a CMK is no
> longer required for baseline at-rest protection; what it buys you is a key whose **policy,
> rotation and audit trail you control**, which is what compliance regimes actually ask for.
>
> What it costs: ~$1/month plus KMS request charges, and a genuine availability risk. Per AWS, if
> the key is disabled the cluster *"will be immediately placed in an unhealthy/degraded state"*
> (with a 30-day window to re-enable, and you keep paying for it meanwhile); if the key is deleted,
> or a `KMS_KEY_NOT_FOUND` / `KMS_GRANT_REVOKED` occurs, *"your cluster will not be recoverable."*
>
> This build keeps the CMK on (the assessment rewards demonstrating the control) with a 30-day
> deletion window and rotation enabled — **and it builds the alarm, rather than recommending one.**

Because that availability risk is real, this phase creates the stack's **only detection mechanism**.
KMS publishes no "key disabled" metric, so the trigger is a CloudTrail event via EventBridge:

```hcl
resource "aws_sns_topic" "alerts" {
  name              = "${var.name}-alerts"
  kms_master_key_id = "alias/aws/sns"
}

resource "aws_sns_topic_subscription" "alerts_email" {
  count     = var.alert_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email   # confirm the subscription from your inbox, or it is silent
}

# Disabling or scheduling deletion of the cluster CMK degrades the cluster
# immediately and, if the deletion completes, makes it UNRECOVERABLE. This is
# the one failure in the design with no rollback, so it gets the one alarm.
resource "aws_cloudwatch_event_rule" "kms_key_danger" {
  name        = "${var.name}-kms-key-danger"
  description = "EKS CMK disabled or scheduled for deletion"
  event_pattern = jsonencode({
    source        = ["aws.kms"]
    "detail-type" = ["AWS API Call via CloudTrail"]
    detail = {
      eventSource = ["kms.amazonaws.com"]
      eventName   = ["DisableKey", "ScheduleKeyDeletion", "DisableKeyRotation"]
      requestParameters = { keyId = [module.eks.kms_key_id, module.eks.kms_key_arn] }
    }
  })
}

resource "aws_cloudwatch_event_target" "kms_key_danger" {
  rule      = aws_cloudwatch_event_rule.kms_key_danger.name
  target_id = "sns"
  arn       = aws_sns_topic.alerts.arn
}
```

The SNS topic policy must allow `events.amazonaws.com` to publish. Note this depends on CloudTrail
being enabled in the account — **verify that**, and if it is not, say so in your completion report
rather than shipping an alarm that can never fire.

Do not expand this into a general alerting stack; §6 scopes that out deliberately. This is one
alarm, for the one unrecoverable failure.

Audit logs are the expensive one and the one auditors ask for. All five types are on by default per
interface-contract §3; retention is 90 days — note that 90 is the *module's* default, not an AWS
recommendation. Real retention is driven by whatever compliance regime applies.

One operational limit worth a code comment: a CloudWatch Logs entry maxes out at 256 KB while a
Kubernetes API request can be 1.5 MiB, so unusually large audit entries are truncated.

### 2.4 Add-ons

```hcl
  addons = {
    vpc-cni = {
      # Must exist before nodes join, or they come up without pod networking.
      before_compute = true
      most_recent    = true
      # Cheap safety net: v21 changed this default from OVERWRITE to NONE, so if
      # a conflicting resource ever does exist, creation fails. See the note below
      # on why a conflict is unlikely with THIS module.
      resolve_conflicts_on_create = "OVERWRITE"
      configuration_values = jsonencode({
        env = {
          ENABLE_PREFIX_DELEGATION = "true"
          WARM_PREFIX_TARGET       = "1"
        }
      })

      # Give the CNI its own identity so the NODE roles do not need
      # AmazonEKS_CNI_Policy. See the note below — this is what makes S-32
      # and S-27 true rather than aspirational.
      pod_identity_association = [{
        role_arn        = aws_iam_role.vpc_cni.arn
        service_account = "aws-node"
      }]
    }

    kube-proxy = {
      most_recent                 = true
      resolve_conflicts_on_create = "OVERWRITE"
    }

    coredns = {
      most_recent                 = true
      resolve_conflicts_on_create = "OVERWRITE"
    }

    # NON-OPTIONAL. The Karpenter controller authenticates via EKS Pod Identity;
    # without this agent it cannot obtain credentials and never provisions a node.
    eks-pod-identity-agent = {
      before_compute = true
      most_recent    = true
    }

    aws-ebs-csi-driver = {
      most_recent = true
      pod_identity_association = [{
        role_arn        = aws_iam_role.ebs_csi.arn
        service_account = "ebs-csi-controller-sa"
      }]
    }
  }
```

> ⚠️ **This add-on list is not optional garnish — it is the whole control plane's data path.**
> EKS module v21.24.2 hardcodes the cluster's `bootstrap_self_managed_addons` to **`false`** (it is
> not exposed as a variable, and it sits in `lifecycle.ignore_changes`). So unlike a cluster created
> through the console or the raw API, **nothing is installed by default**: if you omit `vpc-cni`,
> `coredns` or `kube-proxy` from this map, the cluster comes up with no pod networking and no
> cluster DNS, and every node joins broken.
>
> The same fact is why `resolve_conflicts_on_create = "OVERWRITE"` is usually unnecessary *with this
> module* — there is no pre-existing self-managed add-on to conflict with. Keep it anyway; it costs
> nothing and covers the case where a cluster was created another way. Do not remove it "because the
> module handles it".
>
> Verify the hardcoding still holds before relying on it:
> ```bash
> curl -s https://raw.githubusercontent.com/terraform-aws-modules/terraform-aws-eks/v21.24.2/main.tf \
>   | grep -n 'bootstrap_self_managed_addons'
> ```

**On `ENABLE_PREFIX_DELEGATION`.** It changes the VPC CNI from allocating individual secondary IPs
to allocating `/28` prefixes. Be accurate about what that buys you here: it markedly reduces EC2 API
pressure and IP-allocation latency when Karpenter is churning nodes, which is the real benefit in
this design. It does **not**, on its own, raise the pod-per-node ceiling on Karpenter nodes —
Karpenter's `maxPods` calculation still uses the secondary-IP formula and does not account for
prefix delegation (upstream issue `aws/karpenter-provider-aws#8210`, still open). To actually raise
density you would also have to set `kubelet: { maxPods: ... }` in the EC2NodeClass, which this build
does not do because a 2-vCPU node with 110 pods is not a sensible default. Justify the setting on API
pressure, and do not claim a density win the configuration does not deliver.

**On the node IAM roles — the `AmazonEKS_CNI_Policy` problem.**

Both node roles get `AmazonEKS_CNI_Policy` by default: the karpenter submodule attaches it when
`node_iam_role_attach_cni_policy` is `true` (its default), and the managed-node-group submodule does
the same via `iam_role_attach_cni_policy`. That policy grants ENI and IP-address manipulation
(`ec2:CreateNetworkInterface`, `AssignPrivateIpAddresses`, …) to the **node**, and any pod running
with `hostNetwork: true` inherits the node's credentials regardless of the IMDS hop limit (S-51's
stated limitation). So a least-privilege claim that ignores this is not true.

The fix is the pattern this phase already uses for the EBS CSI driver — give the CNI its own Pod
Identity role and take the policy off the nodes:

```hcl
  # in the managed node group definition
  iam_role_attach_cni_policy = false
```

```hcl
# iam.tf — same trust policy shape as the EBS CSI role
resource "aws_iam_role" "vpc_cni" {
  name               = "${var.name}-vpc-cni"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "vpc_cni" {
  role       = aws_iam_role.vpc_cni.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}
```

Phase 3 sets `node_iam_role_attach_cni_policy = false` on the Karpenter node role for the same
reason. **Verify pod networking still works after this change** — it is the one modification in this
plan that can break the data plane if the association is wrong. `kubectl get pods -n kube-system -l
k8s-app=aws-node` and confirm a new pod gets an IP.

**On add-on versions:** do not hardcode version strings. `most_recent = true` (the module's default
in v21) resolves them at apply time.

> **Change-management consequence, worth a line in the README's Operations section:** `most_recent`
> re-resolves at *every* plan. An apply you run six weeks later to change an unrelated variable can
> therefore also propose in-place upgrades of `vpc-cni`, `coredns`, `kube-proxy` and the EBS CSI
> driver — the four components whose failure takes the data plane down. Always read the plan diff for
> `aws_eks_addon` version changes before approving. If you later want reproducible pins, capture the resolved
versions after the first apply with `aws eks describe-addon --cluster-name <c> --addon-name <a>`,
and note that `most_recent` is an input on the *module's* `addons` object — the underlying
`aws_eks_addon` resource has no such argument.

### 2.5 The EBS CSI Pod Identity role (`iam.tf`)

Pod Identity trust policy — note it is `pods.eks.amazonaws.com`, and it needs **both**
`sts:AssumeRole` and `sts:TagSession`:

```hcl
data "aws_iam_policy_document" "pod_identity_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ebs_csi" {
  name               = "${var.name}-ebs-csi"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role = aws_iam_role.ebs_csi.name
  # AWS shipped tighter replacements in April 2026: AmazonEBSCSIDriverPolicyV2 and
  # AmazonEBSCSIDriverEKSClusterScopedPolicy, described as "more restrictive
  # alternatives to AmazonEBSCSIDriverPolicy". The cluster-scoped one was extended
  # in May 2026 to honour the eks:eks-cluster-name tag "including open source
  # Karpenter", so it works with Karpenter-launched nodes.
  # AWS's current documentation uses V2 in every example, so prefer it.
  # Verify the ARN before applying:
  #   aws iam list-policies --scope AWS --query "Policies[?contains(PolicyName,'EBSCSIDriver')].[PolicyName,Arn]" --output table
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicyV2"
}
```

Omitting `sts:TagSession` is a common error: the association is created successfully and then every
credential fetch fails at runtime.

### 2.5b There is no default StorageClass — and that is a trap

Installing the EBS CSI driver makes persistent volumes *look* supported. They are not, yet: **EKS
does not create a default StorageClass.** A developer who writes a normal PVC —

```yaml
spec:
  accessModes: [ReadWriteOnce]
  resources: { requests: { storage: 10Gi } }   # no storageClassName
```

— gets a PVC that sits `Pending` forever with `no persistent volumes available for this claim and no
storage class is set`, and a pod stuck `Pending` behind it. There is no error at apply time and
nothing in the cluster explains it. This is the classic "looks supported but silently isn't" gap.

Ship a default `gp3` StorageClass:

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: ebs.csi.aws.com
volumeBindingMode: WaitForFirstConsumer   # REQUIRED with Karpenter: bind the volume
                                          # only once a pod is scheduled, so the volume
                                          # lands in the AZ Karpenter picked. Immediate
                                          # binding creates volumes in the wrong AZ and
                                          # the pod can never schedule.
allowVolumeExpansion: true
reclaimPolicy: Delete                     # POC. Use Retain where data matters.
parameters:
  type: gp3
  encrypted: "true"                       # matches S-24/S-50: everything encrypted at rest
```

`volumeBindingMode: WaitForFirstConsumer` is the load-bearing line. With `Immediate` (the default),
the volume is provisioned in some AZ before scheduling, and Karpenter — which is free to launch the
node anywhere — routinely picks a different one. The pod then cannot start, and the error blames
node affinity rather than the StorageClass.

**Delivery:** this stack has no `kubernetes` provider (ADR-6), so it goes into the local Helm chart
that Phase 5 already uses for cluster-scoped objects. Note it in your completion report so the
Phase 5 agent adds it; do not create a second provider to solve one object.

If you would rather not support persistent storage at all in this POC, that is a legitimate choice —
but then **remove the EBS CSI driver add-on**, so nothing implies PVCs work. Do not leave the driver
installed with no StorageClass.

### 2.6 The bootstrap managed node group

```hcl
  eks_managed_node_groups = {
    bootstrap = {
      # Graviton: cheaper, and it demonstrates that even the control tier runs on arm64.
      #
      # ami_type MUST match the architecture of instance_types. Since
      # instance_types is a variable, someone will eventually set it to a
      # non-Graviton family (t4g unavailable in their region, arm64 quota
      # exhausted) and get a hard mismatch. Derive it rather than hardcoding:
      ami_type       = var.bootstrap_node_ami_type
      instance_types = var.bootstrap_node_instance_types   # default ["t4g.medium"]
      capacity_type  = "ON_DEMAND"                         # see ADR-3: not Spot, deliberately

      # The Karpenter chart defaults to replicas=2 with a REQUIRED podAntiAffinity on
      # kubernetes.io/hostname. Fewer than 2 nodes leaves a Karpenter pod Pending forever.
      min_size     = var.bootstrap_node_min_size     # 2
      max_size     = var.bootstrap_node_max_size     # 3
      desired_size = var.bootstrap_node_desired_size # 2

      subnet_ids = var.private_subnet_ids

      labels = {
        "node-role" = "bootstrap"
      }

      taints = var.taint_bootstrap_nodes ? {
        critical_addons = {
          key    = "CriticalAddonsOnly"
          value  = "true"
          effect = "NO_SCHEDULE"
        }
      } : {}

      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size           = 50
            volume_type           = "gp3"
            encrypted             = true
            delete_on_termination = true
          }
        }
      }

      metadata_options = {
        http_endpoint               = "enabled"
        http_tokens                 = "required"   # IMDSv2 only
        http_put_response_hop_limit = 1
      }
    }
  }
```

**On the taint.** `var.taint_bootstrap_nodes` defaults to `true`. Tainting keeps user workloads off
the system nodes, so `kubectl get nodes` cleanly separates "the two nodes Terraform made" from
"the nodes Karpenter made" — which makes the Phase 6 demo unambiguous. The components that must
tolerate it:

| Component | Tolerates `CriticalAddonsOnly`? |
|---|---|
| Karpenter | Yes — chart default toleration. |
| CoreDNS (EKS add-on) | Yes — EKS ships this toleration. **Verify, do not assume.** |
| `eks-pod-identity-agent`, `vpc-cni`, `kube-proxy` | Yes — DaemonSets with broad tolerations. |
| `aws-ebs-csi-driver` controller | **Verify.** If the controller pods stay `Pending`, that is why. |
| Phase 9 / 10 components | Must be given the toleration explicitly. Note this in your report. |

Verification is one command, in the acceptance criteria below. If anything is stuck `Pending`,
either add the toleration to that component or set `taint_bootstrap_nodes = false` and say so.

**The taint is a scheduling convention, not a security boundary.** `AmazonEKSEditPolicy` lets any
developer write an arbitrary pod spec, and two lines —
`tolerations: [{key: CriticalAddonsOnly, operator: Exists}]`, widely copy-pasted from tutorials —
put their workload next to the Karpenter controller and CoreDNS on the On-Demand bootstrap nodes.
Nothing enforces the separation. Say this in the README rather than describing the taint as though
it isolates anything.

> **The bootstrap group is a fixed-size capacity dead end, and Karpenter is its first casualty.**
> It runs `min 2 / max 3`, Karpenter cannot grow it (it does not manage this node group and will not
> launch capacity for itself), and there is no autoscaler attached to it. So as system components
> accumulate — Karpenter at 1 CPU / 1Gi, CoreDNS, the EBS CSI controller, plus anything Phase 9/10
> adds with a `CriticalAddonsOnly` toleration — the two `t4g.medium` nodes (2 vCPU / 4 GiB each)
> fill up. The first symptom is a Karpenter replica going `Pending`, which then means nothing else
> in the cluster scales either.
>
> Mitigations, in order: keep the taint on so only system components land here; raise
> `bootstrap_node_instance_types` to `t4g.large` before adding controllers; and if you add Phase 9
> or 10, re-check headroom with `kubectl top nodes` and `kubectl describe node`. Record the decision
> in the README's Operations section — an operator who does not know this will debug it as a
> Karpenter bug.

> **`desired_size` is ignored by this module — by design.** The module puts `desired_size` in a
> `lifecycle { ignore_changes }` so that autoscalers can move it without Terraform fighting them.
> Consequence: raising `desired_size` in HCL after creation produces *"No changes"*, and if you were
> raising it to give the second Karpenter replica somewhere to land, that replica stays `Pending`
> and nothing explains why. Change it with `aws eks update-nodegroup-config`, or via `min_size`.

### 2.7 The node security group tag — Phase 1 deferred this to you

```hcl
  node_security_group_tags = {
    # Karpenter's EC2NodeClass securityGroupSelectorTerms matches on this.
    # Phase 1 tagged the subnets; the node SG is created by THIS module, so it is tagged here.
    "karpenter.sh/discovery" = var.name
  }
```

Miss this and Karpenter reports `no security groups found` and provisions nothing.

**At most one security group in the entire account may carry this tag.** The selector matches by tag
across the account, so a second tagged SG makes Karpenter attach the wrong one — or refuse. The
module's own docs carry this warning.

Related, and worth getting right now rather than debugging in Phase 9: leave
`attach_cluster_primary_security_group` at its default of `false`. Setting it `true` attaches *both*
the EKS-created cluster primary SG and the module's node SG to every node, and the AWS Load Balancer
Controller then fails with `expect exactly one securityGroup tagged with kubernetes.io/cluster/<name>`.

### 2.8 Outputs

Exactly interface-contract §5.2. Remember the naming asymmetry:

```hcl
output "cluster_name"    { value = module.eks.cluster_name }     # ✅
output "cluster_version" { value = module.eks.cluster_version }  # ✅
# module.eks.name and module.eks.kubernetes_version DO NOT EXIST
```

Mark `cluster_certificate_authority_data` as `sensitive = true` at both module and root level.

Add the root-level convenience output:

```hcl
output "configure_kubectl" {
  description = "Run this to point kubectl at the new cluster."
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}
```

---

## Security requirements owned by this phase

- **S-20** `authentication_mode = "API"`; the aws-auth ConfigMap path is not used.
- **S-21** Secrets envelope-encrypted with a customer-managed KMS key that has rotation enabled.
- **S-22** All five control-plane log types enabled, with an explicit retention period.
- **S-23** Public endpoint either disabled or restricted to an explicit CIDR allowlist; never `0.0.0.0/0`.
- **S-24** Node group root volumes encrypted; IMDSv2 required with hop limit 1.
- **S-25** `eks-pod-identity-agent` installed; the EBS CSI driver uses Pod Identity, not a static key.
- **S-26** Cluster admin access granted only to `enable_cluster_creator_admin_permissions` plus an explicit `var.admin_principal_arns` list.

---

## Acceptance criteria

Without credentials:

```bash
terraform fmt -check -recursive
terraform init -backend=false
terraform validate
```

Static assertions — each must print PASS:

```bash
cd modules/eks
grep -q 'authentication_mode *= *"API"'                       main.tf && echo "PASS: access entries"
grep -q 'enable_cluster_creator_admin_permissions *= *true'   main.tf && echo "PASS: not locked out"
grep -q 'eks-pod-identity-agent'                              main.tf && echo "PASS: pod identity agent"
grep -q 'karpenter.sh/discovery'                              main.tf && echo "PASS: node SG tagged"
grep -q 'before_compute *= *true'                             main.tf && echo "PASS: vpc-cni ordering"
grep -q 'resolve_conflicts_on_create *= *"OVERWRITE"'         main.tf && echo "PASS: addon adoption"
grep -q 'sts:TagSession'                                      iam.tf  && echo "PASS: pod identity trust"
grep -q 'http_tokens *= *"required"'                          main.tf && echo "PASS: IMDSv2"

# These must find NOTHING (v20 names / locked-out config).
# NOTE: strip comments first. This phase REQUIRES you to write comments such as
# `# v20 called this cluster_name`, so an unanchored grep matches your own
# documentation and reports a false failure — which then trains you to ignore it.
grep -vE '^[[:space:]]*#' main.tf | grep -nE 'cluster_version|cluster_enabled_log_types|manage_aws_auth_configmap'
grep -vE '^[[:space:]]*#' outputs.tf | grep -nE 'module\.eks\.name|module\.eks\.kubernetes_version'
```

With credentials (this is where the phase is really proven — allow ~15 minutes):

```bash
terraform apply
aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER"

kubectl get nodes                                   # exactly 2 Ready nodes, ARM64
kubectl get nodes -o jsonpath='{.items[*].status.nodeInfo.architecture}'   # arm64 arm64

# Nothing may be stuck Pending — this is the taint check from §2.6.
kubectl get pods -A --field-selector=status.phase=Pending
# Expect: "No resources found". If not, read the events:
kubectl describe pod -n kube-system <pending-pod> | tail -20

kubectl get pods -n kube-system                     # coredns, aws-node, kube-proxy,
                                                    # eks-pod-identity-agent, ebs-csi-* all Running
aws eks describe-cluster --name "$CLUSTER" \
  --query 'cluster.{version:version,logging:logging.clusterLogging,encryption:encryptionConfig,endpoint:resourcesVpcConfig}'
```

---

## Notes for the implementing agent

- Do **not** add a `helm` provider block yet — Phase 4 does that. There is no `kubernetes`
  provider in this stack at all (ADR-6). Nothing in this phase
  needs to talk to the Kubernetes API.
- Do **not** install Karpenter here, and do not create its IAM roles. Phase 3 owns them.
- If `kubernetes_version = "1.36"` is rejected by the API, the version list has moved. Re-run the
  check in `reference/version-pinning.md` §3, update that file, and note it.
- The first apply takes 12–20 minutes. Most of it is the control plane. This is normal.

---

## Agent prompt

```text
Implement Phase 2 of the EKS + Karpenter Terraform assessment.

Working directory: /home/artin/personal/git/dso-projects/terraform

SCOPE BOUNDARY — non-negotiable, applies to every action you take:
  1. Your working directory is /home/artin/personal/git/dso-projects/terraform. You never leave it.
     Every path in this prompt and in every doc it references is RELATIVE TO THAT DIRECTORY.
  2. The sibling directory /home/artin/personal/git/dso-projects/architecture is a DIFFERENT,
     UNRELATED assessment. Do not read it, write to it, list it, grep it, or cd into it.
     There is nothing in it you need.
  3. Create NOTHING at the repository root (/home/artin/personal/git/dso-projects) — no new files,
     no new directories, no sibling of terraform/ or architecture/. Everything you produce
     lives under terraform/. That includes .gitignore, CI config, scripts and notes.
  4. Do not run commands that walk the whole repo (`find /home/artin/personal/git/dso-projects`,
     `grep -r` from the root, `git status` at the root). Scope every search to terraform/.
  If you believe you genuinely need something outside terraform/, stop and say so in your
  completion report instead of doing it.

Read these files first, in this order:
  1. docs/00-architecture-and-decisions.md          (ADR-3, ADR-4, ADR-5)
  2. docs/contracts/interface-contract.md           (NORMATIVE — §5.2 signature)
  3. docs/reference/version-pinning.md              (§4 v20->v21 RENAMES — read carefully,
                                                             §5 dangerous defaults)
  4. docs/reference/karpenter-api-reference.md      (§6 — why 2 bootstrap nodes)
  5. docs/phases/phase-02-eks-cluster.md            (your specification)
  6. docs/phases/phase-01-networking.md             (read its Completion report only)

Implement modules/eks/ exactly as phase-02 specifies, then wire it into
main.tf as `module "eks"` and add the cluster outputs to outputs.tf.

Critical constraints:
  - The eks module is v21. INPUTS are `name` and `kubernetes_version`; OUTPUTS are
    `cluster_name` and `cluster_version`. Do not mix these up.
  - Any variable name in the phase doc that is NOT listed as verified in
    reference/version-pinning.md must be checked against
    https://raw.githubusercontent.com/terraform-aws-modules/terraform-aws-eks/v21.24.2/variables.tf
    before you use it. Correct any drift and record it in your completion report.
  - Do NOT add a helm provider block (Phase 4 owns it). This stack never uses a kubernetes
    provider at all.
  - Do NOT create Karpenter IAM roles or the SQS queue (Phase 3 owns those).
  - terraform fmt -recursive must be clean.
  - Do NOT run `terraform apply` unless I have told you AWS credentials are available.
    Otherwise stop at fmt/init/validate plus the static assertions.

When finished, run the applicable "Acceptance criteria", then fill in the
"## Completion report" section at the bottom of docs/phases/phase-02-eks-cluster.md
and stop. Do not start Phase 3.
```

---

## Completion report

*To be filled in by the implementing agent.*

- Status:
- Files created/changed:
- Deviations from spec (**especially any variable name you had to correct**):
- Names added to interface-contract.md:
- Verification run:
- Notes for the next phase:
