
#!/usr/bin/env bash
# Bootstrap Terraform backend on AWS: S3 bucket (+versioning, encryption, public access block)
# and optional DynamoDB table for state locking (legacy). See README for details.
set -euo pipefail

REGION=""
BUCKET=""
DDB_TABLE=""
KMS_KEY_ID=""
PROFILE_OPTS=()
SKIP_DDB=0

usage(){
  cat <<USAGE
Usage:
  $0 --bucket <name> --region <aws-region> [--dynamodb-table <name>] [--kms-key-id <arn>] [--profile <p>] [--skip-dynamodb]
Examples:
  $0 --bucket org-tfstate-eu-west-2 --region eu-west-2 --dynamodb-table terraform-locks
  $0 --bucket org-tfstate-eu-west-2 --region eu-west-2 --skip-dynamodb    # Terraform >= 1.10 use_lockfile
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bucket) BUCKET="$2"; shift 2;;
    --region) REGION="$2"; shift 2;;
    --dynamodb-table) DDB_TABLE="$2"; shift 2;;
    --kms-key-id) KMS_KEY_ID="$2"; shift 2;;
    --profile) PROFILE_OPTS+=(--profile "$2"); shift 2;;
    --skip-dynamodb) SKIP_DDB=1; shift;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1"; usage; exit 2;;
  esac
done

if [[ -z "$BUCKET" || -z "$REGION" ]]; then
  echo "ERROR: --bucket and --region are required." >&2; exit 2
fi
if [[ $SKIP_DDB -eq 0 && -z "$DDB_TABLE" ]]; then
  echo "ERROR: --dynamodb-table is required unless --skip-dynamodb is set." >&2; exit 2
fi

echo "==> Creating S3 bucket: $BUCKET in $REGION"
if [[ "$REGION" == "us-east-1" ]]; then
  aws "${PROFILE_OPTS[@]}" s3api create-bucket --bucket "$BUCKET" --region "$REGION" >/dev/null 2>&1 || true
else
  aws "${PROFILE_OPTS[@]}" s3api create-bucket --bucket "$BUCKET"     --region "$REGION"     --create-bucket-configuration LocationConstraint="$REGION" >/dev/null 2>&1 || true
fi

echo "==> Enabling bucket versioning"
aws "${PROFILE_OPTS[@]}" s3api put-bucket-versioning --bucket "$BUCKET" --versioning-configuration Status=Enabled >/dev/null

echo "==> Enabling default server-side encryption"
if [[ -n "$KMS_KEY_ID" ]]; then
  ENC_CFG='{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"aws:kms","KMSMasterKeyID":"'"$KMS_KEY_ID"'"}}]}'
else
  ENC_CFG='{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
fi
aws "${PROFILE_OPTS[@]}" s3api put-bucket-encryption --bucket "$BUCKET" --server-side-encryption-configuration "$ENC_CFG" >/dev/null

echo "==> Blocking all public access on the bucket"
aws "${PROFILE_OPTS[@]}" s3api put-public-access-block   --bucket "$BUCKET"   --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true >/dev/null

if [[ $SKIP_DDB -eq 0 ]]; then
  echo "==> Creating DynamoDB table for state locking: $DDB_TABLE"
  aws "${PROFILE_OPTS[@]}" dynamodb create-table     --table-name "$DDB_TABLE"     --attribute-definitions AttributeName=LockID,AttributeType=S     --key-schema AttributeName=LockID,KeyType=HASH     --billing-mode PAY_PER_REQUEST     --region "$REGION" >/dev/null 2>&1 || true
  echo "=> DynamoDB lock table created (or already exists)"
fi

cat <<EOF

Bootstrap complete. Example backend config (choose one):

# (A) S3 + DynamoDB locking (legacy/compatible)
terraform {
  backend "s3" {
    bucket         = "$BUCKET"
    key            = "envs/dev/terraform.tfstate"
    region         = "$REGION"
    dynamodb_table = "$DDB_TABLE"
    encrypt        = true
  }
}

# (B) S3 native locking (Terraform >= 1.10)
terraform {
  backend "s3" {
    bucket       = "$BUCKET"
    key          = "envs/dev/terraform.tfstate"
    region       = "$REGION"
    use_lockfile = true
    encrypt      = true
  }
}

Then run: terraform init -reconfigure
EOF
