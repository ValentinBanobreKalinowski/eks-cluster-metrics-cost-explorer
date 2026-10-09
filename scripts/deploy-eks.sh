#!/usr/bin/env bash

# The script deploys the app to EKS. We first need to run terraform apply of course to provision the infrastructure. 

set -euo pipefail # Exit on error, unset variable, or error in pipe
cd "$(dirname "$0")/.." # Change to the script's directory so we can run it from anywhere

REGION=$(terraform -chdir=terraform output -raw region) # Get the region from terraform output
export REGION # So that Skaffold can pick it up.

CLUSTER_NAME=$(terraform -chdir=terraform output -raw eks_cluster_name) # Get the cluster name from terraform output
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$REGION" # Point kubectl/skaffold at the current cluster (its endpoint changes every time it's recreated)

POSTGRES_HOST=$(terraform -chdir=terraform output -raw rds_address) # Get the RDS address from terraform output
export POSTGRES_HOST # Export the RDS address so that the app can connect to it

S3_REPORTS_BUCKET=$(terraform -chdir=terraform output -raw s3_reports_bucket) # Get the buckets name
export S3_REPORTS_BUCKET # Export so that Skaffold can pick it up

FRONTEND_CERT_ARN=$(terraform -chdir=terraform output -raw acm_certificate_arn) # Validated ACM cert from the route53 module
export FRONTEND_CERT_ARN # Export so that Skaffold can attach it to the frontend NLB's 443 listener

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text) # Get the AWS account ID
ECR_REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com" # Construct the ECR registry URL

aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$ECR_REGISTRY" # Login to ECR

# Set environment variables from .env file
set -a
source .env
set +a

# On EKS the backend connects as the IAM-auth DB role, not the master user from .env (RDS doesn't allow IAM auth for the master user)
POSTGRES_USER=$(terraform -chdir=terraform output -raw postgres_app_username)
export POSTGRES_USER

# Build and push the Docker images to ECR, then deploy to EKS using Skaffold
echo "Deploying to EKS cluster '$CLUSTER_NAME' in region '$REGION'..."
skaffold run -p eks --default-repo="$ECR_REGISTRY"

# Run ./scripts/update-dns.sh afterwards to point the domain at the frontend's LB.
