# Consul — Service Guide

Single-node HashiCorp Consul agent (service discovery + TCP health checks)
for the local `aws/` monorepo. Follow the sibling patterns exactly (`kafka/`,
`prometheus/`, `vault/`) — this repo is a copy-paste evolution of them.

## Ecosystem documentation (sca-docs)

The ecosystem docs live in the
[sca-docs](https://github.com/sca-node-template/sca-docs) repository — the
single source of truth for ecosystem topology and conventions. Consult it
before writing or editing anything about topology, ports, networks, or
conventions. Principle: **one fact, one place** — depth lives in this repo,
topology/maps in the vault, pointers in READMEs.

- [04-infrastructure/INDEX.md](https://github.com/sca-node-template/sca-docs/blob/main/04-infrastructure/INDEX.md) — infrastructure catalog
- [00-ecosystem/conventions.md](https://github.com/sca-node-template/sca-docs/blob/main/00-ecosystem/conventions.md) — naming, links, catalogs
- [00-ecosystem/HOME.md](https://github.com/sca-node-template/sca-docs/blob/main/00-ecosystem/HOME.md) — vault entry point
- [README.md](https://github.com/sca-node-template/sca-docs/blob/main/README.md) — ecosystem vision + repository map
- [03-connections-map/connection-map.md](https://github.com/sca-node-template/sca-docs/blob/main/03-connections-map/connection-map.md) — ecosystem graph
- [99-glossary/INDEX.md](https://github.com/sca-node-template/sca-docs/blob/main/99-glossary/INDEX.md) — ubiquitous language
- [CONTRIBUTING.md](https://github.com/sca-node-template/sca-docs/blob/main/CONTRIBUTING.md) — vault conventions and definition of done

Fetch them via the web, the GitHub API/MCP, or the raw URLs
(`https://raw.githubusercontent.com/sca-node-template/sca-docs/main/<path>`).
Do not rely on a local checkout of `sca-docs`.

Keep the vault in sync: if a change materially alters this component (ports,
gossip key, network, catalog), update the corresponding vault note and open a
PR in `sca-docs` — or flag it in this repo's PR.

## Project

Single-node Consul server (`hashicorp/consul:1.19`) on the host network:
`-server -bootstrap-expect=1 -datacenter=dev`, no ACLs. API+UI on
<http://127.0.0.1:8500>, DNS `8600`, RPC `8300`, gossip `8301` — all loopback
only. Registers the sibling stack services with TCP checks on
`127.0.0.1:<port>` from the single catalog `scripts/services.txt`. Gossip key
(`CONSUL_GOSSIP_KEY`, `consul keygen`) is stored in Vault
`secret/consul/dev`; `.env` is generated from Vault via the `consul` AppRole.
Production reference (same image): `../ansible/roles/consul` +
`../terraform/modules/consul`. Full spec: the canonical note in the sca-docs
vault ([infrastructure catalog](https://github.com/sca-node-template/sca-docs/blob/main/04-infrastructure/INDEX.md)).

## Layout

- `docker-compose.yml` — the single `consul` service (host network,
  `-bootstrap-expect=1`, healthcheck, `consul_data` volume).
- `Makefile` — targets: `help setup vault-secrets env up register validate all
  down stop restart logs ps clean` (idempotent).
- `scripts/` — `vault-secrets.sh`, `gen-env.sh`, `register-services.sh`,
  `validate.sh`, `dns-query.py` and `services.txt`.
- `scripts/services.txt` — the catalog, **single source of truth** (`name:port`
  per line, `#` comments); read by both `register-services.sh` and
  `validate.sh`.
- `.env.example` — non-secret vars and ports; `.env` is generated, gitignored.
- `.github/` — CI (`validate.yml`), PR template, CONTRIBUTING, dependabot.
- `.mcp.json` + `.claude/` — Claude Code + codegraph MCP wiring.
- `.claude/skills/` — shared AI skills (`consul-lifecycle`,
  `register-validate-services`); registered for opencode via `opencode.jsonc`
  (`skills.paths`), so every agent uses the same files.
- `opencode.jsonc` + `.opencode/` — opencode project config, MCP and
  `/validate`, `/up`, `/down`, `/ps` commands.
- `docs/` — conceptual docs (architecture); operational content and
  troubleshooting live in `README.md`.
- `0.Project_info/` — user tooling (commit/merge/prompt flows); do not touch.

## Commands

- `make help` — all targets.
- `make setup` — `vault-secrets` + `env`.
- `make all` — `setup` + `up` + `register`.
- `make up` — compose up the agent.
- `make register` — register the catalog from `scripts/services.txt`
  (idempotent `PUT /v1/agent/service/register`, TCP checks
  `127.0.0.1:<port>`).
- `make validate` — leader elected, single node, catalog matches
  `services.txt`, DNS `redis.service.consul` resolves.
- `make down stop restart logs ps clean` — stack lifecycle.
- CI mirrors the static checks in `.github/workflows/validate.yml`.

## Conventions

- `scripts/services.txt` is the **single source of truth**: add/remove a
  service there (`name:port`), never hardcode lists in scripts. Both
  `register-services.sh` and `validate.sh` read it, and the README table
  mirrors it.
- TCP checks run against `127.0.0.1:<port>` (`interval: 10s`,
  `timeout: 5s`) because the agent runs on the host network and the sibling
  services publish their ports on loopback.
- The agent runs `network_mode: host` with `-bind=127.0.0.1`,
  `-client=0.0.0.0`, `-bootstrap-expect=1`, `-datacenter=dev` and
  `-encrypt=${CONSUL_GOSSIP_KEY}`. All agent ports (8500, 8600, 8300, 8301)
  bind to loopback only; nothing is exposed on the LAN.
- **No ACLs** locally — the agent is a plain single-server dev node. Do not
  add ACL bootstrap locally without also updating production.
- Shell scripts: `set -euo pipefail` + a header comment only; no other
  comments.
- `.env` is gitignored and generated by `scripts/gen-env.sh` from Vault
  `secret/consul/dev` (`CONSUL_GOSSIP_KEY`), `chmod 600`. AppRole
  role_id/secret_id land in `.secrets/` (gitignored). Never commit `.env` or
  `.secrets/`.
- `scripts/vault-secrets.sh` bootstraps the `consul` AppRole via
  `../vault/scripts/add-service.sh consul "" --read-policy secret/data/consul/*`,
  saves the creds to `.secrets/`, and writes a fresh `consul keygen` key to
  `secret/consul/dev` (`FORCE=1` rotates it).
- Production mirror: `../ansible/roles/consul` + `../terraform/modules/consul`
  — same image (`hashicorp/consul:1.19`) and `-bootstrap-expect=1`; the gossip
  key comes from AWS Secrets Manager and the EC2 security group opens
  8500/8600/8300/8301. Keep local flags in sync with production.
- Content in English; changes land through a PR.
