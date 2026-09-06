#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
"$ROOT/scripts/validate_production_source.sh"
AWS_PROFILE="${AWS_PROFILE:-status-page}"
AWS_REGION="${AWS_REGION:-il-central-1}"
EXPECTED_ACCOUNT_ID="992382545251"
REPOSITORY="${GITHUB_REPOSITORY:-yinon-mitin/Status-Page}"
CLUSTER="yinon-status-page-prod"
SOURCE_FAMILY="yinon-status-page-prod-worker"
ONEOFF_FAMILY="yinon-status-page-prod-migration"
sha="$(git -C "$ROOT" rev-parse origin/main)"
IMAGE_TAG="${IMAGE_TAG:-sha-$sha}"

[[ "$IMAGE_TAG" == "sha-$sha" ]] || {
  echo "Migration image must match exact origin/main SHA: sha-$sha" >&2
  exit 2
}
[[ "${CONFIRM_MIGRATION:-}" == "$sha" ]] || {
  echo "Set CONFIRM_MIGRATION=$sha for this exact migration revision." >&2
  exit 2
}
account_id="$(AWS_PROFILE="$AWS_PROFILE" aws sts get-caller-identity --query Account --output text)"
[[ "$account_id" == "$EXPECTED_ACCOUNT_ID" ]] || {
  echo "Refusing migration in AWS account $account_id" >&2
  exit 2
}

app_image="$account_id.dkr.ecr.$AWS_REGION.amazonaws.com/yinon-status-page-prod-app:$IMAGE_TAG"
tmp_dir="$(mktemp -d /tmp/yinon-status-page-migration.XXXXXX)"
registered_arn=""
cleanup() {
  status=$?
  trap - EXIT
  if [[ -n "$registered_arn" ]]; then
    AWS_PROFILE="$AWS_PROFILE" aws ecs deregister-task-definition --region "$AWS_REGION" \
      --task-definition "$registered_arn" >/dev/null 2>&1 || true
    AWS_PROFILE="$AWS_PROFILE" aws ecs delete-task-definitions --region "$AWS_REGION" \
      --task-definitions "$registered_arn" >/dev/null 2>&1 || true
  fi
  rm -rf "$tmp_dir"
  exit "$status"
}
trap cleanup EXIT

AWS_PROFILE="$AWS_PROFILE" aws ecs describe-task-definition --region "$AWS_REGION" \
  --task-definition "$SOURCE_FAMILY" >"$tmp_dir/source.json"
python3 "$ROOT/scripts/build_oneoff_task_definition.py" \
  "$tmp_dir/source.json" "$tmp_dir/register.json" \
  --family "$ONEOFF_FAMILY" \
  --image "$app_image" \
  --command-json '["python","manage.py","migrate","--noinput"]'

registered_arn="$(AWS_PROFILE="$AWS_PROFILE" aws ecs register-task-definition \
  --region "$AWS_REGION" --cli-input-json "file://$tmp_dir/register.json" \
  --tags key=ManagedBy,value=operator-script key=Owner,value=yinon \
    key=Project,value=yinon-status-page key=Environment,value=prod \
  --query 'taskDefinition.taskDefinitionArn' --output text)"

network="$(AWS_PROFILE="$AWS_PROFILE" terraform -chdir="$ROOT/terraform" output -json network)"
subnets="$(jq -r '.app_subnet_ids | join(",")' <<<"$network")"
security_group="$(jq -r '.ecs_security_group' <<<"$network")"
[[ -n "$subnets" && "$security_group" == sg-* ]] || {
  echo "Production ECS network outputs are unavailable." >&2
  exit 1
}

run_result="$(AWS_PROFILE="$AWS_PROFILE" aws ecs run-task --region "$AWS_REGION" \
  --cluster "$CLUSTER" --launch-type FARGATE --task-definition "$registered_arn" \
  --started-by "status-page-migration-${sha:0:8}" \
  --network-configuration "awsvpcConfiguration={subnets=[$subnets],securityGroups=[$security_group],assignPublicIp=DISABLED}" \
  --propagate-tags TASK_DEFINITION --output json)"
[[ "$(jq '.failures | length' <<<"$run_result")" == "0" ]] || {
  jq -r '.failures[] | "ECS RunTask failed: \(.arn // "unknown") \(.reason // "unknown")"' <<<"$run_result" >&2
  exit 1
}
task_arn="$(jq -r '.tasks[0].taskArn // empty' <<<"$run_result")"
[[ -n "$task_arn" ]] || { echo "ECS did not return a migration task ARN." >&2; exit 1; }

AWS_PROFILE="$AWS_PROFILE" aws ecs wait tasks-stopped --region "$AWS_REGION" \
  --cluster "$CLUSTER" --tasks "$task_arn"
task_result="$(AWS_PROFILE="$AWS_PROFILE" aws ecs describe-tasks --region "$AWS_REGION" \
  --cluster "$CLUSTER" --tasks "$task_arn" --output json)"
exit_code="$(jq -r '.tasks[0].containers[0].exitCode // -1' <<<"$task_result")"
stop_reason="$(jq -r '.tasks[0].stoppedReason // "unknown"' <<<"$task_result")"
[[ "$exit_code" == "0" ]] || {
  echo "Migration task failed: exit_code=$exit_code stopped_reason=$stop_reason" >&2
  exit 1
}

gh variable set MIGRATION_EVIDENCE_SHA --repo "$REPOSITORY" --body "$sha"
printf 'migration_task=verified sha=%s task_arn=%s MIGRATION_EVIDENCE_SHA=%s\n' \
  "$sha" "$task_arn" "$sha"
