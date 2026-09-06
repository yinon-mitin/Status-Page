# Подтверждение реализации

[English version](DELIVERY_EVIDENCE.md)

Этот документ фиксирует результат проверки проекта на реальном AWS. Runtime был намеренно удалён после rehearsal, поэтому evidence подтверждает воспроизводимость реализации, а не существование постоянно работающей среды.

## Что проверено

| Область | Результат |
| --- | --- |
| Local runtime | Docker Compose запускает PostgreSQL, Redis, Django/Gunicorn, NGINX, RQ Worker и RQ Scheduler |
| Application health | Homepage, `/healthz`, static assets, Django checks и RQ smoke job проходят |
| Infrastructure create | Terraform создаёт network, data, compute и monitoring resources из clean state |
| Immutable images | Application и NGINX images публикуются в ECR с exact Git SHA |
| Database migration | Private one-off Fargate task выполняет migrations до service rollout |
| ECS runtime | Web `2/2`, worker `1/1`, scheduler `1/1`; rollouts завершаются успешно |
| Monitoring | CloudWatch dashboard и 18 alarms проходят direct API read-back |
| Controlled release | GitHub Environment approval и отдельная branch-bound OIDC role обновляют ECS |
| Backup restore | Snapshot восстанавливается в disposable private RDS; probe и Django migrations найдены |
| Idempotency | Refreshed Terraform plan возвращает `No changes` |
| Teardown | Guarded destroy удаляет runtime и возвращает Terraform state к `0` |

## Проверенный lifecycle

```text
clean origin/main
  -> reviewed Terraform create
  -> immutable ECR publication
  -> private migration task
  -> ECS and ALB health
  -> monitoring read-back
  -> approved OIDC deployment
  -> semantic RDS restore
  -> Terraform no changes
  -> guarded destroy
  -> empty state
```

## Recovery после destroy

После удаления runtime были сохранены только заранее определённые recovery и bootstrap resources:

- encrypted versioned remote-state bucket;
- manually managed ECS и GitHub OIDC roles;
- Django runtime secret;
- encrypted final RDS snapshot.

В конце rehearsal отсутствие ECR repositories, ECS services, ALB, RDS instance, Redis, VPC, dashboard и alarms было проверено через AWS API.

## Проверки репозитория

CI выполняет:

- Docker Compose configuration и image builds;
- полный runtime smoke test;
- application tests;
- documentation build;
- production automation contract tests;
- Terraform formatting, validation и TFLint;
- Gitleaks scan полной Git history.

`main` защищён pull request и обязательными checks. Production deployment требует отдельного Environment approval.

## Воспроизведение

Операторские команды и safety gates описаны в [PRODUCTION_LIFECYCLE.ru.md](PRODUCTION_LIFECYCLE.ru.md). Точная архитектура находится в [ARCHITECTURE.ru.md](ARCHITECTURE.ru.md).
