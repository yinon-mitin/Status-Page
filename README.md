# Yinon Final DevOps Project

This is an unofficial educational DevOps fork of [Status-Page](https://github.com/Status-Page/Status-Page). It contains the application source together with a Docker, AWS ECS/Fargate, Terraform, and CI/CD implementation.

## Documentation

- [AWS architecture — English](docs/ARCHITECTURE.md)
- [AWS architecture — Russian](docs/ARCHITECTURE.ru.md)
- [Technology index — English](docs/TECHNOLOGY_INDEX.md)
- [Technology index — Russian](docs/TECHNOLOGY_INDEX.ru.md)
- [Interactive project and infrastructure overview](docs/PROJECT_INFRASTRUCTURE.html)
- [Upstream provenance and maintenance policy](UPSTREAM.md)
- [Thursday Terraform baseline](terraform/README.md)
- [Thursday implementation status — English](docs/THURSDAY_STATUS.md)
- [Thursday implementation status — Russian](docs/THURSDAY_STATUS.ru.md)
- [Changelog](CHANGELOG.md)
- [Implementation log — English](docs/IMPLEMENTATION_LOG.md)
- [Implementation log — Russian](docs/IMPLEMENTATION_LOG.ru.md)
- [Wednesday/Thursday milestone audit — English](docs/MILESTONE_AUDIT.md)
- [Wednesday/Thursday milestone audit — Russian](docs/MILESTONE_AUDIT.ru.md)
- [Pinned application source: upstream Status-Page v2.5.1](https://github.com/Status-Page/Status-Page/releases/tag/v2.5.1)

The architecture document distinguishes facts derived from the supplied Status-Page source and decisions approved for the AWS target deployment. The infrastructure diagram uses Mermaid and can be viewed in GitHub, GitLab, or a Mermaid-compatible Markdown preview.

## Local Docker milestone

The Wednesday milestone is implemented: Docker Compose runs NGINX, Django/Gunicorn, RQ Worker, RQ Scheduler, PostgreSQL, and Redis.

```bash
cp .env.example .env
docker compose up --build -d
curl http://localhost:8081/healthz
docker compose ps
```

Open `http://localhost:8081`. Stop the stack with `docker compose down`; add `-v` only when intentionally deleting local PostgreSQL, Redis, static, and media volumes. Set `STATUSPAGE_HTTP_PORT` and the matching `STATUS_PAGE_SITE_URL` in `.env` to use another host port.

## Target architecture at a glance

Docker → Amazon ECR → Amazon ECS Fargate, with an internet-facing ALB in two public subnets and ECS in internal application subnets. RDS PostgreSQL is configured publicly accessible but allows port 5432 only from the ECS security group; ElastiCache Redis remains private. NGINX runs inside the web task, with Secrets Manager, IAM, CloudWatch, Terraform, and GitHub Actions completing the platform.

## Thursday milestone

The ECR/ECS and CI foundations are implemented as code. Terraform creates the immutable ECR repositories, ECS cluster, task definitions, CloudWatch log groups, and least-privilege ECS roles. GitHub Actions validates Docker/Terraform on pull requests and publishes both images to ECR through GitHub OIDC after the required repository variables and AWS role exist. No AWS resource is applied automatically, and ECS services remain disabled until the reviewed network, database, Redis, ALB, and Secrets Manager inputs are available.

## Source version policy

The application at the repository root is pinned to the official stable upstream release **v2.5.1** (29 October 2024), rather than the earlier instructional archive. Upstream was archived in October 2025 and its stated security support ended on 31 December 2025; the final project therefore treats v2.5.1 as a fixed, auditable dependency rather than an actively maintained product.
