# Delivery validation

[Русская версия](DELIVERY_EVIDENCE.ru.md)

This document records the verification performed against the project. It is a historical proof of the implementation, not a claim that a permanently running environment exists.

## Validated lifecycle

The AWS rehearsal completed the following sequence:

```text
validate source and Terraform
  -> create private AWS runtime
  -> publish immutable images
  -> run one-off database migration
  -> deploy web, worker and scheduler
  -> verify health and monitoring
  -> restore and inspect a database snapshot
  -> confirm an idempotent Terraform plan
  -> apply a guarded destroy
  -> verify empty Terraform state
```

## Results

| Area | Validation result |
| --- | --- |
| Local runtime | Six Docker Compose services reached healthy state |
| Application | Homepage and `/healthz` returned HTTP 200 |
| Background work | RQ Worker completed an enqueued smoke job |
| Container publication | Application and NGINX images were published under immutable Git SHA tags |
| Database migration | A private one-off Fargate task completed for the exact release revision |
| ECS deployment | Web reached `2/2`; worker and scheduler reached `1/1` desired/running tasks |
| Load balancing | Both web targets became healthy |
| Monitoring | CloudWatch accepted the dashboard and all 18 alarms; values were read back through the AWS API |
| Restore rehearsal | RDS restored a snapshot into a disposable private instance; the probe record and Django migration history were verified |
| Idempotency | A refreshed Terraform plan returned `No changes` |
| Teardown | The guarded destroy removed all 76 Terraform-managed runtime resources and returned state to zero |
| Cleanup | No temporary restore database, snapshot or active restore task remained |

## Continuous checks

The repository's `make verify` gate covers:

- Docker and application health;
- Django tests and system checks;
- Terraform formatting and validation;
- TFLint and shell syntax checks;
- lifecycle automation contract tests;
- Cloudflare Worker tests;
- Cloud-Init contract validation;
- documentation build in strict mode.

GitHub's separate security workflow checks the complete repository history with Gitleaks. The final project revision passed both the validation and security workflows. Production jobs remain opt-in so an ordinary push cannot create AWS resources.

## External integration scope

Cloudflare DNS and Telegram alert delivery are optional additions outside the core AWS lifecycle. Their code and tests are part of the repository. Live delivery requires operator-owned Cloudflare and Telegram credentials plus an SNS topic supplied by an AWS account with the required permissions.

## Evidence boundary

The rehearsal proves that the repository can create, update, inspect, restore and remove the defined environment. The runtime was intentionally removed after validation to stop ongoing cloud charges. Long-lived bootstrap and recovery assets are separate from Terraform's disposable runtime scope.

Historical GitHub Actions runs remain available in the public repository. The implementation and executable validators are the source of truth if this document and the code ever diverge.
