.DEFAULT_GOAL := help

.PHONY: help up down logs check test docs verify tf-fmt tf-validate tf-lint

help:
	@printf '%s\n' 'Targets: up, down, logs, check, test, docs, verify, tf-fmt, tf-validate, tf-lint'

up:
	docker compose up --build -d

down:
	docker compose down

logs:
	docker compose logs --follow --tail=100

check:
	docker compose config --quiet
	curl --fail --silent --show-error http://localhost:8081/healthz
	docker compose exec -T web python manage.py check
	docker compose exec -T web python /opt/status-page/scripts/verify_runtime.py

test:
	docker compose exec -T web python manage.py test

docs:
	docker compose run --rm --no-deps --workdir /opt/status-page web mkdocs build --strict

verify: check test docs tf-fmt tf-validate tf-lint
	@printf '%s\n' 'Local verification passed.'

tf-fmt:
	terraform -chdir=terraform fmt -recursive

tf-validate:
	terraform -chdir=terraform init -backend=false
	terraform -chdir=terraform validate

tf-lint:
	tflint --chdir=terraform --config=.tflint.hcl --init
	tflint --chdir=terraform --config=.tflint.hcl
