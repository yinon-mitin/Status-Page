#!/usr/bin/env bash
set -euo pipefail

AWS_PROFILE="${AWS_PROFILE:-status-page}"
AWS_REGION="${AWS_REGION:-il-central-1}"
ACCOUNT_ID="992382545251"
TOPIC_ARN="arn:aws:sns:$AWS_REGION:$ACCOUNT_ID:yinon-status-page-prod-alerts"
DASHBOARD="yinon-status-page-prod"
BUDGET="yinon-status-page-prod-monthly"

[[ "$(AWS_PROFILE="$AWS_PROFILE" aws sts get-caller-identity --query Account --output text)" == "$ACCOUNT_ID" ]]
alarm_names="$(AWS_PROFILE="$AWS_PROFILE" aws cloudwatch describe-alarms --region "$AWS_REGION" \
  --alarm-name-prefix yinon-status-page-prod- --query 'MetricAlarms[].AlarmName' --output json)"
[[ "$(jq length <<<"$alarm_names")" == "18" ]] || {
  echo "Expected exactly 18 production metric alarms." >&2
  jq -r '.[]' <<<"$alarm_names" >&2
  exit 1
}
AWS_PROFILE="$AWS_PROFILE" aws cloudwatch get-dashboard --region "$AWS_REGION" \
  --dashboard-name "$DASHBOARD" >/dev/null
AWS_PROFILE="$AWS_PROFILE" aws sns get-topic-attributes --region "$AWS_REGION" \
  --topic-arn "$TOPIC_ARN" >/dev/null
budget="$(AWS_PROFILE="$AWS_PROFILE" aws budgets describe-budget --account-id "$ACCOUNT_ID" \
  --budget-name "$BUDGET" --output json)"
[[ "$(jq -r '.Budget.BudgetLimit.Amount' <<<"$budget")" == "300" ]]
[[ "$(jq -r '.Budget.BudgetLimit.Unit' <<<"$budget")" == "USD" ]]

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
if [[ -n "$relay_url" ]]; then
  subscription="$(AWS_PROFILE="$AWS_PROFILE" aws sns list-subscriptions-by-topic --region "$AWS_REGION" \
    --topic-arn "$TOPIC_ARN" --output json)"
  jq -e --arg endpoint "$relay_url" \
    '.Subscriptions | any(.Protocol == "https" and .Endpoint == $endpoint and .SubscriptionArn != "PendingConfirmation")' \
    <<<"$subscription" >/dev/null || {
      echo "Telegram relay SNS subscription is not confirmed." >&2
      exit 1
    }
fi

printf 'observability=verified alarms=18 dashboard=%s budget_usd=300 sns_topic=%s relay=%s\n' \
  "$DASHBOARD" "$TOPIC_ARN" "${relay_url:+confirmed}"
