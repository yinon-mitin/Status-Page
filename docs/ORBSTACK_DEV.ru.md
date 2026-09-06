# OrbStack development VM

[English version](ORBSTACK_DEV.md)

Репозиторий содержит локальный Cloud-Init bootstrap для Ubuntu 24.04 ARM64 VM под управлением OrbStack. Эта среда проверяет Docker, Compose, запуск через systemd и восстановление после перезагрузки Linux VM без Docker Desktop.

## Требования

- macOS с установленным OrbStack;
- `orbctl` в `PATH`;
- локальный checkout репозитория.

## Создание VM

Из корня репозитория:

```bash
orbctl create \
  --arch arm64 \
  --cpus 4 \
  --memory 8G \
  --disk 64G \
  --user statuspage \
  --user-data "$PWD/infra/cloud-init/statuspage-dev.yaml" \
  ubuntu:24.04 \
  statuspage-dev
```

Дождись завершения Cloud-Init:

```bash
orbctl run -m statuspage-dev cloud-init status --wait
```

## Установка checkout в VM

```bash
orbctl push -m statuspage-dev "$PWD" /home/statuspage/Status-Page
orbctl run -m statuspage-dev -u root -- sh -lc \
  'rm -rf /opt/status-page && mv /home/statuspage/Status-Page /opt/status-page && chown -R statuspage:statuspage /opt/status-page && systemctl start statuspage-dev.service'
```

VM bootstrap управляет Compose lifecycle через `statuspage-dev.service`. Сервис запускает stack после готовности Docker и сети и останавливает его перед выключением VM.

## Проверка VM

```bash
orbctl run -m statuspage-dev -u root /usr/local/bin/statuspage-dev-check
```

Команда проверяет состояние Compose, `/healthz`, Django system checks, Django tests и RQ smoke test.

## Проверка восстановления после перезагрузки

```bash
orbctl restart statuspage-dev
orbctl run -m statuspage-dev -u root systemctl is-active --wait statuspage-dev.service
orbctl run -m statuspage-dev -u statuspage -- sh -lc \
  'curl --fail --silent --show-error http://127.0.0.1:8081/healthz'
```

Ожидаемый ответ: `{"status": "ok"}`. В первые секунды после перезагрузки systemd может показывать `activating`, пока Compose health checks не завершатся. Проверяй результат после перехода сервиса в `active`.

Эта VM предназначена для локальной разработки и проверки mechanics. Она не заменяет проверку AWS VPC, ALB, RDS, Redis, public DNS или ECS.
