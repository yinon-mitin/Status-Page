# Changelog

Notable changes to this DevOps fork are recorded here. Application history before the fork remains available in the upstream Git history and release notes.

## [Unreleased]

### Changed

- Reorganized the public documentation around the finished system rather than its development timeline.

## Project completion

### Added

- Complete six-service Docker Compose environment for PostgreSQL, Redis, Django/Gunicorn, NGINX, RQ Worker and RQ Scheduler.
- Standalone application and NGINX images, including compiled frontend assets.
- Terraform-managed AWS VPC, public/application/data subnets, security groups, VPC endpoints, ECR, ECS Fargate, ALB, RDS PostgreSQL, ElastiCache Redis and CloudWatch monitoring.
- Guarded create, release, verification, semantic database restore and destroy automation.
- GitHub Actions validation, full-history secret scanning, immutable ECR publication and approved ECS deployment through separate OIDC roles.
- Dedicated private Fargate migration task with exact-revision release evidence.
- CloudWatch dashboard and 18 alarms covering ALB, ECS, RDS and Redis.
- Exact-host Cloudflare DNS updater and optional signed SNS-to-Telegram relay.
- English and Russian architecture, lifecycle, technology and validation documentation.

### Verified

- Local runtime health, static assets, Django checks, tests and RQ job execution.
- Real AWS create, immutable image publication, migration, ECS rollout and HTTP health.
- Terraform idempotency after deployment.
- Semantic RDS snapshot restore into a disposable private database.
- Guarded removal of the Terraform-managed runtime with empty final state.

## Initial foundation

### Added

- Pinned Status-Page `v2.5.1` source with preserved upstream history and Apache-2.0 license.
- Initial Docker, Compose, Terraform and CI foundation for the project.
