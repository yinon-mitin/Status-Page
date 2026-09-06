#!/usr/bin/env bash
set -euo pipefail

: "${AWS_REGION:?AWS_REGION is required}"
: "${ECS_CLUSTER:?ECS_CLUSTER is required}"
: "${ECS_WEB_SERVICE:?ECS_WEB_SERVICE is required}"
: "${ECS_WORKER_SERVICE:?ECS_WORKER_SERVICE is required}"
: "${ECS_SCHEDULER_SERVICE:?ECS_SCHEDULER_SERVICE is required}"
: "${IMAGE_TAG:?IMAGE_TAG is required}"
: "${APP_IMAGE:?APP_IMAGE is required}"
: "${NGINX_IMAGE:?NGINX_IMAGE is required}"
: "${PUBLIC_HEALTHCHECK_URL:?PUBLIC_HEALTHCHECK_URL is required}"

service_task_definition() {
  aws ecs describe-services --region "$AWS_REGION" --cluster "$ECS_CLUSTER" \
    --services "$1" --query 'services[0].taskDefinition' --output text
}

old_web="$(service_task_definition "$ECS_WEB_SERVICE")"
old_worker="$(service_task_definition "$ECS_WORKER_SERVICE")"
old_scheduler="$(service_task_definition "$ECS_SCHEDULER_SERVICE")"
updated_services=()
rollback_started=false

rollback() {
  status=$?
  trap - ERR
  set +e
  if [[ "$rollback_started" == true && "${#updated_services[@]}" -gt 0 ]]; then
    echo "Deployment failed; rolling updated ECS services back." >&2
    for service in "${updated_services[@]}"; do
      case "$service" in
        "$ECS_WEB_SERVICE") previous="$old_web" ;;
        "$ECS_WORKER_SERVICE") previous="$old_worker" ;;
        "$ECS_SCHEDULER_SERVICE") previous="$old_scheduler" ;;
        *) echo "Refusing unknown rollback service: $service" >&2; continue ;;
      esac
      aws ecs update-service --region "$AWS_REGION" --cluster "$ECS_CLUSTER" \
        --service "$service" --task-definition "$previous" --force-new-deployment >/dev/null
    done
    aws ecs wait services-stable --region "$AWS_REGION" --cluster "$ECS_CLUSTER" \
      --services "${updated_services[@]}" || true
  fi
  exit "$status"
}
trap rollback ERR

register_definition() {
  current="$1"
  update_nginx="$2"
  definition="$(aws ecs describe-task-definition --region "$AWS_REGION" \
    --task-definition "$current" --query taskDefinition --output json | jq \
      --arg app_image "$APP_IMAGE" \
      --arg nginx_image "$NGINX_IMAGE" \
      --argjson update_nginx "$update_nginx" '
        del(.taskDefinitionArn, .revision, .status, .requiresAttributes,
            .compatibilities, .registeredAt, .registeredBy, .deregisteredAt) |
        .containerDefinitions |= map(
          if (.name == "app" or .name == "worker" or .name == "scheduler") then .image = $app_image
          elif .name == "nginx" and $update_nginx then .image = $nginx_image
          else . end
        )')"
  aws ecs register-task-definition --region "$AWS_REGION" \
    --cli-input-json "$definition" --query 'taskDefinition.taskDefinitionArn' --output text
}

new_web="$(register_definition "$old_web" true)"
new_worker="$(register_definition "$old_worker" false)"
new_scheduler="$(register_definition "$old_scheduler" false)"

# The training-account deployer cannot call ecs:RunTask. The web image's
# start-web.sh runs `manage.py migrate --noinput` before Gunicorn, so service
# stability remains the available migration gate. See PRODUCTION_LIFECYCLE.md.
rollback_started=true
updated_services+=("$ECS_WEB_SERVICE")
aws ecs update-service --region "$AWS_REGION" --cluster "$ECS_CLUSTER" \
  --service "$ECS_WEB_SERVICE" --task-definition "$new_web" --force-new-deployment >/dev/null
aws ecs wait services-stable --region "$AWS_REGION" --cluster "$ECS_CLUSTER" \
  --services "$ECS_WEB_SERVICE"

updated_services+=("$ECS_WORKER_SERVICE")
aws ecs update-service --region "$AWS_REGION" --cluster "$ECS_CLUSTER" \
  --service "$ECS_WORKER_SERVICE" --task-definition "$new_worker" --force-new-deployment >/dev/null
updated_services+=("$ECS_SCHEDULER_SERVICE")
aws ecs update-service --region "$AWS_REGION" --cluster "$ECS_CLUSTER" \
  --service "$ECS_SCHEDULER_SERVICE" --task-definition "$new_scheduler" --force-new-deployment >/dev/null

aws ecs wait services-stable --region "$AWS_REGION" --cluster "$ECS_CLUSTER" \
  --services "$ECS_WEB_SERVICE" "$ECS_WORKER_SERVICE" "$ECS_SCHEDULER_SERVICE"
curl --fail --silent --show-error --retry 12 --retry-all-errors --retry-delay 10 \
  --connect-timeout 10 --max-time 30 "$PUBLIC_HEALTHCHECK_URL"
trap - ERR
printf '\ndeployed_image_tag=%s\n' "$IMAGE_TAG"
