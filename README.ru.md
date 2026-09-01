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

## Статус проекта

| Направление | Статус | Подтверждение |
| --- | --- | --- |
| Локальный runtime | Готово | Шесть services работают; `/healthz` и homepage возвращают HTTP 200. |
| ECR | Применено | Immutable app/NGINX repositories, scan-on-push и lifecycle policies. |
| ECS foundation | Применено | Cluster и CloudWatch log groups существуют; services выключены. |
| ECS roles / task definitions | Ручной IAM bootstrap | Roles создаются вне Terraform; task definitions получают явные role ARNs. |
| Network Terraform | Код готов, не применён | Защищён `create_network = false`. |
| ECR publishing | Готово, но ожидает доступ | Запустится после настройки GitHub OIDC role. |
| Сканирование секретов | Готово | Gitleaks проверяет полную Git history в pull requests и `main`. |
| Качество Terraform | Готово | `fmt`, `validate` и recommended TFLint rules выполняются до cloud planning. |

## Документация

| Тема | English | Русский |
| --- | --- | --- |
| AWS architecture | [AWS architecture — English](https://github.com/yinon-mitin/Status-Page/blob/main/docs/ARCHITECTURE.md) | [AWS architecture — Russian](https://github.com/yinon-mitin/Status-Page/blob/main/docs/ARCHITECTURE.ru.md) |
| Technology index | [English](https://github.com/yinon-mitin/Status-Page/blob/main/docs/TECHNOLOGY_INDEX.md) | [Russian](https://github.com/yinon-mitin/Status-Page/blob/main/docs/TECHNOLOGY_INDEX.ru.md) |
| Infrastructure overview | [HTML page](https://github.com/yinon-mitin/Status-Page/blob/main/docs/PROJECT_INFRASTRUCTURE.html) | — |
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
- Production HTTPS будет использовать `status.yifilter.uk` с Cloudflare DNS only и ACM certificate на ALB.
- Fork сохраняет upstream [Apache-2.0 licence](LICENSE.txt), source history и тег `upstream-v2.5.1`.
