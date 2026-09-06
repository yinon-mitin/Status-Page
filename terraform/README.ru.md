# AWS-инфраструктура

[English version](README.md)

Этот Terraform root описывает воспроизводимую AWS-среду Status-Page в регионе `il-central-1`.

## Управляемые компоненты

- VPC в двух Availability Zones;
- public subnets для Application Load Balancer;
- private application subnets для ECS Fargate;
- private data subnets для RDS PostgreSQL и ElastiCache Redis;
- VPC endpoints для ECR, S3, CloudWatch Logs и Secrets Manager;
- immutable ECR repositories;
- ECS cluster, task definitions и сервисы web, worker и scheduler;
- CloudWatch log groups, dashboard и alarms;
- опциональные SNS notifications и AWS Budget.

Terraform получает ARN ECS execution role и task role через variables. Эти роли, remote-state bucket и application secret подготавливаются один раз за пределами этого root.

## Конфигурация

Из корня репозитория скопируй безопасный пример в игнорируемый локальный файл:

```bash
cp terraform/environments/prod.tfvars.example terraform/prod.tfvars
```

Заполни deployment-specific значения в `terraform/prod.tfvars`. Нельзя коммитить этот файл, state, plans или credentials.

Инициализируй S3 backend с согласованным bucket и state key:

```bash
terraform -chdir=terraform init \
  -backend-config="bucket=<state-bucket>" \
  -backend-config="key=yinon-status-page/prod/terraform.tfstate" \
  -backend-config="region=il-central-1" \
  -backend-config="encrypt=true" \
  -backend-config="use_lockfile=true"
```

## Lifecycle

Используй repository scripts из корня проекта, а не произвольные Terraform commands:

```bash
scripts/production_create.sh
SHA="$(git rev-parse origin/main)"
CONFIRM_PRODUCTION_APPROVAL="$SHA" scripts/production_release.sh
CONFIRM_RESTORE_TEST="$SHA" scripts/production_backup_restore_test.sh
CONFIRM_DESTROY=yinon-status-page-prod scripts/production_destroy.sh
```

Scripts проверяют ожидаемую revision репозитория, AWS account, префиксы ресурсов и форму плана. Создание разбито на этапы: сначала появляются ECR repositories, затем публикуются immutable images и запускаются ECS services. Перед rollout web, worker и scheduler релиз выполняет отдельную one-off migration task. При удалении scripts сначала подготавливают защищённые ресурсы, затем применяют новый delete-only plan и проверяют пустой state.

## Прямые проверки Terraform

```bash
terraform -chdir=terraform fmt -check -recursive
terraform -chdir=terraform validate
tflint --chdir=terraform --config=.tflint.hcl
```

Production plans сохраняются вне репозитория и проходят `scripts/validate_terraform_plan.py` до apply.

## Runtime layout

- ALB принимает публичный HTTP traffic и передаёт его web service на TCP `80`.
- ECS tasks не имеют public IP.
- RDS принимает TCP `5432` только от ECS security group.
- Redis принимает TCP `6379` только от ECS security group.
- Web service запускает NGINX и Django/Gunicorn в одной task.
- Worker и scheduler используют application image с другими commands.

## State и восстановление

Обычный destroy удаляет управляемый Terraform runtime. Отдельно подготовленные state bucket, roles и application secret сохраняются вместе с RDS final snapshot. Благодаря этому среду можно создать заново, не смешивая долговечные recovery assets с временным демонстрационным runtime.

Полная инструкция находится в [production lifecycle](../docs/PRODUCTION_LIFECYCLE.ru.md), а устройство системы — в [архитектуре](../docs/ARCHITECTURE.ru.md).
