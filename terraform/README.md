# AWS infrastructure

[Русская версия](README.ru.md)

This Terraform root defines the reproducible AWS runtime for Status-Page in `il-central-1`.

## Managed components

- a VPC across two Availability Zones;
- public subnets for the Application Load Balancer;
- private application subnets for ECS Fargate;
- private data subnets for RDS PostgreSQL and ElastiCache Redis;
- VPC endpoints for ECR, S3, CloudWatch Logs and Secrets Manager;
- immutable ECR repositories;
- ECS cluster, task definitions and web, worker and scheduler services;
- CloudWatch log groups, dashboard and alarms;
- optional SNS notification and AWS Budget resources.

Terraform receives the ECS execution-role and task-role ARNs as variables. Those roles, the remote-state bucket and the application secret are prepared once outside this root.

## Configuration

From the repository root, copy the safe example to an ignored local file:

```bash
cp terraform/environments/prod.tfvars.example terraform/prod.tfvars
```

Set deployment-specific values in `terraform/prod.tfvars`. Never commit this file, state, plans or credentials.

Initialize the S3 backend with the approved bucket and state key:

```bash
terraform -chdir=terraform init \
  -backend-config="bucket=<state-bucket>" \
  -backend-config="key=yinon-status-page/prod/terraform.tfstate" \
  -backend-config="region=il-central-1" \
  -backend-config="encrypt=true" \
  -backend-config="use_lockfile=true"
```

## Lifecycle

Use the repository scripts from the project root rather than applying arbitrary Terraform commands:

```bash
scripts/production_create.sh
SHA="$(git rev-parse origin/main)"
CONFIRM_PRODUCTION_APPROVAL="$SHA" scripts/production_release.sh
CONFIRM_RESTORE_TEST="$SHA" scripts/production_backup_restore_test.sh
CONFIRM_DESTROY=yinon-status-page-prod scripts/production_destroy.sh
```

The scripts enforce the expected repository revision, AWS account, resource prefixes and plan shape. Creation is phased so ECR repositories exist before immutable images are published and ECS services start. Releases run a separate one-off migration task before rolling out web, worker and scheduler. Destruction first prepares protected resources, then applies a fresh delete-only plan and verifies empty state.

## Direct Terraform checks

```bash
terraform -chdir=terraform fmt -check -recursive
terraform -chdir=terraform validate
tflint --chdir=terraform --config=.tflint.hcl
```

Production plans are saved outside the repository and checked by `scripts/validate_terraform_plan.py` before apply.

## Runtime layout

- ALB accepts public HTTP traffic and forwards it to the web service on TCP `80`.
- ECS tasks have no public IP addresses.
- RDS accepts TCP `5432` only from the ECS security group.
- Redis accepts TCP `6379` only from the ECS security group.
- The web service runs NGINX and Django/Gunicorn in one task.
- Worker and scheduler services reuse the application image with different commands.

## State and recovery

The normal destroy removes the Terraform-managed runtime. It preserves the separately prepared state bucket, roles and application secret, along with the RDS final snapshot. This keeps the environment recreatable without mixing long-lived recovery assets into the short-lived demonstration runtime.

See [the production lifecycle](../docs/PRODUCTION_LIFECYCLE.md) for the full runbook and [architecture](../docs/ARCHITECTURE.md) for the system design.
