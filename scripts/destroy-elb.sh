#!/usr/bin/env bash

# The frontend Service is type=LoadBalancer on EKS, so AWS provisions a
# classic ELB for it outside of Terraform (no aws_lb resource tracks it).
# Its ENIs stay attached to the VPC's subnets/security groups until the ELB
# is deleted, which blocks terraform destroy. This script deletes the ELB
# first, then we can run terraform destroy.

set -euo pipefail # Exit on error, unset variable, or error in pipe
cd "$(dirname "$0")/.." # Change to the script's directory so we can run it from anywhere

REGION=$(terraform -chdir=terraform output -raw region)
CLUSTER_NAME=$(terraform -chdir=terraform output -raw eks_cluster_name)

aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$REGION" >/dev/null

if ! kubectl get svc cost-explorer-frontend-service -n frontend >/dev/null 2>&1; then
  echo "No frontend LoadBalancer service found, nothing to clean up."
  exit 0
fi

echo "Deleting frontend LoadBalancer service (blocks until AWS finishes tearing down the ELB)..."
kubectl delete svc cost-explorer-frontend-service -n frontend --timeout=5m
