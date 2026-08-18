# consul — HashiCorp Consul agent (service discovery + health checks)

Single-node [HashiCorp Consul](https://www.consul.io/) agent providing
**service discovery** and **TCP health checks** for the sibling stack services. API and UI on `http://127.0.0.1:8500`, DNS on
`127.0.0.1:8600` (**loopback only**). Image `hashicorp/consul:1.19`, single
server (`-bootstrap-expect=1`), no ACLs, gossip key managed by Vault.

| Service | Image | Local (development) | Production |
| --- | --- | --- | --- |
| Consul (agent/server) | `hashicorp/consul:1.19` | `8500` API+UI, `8600` DNS, `8300` RPC, `8301` gossip | Same image; gossip key from AWS Secrets Manager |

Integrates with the sibling projects:

- **Vault** ([vault](https://github.com/sca-templates/vault)) — source of `CONSUL_GOSSIP_KEY` (secret
  `secret/consul/dev`, read via the `consul` AppRole).
- **postgres-app** ([postgres-app](https://github.com/sca-templates/postgres-app)), **redis** ([redis](https://github.com/sca-templates/redis)),
  **kafka** / **kafka-connect** ([kafka](https://github.com/sca-templates/kafka)), **vault** ([vault](https://github.com/sca-templates/vault)),
  **prometheus** ([prometheus](https://github.com/sca-templates/prometheus)), **grafana** ([grafana](https://github.com/sca-templates/grafana)) — registered
  services with TCP checks (see [Registered services](#registered-services)).

## Quick Start (local)

```bash
# 1. Vault running and unsealed (once)
cd vault && make up && make unseal

# 2. All-in-one: Vault secrets + .env + up + register
cd consul && make all

# 3. Verify
make validate
```

On subsequent starts `make up && make register` is enough (`make all` is
idempotent too).

## Commands

| Command | Description |
| --- | --- |
| `make setup` | First time: Vault AppRole + gossip key + `.env` (idempotent) |
| `make all` | `setup` + `up` + `register` |
| `make up` | Starts the Consul agent |
| `make register` | Registers the stack services with TCP checks |
| `make validate` | Checks leader, single node, catalog and DNS |
| `make vault-secrets` | Registers the `consul` AppRole + stores `CONSUL_GOSSIP_KEY` in Vault |
| `make env` | Generates `.env` from Vault |
| `make down` / `make restart` / `make stop` / `make logs` / `make ps` | Stack management |
| `make clean` | `down -v` + removes `.env` |

## Registered services

The catalog lives in `scripts/services.txt` (`name:port` per line, `#`
comments) — the **single source of truth** read by both
`scripts/register-services.sh` (registration) and `scripts/validate.sh`
(verification). Never hardcode a service list in a script. Every `make up` /
`make register` re-registers all entries (idempotent
`PUT /v1/agent/service/register`). Checks are TCP against `127.0.0.1:<port>`
(`interval: 10s`, `timeout: 5s`).

| Service | Port | Host |
| --- | --- | --- |
| `postgres-app` | 5432 | 127.0.0.1 |
| `redis` | 6379 | 127.0.0.1 |
| `kafka` | 9092 | 127.0.0.1 |
| `kafka-connect` | 8083 | 127.0.0.1 |
| `vault` | 8201 | 127.0.0.1 |
| `prometheus` | 9090 | 127.0.0.1 |
| `grafana` | 3000 | 127.0.0.1 |
| `postgres-exporter` | 9187 | 127.0.0.1 |
| `redis-exporter` | 9121 | 127.0.0.1 |
| `kafka-connect-exporter` | 9309 | 127.0.0.1 |

## How the gossip key flows (local)

1. `scripts/vault-secrets.sh` registers the `consul` AppRole in Vault (via
   `vault/scripts/add-service.sh`, read-only policy on
   `secret/data/consul/*`) and saves the role_id/secret_id to `.secrets/`
   (gitignored).
2. It generates `CONSUL_GOSSIP_KEY` with `consul keygen` and stores it in
   `secret/consul/dev` (`FORCE=1` rotates it).
3. `scripts/gen-env.sh` (`make env`) reads the key via the AppRole and writes
   `.env` (gitignored, `chmod 600`). Compose passes it through
   `env_file: .env` and `-encrypt=${CONSUL_GOSSIP_KEY}`.

The gossip key is stored in AWS Secrets Manager
(`{{ project }}/{{ environment }}/consul_gossip_key`); the image and
`-bootstrap-expect=1` flags are identical.

## Networking

- The agent runs on the **host network** (`network_mode: host`) with
  `-bind=127.0.0.1` (gossip) and `-client=0.0.0.0` (API/DNS/RPC), so its TCP
  checks reach the sibling services that publish ports on the host.
- API+UI bind to **loopback only** (`127.0.0.1:8500`); nothing is exposed on
  the LAN. DNS answers point to `127.0.0.1`.
- Any registered service resolves as `<name>.service.consul` via
  `127.0.0.1:8600` (see Usage examples).

## Usage examples

> All examples below use `127.0.0.1` because services bind to loopback in development. In production, use the service's internal DNS name or load balancer endpoint.

```bash
# Catalog (all registered services)
curl -s http://127.0.0.1:8500/v1/catalog/services

# Leader status
curl -s http://127.0.0.1:8500/v1/status/leader

# Health of a specific service
curl -s http://127.0.0.1:8500/v1/health/service/redis

# DNS — no `dig` on this host, use the stdlib helper
python3 scripts/dns-query.py redis.service.consul        # -> 127.0.0.1
python3 scripts/dns-query.py kafka.service.consul        # -> 127.0.0.1

# DNS with dig (on hosts that have it)
dig @127.0.0.1 -p 8600 redis.service.consul +short       # -> 127.0.0.1

# UI
# http://127.0.0.1:8500/ui
```

## Troubleshooting

| Symptom | Probable cause | Fix |
| --- | --- | --- |
| `make env` / `make vault-secrets` fail | Vault is not running/unsealed | `cd vault && make up && make unseal` |
| `make validate` shows `Service missing: <svc>` | Service not registered or its port is not published | Start the sibling stack, then `make register`; the check recovers automatically |
| Agent unhealthy (`docker ps`) | `consul members` fails right after start | Wait for the `start_period` (15s); check `make logs` |
| DNS doesn't answer | `:8600` blocked or agent not ready | `make ps`; ensure no other process binds 8600 |
| `consul:1.19` pull errors | No registry access | Check internet access to Docker Hub |

## Structure

```text
├── docker-compose.yml                  # single consul agent (host network)
├── Makefile                            # orchestrator
├── .env.example                        # non-secret vars and ports
├── scripts/
│   ├── services.txt                    # catalog: single source of truth
│   ├── vault-secrets.sh                # AppRole + CONSUL_GOSSIP_KEY in Vault
│   ├── gen-env.sh                      # .env from Vault
│   ├── register-services.sh            # register the stack services (TCP checks)
│   ├── validate.sh                     # leader, members, catalog, DNS
│   └── dns-query.py                    # stdlib DNS A lookup (no dig needed)
├── docs/                               # architecture, index
└── .claude/skills/ + .opencode/        # agent skills and commands
```
