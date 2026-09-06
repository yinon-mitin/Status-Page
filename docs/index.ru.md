# Status-Page в AWS

[English version](index.md)

Документация описывает завершённую DevOps-реализацию для приложения Status-Page. Проект включает локальную Docker-среду и воспроизводимый AWS lifecycle на Terraform, ECS Fargate, managed data services и GitHub Actions.

## Основные документы

- [Архитектура](ARCHITECTURE.ru.md) описывает runtime, сеть и delivery model.
- [Production lifecycle](PRODUCTION_LIFECYCLE.ru.md) содержит команды создания, релиза, восстановления и удаления.
- [Карта технологий](TECHNOLOGY_INDEX.ru.md) связывает каждый инструмент с его задачей.
- [Подтверждение реализации](DELIVERY_EVIDENCE.ru.md) фиксирует локальные и AWS-проверки.
- [HTTPS scope](HTTPS_LIMITATION.ru.md) объясняет transport boundary демонстрации.

## Локальная среда

```bash
cp .env.example .env
make up
make check
```

Локальный stack запускает PostgreSQL, Redis, Django/Gunicorn, NGINX, RQ Worker и RQ Scheduler.

## AWS lifecycle

```text
create -> publish -> migrate -> approve -> deploy -> verify -> restore test -> destroy
```

Lifecycle scripts проверяют source revision, AWS account и сохранённый Terraform plan до изменения инфраструктуры.
