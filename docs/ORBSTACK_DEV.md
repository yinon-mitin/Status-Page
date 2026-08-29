# OrbStack development VM

This repository includes a local Cloud-Init bootstrap for an Ubuntu 24.04 ARM64
VM managed by OrbStack. It exercises Docker, Compose, systemd startup, and
recovery after a Linux VM restart without requiring Docker Desktop.

## Prerequisites

- macOS with OrbStack installed;
- `orbctl` available on `PATH`;
- this repository checked out locally.

## Create the VM

From the repository root:

```bash
orbctl create \
  --arch arm64 \
  --cpus 4 \
  --memory 8G \
  --disk 64G \
  --user statuspage \
  --user-data "$PWD/infra/cloud-init/statuspage-dev.yaml" \
  ubuntu:24.04 \
  statuspage-dev
```

Wait for Cloud-Init:

```bash
orbctl run -m statuspage-dev cloud-init status --wait
```

## Install the checkout into the VM

```bash
orbctl push -m statuspage-dev "$PWD" /home/statuspage/Status-Page
orbctl run -m statuspage-dev -u root -- sh -lc \
  'rm -rf /opt/status-page && mv /home/statuspage/Status-Page /opt/status-page && chown -R statuspage:statuspage /opt/status-page && systemctl start statuspage-dev.service'
```

The VM bootstrap owns the Compose lifecycle through
`statuspage-dev.service`. It starts the stack after Docker and networking are
ready and stops it before shutdown.

## Verify the VM

```bash
orbctl run -m statuspage-dev -u root /usr/local/bin/statuspage-dev-check
```

The check verifies Compose status, `/healthz`, Django system checks, Django
tests, and the RQ smoke test.

## Reboot recovery test

```bash
orbctl restart statuspage-dev
orbctl run -m statuspage-dev -u root systemctl is-active --wait statuspage-dev.service
orbctl run -m statuspage-dev -u statuspage -- sh -lc \
  'curl --fail --silent --show-error http://127.0.0.1:8081/healthz'
```

The expected response is `{"status": "ok"}`. The first few seconds after a
reboot may report `activating` while Compose healthchecks complete; wait for
`active` before judging recovery.

This VM is a local development and substitute-validation environment. It does
not prove AWS VPC, ALB, RDS, Redis, public DNS, or ECS behavior.
