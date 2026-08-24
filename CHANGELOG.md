# Changelog

All notable project changes are recorded here. This project follows the spirit of [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and uses ISO dates.

## [Unreleased]

### Changed

- Excluded Git metadata from the Docker build context to keep local and CI image builds small and reproducible.
- Added disabled-by-default VPC, public/internal subnet, route-table, and ALB/ECS security-group Terraform code for the next network phase.
- Redesigned both README files with a project icon, badges, concise navigation, status table, quick start, and parallel English/Russian documentation links.

### Added

- Project icon at `assets/statuspage-devops-icon.png`.
- Makefile targets for local Compose and Terraform quality checks.
- Full Docker Compose smoke test in GitHub Actions: health checks, NGINX HTTP, Django system check, and cleanup.
- RQ end-to-end smoke test that verifies a Django-enqueued job completes through Redis and the worker.

### Verified

- Re-ran the Wednesday Docker Compose acceptance checks: all six services are up, `/healthz` and the homepage return HTTP 200, and `manage.py check` passes.
- Rechecked the Thursday AWS and CI deliverables: both ECR repositories are immutable and scan on push; the ECS cluster is active with Container Insights; GitHub Actions validation is successful.

## [2026-08-24]

### Added

- Forked the official Status-Page release `v2.5.1` and preserved upstream provenance with the `upstream-v2.5.1` tag.
- Dockerfiles, Docker Compose runtime, NGINX reverse proxy, environment-based configuration, and `/healthz` endpoint.
- English and Russian architecture, technology, upstream-policy, and infrastructure documentation.
- Terraform ECR/ECS baseline, CloudWatch log groups, ECR lifecycle policies, ECS task-definition definitions, and guarded ECS-service configuration.
- GitHub Actions validation workflow and OIDC-based ECR publishing workflow.
- Thursday implementation status documents recording the applied AWS resources and the current IAM limitation.

### Changed

- Replaced the previous instructional Status-Page archive with the official stable upstream `v2.5.1` source.

## Infrastructure state note

The ECR repositories, lifecycle policies, ECS cluster, and CloudWatch log groups were created in AWS account `992382545251`, region `il-central-1`. ECS task definitions and services are not yet created because the current IAM identity is denied `iam:ListRolePolicies`; see `docs/THURSDAY_STATUS.md`.
