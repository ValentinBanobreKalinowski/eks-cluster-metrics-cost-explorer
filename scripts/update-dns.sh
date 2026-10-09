#!/usr/bin/env bash

# Points the app's domain at the frontend's LoadBalancer. Run this after
# deploy-eks.sh - the LB's hostname isn't known until the Service exists.

set -euo pipefail # Exit on error, unset variable, or error in pipe
cd "$(dirname "$0")/.." # Change to the script's directory so we can run it from anywhere

REGION=$(terraform -chdir=terraform output -raw region)
CLUSTER_NAME=$(terraform -chdir=terraform output -raw eks_cluster_name)
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$REGION" >/dev/null

ZONE_ID=$(terraform -chdir=terraform output -raw route53_zone_id)
DOMAIN=$(terraform -chdir=terraform output -raw app_hostname)

LB_HOSTNAME=$(kubectl get svc cost-explorer-frontend-service -n frontend -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

if [ -z "$LB_HOSTNAME" ]; then
  echo "Frontend LoadBalancer has no hostname yet, try again in a minute." >&2
  exit 1
fi

aws route53 change-resource-record-sets --hosted-zone-id "$ZONE_ID" --change-batch '{
  "Changes": [{
    "Action": "UPSERT",
    "ResourceRecordSet": {
      "Name": "'"$DOMAIN"'",
      "Type": "CNAME",
      "TTL": 60,
      "ResourceRecords": [{"Value": "'"$LB_HOSTNAME"'"}]
    }
  }]
}'

echo "$DOMAIN now points at $LB_HOSTNAME"
