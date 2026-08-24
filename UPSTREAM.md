# Upstream provenance and maintenance policy

This repository is an unofficial educational DevOps fork of [Status-Page](https://github.com/Status-Page/Status-Page), based on the upstream release tag [`v2.5.1`](https://github.com/Status-Page/Status-Page/releases/tag/v2.5.1).

The original project was archived in October 2025 and its announced security-support period ended on 31 December 2025. This project therefore pins the application to `v2.5.1`; it does not represent an actively maintained upstream service.

The fork preserves the upstream history and license. Project-specific work is deliberately isolated in Docker files, `docker-compose.yml`, `.github/workflows/`, `terraform/`, and `docs/`. Application changes are limited to an environment-driven configuration adapter and the `/healthz` endpoint required by the load balancer.

Keep the `upstream` remote for provenance. Treat upstream code as a fixed baseline: review and explicitly document any future security patches before applying them.
