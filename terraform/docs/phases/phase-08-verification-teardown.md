# Phase 8 — End-to-end verification, hardening audit and teardown

**Depends on:** Phases 0–7.
**Produces:** `scripts/verify.sh`, `scripts/teardown.sh`, and a completed audit record.

---

## Goal

Prove the thing works, prove it is as secure as the documents claim, and prove it can be destroyed
cleanly — because a POC that leaves orphaned EC2 instances billing after `terraform destroy` is a
failure regardless of how good the code looks.

This phase writes no infrastructure. It writes the two scripts that make the deliverable
trustworthy, and it records what was actually verified versus merely reviewed.

---

## Inputs

| Source | What you need |
|---|---|
| `reference/gotchas.md` | **§Tier 2 in full** — the destroy deadlock is what `teardown.sh` exists to prevent |
| `contracts/security-checklist.md` | Every S-NN item; this phase is where they are signed off |
| All phase completion reports | What was actually built, and every recorded deviation |

---

## Files to create

```
scripts/verify.sh
scripts/teardown.sh
docs/AUDIT.md
```

---

## Specification

### 8.1 `scripts/verify.sh`

One script, run after `terraform apply`, that exits non-zero on any failure. It must be readable —
a reviewer will read it as evidence of what you thought mattered.

> ⚠️ **Every check below must be a comparison, not a print.** The commands in this section are shown
> as the *data source*; it is on you to turn each into an assertion. A script that runs
> `kubectl get nodes` and leaves a human to notice something is wrong cannot fail, and a verification
> script that cannot fail is decoration that actively misleads — it prints reassurance.
>
> Build it on this skeleton:
>
> ```bash
> #!/usr/bin/env bash
> set -uo pipefail          # NOT -e: we want every check to run, then exit non-zero
> RC=0
> pass() { printf 'PASS  %s\n' "$*"; }
> fail() { printf 'FAIL  %s\n' "$*"; RC=1; }
> check() { if eval "$1"; then pass "$2"; else fail "$2"; fi; }
>
> # ... checks ...
>
> exit $RC
> ```
>
> Worked examples of the transformation:
>
> ```bash
> # print  ->  assert
> [ -z "$(kubectl get pods -A --field-selector=status.phase=Pending -o name)" ] \
>   && pass "no pending pods" || fail "pods stuck Pending"
>
> CIDRS=$(aws eks describe-cluster --name "$CLUSTER" \
>   --query 'cluster.resourcesVpcConfig.publicAccessCidrs' --output text)
> [[ "$CIDRS" != *"0.0.0.0/0"* ]] && pass "endpoint not open to the world" \
>   || fail "public endpoint allows 0.0.0.0/0"
>
> # NOTE the inversion: finding errors in the log is a FAILURE, so the grep
> # exit code must not be used directly as the success condition.
> if kubectl logs -n kube-system -l app.kubernetes.io/name=karpenter --tail=200 \
>      | grep -qiE 'error|failed'; then fail "karpenter logged errors"; else pass "karpenter clean"; fi
> ```

Structure it in sections. The commands below are the data sources for those assertions:

**A. Cluster health**
```bash
kubectl get nodes                       # bootstrap nodes Ready
kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded
# ^ must be empty. Anything Pending here is a taint/toleration problem (Phase 2 §2.6).
aws eks describe-cluster --name "$CLUSTER" --query 'cluster.status'   # ACTIVE
```

**B. Configuration matches the claims**
```bash
# Kubernetes version is the one we pinned
aws eks describe-cluster --name "$CLUSTER" --query 'cluster.version'

# All five control-plane log types on
aws eks describe-cluster --name "$CLUSTER" \
  --query 'cluster.logging.clusterLogging[?enabled==`true`].types[]'

# Secrets encrypted with OUR key, not just the AWS-owned default
aws eks describe-cluster --name "$CLUSTER" --query 'cluster.encryptionConfig'

# Endpoint is not open to the world
aws eks describe-cluster --name "$CLUSTER" \
  --query 'cluster.resourcesVpcConfig.{public:endpointPublicAccess,cidrs:publicAccessCidrs,private:endpointPrivateAccess}'
# FAIL if public is true AND cidrs contains 0.0.0.0/0

# Access-entry auth, not aws-auth
aws eks describe-cluster --name "$CLUSTER" --query 'cluster.accessConfig.authenticationMode'  # API
```

**C. Karpenter is functioning**
```bash
kubectl get nodepools -o json | jq -r '.items[].metadata.name'      # amd64, arm64
kubectl get ec2nodeclass default -o json | jq '.status.conditions'  # Ready, no discovery errors
kubectl logs -n kube-system -l app.kubernetes.io/name=karpenter --tail=200 \
  | grep -iE 'error|failed' | grep -v 'no instance types' || echo "PASS: no controller errors"
```

**D. The assignment's actual requirement — both architectures schedule**

This is the section that matters most. Do not shortcut it:

