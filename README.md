
# Terraform + Azure DevOps + AWS OIDC (Bundle)

This bundle contains a ready-to-use Azure Pipeline with TFLint and Checkov gates, plus a bootstrap script to create the S3 backend (and optional DynamoDB lock table).

## Contents
- `azure-pipelines.yml` – Full pipeline: TFLint → Checkov (code + plan) → Plan → Apply
- `.tflint.hcl` – TFLint configuration with Terraform and AWS rulesets
- `.checkov.yaml` – Checkov defaults (Terraform + Terraform Plan frameworks)
- `bootstrap-terraform-backend.sh` – One-shot script to create S3 bucket, encryption, versioning, block public access, and optional DynamoDB lock table

## Quick start
1. **Backend** – Run the bootstrap script once (pick KMS or AES256):
   ```bash
   chmod +x bootstrap-terraform-backend.sh
   ./bootstrap-terraform-backend.sh --bucket org-tfstate-eu-west-2 --region eu-west-2 --dynamodb-table terraform-locks
   # or (Terraform >= 1.10) skip DynamoDB and use S3 native lockfile
   ./bootstrap-terraform-backend.sh --bucket org-tfstate-eu-west-2 --region eu-west-2 --skip-dynamodb
   ```
2. **Pipeline prerequisites**
   - Install the **AWS Toolkit for Azure DevOps** extension (provides `AWSShellScript@1`).
   - Create an **AWS** service connection and check **Use OIDC**.
   - Configure an **AWS IAM OIDC provider** with issuer `https://vstoken.dev.azure.com/{OrgGUID}`, audience `api://AzureADTokenExchange`, and trust policy limiting `sub` to your service connection (format: `sc://Org/Project/ServiceConnection`).
3. **Commit** the files to your repo root and adjust variables in `azure-pipelines.yml`:
   - `service_connection`, `aws_region`, `env_name`, and backend bucket/table names.
4. **Create** the environment folder (e.g., `envs/dev/`) with your Terraform code and backend snippet printed by the bootstrap script.

## Notes
- Checkov is run twice: a soft-fail code scan and an enforced plan scan (`terraform show -json ... | checkov -f`).
- TFLint fails the build if any issues are found (`--error-with-issues`).
- The "Plan" and "Apply" stages are examples; keep your existing approval gates.
