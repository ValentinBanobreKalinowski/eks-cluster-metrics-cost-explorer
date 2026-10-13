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
  description = "GitHub repo allowed to assume the CI role, as owner/name"
  type        = string
  default     = "ValentinBanobreKalinowski/eks-cluster-metrics-cost-explorer"
}
