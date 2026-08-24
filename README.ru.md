# Финальный DevOps-проект Yinon

Это неофициальный учебный DevOps fork [Status-Page](https://github.com/Status-Page/Status-Page). Он содержит исходный код приложения и реализацию Docker, AWS ECS/Fargate, Terraform и CI/CD.

## Документация

- [AWS-архитектура — English](docs/ARCHITECTURE.md)
- [AWS-архитектура — Russian](docs/ARCHITECTURE.ru.md)
- [Индекс технологий — English](docs/TECHNOLOGY_INDEX.md)
- [Индекс технологий — Russian](docs/TECHNOLOGY_INDEX.ru.md)
- [Интерактивный обзор проекта и инфраструктуры](docs/PROJECT_INFRASTRUCTURE.html)
- [Происхождение upstream и политика сопровождения](UPSTREAM.ru.md)
- [Terraform baseline на четверг](terraform/README.md)
- [Статус реализации на четверг — English](docs/THURSDAY_STATUS.md)
- [Статус реализации на четверг — Russian](docs/THURSDAY_STATUS.ru.md)
- [Changelog](CHANGELOG.md)
- [Журнал реализации — English](docs/IMPLEMENTATION_LOG.md)
- [Журнал реализации — Russian](docs/IMPLEMENTATION_LOG.ru.md)
- [Аудит milestone среды/четверга — English](docs/MILESTONE_AUDIT.md)
- [Аудит milestone среды/четверга — Russian](docs/MILESTONE_AUDIT.ru.md)
- [Зафиксированный application source: upstream Status-Page v2.5.1](https://github.com/Status-Page/Status-Page/releases/tag/v2.5.1)

Документ отделяет факты, взятые из исходника Status-Page, от согласованных решений для AWS deployment. Инфраструктурная диаграмма использует Mermaid и отображается в GitHub, GitLab или Markdown-просмотрщиках с поддержкой Mermaid.

## Локальный Docker milestone

Milestone на среду реализован: Docker Compose запускает NGINX, Django/Gunicorn, RQ Worker, RQ Scheduler, PostgreSQL и Redis.

```bash
cp .env.example .env
docker compose up --build -d
curl http://localhost:8081/healthz
docker compose ps
```

Приложение доступно по `http://localhost:8081`. Для остановки используйте `docker compose down`; добавляйте `-v` только при намеренном удалении локальных volumes PostgreSQL, Redis, static и media. Чтобы выбрать другой host port, задайте согласованные `STATUSPAGE_HTTP_PORT` и `STATUS_PAGE_SITE_URL` в `.env`.

## Целевая архитектура в одном абзаце

Docker → Amazon ECR → Amazon ECS Fargate; internet-facing ALB находится в двух public subnets, а ECS — во внутренних application subnets. RDS PostgreSQL имеет setting publicly accessible, но port 5432 разрешён только от ECS security group; ElastiCache Redis остаётся private. NGINX работает внутри web task, платформу дополняют Secrets Manager, IAM, CloudWatch, Terraform и GitHub Actions.

## Milestone на четверг

ECR/ECS и CI foundations реализованы в коде. Terraform создаёт immutable ECR repositories, ECS cluster, task definitions, CloudWatch log groups и least-privilege ECS roles. GitHub Actions проверяет Docker/Terraform в pull request и публикует оба image в ECR через GitHub OIDC после настройки repository variables и AWS role. AWS resources не применяются автоматически, а ECS services остаются выключенными, пока не готовы и не проверены network, database, Redis, ALB и Secrets Manager inputs.

## Политика версии исходника

Application source в корне репозитория закреплён на официальном stable upstream release **v2.5.1** от 29 октября 2024, а не на прежнем учебном архиве. Upstream был архивирован в октябре 2025, а заявленная security support завершилась 31 декабря 2025; поэтому финальный проект рассматривает v2.5.1 как фиксированную и проверяемую зависимость, а не активно поддерживаемый продукт.
