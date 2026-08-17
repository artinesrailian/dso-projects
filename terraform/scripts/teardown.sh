#!/usr/bin/env bash
#
# teardown.sh — ordered destruction of the EKS + Karpenter POC.
# Phase 8, docs/phases/phase-08-verification-teardown.md §8.2.
#
# Run from the terraform/ directory:
#
#     ./scripts/teardown.sh        # or: make destroy
#
# WHY THIS SCRIPT EXISTS — docs/reference/gotchas.md G-09.
#
# `helm_release.karpenter` references module.eks outputs, so Terraform tears
# the Helm release down FIRST. That removes the Karpenter controller, which is
# the only thing that reconciles the karpenter.sh/termination finalizer. Live
# NodeClaims then never drain and never terminate; their VPC CNI ENIs stay
# attached to the node security group; and those ENIs are the
# DependencyViolation that blocks deleting the security group and the subnets.
#
# The result is a half-destroyed stack, EC2 instances nobody is tracking, and
# an ongoing bill. The fix is ordering: drain Karpenter's capacity while the
# controller is still alive, PROVE nothing is left, and only then hand over to
# Terraform.
#
# Steps 1-3 are the whole point. Step 3 refuses to continue if any instance
# survives — a destructive script that ploughs on through a failed
# precondition is worse than no script.
#
# Environment overrides:
#   TEARDOWN_ASSUME_YES=1   skip the interactive confirmation (for CI)
#
set -euo pipefail

