SHELL := /bin/bash
.ONESHELL:
.SHELLFLAGS := -euo pipefail -c
.DEFAULT_GOAL := help

COMPOSE_FILE := docker-compose.yml
COMPOSE_PROJECT_NAME := consul
COMPOSE := docker compose -f $(COMPOSE_FILE) -p $(COMPOSE_PROJECT_NAME)
# this project lives in aws/local/consul, so Vault is two levels up
VAULT_DIR := $(shell dirname $(abspath $(lastword $(MAKEFILE_LIST))))/../../vault

.PHONY: help
help:
	@echo 'consul — HashiCorp Consul agent (service discovery + health checks)'
	@echo ''
	@echo '  make setup         First time: Vault secrets + .env (idempotent)'
	@echo '  make all           setup + up + register (all-in-one)'
	@echo '  make up            Start Consul agent'
	@echo '  make register      Register the stack services with TCP checks'
	@echo '  make validate      Verify leader, members, catalog and DNS'
	@echo ''
	@echo '  make vault-secrets Store CONSUL_GOSSIP_KEY in Vault'
	@echo '  make env           Generate .env from Vault'
	@echo ''
	@echo '  make down          Stop and remove stack'
	@echo '  make restart       down + up'
	@echo '  make stop          Stop without removing'
	@echo '  make logs          Live logs'
	@echo '  make ps            Container status'
	@echo '  make clean         down + remove .env and volume'

.PHONY: vault-secrets
vault-secrets:
	@echo '=== Storing CONSUL_GOSSIP_KEY in Vault ==='
	scripts/vault-secrets.sh

.PHONY: env
env:
	@echo '=== Generating .env from Vault ==='
	scripts/gen-env.sh

.PHONY: setup
setup: vault-secrets env
	@echo '=== Setup complete. Next: make up ==='

.PHONY: up
up:
	@echo '=== Starting Consul agent ==='
	$(COMPOSE) up -d

.PHONY: register
register:
	@echo '=== Registering services ==='
	scripts/register-services.sh

.PHONY: validate
validate:
	@echo '=== Validating Consul ==='
	scripts/validate.sh

.PHONY: all
all: setup up register
	@echo ''
	@echo '============================================'
	@echo '  Consul ready:'
	@echo '  HTTP API + UI : http://127.0.0.1:8500 (/ui)'
	@echo '  DNS           : 127.0.0.1:8600'
	@echo '============================================'

.PHONY: down
down:
	@echo '=== Stopping stack ==='
	$(COMPOSE) down

.PHONY: restart
restart: down up

.PHONY: stop
stop:
	$(COMPOSE) stop

.PHONY: logs
logs:
	$(COMPOSE) logs -f

.PHONY: ps
ps:
	$(COMPOSE) ps

.PHONY: clean
clean:
	@echo '=== Cleaning up ==='
	-$(COMPOSE) down -v 2>/dev/null || true
	rm -f .env
	@echo 'Done.'
