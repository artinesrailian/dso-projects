#!/usr/bin/env bash
#
# verify.sh — end-to-end assertion suite for the EKS + Karpenter POC.
# Phase 8, docs/phases/phase-08-verification-teardown.md §8.1.
#
# Run this AFTER `terraform apply`, from the terraform/ directory:
#
#     ./scripts/verify.sh          # or: make verify
#
# Every check below is a COMPARISON, not a print. A verification script that
# cannot fail is decoration that actively misleads — it prints reassurance.
# The exit code is the result: 0 = everything asserted held, non-zero = at
# least one assertion failed.
#
# Deliberately NOT `set -e`: we want every check to run so one failure gives a
# complete picture rather than the first symptom. `set -u` IS on, which is why
# every derived value below is assigned with a `:-` default and then gated on
# being non-empty — an unresolvable input must become one FAIL, never a dead
# script that exits silently having asserted nothing.
#
# Environment overrides (all optional):
#   VERIFY_NAMESPACE=demo            the governed namespace to probe
#   VERIFY_SKIP_SCHEDULING=1         skip §D (applies real workloads, ~10 min)
#   VERIFY_SKIP_CONSOLIDATION=1      skip §F (waits for scale-to-zero, ~10 min)
#   VERIFY_MIN_VCPU_QUOTA=104        floor for the EC2 vCPU quota assertion
#
set -uo pipefail

RC=0

pass() { printf '  \033[32mPASS\033[0m  %s\n' "$*"; }
fail() { printf '  \033[31mFAIL\033[0m  %s\n' "$*"; RC=1; }
warn() { printf '  \033[33mWARN\033[0m  %s\n' "$*"; }
info() { printf '        %s\n' "$*"; }
section() { printf '\n\033[1m== %s\033[0m\n' "$*"; }
# check <message> <command...> — runs the command and asserts its exit status.
# §8.1's skeleton writes this as `check '<expr>' <msg>` and evals the string;
# taking the condition as ARGUMENTS instead is equivalent, avoids eval, and
# keeps shellcheck able to see the variables (the eval form reports every one
# of them as unused and every quoted expression as a quoting bug).
check() { local msg="$1"; shift; if "$@"; then pass "$msg"; else fail "$msg"; fi; }

# A precondition that makes every later assertion meaningless if it fails.
# Unlike a check, this stops the script — running the rest would produce a
# page of misleading FAILs whose real cause is one missing tool.
die() { printf '\n\033[31mABORT\033[0m  %s\n' "$*" >&2; exit 2; }

# ---------------------------------------------------------------------------
# Preflight — resolve inputs and prove we are pointed at the right cluster
# ---------------------------------------------------------------------------
section "Preflight"

for t in terraform aws kubectl jq; do
  command -v "$t" >/dev/null 2>&1 || die "required tool not on PATH: $t"
done
pass "terraform, aws, kubectl and jq are present"

# `terraform output` on an uninitialised or empty state prints an opaque error.
# Resolve everything once, tolerate failure, then report it as a single ABORT.
CLUSTER="$(terraform output -raw cluster_name 2>/dev/null || true)"
REGION="$(terraform output -raw region 2>/dev/null || true)"
ENDPOINT="$(terraform output -raw cluster_endpoint 2>/dev/null || true)"
RBAC_GROUP="$(terraform output -raw developer_rbac_group 2>/dev/null || true)"
NODE_SG="$(terraform output -raw node_security_group_id 2>/dev/null || true)"
QUEUE="$(terraform output -raw karpenter_interruption_queue_name 2>/dev/null || true)"

[ -n "$CLUSTER" ] || die "could not read 'cluster_name' from terraform output — run this from terraform/ against an applied state"
[ -n "$REGION" ]  || die "could not read 'region' from terraform output"
[ -n "$ENDPOINT" ] || die "could not read 'cluster_endpoint' from terraform output"
pass "terraform state resolves: cluster=$CLUSTER region=$REGION"

NS="${VERIFY_NAMESPACE:-demo}"
MIN_VCPU_QUOTA="${VERIFY_MIN_VCPU_QUOTA:-104}"

# The single most dangerous failure mode for this script: a kubeconfig pointing
# at an unrelated cluster. §D applies workloads and §F deletes them, so this is
# not a read-only tool. Assert the current context really is this cluster.
CTX_SERVER="$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}' 2>/dev/null || true)"
if [ -z "$CTX_SERVER" ]; then
  die "no current kubectl context — run: aws eks update-kubeconfig --region $REGION --name $CLUSTER"
