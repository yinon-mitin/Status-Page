import importlib.util
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class AwsMonitoringContracts(unittest.TestCase):
    def test_monitoring_and_budget_resources_are_declared(self):
        monitoring = (ROOT / "terraform" / "monitoring.tf").read_text()
        variables = (ROOT / "terraform" / "variables.tf").read_text()
        for resource in (
            'resource "aws_sns_topic" "alerts"',
            'resource "aws_sns_topic_policy" "alerts"',
            'resource "aws_cloudwatch_dashboard" "production"',
            'resource "aws_cloudwatch_metric_alarm" "alb_unhealthy_hosts"',
            'resource "aws_cloudwatch_metric_alarm" "alb_target_5xx"',
            'resource "aws_cloudwatch_metric_alarm" "ecs_cpu"',
            'resource "aws_cloudwatch_metric_alarm" "ecs_memory"',
            'resource "aws_cloudwatch_metric_alarm" "rds_free_storage"',
            'resource "aws_cloudwatch_metric_alarm" "redis_memory"',
            'resource "aws_budgets_budget" "project"',
        ):
            self.assertIn(resource, monitoring)
        self.assertIn('limit_amount = "300"', monitoring)
        self.assertIn("subscriber_sns_topic_arns", monitoring)
        self.assertIn("budgets.amazonaws.com", monitoring)
        self.assertNotIn("metrics = flatten([", monitoring)
        self.assertIn("setproduct", monitoring)
        self.assertIn('variable "create_alert_topic"', variables)
        self.assertIn('variable "enable_aws_budget"', variables)
        self.assertIn("count = var.enable_monitoring && var.create_alert_topic", monitoring)
        self.assertIn("count = var.enable_monitoring && var.enable_aws_budget", monitoring)

    def test_monitoring_addresses_are_plan_allowlisted(self):
        validator = (ROOT / "scripts" / "validate_terraform_plan.py").read_text()
        for token in (
            "aws_sns_topic",
            "aws_sns_topic_policy",
            "aws_sns_topic_subscription",
            "aws_cloudwatch_dashboard",
            "aws_cloudwatch_metric_alarm",
            "aws_budgets_budget",
        ):
            self.assertIn(token, validator)

    def test_https_subscription_address_is_exactly_allowlisted(self):
        spec = importlib.util.spec_from_file_location(
            "validator", ROOT / "scripts" / "validate_terraform_plan.py"
        )
        if spec is None or spec.loader is None:
            raise RuntimeError("Cannot load Terraform plan validator")
        validator = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(validator)
        valid = (
            'aws_sns_topic_subscription.https_alerts['
            '"https://status-page-alert-relay.example.workers.dev/"]'
        )
        invalid = 'aws_sns_topic_subscription.https_alerts["https://bad host/"]'
        self.assertTrue(any(pattern.fullmatch(valid) for pattern in validator.ALLOWED_ADDRESS_PATTERNS))
        self.assertFalse(any(pattern.fullmatch(invalid) for pattern in validator.ALLOWED_ADDRESS_PATTERNS))


class MigrationContracts(unittest.TestCase):
    def test_operator_migration_task_is_required_before_service_rollout(self):
        migration = ROOT / "scripts" / "run_migration_task.sh"
        self.assertTrue(migration.is_file())
        text = migration.read_text()
        self.assertIn("aws ecs run-task", text)
        self.assertIn("manage.py", text)
        self.assertIn("migrate", text)
        self.assertIn("tasks-stopped", text)
        self.assertIn("MIGRATION_EVIDENCE_SHA", text)

        create = (ROOT / "scripts" / "production_create.sh").read_text()
        release = (ROOT / "scripts" / "production_release.sh").read_text()
        workflow = (ROOT / ".github" / "workflows" / "publish-ecr.yml").read_text()
        self.assertIn("run_migration_task.sh", create)
        self.assertIn("verify_production_observability.sh", create)
        self.assertIn("aws ecs list-services", create)
        self.assertIn("existing_service_count", create)
        self.assertNotIn('IMAGE_TAG="sha-$sha" CREATE_SERVICES=false', create)
        self.assertIn("run_migration_task.sh", release)
        self.assertIn("MIGRATION_EVIDENCE_SHA", workflow)
        self.assertIn("github.event_name == 'workflow_dispatch'", workflow)
        start_web = (ROOT / "docker" / "start-web.sh").read_text()
        terraform = (ROOT / "terraform" / "main.tf").read_text()
        self.assertIn("STATUS_PAGE_RUN_MIGRATIONS_ON_START", start_web)
        self.assertIn('STATUS_PAGE_RUN_MIGRATIONS_ON_START = "false"', terraform)

        destroy = (ROOT / "scripts" / "production_destroy.sh").read_text()
        self.assertIn("MIGRATION_EVIDENCE_SHA", destroy)
        self.assertIn("yinon-status-page-prod-migration", destroy)
        self.assertIn("yinon-status-page-prod-restore-validation", destroy)


