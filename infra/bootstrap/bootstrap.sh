#!/usr/bin/env bash
# Creates the S3 bucket that holds Terraform state. Idempotent — sets
# versioning + SSE-S3 + public-access-block.
#
# Usage: bootstrap.sh <bucket-name> <region>
# Example: bootstrap.sh sample-eks-microservice-tfstate us-east-1
#
# Pass the bucket/region into `terraform init` via -backend-config, or drop
# them in envs/dev/backend.tfvars:
#   bucket = "<bucket-name>"
#   region = "<region>"
#   key    = "envs/dev/terraform.tfstate"

set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <bucket-name> <region>" >&2
  exit 64
fi

bucket="$1"
region="$2"

if ! command -v aws >/dev/null 2>&1; then
  echo "aws CLI not found on PATH" >&2
  exit 127
fi

# Create the bucket. us-east-1 is the only region that rejects an explicit
# LocationConstraint, so branch on it.
create_bucket() {
  if [[ "$region" == "us-east-1" ]]; then
    aws s3api create-bucket --bucket "$bucket" --region "$region"
  else
    aws s3api create-bucket \
      --bucket "$bucket" \
      --region "$region" \
      --create-bucket-configuration "LocationConstraint=$region"
  fi
}

echo ">> ensuring bucket $bucket exists in $region"
if ! create_bucket 2>/tmp/bootstrap.err; then
  if grep -q 'BucketAlreadyOwnedByYou' /tmp/bootstrap.err; then
    echo "   bucket already owned by this account, continuing"
  elif grep -q 'BucketAlreadyExists' /tmp/bootstrap.err; then
    echo "   bucket name '$bucket' is already taken globally by another account." >&2
    echo "   pick a different name (e.g. include the AWS account id)." >&2
    exit 1
  else
    cat /tmp/bootstrap.err >&2
    exit 1
  fi
fi

echo ">> enabling versioning"
aws s3api put-bucket-versioning \
  --bucket "$bucket" \
  --versioning-configuration Status=Enabled

echo ">> enabling SSE-S3 encryption"
aws s3api put-bucket-encryption \
  --bucket "$bucket" \
  --server-side-encryption-configuration '{
    "Rules": [
      {
        "ApplyServerSideEncryptionByDefault": { "SSEAlgorithm": "AES256" },
        "BucketKeyEnabled": true
      }
    ]
  }'

echo ">> blocking public access"
aws s3api put-public-access-block \
  --bucket "$bucket" \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

cat <<EOF

State backend ready.

  bucket: $bucket
  region: $region

Use these values with terraform init:

  terraform -chdir=infra/envs/dev init \\
    -backend-config="bucket=$bucket" \\
    -backend-config="region=$region" \\
    -backend-config="key=envs/dev/terraform.tfstate"
EOF
