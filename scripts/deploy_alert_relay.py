#!/usr/bin/env python3
"""Deploy the fixed Cloudflare SNS-to-Telegram Worker without logging secrets."""

from __future__ import annotations

import argparse
import json
import os
import re
import secrets
import stat
import sys
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any, Dict, Optional

API_BASE = "https://api.cloudflare.com/client/v4"
SCRIPT_NAME = "status-page-alert-relay"
KV_NAMESPACE_TITLE = "status-page-alert-relay-dedup"
TOPIC_ARN = "arn:aws:sns:il-central-1:992382545251:yinon-status-page-prod-alerts"
KNOWN_KEYS = {
    "CLOUDFLARE_API_TOKEN",
    "CLOUDFLARE_WORKERS_API_TOKEN",
    "CLOUDFLARE_ACCOUNT_ID",
    "CLOUDFLARE_ZONE_ID",
    "CLOUDFLARE_DNS_API_TOKEN",
    "TELEGRAM_BOT_TOKEN",
    "TELEGRAM_CHAT_ID",
    "ALERT_RELAY_URL",
}


def load_credentials(path: Path) -> Dict[str, str]:
    if not path.is_file():
        raise FileNotFoundError(f"integration credentials file does not exist: {path}")
    if stat.S_IMODE(path.stat().st_mode) & 0o077:
        raise PermissionError(f"{path} must have mode 0600")
    values: Dict[str, str] = {}
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        key, separator, value = line.partition("=")
        if separator and key in KNOWN_KEYS:
            values[key] = value
    return values


