#!/usr/bin/env bash
set -euo pipefail

AWS_PROFILE="${AWS_PROFILE:-status-page}"
AWS_REGION="${AWS_REGION:-il-central-1}"
ACCOUNT_ID="992382545251"
ALARM_NAME="yinon-status-page-prod-alb-target-5xx"

[[ "${CONFIRM_SYNTHETIC_ALERT_TEST:-}" == "$ALARM_NAME" ]] || {
  echo "Set CONFIRM_SYNTHETIC_ALERT_TEST=$ALARM_NAME to test the notification path." >&2
  exit 2
}
[[ "$(AWS_PROFILE="$AWS_PROFILE" aws sts get-caller-identity --query Account --output text)" == "$ACCOUNT_ID" ]]

AWS_PROFILE="$AWS_PROFILE" aws cloudwatch set-alarm-state --region "$AWS_REGION" \
  --alarm-name "$ALARM_NAME" --state-value ALARM \
  --state-reason "Synthetic notification-path rehearsal; no real outage occurred."
for _ in $(seq 1 30); do
  state="$(AWS_PROFILE="$AWS_PROFILE" aws cloudwatch describe-alarms --region "$AWS_REGION" \
    --alarm-names "$ALARM_NAME" --query 'MetricAlarms[0].StateValue' --output text)"
  [[ "$state" == "ALARM" ]] && break
  sleep 2
done
[[ "${state:-}" == "ALARM" ]] || { echo "Synthetic ALARM state did not become visible." >&2; exit 1; }

AWS_PROFILE="$AWS_PROFILE" aws cloudwatch set-alarm-state --region "$AWS_REGION" \
  --alarm-name "$ALARM_NAME" --state-value OK \
  --state-reason "Synthetic notification-path rehearsal completed."
for _ in $(seq 1 30); do
  state="$(AWS_PROFILE="$AWS_PROFILE" aws cloudwatch describe-alarms --region "$AWS_REGION" \
    --alarm-names "$ALARM_NAME" --query 'MetricAlarms[0].StateValue' --output text)"
  [[ "$state" == "OK" ]] && break
  sleep 2
done
[[ "${state:-}" == "OK" ]] || { echo "Alarm did not return to OK." >&2; exit 1; }

printf 'synthetic_alert=published alarm=%s final_state=OK user_must_verify_telegram_delivery=true\n' "$ALARM_NAME"