elif [ "$CTX_SERVER" != "$ENDPOINT" ]; then
  die "kubectl context points at $CTX_SERVER but this stack's cluster is $ENDPOINT
       Refusing to run — §D applies workloads and §F deletes them.
       Fix with: aws eks update-kubeconfig --region $REGION --name $CLUSTER"
fi
pass "kubectl context matches the cluster endpoint in Terraform state"

# Karpenter's namespace is a variable (default kube-system) and is not a root
# output — discover it rather than hardcoding, so the script survives a change.
KARPENTER_NS="$(kubectl get deploy -A -l app.kubernetes.io/name=karpenter \
  -o jsonpath='{.items[0].metadata.namespace}' 2>/dev/null || true)"
KARPENTER_NS="${KARPENTER_NS:-kube-system}"
info "Karpenter namespace: $KARPENTER_NS · probing namespace: $NS"

# ---------------------------------------------------------------------------
# A. Cluster health
# ---------------------------------------------------------------------------
section "A. Cluster health"

STATUS="$(aws eks describe-cluster --region "$REGION" --name "$CLUSTER" \
  --query 'cluster.status' --output text 2>/dev/null || true)"
if [ "$STATUS" = "ACTIVE" ]; then pass "cluster status is ACTIVE"
else fail "cluster status is '${STATUS:-<unreadable>}', expected ACTIVE"; fi

# Nodes: assert none is anything other than Ready. An empty node list is also a
# failure — "no nodes" must not read as "no unready nodes".
NODE_TOTAL="$(kubectl get nodes -o json 2>/dev/null | jq -r '.items | length' || echo 0)"
NOT_READY="$(kubectl get nodes -o json 2>/dev/null \
  | jq -r '.items[] | select((.status.conditions[] | select(.type=="Ready") | .status) != "True") | .metadata.name' \
  | tr '\n' ' ' || true)"
if [ "${NODE_TOTAL:-0}" -lt 1 ]; then
  fail "no nodes in the cluster at all"
elif [ -n "${NOT_READY// /}" ]; then
  fail "nodes not Ready: $NOT_READY"
else
  pass "all $NODE_TOTAL node(s) are Ready"
fi

# The bootstrap group must hold >= 2 nodes or Karpenter's own 2-replica
# required podAntiAffinity leaves a replica Pending forever (gotchas G-05).
BOOTSTRAP_NODES="$(kubectl get nodes -l node-role=bootstrap -o name 2>/dev/null | grep -c . || true)"
if [ "${BOOTSTRAP_NODES:-0}" -ge 2 ]; then
  pass "bootstrap node group has $BOOTSTRAP_NODES nodes (>= 2, so Karpenter can run 2 replicas — G-05)"
else
  fail "bootstrap node group has ${BOOTSTRAP_NODES:-0} node(s); Karpenter's required podAntiAffinity needs 2 (G-05)"
fi

# Anything not Running/Succeeded is a taint/toleration or capacity problem.
STUCK="$(kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded \
  -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}({.status.phase}) {end}' 2>/dev/null || true)"
if [ -z "${STUCK// /}" ]; then pass "no pods outside Running/Succeeded"
else fail "pods not Running/Succeeded: $STUCK"; fi

# ---------------------------------------------------------------------------
# B. Configuration matches the claims
# ---------------------------------------------------------------------------
section "B. Configuration matches the claims"

# Compare the LIVE version against the version Terraform recorded at apply.
# A mismatch means the control plane moved underneath the state.
LIVE_VERSION="$(aws eks describe-cluster --region "$REGION" --name "$CLUSTER" \
  --query 'cluster.version' --output text 2>/dev/null || true)"
TF_VERSION="$(terraform output -raw cluster_version 2>/dev/null || true)"
if [ -n "$LIVE_VERSION" ] && [ "$LIVE_VERSION" = "$TF_VERSION" ]; then
  pass "Kubernetes version $LIVE_VERSION matches Terraform state"
else
  fail "Kubernetes version drift: live='${LIVE_VERSION:-?}' terraform='${TF_VERSION:-?}'"
fi

