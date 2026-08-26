# Индекс технологий — финальный DevOps-проект Yinon

Этот индекс определяет каждую технологию и operational term, используемые в предложенной AWS-архитектуре Status-Page. Он отделяет текущее приложение от целевого deployment.

## Метки источника

- **Факт из исходника** — подтверждён закреплённым official upstream release `v2.5.1` в корне репозитория; `reference/ARCHITECTURE.source.html` — historical reference material.
- **Целевое решение** — выбрано для AWS deployment финального проекта.

## Runtime приложения

| Технология / термин | Тип | Источник | Назначение в проекте |
|---|---|---|---|
| Django 5.1.2 | Python web framework | Факт из исходника | Предоставляет модульный монолит, страницы, административный интерфейс и REST API. |
| Python ≥ 3.10 | Programming language/runtime | Факт из исходника | Запускает Django, worker, scheduler и management commands. |
| Gunicorn | WSGI application server | Факт из исходника | Запускает процесс Django `statuspage.wsgi` для динамических HTTP requests. |
| WSGI | Web Server Gateway Interface | Факт из исходника | Стандартный интерфейс между Gunicorn и Django. |
| NGINX | Web server / reverse proxy | Факт из исходника + целевое решение | Отдаёт `/static/`, передаёт dynamic traffic в Gunicorn и сохраняет proxy headers. В AWS остаётся в web task, а ALB обрабатывает public TLS. |
| DRF | Django REST Framework | Факт из исходника | Предоставляет REST API endpoints приложения. |
| PostgreSQL | Relational database | Факт из исходника | Единственный system of record для данных Status-Page. |
| Redis | In-memory data store | Факт из исходника | Содержит logical DB 0 для RQ queues и DB 1 для Django cache. |
| RQ | Redis Queue | Факт из исходника | Python queue для асинхронных jobs: notifications, automation и plugin polls. |
| RQ Worker | Background process | Факт из исходника | Запускает `rqworker high default low`; берёт jobs из Redis и выполняет асинхронную работу. |
| RQ Scheduler | Background process | Факт из исходника | Запускает `rqscheduler`; регистрирует и выпускает периодические jobs. |
| SMTP | Simple Mail Transfer Protocol | Факт из исходника | Optional upstream Status-Page capability для notification email. |
| `/static/` | Static asset path | Факт из исходника | Содержит собранные CSS, JavaScript и image assets, отдаваемые NGINX. |
| `MEDIA_ROOT` | Django media storage directory | Факт из исходника | Текущее local-disk хранилище user-uploaded media; не сохраняется при замене ECS task. |

## Целевая AWS-платформа

