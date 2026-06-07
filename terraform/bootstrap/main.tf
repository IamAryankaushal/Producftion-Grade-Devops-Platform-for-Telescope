# ============================================================================
# Bootstrap — runs ONCE to create the Terraform remote state backend
# Uses local state intentionally — this is the bootstrapper
# After running: terraform init && terraform apply
# ============================================================================

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  # Local state — intentional, this creates the remote backend
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Project   = "telescope-devops"
      ManagedBy = "terraform"
      Purpose   = "state-backend"
    }
  }
}

# ── S3 bucket for Terraform state ──────────────────────────────────────────
resource "aws_s3_bucket" "tfstate" {
  bucket = "telescope-tfstate-${data.aws_caller_identity.current.account_id}"

  lifecycle {
    prevent_destroy = true
  }

  tags = { Name = "telescope-terraform-state" }
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ── DynamoDB table for state locking ───────────────────────────────────────
resource "aws_dynamodb_table" "tfstate_lock" {
  name         = "telescope-tfstate-lock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  lifecycle {
    prevent_destroy = true
  }

  tags = { Name = "telescope-terraform-state-lock" }
}

data "aws_caller_identity" "current" {}
