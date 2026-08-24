# Thursday milestone status

**Date:** 24 August 2026 · **AWS account:** `992382545251` · **Region:** `il-central-1`

## Completed in AWS

- ECR repository `statuspage-dev-app` — immutable tags and scan on push enabled.
- ECR repository `statuspage-dev-nginx` — immutable tags and scan on push enabled.
- ECR lifecycle policies — retain the latest 30 `sha-*` images.
- ECS cluster `statuspage-dev` — active, with the configuration recorded in Terraform.
- CloudWatch log groups for web, worker, and scheduler — 30-day retention.

## Implemented in the repository

- Terraform configuration for the ECR/ECS baseline, three task definitions, runtime secret injection, and a deliberately disabled ECS-service layer.
- Docker/Terraform validation workflow for pull requests and `main`.
- ECR publishing workflow using GitHub OIDC, SHA image tags, and Buildx cache. The job is intentionally skipped until the OIDC role ARN is configured as a repository variable.
- Account-specific `Owner=yinon` tags on AWS resources that support resource tagging.

## Account guardrail found

The account enforces an owner tag at resource creation. The first Terraform apply exposed this control; the code was updated and the second apply completed the ECR, ECS-cluster, and log-group resources.

The current IAM user can create the two ECS roles but is denied `iam:ListRolePolicies`. Terraform therefore cannot safely refresh or attach the managed execution policy to those roles, and it stopped before creating task definitions. This is an IAM permission boundary, not a Terraform or application failure.

Before the next apply, request these narrowly scoped permissions for the project roles:

- `iam:GetRole`, `iam:ListRolePolicies`, `iam:GetRolePolicy`, `iam:ListAttachedRolePolicies`, and `iam:AttachRolePolicy` on `statuspage-dev-ecs-task` and `statuspage-dev-ecs-execution`;
- `iam:ListOpenIDConnectProviders` and `iam:GetOpenIDConnectProvider` to inspect GitHub OIDC; `iam:CreateOpenIDConnectProvider` only if the account does not already have `token.actions.githubusercontent.com`.

No ECS service has been created. RDS, Redis, ALB, VPC/subnets, Secrets Manager, and application tasks remain out of scope until their agreed Terraform phase.

## Next command after IAM access is fixed

```bash
cd terraform
terraform apply
```

Then supply the generated GitHub OIDC publishing-role ARN as `AWS_ROLE_TO_ASSUME` in repository variables. The next push to `main` will publish both images to the two ECR repositories.
