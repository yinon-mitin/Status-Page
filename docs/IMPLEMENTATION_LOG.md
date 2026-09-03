# Implementation log

This log explains why project changes were made, what was verified, and any remaining constraints. It complements `CHANGELOG.md`, which is the concise change record.

## 2026-08-24 — Wednesday local-runtime milestone

**Decision:** use one application image for Django/Gunicorn, RQ Worker, and RQ Scheduler; use a separate NGINX image as the reverse proxy.

**Why:** this matches the source-derived runtime roles while keeping local Docker Compose and the future ECS task definitions aligned.

**Verification:** the complete Compose stack built successfully; NGINX returned HTTP 200 for the homepage and `/healthz`; Django system checks passed.

## 2026-08-24 — Thursday ECR/ECS and CI foundation

**Decision:** use immutable, SHA-tagged ECR images and GitHub OIDC rather than long-lived AWS access keys.

**Why:** each deployable image is traceable to a commit, and GitHub receives temporary AWS credentials only through a narrowly scoped role.

**Verification:** GitHub Actions validation completed successfully for commit `b2ee89f`. AWS now contains the two ECR repositories, lifecycle policies, ECS cluster, and CloudWatch log groups.

**Constraint:** the current IAM identity is allowed to create roles but denied `iam:ListRolePolicies`; Terraform cannot safely finish role-policy management or register task definitions. The exact required permissions are documented in `THURSDAY_STATUS.md`.

## 2026-08-24 — Docker build-context correction

**Decision:** exclude `.git` from Docker build context.

**Why:** Git history does not belong in application images and made the local build context about 687 MB. Excluding it reduces build transfer, avoids accidental inclusion of repository metadata, and improves CI/ECR build time.

**Verification:** rebuilt the Compose stack with a 59.48 kB application build context. All six services were up; `/healthz` and the homepage returned HTTP 200; `manage.py check` passed.

## 2026-08-24 — Network code prepared, not applied

**Decision:** define two public ALB subnets and two internal ECS application subnets in Terraform, disabled by default.

**Why:** this directly implements the agreed placement: public ALB across `il-central-1a`/`il-central-1b`, private ECS tasks, and security-group-only ALB-to-ECS traffic. Keeping `create_network = false` prevents unreviewed VPC resources and network cost while IAM/OIDC remains unresolved.

**Verification:** `terraform fmt -recursive`, `terraform validate`, and `docker compose config --quiet` passed. No AWS network resource was created by this change.

## 2026-08-24 — Repository presentation and documentation navigation

**Decision:** redesign the English primary README and its Russian counterpart as parallel project entry points, with explicit language-specific document links.

**Why:** readers should see the project purpose, verified status, quick start, and authoritative documentation without searching the repository. The Russian README must not merely point to English documents when a Russian translation exists.

**Implementation:** added a project icon, CI/licence/upstream badges, concise navigation, an honest delivery-status table, and an English/Russian documentation matrix. The README style follows the useful patterns collected by Awesome README: a clear visual identity, short description, badges, navigation, quick start, and structured links.

## 2026-08-24 — Offline CI smoke test

**Decision:** extend CI from static Compose/build validation to a full local runtime smoke test.

**Why:** a successful image build does not prove that the web, database, Redis, worker, scheduler, NGINX, migrations, or `/healthz` work together. This check gives fast feedback without AWS credentials or cloud resource changes.

**Implementation:** CI starts an isolated Compose project on port `18081`, waits for service health, checks NGINX `/healthz` and homepage access, runs `manage.py check`, and removes resources even after failure. The Makefile exposes matching local validation commands.

## 2026-08-24 — RQ end-to-end runtime verification

**Decision:** extend the offline smoke test with a real queue job rather than treating a running worker container as sufficient evidence.

**Why:** the application depends on Redis and RQ for background processing. A container can be running while its broker connection, job serialization, or worker processing is broken.

**Implementation:** `scripts/verify_runtime.py` resolves the Django project root explicitly, enqueues `sum([2, 3])` on the default queue, waits up to 30 seconds for the worker, and fails unless the job returns `5`. Local `make check` and GitHub Actions run the same script.

## 2026-08-26 — Offline security and Terraform quality gates

**Decision:** add repository-history secret scanning and a Terraform static-analysis gate that do not require AWS credentials.

**Why:** accidental credentials must be detected before a pull request is merged, while infrastructure code should be checked more deeply than syntax before it is allowed to reach the AWS plan/apply stage.

**Implementation:** `.github/workflows/security.yml` uses Gitleaks to inspect the complete Git history on pull requests and `main`. The validation workflow installs TFLint, initializes its recommended Terraform rules, and lints the entire `terraform/` tree after `fmt` and `validate`. `.dockerignore` also excludes Terraform's local cache, state, plans, and `.tfvars` files so they cannot inflate or leak into an application build context.

