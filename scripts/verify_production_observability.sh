#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AWS_PROFILE="${AWS_PROFILE:-status-page}"
AWS_REGION="${AWS_REGION:-il-central-1}"
ACCOUNT_ID="992382545251"
DASHBOARD="yinon-status-page-prod"
BUDGET="yinon-status-page-prod-monthly"

[[ "$(AWS_PROFILE="$AWS_PROFILE" aws sts get-caller-identity --query Account --output text)" == "$ACCOUNT_ID" ]]
topic_arn="$(AWS_PROFILE="$AWS_PROFILE" terraform -chdir="$ROOT/terraform" output -json | jq -r '.alert_topic_arn.value // empty')"
alarms="$(AWS_PROFILE="$AWS_PROFILE" aws cloudwatch describe-alarms --region "$AWS_REGION" \
  --alarm-name-prefix yinon-status-page-prod- --output json)"
[[ "$(jq '.MetricAlarms | length' <<<"$alarms")" == "18" ]] || {
  echo "Expected exactly 18 production metric alarms." >&2
  jq -r '.MetricAlarms[].AlarmName' <<<"$alarms" >&2
  exit 1
}
expected_actions="$(jq -cn --arg topic "$topic_arn" 'if $topic == "" then [] else [$topic] end')"
jq -e --argjson expected "$expected_actions" \
  'all(.MetricAlarms[]; .AlarmActions == $expected and .OKActions == $expected)' \
  <<<"$alarms" >/dev/null || {
    echo "Production alarms have stale or unauthorized alarm actions." >&2
    exit 1
  }
AWS_PROFILE="$AWS_PROFILE" aws cloudwatch get-dashboard --region "$AWS_REGION" \
  --dashboard-name "$DASHBOARD" >/dev/null
budget_status="permission-gated"
if AWS_PROFILE="$AWS_PROFILE" terraform -chdir="$ROOT/terraform" state list | grep -qx 'aws_budgets_budget.project\[0\]'; then
  budget="$(AWS_PROFILE="$AWS_PROFILE" aws budgets describe-budget --account-id "$ACCOUNT_ID" \
    --budget-name "$BUDGET" --output json)"
  [[ "$(jq -r '.Budget.BudgetLimit.Amount' <<<"$budget")" == "300" ]]
  [[ "$(jq -r '.Budget.BudgetLimit.Unit' <<<"$budget")" == "USD" ]]
  budget_status="verified"
fi
if [[ -n "$topic_arn" ]]; then
  AWS_PROFILE="$AWS_PROFILE" aws sns get-topic-attributes --region "$AWS_REGION" \
    --topic-arn "$topic_arn" >/dev/null
fi

integrations_file="${INTEGRATIONS_FILE:-$HOME/.config/status-page/integrations.env}"
relay_url=""
if [[ -f "$integrations_file" ]]; then
  relay_url="$(python3 - "$integrations_file" <<'PY'
import os, stat, sys
path=sys.argv[1]
if stat.S_IMODE(os.stat(path).st_mode) & 0o077:
    raise SystemExit(f"{path} must have mode 0600")
for line in open(path, encoding="utf-8"):
    if line.startswith("ALERT_RELAY_URL="):
        print(line.rstrip("\n").partition("=")[2])
        break
PY
)"
fi
if [[ -n "$relay_url" && -n "$topic_arn" ]]; then
  subscription="$(AWS_PROFILE="$AWS_PROFILE" aws sns list-subscriptions-by-topic --region "$AWS_REGION" \
    --topic-arn "$topic_arn" --output json)"
  jq -e --arg endpoint "$relay_url" \
    '.Subscriptions | any(.Protocol == "https" and .Endpoint == $endpoint and .SubscriptionArn != "PendingConfirmation")' \
    <<<"$subscription" >/dev/null || {
      echo "Telegram relay SNS subscription is not confirmed." >&2
      exit 1
    }
elif [[ -n "$relay_url" ]]; then
  echo "Telegram relay is configured, but no administrator-approved SNS topic is available." >&2
fi

printf 'observability=verified alarms=18 dashboard=%s budget=%s sns_topic=%s relay=%s\n' \
  "$DASHBOARD" "$budget_status" "${topic_arn:-permission-gated}" "${relay_url:+configured}"
