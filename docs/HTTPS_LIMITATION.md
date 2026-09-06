# HTTPS scope

[Русская версия](HTTPS_LIMITATION.ru.md)

The AWS demonstration uses HTTP at the load balancer. HTTPS is intentionally outside the implemented scope because the training account used for the project did not provide the required ACM permissions.

This is a deployment boundary, not an application architecture change. The network and Terraform code keep certificate support separate so it can be enabled in an account that provides ACM access.

## Enabling HTTPS in another account

1. Request an ACM certificate in the same AWS Region as the ALB.
2. Add the ACM DNS validation record to the authoritative DNS zone.
3. Wait until ACM reports the certificate as `ISSUED`.
4. Supply the certificate ARN to Terraform.
5. Create the HTTPS listener and redirect HTTP to HTTPS.
6. Update the application URL, trusted origins and secure-cookie settings.
7. Verify the certificate chain, hostname, redirect, health check and application login flow.

Do not point DNS at an HTTPS listener before the certificate is issued and attached. Do not describe the demonstration endpoint as HTTPS-enabled until the complete browser path has been tested.
