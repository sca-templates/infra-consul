---
name: consul-lifecycle
description: Start, stop and troubleshoot the Consul agent. Use when the user asks to make up/down/stop/restart, check leader/members/catalog/DNS, or fix an agent that is unhealthy or a service missing from the catalog.
---

# Consul lifecycle

- `make up` — start the agent
- `make all` — `setup` + `up` + `register`
- `make register` — register the catalog from `scripts/services.txt`
- `make down` — stop and remove containers
- `make stop` / `make restart` — stop without removing / down + up
- `make ps` — container status
- `make logs` — follow logs
- `make clean` — `down -v` + remove `.env`

## Health checks

- `curl http://127.0.0.1:8500/v1/status/leader` — leader elected
- `curl http://127.0.0.1:8500/v1/agent/members` — exactly one node
- `curl http://127.0.0.1:8500/v1/catalog/services` — catalog contents
- `python3 scripts/dns-query.py redis.service.consul` — DNS A record

## Troubleshooting

- Agent not ready: the compose healthcheck runs `consul members` with a 15s
  `start_period`; wait, then check `make logs`.
- Service missing from the catalog: run `make register`; a TCP check only
  turns green once the target publishes its port on `127.0.0.1`.
- `make env` / `make vault-secrets` fail: Vault is not running/unsealed —
  `cd vault && make up && make unseal`.
- `make env` can't find the gossip key: run `make vault-secrets` first (the
  AppRole creds land in `.secrets/`, gitignored).
