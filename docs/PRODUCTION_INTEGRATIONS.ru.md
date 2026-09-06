# Опциональные внешние интеграции

[English version](PRODUCTION_INTEGRATIONS.md)

Основной AWS lifecycle не зависит от этих интеграций. Они добавляют постоянное публичное DNS-имя и доставку AWS alerts в Telegram, если доступны credentials внешних providers и AWS notification topic.

## Приватная конфигурация

Создай `~/.config/status-page/integrations.env` с mode `0600`:

```text
CLOUDFLARE_DNS_API_TOKEN=REDACTED
CLOUDFLARE_WORKERS_API_TOKEN=REDACTED
CLOUDFLARE_ZONE_ID=REDACTED
CLOUDFLARE_ACCOUNT_ID=REDACTED
TELEGRAM_BOT_TOKEN=REDACTED
TELEGRAM_CHAT_ID=REDACTED
```

Используй отдельные Cloudflare tokens:

- DNS token: `Zone / DNS / Edit`, ограниченный zone `yifilter.uk`;
- Worker token: `Workers Scripts / Edit` и `Workers KV Storage / Edit`, ограниченный выбранным account.

Zone-scoped DNS token технически может менять другие records в этой zone. Updater программно разрешает только `status.yifilter.uk`. Для provider-enforced изоляции одной записи hostname пришлось бы делегировать как отдельную zone.

## Обновление DNS

После создания ALB `production_create.sh` вызывает updater. Скрипт принимает только:

```text
CNAME status.yifilter.uk
  -> yinon-status-page-prod-alb-*.il-central-1.elb.amazonaws.com
proxied=false
```

Другие names и targets отклоняются, а результат проверяется повторным запросом к Cloudflare.

Ручной запуск:

```bash
ALB_DNS="$(AWS_PROFILE=status-page terraform -chdir=terraform output -raw alb_dns_name)"
python3 scripts/update_cloudflare_dns.py --target "$ALB_DNS"
```

## Telegram alert relay

AWS alarms отправляют сообщения в точный SNS topic проекта. Cloudflare Worker проверяет SNS signature, topic ARN и timestamp, подавляет повторные MessageId через Cloudflare KV и отправляет сообщение в Telegram.

Deployment Worker:

```bash
python3 scripts/deploy_alert_relay.py
```

Скрипт создаёт или переиспользует фиксированный KV namespace, загружает Worker с secret bindings, включает endpoint `workers.dev`, проверяет bindings и health endpoint, затем сохраняет в private configuration только несекретный relay URL.

Terraform получает точный SNS topic ARN и relay endpoint. SNS topic policy должна разрешать публикацию только project CloudWatch alarms и project Budget из того же AWS account.

## Проверка

После подтверждения HTTPS subscription выполни synthetic notification test:

```bash
CONFIRM_SYNTHETIC_ALERT_TEST=yinon-status-page-prod-alb-target-5xx \
AWS_PROFILE=status-page \
scripts/test_production_alert.sh
```

Тест переводит alarm в `ALARM`, возвращает в `OK` и проверяет финальное состояние. Оба сообщения нужно подтвердить в Telegram. Synthetic state проверяет delivery path, а не реальный отказ сервиса.

Cloudflare KV использует eventual consistency, поэтому replay suppression является bounded, а не exactly-once delivery.
