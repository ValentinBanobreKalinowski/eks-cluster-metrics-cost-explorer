#!/usr/bin/env bash

# Deploy the AWS infra as well as the helm chart after that.

set -euo pipefail # Exit on error, unset variable, or error in pipe
cd "$(dirname "$0")/.." # Change to the script's directory so we can run it from anywhere

./scripts/tf.sh apply
./scripts/deploy-eks.sh
