#!/usr/bin/env python3
"""Fail-closed validation for saved production Terraform plans."""

from __future__ import annotations

import argparse
import json
import re
import sys
from collections.abc import Mapping
from pathlib import Path
from typing import Any


PROJECT = "yinon-status-page"
ENVIRONMENT = "prod"
PROTECTED_IDENTIFIERS = (
    '"statuspage-dev"',
    "statuspage-dev-",
    "yinon-status-page-iam-smoke-20260828",
    "yinon-status-page-tfstate-",
)
PREPARE_DESTROY_FIELDS = {
    "aws_db_instance.postgres[0]": {
        "deletion_protection",
        "final_snapshot_identifier",
    },
    "aws_lb.web[0]": {"enable_deletion_protection"},
    "aws_ecr_repository.app": {"force_delete"},
    "aws_ecr_repository.nginx": {"force_delete"},
}
ALLOWED_ADDRESS_PATTERNS = tuple(
    re.compile(pattern)
    for pattern in (
        r"^aws_cloudwatch_log_group\.(web|worker|scheduler)$",
        r"^aws_db_instance\.postgres\[0\]$",
        r"^aws_db_subnet_group\.postgres\[0\]$",
        r"^aws_ecr_lifecycle_policy\.(app|nginx)$",
        r"^aws_ecr_repository\.(app|nginx)$",
        r"^aws_ecs_cluster\.this$",
        r"^aws_ecs_service\.(web|worker|scheduler)\[0\]$",
        r"^aws_ecs_task_definition\.(web|worker|scheduler)$",
        r"^aws_elasticache_replication_group\.redis\[0\]$",
        r"^aws_elasticache_subnet_group\.redis\[0\]$",
        r"^aws_internet_gateway\.main\[0\]$",
        r"^aws_lb\.web\[0\]$",
        r"^aws_lb_listener\.(http|https)\[0\]$",
        r"^aws_lb_target_group\.web\[0\]$",
        r"^aws_route\.public_internet\[0\]$",
        r"^aws_route_table\.(app|public)\[0\]$",
        r'^aws_route_table_association\.(app|data|public)\["[ab]"\]$',
        r"^aws_secretsmanager_secret_policy\.rds_master\[0\]$",
        r"^aws_security_group\.(alb|ecs|endpoints|rds|redis)\[0\]$",
        r'^aws_subnet\.(app|data|public)\["[ab]"\]$',
        r"^aws_vpc\.main\[0\]$",
        r'^aws_vpc_endpoint\.interface\["(ecr\.api|ecr\.dkr|logs|secretsmanager)"\]$',
        r"^aws_vpc_endpoint\.s3\[0\]$",
        r"^aws_vpc_security_group_egress_rule\.(alb_to_ecs|ecs_all)\[0\]$",
        r"^aws_vpc_security_group_ingress_rule\.(alb_http|alb_https|ecs_from_alb|endpoints_from_ecs|rds_from_ecs|redis_from_ecs)\[0\]$",
        r"^aws_acm_certificate\.web\[0\]$",
    )
)
TAG_REQUIRED_TYPES = {
    "aws_acm_certificate",
    "aws_cloudwatch_log_group",
    "aws_db_instance",
    "aws_db_subnet_group",
    "aws_ecr_repository",
    "aws_ecs_cluster",
    "aws_ecs_service",
    "aws_ecs_task_definition",
    "aws_elasticache_replication_group",
    "aws_internet_gateway",
    "aws_lb",
    "aws_lb_target_group",
    "aws_route_table",
    "aws_security_group",
    "aws_subnet",
    "aws_vpc",
    "aws_vpc_endpoint",
}


def _changed_top_level_fields(before: Any, after: Any) -> set[str]:
    before_map = before if isinstance(before, Mapping) else {}
    after_map = after if isinstance(after, Mapping) else {}
    return {
        key
        for key in set(before_map) | set(after_map)
        if before_map.get(key) != after_map.get(key)
    }