# S-22: all five control-plane log types, not "some logging".
# shellcheck disable=SC2016  # JMESPath: backticks are literals, they must NOT be shell-expanded
LOGS_ON="$(aws eks describe-cluster --region "$REGION" --name "$CLUSTER" \
  --query 'cluster.logging.clusterLogging[?enabled==`true`].types[]' --output text 2>/dev/null | tr '\t' '\n' | sort || true)"
MISSING_LOGS=""
for t in api audit authenticator controllerManager scheduler; do
  printf '%s\n' "$LOGS_ON" | grep -qx "$t" || MISSING_LOGS="$MISSING_LOGS $t"
done
if [ -z "${MISSING_LOGS// /}" ]; then pass "all five control-plane log types enabled"
else fail "control-plane log types not enabled:$MISSING_LOGS"; fi

# S-21: envelope encryption with OUR key, not just the AWS-owned default.
ENC_KEY="$(aws eks describe-cluster --region "$REGION" --name "$CLUSTER" \
  --query 'cluster.encryptionConfig[0].provider.keyArn' --output text 2>/dev/null || true)"
ENC_RES="$(aws eks describe-cluster --region "$REGION" --name "$CLUSTER" \
  --query 'cluster.encryptionConfig[0].resources[0]' --output text 2>/dev/null || true)"
if [ "$ENC_RES" = "secrets" ] && [[ "$ENC_KEY" == arn:aws*:kms:* ]]; then
  pass "Secrets envelope-encrypted with a customer-managed key"
  # S-21 also requires rotation ON. A CMK without rotation half-satisfies it.
  KEY_ID="${ENC_KEY##*/}"
  ROT="$(aws kms get-key-rotation-status --region "$REGION" --key-id "$KEY_ID" \
    --query 'KeyRotationEnabled' --output text 2>/dev/null || true)"
  if [ "$ROT" = "True" ]; then pass "cluster CMK has rotation enabled"
  else fail "cluster CMK rotation is '${ROT:-?}', expected True"; fi
else
  fail "encryptionConfig is not {resources:[secrets], CMK}: resources='${ENC_RES:-?}' key='${ENC_KEY:-?}'"
fi

# S-23 / S-04: the endpoint must not be reachable from the whole internet.
PUB="$(aws eks describe-cluster --region "$REGION" --name "$CLUSTER" \
  --query 'cluster.resourcesVpcConfig.endpointPublicAccess' --output text 2>/dev/null || true)"
CIDRS="$(aws eks describe-cluster --region "$REGION" --name "$CLUSTER" \
  --query 'cluster.resourcesVpcConfig.publicAccessCidrs' --output text 2>/dev/null || true)"
if [ "$PUB" != "True" ]; then
  pass "public endpoint disabled entirely"
elif [[ "$CIDRS" == *"0.0.0.0/0"* ]]; then
  fail "public endpoint allows 0.0.0.0/0 — the control S-04 exists to prevent"
else
  pass "public endpoint restricted to: $CIDRS"
fi

# S-20: access entries, not the legacy aws-auth ConfigMap.
AUTHMODE="$(aws eks describe-cluster --region "$REGION" --name "$CLUSTER" \
  --query 'cluster.accessConfig.authenticationMode' --output text 2>/dev/null || true)"
check "authenticationMode is API (aws-auth path is off) — got '${AUTHMODE:-?}'" [ "$AUTHMODE" = "API" ]

# S-55 / G-13: the discovery tag must resolve to EXACTLY one security group
# ACCOUNT-WIDE. A second tagged SG makes Karpenter silently pick the wrong one.
SG_TAGGED="$(aws ec2 describe-security-groups --region "$REGION" \
  --filters "Name=tag:karpenter.sh/discovery,Values=$CLUSTER" \
  --query 'SecurityGroups[].GroupId' --output text 2>/dev/null | tr '\t' '\n' | grep -c . || true)"
if [ "${SG_TAGGED:-0}" -eq 1 ]; then pass "exactly one security group carries karpenter.sh/discovery=$CLUSTER"
else fail "${SG_TAGGED:-0} security groups carry karpenter.sh/discovery=$CLUSTER — must be exactly 1 (G-13)"; fi
if [ -n "$NODE_SG" ]; then
  TAGGED_ID="$(aws ec2 describe-security-groups --region "$REGION" \
    --filters "Name=tag:karpenter.sh/discovery,Values=$CLUSTER" \
    --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || true)"
  check "the tagged security group is the node SG ($NODE_SG)" [ "$TAGGED_ID" = "$NODE_SG" ]
