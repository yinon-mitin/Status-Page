# Optional external integrations

[Русская версия](PRODUCTION_INTEGRATIONS.ru.md)

The core AWS lifecycle does not depend on these integrations. They add a stable public DNS name and Telegram delivery for AWS alerts when the required provider credentials and AWS notification topic are available.

## Private configuration

Create `~/.config/status-page/integrations.env` with mode `0600`:

```text
CLOUDFLARE_DNS_API_TOKEN=REDACTED
CLOUDFLARE_WORKERS_API_TOKEN=REDACTED
CLOUDFLARE_ZONE_ID=REDACTED
CLOUDFLARE_ACCOUNT_ID=REDACTED
TELEGRAM_BOT_TOKEN=REDACTED
TELEGRAM_CHAT_ID=REDACTED
```

Use separate Cloudflare tokens:

- DNS token: `Zone / DNS / Edit`, restricted to `yifilter.uk`;
- Worker token: `Workers Scripts / Edit` and `Workers KV Storage / Edit`, restricted to the selected account.

A zone-scoped DNS token can technically edit other records in that zone. The updater enforces the exact `status.yifilter.uk` record in code; provider-enforced record isolation would require delegating that hostname as a separate zone.

## DNS update

`production_create.sh` calls the updater after the ALB exists. The script accepts only:

```text
CNAME status.yifilter.uk
  -> yinon-status-page-prod-alb-*.il-central-1.elb.amazonaws.com
proxied=false
```

It rejects other names and target classes, then reads the record back from Cloudflare.

Manual invocation:

```bash
ALB_DNS="$(AWS_PROFILE=status-page terraform -chdir=terraform output -raw alb_dns_name)"
python3 scripts/update_cloudflare_dns.py --target "$ALB_DNS"
```

## Telegram alert relay

AWS alarms publish to the exact project SNS topic. A Cloudflare Worker verifies the SNS signature, topic ARN and timestamp, suppresses repeated message IDs through Cloudflare KV, and sends the message to Telegram.

Deploy the Worker after creating the private configuration:

```bash
python3 scripts/deploy_alert_relay.py
```

The deployment creates or reuses the fixed KV namespace, uploads the Worker with secret bindings, enables its `workers.dev` endpoint, checks the bindings and health endpoint, and stores only the non-secret relay URL in the private configuration file.

Configure Terraform with the exact SNS topic ARN and relay endpoint. The SNS topic policy must allow only project CloudWatch alarms and the project Budget from the same AWS account.

## Verification

After Terraform confirms the HTTPS subscription, run the synthetic notification-path test:

```bash
CONFIRM_SYNTHETIC_ALERT_TEST=yinon-status-page-prod-alb-target-5xx \
AWS_PROFILE=status-page \
scripts/test_production_alert.sh
```

The test moves one alarm to `ALARM`, returns it to `OK`, and verifies the final state. Confirm both messages in Telegram. Synthetic state changes prove delivery, not a real service failure.

Cloudflare KV is eventually consistent, so replay suppression is bounded rather than exactly-once delivery.
