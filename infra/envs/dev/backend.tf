# Partial backend — bucket/region come from -backend-config at init time.
# Locking uses S3 conditional writes (use_lockfile), no DynamoDB needed.
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
