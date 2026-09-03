# HTTPS limitation and ACM recovery

## Current status

`http://status.yifilter.uk/` is intentionally an **HTTP-only demonstration endpoint**. It is a live ECS/ALB deployment, but it is **not HTTPS production-ready**. The ALB has only its HTTP listener, and no HTTP-to-HTTPS redirect is configured.

This is not an application or Terraform defect. The AWS identity available for this project lacks the ACM permissions required to request and validate a public certificate. The observed denial includes `acm-pca:ListCertificateAuthorities`; requesting a certificate also requires the relevant ACM public-certificate permissions. No attempt is made to bypass this boundary or to store a certificate/private key in GitHub or Terraform state.

Cloudflare must remain **DNS only** while ACM performs DNS validation. Proxying the record can hide or alter the validation path and is outside the supported recovery procedure.

## Required AWS access

An AWS administrator must grant the operator a least-privilege policy sufficient to:

- request a public ACM certificate for `status.yifilter.uk` in `il-central-1`;
- describe the certificate and validation records until it reaches `ISSUED`;
- attach the issued certificate to the existing production ALB HTTPS listener; and
- create or update the matching ALB listener and HTTP-to-HTTPS redirect through the reviewed Terraform change.

Use the smallest scope AWS supports for the hostname and the existing ALB. Do not grant `AdministratorAccess`, do not import a private key, and do not expose certificate material in repository variables or secrets.

## Recovery procedure

1. Keep the Cloudflare record for `status.yifilter.uk` in **DNS-only** mode.
2. Have the administrator grant the ACM/ELBv2 permissions above to the human operator. IAM roles remain a manually managed bootstrap boundary; Terraform must not manage IAM roles or policies.
3. On a protected branch, make the reviewed Terraform change that enables ACM certificate issuance, the HTTPS listener on port 443, and the port-80 redirect. Do not change the existing ECS, RDS, Redis, or legacy `statuspage-dev-*` resources.
4. Run `terraform fmt -check -recursive`, `terraform validate`, TFLint when installed, and an explicit production plan. Review that the plan changes only the intended `yinon-status-page-*` ingress/certificate resources.
5. Apply the approved plan. Copy the ACM DNS validation CNAME exactly into Cloudflare DNS; do not publish a proxy record.
6. Wait until ACM reports `ISSUED`, then verify the ALB HTTPS listener has the certificate attached and the HTTP listener redirects to HTTPS.
7. Verify externally: `https://status.yifilter.uk/`, `https://status.yifilter.uk/healthz`, the certificate hostname/chain, and the HTTP redirect. Record the evidence in `docs/DELIVERY_EVIDENCE.md`.

Until all seven steps are complete, documentation and release checks must continue to describe the public endpoint as HTTP-only.