fi

SUBNETS_TAGGED="$(aws ec2 describe-subnets --region "$REGION" \
  --filters "Name=tag:karpenter.sh/discovery,Values=$CLUSTER" \
  --query 'Subnets[].SubnetId' --output text 2>/dev/null | tr '\t' '\n' | grep -c . || true)"
if [ "${SUBNETS_TAGGED:-0}" -ge 2 ]; then pass "$SUBNETS_TAGGED private subnets carry karpenter.sh/discovery"
else fail "only ${SUBNETS_TAGGED:-0} subnet(s) carry karpenter.sh/discovery — Karpenter will report 'no subnets found'"; fi

# Phase 3 deferred this assertion here deliberately (see its completion report):
# create_spot_service_linked_role defaults false, so nothing in Terraform proves
# AWSServiceRoleForEC2Spot exists. Without it every Spot launch fails (G-07).
if aws iam get-role --role-name AWSServiceRoleForEC2Spot >/dev/null 2>&1; then
  pass "AWSServiceRoleForEC2Spot exists (Spot launches can succeed — G-07)"
else
  fail "AWSServiceRoleForEC2Spot is missing — every Spot launch will fail with AuthFailure.ServiceLinkedRoleCreationNotPermitted (G-07).
        Fix: aws iam create-service-linked-role --aws-service-name spot.amazonaws.com"
fi

# S-24 / S-51: IMDSv2 required with hop limit 1 on every instance in the
# cluster — asserted on the live instances, which covers both the bootstrap
# node group and Karpenter-launched nodes in one check.
# shellcheck disable=SC2016  # JMESPath: backticks are literals, they must NOT be shell-expanded
BAD_IMDS="$(aws ec2 describe-instances --region "$REGION" \
  --filters "Name=tag:kubernetes.io/cluster/$CLUSTER,Values=owned" "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[?MetadataOptions.HttpTokens!=`required`||MetadataOptions.HttpPutResponseHopLimit!=`1`].InstanceId' \
  --output text 2>/dev/null | tr '\t' '\n' | grep -c . || true)"
INSTANCE_TOTAL="$(aws ec2 describe-instances --region "$REGION" \
  --filters "Name=tag:kubernetes.io/cluster/$CLUSTER,Values=owned" "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].InstanceId' --output text 2>/dev/null | tr '\t' '\n' | grep -c . || true)"
if [ "${INSTANCE_TOTAL:-0}" -lt 1 ]; then
  fail "no running instances tagged kubernetes.io/cluster/$CLUSTER — cannot assert IMDSv2"
elif [ "${BAD_IMDS:-0}" -eq 0 ]; then
  pass "all $INSTANCE_TOTAL instance(s) require IMDSv2 with hop limit 1"
else
  fail "$BAD_IMDS of $INSTANCE_TOTAL instance(s) do not require IMDSv2 with hop limit 1"
fi

# S-24 / S-50: every attached volume encrypted.
UNENC="$(aws ec2 describe-volumes --region "$REGION" \
  --filters "Name=tag:kubernetes.io/cluster/$CLUSTER,Values=owned" "Name=encrypted,Values=false" \
  --query 'Volumes[].VolumeId' --output text 2>/dev/null | tr '\t' '\n' | grep -c . || true)"
check "no unencrypted EBS volumes tagged to this cluster (found ${UNENC:-0})" [ "${UNENC:-0}" -eq 0 ]

# ---------------------------------------------------------------------------
# C. Karpenter is functioning
# ---------------------------------------------------------------------------
section "C. Karpenter is functioning"

# G-05: one Running replica and one Pending forever is the classic silent
# failure — assert readyReplicas, not that the Deployment object exists.
K_READY="$(kubectl get deploy -n "$KARPENTER_NS" karpenter -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)"
K_WANT="$(kubectl get deploy -n "$KARPENTER_NS" karpenter -o jsonpath='{.spec.replicas}' 2>/dev/null || true)"
if [ -n "$K_READY" ] && [ "$K_READY" = "$K_WANT" ]; then
  pass "karpenter deployment: $K_READY/$K_WANT replicas ready"
else
  fail "karpenter deployment: ${K_READY:-0}/${K_WANT:-?} replicas ready (G-05: needs 2 distinct nodes)"
