# Delivery Evidence and Release Gates

This page is the evidence index for the Status Page delivery model. It deliberately separates what is live from what is implemented only or blocked; an unchecked gate is not a production claim.

## Current architecture

```text
feature/* → dev → pull request → main → build/publish → production approval → ECS rollout

Local development: Docker Compose on the developer machine
Production when enabled: Cloudflare DNS-only → public HTTP ALB → private ECS Fargate
                                           ├─ web (2 tasks)
                                           ├─ worker (1 task)
                                           └─ scheduler (1 task)
Private data plane: RDS PostgreSQL and ElastiCache Redis
```

## Evidence matrix

| Requirement | Implemented configuration | Current evidence | Status |
| --- | --- | --- | --- |
| Local development | Docker Compose runs web, NGINX, PostgreSQL, Redis, worker, and scheduler. | `make verify` was passed locally using OrbStack Docker. | Verified locally |
| Production runtime | Separate `yinon-status-page-prod-*` ECS, ALB, RDS, Redis, ECR, and manually managed ECS roles in `il-central-1`. | The runtime was verified live, then safely destroyed; Terraform state currently has zero resources. | Historical live proof; currently paused |
| Terraform remote state | S3 backend with locking, encrypted/versioned bucket `yinon-status-page-tfstate-992382545251`. | Production state key remains available and empty after teardown. | Backend retained; runtime absent |
| Environment separation | `environment` is validated as `dev` or `prod`; separate example contracts exist. | Production is paused. A cloud dev runtime has **not** been applied or verified and must use its own state key and resources. | Configuration verified; runtimes absent |
| CI | `Validate` and `Security scan` run for PRs and pushes to `dev` and `main`. | Main runs `33765216944` (Validate) and `33765216994` (Security scan) succeeded. | Verified on main |
| Main branch flow | GitHub `main` requires a pull request, successful required checks, up-to-date branches, resolved conversations, linear history, and has direct pushes/force pushes blocked. | GitHub branch-protection rule is configured. | Configured |
| Production approval | GitHub Environment `production` is configured with a required reviewer before the deploy job starts. | Workflow contains the gated deployment job. | Configured; runtime dependency below |
| GitHub OIDC publish | Publish job uses GitHub OIDC and immutable `sha-${github.sha}` amd64 ECR tags. | Run `33788559359` successfully assumed the dedicated ECR publisher role and published both runtime images. | Verified |
| GitHub OIDC deploy | Deployment uses a distinct `AWS_DEPLOY_ROLE_TO_ASSUME`; approval and branch-bound OIDC are separate dependent jobs. | The previous environment-bound deploy failed before ECS. The revised path still requires a live approved rehearsal. | Implemented; pending new proof |
| HTTPS | ACM termination is the target architecture. | No public runtime currently exists; ACM permissions remain unavailable. The recovery procedure is documented in [`HTTPS_LIMITATION.md`](HTTPS_LIMITATION.md). | Runtime absent; access blocked |

## Release procedure

1. Create `feature/<name>` from `dev`; push the feature branch and open a pull request into `dev`.
2. CI must be green. Merge the reviewed feature into `dev`.
3. Open a pull request from `dev` to `main`. GitHub blocks direct pushes to `main`; required checks must pass.
4. Merging `main` starts the immutable `linux/amd64` ECR build. Images are tagged `sha-<commit SHA>`.
5. The `Deploy immutable images to production` job pauses at GitHub Environment **production** for reviewer approval.
6. After approval, the deployment role registers new ECS task-definition revisions and waits for all three services to become stable. In this restricted training account, the web entrypoint runs Django migrations before Gunicorn because the deployer cannot call `ecs:RunTask` and IAM cannot be changed.
7. Verify `/healthz`, the public page, ALB target health, and a Terraform no-change plan.

No GitHub workflow may receive broad Terraform or production access merely to make deployment convenient. IAM roles and policies are a manual security boundary in this project.

The executable create/release/destroy procedure and its safety checks are in [`PRODUCTION_LIFECYCLE.md`](PRODUCTION_LIFECYCLE.md).

## Manual IAM prerequisite

The ECR and deploy roles must be created outside Terraform. They must trust only GitHub OIDC tokens for:

```text
repository: yinon-mitin/Status-Page
branch: main
subject: repo:yinon-mitin@33204470/Status-Page@1345305838:ref:refs/heads/main
audience: sts.amazonaws.com
```

Use two roles:

- **ECR publisher role**: only `ecr:GetAuthorizationToken` and the upload/read actions scoped to `yinon-status-page-prod-app` and `yinon-status-page-prod-nginx`. Set its ARN as repository Variable `AWS_ROLE_TO_ASSUME`.
- **Production deploy role**: only ECS describe/register/update and `iam:PassRole` for the existing production task/execution role ARNs, scoped to the production cluster/services. Set its ARN as repository Variable `AWS_DEPLOY_ROLE_TO_ASSUME`.

Do not put either ARN, runtime secrets, Terraform `*.tfvars`, state files, or credentials in the repository.

## Reviewer demonstration checklist

For a presentation, show these live screens or command outputs:

1. GitHub **Settings → Branches → main**: pull-request-only rule and required checks.
2. GitHub **Settings → Environments → production**: required reviewer rule.
3. GitHub **Actions**: retain the successful `Validate`, `Security scan`, and OIDC ECR-publish evidence; complete and record the first reviewer-approved deployment from `main`.
4. AWS S3: versioning/encryption on the state bucket and the `prod` state key (do not reveal state contents).
5. AWS ECS/ALB: desired/running counts and healthy targets.
6. During an enabled rehearsal, use the Terraform ALB DNS output for `/healthz`; update and verify the Cloudflare hostname separately.
7. `terraform plan -detailed-exitcode` using the private production inputs: zero changes.

## Deliberate non-claims

- Local Docker Compose is a development environment; it is not a separately deployed cloud `dev` environment.
- `dev` Terraform examples are configuration contracts, not proof of a deployed dev data plane.
- Production ingress is not HTTPS-ready; it intentionally remains HTTP-only until the documented ACM recovery procedure is completed.
- A workflow YAML file is not proof of deployment until the reviewer-approved `main` run completes an ECS rollout and public health check.
