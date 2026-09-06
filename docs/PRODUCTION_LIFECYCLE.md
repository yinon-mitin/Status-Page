# Automated production lifecycle

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
3. applies ECS services using those immutable images;
4. points the workflow health check at the generated ALB DNS name; and
5. waits for all services and the provider-level `/healthz` probe.

Cloudflare DNS remains an external manual boundary unless a narrowly scoped Cloudflare API token is provided. ALB DNS is sufficient for provider-level lifecycle verification.

## Approved release

To approve and deploy one exact revision:

```bash
SHA="$(git rev-parse origin/main)"
CONFIRM_PRODUCTION_APPROVAL="$SHA" scripts/production_release.sh
```

The GitHub Environment approval runs in its own job. The following deploy job has no Environment attachment, so its OIDC token keeps the branch-bound immutable subject already allowed by the manually managed deployer role. The successful prerequisite publish job proves the immutable images were pushed; the restricted deployer does not need ECR or STS read permissions. The deployment script registers all three task definitions, stabilizes web before workers, probes health, and rolls changed service task definitions back on failure.

GitHub Actions owns post-bootstrap service task-definition revisions. Terraform ignores only the `task_definition` attribute on existing services so a later infrastructure apply cannot silently roll a release back; Terraform still owns service creation, networking, scaling counts, and destruction. The destroy script deregisters and requests deletion of every exact production task-definition family revision created by either owner.

### Training-account migration limitation

The deployer role cannot call `ecs:RunTask`, and IAM cannot be changed. A separate one-off migration task is therefore impossible in this account. The available safe path is the existing web entrypoint: `docker/start-web.sh` runs `python manage.py migrate --noinput` before Gunicorn, and web must stabilize before worker/scheduler rollout. This remains weaker than a dedicated migration gate because two web tasks may enter Django migration startup concurrently. Image rollback does not reverse a schema migration, so production schema changes must remain backward-compatible; a real production account should grant narrowly scoped `ecs:RunTask`/`ecs:DescribeTasks` for a dedicated migration task family.

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
- an approved GitHub run assumes the deployer role and completes entrypoint migration/rollout;
- destroy plan validation reports deletes only;
- Terraform state is empty afterward; and
- protected/manual boundaries still exist.

## Verified rehearsal

Revision `86d711d7c915d5efa66cb685a25964d7edf57a94` completed the full procedure:

- image publication: GitHub run `34030885146`;
- reviewer approval and deployer OIDC rollout: GitHub run `34031224217`;
- stable services: web `2/2`, worker `1/1`, scheduler `1/1`;
- provider health: two healthy ALB targets and successful `/healthz`;
- idempotency: Terraform reported no changes before teardown;
- destroy: 57 delete actions validated, applied, and followed by empty state and no exact-family task-definition revisions.

The runtime is currently absent and `PRODUCTION_ENABLED=false`.