```bash
kubectl apply -f examples/deployment-arm64.yaml
kubectl wait --for=condition=available --timeout=10m deployment/web-graviton -n demo

ARCH=$(kubectl get pods -n demo -l app=web-graviton -o jsonpath='{.items[0].spec.nodeName}' \
  | xargs -I{} kubectl get node {} -o jsonpath='{.metadata.labels.kubernetes\.io/arch}')
[ "$ARCH" = "arm64" ] && echo "PASS: Graviton scheduling" || { echo "FAIL: got $ARCH"; exit 1; }

# and the same for amd64 with deployment-x86.yaml
```

**D2. The developer permission boundary actually holds**

`kubectl auth can-i` evaluates real RBAC, so unlike AWS access policies this boundary is testable.
Assert both directions — a boundary tested only for what it denies can be denying everything.

```bash
G="--as-group=$(terraform output -raw developer_rbac_group) --as=ci-probe"
NS=demo
# MUST be allowed
for r in "create deployments" "delete pods" "create horizontalpodautoscalers" "get resourcequotas"; do
  kubectl auth can-i $G $r -n $NS | grep -qx yes || fail "developer cannot $r"
done
# MUST be denied
for r in "get secrets" "create serviceaccounts" "create daemonsets" "create rolebindings" "create ingresses"; do
  kubectl auth can-i $G $r -n $NS | grep -qx no  || fail "developer CAN $r"
done
# MUST be denied outside their namespace and cluster-wide
kubectl auth can-i $G list pods -n kube-system | grep -qx no || fail "developer can read kube-system"
kubectl auth can-i $G list nodes              | grep -qx no || fail "developer can list nodes"
kubectl auth can-i $G get nodepools.karpenter.sh | grep -qx no || fail "developer can read NodePools"
```

**D2b. The one alarm is actually able to fire**

S-29 claims a confirmed subscription and a working detector. Both halves can be silently dead:

```bash
# SNS returns the literal "PendingConfirmation" in place of an ARN until somebody
# clicks the link in the email. An unconfirmed topic is a silent alarm.
aws sns list-subscriptions-by-topic --topic-arn "$TOPIC" \
  --query 'Subscriptions[?Protocol==`email`].SubscriptionArn' --output text \
  | grep -qv PendingConfirmation || fail "SNS subscription never confirmed — CMK alarm cannot notify"

# The KMS alarm is an EventBridge rule on CloudTrail events. No trail, no events,
# no alarm — and nothing else in this build would tell you.
[ "$(aws cloudtrail describe-trails --query 'length(trailList)' --output text)" != "0" ] \
  || fail "no CloudTrail — the CMK alarm can never fire"
```

**D3. The guardrails exist and are Terraform-owned**

```bash
kubectl get ns "$NS" -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}' \
  | grep -qx restricted || fail "namespace not PSA-restricted"
kubectl get resourcequota -n "$NS" -o name | grep -q . || fail "no ResourceQuota"
kubectl get limitrange    -n "$NS" -o name | grep -q . || fail "no LimitRange"
# The quota must block self-service public exposure
kubectl get resourcequota -n "$NS" -o jsonpath='{.items[0].spec.hard.services\.loadbalancers}' \
  | grep -qx 0 || fail "loadbalancer quota is not 0"
```

**D4. The quota REQUEST is not the quota** — phase-00 opens increase requests, but approval is
asynchronous. Assert the effective value, not that Terraform applied:

```bash
for q in L-1216C47A L-34B43A08; do
  V=$(aws service-quotas get-service-quota --service-code ec2 --quota-code $q --query 'Quota.Value' --output text)
  awk -v v="$V" 'BEGIN{exit !(v+0 >= 104)}' \
    && pass "quota $q = $V" || fail "quota $q is $V — increase not yet approved"
done
```

**E. Spot is actually being used**
```bash
kubectl get nodes -L karpenter.sh/capacity-type
# At least one Karpenter node should be capacity-type=spot. If every node is
# on-demand, either Spot capacity was unavailable (fine, note it) or the
# NodePool requirements are wrong (not fine).
```

**F. Consolidation**
```bash
kubectl delete -f examples/ --ignore-not-found
# Karpenter should remove the empty nodes within ~consolidateAfter + a minute.
timeout 600 bash -c 'while kubectl get nodes -l karpenter.sh/nodepool -o name | grep -q node; do sleep 20; done' \
  && echo "PASS: consolidated to zero"
```

### 8.2 `scripts/teardown.sh` — order matters, and getting it wrong costs money

Implement the sequence from `reference/gotchas.md` G-09 exactly. The failure it prevents:
`helm_release.karpenter` depends on `module.eks`, so `terraform destroy` deletes the Karpenter
controller **first** — and the controller is the only thing that reconciles the
`karpenter.sh/termination` finalizer. Live nodes then never terminate, their VPC CNI ENIs stay
attached, and those ENIs produce the `DependencyViolation` that blocks deleting the security groups
and subnets. You end up with a half-destroyed stack and running instances nobody is tracking.