**Scope:** this is a static quality gate, not a live `terraform plan`. A credentialed plan remains intentionally separate because it needs the approved AWS IAM/OIDC role and would query real infrastructure.

## 2026-08-26 — Production decisions confirmed

**Decision:** deploy `status.yifilter.uk` through Cloudflare DNS-only to an ACM-protected ALB; keep RDS private; run two web tasks across `il-central-1a` and `il-central-1b`; retain RDS backups for two days; cap project spend at $300.

**Why:** this provides a real HTTPS production endpoint, compute-level multi-AZ availability, and a database that is not internet-addressable while respecting the project budget.

**Egress decision:** adopt VPC endpoints for ECR API/Docker, CloudWatch Logs, Secrets Manager, and S3. NAT Gateway remains an optional Terraform path for arbitrary external HTTPS calls, not a permanent resource. Two permanent NAT Gateways would consume most of the budget before application resources.

**State decision:** do not create DynamoDB locking. Local state is adequate during single-operator preparation; before automated GitHub Terraform apply, use an encrypted, versioned S3 backend with Terraform's native S3 lockfile.

## 2026-08-26 — Isolated ECR/ECS Terraform smoke-test design

**Decision:** test ECR and ECS using a separate local Terraform state and the temporary `yinon-status-page-smoke-*` resource prefix rather than modifying or destroying the existing `statuspage-dev` stack.

**Why:** the shared training account contains prior state and other students' resources. An isolated stack makes ownership visible through `Owner=yinon` and `Project=yinon-status-page` tags, allows a genuine idempotency check, and gives `terraform destroy` an exact and safe target.

**Scope:** the test creates two temporary ECR repositories and an ECS cluster. A Fargate task definition referencing the pushed local application image is optional and requires a project-scoped execution-role ARN. The test deliberately does not run a task or create network, IAM, data, or ingress resources.

**Result:** both locally built images were pushed with immutable tag `smoke-3910843` and verified by digest in ECR. The tagged ECS cluster was active, and `terraform plan -detailed-exitcode` reported **No changes**, proving idempotency for the created resources. The initial Fargate task-definition registration correctly failed because a private ECR image requires an ECS execution role; the smoke configuration now makes that resource conditional on a project-scoped role ARN instead of reusing the generic legacy role. The destroy plan removed only the two temporary repositories (including images) and temporary ECS cluster; final read-only checks confirmed the repositories were absent and the cluster was `INACTIVE`.

## 2026-08-29 — Manual IAM bootstrap boundary

**Decision:** production ECS IAM roles are managed manually outside Terraform.

**Implementation:** Terraform no longer declares IAM roles, role-policy attachments, inline role policies, or the GitHub OIDC publishing role. ECS task definitions consume `ecs_execution_role_arn` and `ecs_task_role_arn` inputs. The legacy `statuspage-dev` resources and temporary smoke role remain outside this change.

**Constraint:** role creation and credentialed AWS plan/apply require the approved IAM identity and exact project secret ARNs. No AWS mutation was performed from this checkout because AWS credentials were unavailable.

## 2026-09-01 — Isolated production foundation applied

**Decision:** create production foundation in a dedicated S3 state object, separate from legacy `statuspage-dev` state.

**Implementation:** created `yinon-status-page-tfstate-992382545251` with versioning, AES-256 default encryption, public-access block, BucketOwnerEnforced ownership, project tags, and native S3 lockfiles. Terraform applied 11 new `yinon-status-page-prod-*` resources: two immutable scan-on-push ECR repositories and lifecycle policies, three CloudWatch log groups, an ECS cluster, and web/worker/scheduler task definitions using manually managed role ARNs.

**Verification:** apply reported `11 added, 0 changed, 0 destroyed`; a refreshed `terraform plan -detailed-exitcode` reported `No changes`. No IAM, legacy `statuspage-dev`, or smoke resources were modified. ECS services remain disabled until network, data layer, exact secrets, ALB, and ACM are reviewed.

## 2026-09-03 — Network and private data plane applied; ACM permission blocked

**Implementation:** applied the reviewed `41 add / 0 change / 0 destroy` production network/data plan. The VPC, public/internal/data subnets in `il-central-1a` and `il-central-1b`, public ALB, target group, endpoint security group, ECR API/Docker, CloudWatch Logs, Secrets Manager, and S3 VPC endpoints, private PostgreSQL RDS, and encrypted private Redis are now live. NAT Gateway remains absent.

**Verification:** RDS is `available`, `publicly_accessible=false`, has two-day backups, and has an AWS-managed master secret; Redis is `available` with at-rest and transit encryption; the ALB and every VPC endpoint are active. Terraform state tracks the successful resources in the isolated production S3 backend.

**Blocker:** ACM certificate creation is the sole pending resource (`1 add / 0 change / 0 destroy`). The approved user is denied `acm:RequestCertificate`; no listener, DNS validation CNAME, Cloudflare cutover, or ECS service was attempted. Do not point the public hostname to private address `10.42.0.1`.
