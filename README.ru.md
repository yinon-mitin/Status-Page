<p align="center"><img src="assets/statuspage-devops-icon.png" width="150" alt="Иконка Status-Page DevOps"></p>

<h1 align="center">Status-Page DevOps</h1>

<p align="center">AWS-инфраструктура для open-source приложения Status-Page.</p>

<p align="center">
  <a href="https://github.com/yinon-mitin/Status-Page/actions/workflows/ci.yml"><img src="https://github.com/yinon-mitin/Status-Page/actions/workflows/ci.yml/badge.svg?branch=main" alt="Validate workflow"></a>
  <a href="https://github.com/yinon-mitin/Status-Page/blob/main/LICENSE.txt"><img src="https://img.shields.io/badge/license-Apache--2.0-blue.svg" alt="Лицензия Apache 2.0"></a>
  <a href="https://github.com/Status-Page/Status-Page/releases/tag/v2.5.1"><img src="https://img.shields.io/badge/upstream-v2.5.1-1f6feb" alt="Upstream v2.5.1"></a>
</p>

<p align="center"><a href="#быстрый-старт">Быстрый старт</a> · <a href="#статус-проекта">Статус</a> · <a href="#документация">Документация</a> · <a href="README.md">English version</a></p>

> [!WARNING]
> Это неофициальный учебный fork. Upstream Status-Page архивирован; репозиторий закреплён на release `v2.5.1` и не заявляет upstream support.

## Для чего нужен этот репозиторий

Fork показывает практический путь от source-derived Status-Page runtime—Django/Gunicorn, RQ Worker, RQ Scheduler, PostgreSQL, Redis и NGINX—к AWS-дизайну с ECR, ECS Fargate, ALB, RDS, ElastiCache, Secrets Manager, Terraform, CloudWatch и GitHub Actions.

## Быстрый старт

Требования: Docker Desktop и Docker Compose.

```bash
cp .env.example .env
make up
make check
```

Открой [http://localhost:8081](http://localhost:8081). Используй `make logs` для просмотра services и `make down` для остановки; добавляй `-v` к Docker Compose только при намеренном удалении локальных данных.

### Граница IAM

Production roles `yinon-status-page-prod-ecs-execution` и
`yinon-status-page-prod-ecs-task` создаются и управляются вручную вне
Terraform. Terraform только получает их ARNs через private variables. Legacy
resources `statuspage-dev` и временная role
`yinon-status-page-iam-smoke-20260828` не переиспользуются и не изменяются.

Production Terraform state изолирован в encrypted, versioned, public-blocked S3
bucket с native S3 lockfiles. После проверенного teardown state пуст. Exact-domain
Cloudflare automation обновляет только `status.yifilter.uk` после пересоздания ALB; `10.42.0.0/16` — private
VPC address space и никогда не может быть public DNS target.

## Статус проекта

| Направление | Статус | Подтверждение |
| --- | --- | --- |
| Локальный runtime | Готово | Шесть services работают; `/healthz` и homepage возвращают HTTP 200. |
| Production ECS runtime | Automated lifecycle проверен; сейчас приостановлен | Revision `86d711d` пересоздан, deployed через approval/OIDC, health-checked и полностью уничтожен; remote state пуст. |
| ECS roles / task definitions | Ручной IAM bootstrap | Roles создаются вне Terraform; task definitions получают явные role ARNs. |
| Network и data plane | Live cycle проверен; сейчас отсутствует | Guarded scripts применили 54 foundation resources и 3 services, затем validated и уничтожили 57 resources. |
| ECR publishing и ECS deployment | Проверено | Image run `34030885146` и approved deploy run `34031224217` завершились успешно с разными manually managed OIDC roles. |
| Сканирование секретов | Готово | Gitleaks проверяет полную Git history в pull requests и `main`. |
| Качество Terraform | Готово | `fmt`, `validate` и recommended TFLint rules выполняются до cloud planning. |

## Документация

| Тема | English | Русский |
| --- | --- | --- |
| AWS architecture | [AWS architecture — English](https://github.com/yinon-mitin/Status-Page/blob/main/docs/ARCHITECTURE.md) | [AWS architecture — Russian](https://github.com/yinon-mitin/Status-Page/blob/main/docs/ARCHITECTURE.ru.md) |
| Technology index | [English](https://github.com/yinon-mitin/Status-Page/blob/main/docs/TECHNOLOGY_INDEX.md) | [Russian](https://github.com/yinon-mitin/Status-Page/blob/main/docs/TECHNOLOGY_INDEX.ru.md) |
| Infrastructure overview | [HTML page](https://github.com/yinon-mitin/Status-Page/blob/main/docs/PROJECT_INFRASTRUCTURE.html) | — |
| Automated production lifecycle | [Create, release, verify и destroy](https://github.com/yinon-mitin/Status-Page/blob/main/docs/PRODUCTION_LIFECYCLE.md) | — |
| Milestone audit | [English](https://github.com/yinon-mitin/Status-Page/blob/main/docs/MILESTONE_AUDIT.md) | [Russian](https://github.com/yinon-mitin/Status-Page/blob/main/docs/MILESTONE_AUDIT.ru.md) |
| Implementation log | [English](https://github.com/yinon-mitin/Status-Page/blob/main/docs/IMPLEMENTATION_LOG.md) | [Russian](https://github.com/yinon-mitin/Status-Page/blob/main/docs/IMPLEMENTATION_LOG.ru.md) |
| Thursday AWS status | [English](https://github.com/yinon-mitin/Status-Page/blob/main/docs/THURSDAY_STATUS.md) | [Russian](https://github.com/yinon-mitin/Status-Page/blob/main/docs/THURSDAY_STATUS.ru.md) |
| Terraform baseline | [README](https://github.com/yinon-mitin/Status-Page/blob/main/terraform/README.md) | — |

См. [CHANGELOG.md](CHANGELOG.md) для истории изменений и [UPSTREAM.ru.md](UPSTREAM.ru.md) для политики исходного кода.

## Структура репозитория

```text
assets/              Иконка проекта и visual assets
docker/              Entrypoint scripts и NGINX configuration
docs/                Architecture, audit и implementation logs
terraform/           AWS ECR, ECS и защищённая network infrastructure
.github/workflows/   Validation и OIDC-based ECR publishing
statuspage/          Django source из upstream v2.5.1
```

## Безопасность и лицензия

- Secret values не коммитятся; runtime secrets предназначены для Secrets Manager.
- ALB рассчитан на public subnets; ECS tasks остаются internal.
- RDS остаётся private (`publicly_accessible = false`) и принимает PostgreSQL traffic только от ECS security group.
- При активном runtime `status.yifilter.uk` остаётся HTTP-only demonstration endpoint. Сейчас runtime уничтожен, а ACM permissions по-прежнему отсутствуют. См. [`docs/HTTPS_LIMITATION.ru.md`](docs/HTTPS_LIMITATION.ru.md).
- Добавлены отдельный migration gate, CloudWatch dashboard/alarms, opt-in project-scoped AWS Budget `$300`, безопасный SNS→Telegram relay и semantic private RDS restore rehearsal. Budget/SNS delivery остаются permission-gated в учебном аккаунте. Текущий evidence-status указан в [`docs/PRODUCTION_READINESS.md`](docs/PRODUCTION_READINESS.md); implementation не выдаётся за live proof.
- Fork сохраняет upstream [Apache-2.0 licence](LICENSE.txt), source history и тег `upstream-v2.5.1`.