class RestoreContracts(unittest.TestCase):
    def test_restore_rehearsal_is_private_semantic_and_self_cleaning(self):
        restore = ROOT / "scripts" / "production_backup_restore_test.sh"
        self.assertTrue(restore.is_file())
        text = restore.read_text()
        for token in (
            "create-db-snapshot",
            "restore-db-instance-from-db-snapshot",
            "--no-publicly-accessible",
            "run-task",
            "django_migrations",
            "delete-db-instance",
            "delete-db-snapshot",
            "trap cleanup EXIT",
        ):
            self.assertIn(token, text)
        self.assertNotIn("--manage-master-user-password", text)


class CloudflareContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        module_path = ROOT / "scripts" / "update_cloudflare_dns.py"
        spec = importlib.util.spec_from_file_location("update_cloudflare_dns", module_path)
        if spec is None or spec.loader is None:
            raise RuntimeError(f"Cannot load {module_path}")
        cls.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.module)

    def test_dns_scope_is_exactly_the_demo_hostname(self):
        self.assertEqual("status.yifilter.uk", self.module.DOMAIN)
        self.module.validate_domain("status.yifilter.uk")
        with self.assertRaises(ValueError):
            self.module.validate_domain("other.yifilter.uk")

    def test_dns_target_must_be_the_project_alb(self):
        self.module.validate_target(
            "yinon-status-page-prod-alb-123456.il-central-1.elb.amazonaws.com"
        )
        with self.assertRaises(ValueError):
            self.module.validate_target("example.com")

    def test_dns_update_reads_back_one_unproxied_cname(self):
        target = "yinon-status-page-prod-alb-123456.il-central-1.elb.amazonaws.com"

        class FakeClient:
            def __init__(self):
                self.calls = []

            def request(self, method, path, payload=None):
                self.calls.append((method, path, payload))
                if path == "/zones/zone":
                    return {"name": "yifilter.uk"}
                if "dns_records?" in path:
                    return [{"id": "record"}]
                if method == "PUT":
                    return payload
                return {
                    "type": "CNAME",
                    "name": "status.yifilter.uk",
                    "content": target,
                    "proxied": False,
                }

        client = FakeClient()
        self.assertEqual("record", self.module.update_record(client, "zone", target))
        update = [call for call in client.calls if call[0] == "PUT"][0]
        self.assertEqual("status.yifilter.uk", update[2]["name"])
        self.assertFalse(update[2]["proxied"])

    def test_telegram_worker_verifies_sns_before_delivery(self):
        worker = (ROOT / "integrations" / "cloudflare-worker" / "src" / "worker.mjs").read_text()
        for token in (
            "crypto.subtle.verify",
            "SigningCertURL",
            "SNS_TOPIC_ARN",
            "SubscriptionConfirmation",
            "TELEGRAM_BOT_TOKEN",
            "TELEGRAM_CHAT_ID",
            "SNS_DEDUP",
            "expirationTtl",
        ):
            self.assertIn(token, worker)
        deployer = (ROOT / "scripts" / "deploy_alert_relay.py").read_text()
        self.assertIn('workers/scripts/{SCRIPT_NAME}/subdomain', deployer)
        self.assertIn("storage/kv/namespaces", deployer)


class ScopeContracts(unittest.TestCase):
    def test_https_remains_documented_and_disabled(self):
        variables = (ROOT / "terraform" / "environments" / "prod.tfvars.example").read_text()
        limitation = (ROOT / "docs" / "HTTPS_LIMITATION.md").read_text()
        self.assertNotIn("request_acm_certificate = true", variables)
        self.assertIn("not HTTPS production", limitation)


class OneOffTaskDefinitionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        module_path = ROOT / "scripts" / "build_oneoff_task_definition.py"
        spec = importlib.util.spec_from_file_location("build_oneoff", module_path)
        if spec is None or spec.loader is None:
            raise RuntimeError(f"Cannot load {module_path}")
        cls.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.module)

    def test_clones_only_runtime_fields_and_overrides_app_contract(self):
        source = {
            "family": "old",
            "revision": 42,
            "networkMode": "awsvpc",
            "requiresCompatibilities": ["FARGATE"],
            "cpu": "256",
            "memory": "512",
            "containerDefinitions": [{
                "name": "worker",
                "image": "old",
                "environment": [{"name": "POSTGRES_HOST", "value": "old-host"}],
                "secrets": [{"name": "POSTGRES_PASSWORD", "valueFrom": "old-secret"}],
            }],
        }
        image = (
            "992382545251.dkr.ecr.il-central-1.amazonaws.com/"
            "yinon-status-page-prod-app:sha-" + "a" * 40
        )
        result = self.module.build_definition(
            source,
            "yinon-status-page-prod-migration",
            image,
            ["python", "manage.py", "migrate", "--noinput"],
            {"POSTGRES_HOST": "new-host"},
            {"POSTGRES_PASSWORD": "new-secret"},
        )
        self.assertNotIn("revision", result)
        container = result["containerDefinitions"][0]
        self.assertEqual("oneoff", container["name"])
        self.assertEqual(image, container["image"])
        self.assertIn({"name": "POSTGRES_HOST", "value": "new-host"}, container["environment"])
        self.assertIn({"name": "POSTGRES_PASSWORD", "valueFrom": "new-secret"}, container["secrets"])


if __name__ == "__main__":
    unittest.main()
