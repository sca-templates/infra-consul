# consul — Consul agent (service discovery + health checks)

A single-node [HashiCorp Consul](https://www.consul.io/) agent running in Docker
for **local development**, providing **service discovery** and **TCP health
checks** for the sibling stack services. It mirrors production
(`ansible/roles/consul` + `terraform/modules/consul`): same image
(`hashicorp/consul:1.19`), single server (`-bootstrap-expect=1`), gossip key
managed by the secrets backend (Vault locally, AWS Secrets Manager in prod),
no ACLs.

| Service | Image | Port |
|---|---|---|
| Consul (agent/server) | `hashicorp/consul:1.19` | `8500` API+UI, `8600` DNS, `8300` RPC, `8301` gossip |

Integrates with the sibling projects:
- **Vault** (`../vault`) — source of `CONSUL_GOSSIP_KEY` (secret `secret/consul/dev`).
- **postgres-app** / **redis** / **kafka** / **kafka-connect** / **vault** —
  registered services with TCP checks.

## Architecture Overview

```
                        +--------------------+
                        |    Vault Cluster   |  (../vault, 127.0.0.1:8201)
                        |  secret/consul/dev |
                        |  CONSUL_GOSSIP_KEY |
                        +---------+----------+
                                  |
                         make setup (vault-secrets + env)
                                  |
                                  v
                        +---------+----------+
                        |  Makefile          |  ──>  .env (gitignored)
                        +---------+----------+
                                  |
                                  | docker compose up
                                  v
        +----------------------------------------------------+
        |  Consul agent  (hashicorp/consul:1.19, host net)   |
        |  -server -bootstrap-expect=1 -datacenter=dev       |
        |  API+UI :8500 · DNS :8600 · RPC :8300 · gossip :8301|
        +----------------------------------------------------+
                ^  register (PUT /v1/agent/service/register)
                |  TCP checks 127.0.0.1:<port>
        +-------+-------+-------+-------+---------+
        |       |       |       |       |         |
    postgresql   redis  kafka kafka-  vault
       -app               connect
       :5432    :6379  :9092  :8083   :8201
```

The container runs with `network_mode: host` and `-bind=127.0.0.1` /
`-client=0.0.0.0`, so its TCP checks reach the services that publish ports on
the host. DNS answers point to `127.0.0.1`.

## Quick Start (local)

```bash
# 1. Vault running (once per machine start)
cd ../vault && make up && make unseal

# 2. All-in-one: Vault secrets + .env + up + register
cd ../consul && make all

# 3. Verify
make validate
```

On subsequent starts `make up && make register` is enough (`make all` is
idempotent too).

## Commands

| Command | Description |
|---|---|
| `make setup` | Stores `CONSUL_GOSSIP_KEY` in Vault and generates `.env` (idempotent) |
| `make all` | `setup` + `up` + `register` |
| `make up` | Starts the Consul agent |
| `make register` | Registers the stack services with TCP checks |
| `make validate` | Checks leader, members, catalog and DNS |
| `make vault-secrets` | Registers the `consul` AppRole + stores `CONSUL_GOSSIP_KEY` in Vault |
| `make env` | Generates `.env` from Vault |
| `make down` / `make restart` / `make stop` / `make logs` / `make ps` | Stack management |
| `make clean` | `down -v` + removes `.env` |

## Registered services

Every `make up`/`make register` re-registers these services (idempotent
`PUT /v1/agent/service/register`). Checks are TCP against `127.0.0.1:<port>`
(`interval: 10s`, `timeout: 5s`).

| Service | Port | Host |
|---|---|---|
| `postgresql-app` | 5432 | 127.0.0.1 |
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

1. `scripts/vault-secrets.sh` registers the `consul` AppRole (`add-service.sh
   consul kv-reader`) and writes `CONSUL_GOSSIP_KEY` (generated with
   `consul keygen`) in `secret/consul/dev`.
2. `scripts/gen-env.sh` reads it and generates `.env` (gitignored).
3. Compose passes it to the agent via `env_file` and `-encrypt=${CONSUL_GOSSIP_KEY}`.

The same flow in production is Ansible + AWS Secrets Manager
(`{{ project }}/{{ environment }}/consul_gossip_key`); the image and
`-bootstrap-expect=1` flags are identical.

## Usage examples

```bash
# Catalog (all registered services)
curl -s http://127.0.0.1:8500/v1/catalog/services

# Leader status
curl -s http://127.0.0.1:8500/v1/status/leader

# Health of a specific service
curl -s http://127.0.0.1:8500/v1/health/service/redis

# DNS — no `dig` on this host, use the stdlib helper
python3 scripts/dns-query.py redis.service.consul        # → 127.0.0.1
python3 scripts/dns-query.py kafka.service.consul        # → 127.0.0.1

# DNS with dig (on hosts that have it)
dig @127.0.0.1 -p 8600 redis.service.consul +short       # → 127.0.0.1

# UI
# http://127.0.0.1:8500/ui
```

Other services/apps can resolve any registered service as
`<name>.service.consul` through `127.0.0.1:8600`.

## Troubleshooting

| Symptom | Probable cause | Fix |
|---|---|---|
| `make env` / `make vault-secrets` fail | Vault is not running | `cd ../vault && make up && make unseal` |
| `make validate` shows `Service missing: vault` | Vault registered check is critical (Vault down) | Start Vault; the check recovers automatically |
| Agent unhealthy (`docker ps`) | `consul members` fails right after start | Wait for `start_period` (15s); check `make logs` |
| DNS doesn't answer | `:8600` blocked or agent not ready | `make ps`; ensure no other process binds 8600 |
| `consul:1.19` pull errors | No registry access | Check internet access to Docker Hub |

## Production reference

- **Ansible**: `../../ansible/roles/consul/tasks/main.yml` + `templates/docker-compose.yml.j2`
  (gossip key from AWS Secrets Manager, same image and flags).
- **Terraform**: `../../terraform/modules/consul/` (EC2 instance + security
  group for `8500`, `8600`, `8300`, `8301`).

## Structure

```
├── docker-compose.yml
├── Makefile
├── .env.example
├── scripts/
│   ├── vault-secrets.sh        # AppRole + CONSUL_GOSSIP_KEY in Vault
│   ├── gen-env.sh              # .env from Vault
│   ├── register-services.sh    # register the stack services (TCP checks)
│   ├── validate.sh             # leader, members, catalog, DNS
│   └── dns-query.py            # stdlib DNS A lookup (no dig needed)
└── 0.Project_info/             # commit / MR helper templates
```
