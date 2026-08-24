# Аудит milestone среды и четверга

**Проверено:** 24 августа 2026 · **Revision репозитория:** `b2ee89f` до этого audit update

## Среда — локальный Docker runtime

| Acceptance criterion | Evidence | Результат |
| --- | --- | --- |
| Compose configuration валидна | `docker compose config --quiet` завершилась успешно. | Pass |
| Есть шесть runtime services | PostgreSQL, Redis, web, NGINX, RQ Worker и RQ Scheduler были running. | Pass |
| Работает public reverse-proxy path | `GET http://localhost:8081/` вернул HTTP 200. | Pass |
| Работает health endpoint | `GET http://localhost:8081/healthz` вернул `{"status": "ok"}` и HTTP 200. | Pass |
| Django configuration валидна | `docker compose exec -T web python manage.py check` не нашёл ошибок. | Pass |
| Build context без repository metadata | После исключения `.git` Docker передал application context 59.48 kB. | Pass |

**Вывод:** milestone среды завершён.

## Четверг — ECR, ECS foundation, Terraform и CI

| Acceptance criterion | Evidence | Результат |
| --- | --- | --- |
| ECR repositories | `statuspage-dev-app` и `statuspage-dev-nginx` существуют в `il-central-1`, имеют immutable tags и scan-on-push. | Pass |
| Image lifecycle | Оба repository сохраняют 30 последних `sha-*` images. | Pass |
| ECS foundation | Cluster `statuspage-dev` имеет статус `ACTIVE`; Container Insights включён. | Pass |
| Logging | CloudWatch log groups для web, worker и scheduler существуют с retention 30 дней. | Pass |
| Terraform quality | `terraform fmt -check` и `terraform validate` проходят. | Pass |
| CI | GitHub Actions Validate workflow для `b2ee89f` успешно завершился. | Pass |
| GitHub OIDC image publishing | Workflow существует и защищён до настройки `AWS_ROLE_TO_ASSUME`. | Pending account access |
| ECS roles / task definitions | IAM запрещает `iam:ListRolePolicies`; Terraform не может безопасно завершить role-policy management. | Blocked by IAM |
| ECS services | Намеренно выключены до готовности network, data, secrets и ALB inputs. | Not started by design |

**Вывод:** код четверга и AWS foundation без service layer завершены. Automatic ECR publishing и ECS task/service deployment ожидают задокументированного IAM/OIDC prerequisite; см. `THURSDAY_STATUS.ru.md`.