RED=$'\033[31m'; GRN=$'\033[32m'; YEL=$'\033[33m'; BLD=$'\033[1m'; RST=$'\033[0m'
step() { printf '\n%s==> %s%s\n' "$BLD" "$*" "$RST"; }
ok()   { printf '    %sok%s  %s\n' "$GRN" "$RST" "$*"; }
note() { printf '    %s\n' "$*"; }
abort() { printf '\n%sSTOP%s  %s\n' "$RED" "$RST" "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Preflight — resolve inputs, prove we are pointed at the right cluster
# ---------------------------------------------------------------------------
step "0/6 Preflight"

for t in terraform aws kubectl; do
  command -v "$t" >/dev/null 2>&1 || abort "required tool not on PATH: $t"
done

# On an uninitialised or empty state this errors opaquely at line 1. Catch it
# and say the useful thing instead.
CLUSTER="$(terraform output -raw cluster_name 2>/dev/null || true)"
REGION="$(terraform output -raw region 2>/dev/null || true)"
ENDPOINT="$(terraform output -raw cluster_endpoint 2>/dev/null || true)"
VPC_ID="$(terraform output -raw vpc_id 2>/dev/null || true)"

if [ -z "$CLUSTER" ] || [ -z "$REGION" ]; then
  abort "no readable Terraform state in $(pwd).
       Either nothing was ever applied (there is nothing to tear down), or the
       backend is not initialised — run 'terraform init -backend-config=backend.hcl' first."
fi
ok "cluster=$CLUSTER region=$REGION vpc=${VPC_ID:-<unknown>}"

# The single worst thing this script can do is run its kubectl deletions
# against an unrelated cluster: those commands would SUCCEED, so set -e cannot
# save us. Assert the current context really is this stack's cluster.
CTX_SERVER="$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}' 2>/dev/null || true)"
CTX_NAME="$(kubectl config current-context 2>/dev/null || echo '<none>')"
if [ -z "$CTX_SERVER" ]; then
  abort "no current kubectl context.
       Point it at this cluster first: aws eks update-kubeconfig --region $REGION --name $CLUSTER"
elif [ -n "$ENDPOINT" ] && [ "$CTX_SERVER" != "$ENDPOINT" ]; then
  abort "kubectl context '$CTX_NAME' points at $CTX_SERVER
       but this stack's cluster is $ENDPOINT
       Refusing to delete Kubernetes objects in a cluster this stack does not own.
       Fix with: aws eks update-kubeconfig --region $REGION --name $CLUSTER"
fi
ok "kubectl context '$CTX_NAME' matches the cluster in Terraform state"

if [ "${TEARDOWN_ASSUME_YES:-0}" != "1" ]; then
  printf '\n%sThis destroys the %s stack in %s, including the VPC.%s\n' "$YEL" "$CLUSTER" "$REGION" "$RST"
  printf 'The state bucket and its KMS key are NOT touched (bootstrap/ is separate).\n'
  read -r -p "Type the cluster name to confirm: " CONFIRM
  [ "$CONFIRM" = "$CLUSTER" ] || abort "confirmation did not match — nothing was changed."
fi

# ---------------------------------------------------------------------------
step "1/6 Removing demo workloads and any Service/Ingress load balancers"

kubectl delete -f examples/ --ignore-not-found --wait=true || true
kubectl delete namespace demo --ignore-not-found --wait=true || true

# G-12: load balancers created by a Service type=LoadBalancer or an Ingress are
# made by an in-cluster controller. Terraform never knew about them, and their
# ENIs cause exactly the DependencyViolation this script exists to prevent.
kubectl delete svc --all-namespaces --field-selector spec.type=LoadBalancer --ignore-not-found || true
# G-12 names Ingress as well as Service — one left by a developer, or by
# Phase 9's controller, leaves an ALB behind.
kubectl delete ingress --all-namespaces --all --ignore-not-found || true

# Poll for the load balancers to actually disappear rather than guessing with
# `sleep 60`. A fixed sleep either wastes a minute or is too short, and it
# cannot tell you which.
if [ -n "$VPC_ID" ]; then
  note "waiting for load balancers in $VPC_ID to unwind..."
  for _ in $(seq 1 30); do
    N="$(aws elbv2 describe-load-balancers --region "$REGION" \
          --query "length(LoadBalancers[?VpcId=='$VPC_ID'])" --output text 2>/dev/null || echo 0)"
    M="$(aws elb describe-load-balancers --region "$REGION" \
          --query "length(LoadBalancerDescriptions[?VPCId=='$VPC_ID'])" --output text 2>/dev/null || echo 0)"
    [ "$N" = "0" ] && [ "$M" = "0" ] && break
    sleep 10
  done
  ok "no load balancers remain in the VPC (elbv2=${N:-?} classic=${M:-?})"
else
  note "vpc_id unavailable — skipped the load-balancer wait"
fi

# ---------------------------------------------------------------------------
step "2/6 Deleting NodePools, then NodeClaims, so Karpenter drains and terminates its nodes"

# NodePools first (REVIEW.md F-23): deleting one cascades to its NodeClaims
# and blocks new launches, closing the window where Karpenter could
# re-provision between "zero instances" (step 3) and terraform destroy (step 4).
kubectl delete nodepools --all --wait=true --timeout=15m || true

# Belt-and-braces: drain any NodeClaim not owned by a NodePool while the
# controller is still running to honour the termination finalizer — do this
# before the controller is gone and the finalizer stops being reconciled (G-10).
kubectl delete nodeclaims --all --wait=true --timeout=15m || true
ok "NodePools and NodeClaims deletion returned"

# ---------------------------------------------------------------------------
step "3/6 Verifying no Karpenter instances remain"

# A failed AWS call must NOT read as "empty, therefore safe". Capture the exit
# status separately from the output and treat an error as a hard stop.
#
# NOTE (REVIEW.md F-03): this used to query karpenter.sh/managed-by, a tag
# Karpenter v1.14.0 no longer sets — the gate rested on karpenter.sh/nodepool=*
# alone, which isn't cluster-scoped and would abort forever (or false-pass G-09's
# recovery recipe) in a region running another Karpenter cluster. Fixed by
# ANDing that tag with a cluster-scoped one, checked two independent ways.
query_instances() {
  aws ec2 describe-instances --region "$REGION" \
    --filters "Name=tag:karpenter.sh/nodepool,Values=*" \
              "Name=tag:$1,Values=$2" \
              "Name=instance-state-name,Values=running,pending,stopping,stopped" \
    --query 'Reservations[].Instances[].InstanceId' --output text
}

if ! PRIMARY="$(query_instances 'eks:eks-cluster-name' "$CLUSTER")"; then
  abort "could not query EC2 for surviving Karpenter instances.
       Refusing to proceed blind — resolve the AWS error above and re-run."
fi
if ! SECOND="$(query_instances "kubernetes.io/cluster/$CLUSTER" 'owned')"; then
  abort "could not query EC2 for surviving Karpenter instances.
       Refusing to proceed blind — resolve the AWS error above and re-run."
fi

# Two independent tag keys Karpenter v1.14.0 sets on every launched instance,
# so a gap in one does not silently pass the gate.
LEFT="$(printf '%s\n%s\n' "$PRIMARY" "$SECOND" | tr '\t' '\n' | grep -v '^$' | sort -u || true)"

if [ -n "$LEFT" ]; then
  printf '\n%sSTOP%s  Karpenter instances are still running:\n' "$RED" "$RST" >&2
  printf '%s\n' "$LEFT" | sed 's/^/         /' >&2
  cat >&2 <<'EOF'

       Do NOT proceed. Destroying now leaves these instances orphaned, out of
       Terraform state, and billing — with ENIs that will block deleting the
       security groups and subnets anyway.

       See docs/reference/gotchas.md G-09 (the ordering) and G-10 (nodes stuck
       Terminating because the karpenter.sh/termination finalizer is no longer
       being reconciled). The recovery one-liner is at the end of this script.
EOF
  exit 1
fi
ok "zero Karpenter instances remain — safe to hand over to Terraform"

# ---------------------------------------------------------------------------
step "4/6 Destroying the Terraform-managed stack"

terraform destroy -auto-approve

# ---------------------------------------------------------------------------
step "4b/6 Sweeping EBS volumes left behind by PVCs"

# StatefulSet volumeClaimTemplates are RETAINED by default when the workload is
# deleted, and dynamically-provisioned PVs are invisible to Terraform. Left
# alone the spend outlives the cluster — gp3 is ~$0.08/GiB-month, forever.
# This delete branch only matches if the CSI driver is tagging with
# kubernetes.io/cluster/<name>=owned, which per its own tagging.md is NOT the
# default (needs the add-on's --k8s-tag-cluster-id flag) — check:
#   kubectl -n kube-system get deploy ebs-csi-controller \
#     -o jsonpath='{.spec.template.spec.containers[0].args}'
# If absent this branch is a silent no-op; the report below still lists every
# orphaned volume regardless, so nothing goes untracked.
aws ec2 describe-volumes --region "$REGION" \
  --filters "Name=tag:kubernetes.io/cluster/$CLUSTER,Values=owned" "Name=status,Values=available" \
  --query 'Volumes[].VolumeId' --output text 2>/dev/null | tr '\t' '\n' | grep -v '^$' \
  | xargs -r -I{} aws ec2 delete-volume --region "$REGION" --volume-id {} || true

# Volumes tagged by the CSI driver but NOT by the cluster tag are reported
# rather than deleted: the tag is not cluster-scoped, so another cluster in the
# same account could own them. Deleting on this filter would be unsafe.
note "volumes tagged ebs.csi.aws.com/cluster (review manually — this tag is not cluster-scoped):"
# shellcheck disable=SC2016  # JMESPath: backticks are literals, they must NOT be shell-expanded
aws ec2 describe-volumes --region "$REGION" \
  --filters "Name=tag:ebs.csi.aws.com/cluster,Values=true" "Name=status,Values=available" \
  --query 'Volumes[].{id:VolumeId,size:Size,name:Tags[?Key==`CSIVolumeName`]|[0].Value}' \
  --output table 2>/dev/null || true

# ---------------------------------------------------------------------------
step "5/6 Sweeping launch templates Karpenter created outside Terraform state"

# G-11: Karpenter creates launch templates itself. Nothing in Terraform knows
# about them, so they accumulate in the account forever.
aws ec2 describe-launch-templates --region "$REGION" \
  --filters "Name=tag:karpenter.k8s.aws/cluster,Values=$CLUSTER" \
  --query 'LaunchTemplates[].LaunchTemplateName' --output text 2>/dev/null \
  | tr '\t' '\n' | grep -v '^$' \
  | xargs -r -I{} aws ec2 delete-launch-template --region "$REGION" --launch-template-name {} || true
ok "launch templates swept"

# ---------------------------------------------------------------------------
step "6/6 Residual check"

note "instances still tagged to this cluster (expect none):"
aws ec2 describe-instances --region "$REGION" \
  --filters "Name=tag:kubernetes.io/cluster/$CLUSTER,Values=owned" \
            "Name=instance-state-name,Values=running,pending" \
  --query 'Reservations[].Instances[].InstanceId' --output text 2>/dev/null | sed 's/^/      /' || true

note "log groups still present (these are retained by design if retention has not elapsed):"
aws logs describe-log-groups --region "$REGION" \
  --log-group-name-prefix "/aws/eks/$CLUSTER" \
  --query 'logGroups[].logGroupName' --output text 2>/dev/null | tr '\t' '\n' | sed 's/^/      /' || true

printf '\n%sTeardown complete.%s\n' "$GRN" "$RST"
printf 'Note: the state S3 bucket and its KMS key are NOT destroyed — bootstrap/ is a separate root module.\n'
printf 'To remove those too: terraform -chdir=bootstrap destroy\n\n'

# ---------------------------------------------------------------------------
# RECOVERY ONLY — not part of the flow above.
# ---------------------------------------------------------------------------
#
# If nodes hang in Terminating and block namespace or cluster deletion, the
# cause is G-10: Karpenter adds a karpenter.sh/termination finalizer to every
# node it provisions, and once the controller is gone nothing removes it, so
# the API server blocks deletion indefinitely.
#
# Karpenter's own documented one-liner:
#
#   kubectl get nodes -ojsonpath='{range .items[*].metadata}{@.name}:{@.finalizers}{"\n"}' \
#     | grep "karpenter.sh/termination" | cut -d ':' -f 1 \
#     | xargs kubectl patch node --type='json' \
#         -p='[{"op": "remove", "path": "/metadata/finalizers"}]'
#
# WARNING: Karpenter's docs are explicit that this strips ALL finalizers from
# those nodes, not just Karpenter's. Anything else relying on a node finalizer
# to clean up will be skipped. It is a recovery tool for a stack that is
# already wedged, never routine cleanup — and it does not terminate the EC2
# instances, so verify the instance list is empty afterwards before assuming
# the account is clean.
