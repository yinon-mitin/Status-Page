# Technology index

[Русская версия](TECHNOLOGY_INDEX.ru.md)

This index explains the main technologies used by the project and the job each one performs.

## Application

| Technology | Role |
| --- | --- |
| Python | Runtime for the application and operational scripts |
| Django | Status pages, incidents, administration and REST API |
| Gunicorn | WSGI server for Django |
| NGINX | Reverse proxy and static-file server inside the web task |
| PostgreSQL | Application system of record |
| Redis | RQ queues and Django cache |
| RQ Worker | Executes asynchronous jobs from Redis |
| RQ Scheduler | Releases recurring jobs on schedule |

## Containers and local development

| Technology | Role |
| --- | --- |
| Docker | Packages the application and NGINX runtime |
| Docker Compose | Runs the complete six-service environment locally |
| OrbStack | Optional macOS container and Linux VM runtime used during development |
| Tailwind and TypeScript | Build the frontend assets embedded in the NGINX image |

## AWS platform

| Service | Role |
| --- | --- |
| VPC | Network boundary for the project |
| Public subnets | Host the Internet-facing load balancer in two Availability Zones |
| Private application subnets | Host ECS tasks without public IP addresses |
| Private data subnets | Host RDS and ElastiCache |
| Application Load Balancer | Routes HTTP traffic to healthy web task IPs |
| ECS Fargate | Runs web, worker and scheduler without EC2 hosts |
| Amazon ECR | Stores immutable application and NGINX images |
| Amazon RDS for PostgreSQL | Managed encrypted database, backups and final snapshots |
| ElastiCache for Redis | Managed encrypted queue and cache service |
| Secrets Manager | Supplies runtime secrets to ECS |
| VPC endpoints | Give private tasks access to ECR, S3, Logs and Secrets Manager |
| CloudWatch | Stores logs and provides the dashboard and workload alarms |
| Amazon SNS | Optional transport for external alarm delivery |
| AWS Budgets | Optional tagged monthly cost threshold |

## Delivery and infrastructure

| Technology | Role |
| --- | --- |
| Terraform | Declares AWS resources and remote state |
| S3 backend | Stores encrypted, versioned Terraform state and native lockfiles |
| GitHub Actions | Runs CI, security checks, image publication and ECS rollout |
| OpenID Connect | Gives GitHub short-lived AWS credentials |
| Git SHA image tags | Bind deployed images to a source revision |
| GitHub Environment | Adds the production approval step |
| Gitleaks | Scans reachable Git history for secrets |
| TFLint | Checks Terraform beyond syntax validation |
| ShellCheck and Actionlint | Validate lifecycle scripts and GitHub workflows |

## Operational concepts

| Term | Meaning in this project |
| --- | --- |
| Health check | `/healthz` probe used by Docker, ECS and ALB |
| One-off migration | Private Fargate task that updates the database before rollout |
| Rolling deployment | Web-first ECS replacement followed by worker and scheduler |
| Semantic restore | Snapshot restore that verifies an exact database probe and Django migration history |
| Idempotency | A refreshed Terraform plan reports no changes after deployment |
| Guarded destroy | Delete-only allowlisted plan followed by direct absence checks |

## Architecture rules

1. Web, worker and scheduler use the same application image with different commands.
2. The public surface ends at the load balancer; application and data services stay private.
3. Database and Redis ports are allowed only from the ECS security group.
4. Releases use immutable images and a separate migration task.
5. Terraform plans are reviewed and validated before apply or destroy.
6. Runtime secrets never belong in Git, image layers, plans or logs.

See [Architecture](ARCHITECTURE.md) and [Production lifecycle](PRODUCTION_LIFECYCLE.md) for the complete system.
