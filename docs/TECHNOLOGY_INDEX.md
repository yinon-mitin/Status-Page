# Technology Index — Yinon Final DevOps Project

This index defines every technology and operational term used in the proposed Status-Page AWS architecture. It distinguishes the current application from the target deployment.

## Evidence labels

- **Source-derived** — confirmed by the pinned official upstream release `v2.5.1` at the repository root; `reference/ARCHITECTURE.source.html` is historical reference material.
- **Target decision** — selected for the AWS final-project deployment.

## Application runtime

| Technology / term | Type | Evidence | Purpose in this project |
|---|---|---|---|
| Django 5.1.2 | Python web framework | Source-derived | Provides the modular monolith, pages, administration interface, and REST API. |
| Python ≥ 3.10 | Programming language/runtime | Source-derived | Runs Django, worker, scheduler, and management commands. |
| Gunicorn | WSGI application server | Source-derived | Runs Django's `statuspage.wsgi` process for dynamic HTTP requests. |
| WSGI | Web Server Gateway Interface | Source-derived | Standard interface between Gunicorn and Django. |
| NGINX | Web server / reverse proxy | Source-derived + target decision | Serves `/static/`, forwards dynamic traffic to Gunicorn, and preserves proxy headers. In AWS, it remains in the web task while ALB handles public TLS. |
| DRF | Django REST Framework | Source-derived | Provides the application's REST API endpoints. |
| PostgreSQL | Relational database | Source-derived | Single system of record for Status-Page application data. |
| Redis | In-memory data store | Source-derived | Hosts logical DB 0 for RQ queues and DB 1 for Django cache. |
| RQ | Redis Queue | Source-derived | Python queue for asynchronous jobs such as notifications, automation, and plugin polls. |
| RQ Worker | Background process | Source-derived | Runs `rqworker high default low`; takes jobs from Redis and performs asynchronous work. |
| RQ Scheduler | Background process | Source-derived | Runs `rqscheduler`; registers and releases recurring jobs. |
| SMTP | Simple Mail Transfer Protocol | Source-derived | Optional upstream Status-Page capability for notification email. |
| `/static/` | Static asset path | Source-derived | Contains collected CSS, JavaScript, and image assets served by NGINX. |
| `MEDIA_ROOT` | Django media storage directory | Source-derived | Current local-disk location for user-uploaded media; not durable across ECS task replacement. |

## AWS target platform

| Technology / term | Expansion | Purpose in this project |
|---|---|---|
| AWS | Amazon Web Services | Cloud platform for the target deployment. |
| Docker | Container platform | Packages the application and dependencies into a reproducible image. |
| ECR | Elastic Container Registry | Stores versioned Docker images tagged by Git commit SHA. |
| ECS | Elastic Container Service | Orchestrates the web, worker, and scheduler container workloads. |
| Fargate | Serverless ECS compute engine | Runs ECS tasks without managing EC2 hosts. |
| ALB | Application Load Balancer | Internet-facing HTTP/HTTPS entry point in two public subnets; redirects port 80, terminates TLS on 443, and routes to ECS IP targets. |
| ACM | AWS Certificate Manager | Issues and renews the TLS certificate attached to the ALB. |
| RDS | Relational Database Service | Provides private managed PostgreSQL with encryption, patching, and two-day automated backups. Its SG permits 5432 only from the ECS SG. |
| ElastiCache for Redis | Managed Redis service | Provides managed Redis compatible with the existing queue/cache split. |
| Secrets Manager | AWS secret store | Holds database, Django, Redis, and approved external API credentials. |
| IAM | Identity and Access Management | Grants least-privilege permissions to people, GitHub Actions, ECS task execution, and application tasks. |
| VPC | Virtual Private Cloud | Private AWS network boundary for the project. |
| Subnet | VPC network segment | Separates public ALB placement, internal ECS applications, and private RDS/Redis across two AZs. |
| AZ | Availability Zone | Independent AWS location used to improve resilience. |
| Security Group | Stateful virtual firewall | Allows only Internet → ALB → ECS → RDS/Redis traffic paths. |
| SG reference | Security-group-to-security-group rule | Grants RDS port 5432 to the ECS SG without opening the database to an Internet CIDR range. |
| Target group | ALB backend destination set | Registers ECS task IP addresses on HTTP port 80 and checks `/healthz`. |
| ECS task spread | Placement across Availability Zones | Places two web tasks in the internal subnets of `il-central-1a` and `il-central-1b` for compute-level availability. |
| `/healthz` | Application health endpoint | Returns HTTP 200 without a database query and is used by Docker, ECS, and ALB checks. |
| VPC endpoint | PrivateLink / gateway connection | Lets private ECS tasks reach ECR, CloudWatch Logs, Secrets Manager, and S3 without NAT or public IPs. |
| NAT Gateway | Managed outbound network translation | Optional and disabled by default; used only temporarily if the application must call arbitrary public HTTPS services. |
| Cloudflare DNS only | Authoritative DNS configuration | Hosts `status.yifilter.uk` DNS records while traffic terminates directly at the ALB with ACM TLS. |
| CloudWatch | AWS observability service | Stores logs and metrics; triggers alarms for service and data-tier health. |
| CloudTrail | AWS audit service | Records AWS management API activity for security and traceability. |
| DNS | Domain Name System | Maps a project domain to the ALB. |

## Delivery and infrastructure

| Technology / term | Expansion | Purpose in this project |
|---|---|---|
| Terraform | Infrastructure as Code tool | Declares, reviews, and creates the AWS resources consistently. |
| IaC | Infrastructure as Code | Practice of storing infrastructure definitions in version control. |
| Remote state | Shared Terraform state storage | Required before GitHub Actions performs Terraform apply: an encrypted versioned S3 backend persists state; native S3 lockfiles replace DynamoDB locking. |
| GitHub Actions | CI/CD automation platform | Runs tests, builds images, pushes to ECR, validates Terraform, and deploys ECS services. |
| CI/CD | Continuous Integration / Continuous Delivery | Automated path from a reviewed code change to a verified deployment. |
| OIDC | OpenID Connect | Lets GitHub Actions receive short-lived AWS credentials without long-lived access keys. |
| SHA | Secure Hash Algorithm commit identifier | Used as an immutable-ish Docker image version tag. |
| Health check | Service availability probe | Lets ALB/ECS identify a non-working web task. |
| Rolling deployment | Incremental service replacement | Replaces ECS tasks gradually and enables a controlled rollback. |
| Migration | Database schema change | Must run as a controlled ECS one-off task or release step. |

## Important architecture rules

1. A single Docker image is reused for web, worker, and scheduler with different commands.
2. The web service starts with two tasks across two AZs; worker and scheduler remain one task each because the source has local-media and worker-concurrency constraints.
3. Only ALB is public. ECS, RDS, and Redis are private; RDS has `publicly_accessible = false`.
4. Secrets never enter Git, Docker layers, regular Terraform variables, or logs.
5. RDS and Redis accept application traffic only from the ECS security group; ECS uses VPC endpoints for required AWS-service egress.
6. EKS is intentionally not selected: its operational complexity is not justified for this small workload.

## Primary references

- `reference/ARCHITECTURE.source.html` — current Status-Page system architecture reference.
- repository root — pinned official upstream v2.5.1 source, including `contrib/` runtime configurations and installation documentation.
- `ARCHITECTURE.md` and `ARCHITECTURE.ru.md` — separate English/Russian AWS architecture and implementation roadmaps.
