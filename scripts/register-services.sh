#!/usr/bin/env bash
# register-services.sh — Registers the local stack services in Consul (idempotent).
#   PUT /v1/agent/service/register for each service with a TCP check
#   (interval 10s, timeout 5s) against 127.0.0.1:<port>.
# Usage: make register   (re-runs on every make up)
set -euo pipefail

CONSUL_ADDR="${CONSUL_ADDR:-http://127.0.0.1:8500}"

# name:port — Address is 127.0.0.1 so the checks reach host-published services.
# Single source of truth: scripts/services.txt (name:port per line).
SERVICES="$(grep -v '^#' "$(dirname "${BASH_SOURCE[0]}")/services.txt" | tr '\n' ' ')"

wait_for_consul() {
  echo "[consul] Waiting for leader election..."
  until [ -n "$(curl -sf "${CONSUL_ADDR}/v1/status/leader" 2>/dev/null || true)" ]; do
    sleep 3
  done
  echo "[consul] Leader elected."
}

register() {
  local name="$1" port="$2"
  local payload
  payload=$(python3 - "$name" "$port" <<'PY'
import json, sys
name, port = sys.argv[1], int(sys.argv[2])
print(json.dumps({
    "ID": name,
    "Name": name,
    "Tags": ["dev"],
    "Address": "127.0.0.1",
    "Port": port,
    "Check": {"TCP": "127.0.0.1:%d" % port, "Interval": "10s", "Timeout": "5s"},
}))
PY
)
  echo "[consul] Registering ${name} (127.0.0.1:${port})..."
  curl -sf -X PUT -H "Content-Type: application/json" -d "$payload" \
    "${CONSUL_ADDR}/v1/agent/service/register" > /dev/null
  echo "[consul] ${name} registered."
}

wait_for_consul
for spec in $SERVICES; do
  register "${spec%%:*}" "${spec##*:}"
done

echo ""
echo "[consul] Registered services:"
curl -sf "${CONSUL_ADDR}/v1/catalog/services" | python3 -m json.tool 2>/dev/null || true
