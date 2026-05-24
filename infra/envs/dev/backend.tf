# Partial backend config. The bucket and region are passed at init time so the
# same code works against any pre-bootstrapped state bucket. Locking uses S3's
# native conditional writes (use_lockfile) — no DynamoDB table required.
#
# terraform -chdir=infra/envs/dev init \
#   -backend-config="bucket=<bucket>" \
#   -backend-config="region=<region>" \
#   -backend-config="key=envs/dev/terraform.tfstate"

terraform {
  backend "s3" {
    key          = "envs/dev/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}
