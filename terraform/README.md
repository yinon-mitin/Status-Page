# Thursday Terraform baseline

This directory implements immutable ECR repositories and the production ECS Fargate runtime for the Status-Page web, RQ worker, and RQ scheduler processes.

Production is controlled by the private, ignored `prod.tfvars` and the guarded
lifecycle scripts. The runtime is currently destroyed; the isolated remote
state is empty while the state bucket, manual IAM roles, Django secret, and final
RDS snapshot remain available.

## What `terraform apply` creates now

- two private ECR repositories: `${project}-${environment}-app` and `${project}-${environment}-nginx`;
- immutable SHA-tagged images, scan-on-push, and 30-image lifecycle policies;
- an ECS cluster with Container Insights;
- CloudWatch log groups for web, worker, and scheduler;
- ECS task definitions that consume manually managed execution and task role ARNs;
- three Fargate task definitions: web (app + NGINX sidecar), worker, and scheduler.

With `create_data_plane = true`, Terraform derives private subnet IDs, security
groups, target group, database/Redis endpoints, and the RDS-managed password
secret ARN. The private inputs supply only the manual IAM role ARNs and external
`STATUS_PAGE_SECRET_KEY` secret ARN.

## Network foundation

`network.tf` implements the approved topology but is disabled by default with `create_network = false`: a VPC, public subnets in `il-central-1a` and `il-central-1b` for the internet-facing ALB, and internal application subnets in the same AZs for ECS. The ALB security group accepts public HTTP/HTTPS and has TCP/80 egress only to the ECS security group; the ECS security group accepts HTTP only from the ALB security group. Internal ECS subnets have no public IP assignment or direct Internet route.

The approved baseline uses `il-central-1a` and `il-central-1b`; `il-central-1c` is reserved for future expansion. ECS runs two web tasks across the two application subnets, while worker and scheduler each start at one task. Private task egress uses VPC endpoints for ECR API/Docker, CloudWatch Logs, Secrets Manager, and S3. NAT Gateway is an optional, disabled-by-default path only for application features that need arbitrary public HTTPS egress.

RDS is created with `publicly_accessible = false`, a private DB subnet group,
ECS-SG-only ingress on 5432, encryption, and two-day automated backup retention.
Cloudflare DNS is external to Terraform and must be updated after ALB recreation.
HTTPS remains permission-blocked.

## Automated production lifecycle

```bash
cp terraform/environments/prod.tfvars.example terraform/prod.tfvars
# Replace only the manual role and Django-secret placeholders.
AWS_PROFILE=status-page scripts/production_create.sh

SHA="$(git rev-parse origin/main)"
CONFIRM_PRODUCTION_APPROVAL="$SHA" scripts/production_release.sh

CONFIRM_DESTROY=yinon-status-page-prod \
AWS_PROFILE=status-page scripts/production_destroy.sh
```

Each script verifies AWS account `992382545251`, initializes the exact S3 state
key, creates a saved plan, validates its JSON safety contract, and applies that
exact plan. Destroy uses a unique final snapshot identifier and a separate
target-limited preparation plan. See [`../docs/PRODUCTION_LIFECYCLE.md`](../docs/PRODUCTION_LIFECYCLE.md).

Do not commit `prod.tfvars`, state files, plans, or secret values.

IAM roles are a manual bootstrap boundary. Terraform does not create, update,
attach, detach, or delete IAM roles or policies. Supply the ARNs of the
manually managed `yinon-status-page-prod-ecs-execution` and
`yinon-status-page-prod-ecs-task` roles through private variables.

## Environment isolation

Development and production use the same Terraform code but must use separate
state objects and variable files. Production currently uses the encrypted,
versioned S3 state object `yinon-status-page/prod/terraform.tfstate` in the
manually bootstrapped state bucket. Start development with the checked-in examples:

```bash
cp terraform/environments/dev.tfvars.example terraform/dev.tfvars
terraform -chdir=terraform init -backend-config="key=statuspage/dev/terraform.tfstate"
terraform -chdir=terraform plan -var-file=dev.tfvars
```

Use a different backend key and `prod.tfvars` for production. Never reuse a
state file, subnet ID, database endpoint, Redis endpoint, or Secrets Manager
ARN between environments. The `environment` variable is deliberately limited
to `dev` and `prod` so accidental environment names cannot silently create a
third, unmanaged deployment boundary.

This account requires an `Owner` tag on taggable resources; the default value is `yinon`. Change `owner` in `terraform.tfvars` if the account's policy requires a different exact value. Local state is acceptable only while one operator is preparing and reviewing the foundation. Before GitHub Actions performs Terraform `apply`, use an encrypted, versioned S3 backend with `use_lockfile = true`; DynamoDB locking is not required.

## GitHub Actions prerequisites

The manually bootstrapped publisher and deployer roles use the immutable
branch-bound `main` OIDC subject. Configure repository variables:

| Variable | Required value |
| --- | --- |
| `AWS_ACCOUNT_ID` | Exactly `992382545251`; this avoids requiring `sts:GetCallerIdentity` in the deployer role. |
| `AWS_REGION` | `il-central-1` unless another region is deliberately chosen. |
| `AWS_ROLE_TO_ASSUME` | ARN of a dedicated GitHub OIDC publishing role. |
| `ECR_APP_REPOSITORY` | Exactly `yinon-status-page-prod-app`. |
| `ECR_NGINX_REPOSITORY` | Exactly `yinon-status-page-prod-nginx`. |
| `AWS_DEPLOY_ROLE_TO_ASSUME` | ARN of the distinct production ECS deployer role. |
| `PRODUCTION_ENABLED` | `true` only while the production runtime exists. |

The Environment reviewer gate runs in a separate approval job. The dependent
deploy job therefore retains the branch-bound OIDC subject accepted by the
deployer role. The publisher has ECR-only permissions; the deployer has scoped
ECS actions and `iam:PassRole` only for the two manual ECS roles.

The training account does not permit IAM changes. Consequently the deployer
cannot run a dedicated migration task; the web entrypoint performs Django
migrations before Gunicorn. This limitation and the one-time manual role setup
are documented in `docs/PRODUCTION_LIFECYCLE.md`.