def api_request(
    token: str,
    method: str,
    path: str,
    data: Optional[bytes] = None,
    content_type: str = "application/json",
) -> Any:
    request = urllib.request.Request(
        f"{API_BASE}{path}",
        data=data,
        method=method,
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": content_type,
            "User-Agent": "status-page-worker-deployer/1",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            body = json.load(response)
    except urllib.error.HTTPError as error:
        raise RuntimeError(f"Cloudflare API returned HTTP {error.code}") from error
    except urllib.error.URLError as error:
        raise RuntimeError("Cloudflare API request failed") from error
    if not isinstance(body, dict) or body.get("success") is not True:
        raise RuntimeError("Cloudflare API returned an unsuccessful response")
    return body.get("result")


def multipart(metadata: Dict[str, Any], module: bytes) -> tuple[bytes, str]:
    boundary = f"status-page-{secrets.token_hex(16)}"
    chunks = []
    for name, value, content_type, filename in (
        ("metadata", json.dumps(metadata).encode(), "application/json", None),
        ("worker.mjs", module, "application/javascript+module", "worker.mjs"),
    ):
        disposition = f'form-data; name="{name}"'
        if filename:
            disposition += f'; filename="{filename}"'
        chunks.extend(
            [
                f"--{boundary}\r\n".encode(),
                f"Content-Disposition: {disposition}\r\n".encode(),
                f"Content-Type: {content_type}\r\n\r\n".encode(),
                value,
                b"\r\n",
            ]
        )
    chunks.append(f"--{boundary}--\r\n".encode())
    return b"".join(chunks), f"multipart/form-data; boundary={boundary}"


def persist_relay_url(path: Path, url: str) -> None:
    lines = path.read_text(encoding="utf-8").splitlines()
    replacement = f"ALERT_RELAY_URL={url}"
    updated = False
    for index, line in enumerate(lines):
        if line.startswith("ALERT_RELAY_URL="):
            lines[index] = replacement
            updated = True
    if not updated:
        lines.append(replacement)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    path.chmod(0o600)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--credentials-file",
        type=Path,
        default=Path.home() / ".config" / "status-page" / "integrations.env",
    )
    parser.add_argument(
        "--worker-module",
        type=Path,
        default=Path(__file__).resolve().parents[1]
        / "integrations"
        / "cloudflare-worker"
        / "src"
        / "worker.mjs",
    )
    args = parser.parse_args()

    try:
        credentials = load_credentials(args.credentials_file)
        token = credentials.get("CLOUDFLARE_WORKERS_API_TOKEN") or credentials.get(
            "CLOUDFLARE_API_TOKEN", ""
        )
        account_id = credentials.get("CLOUDFLARE_ACCOUNT_ID", "")
        telegram_token = credentials.get("TELEGRAM_BOT_TOKEN", "")
        telegram_chat_id = credentials.get("TELEGRAM_CHAT_ID", "")
        if not token or not telegram_token or not telegram_chat_id:
            raise ValueError("Worker token and Telegram bot/chat credentials are required")
        if not re.fullmatch(r"[a-f0-9]{32}", account_id):
            raise ValueError("CLOUDFLARE_ACCOUNT_ID must be a 32-character hexadecimal ID")
        if not args.worker_module.is_file():
            raise FileNotFoundError("Cloudflare Worker module is missing")

        namespaces = api_request(
            token,
            "GET",
            f"/accounts/{account_id}/storage/kv/namespaces?per_page=100",
        )
        matching_namespaces = [
            namespace
            for namespace in namespaces
            if isinstance(namespace, dict) and namespace.get("title") == KV_NAMESPACE_TITLE
        ]
        if len(matching_namespaces) > 1:
            raise RuntimeError("Multiple deduplication KV namespaces have the fixed title")
        if matching_namespaces:
            namespace_id = matching_namespaces[0].get("id")
        else:
            created_namespace = api_request(
                token,
                "POST",
                f"/accounts/{account_id}/storage/kv/namespaces",
                json.dumps({"title": KV_NAMESPACE_TITLE}).encode(),
            )
            namespace_id = (
                created_namespace.get("id")
                if isinstance(created_namespace, dict)
                else None
            )
        if not isinstance(namespace_id, str) or not re.fullmatch(
            r"[a-f0-9]{32}", namespace_id
        ):
            raise RuntimeError("Cloudflare did not return a valid deduplication KV namespace ID")

        metadata = {
            "main_module": "worker.mjs",
            "compatibility_date": "2025-01-01",
            "bindings": [
                {
                    "type": "kv_namespace",
                    "name": "SNS_DEDUP",
                    "namespace_id": namespace_id,
                },
                {"type": "secret_text", "name": "SNS_TOPIC_ARN", "text": TOPIC_ARN},
                {
                    "type": "secret_text",
                    "name": "TELEGRAM_BOT_TOKEN",
                    "text": telegram_token,
                },
                {
                    "type": "secret_text",
                    "name": "TELEGRAM_CHAT_ID",
                    "text": telegram_chat_id,
                },
            ],
        }
        body, content_type = multipart(metadata, args.worker_module.read_bytes())
        api_request(
            token,
            "PUT",
            f"/accounts/{account_id}/workers/scripts/{SCRIPT_NAME}",
            body,
            content_type,
        )
        api_request(
            token,
            "POST",
            f"/accounts/{account_id}/workers/scripts/{SCRIPT_NAME}/subdomain",
            json.dumps({"enabled": True, "previews_enabled": False}).encode(),
        )
        settings = api_request(
            token,
            "GET",
            f"/accounts/{account_id}/workers/scripts/{SCRIPT_NAME}/settings",
        )
        binding_names = {
            binding.get("name")
            for binding in settings.get("bindings", [])
            if isinstance(binding, dict)
        }
        required = {
            "SNS_DEDUP",
            "SNS_TOPIC_ARN",
            "TELEGRAM_BOT_TOKEN",
            "TELEGRAM_CHAT_ID",
        }
        if not required.issubset(binding_names):
            raise RuntimeError("Worker settings read-back is missing required bindings")
        subdomain = api_request(token, "GET", f"/accounts/{account_id}/workers/subdomain")
        suffix = subdomain.get("subdomain") if isinstance(subdomain, dict) else None
        if not isinstance(suffix, str) or not suffix:
            raise RuntimeError("Cloudflare Workers subdomain is not configured")
        relay_url = f"https://{SCRIPT_NAME}.{suffix}.workers.dev/"
        with urllib.request.urlopen(relay_url, timeout=30) as response:
            health = json.load(response)
        if health.get("status") != "ok":
            raise RuntimeError("Worker health read-back failed")
        persist_relay_url(args.credentials_file, relay_url)
    except (FileNotFoundError, PermissionError, ValueError, RuntimeError, urllib.error.URLError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1

    print(f"alert_relay=verified url={relay_url}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
