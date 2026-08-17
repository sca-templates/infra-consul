---
name: register-validate-services
description: Register and validate the stack services in Consul. Use when the user asks to add or remove a service from the catalog, re-register services, run make register or make validate, or fix a service failing its TCP check.
---

# Register and validate services

`make register` and `make validate` both read the single source of truth
`scripts/services.txt` (`name:port` per line, `#` comments ignored). Never
hardcode a service list in a script.

## Steps

1. Edit `scripts/services.txt` to add or remove a service (`name:port` on
   `127.0.0.1`). Keep names and ports in sync with the sibling stack that owns
   the service and with the README table.
2. Run `make register` to (re)register every entry — idempotent
   `PUT /v1/agent/service/register` with a TCP check on
   `127.0.0.1:<port>` (`interval: 10s`, `timeout: 5s`).
3. Run `make validate` to confirm the leader, a single node, and that every
   entry in `services.txt` is present in the catalog
   (`/v1/catalog/services`); it also checks DNS (`redis.service.consul`
   resolves to 127.0.0.1).
4. If a check fails: the target must actually be listening on
   `127.0.0.1:<port>` (start its stack), then re-run `make register`.

## Catalog

Current catalog (from `scripts/services.txt`): postgres-app:5432,
redis:6379, kafka:9092, kafka-connect:8083, vault:8201, prometheus:9090,
grafana:3000, postgres-exporter:9187, redis-exporter:9121,
kafka-connect-exporter:9309.

## Notes

- A TCP check stays red until the service publishes its port on loopback.
- `make validate` does not register — run `make register` first (or
  `make all`).
- Keep the README "Registered services" table in sync with `services.txt`.
