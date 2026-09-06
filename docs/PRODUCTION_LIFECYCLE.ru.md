# Автоматизированный production lifecycle

[English version](PRODUCTION_LIFECYCLE.md)

## Область действия

Production runtime воспроизводим после однократной подготовки трёх внешних составляющих:

1. encrypted и versioned S3 bucket для backend;
2. вручную управляемых ECS execution/task roles и GitHub OIDC roles;
3. Django secret в Secrets Manager.

Terraform не управляет IAM roles или policies. Он создаёт VPC, endpoints, ALB, ECR, ECS definitions и services, RDS, Redis, log groups и resource policy, которая даёт точной ECS execution role доступ к новому RDS master secret.

Один раз вручную подготавливаются четыре роли:

- ECS execution role с trust для ECS tasks, стандартной execution policy и доступом к внешнему Django secret;
- ECS task role с trust для ECS tasks и без широких application permissions;
- GitHub publisher с branch-bound OIDC trust и правом только на ECR push;
- GitHub deployer с таким же branch-bound OIDC trust, правами ECS describe/register/update и `iam:PassRole` только для двух ECS roles.

Учебный account не разрешает проекту изменять IAM. Нельзя добавлять IAM resources в Terraform или расширять роли как обходной путь.

## Проверки безопасности

- Каждый сохранённый plan преобразуется в JSON и проверяется `scripts/validate_terraform_plan.py`.
- Каждый mutating script требует clean checkout, точно совпадающий с `origin/main`, учитывает untracked files и отклоняет неявные `*.auto.tfvars*` в Terraform root.
- Create mode отклоняет delete actions, Terraform IAM resources, идентификатор state bucket, protected role и `statuspage-dev-*`.
- Destroy требует точного подтверждения `yinon-status-page-prod`.
- Сначала destroy применяет target-limited preparation plan. Он может только отключить ALB/RDS deletion protection, разрешить удаление images в двух production ECR repositories и установить уникальное имя final RDS snapshot.
- Второй plan разрешает только delete actions и после применения проверяет пустой Terraform state.
- После teardown `PRODUCTION_ENABLED=false` останавливает GitHub publication и deployment.

## Конфигурация

Создай игнорируемый private input из примера и замени только placeholders account, roles и secret:

```bash
cp terraform/environments/prod.tfvars.example terraform/prod.tfvars
```

Не добавляй database/Redis endpoints или RDS password ARN. При каждом создании Terraform получает актуальные endpoints и ARN управляемого RDS secret.

## Создание

Из clean checkout `origin/main`:

```bash
AWS_PROFILE=status-page scripts/production_create.sh
```

Команда:

1. применяет проверенную инфраструктуру с выключенными ECS services;
2. включает release gate и запускает OIDC image-only build для точного `main`;
3. запускает private one-off migration task с exact immutable application image;
4. создаёт ECS services только после migration exit `0` и exact-SHA evidence;
5. передаёт generated ALB DNS name в workflow health check;
6. ждёт стабилизации всех services и проверяет `/healthz` через provider endpoint.

При наличии scoped Cloudflare credentials create обновляет только DNS-only CNAME `status.yifilter.uk` на generated ALB. Без credentials DNS step явно пропускается, а ALB DNS остаётся достаточным для проверки lifecycle.

One-off migration использует operator identity, потому что immutable GitHub deployer role не имеет `ecs:RunTask` или `ecs:DescribeTasks`. Процесс завершается с ошибкой, если calls недоступны, и не возвращается незаметно к параллельным migrations при запуске web tasks.

## Подтверждённый релиз

Для approval и deployment одной точной revision:

```bash
SHA="$(git rev-parse origin/main)"
CONFIRM_PRODUCTION_APPROVAL="$SHA" scripts/production_release.sh
```

GitHub Environment approval выполняется в отдельном job. Следующий deploy job не связан с Environment, поэтому его OIDC token сохраняет branch-bound subject, разрешённый deployer role. Успешный publish job подтверждает наличие immutable images. Deployment script регистрирует три task definitions, стабилизирует web до workers, проверяет health и при ошибке возвращает изменённые services на предыдущие task definitions.

После bootstrap revisions task definitions принадлежат GitHub Actions. Terraform игнорирует только атрибут `task_definition` уже существующих services, чтобы infrastructure apply не откатывал release. Создание services, networking, desired counts и destroy остаются под управлением Terraform. Destroy script очищает все revisions точных production task-definition families независимо от того, какой процесс их создал.

### Выполнение миграций

Immutable GitHub deployer role не может вызывать `ecs:RunTask`, а IAM нельзя изменять. Operator lifecycle запускает отдельную private migration task через согласованный AWS profile и записывает exact-SHA evidence до dispatch workflow. В production startup migrations отключены для web tasks; local Compose сохраняет их по умолчанию. Rollback image не откатывает schema migration, поэтому production migrations должны оставаться backward-compatible.

## Удаление

```bash
CONFIRM_DESTROY=yinon-status-page-prod \
AWS_PROFILE=status-page \
scripts/production_destroy.sh
```

State bucket, manually managed IAM roles, внешний Django secret, final RDS snapshots и Cloudflare record сохраняются. RDS snapshots, Secrets Manager и S3 versions могут создавать небольшие storage charges и требуют отдельного решения о сроке хранения.

## Стандарт проверки

Lifecycle считается доказанным, только когда одна точная revision имеет все следующие evidence:

- static checks и contract tests прошли;
- create plan validation не содержит deletes;
- AWS read-back показывает stable ECS services и HTTP 200;
- private one-off migration завершилась для exact image revision;
- approved GitHub run использовал deployer role и завершил rollout;
- destroy plan validation содержит только deletes;
- после teardown Terraform state пуст;
- protected и manually managed resources сохранились.

## Проверенный rehearsal

Revision `de3ba39d4f953ce8baa6e73167361d2063302a64` прошла полный процесс:

- publication images: GitHub run `34041754952`;
- private migration task: exact revision записана до deployment;
- reviewer approval и deployer OIDC rollout: GitHub run `34043025336`;
- stable services: web `2/2`, worker `1/1`, scheduler `1/1`;
- provider health: два healthy ALB targets и успешный `/healthz`;
- monitoring: CloudWatch dashboard и 18 alarms прошли API read-back;
- recovery: temporary private RDS restore содержал exact semantic probe и Django migration history, после чего был полностью очищен;
- idempotency: Terraform сообщил об отсутствии изменений до teardown;
- destroy: удалено 76 resources, Terraform state стал пустым, revisions точных task-definition families отсутствовали.
