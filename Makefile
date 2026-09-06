.DEFAULT_GOAL := help

.PHONY: help up down logs check test docs automation-check verify vm-status vm-check vm-cloud-init-check tf-fmt tf-validate tf-lint

ORBSTACK_MACHINE ?= statuspage-dev

help:
	@printf '%s\n' 'Targets: up, down, logs, check, test, docs, automation-check, verify, vm-status, vm-check, vm-cloud-init-check, tf-fmt, tf-validate, tf-lint'

up:
	docker compose up --build -d

down:
	docker compose down

logs:
	docker compose logs --follow --tail=100

check:
	docker compose config --quiet
	curl --fail --silent --show-error http://localhost:8081/healthz
	curl --fail --silent --show-error http://localhost:8081/static/statuspage-tailwind.css > /dev/null
	curl --fail --silent --show-error http://localhost:8081/static/statuspage.css > /dev/null
	docker compose exec -T web python manage.py check
	docker compose exec -T web python /opt/status-page/scripts/verify_runtime.py

test:
	docker compose exec -T web python manage.py test

docs:
	docker compose run --rm --no-deps --workdir /opt/status-page web mkdocs build --strict

automation-check:
	python3 -m unittest tests/test_delivery_automation.py -v
	python3 -m unittest tests/test_production_readiness.py -v
	cd integrations/cloudflare-worker && npm test
	@for script in scripts/*.sh; do bash -n "$$script"; done

verify: check test docs automation-check vm-cloud-init-check tf-fmt tf-validate tf-lint
	@printf '%s\n' 'Local verification passed.'

vm-status:
	orbctl info $(ORBSTACK_MACHINE)

vm-check:
	orbctl run -m $(ORBSTACK_MACHINE) -u root /usr/local/bin/statuspage-dev-check

vm-cloud-init-check:
	docker compose run --rm --no-deps --entrypoint python --workdir /opt/status-page web scripts/validate_cloud_init.py

tf-fmt:
	terraform -chdir=terraform fmt -recursive

tf-validate:
	terraform -chdir=terraform init -backend=false
	terraform -chdir=terraform validate

tf-lint:
	tflint --chdir=terraform --config=.tflint.hcl --init
	tflint --chdir=terraform --config=.tflint.hcl