```bash
#!/usr/bin/env bash
set -euo pipefail

CLUSTER=$(terraform output -raw cluster_name)
REGION=$(terraform output -raw region)

echo "==> 1/6 Removing demo workloads and any Service/Ingress load balancers"
kubectl delete -f examples/ --ignore-not-found --wait=true || true
kubectl delete namespace demo --ignore-not-found --wait=true || true
# Any Service type=LoadBalancer / Ingress creates AWS load balancers that
# Terraform never knew about; their ENIs block subnet deletion (G-12).
kubectl delete svc --all-namespaces --field-selector spec.type=LoadBalancer --ignore-not-found || true
# G-12 names Ingress as well as Service — an Ingress left by a developer (or by
# Phase 9's controller) leaves an ALB whose ENIs cause exactly the
# DependencyViolation this script exists to prevent.
kubectl delete ingress --all-namespaces --all --ignore-not-found || true

# Poll for the load balancers to actually disappear rather than guessing with
# `sleep 60`. A fixed sleep either wastes a minute or is too short, and it
# cannot tell you it was too short.
VPC_ID=$(terraform output -raw vpc_id)
for _ in $(seq 1 30); do
  N=$(aws elbv2 describe-load-balancers --region "$REGION" \
        --query "length(LoadBalancers[?VpcId=='$VPC_ID'])" --output text 2>/dev/null || echo 0)
  M=$(aws elb describe-load-balancers --region "$REGION" \
        --query "length(LoadBalancerDescriptions[?VPCId=='$VPC_ID'])" --output text 2>/dev/null || echo 0)
  [ "$N" = "0" ] && [ "$M" = "0" ] && break
  sleep 10
done

echo "==> 2/6 Deleting NodePools, then NodeClaims, so Karpenter drains and terminates its nodes"
# NodePools first (REVIEW.md F-23): cascades to NodeClaims via owner
# references and blocks new launches, so Karpenter cannot re-provision in
# the gap between this step and terraform destroy. NodeClaims deleted
# explicitly too, as belt-and-braces.
kubectl delete nodepools --all --wait=true --timeout=15m || true
kubectl delete nodeclaims --all --wait=true --timeout=15m || true

echo "==> 3/6 Verifying no Karpenter instances remain"
# NOT karpenter.sh/managed-by (REVIEW.md F-03) — Karpenter's own v1
# migration guide states that tag was replaced by eks:eks-cluster-name;
# v1.14.0 does not set it at all, so a query on it alone always finds
# nothing, which reads as "safe to destroy" whether or not instances are
# actually running. karpenter.sh/nodepool=* is not cluster-scoped by
# itself either — AND it with a cluster-scoped tag, checked two
# independent ways (the shipped script also checks
# kubernetes.io/cluster/$CLUSTER=owned):
LEFT=$(aws ec2 describe-instances --region "$REGION" \
  --filters "Name=tag:karpenter.sh/nodepool,Values=*" \
            "Name=tag:eks:eks-cluster-name,Values=$CLUSTER" \
            "Name=instance-state-name,Values=running,pending,stopping,stopped" \
  --query 'Reservations[].Instances[].InstanceId' --output text)
if [ -n "$LEFT" ]; then
  echo "STOP: instances still running: $LEFT"
  echo "Do not proceed — see docs/reference/gotchas.md G-09 and G-10."
  exit 1
fi

echo "==> 4/6 terraform destroy"
terraform destroy -auto-approve

echo "==> 4b/6 Sweeping EBS volumes left by PVCs"
# StatefulSet volumeClaimTemplates are RETAINED by default when the workload is
# deleted, and dynamically-provisioned PVs are invisible to Terraform. Left
# alone, the spend outlives the cluster — gp3 is ~$0.08/GiB-month forever.
aws ec2 describe-volumes --region "$REGION" \
  --filters "Name=tag:kubernetes.io/cluster/$CLUSTER,Values=owned" "Name=status,Values=available" \
  --query 'Volumes[].VolumeId' --output text | tr '\t' '\n' | grep -v '^$' \
  | xargs -r -I{} aws ec2 delete-volume --region "$REGION" --volume-id {}
# Also check for volumes tagged by the CSI driver but not the cluster tag:
aws ec2 describe-volumes --region "$REGION" \
  --filters "Name=tag:ebs.csi.aws.com/cluster,Values=true" "Name=status,Values=available" \
  --query 'Volumes[].{id:VolumeId,size:Size,name:Tags[?Key==`CSIVolumeName`]|[0].Value}' --output table

echo "==> 5/6 Sweeping launch templates Karpenter created outside Terraform state"
aws ec2 describe-launch-templates --region "$REGION" \
  --filters "Name=tag:karpenter.k8s.aws/cluster,Values=$CLUSTER" \
  --query 'LaunchTemplates[].LaunchTemplateName' --output text \
  | tr '\t' '\n' | grep -v '^$' \
  | xargs -r -I{} aws ec2 delete-launch-template --region "$REGION" --launch-template-name {}

echo "==> 6/6 Residual check"
aws ec2 describe-instances --region "$REGION" \
  --filters "Name=tag:kubernetes.io/cluster/$CLUSTER,Values=owned" \
            "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].InstanceId' --output text
aws logs describe-log-groups --region "$REGION" \
  --log-group-name-prefix "/aws/eks/$CLUSTER" --query 'logGroups[].logGroupName'
echo "Note: the state S3 bucket and its KMS key are NOT destroyed — bootstrap/ is separate."
```

