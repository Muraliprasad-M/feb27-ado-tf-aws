terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  backend "s3" {}
}

provider "aws" {
  region = var.aws_region
}

# Simple S3 bucket for testing
resource "aws_s3_bucket" "test" {
  bucket = "ado-terraform-test-${var.environment}-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name        = "ADO Terraform Test"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_s3_bucket_versioning" "test" {
  bucket = aws_s3_bucket.test.id

  versioning_configuration {
    status = "Enabled"
  }
}

data "aws_caller_identity" "current" {}
