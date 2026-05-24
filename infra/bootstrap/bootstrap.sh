#!/usr/bin/env bash
# Create (or recreate) the S3 bucket that holds Terraform state for this repo.
#
# Idempotent: safe to run multiple times. The script enables versioning, SSE-S3
# encryption, and blocks all public access.
#
# Usage: bootstrap.sh <bucket-name> <region>
# Example: bootstrap.sh sample-eks-microservice-tfstate us-east-1
#
# After it succeeds, drop these into envs/dev/backend.tfvars (or pass on the
# command line) so terraform init can find the bucket:
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
  if grep -qE 'BucketAlreadyOwnedByYou|BucketAlreadyExists' /tmp/bootstrap.err; then
    echo "   bucket already exists, continuing"
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
