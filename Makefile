.DEFAULT_GOAL := help

.PHONY: help up down logs check tf-fmt tf-validate

help:
	@printf '%s\n' 'Targets: up, down, logs, check, tf-fmt, tf-validate'

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

tf-fmt:
	terraform -chdir=terraform fmt -recursive

tf-validate:
	terraform -chdir=terraform init -backend=false
	terraform -chdir=terraform validate
