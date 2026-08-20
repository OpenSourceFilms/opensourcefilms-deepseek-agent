#!/usr/bin/env bash
# install_or_update_ds_research.sh
# Idempotent setup for ds_research. Safe to re-run — never overwrites .env,
# never prints secrets.
#
# Usage:
#   bash install_or_update_ds_research.sh
#   bash install_or_update_ds_research.sh --skip-claude-md
#
# Optional env vars:
#   DEEPSEEK_AGENT_SECRETS_DIR  — external per-key secrets dir to seed .env from
#   DEEPSEEK_AGENT_ENV_SH       — shell env file to register this dir's PATH in
#   DEEPSEEK_AGENT_CLAUDE_MD    — Claude Code memory file to append routing
#                                 instructions to (default: ~/.claude/CLAUDE.md)

set -o pipefail
AGENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKIP_CLAUDE_MD=0
[[ "${1:-}" == "--skip-claude-md" ]] && SKIP_CLAUDE_MD=1

echo "=== ds_research install/update ==="
echo "Agent dir: $AGENT_DIR"

# ── 1. Required directories ───────────────────────────────────────────────────
for d in cache/web_research logs system_prompts; do
  mkdir -p "$AGENT_DIR/$d"
  echo "  dir: $AGENT_DIR/$d"
done

# ── 2. Executable permissions ─────────────────────────────────────────────────
for script in ds_research ds_flash.sh verify_ds_research.sh \
               install_or_update_ds_research.sh export_ds_research_bundle.sh; do
  [ -f "$AGENT_DIR/$script" ] && chmod +x "$AGENT_DIR/$script" && \
    echo "  +x: $script"
done

# ── 3. Symlink /usr/local/bin/ds_research (if writable) ──────────────────────
if [ -w /usr/local/bin ] || [ -w /usr/local ]; then
  if [ ! -e /usr/local/bin/ds_research ] || [ -L /usr/local/bin/ds_research ]; then
    ln -sf "$AGENT_DIR/ds_research" /usr/local/bin/ds_research
    echo "  symlink: /usr/local/bin/ds_research -> $AGENT_DIR/ds_research"
  fi
else
  echo "  skip symlink: /usr/local/bin not writable (PATH includes $AGENT_DIR via env.sh)"
fi

# ── 4. .env handling ──────────────────────────────────────────────────────────
ENV_FILE="$AGENT_DIR/.env"
SECRETS_DIR="${DEEPSEEK_AGENT_SECRETS_DIR:-}"

if [ -f "$ENV_FILE" ]; then
  echo "  .env: exists, not overwritten"
elif [ -z "$SECRETS_DIR" ]; then
  echo "  .env: none found, and DEEPSEEK_AGENT_SECRETS_DIR not set — copy .env.example to .env and fill in your keys"
else
  # Create .env by loading from the configured external secrets directory
  echo "  .env: creating from \$DEEPSEEK_AGENT_SECRETS_DIR..."
  {
    echo "# ds_research secrets — do not commit"
    for secret_file in jina_api_key deepseek_api_key scrapfly_api_key \
                        brave_api_key serper_api_key; do
      full="$SECRETS_DIR/$secret_file"
      if [ -f "$full" ]; then
        # Map filename to env var name
        envvar=$(echo "$secret_file" | tr '[:lower:]' '[:upper:]')
        echo "${envvar}=$(cat "$full")"
      fi
    done
  } > "$ENV_FILE"
  echo "  .env: written (keys from pod-persist/secrets)"
fi

# ── 5. .env.example ───────────────────────────────────────────────────────────
if [ ! -f "$AGENT_DIR/.env.example" ]; then
  cat > "$AGENT_DIR/.env.example" << 'EOF'
JINA_API_KEY=
DEEPSEEK_API_KEY=
SEARXNG_URL=
BRAVE_SEARCH_API_KEY=
SERPER_API_KEY=
EOF
  echo "  .env.example: created"
else
  echo "  .env.example: exists"
fi

# ── 6. Update PATH in env.sh if configured ───────────────────────────────────
ENV_SH="${DEEPSEEK_AGENT_ENV_SH:-}"
if [ -n "$ENV_SH" ] && [ -f "$ENV_SH" ]; then
  if ! grep -q "$AGENT_DIR" "$ENV_SH"; then
    echo '' >> "$ENV_SH"
    echo "export PATH=\"$AGENT_DIR:\$PATH\"" >> "$ENV_SH"
    echo "  env.sh: added $AGENT_DIR to PATH"
  else
    echo "  env.sh: PATH already includes this directory"
  fi
fi

# ── 7. CLAUDE.md update (idempotent) ─────────────────────────────────────────
CLAUDE_MD="${DEEPSEEK_AGENT_CLAUDE_MD:-$HOME/.claude/CLAUDE.md}"
MARKER="<!-- ds-research-routing -->"

if [ "$SKIP_CLAUDE_MD" -eq 0 ] && [ -f "$CLAUDE_MD" ]; then
  if grep -q "$MARKER" "$CLAUDE_MD"; then
    echo "  CLAUDE.md: ds_research routing block already present"
  else
    FRAGMENT="$AGENT_DIR/CLAUDE_DS_RESEARCH_FRAGMENT.md"
    if [ -f "$FRAGMENT" ]; then
      printf "\n%s\n" "$MARKER" >> "$CLAUDE_MD"
      cat "$FRAGMENT" >> "$CLAUDE_MD"
      printf "\n%s\n" "$MARKER" >> "$CLAUDE_MD"
      echo "  CLAUDE.md: ds_research routing block appended"
    fi
  fi
else
  echo "  CLAUDE.md: skipped (--skip-claude-md or file missing)"
fi

# ── 8. Verify Python deps ─────────────────────────────────────────────────────
python3 -c "import requests, bs4; print('  deps: requests + bs4 OK')" 2>/dev/null || \
  echo "  deps: WARNING — requests or bs4 missing, run: pip install requests beautifulsoup4"
python3 -c "from ddgs import DDGS; print('  deps: ddgs OK')" 2>/dev/null || \
  python3 -c "from duckduckgo_search import DDGS; print('  deps: duckduckgo_search OK')" 2>/dev/null || \
  echo "  deps: WARNING — ddgs missing, run: pip install --user ddgs"

echo ""
echo "=== Install complete ==="
echo "Run verify: bash $AGENT_DIR/verify_ds_research.sh"
