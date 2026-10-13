# Long-lived resources that must outlive the cluster: destroy-all.sh tears down
# the main stack, but its state, the images, and GitHub Actions' role must
# survive it. Applied once, then left running (near-zero cost).
#
# This stack's own state stays local (gitignored) - it can't live in the
# bucket it creates.

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.region
}

# Remote state for the main stack

resource "aws_s3_bucket" "tfstate" {
  bucket = var.state_bucket_name

  # Losing this bucket means Terraform forgets everything it created
  lifecycle {
    prevent_destroy = true
  }
}

# Every apply writes a new state version - lets us roll back a corrupted state
resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled"
  }
}

# State holds secrets (e.g. the RDS master password)
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

# ECR - moved here from the main stack so images survive destroy-all.sh

resource "aws_ecr_repository" "backend" {
  name                 = "cost-explorer-backend"
  image_tag_mutability = "MUTABLE" # Skaffold re-pushes the same tag on local deploys
  force_delete         = true
}

resource "aws_ecr_repository" "frontend" {
  name                 = "cost-explorer-frontend"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
}

# Every merge to main pushes new images - keep only the most recent so storage doesn't grow forever
resource "aws_ecr_lifecycle_policy" "keep_recent" {
  for_each   = { backend = aws_ecr_repository.backend.name, frontend = aws_ecr_repository.frontend.name }
  repository = each.value

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the 10 most recent images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}

# GitHub Actions -> AWS via OIDC: same idea as IRSA for the backend pod.
# Each workflow run gets short-lived credentials, so no access keys live in GitHub.

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_policy_document" "github_actions_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Only workflow runs on main of this repo - not PRs, forks or other branches
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:ref:refs/heads/main"]
    }
  }
}

resource "aws_iam_role" "github_actions_ecr_push" {
  name               = "github-actions-ecr-push"
  assume_role_policy = data.aws_iam_policy_document.github_actions_assume_role.json
}

data "aws_iam_policy_document" "ecr_push" {
  # GetAuthorizationToken has no resource-level scoping - "*" is the only valid resource
  statement {
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = [
      aws_ecr_repository.backend.arn,
      aws_ecr_repository.frontend.arn,
    ]
  }
}

resource "aws_iam_role_policy" "ecr_push" {
  name   = "ecr-push"
  role   = aws_iam_role.github_actions_ecr_push.id
  policy = data.aws_iam_policy_document.ecr_push.json
}
