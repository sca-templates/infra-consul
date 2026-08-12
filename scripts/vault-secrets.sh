#!/usr/bin/env bash
# vault-secrets.sh — Bootstraps Consul secrets in Vault (idempotent).
#   1. Registers the "consul" AppRole (if it doesn't exist)
#   2. Generates the gossip key (consul keygen) and stores it in secret/consul/dev
# Usage: make vault-secrets   (FORCE=1 to rotate/overwrite)
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VAULT_DIR="${VAULT_DIR:-$PROJECT_DIR/../../vault}"
SECRETS_DIR="$VAULT_DIR/data/secrets"

VAULT_ADDR="$(grep -m1 '^VAULT_ADDR=' "$VAULT_DIR/.env" 2>/dev/null | cut -d= -f2- | tr -d '\n\r')"
VAULT_ADDR="${VAULT_ADDR:-https://127.0.0.1:8201}"
VAULT_ENV="${VAULT_ENV:-dev}"
export VAULT_SKIP_VERIFY=true

VAULT_TOKEN="$(cat "$SECRETS_DIR/root-token.txt" 2>/dev/null || \
  docker exec prod-vault-1 cat /vault/data/secrets/root-token.txt 2>/dev/null | tr -d '\n\r' || true)"
if [ -z "$VAULT_TOKEN" ]; then
  echo "ERROR: Could not obtain the Vault token. Is it running? (cd ../vault && make up && make unseal)"
  exit 1
fi

if ! curl -sk -m 5 -o /dev/null "$VAULT_ADDR/v1/sys/health"; then
  echo "ERROR: Vault is not reachable at $VAULT_ADDR. Start it with: cd ../vault && make up && make unseal"
  exit 1
fi

vault_get() { curl -sk -H "X-Vault-Token: $VAULT_TOKEN" "$VAULT_ADDR/v1/$1"; }
vault_post() { curl -sk -H "X-Vault-Token: $VAULT_TOKEN" -H "Content-Type: application/json" -X POST "$VAULT_ADDR/v1/$1" -d "$2"; }

echo "=== 1. AppRole 'consul' ==="
if echo "$(vault_get "auth/approle/role/consul")" | grep -q 'does not exist'; then
  echo "Registering consul service in Vault..."
  if [ -x "$VAULT_DIR/scripts/add-service.sh" ]; then
    bash "$VAULT_DIR/scripts/add-service.sh" consul kv-reader
  else
    echo "ERROR: $VAULT_DIR/scripts/add-service.sh not found"
    exit 1
  fi
else
  echo "AppRole consul already exists. (FORCE=1 to recreate it)"
fi

echo ""
echo "=== 2. CONSUL_GOSSIP_KEY in secret/consul/$VAULT_ENV ==="
EXISTING="$(vault_get "secret/data/consul/$VAULT_ENV")"

if echo "$EXISTING" | grep -q '"CONSUL_GOSSIP_KEY"' && [ "${FORCE:-0}" != "1" ]; then
  echo "CONSUL_GOSSIP_KEY already exists. (FORCE=1 to regenerate/rotate)"
  exit 0
fi

echo "Generating gossip key (consul keygen)..."
CONSUL_GOSSIP_KEY="$(docker run --rm hashicorp/consul:1.19 consul keygen | tr -d '\n\r')"
if [ -z "$CONSUL_GOSSIP_KEY" ]; then
  echo "ERROR: Could not generate CONSUL_GOSSIP_KEY (docker run hashicorp/consul:1.19 consul keygen failed)"
  exit 1
fi

echo "Writing CONSUL_GOSSIP_KEY to secret/consul/$VAULT_ENV..."
PAYLOAD=$(python3 - "$CONSUL_GOSSIP_KEY" <<'PY'
import json, sys
payload = {"data": {"CONSUL_GOSSIP_KEY": sys.argv[1]}}
print(json.dumps(payload))
PY
)
vault_post "secret/data/consul/$VAULT_ENV" "$PAYLOAD"

echo ""
echo "=== Secrets written to secret/consul/$VAULT_ENV ==="
vault_get "secret/data/consul/$VAULT_ENV" | python3 -c "import sys,json; d=json.load(sys.stdin)['data']['data']; print('\n'.join(f'  {k}=***' for k in d))"
echo ""
echo "Next step: make env"
