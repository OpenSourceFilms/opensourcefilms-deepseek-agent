#!/usr/bin/env bash
# resumable_run.sh <job_dir> <units_file> <command_template>
# Runs command_template once per unit ({UNIT} substituted), capturing stdout to
# <job_dir>/out/<unit>.out written atomically. Units already done (non-empty .out)
# are skipped, so a killed run resumes from where it stopped. CAP-IMMUNE when the
# command calls DeepSeek (ds_flash/ds_research) and this is launched in background:
# it is an OS process on a separate API, unaffected by an Anthropic session cap.
# See RESUMABLE_DELEGATION.md.
set -o pipefail
JOB="$1"; UNITS="$2"; TMPL="$3"
{ [ -n "$JOB" ] && [ -f "$UNITS" ] && [ -n "$TMPL" ]; } || {
  echo "usage: resumable_run.sh <job_dir> <units_file> <command_template with {UNIT}>"; exit 2; }
OUT="$JOB/out"; LOG="$JOB/resumable.log"; mkdir -p "$OUT"
ts(){ date '+%Y-%m-%dT%H:%M:%S'; }
total=0; skip=0; ran=0; fail=0
while IFS= read -r unit || [ -n "$unit" ]; do
  [ -z "$unit" ] && continue
  case "$unit" in \#*) continue;; esac
  total=$((total+1))
  id="$(printf '%s' "$unit" | tr -c 'A-Za-z0-9._-' '_')"
  dest="$OUT/$id.out"
  if [ -s "$dest" ]; then skip=$((skip+1)); echo "$(ts) SKIP $unit" >>"$LOG"; continue; fi
  cmd="${TMPL//\{UNIT\}/$unit}"
  echo "$(ts) RUN  $unit" >>"$LOG"
  tmp="$(mktemp "$OUT/.$id.XXXXXX")"
  if bash -c "$cmd" >"$tmp" 2>>"$LOG" && [ -s "$tmp" ]; then
    mv -f "$tmp" "$dest"; ran=$((ran+1)); echo "$(ts) OK   $unit" >>"$LOG"
  else
    rm -f "$tmp"; fail=$((fail+1)); echo "$(ts) FAIL $unit (will retry next run)" >>"$LOG"
  fi
done < "$UNITS"
echo "$(ts) DONE total=$total skipped=$skip ran=$ran failed=$fail -> $OUT" | tee -a "$LOG"
[ "$fail" -eq 0 ]
