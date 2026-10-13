variable "region" {
  description = "AWS region to deploy resources - must match the main stack"
  type        = string
  default     = "eu-central-1"
}

variable "state_bucket_name" {
  description = "Globally unique S3 bucket name for the main stack's state - must match the backend block in ../main.tf"
  type        = string
  default     = "valentin-eks-cost-explorer-tfstate"
}

variable "github_repo" {
  description = "GitHub repo allowed to assume the CI role, as owner@owner_id/name@repo_id - GitHub's OIDC sub claim pins the immutable IDs so a renamed or re-created repo with the same name can't assume the role"
  type        = string
  default     = "ValentinBanobreKalinowski@69508847/eks-cluster-metrics-cost-explorer@1286020415"
}
