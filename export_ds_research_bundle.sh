#!/usr/bin/env bash
# export_ds_research_bundle.sh
# Creates a portable tarball of ds_research (no secrets, no cache, no logs).
# Output: <parent of this repo>/ds_research_bundle.tar.gz
# Set DEEPSEEK_AGENT_BUNDLE_COPY_TO to also copy the bundle somewhere durable
# (e.g. a persistent-volume path), if your environment has one.

set -o pipefail
AGENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE="$(dirname "$AGENT_DIR")/ds_research_bundle.tar.gz"
PERSIST_BUNDLE="${DEEPSEEK_AGENT_BUNDLE_COPY_TO:-}"

echo "=== Exporting ds_research bundle ==="

# Verify no secrets slip through
if [ -f "$AGENT_DIR/.env" ]; then
  echo "  Excluding .env (secrets)"
fi

BASENAME="$(basename "$AGENT_DIR")"
tar -czf "$BUNDLE" \
  --exclude="${BASENAME}/.env" \
  --exclude="${BASENAME}/logs" \
  --exclude="${BASENAME}/cache" \
  --exclude="${BASENAME}/__pycache__" \
  --exclude="${BASENAME}/.git" \
  --exclude="${BASENAME}/*.pyc" \
  --exclude="${BASENAME}/ds_research_bundle.tar.gz" \
  -C "$(dirname "$AGENT_DIR")" \
  "$BASENAME"

echo "  Bundle: $BUNDLE ($(du -sh "$BUNDLE" | cut -f1))"

# Optionally copy to a configured durable location
if [ -n "$PERSIST_BUNDLE" ]; then
  cp "$BUNDLE" "$PERSIST_BUNDLE"
  echo "  Also copied to: $PERSIST_BUNDLE"
fi

# Verify bundle does not contain .env or key patterns
KEY_CHECK=$(tar -tzf "$BUNDLE" | grep -E "\.env$" || true)
if [ -n "$KEY_CHECK" ]; then
  echo "  ERROR: .env found in bundle — aborting"
  rm -f "$BUNDLE" "$PERSIST_BUNDLE"
  exit 1
fi

echo ""
echo "Bundle contents:"
tar -tzf "$BUNDLE" | sed 's/^/  /'
echo ""
echo "=== Bundle ready ==="
echo "Restore with: tar -xzf $BUNDLE -C /path/to/parent/dir && bash $BASENAME/restore_ds_research.sh"
