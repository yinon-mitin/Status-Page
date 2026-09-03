# Thursday Terraform baseline

This directory implements immutable ECR repositories and the production ECS Fargate runtime for the Status-Page web, RQ worker, and RQ scheduler processes.

It never applies infrastructure automatically. Production is enabled only by the private, ignored `prod.tfvars`, after an explicit reviewed plan. The public ALB, private application/data subnets, RDS PostgreSQL, ElastiCache Redis, Secrets Manager inputs, and ECS services have been applied to the isolated production state.

## What `terraform apply` creates now

- two private ECR repositories: `${project}-${environment}-app` and `${project}-${environment}-nginx`;
- immutable SHA-tagged images, scan-on-push, and 30-image lifecycle policies;
- an ECS cluster with Container Insights;
- CloudWatch log groups for web, worker, and scheduler;
- ECS task definitions that consume manually managed execution and task role ARNs;
- three Fargate task definitions: web (app + NGINX sidecar), worker, and scheduler.

Set `create_services = true` only after supplying private application subnets, the ECS security-group ID, web target-group ARN, non-secret runtime settings, and Secrets Manager ARNs for `STATUS_PAGE_SECRET_KEY` and `POSTGRES_PASSWORD`.

## Network foundation

`network.tf` implements the approved topology but is disabled by default with `create_network = false`: a VPC, public subnets in `il-central-1a` and `il-central-1b` for the internet-facing ALB, and internal application subnets in the same AZs for ECS. The ALB security group accepts public HTTP/HTTPS and has TCP/80 egress only to the ECS security group; the ECS security group accepts HTTP only from the ALB security group. Internal ECS subnets have no public IP assignment or direct Internet route.

The approved baseline uses `il-central-1a` and `il-central-1b`; `il-central-1c` is reserved for future expansion. ECS runs two web tasks across the two application subnets, while worker and scheduler each start at one task. Private task egress uses VPC endpoints for ECR API/Docker, CloudWatch Logs, Secrets Manager, and S3. NAT Gateway is an optional, disabled-by-default path only for application features that need arbitrary public HTTPS egress.

RDS must be created with `publicly_accessible = false`, a private DB subnet group, ECS-SG-only ingress on 5432, encryption, and two-day automated backup retention. Cloudflare hosts DNS for `status.yifilter.uk` in DNS-only mode. The live endpoint is temporary HTTP only because ACM certificate issuance is permission-blocked; do not treat it as HTTPS production readiness.

## Safe first use

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform fmt -recursive
terraform validate
terraform plan
```

Before applying, verify the target account deliberately:

```bash
aws sts get-caller-identity
terraform apply
```

Do not commit `terraform.tfvars`, state files, plans, or secret values.

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

GitHub OIDC and ECR publishing remain deferred until the network/data layer is
stable. When manually bootstrapping a dedicated OIDC publishing role, configure
repository variables:

| Variable | Required value |
| --- | --- |
| `AWS_REGION` | `il-central-1` unless another region is deliberately chosen. |
| `AWS_ROLE_TO_ASSUME` | ARN of a dedicated GitHub OIDC publishing role. |
| `ECR_APP_REPOSITORY` | Terraform ECR app repository name, normally `statuspage-dev-app`. |
| `ECR_NGINX_REPOSITORY` | Terraform ECR NGINX repository name, normally `statuspage-dev-nginx`. |

The publishing role must trust only this repository and `refs/heads/main`, and have permission to obtain an ECR authorization token and push layers/images only to these two repositories. It must not have broad administrator permissions.
