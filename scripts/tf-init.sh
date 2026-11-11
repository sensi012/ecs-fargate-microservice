#!/usr/bin/env bash
set -euo pipefail

ENV_NAME=${1:?Usage: ./scripts/tf-init.sh dev|staging}

: "${PROJECT:?PROJECT environment variable must be set}"
: "${AWS_REGION:?AWS_REGION environment variable must be set}"
: "${ACCOUNT_ID:?ACCOUNT_ID environment variable must be set}"

BUCKET="${PROJECT}-tfstate-${ACCOUNT_ID}"
TABLE="${PROJECT}-terraform-locks"

cd "$(dirname "$0")/../terraform"

terraform init -input=false -reconfigure \
  -backend-config="bucket=${BUCKET}" \
  -backend-config="key=${PROJECT}/${ENV_NAME}.tfstate" \
  -backend-config="region=${AWS_REGION}" \
  -backend-config="dynamodb_table=${TABLE}" \
  -backend-config="encrypt=true"