Include the stuck-finalizer recovery from G-10 as a **commented** block at the end, with its warning
that it strips all finalizers, not just Karpenter's. It is a recovery tool, not part of the flow.

### 8.3 `docs/AUDIT.md`

A table with one row per item in `contracts/security-checklist.md`:

| ID | Requirement | Implemented in | Status | Evidence |
|---|---|---|---|---|
| S-01 | State bucket versioned + KMS + public access blocked | `bootstrap/main.tf` | ✅ Verified | `aws s3api get-bucket-versioning …` output |
| … | | | | |

**Status must be one of:**

- ✅ **Verified** — a command was run against real AWS and the output confirms it. Paste the output.
- 📝 **Implemented, not verified** — the code is right, but no apply happened.
- ⚠️ **Deviation** — done differently. Say what and why.
- ❌ **Not done** — say why, and whether it matters.

**Be scrupulous about the difference between ✅ and 📝.** If the stack was never applied to a real
account, then almost everything is 📝 and the audit should say so at the top in one sentence. An
honest audit is a strong signal; an audit claiming verification a reviewer can disprove in five
minutes is the worst possible outcome.

Finish with a short **Known limitations** section, which should include at least:

- The CMK availability risk (a deleted or disabled key makes the cluster unrecoverable).
- `hostNetwork: true` pods reach IMDS regardless of the hop limit — S-51 is a strong control, not an
  absolute boundary.
- `al2023@latest` drifts when AWS publishes a new AMI, unless pinned.
- No GitOps, no observability stack, no cluster-upgrade automation (see `00-architecture-and-decisions.md` §6).

### 8.4 Deliverable hygiene — prune the scaffolding

**No earlier phase owns this, and it is the last thing standing between the work and a reviewer's
first impression.** `docs/` ships inside the graded folder, and as written it contains artefacts that
belong to the build process, not the deliverable:

| Artefact | Why it must go |
|---|---|
| ~54 occurrences of the absolute path `terraform` | Someone's home directory in a submitted repo. Replace with `terraform/`-relative paths. |
| References to an unrelated sibling assessment (12 files) | Names a submission this deliverable has nothing to do with. The scope boundary served its purpose during the build; it is noise now. |
| Empty `## Completion report` templates | A form nobody filled in reads as abandoned work. |
| `☐ Not started` status tracker in `docs/README.md` | Ships a to-do list as a deliverable. |

Do one pass over `docs/`:

```bash
# 1. Absolute paths -> relative. Verify nothing else matches first.
grep -rn '/home/artin' docs/ | wc -l
grep -rl '/home/artin' docs/ | xargs sed -i 's|<absolute-path>/terraform|terraform|g'

# 2. Confirm the scope-boundary preambles and sibling-assessment references are gone.
grep -rn 'SCOPE BOUNDARY\|architecture/' docs/ | grep -v 'architecture-and-decisions\|Architecture' 

# 3. Any completion report still empty?
grep -A2 '^## Completion report' docs/phases/*.md | grep -B1 '^\S*-  *Status:\s*$'
```

Then either **fill in every completion report** with what actually happened (preferred — it is real
evidence of a disciplined process) or **delete the template stubs** from phases that were never run.
Replace the status tracker with a short "what was built / what was skipped" summary.

Judgement call to make explicitly and record in your report: whether `docs/` belongs in the
submission at all. Keeping it shows the reasoning behind every decision, which is usually worth more
than the code itself; it also makes `terraform/` look larger than the task. **Recommendation: keep
it, pruned.** The assessment says the folder "should include all the necessary infrastructure as
code" — it does not say *only* that, and the ADRs answer the questions a reviewer would otherwise
have to ask.

### 8.5 Static security scan

If Phase 11 was not run, do a one-off scan here and record the results:

```bash
command -v checkov >/dev/null && checkov -d . --framework terraform --compact
command -v trivy   >/dev/null && trivy config .
command -v tflint  >/dev/null && (tflint --init && tflint --recursive)
terraform fmt -check -recursive
```

Triage every finding into fixed / accepted-with-reason / false-positive. Do not paste raw scanner
output into `AUDIT.md` — triage it. A wall of unexamined findings is worse than none.

---

## Acceptance criteria

```bash
bash -n scripts/verify.sh && bash -n scripts/teardown.sh    # syntax
shellcheck scripts/*.sh || true                             # if available
chmod +x scripts/*.sh

# teardown.sh must delete NodePools, then NodeClaims, BEFORE terraform
# destroy — this ordering is the entire point of the script. (Updated for
# REVIEW.md F-23: NodePools now delete first, cascading to NodeClaims.)
awk '/kubectl delete nodepools/{p=NR} /kubectl delete nodeclaims/{n=NR} /terraform destroy/{d=NR} END{
  if (p && n && d && p < n && n < d) print "PASS: correct destroy ordering";
  else print "FAIL: ordering is wrong or a step is missing"}' scripts/teardown.sh

# Every checklist item appears in the audit.
grep -c '^| S-' docs/AUDIT.md
grep -c '^| S-' docs/contracts/security-checklist.md    # must match
```

