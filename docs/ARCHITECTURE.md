# Yinon Final Project — Status-Page AWS Architecture

**Status:** approved direction; local Docker milestone complete · **Language:** English · **Date:** 24 August 2026

## Evidence boundary

- **Source-derived:** verified against the pinned official upstream release `v2.5.1` at the repository root; `reference/ARCHITECTURE.source.html` remains historical reference material.
- **Target decision:** proposed AWS design, to be validated in the AWS account before production use.

## Project overview

Status-Page is a Django modular monolith for public status, incidents, administration, and a REST API. The source runtime uses NGINX → Gunicorn/Django, PostgreSQL, Redis, RQ Worker, and RQ Scheduler.

**Pinned source:** official `Status-Page/Status-Page` release `v2.5.1` (29 October 2024), validated locally as Status-Page 2.5.1. The upstream project is archived and no longer receives security support; this is a documented project constraint.

The target is Docker + ECR + ECS Fargate + ALB/ACM + RDS PostgreSQL + ElastiCache Redis + Secrets Manager + IAM + CloudWatch + Terraform + GitHub Actions. NGINX remains in the web task.

## Current application — source-derived facts

- Django 5.1.2 on Python ≥ 3.10; Gunicorn serves `statuspage.wsgi` on `0.0.0.0:8001` inside the web container.
- NGINX redirects HTTP to HTTPS, serves `/static/` from disk, and proxies dynamic requests to Gunicorn.
- PostgreSQL is the single system of record.
- Redis DB 0 is the RQ broker (`high`, `default`, `low`); Redis DB 1 is Django cache.
- Separate processes run `manage.py rqworker high default low` and `manage.py rqscheduler`.
- `MEDIA_ROOT` is local disk and plugin sync work is not guaranteed concurrency-safe.
- Upstream Status-Page supports optional SMTP notifications.

## Target AWS architecture

```mermaid
flowchart TB
  U[Internet users / API clients] --> ALB[Public ALB / HTTPS 443]
  ACM[ACM certificate] -.-> ALB
  subgraph VPC[AWS VPC — two Availability Zones]
    subgraph PUB[Public subnets — il-central-1a and il-central-1b]
      ALB
      RDS[RDS PostgreSQL — publicly accessible setting / :5432]
    end
    subgraph APP[Private application subnets]
      WEB[ECS web / NGINX → Gunicorn-Django]
      WKR[ECS worker / RQ Worker]
      SCH[ECS scheduler / RQ Scheduler]
    end
    subgraph DATA[Private data subnets]
      REDIS[ElastiCache Redis :6379 / DB 0 queues · DB 1 cache]
    end
    SM[Secrets Manager]
    CW[CloudWatch]
  end
  ALB --> WEB
  WEB --> RDS & REDIS
  WKR --> RDS & REDIS
  SCH --> REDIS
  WEB & WKR & SCH -. secrets .-> SM
  WEB & WKR & SCH --> CW
```

The source three-process runtime is preserved. AWS services and delivery tooling are target decisions. The initial ECS targets are placed in `il-central-1a`; the ALB still attaches to public subnets in both `il-central-1a` and `il-central-1b`. ALB cross-zone load balancing remains enabled so the node in either AZ can route to the targets in AZ A.

## Decisions and components

| Area | Decision | Purpose / rationale |
|---|---|---|
| Docker + ECR | One image, Git-SHA tag | Reproducible web, worker, and scheduler commands from the same image. |
| ECS Fargate | Three ECS workloads | Managed containers without EC2 administration; one web, worker, and scheduler task initially. |
| ALB + ACM | Internet-facing ALB in two public subnets | HTTPS, HTTP redirect, certificate lifecycle, and `/healthz` checks. Target type is `ip`; cross-zone routing is explicitly enabled. |
| NGINX | In the web task | Keeps source `/static/` and Gunicorn reverse-proxy contract. |
| RDS PostgreSQL | Publicly accessible managed database | Meets the mentor-approved topology while its RDS SG allows port 5432 only from the ECS SG; no Internet CIDR rule is allowed. |
| ElastiCache Redis | Private managed Redis | Preserves source cache/queue split; port 6379 only from ECS. |
| Secrets Manager + IAM | Runtime credentials / least privilege | Store `SECRET_KEY`, database and Redis credentials, and approved external API keys only. |
| CloudWatch | Logs, metrics, alarms | Service health, restarts, capacity, RDS, and Redis visibility. |
| Terraform | Infrastructure as Code | Version-controlled VPC, subnets, SGs, services, data tier, logging, and outputs. |
| GitHub Actions + OIDC | CI/CD | Tests and deploys with short-lived AWS credentials. |
| EKS | Not selected | Kubernetes operational overhead is unnecessary for this small workload. |

