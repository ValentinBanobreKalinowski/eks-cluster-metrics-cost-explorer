#!/usr/bin/env bash

# A node can end up NotReady before terraform destroy runs. When that
# happens its pods get stuck in Terminating (kubelet never confirms they're
# gone), which blocks the kubernetes_namespace.* resources from finishing
# their destroy. Terraform then hits a "context deadline exceeded" waiting
# on the namespaces, so it never reaches the EKS node group/cluster destroy
# step - meaning the node's EC2 instance (and its mapped public IP) stays
# alive, which makes aws_internet_gateway.this fail to detach with
# DependencyViolation.
#
# Deleting a NotReady node's object garbage-collects the pods bound to it,
# letting namespaces terminate normally, so this runs before terraform
# destroy to avoid the whole cascade.

set -euo pipefail
cd "$(dirname "$0")/.." # Change to the script's directory so we can run it from anywhere

REGION=$(terraform -chdir=terraform output -raw region)
CLUSTER_NAME=$(terraform -chdir=terraform output -raw eks_cluster_name)

aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$REGION" >/dev/null

NOT_READY_NODES=$(kubectl get nodes --no-headers 2>/dev/null | awk '$2 != "Ready" {print $1}')

if [ -z "$NOT_READY_NODES" ]; then
  echo "No NotReady nodes found, nothing to clean up."
  exit 0
fi

echo "Found NotReady node(s), deleting so their pods get garbage-collected:"
while read -r NODE; do
  echo "  - $NODE"
  kubectl delete node "$NODE" --grace-period=0 --force
done <<< "$NOT_READY_NODES"
