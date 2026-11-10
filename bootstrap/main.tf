# One-time setup, run from your Mac (the pipeline can't create the identity it logs in with):
#   1. S3 bucket for the EKS Terraform state (versioned, encrypted, private, TLS only)
#   2. Two IAM users the pipeline logs in as (this org's SCP blocks GitHub OIDC providers):
#        github-tf-plan  -> read-only + state access. Keys = repo secrets (PRs and main)
#        github-tf-apply -> can create EKS. Keys = eks-sandbox ENVIRONMENT secrets,
#                           so only an approved apply job can read them
#   Access keys are created with the AWS CLI (see README), so they never land in Terraform state.

terraform {
  required_version = ">= 1.11"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
  # Local state on purpose: this creates the bucket the remote state lives in.
  # Keep bootstrap/terraform.tfstate safe (don't commit it).
}

provider "aws" {
  region              = var.region
  allowed_account_ids = [var.account_id] # refuse to run against any other account

  default_tags {
    tags = {
      Project   = "eks-infra"
      ManagedBy = "terraform-bootstrap"
    }
  }
}

locals {
  state_bucket = "eks-infra-tfstate-${var.account_id}-${var.region}"
}

# ---------- 1. State bucket ----------

resource "aws_s3_bucket" "state" {
  #checkov:skip=CKV_AWS_18:Access logging needs a second log bucket; not worth it for a sandbox state bucket
  #checkov:skip=CKV_AWS_144:Cross-region replication not needed for a sandbox
  #checkov:skip=CKV2_AWS_62:Event notifications not needed for a state bucket
  bucket = local.state_bucket

  lifecycle {
    prevent_destroy = true # losing state = losing track of the cluster
  }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled" # lets you recover an older state file
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms" # AWS-managed key (aws/s3)
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    object_ownership = "BucketOwnerEnforced" # disables ACLs
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    id     = "expire-old-state-versions"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration {
      noncurrent_days = 90
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

data "aws_iam_policy_document" "state_tls_only" {
  statement {
    sid     = "DenyNonTLS"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.state.arn,
      "${aws_s3_bucket.state.arn}/*",
    ]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id
  policy = data.aws_iam_policy_document.state_tls_only.json

  depends_on = [aws_s3_bucket_public_access_block.state]
}

# ---------- 2a. Plan user: read-only + state ----------

resource "aws_iam_user" "plan" {
  #checkov:skip=CKV_AWS_273:SCP blocks GitHub OIDC in this org, so the pipeline needs an IAM user
  name = "github-tf-plan"
  tags = {
    Purpose = "GitHub Actions terraform plan for ${var.github_owner}/${var.github_repo}"
  }
}

resource "aws_iam_user_policy_attachment" "plan_readonly" {
  #checkov:skip=CKV_AWS_40:Policy attached to a single-purpose pipeline user on purpose (no group needed)
  user       = aws_iam_user.plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess" # plan only reads AWS
}

data "aws_iam_policy_document" "state_access" {
  statement {
    sid       = "ListStateBucket"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.state.arn]
  }
  statement {
    sid       = "ReadWriteStateAndLock"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"] # DeleteObject releases the .tflock
    resources = ["${aws_s3_bucket.state.arn}/*"]
  }
}

resource "aws_iam_user_policy" "plan_state" {
  #checkov:skip=CKV_AWS_40:Policy attached to a single-purpose pipeline user on purpose (no group needed)
  name   = "terraform-state"
  user   = aws_iam_user.plan.name
  policy = data.aws_iam_policy_document.state_access.json
}

# ---------- 2b. Apply user: can create EKS ----------

resource "aws_iam_user" "apply" {
  #checkov:skip=CKV_AWS_273:SCP blocks GitHub OIDC in this org, so the pipeline needs an IAM user
  name = "github-tf-apply"
  tags = {
    Purpose = "GitHub Actions terraform apply for ${var.github_owner}/${var.github_repo} - approved environment only"
  }
}

# Sandbox shortcut: the EKS module creates VPCs, IAM roles, KMS keys, log groups,
# launch templates... Scope this down before using the pattern anywhere real.
resource "aws_iam_user_policy_attachment" "apply_admin" {
  #checkov:skip=CKV_AWS_274:Sandbox only; EKS module needs broad rights. Replace with a scoped policy for real use.
  #checkov:skip=CKV_AWS_40:Policy attached to a single-purpose pipeline user on purpose (no group needed)
  user       = aws_iam_user.apply.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
