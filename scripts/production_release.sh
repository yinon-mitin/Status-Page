#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPOSITORY="${GITHUB_REPOSITORY:-yinon-mitin/Status-Page}"
WORKFLOW="publish-ecr.yml"
git -C "$ROOT" fetch origin main
sha="$(git -C "$ROOT" rev-parse origin/main)"
AWS_PROFILE="${AWS_PROFILE:-status-page}"
[[ "${CONFIRM_PRODUCTION_APPROVAL:-}" == "$sha" ]] || {
  echo "Set CONFIRM_PRODUCTION_APPROVAL=$sha to approve this exact main revision." >&2
  exit 2
}

AWS_PROFILE="$AWS_PROFILE" aws ecr describe-images --region "${AWS_REGION:-il-central-1}" \
  --repository-name yinon-status-page-prod-app --image-ids imageTag="sha-$sha" >/dev/null
AWS_PROFILE="$AWS_PROFILE" aws ecr describe-images --region "${AWS_REGION:-il-central-1}" \
  --repository-name yinon-status-page-prod-nginx --image-ids imageTag="sha-$sha" >/dev/null

dispatched_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
gh workflow run "$WORKFLOW" --repo "$REPOSITORY" --ref main -f publish=false -f deploy=true
run_id=""
for _ in $(seq 1 30); do
  run_id="$(gh run list --repo "$REPOSITORY" --workflow "$WORKFLOW" --event workflow_dispatch \
    --branch main --limit 10 --json databaseId,headSha,createdAt \
    --jq ".[] | select(.headSha == \"$sha\" and .createdAt >= \"$dispatched_at\") | .databaseId" | sed -n '1p')"
  [[ -n "$run_id" ]] && break
  sleep 2
done
[[ -n "$run_id" ]] || { echo "Could not identify the production workflow run." >&2; exit 1; }

pending_id=""
for _ in $(seq 1 180); do
  pending_id="$(gh api "repos/$REPOSITORY/actions/runs/$run_id/pending_deployments" \
    --jq '.[] | select(.environment.name == "production") | .environment.id' 2>/dev/null || true)"
  [[ -n "$pending_id" ]] && break
  conclusion="$(gh run view "$run_id" --repo "$REPOSITORY" --json status,conclusion --jq '.conclusion // empty')"
  [[ -z "$conclusion" ]] || { echo "Run completed before approval: $conclusion" >&2; exit 1; }
  sleep 5
done
[[ -n "$pending_id" ]] || { echo "Production approval gate did not become pending." >&2; exit 1; }

gh api --method POST "repos/$REPOSITORY/actions/runs/$run_id/pending_deployments" \
  --input - <<JSON
{"environment_ids":[$pending_id],"state":"approved","comment":"Approved automated rehearsal for exact main SHA $sha"}
JSON
gh run watch "$run_id" --repo "$REPOSITORY" --exit-status
"$ROOT/scripts/verify_production.sh"
printf 'deployment_workflow_run=%s\n' "$run_id"
