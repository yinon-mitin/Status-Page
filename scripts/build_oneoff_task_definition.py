#!/usr/bin/env python3
"""Build a constrained ECS one-off task definition from an existing app task."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any, Dict, List

ALLOWED_FIELDS = (
    "taskRoleArn",
    "executionRoleArn",
    "networkMode",
    "volumes",
    "placementConstraints",
    "requiresCompatibilities",
    "cpu",
    "memory",
    "runtimePlatform",
    "ephemeralStorage",
    "pidMode",
    "ipcMode",
    "proxyConfiguration",
    "inferenceAccelerators",
)


def build_definition(
    source: Dict[str, Any],
    family: str,
    image: str,
    command: List[str],
    environment: Dict[str, str],
    secret_overrides: Dict[str, str],
) -> Dict[str, Any]:
    if not family.startswith("yinon-status-page-prod-"):
        raise ValueError("one-off task family must be production project-scoped")
    containers = source.get("containerDefinitions")
    if not isinstance(containers, list) or len(containers) != 1:
        raise ValueError("source must contain exactly one application container")
    container = dict(containers[0])
    if container.get("name") not in {"worker", "app"}:
        raise ValueError("source container is not an approved application container")
    if not image.startswith("992382545251.dkr.ecr.il-central-1.amazonaws.com/yinon-status-page-prod-app:sha-"):
        raise ValueError("one-off task image is outside the immutable production app repository")
    container["name"] = "oneoff"
    container["image"] = image
    container["command"] = command
    container.pop("healthCheck", None)

    values = {
        entry["name"]: entry["value"]
        for entry in container.get("environment", [])
        if isinstance(entry, dict) and "name" in entry and "value" in entry
    }
    values.update(environment)
    container["environment"] = [
        {"name": name, "value": value} for name, value in sorted(values.items())
    ]

    secrets = {
        entry["name"]: entry["valueFrom"]
        for entry in container.get("secrets", [])
        if isinstance(entry, dict) and "name" in entry and "valueFrom" in entry
    }
    secrets.update(secret_overrides)
    container["secrets"] = [
        {"name": name, "valueFrom": value} for name, value in sorted(secrets.items())
    ]

    result = {"family": family, "containerDefinitions": [container]}
    result.update({field: source[field] for field in ALLOWED_FIELDS if field in source})
    return result


def parse_pairs(values: List[str]) -> Dict[str, str]:
    result = {}
    for value in values:
        key, separator, item = value.partition("=")
        if not separator or not key:
            raise ValueError(f"expected NAME=VALUE, got {value!r}")
        result[key] = item
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--family", required=True)
    parser.add_argument("--image", required=True)
    parser.add_argument("--command-json", required=True)
    parser.add_argument("--environment", action="append", default=[])
    parser.add_argument("--secret", action="append", default=[])
    args = parser.parse_args()

    source_body = json.loads(args.source.read_text(encoding="utf-8"))
    source = source_body.get("taskDefinition", source_body)
    command = json.loads(args.command_json)
    if not isinstance(command, list) or not all(isinstance(item, str) for item in command):
        raise ValueError("command JSON must be a string list")
    definition = build_definition(
        source,
        args.family,
        args.image,
        command,
        parse_pairs(args.environment),
        parse_pairs(args.secret),
    )
    args.output.write_text(json.dumps(definition), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
