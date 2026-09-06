#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
"$ROOT/scripts/validate_production_source.sh"
TF_DIR="$ROOT/terraform"
TFVARS="${TFVARS:-$TF_DIR/prod.tfvars}"
AWS_PROFILE="${AWS_PROFILE:-status-page}"
AWS_REGION="${AWS_REGION:-il-central-1}"
EXPECTED_ACCOUNT_ID="${EXPECTED_ACCOUNT_ID:-992382545251}"
STATE_BUCKET="${STATE_BUCKET:-yinon-status-page-tfstate-992382545251}"
STATE_KEY="${STATE_KEY:-yinon-status-page/prod/terraform.tfstate}"
EXPECTED_CONFIRMATION="yinon-status-page-prod"
export AWS_PROFILE AWS_REGION

[[ "${CONFIRM_DESTROY:-}" == "$EXPECTED_CONFIRMATION" ]] || {
  echo "Set CONFIRM_DESTROY=$EXPECTED_CONFIRMATION to authorize the scoped teardown." >&2
  exit 2
}
[[ -f "$TFVARS" ]] || { echo "Missing private tfvars: $TFVARS" >&2; exit 2; }
account_id="$(aws --profile "$AWS_PROFILE" sts get-caller-identity --query Account --output text)"
[[ "$account_id" == "$EXPECTED_ACCOUNT_ID" ]] || { echo "Refusing AWS account $account_id" >&2; exit 2; }
command -v gh >/dev/null 2>&1 || { echo "gh is required to pause production before destroy." >&2; exit 2; }
gh variable set PRODUCTION_ENABLED --repo "${GITHUB_REPOSITORY:-yinon-mitin/Status-Page}" --body false

cleanup_task_definitions() {
  for family in \
    yinon-status-page-prod-web \
    yinon-status-page-prod-worker \
    yinon-status-page-prod-scheduler; do
    active="$(aws ecs list-task-definitions --region "$AWS_REGION" \
      --family-prefix "$family" --status ACTIVE --query 'taskDefinitionArns[]' --output text)"
    [[ "$active" == "None" ]] && active=""
    for arn in $active; do
      family_revision="${arn##*/}"
      [[ "${family_revision%:*}" == "$family" ]] || {
        echo "Refusing unexpected task definition family: $family_revision" >&2
        exit 1
      }
      aws ecs deregister-task-definition --region "$AWS_REGION" --task-definition "$arn" >/dev/null
    done

    inactive="$(aws ecs list-task-definitions --region "$AWS_REGION" \
      --family-prefix "$family" --status INACTIVE --query 'taskDefinitionArns[]' --output text)"
    [[ "$inactive" == "None" ]] && inactive=""
    for arn in $inactive; do
      family_revision="${arn##*/}"
      [[ "${family_revision%:*}" == "$family" ]] || {
        echo "Refusing unexpected task definition family: $family_revision" >&2
        exit 1
      }
      aws ecs delete-task-definitions --region "$AWS_REGION" --task-definitions "$arn" >/dev/null
    done
  done
}

terraform -chdir="$TF_DIR" init -reconfigure -input=false \
  -backend-config="bucket=$STATE_BUCKET" \
  -backend-config="key=$STATE_KEY" \
  -backend-config="region=$AWS_REGION" \
  -backend-config="encrypt=true" \
  -backend-config="use_lockfile=true"

state_resources="$(AWS_PROFILE="$AWS_PROFILE" terraform -chdir="$TF_DIR" state list)"
if [[ -z "$state_resources" ]]; then
  cleanup_task_definitions
  echo "Production Terraform state is already empty; task-definition cleanup complete."
  exit 0
fi

snapshot_id="yinon-status-page-prod-postgres-final-$(date -u +%Y%m%d%H%M%S)"
prepare_plan="$(mktemp /tmp/yinon-status-page-prod-prepare-destroy.tfplan.XXXXXX)"
prepare_json="${prepare_plan}.json"
destroy_plan="$(mktemp /tmp/yinon-status-page-prod-destroy.tfplan.XXXXXX)"
destroy_json="${destroy_plan}.json"
trap 'rm -f "$prepare_plan" "$prepare_json" "$destroy_plan" "$destroy_json"' EXIT

common_vars=(
  -var-file="$TFVARS"
  -var="teardown_mode=true"
  -var="final_snapshot_identifier=$snapshot_id"
)
targets=(
  -target='aws_db_instance.postgres[0]'
  -target='aws_lb.web[0]'
  -target='aws_ecr_repository.app'
  -target='aws_ecr_repository.nginx'
)

AWS_PROFILE="$AWS_PROFILE" terraform -chdir="$TF_DIR" plan \
  -input=false -lock-timeout=60s "${common_vars[@]}" "${targets[@]}" \
  -out="$prepare_plan"
AWS_PROFILE="$AWS_PROFILE" terraform -chdir="$TF_DIR" show -json "$prepare_plan" >"$prepare_json"
python3 "$ROOT/scripts/validate_terraform_plan.py" "$prepare_json" --mode=prepare-destroy --allow-empty
AWS_PROFILE="$AWS_PROFILE" terraform -chdir="$TF_DIR" apply -input=false "$prepare_plan"

AWS_PROFILE="$AWS_PROFILE" terraform -chdir="$TF_DIR" plan -destroy \
  -input=false -lock-timeout=60s "${common_vars[@]}" -out="$destroy_plan"
AWS_PROFILE="$AWS_PROFILE" terraform -chdir="$TF_DIR" show -json "$destroy_plan" >"$destroy_json"
python3 "$ROOT/scripts/validate_terraform_plan.py" "$destroy_json" --mode=destroy
AWS_PROFILE="$AWS_PROFILE" terraform -chdir="$TF_DIR" apply -input=false "$destroy_plan"

remaining="$(AWS_PROFILE="$AWS_PROFILE" terraform -chdir="$TF_DIR" state list)"
[[ -z "$remaining" ]] || { echo "Terraform state is not empty after destroy" >&2; printf '%s\n' "$remaining" >&2; exit 1; }
cleanup_task_definitions
echo "Destroy complete; final RDS snapshot: $snapshot_id"
