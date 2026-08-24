# Журнал реализации

Этот журнал объясняет, почему в проект вносятся изменения, что было проверено и какие ограничения остаются. `CHANGELOG.md` содержит краткую историю изменений.

## 2026-08-24 — Локальный runtime milestone среды

**Решение:** использовать один application image для Django/Gunicorn, RQ Worker и RQ Scheduler; отдельный NGINX image использовать как reverse proxy.

**Почему:** это соответствует source-derived runtime roles и сохраняет одинаковую модель для локального Docker Compose и будущих ECS task definitions.

**Проверка:** полный Compose stack успешно собирался; NGINX возвращал HTTP 200 для homepage и `/healthz`; Django system checks проходили.

## 2026-08-24 — ECR/ECS и CI foundation четверга

**Решение:** использовать immutable ECR images с SHA tags и GitHub OIDC вместо long-lived AWS access keys.

**Почему:** каждый deployable image связан с конкретным commit, а GitHub получает temporary AWS credentials только через narrowly scoped role.

**Проверка:** GitHub Actions validation успешно завершился для commit `b2ee89f`. В AWS уже созданы два ECR repositories, lifecycle policies, ECS cluster и CloudWatch log groups.

**Ограничение:** текущий IAM identity может создать roles, но получает отказ для `iam:ListRolePolicies`; Terraform не может безопасно завершить role-policy management или зарегистрировать task definitions. Точные требуемые permissions записаны в `THURSDAY_STATUS.ru.md`.

## 2026-08-24 — Исправление Docker build context

**Решение:** исключить `.git` из Docker build context.

**Почему:** Git history не должна попадать в application images и увеличивала local build context примерно до 687 MB. Исключение уменьшает передачу данных при сборке, предотвращает попадание repository metadata в image и ускоряет CI/ECR builds.

**Проверка:** Compose stack был пересобран с application build context 59.48 kB. Все шесть services были up; `/healthz` и homepage вернули HTTP 200; `manage.py check` прошёл.

## 2026-08-24 — Network code подготовлен, но не применён

**Решение:** определить в Terraform две public ALB subnets и две internal ECS application subnets, выключенные по умолчанию.

**Почему:** это напрямую реализует согласованное размещение: public ALB в `il-central-1a`/`il-central-1b`, private ECS tasks и traffic ALB-to-ECS только через security groups. `create_network = false` предотвращает непроверенное создание VPC resources и network cost, пока IAM/OIDC не завершены.

**Проверка:** прошли `terraform fmt -recursive`, `terraform validate` и `docker compose config --quiet`. Этот change не создал AWS network resource.

## 2026-08-24 — Оформление репозитория и навигация по документации

**Решение:** переработать основной English README и его Russian counterpart как параллельные точки входа в проект с явными ссылками на документы на соответствующем языке.

**Почему:** читатель должен видеть назначение проекта, подтверждённый статус, быстрый старт и authoritative documentation без поиска по репозиторию. Russian README не должна отправлять читателя к English documents, когда перевод существует.

**Реализация:** добавлены project icon, CI/licence/upstream badges, краткая navigation, честная таблица delivery status и матрица English/Russian documentation. Стиль README использует полезные паттерны Awesome README: понятную visual identity, короткое описание, badges, navigation, quick start и структурированные ссылки.