**Worker and scheduler:** the worker runs `rqworker` for internal asynchronous work. The scheduler runs one `rqscheduler` task to avoid duplicate periodic jobs.

## Network and security model

- VPC `/16` across two AZs. The internet-facing ALB uses public subnets in both AZs. ECS tasks stay in internal application subnets; the initial tasks run only in `il-central-1a`. ElastiCache stays private.
- The ALB target group uses HTTP port 80, target type `ip`, cross-zone load balancing, and `/healthz` with matcher `200`, 15-second interval, healthy threshold 2, and unhealthy threshold 3.
- Security groups allow Internet → ALB (80/443), ALB SG → ECS web SG (80), ECS SG → RDS SG (5432), and ECS SG → Redis SG (6379).
- RDS is configured as publicly accessible and placed in a suitable DB subnet group, but its SG has no public CIDR ingress: database access is admitted only when the source carries the ECS SG. Redis has no public endpoint. Worker egress is restricted to approved HTTPS integrations.
- Use ACM TLS, RDS encryption and backups, compatible Redis TLS/authentication, IAM least privilege, GitHub OIDC, MFA for humans, and Secrets Manager.
- Preserve Django proxy/security settings, CSRF, secure cookies, and source OTP/TOTP protections.

## CI/CD

**Application:** test → Docker build → smoke test → GitHub OIDC → ECR SHA image → ECS task definition → rolling deployment → ECS/ALB health verification.

**Infrastructure:** `terraform fmt -check` → `terraform init` → `terraform validate` → static/security checks → reviewed plan → protected approved apply.

Rollback redeploys the prior known-good SHA. Run database migrations as a controlled ECS one-off task.

## Terraform layout

```text
terraform/
├── versions.tf  providers.tf  backend.tf  variables.tf  outputs.tf
├── environments/{dev,prod}/
└── modules/{network,security-groups,ecr,alb,ecs,rds,redis,iam,secrets,monitoring}/
```

Use remote state and locking. Secrets must not be placed in `*.tfvars`.

## Constraints and roadmap

- **Completed Wednesday milestone:** Docker images and Docker Compose run web, worker, scheduler, PostgreSQL, Redis, NGINX, migrations, static files, `/healthz`, and an executed RQ smoke job locally.
- Start with one task per runtime role. Scale only after media is durable (S3/EFS or a formal restriction) and worker jobs are idempotent/locked.
- Redis is on the request critical path; test recovery. Confirm AWS region, domain, budget, retention, RPO/RTO, and approved external HTTPS integrations.

| Phase | Milestone | Acceptance criteria |
|---|---|---|
| 0 | Decisions | Scope and risk register are recorded. |
| 1 | Local runtime — complete | Complete Docker Compose stack works and returns HTTP 200 through NGINX. |
| 2 | Container — complete | One application image starts three roles; a separate NGINX image fronts web; no production secrets are in either image. |
| 3 | Foundation | Terraform creates network, SGs, state, and tags. |
| 4 | Data | Publicly accessible RDS restricted to ECS SG and private Redis pass migration, cache, and queue tests. |
| 5 | ECS/ingress | Stable tasks, ALB/ACM HTTPS, and health checks work. |
| 6 | CI/CD | OIDC, reviewed deploy, logs, alarms, and rollback are tested. |
| 7 | Validation | Implementation matches the architecture and is reproducible. |

## References

- `reference/ARCHITECTURE.source.html` — authoritative current architecture reference.
- repository root — pinned official upstream source release v2.5.1.
- `TECHNOLOGY_INDEX.md` — English technology index.
- `TECHNOLOGY_INDEX.ru.md` — Russian technology index.