fi

NODEPOOLS="$(kubectl get nodepools -o jsonpath='{range .items[*]}{.metadata.name} {end}' 2>/dev/null || true)"
if [ -z "${NODEPOOLS// /}" ]; then
  fail "no NodePools exist — the CRDs or the cluster-resources chart did not land"
else
  pass "NodePools present: $NODEPOOLS"
  for np in $NODEPOOLS; do
    NP_READY="$(kubectl get nodepool "$np" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)"
    check "NodePool/$np is Ready (got '${NP_READY:-?}')" [ "$NP_READY" = "True" ]
  done
fi

EC2NC_READY="$(kubectl get ec2nodeclass default -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)"
if [ "$EC2NC_READY" = "True" ]; then
  pass "EC2NodeClass/default is Ready (subnets and security groups discovered)"
else
  fail "EC2NodeClass/default Ready='${EC2NC_READY:-?}' — check for 'no subnets found' / 'no security groups found' (G-13)"
  kubectl get ec2nodeclass default -o jsonpath='{range .status.conditions[*]}        {.type}={.status} {.message}{"\n"}{end}' 2>/dev/null || true
fi

# S-42: the chart accepts a missing interruptionQueue SILENTLY, which disables
# all interruption handling. Assert the controller was actually given one.
K_QUEUE="$(kubectl get deploy -n "$KARPENTER_NS" karpenter \
  -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="INTERRUPTION_QUEUE")].value}' 2>/dev/null || true)"
if [ -n "$K_QUEUE" ]; then
  pass "interruption queue wired into the controller: $K_QUEUE"
  if [ -z "$QUEUE" ]; then
    warn "karpenter_interruption_queue_name is not readable from state — cannot cross-check the queue name"
  elif [ "$K_QUEUE" = "$QUEUE" ]; then
    pass "controller queue matches Terraform's karpenter_interruption_queue_name"
  else
    fail "controller queue '$K_QUEUE' does not match Terraform's '$QUEUE'"
  fi
else
  fail "INTERRUPTION_QUEUE is empty — Spot interruptions will kill nodes instead of draining them (S-42)"
fi

# NOTE the inversion: finding errors in the log is a FAILURE, so the grep's
# exit code must not be used directly as the success condition.
K_ERRORS="$(kubectl logs -n "$KARPENTER_NS" -l app.kubernetes.io/name=karpenter --tail=200 --all-containers 2>/dev/null \
  | grep -iE 'error|failed' \
  | grep -viE 'no instance types|insufficient capacity|incompatible with nodepool' || true)"
if [ -z "$K_ERRORS" ]; then
  pass "no errors in the last 200 lines of Karpenter controller logs"
else
  fail "Karpenter logged errors:"
  printf '%s\n' "$K_ERRORS" | head -10 | sed 's/^/        /'
fi

# ---------------------------------------------------------------------------
# D. The assignment's actual requirement — both architectures schedule
# ---------------------------------------------------------------------------
section "D. Both architectures schedule (the assignment's actual requirement)"

# Resolve the node a deployment's first pod landed on, then read that NODE's
# arch label. Reading the pod's own nodeSelector would prove nothing — it would
# only echo back what we asked for.
assert_arch() {
  local manifest="$1" deploy="$2" want="$3"
  if [ ! -f "$manifest" ]; then fail "$manifest not found"; return; fi

  kubectl apply -f "$manifest" >/dev/null 2>&1 || { fail "kubectl apply -f $manifest failed"; return; }
  if ! kubectl wait --for=condition=available --timeout=10m "deployment/$deploy" -n "$NS" >/dev/null 2>&1; then
    fail "$deploy never became available within 10m"
    kubectl get pods -n "$NS" -l "app=$deploy" -o wide 2>/dev/null | sed 's/^/        /'
    return
  fi

  local node got
  node="$(kubectl get pods -n "$NS" -l "app=$deploy" -o jsonpath='{.items[0].spec.nodeName}' 2>/dev/null || true)"
  [ -n "$node" ] || { fail "$deploy has no scheduled pod"; return; }
  got="$(kubectl get node "$node" -o jsonpath='{.metadata.labels.kubernetes\.io/arch}' 2>/dev/null || true)"

  if [ "$got" = "$want" ]; then
    local itype cap
    itype="$(kubectl get node "$node" -o jsonpath='{.metadata.labels.node\.kubernetes\.io/instance-type}' 2>/dev/null || true)"
    cap="$(kubectl get node "$node" -o jsonpath='{.metadata.labels.karpenter\.sh/capacity-type}' 2>/dev/null || true)"
    pass "$deploy scheduled on $want ($node, ${itype:-?}, ${cap:-not-karpenter})"
  else
    fail "$deploy wanted arch=$want but landed on '$got' (node $node)"
  fi
}

