---
description: Register the stack services and run the full Consul validation suite (leader, single node, catalog, DNS).
agent: build
---

# Validate

Run `make register && make validate` from the repo root and report the result.
`validate.sh` checks the leader, single-node membership, the catalog against
`scripts/services.txt`, and DNS. If a check fails, isolate it with the
individual curls in the `register-validate-services` skill and fix it, then
re-run `make register && make validate`.
