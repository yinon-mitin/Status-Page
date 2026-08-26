# Temporary ECR/ECS smoke stack

This isolated configuration validates the ECR and ECS Terraform path without touching the existing `statuspage-dev` state or the production design.

It creates resources with the dedicated prefix `yinon-status-page-smoke-*` and tags them with `Owner=yinon`, `Project=yinon-status-page`, and `Purpose=temporary-idempotency-test`.

## Scope

- two temporary ECR repositories with immutable tags and scan-on-push;
- one ECS cluster with Container Insights;
- optionally, one Fargate task definition that references the pushed local Status-Page application image when a project-scoped ECS execution-role ARN is supplied.

It does **not** create or run an ECS service or Fargate task, and it does not create VPC, ALB, RDS, Redis, secrets, or IAM roles. A Fargate task definition that pulls from private ECR also requires an execution role, so registration is deliberately optional until the project-scoped IAM role is available. Running a task correctly belongs to the later private-network and IAM phase.

`force_delete = true` is intentional and limited to these temporary ECR repositories: it permits `terraform destroy` to delete test images and repositories after verification.

## Acceptance procedure

1. Build local images with Docker Compose.
2. `terraform apply` this directory with an immutable smoke image tag.
3. Authenticate Docker to the two output ECR repository URLs and push both local images.
4. Confirm the ECR images exist and the task definition references the application image URI.
5. Run `terraform plan -detailed-exitcode`; exit code `0` proves the declared infrastructure is idempotent.
6. Run `terraform destroy`; confirm no repositories, ECS cluster, or task-definition family with this prefix remains.
