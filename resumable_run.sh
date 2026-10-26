#!/usr/bin/env bash
# resumable_run.sh <job_dir> <units_file> <trusted_command_template>
# Complete outputs are immutable: a successful unit is published only when
# <job_dir>/out/<id>.out does not exist. A failed unit stays retryable.
# {UNIT} is replaced by the shell variable ${UNIT}, NOT raw unit text.
# The template itself is trusted shell code, not an untrusted input format.
set -uo pipefail

JOB="${1:-}"
UNITS="${2:-}"
TMPL="${3:-}"
if [ -z "$JOB" ] || [ ! -f "$UNITS" ] || [ -z "$TMPL" ]; then
  echo "usage: resumable_run.sh <job_dir> <units_file> <command_template with {UNIT}>" >&2
  exit 2
fi
if [[ "$TMPL" != *'{UNIT}'* ]]; then
  echo "FATAL: command template must contain {UNIT}" >&2
  exit 2
fi

OUT="$JOB/out"
LOG="$JOB/resumable.log"
mkdir -p -- "$OUT" || exit 1
ts(){ date '+%Y-%m-%dT%H:%M:%S'; }
total=0; skip=0; ran=0; fail=0
placeholder='{UNIT}'
replacement='${UNIT}'
# This substitution is done ONCE to the trusted command template. Unit
# content never becomes shell source when bash later evaluates the template.
cmd="${TMPL//"$placeholder"/"$replacement"}"

while IFS= read -r unit || [ -n "$unit" ]; do
  [ -z "$unit" ] && continue
  case "$unit" in \#*) continue;; esac
  total=$((total+1))

  # Preserve on-disk checkpoint IDs for simple historical units. Complex
  # units occupy a separate '~' namespace (disallowed by simple-ID regex),
  # so a literal simple ID can never alias an encoded complex ID. Earlier
  # complex-unit checkpoint names are not silently migrated/reused.
  if [[ "$unit" =~ ^[A-Za-z0-9._-]+$ ]] && [ "${#unit}" -le 100 ] &&
     [ "$unit" != "." ] && [ "$unit" != ".." ]; then
    id="$unit"
  else
    slug="$(printf '%s' "$unit" | LC_ALL=C tr -c 'A-Za-z0-9._-' '_')"
    slug="${slug:0:64}"
    digest="$(printf '%s' "$unit" | sha256sum)" || exit 1
    digest="${digest%% *}"
    id="~${slug:-unit}-${digest:0:16}"
  fi

  dest="$OUT/$id.out"
  if [ -f "$dest" ] && [ ! -L "$dest" ] && [ -s "$dest" ]; then
    skip=$((skip+1))
    echo "$(ts) SKIP $unit" >>"$LOG"
    continue
  fi
  # Never follow/reuse a symlink, directory or empty/partial previous output.
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    fail=$((fail+1))
    echo "$(ts) FAIL $unit (output path exists but is not complete)" >>"$LOG"
    continue
  fi

  echo "$(ts) RUN  $unit" >>"$LOG"
  tmp="$(mktemp "$OUT/.$id.XXXXXX")" || exit 1
  if UNIT="$unit" bash -c "$cmd" >"$tmp" 2>>"$LOG" && [ -s "$tmp" ]; then
    # Same directory/filesystem: hard-link publication is atomic and
    # create-only. A concurrent invocation cannot overwrite a completed unit.
    # -T forbids ln from treating a racing directory/symlink-to-directory
    # as a destination directory and falsely reporting success.
    if ln -T -- "$tmp" "$dest" 2>>"$LOG"; then
      rm -f -- "$tmp"
      ran=$((ran+1))
      echo "$(ts) OK   $unit" >>"$LOG"
    else
      rm -f -- "$tmp"
      fail=$((fail+1))
      echo "$(ts) FAIL $unit (another writer owns output path)" >>"$LOG"
    fi
  else
    rm -f -- "$tmp"
    fail=$((fail+1))
    echo "$(ts) FAIL $unit (will retry next run)" >>"$LOG"
  fi
done < "$UNITS"
echo "$(ts) DONE total=$total skipped=$skip ran=$ran failed=$fail -> $OUT" | tee -a "$LOG"
[ "$fail" -eq 0 ]