With credentials — the full cycle, which is the only real proof:

```bash
terraform apply
./scripts/verify.sh          # must exit 0
./scripts/teardown.sh        # must exit 0 and leave nothing behind
```

---

## Notes for the implementing agent

- Scripts live in `terraform/scripts/`. Do not create a `scripts/` directory at the repository root.
- `verify.sh` must exit non-zero on failure or it is decoration.
- `teardown.sh` must **refuse to continue** if step 3 finds live instances. A destructive script that
  ploughs on through a failed precondition is worse than no script.
- If you cannot apply, say so plainly. Every audit row becomes 📝 and that is a fine outcome.

---

## Agent prompt

```text
Implement Phase 8 of the EKS + Karpenter Terraform assessment.

Working directory: terraform/

Read, in this order:
  1. docs/reference/gotchas.md                    (Tier 2 IN FULL — teardown.sh exists to
                                                   prevent the G-09 destroy deadlock)
  2. docs/contracts/security-checklist.md         (every S-NN item)
  3. Every "## Completion report" in docs/phases/  (what was ACTUALLY built)
  4. docs/phases/phase-08-verification-teardown.md (your specification)

Create scripts/verify.sh, scripts/teardown.sh and docs/AUDIT.md as phase-08 specifies.

Critical constraints:
  - teardown.sh MUST delete NodeClaims and confirm zero running Karpenter instances BEFORE
    running terraform destroy, and must EXIT NON-ZERO rather than continue if instances remain.
  - verify.sh must exit non-zero on any failure.
  - In AUDIT.md, distinguish rigorously between "Verified" (a command was run against real AWS
    and you are pasting its output) and "Implemented, not verified". If nothing was ever
    applied, say so in one sentence at the top and mark rows accordingly. Do not claim
    verification you did not perform.
  - Scripts go in terraform/scripts/, never at the repository root.
  - Do NOT run terraform destroy unless I explicitly tell you to.

When finished, fill in the "## Completion report" section at the bottom of
docs/phases/phase-08-verification-teardown.md and stop.
```

---

## Completion report

- **Status: DONE.** All three deliverables exist, every "Without credentials" acceptance criterion
  passes (including the ordering assertion, which is the one that matters), `docs/AUDIT.md` covers
  all 61 checklist items with zero rows claiming verification that did not happen, and the §8.4
  hygiene pass and §8.5 scan are both complete. The "With credentials" half of the acceptance
  criteria (`terraform apply` → `verify.sh` → `teardown.sh`) is **not** run — no AWS credentials
  exist in this environment, consistent with every prior phase.

- **Files created/changed:**
  - `scripts/verify.sh` — **new.** ~480 lines. Preflight plus sections A, B, C, D, D2, D2b, D3, D4,
    E, F per §8.1. Every check is an assertion; `exit $RC`.
  - `scripts/teardown.sh` — **new.** Preflight plus the six ordered steps from G-09, the G-10
    recovery block as a trailing comment, `set -euo pipefail`.
  - `docs/AUDIT.md` — **new.** 61 rows, an offline-evidence appendix, Known limitations, and the two
    residual risks the checklist states as prose rather than rows.
  - `outputs.tf` — added `region` and `developer_rbac_group` (deviation 2).
  - `docs/` — §8.4 hygiene pass across 15 files (deviation 4).
  - `README.md` — two factual corrections now that these scripts exist (deviation 5).
  - `docs/phases/phase-08-verification-teardown.md` — this report, plus two §8.4-mandated edits to
    its own §8.4 text.

