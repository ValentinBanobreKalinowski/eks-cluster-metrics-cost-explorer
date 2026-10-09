#!/usr/bin/env bash

# Just so that terraform picks up DB:
# TF_VAR_postgres_password,
# TF_VAR_postgres_user,
# TF_VAR_postgres_db
# ENV variables instead of 
# having to ask for them everytime in the terminal.

set -euo pipefail # Exit on error, unset variable, or error in pipe
cd "$(dirname "$0")/.." # Change to the script's directory so we can run it from anywhere

# Load .env 
set -a
source .env
set +a

terraform -chdir=terraform "$@"