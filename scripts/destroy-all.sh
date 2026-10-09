#!/usr/bin/env bash

# Destroy the cluster load balancer that isn't tracked by terraform,
# and after that run terraform destroy.

set -euo pipefail # Exit on error, unset variable, or error in pipe
cd "$(dirname "$0")/.." # Change to the script's directory so we can run it from anywhere

./scripts/destroy-elb.sh
./scripts/destroy-stuck-nodes.sh
./scripts/tf.sh destroy