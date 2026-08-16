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

echo "==> 2/6 Deleting NodeClaims so Karpenter drains and terminates its nodes"
kubectl delete nodeclaims --all --wait=true --timeout=15m || true

echo "==> 3/6 Verifying no Karpenter instances remain"
LEFT=$(aws ec2 describe-instances --region "$REGION" \
  --filters "Name=tag:karpenter.sh/managed-by,Values=$CLUSTER" \
            "Name=instance-state-name,Values=running,pending" \
  --query 'Reservations[].Instances[].InstanceId' --output text)
if [ -n "$LEFT" ]; then
  echo "STOP: instances still running: $LEFT"
  echo "Do not proceed — see docs/reference/gotchas.md G-09 and G-10."
  exit 1
fi

echo "==> 4/6 terraform destroy"
terraform destroy -auto-approve

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
| ~54 occurrences of the absolute path `/home/artin/personal/git/dso-projects/terraform` | Someone's home directory in a submitted repo. Replace with `terraform/`-relative paths. |
| References to the sibling `architecture/` assessment (12 files) | Names an unrelated submission. The scope boundary served its purpose during the build; it is noise now. |
| Empty `## Completion report` templates | A form nobody filled in reads as abandoned work. |
| `☐ Not started` status tracker in `docs/README.md` | Ships a to-do list as a deliverable. |

Do one pass over `docs/`:

```bash
# 1. Absolute paths -> relative. Verify nothing else matches first.
grep -rn '/home/artin' docs/ | wc -l
grep -rl '/home/artin' docs/ | xargs sed -i 's|/home/artin/personal/git/dso-projects/terraform|terraform|g'

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

# teardown.sh must delete NodeClaims BEFORE terraform destroy — this ordering
# is the entire point of the script.
awk '/kubectl delete nodeclaims/{n=NR} /terraform destroy/{d=NR} END{
  if (n && d && n < d) print "PASS: correct destroy ordering";
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

*To be filled in by the implementing agent.*

- Status:
- Files created/changed:
- Deviations from spec:
- **Was the stack applied against real AWS? (yes/no)** — and if no, confirm every AUDIT row is
  marked "Implemented, not verified":
- Verification run:
- Outstanding risks:
