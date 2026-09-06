#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
"$ROOT/scripts/validate_production_source.sh"
AWS_PROFILE="${AWS_PROFILE:-status-page}"
AWS_REGION="${AWS_REGION:-il-central-1}"
EXPECTED_ACCOUNT_ID="992382545251"
SOURCE_DB="yinon-status-page-prod-postgres"
CLUSTER="yinon-status-page-prod"
SOURCE_FAMILY="yinon-status-page-prod-worker"
ONEOFF_FAMILY="yinon-status-page-prod-restore-validation"
sha="$(git -C "$ROOT" rev-parse origin/main)"
IMAGE_TAG="${IMAGE_TAG:-sha-$sha}"

[[ "${CONFIRM_RESTORE_TEST:-}" == "$sha" ]] || {
  echo "Set CONFIRM_RESTORE_TEST=$sha for this exact restore rehearsal revision." >&2
  exit 2
}
[[ "$IMAGE_TAG" == "sha-$sha" ]] || { echo "Restore test image must match origin/main." >&2; exit 2; }
account_id="$(AWS_PROFILE="$AWS_PROFILE" aws sts get-caller-identity --query Account --output text)"
[[ "$account_id" == "$EXPECTED_ACCOUNT_ID" ]] || { echo "Refusing AWS account $account_id" >&2; exit 2; }

stamp="$(date -u +%Y%m%d%H%M%S)"
snapshot_id="yinon-status-page-prod-restore-test-$stamp"
restored_db="yinon-status-page-prod-restore-test-$stamp"
probe_token="restore-$sha-$stamp"
app_image="$account_id.dkr.ecr.$AWS_REGION.amazonaws.com/yinon-status-page-prod-app:$IMAGE_TAG"
tmp_dir="$(mktemp -d /tmp/yinon-status-page-restore.XXXXXX)"
registered_arns=(__none__)
restore_created=false
snapshot_created=false
probe_seeded=false
source_host=""
source_secret=""
network=""

run_oneoff() {
  local phase="$1" host="$2" secret_arn="$3" command_json="$4"
  local source_file="$tmp_dir/source-$phase.json"
  local register_file="$tmp_dir/register-$phase.json"
  local registered_arn result task_arn task_result exit_code stop_reason

  AWS_PROFILE="$AWS_PROFILE" aws ecs describe-task-definition --region "$AWS_REGION" \
    --task-definition "$SOURCE_FAMILY" >"$source_file"
  python3 "$ROOT/scripts/build_oneoff_task_definition.py" \
    "$source_file" "$register_file" --family "$ONEOFF_FAMILY" --image "$app_image" \
    --command-json "$command_json" \
    --environment "POSTGRES_HOST=$host" \
    --environment "RESTORE_PROBE_TOKEN=$probe_token" \
    --secret "POSTGRES_PASSWORD=$secret_arn:password::"

  registered_arn="$(AWS_PROFILE="$AWS_PROFILE" aws ecs register-task-definition \
    --region "$AWS_REGION" --cli-input-json "file://$register_file" \
    --tags key=ManagedBy,value=operator-script key=Owner,value=yinon \
      key=Project,value=yinon-status-page key=Environment,value=prod \
    --query 'taskDefinition.taskDefinitionArn' --output text)"
  registered_arns+=("$registered_arn")

  result="$(AWS_PROFILE="$AWS_PROFILE" aws ecs run-task --region "$AWS_REGION" \
    --cluster "$CLUSTER" --launch-type FARGATE --task-definition "$registered_arn" \
    --started-by "restore-${phase}-${stamp:6:8}" \
    --network-configuration "$network" --propagate-tags TASK_DEFINITION --output json)"
  [[ "$(jq '.failures | length' <<<"$result")" == "0" ]] || {
    jq -r '.failures[] | "ECS RunTask failed: \(.reason // "unknown")"' <<<"$result" >&2
    return 1
  }
  task_arn="$(jq -r '.tasks[0].taskArn // empty' <<<"$result")"
  [[ -n "$task_arn" ]] || return 1
  AWS_PROFILE="$AWS_PROFILE" aws ecs wait tasks-stopped --region "$AWS_REGION" \
    --cluster "$CLUSTER" --tasks "$task_arn"
  task_result="$(AWS_PROFILE="$AWS_PROFILE" aws ecs describe-tasks --region "$AWS_REGION" \
    --cluster "$CLUSTER" --tasks "$task_arn" --output json)"
  exit_code="$(jq -r '.tasks[0].containers[0].exitCode // -1' <<<"$task_result")"
  stop_reason="$(jq -r '.tasks[0].stoppedReason // "unknown"' <<<"$task_result")"
  [[ "$exit_code" == "0" ]] || {
    echo "Restore $phase task failed: exit_code=$exit_code reason=$stop_reason" >&2
    return 1
  }
  printf 'restore_probe_phase=%s task_arn=%s\n' "$phase" "$task_arn"
}

cleanup() {
  status=$?
  trap - EXIT
  set +e
  if [[ "$probe_seeded" == true && -n "$source_host" && -n "$source_secret" && -n "$network" ]]; then
    cleanup_command='["python","manage.py","shell","-c","import os; from django.db import connection; token=os.environ[\"RESTORE_PROBE_TOKEN\"]; c=connection.cursor(); c.execute(\"DELETE FROM statuspage_restore_probe WHERE token = %s\", [token]); c.execute(\"SELECT COUNT(*) FROM statuspage_restore_probe\"); remaining=c.fetchone()[0]; remaining or c.execute(\"DROP TABLE statuspage_restore_probe\")"]'
    run_oneoff cleanup-source "$source_host" "$source_secret" "$cleanup_command" >/dev/null 2>&1 || true
  fi
  if [[ "$restore_created" == true ]]; then
    AWS_PROFILE="$AWS_PROFILE" aws rds delete-db-instance --region "$AWS_REGION" \
      --db-instance-identifier "$restored_db" --skip-final-snapshot --delete-automated-backups >/dev/null 2>&1 || true
    AWS_PROFILE="$AWS_PROFILE" aws rds wait db-instance-deleted --region "$AWS_REGION" \
      --db-instance-identifier "$restored_db" >/dev/null 2>&1 || true
  fi
  if [[ "$snapshot_created" == true ]]; then
    AWS_PROFILE="$AWS_PROFILE" aws rds delete-db-snapshot --region "$AWS_REGION" \
      --db-snapshot-identifier "$snapshot_id" >/dev/null 2>&1 || true
  fi
  for arn in "${registered_arns[@]}"; do
    [[ "$arn" == __none__ ]] && continue
    AWS_PROFILE="$AWS_PROFILE" aws ecs deregister-task-definition --region "$AWS_REGION" \
      --task-definition "$arn" >/dev/null 2>&1 || true
    AWS_PROFILE="$AWS_PROFILE" aws ecs delete-task-definitions --region "$AWS_REGION" \
      --task-definitions "$arn" >/dev/null 2>&1 || true
  done
  rm -rf "$tmp_dir"
  exit "$status"
}
trap cleanup EXIT

source_body="$(AWS_PROFILE="$AWS_PROFILE" aws rds describe-db-instances --region "$AWS_REGION" \
  --db-instance-identifier "$SOURCE_DB" --output json)"
source_host="$(jq -r '.DBInstances[0].Endpoint.Address // empty' <<<"$source_body")"
source_secret="$(jq -r '.DBInstances[0].MasterUserSecret.SecretArn // empty' <<<"$source_body")"
subnet_group="$(jq -r '.DBInstances[0].DBSubnetGroup.DBSubnetGroupName // empty' <<<"$source_body")"
security_group_ids=()
while IFS= read -r security_group_id; do
  [[ -n "$security_group_id" ]] && security_group_ids+=("$security_group_id")
done < <(jq -r '.DBInstances[0].VpcSecurityGroups[].VpcSecurityGroupId' <<<"$source_body")
[[ -n "$source_host" && -n "$source_secret" && -n "$subnet_group" && ${#security_group_ids[@]} -gt 0 ]] || {
  echo "Source RDS network/secret metadata is incomplete." >&2
  exit 1
}
network_json="$(AWS_PROFILE="$AWS_PROFILE" terraform -chdir="$ROOT/terraform" output -json network)"
subnets="$(jq -r '.app_subnet_ids | join(",")' <<<"$network_json")"
ecs_security_group="$(jq -r '.ecs_security_group' <<<"$network_json")"
network="awsvpcConfiguration={subnets=[$subnets],securityGroups=[$ecs_security_group],assignPublicIp=DISABLED}"

seed_command='["python","manage.py","shell","-c","import os; from django.db import connection; token=os.environ[\"RESTORE_PROBE_TOKEN\"]; c=connection.cursor(); c.execute(\"CREATE TABLE IF NOT EXISTS statuspage_restore_probe (token varchar(128) PRIMARY KEY, created_at timestamptz NOT NULL DEFAULT now())\"); c.execute(\"INSERT INTO statuspage_restore_probe (token) VALUES (%s) ON CONFLICT (token) DO NOTHING\", [token])"]'
run_oneoff seed-source "$source_host" "$source_secret" "$seed_command"
probe_seeded=true

AWS_PROFILE="$AWS_PROFILE" aws rds create-db-snapshot --region "$AWS_REGION" \
  --db-instance-identifier "$SOURCE_DB" --db-snapshot-identifier "$snapshot_id" \
  --tags Key=ManagedBy,Value=operator-script Key=Owner,Value=yinon \
    Key=Project,Value=yinon-status-page Key=Environment,Value=prod >/dev/null
snapshot_created=true
AWS_PROFILE="$AWS_PROFILE" aws rds wait db-snapshot-completed --region "$AWS_REGION" \
  --db-snapshot-identifier "$snapshot_id"

# Restore is private, encrypted by the source snapshot, disposable, and deletion-protection-free.
AWS_PROFILE="$AWS_PROFILE" aws rds restore-db-instance-from-db-snapshot --region "$AWS_REGION" \
  --db-instance-identifier "$restored_db" --db-snapshot-identifier "$snapshot_id" \
  --db-instance-class db.t4g.micro --db-subnet-group-name "$subnet_group" \
  --vpc-security-group-ids "${security_group_ids[@]}" --no-publicly-accessible --no-multi-az \
  --no-deletion-protection --copy-tags-to-snapshot \
  --tags Key=ManagedBy,Value=operator-script Key=Owner,Value=yinon \
    Key=Project,Value=yinon-status-page Key=Environment,Value=prod >/dev/null
restore_created=true
AWS_PROFILE="$AWS_PROFILE" aws rds wait db-instance-available --region "$AWS_REGION" \
  --db-instance-identifier "$restored_db"

restore_body="$(AWS_PROFILE="$AWS_PROFILE" aws rds describe-db-instances --region "$AWS_REGION" \
  --db-instance-identifier "$restored_db" --output json)"
restore_host="$(jq -r '.DBInstances[0].Endpoint.Address // empty' <<<"$restore_body")"
publicly_accessible="$(jq -r '.DBInstances[0].PubliclyAccessible' <<<"$restore_body")"
[[ -n "$restore_host" && "$publicly_accessible" == false ]] || {
  echo "Restored RDS failed private endpoint verification." >&2
  exit 1
}

verify_command='["python","manage.py","shell","-c","import os; from django.db import connection; token=os.environ[\"RESTORE_PROBE_TOKEN\"]; c=connection.cursor(); c.execute(\"SELECT COUNT(*) FROM statuspage_restore_probe WHERE token = %s\", [token]); count=c.fetchone()[0]; c.execute(\"SELECT COUNT(*) FROM django_migrations\"); migrations=c.fetchone()[0]; assert count == 1 and migrations > 0, (count, migrations)"]'
# PostgreSQL snapshot restore preserves the source master credential. RDS exposes
# the managed-password restore switch only for Oracle, so the
# validation task deliberately uses the existing source RDS-managed secret.
run_oneoff verify-restored "$restore_host" "$source_secret" "$verify_command"

cleanup_command='["python","manage.py","shell","-c","import os; from django.db import connection; token=os.environ[\"RESTORE_PROBE_TOKEN\"]; c=connection.cursor(); c.execute(\"DELETE FROM statuspage_restore_probe WHERE token = %s\", [token]); c.execute(\"SELECT COUNT(*) FROM statuspage_restore_probe\"); remaining=c.fetchone()[0]; remaining or c.execute(\"DROP TABLE statuspage_restore_probe\")"]'
run_oneoff cleanup-source "$source_host" "$source_secret" "$cleanup_command"
probe_seeded=false

# Cleanup is part of PASS, not deferred housekeeping.
AWS_PROFILE="$AWS_PROFILE" aws rds delete-db-instance --region "$AWS_REGION" \
  --db-instance-identifier "$restored_db" --skip-final-snapshot --delete-automated-backups >/dev/null
AWS_PROFILE="$AWS_PROFILE" aws rds wait db-instance-deleted --region "$AWS_REGION" \
  --db-instance-identifier "$restored_db"
restore_created=false
AWS_PROFILE="$AWS_PROFILE" aws rds delete-db-snapshot --region "$AWS_REGION" \
  --db-snapshot-identifier "$snapshot_id" >/dev/null
AWS_PROFILE="$AWS_PROFILE" aws rds wait db-snapshot-deleted --region "$AWS_REGION" \
  --db-snapshot-identifier "$snapshot_id"
snapshot_created=false

if AWS_PROFILE="$AWS_PROFILE" aws rds describe-db-instances --region "$AWS_REGION" \
  --db-instance-identifier "$restored_db" >/dev/null 2>&1; then
  echo "Disposable restored DB still exists after cleanup." >&2
  exit 1
fi
if AWS_PROFILE="$AWS_PROFILE" aws rds describe-db-snapshots --region "$AWS_REGION" \
  --db-snapshot-identifier "$snapshot_id" >/dev/null 2>&1; then
  echo "Temporary restore snapshot still exists after cleanup." >&2
  exit 1
fi
for arn in "${registered_arns[@]}"; do
  [[ "$arn" == __none__ ]] && continue
  AWS_PROFILE="$AWS_PROFILE" aws ecs deregister-task-definition --region "$AWS_REGION" \
    --task-definition "$arn" >/dev/null 2>&1 || true
  AWS_PROFILE="$AWS_PROFILE" aws ecs delete-task-definitions --region "$AWS_REGION" \
    --task-definitions "$arn" >/dev/null 2>&1 || true
done

printf 'backup_restore=verified snapshot=%s restored_db=%s semantic_probe=present django_migrations=present cleanup=complete\n' \
  "$snapshot_id" "$restored_db"
