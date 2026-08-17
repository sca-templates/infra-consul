---
description: Start the Consul agent (compose up) and confirm a leader is elected.
agent: build
---

# Up

Run `make up` from the repo root and confirm a leader is elected
(`curl http://127.0.0.1:8500/v1/status/leader`).
