#!/usr/bin/env bash
# validate.sh — Verification of the Consul agent (local).
#   Leader elected, single node, catalog contains the stack services, DNS works.
set -euo pipefail

CONSUL_ADDR="${CONSUL_ADDR:-http://127.0.0.1:8500}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0

ok()   { (( PASS++ )) || true; echo "  OK  $1"; }
fail() { (( FAIL++ )) || true; echo "  FAIL $1"; }
section() { echo ""; echo "── $1 ──────────────────────────────────────"; }

section "Agent / status"
LEADER="$(curl -sf "${CONSUL_ADDR}/v1/status/leader" 2>/dev/null || true)"
[ -n "${LEADER}" ] && ok "Leader elected: ${LEADER}" || fail "No leader elected"

MEMBERS="$(curl -sf "${CONSUL_ADDR}/v1/agent/members" 2>/dev/null || true)"
NODES="$(echo "${MEMBERS}" | python3 -c 'import sys,json; print(len(json.load(sys.stdin)))' 2>/dev/null || echo 0)"
[ "${NODES}" -eq 1 ] && ok "consul members reports 1 node" || fail "consul members reports ${NODES} nodes"

section "Catalog services"
EXPECTED=("postgresql-app" "redis" "kafka" "kafka-connect" "vault")
CATALOG="$(curl -sf "${CONSUL_ADDR}/v1/catalog/services" 2>/dev/null || true)"
for svc in "${EXPECTED[@]}"; do
  echo "${CATALOG}" | grep -q "\"${svc}\"" && ok "Service registered: ${svc}" || fail "Service missing: ${svc}"
done

section "DNS"
DNS_RESULT="$(python3 "${PROJECT_DIR}/scripts/dns-query.py" redis.service.consul 2>/dev/null || true)"
[ "${DNS_RESULT}" = "127.0.0.1" ] && ok "redis.service.consul → ${DNS_RESULT}" || fail "redis.service.consul → ${DNS_RESULT:-no answer}"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Result: ${PASS} OK, ${FAIL} FAIL"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
[ "${FAIL}" -eq 0 ] && echo "  All checks passed." || exit 1
