# bootstrap/

A standalone root module with **local state**. It creates the S3 bucket + KMS
key the main stack's `backend.tf` (partial config) points at. It cannot store
its own state in the bucket it creates — hence local state, and hence it is a
separate root module rather than part of the main stack.

Applied once per AWS account, by hand, before the main stack's first `terraform
init`. Safe to re-run.

## Usage

```bash
cd terraform/bootstrap
terraform init
terraform apply

# From terraform/, not terraform/bootstrap/:
cd ..
terraform -chdir=bootstrap output -raw backend_config > backend.hcl
# or: cp backend.hcl.example backend.hcl and fill it in from the outputs above

terraform init -backend-config=backend.hcl
```

After this, `bootstrap/` is not touched again unless the account's state
backend itself needs to change (new region, new KMS key, etc).
