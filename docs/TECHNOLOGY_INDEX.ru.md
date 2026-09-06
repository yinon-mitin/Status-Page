# Карта технологий

[English version](TECHNOLOGY_INDEX.md)

Документ объясняет основные технологии проекта и задачу каждой из них.

## Приложение

| Технология | Роль |
| --- | --- |
| Python | Runtime приложения и operational scripts |
| Django | Status pages, incidents, administration и REST API |
| Gunicorn | WSGI server для Django |
| NGINX | Reverse proxy и static-file server внутри web task |
| PostgreSQL | Основное хранилище приложения |
| Redis | Очереди RQ и Django cache |
| RQ Worker | Выполняет асинхронные задачи из Redis |
| RQ Scheduler | Запускает периодические задачи по расписанию |

## Контейнеры и локальная разработка

| Технология | Роль |
| --- | --- |
| Docker | Упаковывает приложение и NGINX runtime |
| Docker Compose | Запускает полную локальную среду из шести сервисов |
| OrbStack | Опциональный macOS runtime для containers и Linux VM |
| Tailwind и TypeScript | Собирают frontend assets для NGINX image |

## AWS platform

| Сервис | Роль |
| --- | --- |
| VPC | Сетевая граница проекта |
| Public subnets | Размещают Internet-facing load balancer в двух Availability Zones |
| Private application subnets | Размещают ECS tasks без public IP |
| Private data subnets | Размещают RDS и ElastiCache |
| Application Load Balancer | Направляет HTTP traffic на healthy web task IPs |
| ECS Fargate | Запускает web, worker и scheduler без EC2 hosts |
| Amazon ECR | Хранит immutable application и NGINX images |
| Amazon RDS for PostgreSQL | Managed encrypted database, backups и final snapshots |
| ElastiCache for Redis | Managed encrypted queue и cache service |
| Secrets Manager | Передаёт runtime secrets в ECS |
| VPC endpoints | Дают private tasks доступ к ECR, S3, Logs и Secrets Manager |
| CloudWatch | Хранит logs, dashboard и workload alarms |
| Amazon SNS | Опциональный transport внешней доставки alarms |
| AWS Budgets | Опциональный tagged monthly cost threshold |

## Delivery и infrastructure

| Технология | Роль |
| --- | --- |
| Terraform | Описывает AWS resources и remote state |
| S3 backend | Хранит encrypted versioned Terraform state и native lockfiles |
| GitHub Actions | Выполняет CI, security checks, image publication и ECS rollout |
| OpenID Connect | Выдаёт GitHub временные AWS credentials |
| Git SHA image tags | Связывают deployed images с source revision |
| GitHub Environment | Добавляет production approval |
| Gitleaks | Проверяет reachable Git history на secrets |
| TFLint | Проверяет Terraform глубже синтаксиса |
| ShellCheck и Actionlint | Валидируют lifecycle scripts и GitHub workflows |

## Эксплуатационные понятия

| Термин | Значение в проекте |
| --- | --- |
| Health check | Endpoint `/healthz`, используемый Docker, ECS и ALB |
| One-off migration | Private Fargate task, обновляющая database до rollout |
| Rolling deployment | Сначала обновляется web, затем worker и scheduler |
| Semantic restore | Snapshot restore с проверкой точного probe и Django migration history |
| Idempotency | Refreshed Terraform plan не показывает изменений после deployment |
| Guarded destroy | Delete-only allowlisted plan и direct absence checks |

## Правила архитектуры

1. Web, worker и scheduler используют один application image с разными commands.
2. Публичная поверхность заканчивается на load balancer; application и data services остаются private.
3. Database и Redis ports разрешены только от ECS security group.
4. Releases используют immutable images и отдельную migration task.
5. Terraform plans проверяются до apply или destroy.
6. Runtime secrets не попадают в Git, image layers, plans или logs.

Полная схема находится в [Архитектуре](ARCHITECTURE.ru.md), а команды — в [Production lifecycle](PRODUCTION_LIFECYCLE.ru.md).
