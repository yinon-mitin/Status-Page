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