if [ "${VERIFY_SKIP_SCHEDULING:-0}" = "1" ]; then
  warn "§D skipped (VERIFY_SKIP_SCHEDULING=1) — the assignment's core requirement is NOT verified"
else
  assert_arch examples/deployment-arm64.yaml web-graviton arm64
  assert_arch examples/deployment-x86.yaml   web-x86     amd64
fi

# ---------------------------------------------------------------------------
# D2. The developer permission boundary actually holds
# ---------------------------------------------------------------------------
section "D2. Developer RBAC boundary"

if [ -z "$RBAC_GROUP" ]; then
  fail "could not read 'developer_rbac_group' from terraform output — RBAC boundary unverified"
else
  info "impersonating --as=ci-probe --as-group=$RBAC_GROUP"

  # kubectl auth can-i exits 1 on a denial, so capture output and compare the
  # word — never use its exit status as the assertion.
  cani() { kubectl auth can-i "$@" --as=ci-probe --as-group="$RBAC_GROUP" 2>/dev/null || true; }

  # Assert BOTH directions. A boundary tested only for what it denies could be
  # denying everything, which is a broken cluster rather than a secure one.
  for verb_res in "create deployments" "delete pods" "create horizontalpodautoscalers" \
                  "get resourcequotas" "create poddisruptionbudgets" "get pods/log"; do
    # shellcheck disable=SC2086 # deliberate word splitting: "<verb> <resource>"
    if [ "$(cani $verb_res -n "$NS")" = "yes" ]; then pass "developer CAN $verb_res in $NS"
    else fail "developer cannot $verb_res in $NS — the Role is too narrow to do the job"; fi
  done

  for verb_res in "get secrets" "create serviceaccounts" "create daemonsets" \
                  "create rolebindings" "create ingresses" "create resourcequotas"; do
    # shellcheck disable=SC2086 # deliberate word splitting: "<verb> <resource>"
    if [ "$(cani $verb_res -n "$NS")" = "no" ]; then pass "developer CANNOT $verb_res in $NS"
    else fail "developer CAN $verb_res in $NS — privilege escalation path (S-28c)"; fi
  done

  # The binding is a RoleBinding, so it must not reach another namespace or
  # anything cluster-scoped.
  if [ "$(cani list pods -n kube-system)" = "no" ]; then pass "developer CANNOT read kube-system"
  else fail "developer CAN read kube-system — the RoleBinding is leaking cluster-wide"; fi

  # A denial only proves a boundary if the thing being denied actually exists.
  # `kubectl auth can-i` answers "no" for an unknown resource too — so for a
  # CRD, an uninstalled Karpenter would score a PASS here for entirely the
  # wrong reason. Positive-control each cluster-scoped denial against the
  # UN-impersonated caller (cluster admin) first: admin must get "yes", and
  # only then does the developer's "no" mean anything.
  deny_cluster_scoped() {
    local msg="$1"; shift
    local admin developer
    admin="$(kubectl auth can-i "$@" 2>/dev/null || true)"
    developer="$(cani "$@")"
    if [ "$admin" != "yes" ]; then
      fail "positive control failed: cluster admin cannot '$*' either, so a developer denial proves nothing here ($msg)"
    elif [ "$developer" = "no" ]; then
      pass "$msg"
    else
      fail "developer CAN $* — cluster-scoped leak ($msg)"
    fi
  }

  deny_cluster_scoped "developer CANNOT list nodes" list nodes
  deny_cluster_scoped "developer CANNOT read NodePools" get nodepools.karpenter.sh
fi

# ---------------------------------------------------------------------------
# D2b. The one alarm is actually able to fire
# ---------------------------------------------------------------------------
section "D2b. The CMK-danger alarm can actually fire"

