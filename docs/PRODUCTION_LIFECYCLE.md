# Automated production lifecycle

[Русская версия](PRODUCTION_LIFECYCLE.ru.md)

## Scope

The production runtime is reproducible after three explicit bootstrap boundaries exist:

1. the encrypted/versioned S3 backend bucket;
2. the manually managed ECS execution/task and GitHub OIDC roles; and
3. the manually managed Django secret in Secrets Manager.

Terraform never manages IAM roles or policies. It creates the VPC, endpoints, ALB, ECR, ECS definitions/services, RDS, Redis, log groups, and the resource policy that grants the exact ECS execution role access to the newly generated RDS master secret.

The four roles are a one-time manual setup required by the training account:

- ECS execution role: ECS tasks trust plus the standard execution policy and access to the external Django secret;
- ECS task role: ECS tasks trust, with no broad application permissions;
- GitHub publisher: branch-bound OIDC trust and ECR push only;
- GitHub deployer: the same branch-bound OIDC trust, ECS describe/register/update only, and `iam:PassRole` limited to the two ECS roles.

The account does not allow this project to change IAM. Do not add IAM resources to Terraform and do not broaden the roles as a workaround.

## Safety properties

- Every saved plan is converted to JSON and checked by `scripts/validate_terraform_plan.py`.
- Every mutating script requires a clean exact `origin/main` checkout, includes untracked files in the cleanliness check, and rejects implicit root-module `*.auto.tfvars*` files.
- Create mode rejects every delete action, Terraform IAM resource, state-bucket identifier, protected role, and `statuspage-dev-*` identifier.
- Destroy requires the exact confirmation `yinon-status-page-prod`.
- Destroy first applies a target-limited preparation plan that can only disable ALB/RDS deletion protection, enable deletion of images in the two production ECR repositories, and set a unique final RDS snapshot name.
- The second plan permits delete actions only and verifies empty Terraform state afterward.
- `PRODUCTION_ENABLED=false` pauses GitHub publication/deployment after teardown.

## Configuration

Create the ignored private input file from the example and replace only the account/role/secret placeholders:

```bash
cp terraform/environments/prod.tfvars.example terraform/prod.tfvars
```

Do not add database/Redis endpoints or an RDS password ARN. Terraform derives the live endpoints and the RDS-managed secret ARN on every recreation.

## Create

From a clean checkout of `origin/main`:

```bash
AWS_PROFILE=status-page scripts/production_create.sh
```

The command:

1. applies the reviewed infrastructure with ECS services disabled;
2. enables the release gate and dispatches an OIDC image-only build for exact `main`;
3. runs a private one-off migration task with the exact immutable application image;
4. applies ECS services only after migration exit `0` and exact-SHA evidence;
5. points the workflow health check at the generated ALB DNS name; and
6. waits for all services and the provider-level `/healthz` probe.

When narrowly scoped Cloudflare credentials are configured, creation updates only
the DNS-only CNAME `status.yifilter.uk` to the generated ALB. Without credentials,
the DNS step reports an explicit skip; ALB DNS remains sufficient for provider-level
lifecycle verification.

The one-off migration uses the operator identity because the immutable GitHub
deployer role does not have `ecs:RunTask` or `ecs:DescribeTasks`. The path fails
closed if those calls are unavailable; it does not silently return to concurrent
web-startup migrations.

## Approved release

To approve and deploy one exact revision:

```bash
SHA="$(git rev-parse origin/main)"
CONFIRM_PRODUCTION_APPROVAL="$SHA" scripts/production_release.sh
```

The GitHub Environment approval runs in its own job. The following deploy job has no Environment attachment, so its OIDC token keeps the branch-bound immutable subject already allowed by the manually managed deployer role. The successful prerequisite publish job proves the immutable images were pushed; the restricted deployer does not need ECR or STS read permissions. The deployment script registers all three task definitions, stabilizes web before workers, probes health, and rolls changed service task definitions back on failure.

GitHub Actions owns post-bootstrap service task-definition revisions. Terraform ignores only the `task_definition` attribute on existing services so a later infrastructure apply cannot silently roll a release back; Terraform still owns service creation, networking, scaling counts, and destruction. The destroy script deregisters and requests deletion of every exact production task-definition family revision created by either owner.

### Migration execution

The immutable GitHub deployer role cannot call `ecs:RunTask`, and IAM cannot be
changed. The operator lifecycle therefore runs a separate private migration task
with the approved AWS profile and records exact-SHA evidence before workflow
dispatch. Terraform disables startup migrations for production web tasks; local
Compose retains startup migrations by default. Image rollback still does not
reverse a schema migration, so production migrations must remain backward-compatible.

## Destroy

```bash
CONFIRM_DESTROY=yinon-status-page-prod \
AWS_PROFILE=status-page \
scripts/production_destroy.sh
```

The state bucket, manual IAM roles, external Django secret, final RDS snapshots, and Cloudflare record are retained. RDS snapshots, Secrets Manager, and S3 versions can still incur small storage charges and require a separate explicit retention decision.

## Verification standard

A lifecycle is proven only when one exact revision has all of the following evidence:

- static checks and contract tests pass;
- create plan validation reports no deletes;
- provider reads show stable ECS services and HTTP 200 health;
- a private one-off migration succeeds for the exact image revision;
- an approved GitHub run assumes the deployer role and completes rollout;
- destroy plan validation reports deletes only;
- Terraform state is empty afterward; and
- protected/manual boundaries still exist.

## Verified rehearsal

Revision `de3ba39d4f953ce8baa6e73167361d2063302a64` completed the full procedure:

- image publication: GitHub run `34041754952`;
- private migration task: exact revision recorded before deployment;
- reviewer approval and deployer OIDC rollout: GitHub run `34043025336`;
- stable services: web `2/2`, worker `1/1`, scheduler `1/1`;
- provider health: two healthy ALB targets and successful `/healthz`;
- monitoring: CloudWatch dashboard and 18 alarms passed API read-back;
- recovery: a temporary private RDS restore contained the exact semantic probe and Django migration history, then cleaned up completely;
- idempotency: Terraform reported no changes before teardown;
- destroy: 76 resources removed, followed by empty state and no exact-family task-definition revisions.
