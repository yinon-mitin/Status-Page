# Status-Page on AWS

[Русская версия](index.ru.md)

This documentation describes a completed DevOps implementation for the Status-Page application. The project provides a local Docker environment and a reproducible AWS lifecycle built with Terraform, ECS Fargate, managed data services and GitHub Actions.

## Start here

- [Architecture](ARCHITECTURE.md) explains the runtime, network and delivery model.
- [Production lifecycle](PRODUCTION_LIFECYCLE.md) covers create, release, restore and destroy operations.
- [Technology index](TECHNOLOGY_INDEX.md) maps each tool to its role in the system.
- [Validation evidence](DELIVERY_EVIDENCE.md) records what was exercised locally and on AWS.
- [HTTPS scope](HTTPS_LIMITATION.md) documents the demonstration's transport boundary.

## Local environment

```bash
cp .env.example .env
make up
make check
```

The local stack runs PostgreSQL, Redis, Django/Gunicorn, NGINX, RQ Worker and RQ Scheduler. See [OrbStack development VM](ORBSTACK_DEV.md) for the optional macOS VM workflow.

## AWS lifecycle

```text
create -> publish -> migrate -> approve -> deploy -> verify -> restore test -> destroy
```

The lifecycle scripts validate the source revision, AWS account and saved Terraform plan before changing infrastructure.
