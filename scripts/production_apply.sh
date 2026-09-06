#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$ROOT/terraform"
TFVARS="${TFVARS:-$TF_DIR/prod.tfvars}"
AWS_PROFILE="${AWS_PROFILE:-status-page}"
AWS_REGION="${AWS_REGION:-il-central-1}"
EXPECTED_ACCOUNT_ID="${EXPECTED_ACCOUNT_ID:-992382545251}"
STATE_BUCKET="${STATE_BUCKET:-yinon-status-page-tfstate-992382545251}"
STATE_KEY="${STATE_KEY:-yinon-status-page/prod/terraform.tfstate}"
CREATE_SERVICES="${CREATE_SERVICES:-true}"
IMAGE_TAG="${IMAGE_TAG:-sha-$(git -C "$ROOT" rev-parse origin/main)}"
export AWS_PROFILE AWS_REGION

case "$CREATE_SERVICES" in true|false) ;; *) echo "CREATE_SERVICES must be true or false" >&2; exit 2 ;; esac
[[ -f "$TFVARS" ]] || { echo "Missing private tfvars: $TFVARS" >&2; exit 2; }
account_id="$(aws --profile "$AWS_PROFILE" sts get-caller-identity --query Account --output text)"
[[ "$account_id" == "$EXPECTED_ACCOUNT_ID" ]] || { echo "Refusing AWS account $account_id" >&2; exit 2; }

plan="$(mktemp /tmp/yinon-status-page-prod-create.tfplan.XXXXXX)"
plan_json="${plan}.json"
trap 'rm -f "$plan" "$plan_json"' EXIT

terraform -chdir="$TF_DIR" init -reconfigure -input=false \
  -backend-config="bucket=$STATE_BUCKET" \
  -backend-config="key=$STATE_KEY" \
  -backend-config="region=$AWS_REGION" \
  -backend-config="encrypt=true" \
  -backend-config="use_lockfile=true"
terraform -chdir="$TF_DIR" fmt -check -recursive
terraform -chdir="$TF_DIR" validate
if command -v tflint >/dev/null 2>&1; then
  tflint --chdir="$TF_DIR" --config=.tflint.hcl --init
  tflint --chdir="$TF_DIR" --config=.tflint.hcl
fi

AWS_PROFILE="$AWS_PROFILE" terraform -chdir="$TF_DIR" plan \
  -input=false -lock-timeout=60s -var-file="$TFVARS" \
  -var="create_services=$CREATE_SERVICES" -var="image_tag=$IMAGE_TAG" \
  -out="$plan"
AWS_PROFILE="$AWS_PROFILE" terraform -chdir="$TF_DIR" show -json "$plan" >"$plan_json"
python3 "$ROOT/scripts/validate_terraform_plan.py" "$plan_json" --mode=create --allow-empty
AWS_PROFILE="$AWS_PROFILE" terraform -chdir="$TF_DIR" apply -input=false "$plan"
