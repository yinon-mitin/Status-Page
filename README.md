<p align="center"><img src="assets/statuspage-devops-icon.png" width="150" alt="Status-Page DevOps icon"></p>

<h1 align="center">Status-Page DevOps</h1>

<p align="center">Production-minded AWS infrastructure for the open-source Status-Page application.</p>

<p align="center">
  <a href="https://github.com/yinon-mitin/Status-Page/actions/workflows/ci.yml"><img src="https://github.com/yinon-mitin/Status-Page/actions/workflows/ci.yml/badge.svg?branch=main" alt="Validate workflow"></a>
  <a href="https://github.com/yinon-mitin/Status-Page/blob/main/LICENSE.txt"><img src="https://img.shields.io/badge/license-Apache--2.0-blue.svg" alt="Apache 2.0 license"></a>
  <a href="https://github.com/Status-Page/Status-Page/releases/tag/v2.5.1"><img src="https://img.shields.io/badge/upstream-v2.5.1-1f6feb" alt="Upstream v2.5.1"></a>
</p>

<p align="center"><a href="#quick-start">Quick start</a> · <a href="#project-status">Status</a> · <a href="#documentation">Documentation</a> · <a href="README.ru.md">Русская версия</a></p>

> [!WARNING]
> This is an unofficial educational fork. Upstream Status-Page is archived; this repository pins the auditable release `v2.5.1` and does not claim upstream support.

## Why this repository exists

This fork demonstrates a practical path from the source-derived Status-Page runtime—Django/Gunicorn, RQ Worker, RQ Scheduler, PostgreSQL, Redis, and NGINX—to an AWS design using ECR, ECS Fargate, ALB, RDS, ElastiCache, Secrets Manager, Terraform, CloudWatch, and GitHub Actions.

## Quick start

Prerequisites: Docker Desktop and Docker Compose.

```bash
cp .env.example .env
docker compose up --build -d
curl http://localhost:8081/healthz
docker compose ps
```

Open [http://localhost:8081](http://localhost:8081). Stop with `docker compose down`; use `-v` only when intentionally deleting local data.

## Project status

| Area | Status | Evidence |
| --- | --- | --- |
| Local runtime | Complete | Six services run; `/healthz` and homepage return HTTP 200. |
| ECR | Applied | Immutable app/NGINX repositories with scan-on-push and lifecycle policies. |
| ECS foundation | Applied | Cluster and CloudWatch log groups exist; services remain disabled. |
| ECS roles / task definitions | IAM-blocked | Current identity lacks `iam:ListRolePolicies`. |
| Network Terraform | Code complete, not applied | Guarded by `create_network = false`. |
| ECR publishing | Ready, gated | Runs after GitHub OIDC role configuration. |

## Documentation

| Topic | English | Russian |
| --- | --- | --- |
| AWS architecture | [AWS architecture — English](https://github.com/yinon-mitin/Status-Page/blob/main/docs/ARCHITECTURE.md) | [AWS architecture — Russian](https://github.com/yinon-mitin/Status-Page/blob/main/docs/ARCHITECTURE.ru.md) |
| Technology index | [English](https://github.com/yinon-mitin/Status-Page/blob/main/docs/TECHNOLOGY_INDEX.md) | [Russian](https://github.com/yinon-mitin/Status-Page/blob/main/docs/TECHNOLOGY_INDEX.ru.md) |
| Infrastructure overview | [HTML page](https://github.com/yinon-mitin/Status-Page/blob/main/docs/PROJECT_INFRASTRUCTURE.html) | — |
| Milestone audit | [English](https://github.com/yinon-mitin/Status-Page/blob/main/docs/MILESTONE_AUDIT.md) | [Russian](https://github.com/yinon-mitin/Status-Page/blob/main/docs/MILESTONE_AUDIT.ru.md) |
| Implementation log | [English](https://github.com/yinon-mitin/Status-Page/blob/main/docs/IMPLEMENTATION_LOG.md) | [Russian](https://github.com/yinon-mitin/Status-Page/blob/main/docs/IMPLEMENTATION_LOG.ru.md) |
| Thursday AWS status | [English](https://github.com/yinon-mitin/Status-Page/blob/main/docs/THURSDAY_STATUS.md) | [Russian](https://github.com/yinon-mitin/Status-Page/blob/main/docs/THURSDAY_STATUS.ru.md) |
| Terraform baseline | [README](https://github.com/yinon-mitin/Status-Page/blob/main/terraform/README.md) | — |

See [CHANGELOG.md](CHANGELOG.md) for notable changes and [UPSTREAM.md](UPSTREAM.md) for source policy.

## Repository layout

```text
assets/              Project icon and visual assets
docker/              Entrypoint scripts and NGINX configuration
docs/                Architecture, audits, and implementation logs
terraform/           AWS ECR, ECS, and guarded network infrastructure
.github/workflows/   Validation and OIDC-based ECR publishing
statuspage/          Django source from upstream v2.5.1
```

## Safety and licence

- No secret values are committed; runtime secrets are designed for Secrets Manager.
- ALB is designed for public subnets; ECS tasks remain internal.
- RDS is planned with a public setting but ingress only from the ECS security group.
- This fork preserves the upstream [Apache-2.0 licence](LICENSE.txt), source history, and `upstream-v2.5.1` tag.
