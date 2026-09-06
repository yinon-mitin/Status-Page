# Production readiness controls

This document defines the production-minded controls added after the first proven
create/deploy/destroy rehearsal. It distinguishes implementation from live proof.

## Scope decisions

- **HTTPS is intentionally excluded from this demonstration.** The endpoint remains
  HTTP-only because the training identity cannot complete the ACM path. This is not
  HTTPS production readiness; see [HTTPS limitation](HTTPS_LIMITATION.md).
- A separate cloud development environment and ECS autoscaling are intentionally
  outside the demonstration scope.
- Terraform does not create or change IAM roles or policies.

## One-off database migration gate

`run_migration_task.sh` registers a temporary, exact-family Fargate task definition
for the immutable `sha-<origin/main>` application image. It runs:

```text
python manage.py migrate --noinput
```

The task runs in private application subnets, without a public IP, and uses the
existing ECS execution/task roles and RDS-managed secret. The script waits for the
task to stop, requires container exit code `0`, records
`MIGRATION_EVIDENCE_SHA=<exact SHA>` as a GitHub repository Variable, and deletes
the temporary task-definition revision.

A production deploy is now fail-closed unless:

```text
MIGRATION_EVIDENCE_SHA == github.sha
```

Pushes to `main` publish immutable images only. Runtime deployment is accepted only
through an explicit deploy workflow dispatch after the operator-run migration task.
This works around the immutable GitHub deployer role, which lacks `ecs:RunTask` and
`ecs:DescribeTasks`, without broadening IAM. The production operator identity must
have those ECS calls; a live rehearsal is required before this control is marked
production-verified.

Destroy resets the migration evidence and removes only the exact production
one-off families.

## CloudWatch monitoring

Terraform creates one project dashboard and alarms for:

- ALB unhealthy targets, target 5xx responses, and p95 response time;
- ECS CPU, memory, and running-task count for web, worker, and scheduler;
- RDS CPU, free storage, and connection count;
- Redis engine CPU, memory usage, and evictions;
- recent application errors through a CloudWatch Logs Insights widget.

All alarm and recovery actions route to the exact SNS topic:

```text
arn:aws:sns:il-central-1:992382545251:yinon-status-page-prod-alerts
```

The topic policy allows publish only from project-prefixed CloudWatch alarms in the
same account and the exact project Budget. No IAM role is created.

## AWS Budget

Terraform creates a `$300 USD` monthly cost Budget filtered by the resource tag:

```text
Project=yinon-status-page
```

Notifications are emitted at:

- 50% actual spend;
- 80% actual spend;
- 100% forecast spend.

The `Project` cost-allocation tag must be active in AWS Billing. Tag activation and
cost data can take time to propagate. The Budget is project-scoped, not an assertion
about the entire training account.

## Telegram alert delivery

AWS SNS cannot post directly to the Telegram Bot API because Telegram requires a
custom request body. The repository therefore includes a narrow Cloudflare Worker
relay:

```text
CloudWatch alarms / AWS Budget -> SNS HTTPS subscription
  -> signed SNS message verification in Cloudflare Worker
  -> Telegram Bot API
```

The Worker:

- accepts only the exact production SNS Topic ARN;
- validates the AWS SNS signing certificate URL;
- verifies the SNS RSA signature before acting;
- confirms SNS subscriptions only after verification;
- stores Telegram token/chat ID as secret Worker bindings;
- exposes no token in Terraform, Git, logs, or alert payloads.

See [Production integrations](PRODUCTION_INTEGRATIONS.md) for setup and verification.

## DNS automation

`update_cloudflare_dns.py` can create or update only:

```text
CNAME status.yifilter.uk -> yinon-status-page-prod-alb-*.il-central-1.elb.amazonaws.com
proxied=false
```

The updater rejects every other hostname, zone, target class, and proxied mode. It
reads back the exact record after mutation. `production_create.sh` invokes it after
the ALB exists; it reports an explicit skip when Cloudflare credentials are absent.

## Backup restore rehearsal

`production_backup_restore_test.sh` performs a semantic restore, not only a snapshot
status check:

1. writes a unique probe row into a dedicated source database table through a
   private one-off ECS task;
2. creates and waits for a tagged manual RDS snapshot;
3. restores a disposable, encrypted, private RDS instance in the production data
   subnets with no public access and no deletion protection;
4. uses the existing source RDS-managed credential preserved by the PostgreSQL
   snapshot (the restore API's managed-password switch is Oracle-only);
5. runs a private Fargate validation task that requires both the exact probe row and
   populated `django_migrations` state;
6. removes the source probe/table;
7. deletes the disposable RDS instance, temporary snapshot, and one-off task
   definitions before reporting PASS.

A failed run invokes best-effort cleanup through an EXIT trap. Temporary resources
are exact-name/tag scoped. The rehearsal intentionally incurs short-lived RDS and
Fargate cost and must run only during an approved demonstration window.

## Evidence status

| Control | Implemented | Static/local validation | AWS/integration proof |
| --- | --- | --- | --- |
| CloudWatch alarms/dashboard | yes | Terraform plan validated | pending next live cycle |
| `$300` project Budget | yes | Terraform plan validated | pending next live cycle |
| one-off migration gate | yes | contracts/ShellCheck | pending operator permission proof |
| semantic RDS restore | yes | contracts/ShellCheck | pending live rehearsal |
| exact Cloudflare DNS | yes | unit/contract tests | pending credentials/live ALB |
| SNS-to-Telegram relay | yes | Worker unit tests | pending credentials/end-to-end alert |
| HTTPS | excluded | limitation documented | not implemented |
