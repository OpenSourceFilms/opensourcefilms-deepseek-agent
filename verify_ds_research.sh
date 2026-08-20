#!/usr/bin/env bash
# verify_ds_research.sh — Quick smoke test for the ds_research setup.
# Usage:
#   verify_ds_research.sh              # fast tests (no DeepSeek calls)
#   verify_ds_research.sh --full       # includes Jina Search test (burns ~10k tokens)
#   verify_ds_research.sh --check-balance  # show Jina usage stats only

set -o pipefail
AGENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DS_RESEARCH="$AGENT_DIR/ds_research"
PASS=0; FAIL=0

_ok()   { echo "  [OK]  $1"; PASS=$((PASS+1)); }
_fail() { echo "  [FAIL] $1"; FAIL=$((FAIL+1)); }
_warn() { echo "  [WARN] $1"; }
_sep()  { echo ""; echo "── $1 ──"; }

# Load env
[ -f "$AGENT_DIR/.env" ] && source <(grep -v '^#' "$AGENT_DIR/.env" | sed 's/^/export /')
SECRETS_DIR="${DEEPSEEK_AGENT_SECRETS_DIR:-}"
[ -n "$SECRETS_DIR" ] && [ -f "$SECRETS_DIR/jina_api_key" ] && [ -z "$JINA_API_KEY" ] && \
  export JINA_API_KEY="$(cat "$SECRETS_DIR/jina_api_key")"

# Balance check only
if [[ "${1:-}" == "--check-balance" ]]; then
  echo "Jina usage stats:"
  python3 -c "
import json; from pathlib import Path
f = Path('$AGENT_DIR/cache/jina_usage.json')
if f.exists():
    d = json.loads(f.read_text())
    used = d.get('searches_used', 0)
    budget = 1000
    print(f'  searches_used: {used} / {budget}')
    print(f'  remaining_est: {budget - used}')
    print(f'  last_updated:  {d.get(\"last_updated\", \"never\")}')
    if used >= 800:
        print('  WARNING: balance low — get a new key at https://jina.ai')
else:
    print('  searches_used: 0 (no usage recorded)')
"
  exit 0
fi

echo "=== ds_research verification ==="
echo "Agent dir: $AGENT_DIR"
echo ""

_sep "1. Command exists"
if [ -x "$DS_RESEARCH" ]; then
  _ok "ds_research is executable at $DS_RESEARCH"
else
  _fail "ds_research not found or not executable at $DS_RESEARCH"
fi

_sep "2. Env loading"
if [ -n "$JINA_API_KEY" ]; then
  REDACTED="${JINA_API_KEY:0:6}***"
  _ok "JINA_API_KEY loaded (${REDACTED})"
else
  _warn "JINA_API_KEY not set — Jina Search will be unavailable"
fi
if [ -n "$DEEPSEEK_API_KEY" ]; then
  _ok "DEEPSEEK_API_KEY loaded"
else
  _fail "DEEPSEEK_API_KEY not set — DeepSeek calls will fail"
fi

_sep "3. Secret leak check (logs + cache)"
LEAKED=$(grep -r "${JINA_API_KEY:0:12}" "$AGENT_DIR/logs/" "$AGENT_DIR/cache/" 2>/dev/null | grep -v "jina_usage.json" | wc -l)
if [ "$LEAKED" -eq 0 ]; then
  _ok "No Jina key prefix found in logs or cache"
else
  _warn "$LEAKED file(s) may contain partial key — investigate manually"
fi

_sep "4. URL fetch (uses cache if available)"
FETCH_OUT=$("$DS_RESEARCH" --url "https://api-docs.deepseek.com/guides/tool_calls" \
  "Who executes tools?" 2>/dev/null | tail -8)
if echo "$FETCH_OUT" | grep -q "fetch_provider"; then
  _ok "URL fetch returned metadata block"
  echo "$FETCH_OUT" | grep -E "fetch_provider|cache_hit|used_jina" | sed 's/^/    /'
else
  _fail "URL fetch produced no metadata"
fi

_sep "5. Cache hit (second run of same URL)"
CACHE_OUT=$("$DS_RESEARCH" --url "https://api-docs.deepseek.com/guides/tool_calls" \
  "Who executes tools?" 2>/dev/null | grep "cache_hit")
if echo "$CACHE_OUT" | grep -q "True"; then
  _ok "Cache hit confirmed: $CACHE_OUT"
else
  _warn "Cache hit not confirmed: $CACHE_OUT"
fi

_sep "6. Local source mode (RTFM)"
LOCAL_OUT=$("$DS_RESEARCH" "RTFM sync_roots database table" 2>/dev/null | \
  grep "search_provider")
if echo "$LOCAL_OUT" | grep -q "local_source"; then
  _ok "Local source resolver fired: $LOCAL_OUT"
else
  _warn "Local source did not fire (may be OK if RTFM not installed)"
fi

_sep "7. --no-paid-token-providers"
NOPAID_OUT=$(JINA_API_KEY="" "$DS_RESEARCH" --no-paid-token-providers \
  "python requests library" 2>/dev/null | grep -E "used_jina|no-paid")
if echo "$NOPAID_OUT" | grep -q "False\|disabled"; then
  _ok "--no-paid-token-providers: keyed providers disabled"
  echo "$NOPAID_OUT" | sed 's/^/    /'
else
  _warn "Could not confirm no-paid mode: $NOPAID_OUT"
fi

_sep "8. Jina balance stats"
python3 -c "
import json; from pathlib import Path
f = Path('$AGENT_DIR/cache/jina_usage.json')
if f.exists():
    d = json.loads(f.read_text())
    used = d.get('searches_used', 0)
    print(f'  searches_used: {used} / 1000 est.')
    if used >= 800:
        print('  *** BALANCE LOW — renew at https://jina.ai ***')
else:
    print('  searches_used: 0 (no Jina Search calls recorded)')
" 2>/dev/null

# Full test: forced Jina Search (burns ~10k tokens)
if [[ "${1:-}" == "--full" ]] && [ -n "$JINA_API_KEY" ]; then
  _sep "9. Forced Jina Search (--full only)"
  JINA_OUT=$("$DS_RESEARCH" --jina-search \
    "Does DeepSeek API support native live web search?" 2>/dev/null | \
    grep -E "used_jina_search|jina_search_requests")
  if echo "$JINA_OUT" | grep -q "True"; then
    _ok "Forced Jina Search worked"
    echo "$JINA_OUT" | sed 's/^/    /'
  else
    _fail "Forced Jina Search did not fire"
  fi
fi

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
