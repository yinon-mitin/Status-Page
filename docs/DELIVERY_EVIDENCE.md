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
| Production runtime | Separate `yinon-status-page-prod-*` ECS, ALB, RDS, Redis, ECR, and manually managed ECS roles in `il-central-1`. | Revision `de3ba39d4f953ce8baa6e73167361d2063302a64`: resumable create, exact-SHA migration, web `2/2`, worker `1/1`, scheduler `1/1`, HTTP 200 health, no-change plan, approved rollout, semantic restore, and 76-resource destroy to empty state. | Automated live cycle verified; currently paused |
| Terraform remote state | S3 backend with locking, encrypted/versioned bucket `yinon-status-page-tfstate-992382545251`. | Production state key remains available and empty after teardown. | Backend retained; runtime absent |
| Environment separation | `environment` is validated as `dev` or `prod`; separate example contracts exist. | Production is paused. A cloud dev runtime has **not** been applied or verified and must use its own state key and resources. | Configuration verified; runtimes absent |
| CI | `Validate` and `Security scan` run for PRs and pushes to `dev` and `main`. | Main runs `33765216944` (Validate) and `33765216994` (Security scan) succeeded. | Verified on main |
| Main branch flow | GitHub `main` requires a pull request, successful required checks, up-to-date branches, resolved conversations, linear history, and has direct pushes/force pushes blocked. | GitHub branch-protection rule is configured. | Configured |
| Production approval | GitHub Environment `production` is restricted to protected branches and requires a reviewer before its approval job completes. | Run `34043025336` enforced approval after exact-SHA migration evidence and before deploy. | Verified |
| GitHub OIDC publish | Publish job uses GitHub OIDC and immutable `sha-${github.sha}` amd64 ECR tags. | Run `34041754952` published both images for the final rehearsal revision through the dedicated role. | Verified |
| GitHub OIDC deploy | Deployment uses a distinct `AWS_DEPLOY_ROLE_TO_ASSUME`; approval and branch-bound OIDC are separate dependent jobs. | Run `34043025336` passed approval, assumed the deployer role, updated all services, reached stability, and passed provider health. | Verified |
| Monitoring | CloudWatch dashboard plus 18 ALB/ECS/RDS/Redis alarms. | Exact alarm count, empty permission-bound actions, dashboard API read-back, and runtime metrics configuration were live-verified. All were removed by destroy. | Verified; currently absent |
| Backup restore | Manual snapshot restored to a disposable private RDS instance and verified from a private Fargate task. | Exact probe row and populated `django_migrations` were found; source probe, restored DB, test snapshot, and test task definitions all read back absent. | Semantic restore verified |
| SNS/Telegram | Signed SNS relay with freshness/KV replay controls is implemented. | `SNS:CreateTopic` is denied and integration credentials were not supplied. | Implemented; permission/credential blocked |
| AWS Budget | Opt-in project-tagged monthly `$300` Budget with 50/80/100 percent notifications. | `budgets:ViewBudget` is denied; creation was not attempted after the permission was established. | Implemented; permission blocked |
| HTTPS | ACM termination is the target architecture. | No public runtime currently exists; ACM permissions remain unavailable. The recovery procedure is documented in [`HTTPS_LIMITATION.md`](HTTPS_LIMITATION.md). | Runtime absent; access blocked |

## Release procedure

1. Create `feature/<name>` from `dev`; push the feature branch and open a pull request into `dev`.
2. CI must be green. Merge the reviewed feature into `dev`.
3. Open a pull request from `dev` to `main`. GitHub blocks direct pushes to `main`; required checks must pass.
4. Merging `main` starts the immutable `linux/amd64` ECR build. Images are tagged `sha-<commit SHA>`.
5. The `Deploy immutable images to production` job pauses at GitHub Environment **production** for reviewer approval.
6. The operator runs a private one-off migration task for the exact immutable SHA. Only matching `MIGRATION_EVIDENCE_SHA` permits workflow dispatch; production web startup migrations are disabled.
7. After approval, the deployment role registers new ECS task-definition revisions and waits for all three services to become stable.
8. Verify `/healthz`, the public page, ALB target health, and a Terraform no-change plan.

No GitHub workflow may receive broad Terraform or production access merely to make deployment convenient. IAM roles and policies are a manual security boundary in this project.

The executable create/release/destroy procedure and its safety checks are in [`PRODUCTION_LIFECYCLE.md`](PRODUCTION_LIFECYCLE.md).

## Automated lifecycle rehearsal

The live rehearsal for exact `main` revision
`86d711d7c915d5efa66cb685a25964d7edf57a94` produced:

- guarded foundation apply: 54 creates, zero changes, zero destroys;
- OIDC image-only run [`34030885146`](https://github.com/yinon-mitin/Status-Page/actions/runs/34030885146), publishing both immutable `linux/amd64` images;
- guarded service apply: 3 creates, zero changes, zero destroys;
- ECS/ALB evidence: web `2/2`, worker `1/1`, scheduler `1/1`, two healthy targets, and HTTP 200 `/healthz`;
- reviewed idempotency plan: no changes;
- approved deploy-only run [`34031224217`](https://github.com/yinon-mitin/Status-Page/actions/runs/34031224217), including successful deployer OIDC and stable rollout; and
- guarded destroy: 57 deletes only, followed by zero Terraform resources and zero active/inactive exact-family task definitions.

ECR, ALB, RDS, Redis, and the production VPC were read back as absent. The versioned state bucket, four manual roles, protected legacy role, external Django secret, and available 20 GiB final RDS snapshot were preserved intentionally.

## Production-readiness rehearsal

The final rehearsal for `de3ba39d4f953ce8baa6e73167361d2063302a64`
proved the additional controls:

- image publication run [`34041754952`](https://github.com/yinon-mitin/Status-Page/actions/runs/34041754952);
- private one-off migration exited successfully and recorded the exact main SHA;
- CloudWatch dashboard and 18 alarms passed direct API validation;
- ECS reached web `2/2`, worker `1/1`, scheduler `1/1`; `/healthz` returned HTTP 200;
- semantic restore created an exact probe, restored a private temporary PostgreSQL
  instance, found the probe and populated `django_migrations`, then read back zero
  temporary DBs, snapshots, and active restore task definitions;
- approved OIDC rollout run [`34043025336`](https://github.com/yinon-mitin/Status-Page/actions/runs/34043025336) completed all services and health verification;
- refreshed Terraform plan returned detailed exit code `0` (`No changes`); and
- guarded destroy removed 76 Terraform-managed resources and returned state count
  `0`, `PRODUCTION_ENABLED=false`, and `MIGRATION_EVIDENCE_SHA=destroyed`.

The encrypted final snapshot
`yinon-status-page-prod-postgres-final-20260906154858` is available. Runtime ECR,
ALB, RDS, Redis, VPC, dashboard, and alarms were read back absent. SNS/Telegram and
the AWS Budget remain honest permission-bound non-claims: the operator is denied
`SNS:CreateTopic` and `budgets:ViewBudget`, and no integration credentials were
provided.

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
