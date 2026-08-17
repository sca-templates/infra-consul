# Contributing to sca-consul

> Single-node HashiCorp Consul agent for the local stack — service discovery and TCP health checks for the sibling services, gossip key managed by Vault. Docs-as-code: all changes land through a PR with review.

## Ground rules

- **English only** — notes, commits, and PR descriptions are written in English.
- **No secrets in the repo** — `.env` is gitignored and generated from Vault (`secret/consul/dev`); `.secrets/` holds the AppRole role_id/secret_id and is gitignored. Never commit tokens, role IDs, gossip keys or passwords.
- **Docs-as-code** — every change goes through a pull request and is reviewed.

## Repository layout

```text
docker-compose.yml          Single Consul agent (host network, -bootstrap-expect=1)
Makefile                    help | setup | all | up | register | validate | vault-secrets | env | down | stop | restart | logs | ps | clean
scripts/                    vault-secrets.sh | gen-env.sh | register-services.sh | validate.sh | dns-query.py | services.txt
.env.example                Non-secret defaults, ports and ENVIRONMENT
.github/                    CI, PR template, dependabot, markdown link-check config
```

## Adding or changing a registered service

1. Add or edit the entry in `scripts/services.txt` (`name:port`, TCP check on `127.0.0.1:<port>`). It is the **single source of truth** — both `register-services.sh` and `validate.sh` read it; never hardcode a list in a script.
2. Make sure the sibling stack that owns the service publishes its port on `127.0.0.1` (loopback).
3. Run `make register && make validate`.
4. Update the README "Registered services" table (and `docs/architecture.md` if the topology changes).

## Contribution flow

1. Branch off `main`: `git checkout -b feat/<topic>`.
2. Create or edit the files following the conventions above.
3. Run the checks (see Tooling).
4. Open a PR and fill the checklist from the template.

## Definition of done

- [ ] Content is in English.
- [ ] `scripts/services.txt` is kept in sync with the sibling stacks and the README table.
- [ ] No secrets or tokens are committed (`.env`, `.secrets/` stay gitignored).
- [ ] `bash -n scripts/*.sh` and `shellcheck scripts/*.sh` pass.
- [ ] `docker compose -f docker-compose.yml config --quiet` passes.
- [ ] `make validate` passes locally (agent up + services registered).
- [ ] `markdownlint` and link check pass (CI runs them too).
- [ ] `README.md` is updated when the stack, ports or commands change.

## Tooling

```sh
# Register the catalog + validate (needs the agent running)
make register && make validate

# Lint markdown
npx --yes markdownlint-cli2 README.md AGENTS.md CLAUDE.md .github/PULL_REQUEST_TEMPLATE.md .github/CONTRIBUTING.md docs/**/*.md .claude/skills/**/SKILL.md .opencode/command/*.md

# Check links in a single file (config lives in .github/)
npx --yes markdown-link-check -c .github/markdown-link-check.json <file>
```

## License

This repository is licensed under the MIT License (see [LICENSE](../LICENSE)).
