#!/usr/bin/env bash
# gen-env.sh — Generates .env from Vault via the consul AppRole (local).
#   Reads secret/consul/dev (CONSUL_GOSSIP_KEY) and writes .env.
# Usage: make env
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VAULT_DIR="${VAULT_DIR:-$PROJECT_DIR/../vault}"
SECRETS_DIR="$VAULT_DIR/data/secrets"
SECRET_LOCAL_DIR="$PROJECT_DIR/.secrets"
OUT="$PROJECT_DIR/.env"
VAULT_ENV="${VAULT_ENV:-dev}"

VAULT_ADDR="$(grep -m1 '^VAULT_ADDR=' "$VAULT_DIR/.env" 2>/dev/null | cut -d= -f2- | tr -d '\n\r')"
VAULT_ADDR="${VAULT_ADDR:-https://127.0.0.1:8201}"
export VAULT_SKIP_VERIFY=true

if ! curl -sk -m 5 -o /dev/null "$VAULT_ADDR/v1/sys/health"; then
  echo "ERROR: Vault is not reachable at $VAULT_ADDR. Start it with: cd ../vault && make up && make unseal"
  exit 1
fi

# AppRole auth (role_id/secret_id from repo .secrets/, fallback to vault data/secrets)
ROLE_ID="$(cat "$SECRET_LOCAL_DIR/approle-consul-roleid.txt" 2>/dev/null || \
  cat "$SECRETS_DIR/approle-consul-roleid.txt" 2>/dev/null || true)"
SECRET_ID="$(cat "$SECRET_LOCAL_DIR/approle-consul-secretid.txt" 2>/dev/null || \
  cat "$SECRETS_DIR/approle-consul-secretid.txt" 2>/dev/null || true)"
if [ -z "$ROLE_ID" ] || [ -z "$SECRET_ID" ]; then
  echo "ERROR: AppRole credentials missing. Run first: make vault-secrets"
  exit 1
fi

LOGIN_JSON="$(curl -sk -X POST -H "Content-Type: application/json" \
  -d "{\"role_id\":\"$ROLE_ID\",\"secret_id\":\"$SECRET_ID\"}" \
  "$VAULT_ADDR/v1/auth/approle/login")"
VAULT_TOKEN="$(echo "$LOGIN_JSON" | python3 -c 'import sys,json; print(json.load(sys.stdin)["auth"]["client_token"])' 2>/dev/null || true)"
if [ -z "$VAULT_TOKEN" ]; then
  echo "ERROR: AppRole login failed. Re-run: make vault-secrets"
  exit 1
fi

echo "=== Reading CONSUL_GOSSIP_KEY from Vault (AppRole: consul) ==="
CONSUL_GOSSIP_KEY="$(curl -sk -H "X-Vault-Token: $VAULT_TOKEN" "$VAULT_ADDR/v1/secret/data/consul/$VAULT_ENV" \
  | python3 -c 'import sys,json; print(json.load(sys.stdin)["data"]["data"]["CONSUL_GOSSIP_KEY"])')"

if [ -z "$CONSUL_GOSSIP_KEY" ]; then
  echo "ERROR: CONSUL_GOSSIP_KEY is empty. Run first: make vault-secrets"
  exit 1
fi

cat > "$OUT" <<EOF
ENVIRONMENT=${VAULT_ENV:-local}

# Consul agent
CONSUL_GOSSIP_KEY=${CONSUL_GOSSIP_KEY}
CONSUL_HOST=127.0.0.1
CONSUL_API_PORT=8500
CONSUL_DNS_PORT=8600
CONSUL_DATACENTER=dev
EOF

chmod 0600 "$OUT"
echo ".env generated from Vault ($VAULT_ENV). Source: secret/consul/$VAULT_ENV (AppRole: consul)"
