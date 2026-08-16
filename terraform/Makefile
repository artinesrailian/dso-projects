.DEFAULT_GOAL := help
SHELL := /usr/bin/env bash
TF := terraform

## help: list targets
help:
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/## //' | column -t -s ':'

# ---------- static: no AWS credentials, no cost ----------
## check: everything that can be verified for free
check: fmt validate test lint
## fmt: formatting
fmt:
	$(TF) fmt -check -recursive
## validate: config validity (root and bootstrap)
validate:
	$(TF) init -backend=false && $(TF) validate
	$(TF) -chdir=bootstrap init -backend=false && $(TF) -chdir=bootstrap validate
## test: run terraform test — this is what proves the security guards actually fire
test:
	$(TF) test
## lint: tflint + checkov, if installed
lint:
	@command -v tflint >/dev/null && tflint --recursive || echo "tflint not installed, skipping"
	@command -v checkov >/dev/null && checkov -d . --framework terraform --compact || echo "checkov not installed, skipping"

# ---------- day 0 ----------
## bootstrap: create the S3 + KMS state backend (once per account)
bootstrap:
	$(TF) -chdir=bootstrap init && $(TF) -chdir=bootstrap apply
	@echo "Now: cp backend.hcl.example backend.hcl, fill it from the outputs above, then 'make init'"
## init: initialise with the remote backend
init:
	$(TF) init -backend-config=backend.hcl

# ---------- day 1: staged bring-up ----------
# -target is used deliberately for staged FIRST-TIME bring-up and for isolating
# a failure to one layer. Terraform warns it is for exceptional circumstances —
# this is one. `make apply` afterwards is REQUIRED to converge.
## stage-network: VPC only (~4 min, starts the ~$99/mo NAT meter)
stage-network:
	$(TF) plan -target=module.network -out=tf.plan && $(TF) apply tf.plan
## stage-cluster: + EKS control plane and bootstrap nodes (~15 min)
stage-cluster:
	$(TF) plan -target=module.eks -out=tf.plan && $(TF) apply tf.plan
## stage-karpenter: + Karpenter IAM, SQS and both Helm releases (~3 min)
stage-karpenter:
	$(TF) plan -target=module.karpenter -out=tf.plan && $(TF) apply tf.plan
## plan: full plan, saved to tf.plan
plan:
	$(TF) plan -out=tf.plan
## apply: full apply — converges after any staged/targeted apply
apply:
	$(TF) plan -out=tf.plan && $(TF) apply tf.plan

# ---------- verify and demo ----------
## kubeconfig: point kubectl at the cluster
kubeconfig:
	@eval "$$($(TF) output -raw configure_kubectl)"
## verify: full assertion suite (Phase 8)
verify:
	./scripts/verify.sh
## demo: run the Graviton + x86 demo and report where each pod landed
demo:
	kubectl apply -f examples/deployment-arm64.yaml -f examples/deployment-x86.yaml
	kubectl wait --for=condition=available --timeout=10m deployment/web-graviton deployment/web-x86 -n demo
	kubectl get pods -n demo -o wide
	kubectl get nodes -L kubernetes.io/arch,karpenter.sh/capacity-type,node.kubernetes.io/instance-type
## demo-clean: remove the demo workloads and let Karpenter consolidate
demo-clean:
	kubectl delete -f examples/ --ignore-not-found

# ---------- teardown ----------
## destroy: ORDERED teardown. Never use a bare `terraform destroy` — see gotchas G-09.
destroy:
	@test -x scripts/teardown.sh || { echo "scripts/teardown.sh does not exist yet (it ships in Phase 8)."; \
		echo "Refusing to fall back to a bare 'terraform destroy' — see docs/reference/gotchas.md G-09."; exit 1; }
	./scripts/teardown.sh

.PHONY: help check fmt validate test lint bootstrap init stage-network stage-cluster \
        stage-karpenter plan apply kubeconfig verify demo demo-clean destroy
