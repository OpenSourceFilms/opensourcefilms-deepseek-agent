#!/usr/bin/env bash
# ds_flash.sh — DeepSeek delegation wrapper
#
# Usage:
#   ds_flash.sh <task> "<prompt>"          # Pro model (default)
#   ds_flash.sh --flash <task> "<prompt>"  # Flash model (cheap triage)
#   echo "content" | ds_flash.sh <task>   # prompt via stdin
#   ds_flash.sh smoke                     # API connectivity self-test
#   ds_flash.sh tasks                     # list available task names
#
# Tasks map to system_prompts/<task>.txt
# Use task "raw" for no system prompt (ad-hoc / smoke).
# All calls logged to logs/<timestamp>_<task>.json

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
PROMPTS_DIR="$SCRIPT_DIR/system_prompts"
LOGS_DIR="$SCRIPT_DIR/logs"
ENDPOINT="https://api.deepseek.com/v1/chat/completions"
MODEL="deepseek-v4-pro"

# ── Flag parsing ──────────────────────────────────────────────────────────────

if [[ "${1:-}" == "--flash" ]]; then
  MODEL="deepseek-v4-flash"
  shift
fi

# ── Preflight ────────────────────────────────────────────────────────────────

# Self-bootstrap: load workspace env if key not already in environment.
# Covers non-interactive shells (Claude Code Bash tool) where BASH_ENV may
# not yet be wired (e.g. first session after pod start before bootstrap runs).
if [[ -z "$DEEPSEEK_API_KEY" ]]; then
  # Optional external env.sh — unset by default; set DEEPSEEK_AGENT_ENV_SH to
  # whatever secrets-persistence convention your own environment uses.
  _ENV_FILE="${DEEPSEEK_AGENT_ENV_SH:-}"
  [[ -n "$_ENV_FILE" && -f "$_ENV_FILE" ]] && source "$_ENV_FILE" 2>/dev/null
  unset _ENV_FILE
fi

if [[ -z "$DEEPSEEK_API_KEY" ]]; then
  echo "ERROR: \$DEEPSEEK_API_KEY is not set." >&2; exit 1
fi
if ! command -v curl &>/dev/null; then
  echo "ERROR: curl not found." >&2; exit 1
fi
if ! command -v jq &>/dev/null; then
  echo "ERROR: jq not found." >&2; exit 1
fi

# ── Args ─────────────────────────────────────────────────────────────────────

TASK="${1:-}"

if [[ -z "$TASK" ]]; then
  echo "Usage: ds_flash.sh <task> [prompt]" >&2
  echo "       ds_flash.sh smoke" >&2
  echo "       ds_flash.sh tasks" >&2
  exit 1
fi

# List available tasks
if [[ "$TASK" == "tasks" ]]; then
  echo "Available tasks:"
  for f in "$PROMPTS_DIR"/*.txt; do
    [[ -f "$f" ]] && echo "  $(basename "$f" .txt)"
  done
  echo "  raw    (no system prompt)"
  echo "  smoke  (self-test)"
  exit 0
fi

# Smoke test — real API round-trip
if [[ "$TASK" == "smoke" ]]; then
  echo "Running smoke test..." >&2
  RESULT=$("$0" raw "Reply with exactly one word: PASS" 2>&1)
  if echo "$RESULT" | grep -qi "PASS"; then
    echo "PASS"; exit 0
  else
    echo "FAIL" >&2
    echo "Response: $RESULT" >&2
    exit 1
  fi
fi

# Resolve user prompt: arg or stdin
if [[ -n "${2:-}" ]]; then
  USER_PROMPT="$2"
elif [[ ! -t 0 ]]; then
  USER_PROMPT="$(cat)"
else
  echo "ERROR: no prompt supplied — pass as argument or pipe via stdin." >&2
  exit 1
fi

# Resolve system prompt
if [[ "$TASK" == "raw" ]]; then
  SYSTEM_PROMPT="You are a helpful assistant."
else
  SYSTEM_FILE="$PROMPTS_DIR/${TASK}.txt"
  if [[ ! -f "$SYSTEM_FILE" ]]; then
    echo "ERROR: unknown task '$TASK' — no file at $SYSTEM_FILE" >&2
    echo "Run: ds_flash.sh tasks" >&2
    exit 1
  fi
  SYSTEM_PROMPT="$(cat "$SYSTEM_FILE")"
fi

# ── Build request ─────────────────────────────────────────────────────────────

TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
LOG_FILE="$LOGS_DIR/${TIMESTAMP}_${TASK}.json"
mkdir -p "$LOGS_DIR"

REQUEST_JSON="$(jq -n \
  --arg model  "$MODEL" \
  --arg system "$SYSTEM_PROMPT" \
  --arg user   "$USER_PROMPT" \
  '{
    model: $model,
    messages: [
      {role: "system", content: $system},
      {role: "user",   content: $user}
    ],
    stream: false
  }')"

# ── Call API ──────────────────────────────────────────────────────────────────

RESPONSE="$(curl -sf -X POST "$ENDPOINT" \
  -H "Authorization: Bearer $DEEPSEEK_API_KEY" \
  -H "Content-Type: application/json" \
  --max-time 120 \
  -d "$REQUEST_JSON")"
CURL_EXIT=$?

# ── Log ───────────────────────────────────────────────────────────────────────

jq -n \
  --arg  ts    "$TIMESTAMP" \
  --arg  task  "$TASK" \
  --arg  model "$MODEL" \
  --argjson req  "$REQUEST_JSON" \
  --argjson resp "${RESPONSE:-null}" \
  '{timestamp: $ts, task: $task, model: $model, request: $req, response: $resp}' \
  > "$LOG_FILE" 2>/dev/null \
  || printf '%s\n' "$RESPONSE" > "$LOG_FILE"

# ── Output ────────────────────────────────────────────────────────────────────

if [[ $CURL_EXIT -ne 0 ]]; then
  echo "ERROR: curl failed (exit $CURL_EXIT) — check endpoint or key." >&2
  exit 1
fi

API_ERROR="$(printf '%s' "$RESPONSE" | jq -r '.error.message // empty' 2>/dev/null)"
if [[ -n "$API_ERROR" ]]; then
  echo "ERROR: API — $API_ERROR" >&2; exit 1
fi

CONTENT="$(printf '%s' "$RESPONSE" | jq -r '.choices[0].message.content // empty' 2>/dev/null)"
if [[ -z "$CONTENT" ]]; then
  echo "ERROR: empty or unparseable response." >&2
  printf '%s\n' "$RESPONSE" >&2
  exit 1
fi

printf '%s\n' "$CONTENT"

# Write Flash approval tokens so routing gates pass
if [[ "$TASK" == "decisions_entry" ]]; then
  date +%s > /tmp/flash-decisions-approved
fi
if [[ "$TASK" == "sql_draft" ]]; then
  date +%s > /tmp/flash-sql-approved
fi
if [[ "$TASK" == "log_analysis" ]]; then
  date +%s > /tmp/flash-log-approved
fi
if [[ "$TASK" == "patch_draft" ]]; then
  date +%s > /tmp/flash-patch-approved
fi
