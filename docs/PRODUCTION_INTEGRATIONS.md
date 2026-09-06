# Production integrations

No credential value belongs in Git, Terraform state, GitHub Variables, command-line
arguments, or documentation.

## Required credentials

Create `~/.config/status-page/integrations.env` and set mode `0600`:

```text
CLOUDFLARE_DNS_API_TOKEN=REDACTED
CLOUDFLARE_WORKERS_API_TOKEN=REDACTED
CLOUDFLARE_ZONE_ID=32_HEX_CHARACTERS
CLOUDFLARE_ACCOUNT_ID=32_HEX_CHARACTERS
TELEGRAM_BOT_TOKEN=REDACTED
TELEGRAM_CHAT_ID=REDACTED
```

For least privilege, use two Cloudflare tokens:

1. **DNS token:** `Zone / DNS / Edit`, restricted to zone `yifilter.uk`.
2. **Worker token:** `Account / Workers Scripts / Edit`, restricted to the selected
   Cloudflare account.

A single `CLOUDFLARE_API_TOKEN` is accepted for compatibility, but separate tokens
have a smaller blast radius. Zone ID and Account ID are shown in the Cloudflare
`yifilter.uk` dashboard Overview.

Create the Telegram bot through `@BotFather` with `/newbot`, send `/start` to the
new bot, then retrieve the target chat ID from the Telegram `getUpdates` response.
Do not paste the bot token or response into an issue, pull request, or chat.

```bash
chmod 600 ~/.config/status-page/integrations.env
```

## Deploy the alert relay

```bash
python3 scripts/deploy_alert_relay.py
```

The deployer uploads the fixed Worker module with secret bindings, reads back the
required binding names, probes the Worker health endpoint, and writes only the
non-secret `ALERT_RELAY_URL` back to the private credentials file.

The next production Terraform apply reads only `ALERT_RELAY_URL` and creates the
SNS HTTPS subscription when an approved SNS topic is available. The Worker
automatically handles the signed SNS subscription confirmation.

The training operator currently receives `AccessDenied` for `SNS:CreateTopic`.
An account administrator must therefore create exactly
`yinon-status-page-prod-alerts` in `il-central-1`, attach the scoped policy described
in `terraform/monitoring.tf`, and provide its ARN as `external_alert_topic_arn`.
Do not grant broad SNS administration merely for the demo.

## DNS lifecycle

During production creation, the exact-domain updater runs automatically after the
ALB is created. It updates only `status.yifilter.uk`, keeps Cloudflare proxying off,
and verifies the resulting CNAME by API read-back.

Manual verification without changing another name:

```bash
ALB_DNS="$(AWS_PROFILE=status-page terraform -chdir=terraform output -raw alb_dns_name)"
python3 scripts/update_cloudflare_dns.py --target "$ALB_DNS"
```

Cloudflare DNS is external to the AWS Terraform state and therefore remains after
AWS destroy. A parked CNAME to a deleted ALB is expected until the next create or
explicit DNS removal. The automation deliberately has no delete operation.

## End-to-end Telegram test

After the SNS subscription is `Confirmed`:

1. select one project alarm;
2. temporarily set its state through the CloudWatch `SetAlarmState` API;
3. verify one Telegram alert arrives;
4. return the alarm to `OK` and verify recovery delivery;
5. read back the alarm and subscription state.

Synthetic state changes are evidence of the notification path, not evidence that a
real service failure occurred. The live rehearsal log must record this distinction.

## Rotation and revocation

- Rotate the Telegram bot token through `@BotFather`, update the private file, and
  redeploy the Worker.
- Revoke either Cloudflare token independently after the demo if ongoing automation
  is unnecessary.
- Deleting the Worker breaks notification delivery but does not affect AWS runtime.
- Deleting the SNS subscription stops Telegram delivery but alarms remain visible in
  CloudWatch.