def validate_plan(plan: Mapping[str, Any], mode: str, allow_empty: bool = False) -> list[str]:
    """Return safety errors for a Terraform plan JSON object."""
    if mode not in {"create", "prepare-destroy", "destroy"}:
        return [f"unsupported mode: {mode}"]
    if not isinstance(plan, Mapping):
        return ["plan must be a JSON object"]
    resource_changes = plan.get("resource_changes")
    if not isinstance(resource_changes, list):
        return ["resource_changes must be present as a list"]

    errors: list[str] = []
    actionable_changes = 0
    for index, change in enumerate(resource_changes):
        if not isinstance(change, Mapping):
            errors.append(f"resource_changes[{index}] must be an object")
            continue
        change_body = change.get("change")
        if not isinstance(change_body, Mapping):
            errors.append(f"resource_changes[{index}].change must be an object")
            continue
        actions = change_body.get("actions")
        if not isinstance(actions, list) or not actions or not all(isinstance(action, str) for action in actions):
            errors.append(f"resource_changes[{index}].change.actions must be a non-empty string list")
            continue
        if actions == ["no-op"]:
            continue
        actionable_changes += 1

        address = change.get("address")
        resource_type = change.get("type")
        if not isinstance(address, str) or not address:
            errors.append(f"resource_changes[{index}].address must be a non-empty string")
            continue
        if not isinstance(resource_type, str) or not resource_type:
            errors.append(f"{address}: type must be a non-empty string")
            continue
        encoded = json.dumps(change, sort_keys=True)

        if not any(pattern.fullmatch(address) for pattern in ALLOWED_ADDRESS_PATTERNS):
            errors.append(f"{address}: resource address is not allowlisted")
        if resource_type.startswith("aws_iam_"):
            errors.append(f"{address}: Terraform IAM resource is forbidden")
        for identifier in PROTECTED_IDENTIFIERS:
            if identifier in encoded:
                errors.append(f"{address}: protected identifier found: {identifier}")

        action_text = ",".join(actions)
        if mode == "create":
            task_definition_replacement = (
                resource_type == "aws_ecs_task_definition"
                and actions in (["delete", "create"], ["create", "delete"])
            )
            if actions not in (["create"], ["update"]) and not task_definition_replacement:
                errors.append(f"{address}: create mode forbids action {action_text}")
            identity_values = change_body.get("after")

        elif mode == "destroy":
            if actions != ["delete"]:
                errors.append(f"{address}: destroy mode permits delete actions only ({action_text})")
            identity_values = change_body.get("before")

        else:
            identity_values = None
            if actions != ["update"]:
                errors.append(f"{address}: prepare-destroy permits update actions only ({action_text})")
                continue
            allowed_fields = PREPARE_DESTROY_FIELDS.get(address)
            if allowed_fields is None:
                errors.append(f"{address}: unexpected prepare-destroy resource")
                continue
            changed_fields = _changed_top_level_fields(
                change_body.get("before"),
                change_body.get("after"),
            )
            for field in sorted(changed_fields - allowed_fields):
                errors.append(f"{address}: unexpected prepare-destroy field: {field}")

            after = change_body.get("after")
            if not isinstance(after, Mapping):
                errors.append(f"{address}: prepare-destroy after value must be an object")
                continue
            if address == "aws_db_instance.postgres[0]":
                snapshot = after.get("final_snapshot_identifier")
                if after.get("deletion_protection") is not False:
                    errors.append(f"{address}: unsafe prepare-destroy value for deletion_protection")
                if not isinstance(snapshot, str) or not re.fullmatch(
                    r"yinon-status-page-prod-postgres-final-[0-9]{14}", snapshot
                ):
                    errors.append(f"{address}: unsafe prepare-destroy value for final_snapshot_identifier")
            elif address == "aws_lb.web[0]" and after.get("enable_deletion_protection") is not False:
                errors.append(f"{address}: unsafe prepare-destroy value for enable_deletion_protection")
            elif address in {"aws_ecr_repository.app", "aws_ecr_repository.nginx"} and after.get("force_delete") is not True:
                errors.append(f"{address}: unsafe prepare-destroy value for force_delete")

        if mode in {"create", "destroy"} and resource_type in TAG_REQUIRED_TYPES:
            if not isinstance(identity_values, Mapping):
                errors.append(f"{address}: resource values required for identity validation")
            else:
                tags = identity_values.get("tags")
                if not isinstance(tags, Mapping):
                    errors.append(f"{address}: project/environment tags are required")
                elif tags.get("Project") != PROJECT or tags.get("Environment") != ENVIRONMENT:
                    errors.append(f"{address}: project/environment tags do not identify {PROJECT}-prod")

    if mode in {"prepare-destroy", "destroy"} and actionable_changes == 0 and not allow_empty:
        errors.append(f"{mode} plan must contain at least one actionable change")

    return errors


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("plan_json", type=Path)
    parser.add_argument("--mode", required=True, choices=("create", "prepare-destroy", "destroy"))
    parser.add_argument("--allow-empty", action="store_true")
    args = parser.parse_args()

    with args.plan_json.open(encoding="utf-8") as handle:
        plan = json.load(handle)
    errors = validate_plan(plan, args.mode, allow_empty=args.allow_empty)
    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1
    changes = sum(
        change.get("change", {}).get("actions") != ["no-op"]
        for change in plan.get("resource_changes", [])
    )
    print(f"validated mode={args.mode} changes={changes}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