# The topic is named ${cluster_name}-alerts by modules/eks. Resolve by name
# rather than adding a root output solely for this script.
TOPIC="$(aws sns list-topics --region "$REGION" \
  --query "Topics[?ends_with(TopicArn, ':${CLUSTER}-alerts')].TopicArn | [0]" --output text 2>/dev/null || true)"
if [ -z "$TOPIC" ] || [ "$TOPIC" = "None" ]; then
  fail "SNS topic ${CLUSTER}-alerts not found — the CMK alarm has nowhere to publish"
else
  pass "SNS topic exists: $TOPIC"
  # SNS returns the literal "PendingConfirmation" in place of an ARN until
  # somebody clicks the link in the email. An unconfirmed topic is a silent alarm.
  # shellcheck disable=SC2016  # JMESPath: backticks are literals, they must NOT be shell-expanded
  SUBS="$(aws sns list-subscriptions-by-topic --region "$REGION" --topic-arn "$TOPIC" \
    --query 'Subscriptions[?Protocol==`email`].SubscriptionArn' --output text 2>/dev/null || true)"
  if [ -z "${SUBS// /}" ]; then
    fail "no email subscription on $TOPIC — set var.alert_email, then confirm it"
  elif printf '%s' "$SUBS" | grep -q 'PendingConfirmation'; then
    fail "SNS subscription never confirmed — the CMK alarm cannot notify anyone"
  else
    pass "SNS email subscription is confirmed"
  fi
fi

# The detector is an EventBridge rule on CloudTrail events. No trail, no
# events, no alarm — and nothing else in this build would tell you.
TRAILS="$(aws cloudtrail describe-trails --region "$REGION" --query 'length(trailList)' --output text 2>/dev/null || echo 0)"
if [ "${TRAILS:-0}" != "0" ]; then pass "CloudTrail is enabled ($TRAILS trail(s)) — the CMK rule can receive events"
else fail "no CloudTrail in this region — the CMK alarm can never fire (S-29)"; fi

RULE_STATE="$(aws events describe-rule --region "$REGION" --name "${CLUSTER}-kms-key-danger" \
  --query 'State' --output text 2>/dev/null || true)"
check "EventBridge rule ${CLUSTER}-kms-key-danger is ENABLED (got '${RULE_STATE:-missing}')" [ "$RULE_STATE" = "ENABLED" ]

# ---------------------------------------------------------------------------
# D3. The guardrails exist and are Terraform-owned
# ---------------------------------------------------------------------------
section "D3. Namespace guardrails"

PSA="$(kubectl get ns "$NS" -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}' 2>/dev/null || true)"
check "namespace $NS enforces Pod Security 'restricted' (got '${PSA:-none}')" [ "$PSA" = "restricted" ]

RQ="$(kubectl get resourcequota -n "$NS" -o name 2>/dev/null | grep -c . || true)"
check "namespace $NS has a ResourceQuota" [ "${RQ:-0}" -ge 1 ]

LR="$(kubectl get limitrange -n "$NS" -o name 2>/dev/null | grep -c . || true)"
check "namespace $NS has a LimitRange" [ "${LR:-0}" -ge 1 ]

# The quota must block self-service public exposure (S-28b).
LB_QUOTA="$(kubectl get resourcequota -n "$NS" \
  -o jsonpath='{.items[0].spec.hard.services\.loadbalancers}' 2>/dev/null || true)"
check "services.loadbalancers quota is 0 (got '${LB_QUOTA:-unset}')" [ "$LB_QUOTA" = "0" ]

NP_QUOTA="$(kubectl get resourcequota -n "$NS" \
  -o jsonpath='{.items[0].spec.hard.services\.nodeports}' 2>/dev/null || true)"
check "services.nodeports quota is 0 (got '${NP_QUOTA:-unset}')" [ "$NP_QUOTA" = "0" ]

# S-28a: created by Terraform (through the Helm release), not a hand-applied
# manifest that the next apply would not restore.
OWNER="$(kubectl get ns "$NS" -o jsonpath='{.metadata.annotations.meta\.helm\.sh/release-name}' 2>/dev/null || true)"
if [ -n "$OWNER" ]; then pass "namespace $NS is owned by Helm release '$OWNER' (Terraform-managed, S-28a)"
else fail "namespace $NS carries no Helm release annotation — it was created outside Terraform"; fi

# ---------------------------------------------------------------------------
# D4. The quota REQUEST is not the quota
# ---------------------------------------------------------------------------
section "D4. EC2 vCPU quotas are actually approved"

