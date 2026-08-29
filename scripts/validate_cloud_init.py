#!/usr/bin/env python3
"""Validate the repository's local Cloud-Init contract."""

from pathlib import Path

import yaml


REQUIRED_TOP_LEVEL_KEYS = {
    "#cloud-config": None,
    "users": list,
    "write_files": list,
    "runcmd": list,
}


def main():
    path = Path("infra/cloud-init/statuspage-dev.yaml")
    text = path.read_text(encoding="utf-8")
    if not text.startswith("#cloud-config\n"):
        raise SystemExit("Cloud-Init file must start with #cloud-config")

    config = yaml.safe_load(text)
    if not isinstance(config, dict):
        raise SystemExit("Cloud-Init document must be a mapping")

    for key, expected_type in REQUIRED_TOP_LEVEL_KEYS.items():
        if key == "#cloud-config":
            continue
        if key not in config:
            raise SystemExit(f"Missing required Cloud-Init key: {key}")
        if not isinstance(config[key], expected_type):
            raise SystemExit(f"Cloud-Init key {key} must be {expected_type.__name__}")

    files = {item.get("path") for item in config["write_files"] if isinstance(item, dict)}
    required_files = {
        "/etc/systemd/system/statuspage-dev.service",
        "/usr/local/bin/statuspage-dev-check",
    }
    missing_files = required_files - files
    if missing_files:
        raise SystemExit(f"Missing Cloud-Init write_files entries: {sorted(missing_files)}")

    commands = "\n".join(str(command) for command in config["runcmd"])
    for required_command in ("systemctl enable --now docker", "systemctl enable statuspage-dev.service"):
        if required_command not in commands:
            raise SystemExit(f"Missing required Cloud-Init command: {required_command}")

    print(f"Cloud-Init contract valid: {path}")


if __name__ == "__main__":
    main()
