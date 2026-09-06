#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$ROOT/terraform"
AWS_PROFILE="${AWS_PROFILE:-status-page}"
AWS_REGION="${AWS_REGION:-il-central-1}"
ECS_CLUSTER="${ECS_CLUSTER:-yinon-status-page-prod}"
services=(web worker scheduler)

AWS_PROFILE="$AWS_PROFILE" aws ecs wait services-stable \
  --region "$AWS_REGION" --cluster "$ECS_CLUSTER" --services "${services[@]}"
AWS_PROFILE="$AWS_PROFILE" aws ecs describe-services \
  --region "$AWS_REGION" --cluster "$ECS_CLUSTER" --services "${services[@]}" \
  --query 'services[].{Name:serviceName,Desired:desiredCount,Running:runningCount,Pending:pendingCount}' \
  --output table

alb_dns="$(AWS_PROFILE="$AWS_PROFILE" terraform -chdir="$TF_DIR" output -raw alb_dns_name)"
[[ -n "$alb_dns" ]] || { echo "Missing ALB DNS output" >&2; exit 1; }
curl --fail --silent --show-error --retry 12 --retry-all-errors \
  --retry-delay 10 --connect-timeout 10 --max-time 30 "http://$alb_dns/healthz"
printf '\nprovider_health_url=http://%s/healthz\n' "$alb_dns"
