import importlib.util
import json
import stat
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
VALIDATOR_PATH = ROOT / "scripts" / "validate_terraform_plan.py"


def load_validator():
    spec = importlib.util.spec_from_file_location("validate_terraform_plan", VALIDATOR_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Cannot load {VALIDATOR_PATH}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def resource_change(address, resource_type, actions, before=None, after=None):
    return {
        "address": address,
        "type": resource_type,
        "change": {
            "actions": actions,
            "before": before,
            "after": after,
        },
    }


class TerraformPlanSafetyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.validator = load_validator()

    def test_create_accepts_only_non_destructive_project_changes(self):
        plan = {
            "resource_changes": [
                resource_change(
                    "aws_vpc.main[0]",
                    "aws_vpc",
                    ["create"],
                    after={"tags": {"Project": "yinon-status-page", "Environment": "prod"}},
                )
            ]
        }
        self.assertEqual([], self.validator.validate_plan(plan, "create"))

    def test_malformed_plan_is_rejected(self):
        self.assertIn("resource_changes", "\n".join(self.validator.validate_plan({}, "destroy")))

    def test_missing_actions_are_rejected(self):
        plan = {"resource_changes": [{"address": "aws_vpc.main[0]", "type": "aws_vpc", "change": {}}]}
        self.assertIn("actions", "\n".join(self.validator.validate_plan(plan, "destroy")))

    def test_create_rejects_delete(self):
        plan = {
            "resource_changes": [
                resource_change("aws_vpc.main[0]", "aws_vpc", ["delete"], before={})
            ]
        }
        self.assertIn("create mode forbids action delete", "\n".join(self.validator.validate_plan(plan, "create")))

    def test_create_accepts_task_definition_revision_replacement(self):
        plan = {
            "resource_changes": [
                resource_change(
                    "aws_ecs_task_definition.web",
                    "aws_ecs_task_definition",
                    ["delete", "create"],
                    before={"tags": {"Project": "yinon-status-page", "Environment": "prod"}},
                    after={"tags": {"Project": "yinon-status-page", "Environment": "prod"}},
                )
            ]
        }
        self.assertEqual([], self.validator.validate_plan(plan, "create"))

    def test_destroy_rejects_non_delete(self):
        plan = {
            "resource_changes": [
                resource_change("aws_vpc.main[0]", "aws_vpc", ["update"], before={}, after={})
            ]
        }
        self.assertIn("destroy mode permits delete actions only", "\n".join(self.validator.validate_plan(plan, "destroy")))

    def test_all_modes_reject_terraform_iam_resources(self):
        plan = {
            "resource_changes": [
                resource_change("aws_iam_role.bad", "aws_iam_role", ["create"], after={})
            ]
        }
        self.assertIn("Terraform IAM resource is forbidden", "\n".join(self.validator.validate_plan(plan, "create")))

    def test_all_modes_reject_protected_legacy_identifiers(self):
        plan = {
            "resource_changes": [
                resource_change(
                    "aws_ecs_cluster.bad",
                    "aws_ecs_cluster",
                    ["delete"],
                    before={"name": "statuspage-dev-cluster"},
                )
            ]
        }
        self.assertIn("protected identifier", "\n".join(self.validator.validate_plan(plan, "destroy")))

    def test_exact_legacy_cluster_identifier_is_rejected(self):
        plan = {
            "resource_changes": [
                resource_change("aws_ecs_cluster.this", "aws_ecs_cluster", ["delete"], before={"name": "statuspage-dev"})
            ]
        }
        self.assertIn("protected identifier", "\n".join(self.validator.validate_plan(plan, "destroy")))

    def test_destroy_rejects_unknown_resource_address(self):
        plan = {
            "resource_changes": [
                resource_change("aws_s3_bucket.unrelated", "aws_s3_bucket", ["delete"], before={})
            ]
        }
        self.assertIn("resource address is not allowlisted", "\n".join(self.validator.validate_plan(plan, "destroy")))

    def test_prepare_destroy_accepts_only_known_safety_updates(self):
        plan = {
            "resource_changes": [
                resource_change(
                    "aws_db_instance.postgres[0]",
                    "aws_db_instance",
                    ["update"],
                    before={"deletion_protection": True, "final_snapshot_identifier": "old"},
                    after={
                        "deletion_protection": False,
                        "final_snapshot_identifier": "yinon-status-page-prod-postgres-final-20260906120000",
                    },
                ),
                resource_change(
                    "aws_ecr_repository.app",
                    "aws_ecr_repository",
                    ["update"],
                    before={"force_delete": False},
                    after={"force_delete": True},
                ),
            ]
        }
        self.assertEqual([], self.validator.validate_plan(plan, "prepare-destroy"))

    def test_prepare_destroy_rejects_unrelated_field_change(self):
        plan = {
            "resource_changes": [
                resource_change(
                    "aws_db_instance.postgres[0]",
                    "aws_db_instance",
                    ["update"],
                    before={"instance_class": "db.t4g.micro"},
                    after={"instance_class": "db.t4g.large"},
                )
            ]
        }
        self.assertIn("unexpected prepare-destroy field", "\n".join(self.validator.validate_plan(plan, "prepare-destroy")))

    def test_prepare_destroy_rejects_unsafe_postcondition(self):
        plan = {
            "resource_changes": [
                resource_change(
                    "aws_ecr_repository.app",
                    "aws_ecr_repository",
                    ["update"],
                    before={"force_delete": True},
                    after={"force_delete": False},
                )
            ]
        }
        self.assertIn("unsafe prepare-destroy value", "\n".join(self.validator.validate_plan(plan, "prepare-destroy")))


class DeliveryWorkflowContractTests(unittest.TestCase):
    def test_release_workflow_is_fail_closed_and_approval_precedes_deploy(self):
        workflow = (ROOT / ".github" / "workflows" / "publish-ecr.yml").read_text()
        self.assertNotIn("statuspage-dev-app", workflow)
        self.assertNotIn("statuspage-dev-nginx", workflow)
        self.assertIn("PRODUCTION_ENABLED", workflow)
        self.assertIn("production-approval:", workflow)
        self.assertIn("environment:\n      name: production", workflow)
        self.assertIn("needs: [release-gate, publish, production-approval]", workflow)
        deploy = workflow.split("  deploy-production:", 1)[1]
        self.assertNotIn("\n    environment:", deploy)
        self.assertIn("github.ref == 'refs/heads/main'", workflow)
        deploy_script = (ROOT / "scripts" / "deploy_ecs_release.sh").read_text()
        self.assertNotIn("run-task", deploy_script)
        self.assertNotIn("describe-images", deploy_script)
        self.assertNotIn("get-caller-identity", deploy)
        self.assertIn("rollback", deploy_script)
        web_entrypoint = (ROOT / "docker" / "start-web.sh").read_text()
        self.assertLess(web_entrypoint.index("manage.py migrate"), web_entrypoint.index("gunicorn"))

    def test_dependabot_tracks_the_real_frontend_directory(self):
        dependabot = (ROOT / ".github" / "dependabot.yml").read_text()
        self.assertIn('directory: "/statuspage/project-static"', dependabot)


class TerraformLifecycleContractTests(unittest.TestCase):
    def test_teardown_mode_and_generated_runtime_values_are_declared(self):
        variables = (ROOT / "terraform" / "variables.tf").read_text()
        data_plane = (ROOT / "terraform" / "data_plane.tf").read_text()
        main = (ROOT / "terraform" / "main.tf").read_text()
        self.assertIn('variable "teardown_mode"', variables)
        self.assertIn('variable "final_snapshot_identifier"', variables)
        self.assertIn("master_user_secret", main)
        self.assertIn(":password::", main)
        self.assertIn("aws_db_instance.postgres[0].address", main)
        self.assertIn("aws_elasticache_replication_group.redis[0].primary_endpoint_address", main)
        self.assertIn("force_delete", main)
        self.assertIn("!var.teardown_mode", data_plane)
        self.assertGreaterEqual(main.count("[aws_secretsmanager_secret_policy.rds_master]"), 3)
        self.assertGreaterEqual(main.count("ignore_changes = [task_definition]"), 3)

    def test_lifecycle_scripts_exist(self):
        for relative in (
            "scripts/production_apply.sh",
            "scripts/production_destroy.sh",
            "scripts/verify_production.sh",
        ):
            path = ROOT / relative
            self.assertTrue(path.is_file(), relative)
            self.assertTrue(path.stat().st_mode & stat.S_IXUSR, relative)
            self.assertIn("set -euo pipefail", path.read_text())

        deploy = ROOT / "scripts" / "deploy_ecs_release.sh"
        self.assertTrue(deploy.stat().st_mode & stat.S_IXUSR, str(deploy))

    def test_mutating_terraform_scripts_validate_the_exact_source_snapshot(self):
        source_guard = ROOT / "scripts" / "validate_production_source.sh"
        self.assertTrue(source_guard.is_file())
        self.assertTrue(source_guard.stat().st_mode & stat.S_IXUSR, str(source_guard))
        guard = source_guard.read_text()
        self.assertIn("--untracked-files=all", guard)
        self.assertIn("*.auto.tfvars", guard)
        self.assertIn("origin/main", guard)
        for relative in ("scripts/production_apply.sh", "scripts/production_destroy.sh"):
            self.assertIn("validate_production_source.sh", (ROOT / relative).read_text())

        create = (ROOT / "scripts" / "production_create.sh").read_text()
        self.assertNotIn("--untracked-files=no", create)

    def test_create_sets_all_non_secret_release_identifiers(self):
        create = (ROOT / "scripts" / "production_create.sh").read_text()
        for variable in (
            "AWS_ACCOUNT_ID",
            "AWS_REGION",
            "ECR_APP_REPOSITORY",
            "ECR_NGINX_REPOSITORY",
            "ECS_CLUSTER",
            "ECS_WEB_SERVICE",
            "ECS_WORKER_SERVICE",
            "ECS_SCHEDULER_SERVICE",
            "PUBLIC_HEALTHCHECK_URL",
        ):
            self.assertIn(f"gh variable set {variable}", create)

    def test_destroy_cleans_workflow_registered_task_definition_revisions(self):
        destroy = (ROOT / "scripts" / "production_destroy.sh").read_text()
        self.assertIn("list-task-definitions", destroy)
        self.assertLess(
            destroy.index("gh variable set PRODUCTION_ENABLED"),
            destroy.index('terraform -chdir="$TF_DIR" init'),
        )
        for family in ("web", "worker", "scheduler"):
            self.assertIn(f"yinon-status-page-prod-{family}", destroy)


if __name__ == "__main__":
    unittest.main()
