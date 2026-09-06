#!/usr/bin/env python3
"""Update the one approved Cloudflare DNS record to the production ALB."""

from __future__ import annotations

import argparse
import json
import os
import re
import stat
import sys
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any, Dict, Optional

DOMAIN = "status.yifilter.uk"
ZONE_NAME = "yifilter.uk"
API_BASE = "https://api.cloudflare.com/client/v4"
ALB_PATTERN = re.compile(
    r"^yinon-status-page-prod-alb-[a-z0-9-]+\.il-central-1\.elb\.amazonaws\.com\.?$"
)


def validate_domain(domain: str) -> None:
    if domain != DOMAIN:
        raise ValueError(f"DNS automation is confined to {DOMAIN}")


def validate_target(target: str) -> str:
    normalized = target.rstrip(".")
    if not ALB_PATTERN.fullmatch(target):
        raise ValueError("target must be the generated yinon-status-page-prod ALB DNS name")
    return normalized


def load_credentials(path: Path) -> None:
    if not path.exists():
        return
    mode = stat.S_IMODE(path.stat().st_mode)
    if mode & 0o077:
        raise PermissionError(f"{path} must not be accessible by group or others")
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        key, separator, value = line.partition("=")
        if not separator or key not in {
            "CLOUDFLARE_API_TOKEN",
            "CLOUDFLARE_DNS_API_TOKEN",
            "CLOUDFLARE_ZONE_ID",
            "CLOUDFLARE_ACCOUNT_ID",
            "TELEGRAM_BOT_TOKEN",
            "TELEGRAM_CHAT_ID",
        }:
            continue
        os.environ.setdefault(key, value)


class CloudflareClient:
    def __init__(self, token: str) -> None:
        if not token:
            raise ValueError("Cloudflare API token is required")
        self._token = token

    def request(
        self, method: str, path: str, payload: Optional[Dict[str, Any]] = None
    ) -> Any:
        data = None if payload is None else json.dumps(payload).encode()
        request = urllib.request.Request(
            f"{API_BASE}{path}",
            data=data,
            method=method,
            headers={
                "Authorization": f"Bearer {self._token}",
                "Content-Type": "application/json",
                "User-Agent": "status-page-dns-automation/1",
            },
        )
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                body = json.load(response)
        except urllib.error.HTTPError as error:
            raise RuntimeError(f"Cloudflare API returned HTTP {error.code}") from error
        except urllib.error.URLError as error:
            raise RuntimeError("Cloudflare API request failed") from error
        if not isinstance(body, dict) or body.get("success") is not True:
            raise RuntimeError("Cloudflare API returned an unsuccessful response")
        return body.get("result")


def update_record(client: CloudflareClient, zone_id: str, target: str) -> str:
    zone = client.request("GET", f"/zones/{zone_id}")
    if not isinstance(zone, dict) or zone.get("name") != ZONE_NAME:
        raise RuntimeError(f"zone ID must resolve exactly to {ZONE_NAME}")

    records = client.request(
        "GET",
        f"/zones/{zone_id}/dns_records?type=CNAME&name={DOMAIN}",
    )
    if not isinstance(records, list) or len(records) > 1:
        raise RuntimeError(f"expected zero or one CNAME record for {DOMAIN}")

    payload = {
        "type": "CNAME",
        "name": DOMAIN,
        "content": target,
        "ttl": 1,
        "proxied": False,
        "comment": "Managed by Status-Page exact-domain automation",
    }
    if records:
        record_id = records[0].get("id")
        if not isinstance(record_id, str) or not record_id:
            raise RuntimeError("existing Cloudflare record has no stable ID")
        client.request("PUT", f"/zones/{zone_id}/dns_records/{record_id}", payload)
    else:
        created = client.request("POST", f"/zones/{zone_id}/dns_records", payload)
        record_id = created.get("id") if isinstance(created, dict) else None
        if not isinstance(record_id, str) or not record_id:
            raise RuntimeError("Cloudflare did not return the created record ID")

    verified = client.request("GET", f"/zones/{zone_id}/dns_records/{record_id}")
    expected = {"type": "CNAME", "name": DOMAIN, "content": target, "proxied": False}
    if not isinstance(verified, dict) or any(verified.get(key) != value for key, value in expected.items()):
        raise RuntimeError("Cloudflare DNS read-back did not match the requested record")
    return record_id


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--domain", default=DOMAIN)
    parser.add_argument("--target", required=True)
    parser.add_argument("--if-configured", action="store_true")
    parser.add_argument(
        "--credentials-file",
        type=Path,
        default=Path.home() / ".config" / "status-page" / "integrations.env",
    )
    args = parser.parse_args()

    try:
        validate_domain(args.domain)
        target = validate_target(args.target)
        load_credentials(args.credentials_file)
        token = os.environ.get("CLOUDFLARE_DNS_API_TOKEN") or os.environ.get(
            "CLOUDFLARE_API_TOKEN", ""
        )
        zone_id = os.environ.get("CLOUDFLARE_ZONE_ID", "")
        if args.if_configured and (not token or not zone_id):
            print("cloudflare_dns=skipped reason=credentials-not-configured")
            return 0
        if not zone_id or not re.fullmatch(r"[a-f0-9]{32}", zone_id):
            raise ValueError("CLOUDFLARE_ZONE_ID must be a 32-character hexadecimal ID")
        record_id = update_record(CloudflareClient(token), zone_id, target)
    except (ValueError, PermissionError, RuntimeError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1

    print(f"cloudflare_dns=verified domain={DOMAIN} target={target} record_id={record_id}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
