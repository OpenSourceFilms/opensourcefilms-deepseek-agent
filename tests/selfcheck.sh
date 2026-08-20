#!/bin/bash
# Syntax and structural self-check. Does not require any API keys or network
# access — verifies the scripts parse correctly and no secret material has
# been accidentally committed. For a deeper check that exercises the actual
# provider cascade (no keys needed for the fast path), see
# ../verify_ds_research.sh instead.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAIL=0

echo "=== bash -n syntax check ==="
for f in \
  "$ROOT/ds_flash.sh" \
  "$ROOT/verify_ds_research.sh" \
  "$ROOT/install_or_update_ds_research.sh" \
  "$ROOT/restore_ds_research.sh" \
  "$ROOT/export_ds_research_bundle.sh" \
  "$ROOT/resumable_run.sh"
do
  if bash -n "$f"; then
    echo "OK   $f"
  else
    echo "FAIL $f"
    FAIL=1
  fi
done

echo
echo "=== python syntax check ==="
if python3 -m py_compile "$ROOT/ds_research"; then
  echo "OK   $ROOT/ds_research"
else
  echo "FAIL $ROOT/ds_research"
  FAIL=1
fi

echo
echo "=== no committed secret material ==="
if grep -rlE '\-\-\-\-\-BEGIN (OPENSSH|RSA|EC) PRIVATE KEY\-\-\-\-\-|^(jina_|hf_|sk-)[A-Za-z0-9]{15,}' "$ROOT" \
    --include='*' 2>/dev/null | grep -v '^Binary'; then
  echo "FAIL: possible secret material found committed in this repo"
  FAIL=1
else
  echo "OK   no private key headers or API key patterns found"
fi

echo
if [ "$FAIL" = "0" ]; then
  echo "selfcheck: PASS"
else
  echo "selfcheck: FAIL"
fi
exit "$FAIL"