# quotas.tf only OPENS an increase request. Approval is asynchronous, so a
# successful apply says nothing about the effective limit. Assert the effective
# value. 104 = nodepool_cpu_limit (100) + the bootstrap group (2 x t4g.medium).
for q in L-1216C47A L-34B43A08; do
  V="$(aws service-quotas get-service-quota --region "$REGION" --service-code ec2 --quota-code "$q" \
    --query 'Quota.Value' --output text 2>/dev/null || true)"
  if [ -z "$V" ] || [ "$V" = "None" ]; then
    fail "could not read quota $q"
  elif awk -v v="$V" -v m="$MIN_VCPU_QUOTA" 'BEGIN{exit !(v+0 >= m+0)}'; then
    pass "quota $q = $V (>= $MIN_VCPU_QUOTA)"
  else
    fail "quota $q is $V — below $MIN_VCPU_QUOTA, the increase is not yet approved (G-02)"
  fi
done

# ---------------------------------------------------------------------------
# E. Spot is actually being used
# ---------------------------------------------------------------------------
section "E. Spot capacity"

# Two distinct failures hide behind "every node is on-demand":
#   - the NodePool never asked for spot            -> a real defect, FAIL
#   - it asked and AWS had no spot capacity        -> environmental, WARN
SPOT_REQUESTED=0
for np in $NODEPOOLS; do
  if kubectl get nodepool "$np" -o json 2>/dev/null \
     | jq -e '.spec.template.spec.requirements[]
              | select(.key=="karpenter.sh/capacity-type")
              | .values[] | select(. == "spot")' >/dev/null 2>&1; then
    SPOT_REQUESTED=1
  fi
done
check "at least one NodePool requests spot capacity" [ "$SPOT_REQUESTED" = "1" ]

SPOT_NODES="$(kubectl get nodes -l karpenter.sh/capacity-type=spot -o name 2>/dev/null | grep -c . || true)"
KARP_NODES="$(kubectl get nodes -l karpenter.sh/nodepool -o name 2>/dev/null | grep -c . || true)"
if [ "${SPOT_NODES:-0}" -ge 1 ]; then
  pass "$SPOT_NODES of ${KARP_NODES:-0} Karpenter node(s) are running on Spot"
elif [ "${KARP_NODES:-0}" -eq 0 ]; then
  warn "no Karpenter nodes are running, so Spot usage could not be observed"
else
  warn "all ${KARP_NODES} Karpenter node(s) are On-Demand — Spot capacity was likely unavailable at launch time (NodePool config is correct, asserted above)"
fi
kubectl get nodes -L kubernetes.io/arch,karpenter.sh/capacity-type,karpenter.sh/nodepool 2>/dev/null | sed 's/^/        /'

# ---------------------------------------------------------------------------
# F. Consolidation returns the cluster to zero Karpenter nodes
# ---------------------------------------------------------------------------
section "F. Consolidation (S-C4)"

if [ "${VERIFY_SKIP_CONSOLIDATION:-0}" = "1" ]; then
  warn "§F skipped (VERIFY_SKIP_CONSOLIDATION=1) — idle-capacity reclamation is NOT verified"
else
  info "removing demo workloads and waiting for Karpenter to consolidate to zero (up to 10m)"
  kubectl delete -f examples/ --ignore-not-found >/dev/null 2>&1 || true

  # consolidateAfter is 5m, so allow that plus the drain and terminate cycle.
  if timeout 600 bash -c 'while kubectl get nodes -l karpenter.sh/nodepool -o name 2>/dev/null | grep -q node; do sleep 20; done'; then
    pass "consolidated to zero Karpenter nodes — idle capacity is reclaimed (S-C4)"
  else
    REMAIN="$(kubectl get nodes -l karpenter.sh/nodepool -o name 2>/dev/null | grep -c . || true)"
    fail "${REMAIN:-?} Karpenter node(s) still running after 10m — consolidation is not reclaiming idle capacity"
  fi
fi

# ---------------------------------------------------------------------------
section "Result"
if [ "$RC" -eq 0 ]; then
  printf '  \033[32mAll assertions passed.\033[0m\n\n'
else
  printf '  \033[31mAt least one assertion FAILED — see above.\033[0m\n\n'
fi
exit $RC