| Технология / термин | Расшифровка | Назначение в проекте |
|---|---|---|
| AWS | Amazon Web Services | Облачная платформа для target deployment. |
| Docker | Container platform | Упаковывает приложение и dependencies в воспроизводимый image. |
| ECR | Elastic Container Registry | Хранит versioned Docker images с Git commit SHA tags. |
| ECS | Elastic Container Service | Orchestrates container workloads web, worker и scheduler. |
| Fargate | Serverless ECS compute engine | Запускает ECS tasks без управления EC2 hosts. |
| ALB | Application Load Balancer | Internet-facing HTTP/HTTPS entry point в двух public subnets; redirect port 80, TLS on 443 и routing к ECS IP targets. |
| ACM | AWS Certificate Manager | Выпускает и обновляет TLS certificate для ALB. |
| RDS | Relational Database Service | Предоставляет private managed PostgreSQL с encryption, patching и двухдневными automated backups. RDS SG разрешает 5432 только от ECS SG. |
| ElastiCache for Redis | Managed Redis service | Предоставляет managed Redis, совместимый с существующим queue/cache split. |
| Secrets Manager | AWS secret store | Хранит database, Django, Redis и approved external API credentials. |
| IAM | Identity and Access Management | Предоставляет least-privilege permissions людям, GitHub Actions, ECS task execution и application tasks. |
| VPC | Virtual Private Cloud | Private AWS network boundary проекта. |
| Subnet | VPC network segment | Разделяет public placement ALB, internal ECS applications и private RDS/Redis в двух AZ. |
| AZ | Availability Zone | Независимая AWS location для повышения resilience. |
| Security Group | Stateful virtual firewall | Разрешает только paths Internet → ALB → ECS → RDS/Redis. |
| SG reference | Security-group-to-security-group rule | Разрешает RDS port 5432 для ECS SG без открытия database для Internet CIDR range. |
| Target group | Набор backend destinations ALB | Регистрирует IP addresses ECS tasks на HTTP port 80 и проверяет `/healthz`. |
| ECS task spread | Размещение по Availability Zones | Размещает две web task в internal subnets `il-central-1a` и `il-central-1b` для compute-level availability. |
| `/healthz` | Application health endpoint | Возвращает HTTP 200 без database query и используется проверками Docker, ECS и ALB. |
| VPC endpoint | PrivateLink / gateway connection | Позволяет private ECS tasks обращаться к ECR, CloudWatch Logs, Secrets Manager и S3 без NAT и public IPs. |
| NAT Gateway | Managed outbound network translation | Опционален и по умолчанию выключен; используется только временно, если приложению нужны произвольные public HTTPS services. |
| Cloudflare DNS only | Authoritative DNS configuration | Хранит DNS records `status.yifilter.uk`, а traffic завершается напрямую на ALB с ACM TLS. |
| CloudWatch | AWS observability service | Хранит logs и metrics; запускает alarms при проблемах service/data tier. |
| CloudTrail | AWS audit service | Записывает AWS management API activity для security и traceability. |
| DNS | Domain Name System | Связывает project domain с ALB. |

## Delivery и infrastructure

| Технология / термин | Расшифровка | Назначение в проекте |
|---|---|---|
| Terraform | Infrastructure as Code tool | Описывает, проверяет и создаёт AWS resources единообразно. |
| IaC | Infrastructure as Code | Практика хранения infrastructure definitions в version control. |
| Remote state | Shared Terraform state storage | Нужен перед Terraform apply из GitHub Actions: encrypted versioned S3 backend сохраняет state, а native S3 lockfiles заменяют DynamoDB locking. |
| GitHub Actions | CI/CD automation platform | Запускает tests, builds images, pushes в ECR, validates Terraform и deploys ECS services. |
| CI/CD | Continuous Integration / Continuous Delivery | Автоматизированный путь от reviewed code change к verified deployment. |
| OIDC | OpenID Connect | Позволяет GitHub Actions получать short-lived AWS credentials без long-lived access keys. |
| SHA | Secure Hash Algorithm commit identifier | Используется как immutable-ish Docker image version tag. |
| Health check | Service availability probe | Позволяет ALB/ECS обнаружить неработающий web task. |
| Rolling deployment | Incremental service replacement | Постепенно заменяет ECS tasks и позволяет controlled rollback. |
| Migration | Database schema change | Должна запускаться controlled ECS one-off task или release step. |

## Важные правила архитектуры

1. Один Docker image переиспользуется для web, worker и scheduler с разными commands.
2. Web service начинает с двух task в двух AZ; worker и scheduler остаются по одной task из-за local-media и worker-concurrency constraints исходника.
3. Public остаётся только ALB. ECS, RDS и Redis private; RDS использует `publicly_accessible = false`.
4. Secrets никогда не попадают в Git, Docker layers, обычные Terraform variables или logs.
5. RDS и Redis принимают application traffic только от ECS security group; ECS использует VPC endpoints для обязательного AWS-service egress.
6. EKS намеренно не выбран: его operational complexity не оправдана для этого небольшого workload.

## Основные источники

- `reference/ARCHITECTURE.source.html` — текущая system architecture Status-Page reference.
- корень репозитория — закреплённый официальный upstream source v2.5.1, включая `contrib/` runtime configurations и installation documentation.
- `ARCHITECTURE.md` и `ARCHITECTURE.ru.md` — отдельные English/Russian AWS architecture и implementation roadmap.
