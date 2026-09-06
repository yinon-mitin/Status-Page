#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPOSITORY="${GITHUB_REPOSITORY:-yinon-mitin/Status-Page}"
WORKFLOW="publish-ecr.yml"
git -C "$ROOT" fetch origin main
sha="$(git -C "$ROOT" rev-parse origin/main)"
[[ "$(git -C "$ROOT" rev-parse HEAD)" == "$sha" ]] || {
  echo "Check out the current origin/main before creating production." >&2
  exit 2
}
[[ -z "$(git -C "$ROOT" status --porcelain --untracked-files=no)" ]] || {
  echo "Tracked worktree changes must be committed before production creation." >&2
  exit 2
}

production_ready=false
pause_on_error() {
  status=$?
  trap - ERR
  if [[ "$production_ready" != true ]]; then
    gh variable set PRODUCTION_ENABLED --repo "$REPOSITORY" --body false || true
  fi
  exit "$status"
}
trap pause_on_error ERR

IMAGE_TAG="sha-$sha" CREATE_SERVICES=false "$ROOT/scripts/production_apply.sh"
alb_dns="$(AWS_PROFILE="${AWS_PROFILE:-status-page}" terraform -chdir="$ROOT/terraform" output -raw alb_dns_name)"
gh variable set AWS_ACCOUNT_ID --repo "$REPOSITORY" --body 992382545251
gh variable set AWS_REGION --repo "$REPOSITORY" --body il-central-1
gh variable set ECR_APP_REPOSITORY --repo "$REPOSITORY" --body yinon-status-page-prod-app
gh variable set ECR_NGINX_REPOSITORY --repo "$REPOSITORY" --body yinon-status-page-prod-nginx
gh variable set ECS_CLUSTER --repo "$REPOSITORY" --body yinon-status-page-prod
gh variable set ECS_WEB_SERVICE --repo "$REPOSITORY" --body web
gh variable set ECS_WORKER_SERVICE --repo "$REPOSITORY" --body worker
gh variable set ECS_SCHEDULER_SERVICE --repo "$REPOSITORY" --body scheduler
gh variable set PUBLIC_HEALTHCHECK_URL --repo "$REPOSITORY" --body "http://$alb_dns/healthz"
gh variable set PRODUCTION_ENABLED --repo "$REPOSITORY" --body true

dispatched_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
gh workflow run "$WORKFLOW" --repo "$REPOSITORY" --ref main -f publish=true -f deploy=false
run_id=""
for _ in $(seq 1 30); do
  run_id="$(gh run list --repo "$REPOSITORY" --workflow "$WORKFLOW" --event workflow_dispatch \
    --branch main --limit 10 --json databaseId,headSha,createdAt \
    --jq ".[] | select(.headSha == \"$sha\" and .createdAt >= \"$dispatched_at\") | .databaseId" | sed -n '1p')"
  [[ -n "$run_id" ]] && break
  sleep 2
done
[[ -n "$run_id" ]] || { echo "Could not identify the bootstrap image workflow run." >&2; exit 1; }
gh run watch "$run_id" --repo "$REPOSITORY" --exit-status

IMAGE_TAG="sha-$sha" CREATE_SERVICES=true "$ROOT/scripts/production_apply.sh"
"$ROOT/scripts/verify_production.sh"
production_ready=true
trap - ERR
printf 'bootstrap_workflow_run=%s\n' "$run_id"
