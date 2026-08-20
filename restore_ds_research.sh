#!/usr/bin/env bash
# restore_ds_research.sh
# Restore ds_research from a bundle on a fresh machine/pod.
#
# Usage:
#   # 1. Extract the bundle wherever you want this tool to live:
#   tar -xzf ds_research_bundle.tar.gz -C /path/to/parent/dir
#
#   # 2. Run this script:
#   bash restore_ds_research.sh
#
#   # 3. Add your secrets (either works):
#   cp .env.example .env && edit .env
#   # or, if you use an external secrets directory:
#   export DEEPSEEK_AGENT_SECRETS_DIR=/path/to/secrets
#   echo "YOUR_JINA_KEY" > "$DEEPSEEK_AGENT_SECRETS_DIR/jina_api_key"

set -o pipefail
AGENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Restoring ds_research ==="

# ── Install/update ────────────────────────────────────────────────────────────
bash "$AGENT_DIR/install_or_update_ds_research.sh"

# ── Check secrets ─────────────────────────────────────────────────────────────
echo ""
echo "── Secrets status ──"
if [ -f "$AGENT_DIR/.env" ]; then
  echo "  [OK]  $AGENT_DIR/.env exists"
elif [ -n "${DEEPSEEK_AGENT_SECRETS_DIR:-}" ]; then
  for secret in jina_api_key deepseek_api_key; do
    if [ -f "$DEEPSEEK_AGENT_SECRETS_DIR/$secret" ]; then
      echo "  [OK]  $DEEPSEEK_AGENT_SECRETS_DIR/$secret exists"
    else
      echo "  [MISSING] $DEEPSEEK_AGENT_SECRETS_DIR/$secret"
    fi
  done
else
  echo "  [MISSING] no .env and DEEPSEEK_AGENT_SECRETS_DIR not set"
  echo "    Fix: cp $AGENT_DIR/.env.example $AGENT_DIR/.env and fill in your keys"
fi

# ── Smoke test ────────────────────────────────────────────────────────────────
echo ""
echo "── Smoke test ──"
bash "$AGENT_DIR/verify_ds_research.sh"

echo ""
echo "=== Restore complete ==="
echo "then re-run: bash $AGENT_DIR/verify_ds_research.sh"
