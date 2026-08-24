# Статус milestone на четверг

**Дата:** 24 августа 2026 · **AWS account:** `992382545251` · **Region:** `il-central-1`

## Готово в AWS

- ECR repository `statuspage-dev-app` — включены immutable tags и scan on push.
- ECR repository `statuspage-dev-nginx` — включены immutable tags и scan on push.
- ECR lifecycle policies — сохраняют последние 30 image с тегом `sha-*`.
- ECS cluster `statuspage-dev` — active, а его configuration зафиксирована в Terraform.
- CloudWatch log groups для web, worker и scheduler — retention 30 дней.

## Реализовано в репозитории

- Terraform configuration для ECR/ECS baseline, трёх task definitions, runtime secrets injection и намеренно выключенного ECS-service layer.
- Docker/Terraform validation workflow для pull request и `main`.
- ECR publishing workflow через GitHub OIDC, SHA image tags и Buildx cache. Job намеренно пропускается, пока ARN OIDC role не задан как repository variable.
- Account-specific теги `Owner=yinon` на AWS resources, которые поддерживают resource tagging.

## Обнаруженный account guardrail

Account требует owner tag при создании ресурса. Первый Terraform apply показал это ограничение; код был обновлён, и второй apply завершил ECR, ECS cluster и log groups.

Текущий IAM user может создать две ECS roles, но получает отказ для `iam:ListRolePolicies`. Поэтому Terraform не может безопасно refresh roles и прикрепить managed execution policy; он остановился до создания task definitions. Это IAM permission boundary, а не ошибка Terraform или приложения.

Перед следующим apply запроси минимально необходимые permissions для project roles:

- `iam:GetRole`, `iam:ListRolePolicies`, `iam:GetRolePolicy`, `iam:ListAttachedRolePolicies` и `iam:AttachRolePolicy` для `statuspage-dev-ecs-task` и `statuspage-dev-ecs-execution`;
- `iam:ListOpenIDConnectProviders` и `iam:GetOpenIDConnectProvider` для проверки GitHub OIDC; `iam:CreateOpenIDConnectProvider` — только если в account ещё нет `token.actions.githubusercontent.com`.

Ни один ECS service не создан. RDS, Redis, ALB, VPC/subnets, Secrets Manager и application tasks остаются за пределами текущего этапа Terraform.

## Следующая команда после исправления IAM access

```bash
cd terraform
terraform apply
```

Затем задай созданный ARN GitHub OIDC publishing role как `AWS_ROLE_TO_ASSUME` в repository variables. Следующий push в `main` опубликует оба image в ECR repositories.