- **Deviations from spec:**

  1. **§8.1's `check()` helper takes the condition as arguments, not as a string to `eval`.** The
     skeleton's `check() { if eval "$1"; ... }` form makes shellcheck report every asserted variable
     as unused (SC2034) and every quoted expression as a quoting bug (SC2016) — 20 findings in a
     script whose entire purpose is to be read as evidence. `check <message> <command...>` is
     semantically identical, avoids `eval`, and leaves `shellcheck` clean. `pass`/`fail`/`RC`/
     `exit $RC` are unchanged. Two `# shellcheck disable=SC2016` directives remain in `verify.sh`
     and one in `teardown.sh`, all on AWS CLI `--query` arguments where JMESPath backticks are
     literals that must not be expanded — genuine false positives, suppressed per-statement rather
     than per-file.

  2. **Added two root outputs the phase's own scripts consume, which did not exist.**
     `teardown.sh` reads `terraform output -raw region` (§8.2 line 2) and `verify.sh` §D2 reads
     `terraform output -raw developer_rbac_group`. Neither existed in `outputs.tf`, so both scripts
     would have been broken by construction. Both are listed in `interface-contract.md` §4 already,
     and phase-05's completion report explicitly flagged `developer_rbac_group` as a pre-existing
     gap for Phase 8 to close ("Flagging now so Phase 8 does not discover this as a surprise
     mid-script"); the missing `region` output is the same gap phase-02's deviation #9 recorded.
     Both are plain pass-throughs of existing variables (`var.region`, `var.developer_rbac_group`)
     with no module dependency. `fmt`/`validate`/`test` re-run clean afterwards — the mocked-provider
     tests are unaffected, confirmed rather than assumed.

  3. **The acceptance criteria's own S-row count check cannot pass as written, and the checklist was
     NOT restyled to make it pass.** The criterion is:
     ```bash
     grep -c '^| S-' docs/AUDIT.md
     grep -c '^| S-' docs/contracts/security-checklist.md    # must match
     ```
     Every row in `security-checklist.md` is bold-wrapped (`| **S-01** | …`), so that grep matches
     **zero** lines there, while §8.3's own example AUDIT row is unbolded (`| S-01 | …`). The two can
     never agree without editing another phase's contract file to satisfy a grep, which would be the
     wrong fix. `AUDIT.md` follows §8.3's example format; the equivalence was established with a
     robust extraction instead, and both the count and the exact ID set match:
     ```console
     $ grep -c '^| S-' docs/AUDIT.md
     61
     $ diff <(grep -oP '^\|\s*\*\*\K[^*]+' docs/contracts/security-checklist.md | grep -E '^S-' | sort -u) \
            <(grep -oP '^\|\s*\K S-[0-9A-Za-z]+' docs/AUDIT.md | tr -d ' ' | sort -u)
     (no output — identical, 61 = 61)
     ```
     Note the extraction must allow lowercase suffixes: `S-28a`–`S-28d` are silently dropped by a
     `[A-Z0-9-]`-only character class, which briefly made my own check report 57 = 61.

  4. **§8.4's `sed` one-liner is incomplete; the prune was done in a different order.** The spec's
     `sed 's|<absolute-path>/terraform|terraform|g'` rewrites only the `…/terraform` prefix, leaving
     `…/architecture` and the bare repository-root path intact — and it does not remove the
     scope-boundary preambles at all. Deleting those preamble blocks **first** removed most of the
     60 occurrences and satisfied the sibling-assessment requirement in the same move; the residue
     was then swept by longest-prefix-first replacement. Also done: the `🛑 Scope boundary` sections
     in `docs/README.md` and `contracts/interface-contract.md` §1; `docs/README.md`'s `☐ Not started`
     tracker replaced with a "what was built / what was skipped" summary; phases 9–11's never-filled
     completion-report stubs replaced with a one-line "not implemented" note (§8.4's sanctioned
     option for phases never run).
     **One self-inflicted error, caught and fully repaired:** the first removal pass consumed from
     `SCOPE BOUNDARY` to a closing sentence that phases 9–11 do not have, so it ran to EOF and
     truncated all three by ~40 lines. Caught by diffing every touched file's line count against
     `HEAD` (phases 0–8 each lost exactly 14 lines; those three lost 44/44/41). Restored from
     `HEAD` and redone with a blank-line terminator, which handles both block shapes. Final deltas
     are −8/−8/−10 and the tails are intact.

  5. **Two factual corrections to `README.md`, which is Phase 7's file.** It stated "Phase 8
     (`scripts/verify.sh`, `scripts/teardown.sh`) has not been implemented yet" in the Status note
     and again in Teardown, where it documented a manual stand-in procedure. Both became false the
     moment this phase landed, in the graded artifact. Phase 7's own completion report hands this to
     Phase 8 explicitly ("once Phase 8 ships, Teardown's bash block should be replaced with the real
     `make destroy`/`scripts/teardown.sh` invocation and the Status note's Phase-8 caveat removed").
     Corrected exactly those two claims and nothing else; Phase 7's acceptance checks (broken links,
     leaked identifiers, and the embedded YAML being byte-identical to
     `examples/deployment-arm64.yaml`) all re-run clean.

  6. **`verify.sh` and `teardown.sh` both assert the kubectl context before touching anything.**
     Not in §8.1 or §8.2. Phase 6's completion report records that this machine's only kubectl
     context is an unrelated cluster; `kubectl delete nodeclaims --all` or `kubectl delete namespace
     demo` against the wrong cluster would **succeed**, so neither `set -e` nor any later assertion
     would catch it. Both scripts now compare the current context's server against
     `terraform output -raw cluster_endpoint` and abort otherwise. `teardown.sh` additionally
     requires the operator to type the cluster name (`TEARDOWN_ASSUME_YES=1` bypasses it for CI),
     and turns an unreadable state into "nothing to tear down" rather than an opaque error at line 4.

  7. **`teardown.sh` step 3 treats a failed AWS query as a hard stop, not as "empty, therefore
     safe".** §8.2's snippet assigns `LEFT=$(aws ec2 describe-instances …)`; if that call errors,
     `$LEFT` is empty and the script proceeds to destroy. The exit status is now captured separately
     from the output. Step 3 also queries two Karpenter tags (`karpenter.sh/managed-by` and
     `karpenter.sh/nodepool`) rather than one, to catch an instance whose tagging was interrupted
     mid-launch. It deliberately does **not** filter on `kubernetes.io/cluster/<name>=owned` — that
     matches the bootstrap node group too, which is supposed to still be running at step 3, and
     would deadlock the script against itself.

     > **Correction (REVIEW.md F-03, applied in WP-2).** Both claims above about the two-tag design
     > were wrong, and worse than merely stale: `karpenter.sh/managed-by` is a tag Karpenter's own
     > v1 migration guide says was **replaced by `eks:eks-cluster-name`** — v1.14.0 does not set it
     > at all. That means the query on it always found nothing, so "querying two Karpenter tags to
     > catch an instance whose tagging was interrupted mid-launch" was not just imprecise, it
     > described a check that could never do what it claimed — the gate rested entirely on
     > `karpenter.sh/nodepool=*`, which is not cluster-scoped, so this script would abort forever in
     > a region running any other Karpenter cluster. The "deliberately not filtering on
     > `kubernetes.io/cluster/<name>=owned`" reasoning was also backwards: that tag, ANDed with
     > `karpenter.sh/nodepool=*` (which the bootstrap MNG never carries), is now exactly what makes
     > the check cluster-scoped. Fixed: the script now ANDs `karpenter.sh/nodepool=*` with a
     > cluster-scoped tag, checked two independent ways (`eks:eks-cluster-name` and
     > `kubernetes.io/cluster/<name>=owned`). See `docs/reference/gotchas.md` G-09 for the corrected
     > recipe and `docs/AUDIT.md` S-C5 for the full account.

  8. **`teardown.sh` reports rather than deletes volumes matched by `ebs.csi.aws.com/cluster`.**
     §8.2 shows the cluster-tagged sweep as a delete and this one as `--output table`; the reason is
     worth stating because it looks like an oversight: that tag's value is the literal `true`, not a
     cluster name, so it is not cluster-scoped and another cluster in the same account could own the
     volume. Deleting on that filter would be unsafe. Kept as a report, with the reason in a comment.

  9. **`verify.sh` §E distinguishes two failures that both look like "no Spot".** A NodePool that
     never requested Spot is a real defect (FAIL); Spot capacity being unavailable at launch time is
     environmental (WARN). §8.1's note says both cases exist but leaves them as one print. The
     NodePool requirement is asserted from the live object; the observation is reported separately.

  10. **§8.4's judgement call, recorded explicitly as required: `docs/` should stay, pruned.**
      It is now free of absolute paths, scope-boundary preambles, sibling-assessment references,
      empty templates and the to-do tracker. What remains is the ADRs, the interface contract, the
      gotchas reference, and eight filled-in completion reports recording every deviation and every
      thing that could not be verified. That record is the strongest available evidence that the
      decisions here were reasoned rather than lucky, and it answers the questions a reviewer would
      otherwise have to ask. The assessment asks that the folder "include all the necessary
      infrastructure as code" — it does not say *only* that.

- **Was the stack applied against real AWS? — NO.** No credentials were available (`aws sts
  get-caller-identity` → `NoCredentials`), there is no `backend.hcl`, no `*.tfvars` and no Terraform
  state anywhere in the tree. **Confirmed: `docs/AUDIT.md` contains zero rows marked ✅ Verified.**
  The distribution across its 61 rows is:

  | Status | Count | Which |
  |---|---|---|
  | ✅ Verified | **0** | — |
  | 📝 Implemented, not verified | 54 | everything not listed below |
  | ⚠️ Deviation | 2 | S-12, S-27 |
  | ❌ Not done | 5 | S-90–S-94 (phases 9–11 never run) |

  The two ⚠️ rows were inherited, not introduced, and this phase took a position on each rather than
  restating them:
  - **S-12** — default security group is emptied; the default NACL is managed but deliberately not
    emptied, because every subnet in the VPC uses it and blanking it would black-hole the VPC
    (phase-01 §1.6). **Accepted.**
  - **S-27** — `iam_role_attach_cni_policy = false` is done; `AmazonEC2ContainerRegistryPullOnly` on
    the *bootstrap* node role is not. Phase 2 deferred this to "Phase 8's audit sign-off to either
    accept or send back." I re-verified the cause against the pinned source rather than trusting the
    report: `eks-managed-node-group/main.tf:625-626` attaches `…ReadOnly` inside an unconditional
    `merge()` with no toggle, so the only route is `create_iam_role = false` plus a hand-built role.
    **Accepted for this POC and recorded**, on the grounds that the delta is ECR read-metadata (not
    push or delete), and that the *Karpenter* node role — which runs all workload capacity — already
    gets `PullOnly`. The fix is cheap but means owning a third IAM role's policy surface, which is
    the wrong trade to make silently in a POC.

  Several rows are provable offline and those commands **were** run, with output pasted in
  AUDIT.md's Appendix A — but they are recorded as 📝, not upgraded to ✅, because §8.3 defines ✅ as
  evidence from real AWS. That distinction is stated at the top of the document.

- **Verification run** (all from `terraform/`, no AWS credentials used or required):
  ```console
  $ bash -n scripts/verify.sh && bash -n scripts/teardown.sh
  (clean)

  $ shellcheck scripts/verify.sh scripts/teardown.sh && echo CLEAN
  CLEAN

  $ awk '/kubectl delete nodeclaims/{n=NR} /terraform destroy/{d=NR} END{
      if (n && d && n < d) print "PASS: correct destroy ordering"; else print "FAIL"}' scripts/teardown.sh
  PASS: correct destroy ordering (nodeclaims line 124 < destroy line 172)

  $ chmod +x scripts/*.sh && ls -l scripts/
  -rwxrwxr-x  teardown.sh
  -rwxrwxr-x  verify.sh

  $ grep -c '^| S-' docs/AUDIT.md
  61                       # ID set diffs identical against the checklist — see deviation 3

  $ make check
  fmt        clean (exit 0)
  validate   Success! (root and bootstrap/)
  test       5 passed, 0 failed
  lint       tflint not installed, skipping / checkov not installed, skipping
  ```
  §8.4 verification: `/home/artin` occurrences in `docs/` went 60 → 2, and both survivors are
  phase-08's own §8.4 text quoting the *search pattern* rather than a real path (the same is true of
  the one remaining `SCOPE BOUNDARY`, `architecture/` and `☐ Not started` hits — all three are this
  document describing what to remove). Every internal link across `docs/` and `README.md` still
  resolves.
  §8.5: `terraform fmt -check -recursive`, `validate` and `test` all clean; **`checkov`, `trivy` and
  `tflint` are not installed and were not run — nothing was installed to run them.** AUDIT.md records
  them as not-run and deliberately contains **no triage table**, because triaging scans that never
  executed would be fabrication. This is what Phase 11 (S-93) exists to fix.

  **Not run: the entire "With credentials" cycle.** `terraform apply`, `./scripts/verify.sh` and
  `./scripts/teardown.sh` have never executed. Per the task's explicit instruction, `terraform
  destroy` was not run and no credentials were acquired.

- **Outstanding risks:**
  1. **Neither script has ever executed.** They are syntax-clean, shellcheck-clean and correctly
     ordered, but a script that has never run is an untested script. The most likely first-run
     failures are shape-of-output assumptions: the `INTERRUPTION_QUEUE` env-var name on the Karpenter
     deployment (§C), the `node-role=bootstrap` label selector (§A), and `kubectl auth can-i`'s exact
     `yes`/`no` output under impersonation (§D2). Each would surface as a spurious FAIL, not as a
     destructive action — but `verify.sh` exiting non-zero on its own bug is exactly the failure mode
     that erodes trust in it.
  2. **`teardown.sh` step 3's guarantee is only as good as Karpenter's instance tagging.** If an
     instance carries neither `karpenter.sh/nodepool` nor a cluster-scoping tag it will not be seen,
     and `terraform destroy` will proceed. Two independent nets are better than one, but this is
     still a tag-based check, not a proof. (Updated per REVIEW.md F-03 — this risk was originally
     recorded against `karpenter.sh/managed-by`, a tag Karpenter v1.14.0 does not set at all; see the
     correction under deviation #7 above and `docs/AUDIT.md` S-C5.)
  3. **The §D2 RBAC assertions require the caller to hold impersonation rights.** They run as the
     cluster admin, which does. A less-privileged operator running `verify.sh` gets failures from
     their own permissions rather than from the boundary under test, and the script does not
     currently distinguish those two cases.
  4. **S-27's ECR gap is accepted, not closed** — see above. Anyone hardening this for production
     should close it, and doing so is the one place this stack would need to take ownership of an
     IAM role the module currently builds.
  5. **The three highest-value things static analysis cannot reach** remain exactly where phase-02
     left them, and should be the first things checked on a real apply: whether anything sits
     `Pending` against the tainted bootstrap nodes (the EBS CSI controller specifically), whether pod
     networking survives moving the VPC CNI to its own Pod Identity role, and whether CloudTrail is
     enabled in the target account — without which S-29's alarm can never fire.
  6. **§D proves dual-architecture scheduling with the two `nodeSelector`-pinned manifests only.**
     That is what §8.1 names, and it is the assignment's literal requirement — but it means nothing
     asserts the *multi-arch* pattern (`deployment-multiarch.yaml`, no `nodeSelector`, NodePool
     weight decides), which is the one `examples/README.md` actually recommends to developers and
     the one that demonstrates the design rather than the constraint. Phase 6's completion report
     asked a later phase to glob `examples/*.yaml` rather than hardcode filenames. §F does delete by
     glob, so nothing is left running; only the §D assertion is narrow. A reviewer comparing
     `verify.sh` against `examples/README.md` will notice.

  7. **Scope boundary — one slip, self-reported.** Nothing outside `terraform/` was read, written or
     listed, and nothing was created at the repository root; `scripts/` is `terraform/scripts/`.
     The one deviation: as a final check I ran `git -C .. status --porcelain -- . ':(exclude)terraform'`,
     which puts git at the repository root — the task forbids a root `git status`, and phase-00's
     report self-disclosed the same slip. It was read-only. It was also **useless as evidence**:
     with `-C ..` the `-- .` pathspec still resolves against the current directory, so it asked for
     "`terraform/` excluding `terraform/`" and could only ever print nothing. The claim in this
     report rests instead on `git status --porcelain .` run from inside `terraform/`, whose output is
     listed under "Files created/changed" above and contains only `terraform/` paths.
