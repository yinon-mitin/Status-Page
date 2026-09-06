# Security policy

[Русская версия](SECURITY.ru.md)

## Scope

Security reports for this repository should cover the project-specific Docker, Terraform, automation, configuration and application changes. The bundled Status-Page application is pinned to the archived upstream release `v2.5.1`; upstream issues should be checked against the original repository before reporting them here.

## Supported code

The current `main` branch is the only supported project revision. Historical branches, demonstration deployments and the archived upstream application are not maintained as separate release lines.

## Reporting a vulnerability

Use GitHub's private vulnerability reporting feature for this repository. Include:

- the affected file or component;
- steps to reproduce the issue;
- expected impact;
- a suggested mitigation, if known.

Do not open a public issue containing credentials, tokens, private infrastructure values or exploit details. The repository does not accept production secrets in source, examples, issues or logs.

## Deployment responsibility

Anyone deploying this project is responsible for reviewing dependencies, rotating credentials, applying relevant security updates and validating the target account's access policies. The checked-in automation provides reproducible controls; it is not a managed security service.
