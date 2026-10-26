# Surviving session limits — resumable, cap-immune delegation

**Problem.** When the Anthropic account hits its session/usage limit, *every* Anthropic API
call fails at once — the main thread AND all Claude subagents (Task/Agent). In-flight
subagents die and their work is lost. There is **no** way to keep a Claude subagent running
through an account cap; the cap is account-wide. (Observed 2026-07-09: a doc-consolidation
agent + 2 forks all died mid-task on the cap.)

**The fix is not "immortal agents" — it is "survivable work."** Two independent levers:

## Lever 1 — Run survivable work on a cap-immune substrate (background bash + DeepSeek)

A `run_in_background` bash process that calls **DeepSeek** (`ds_flash.sh` / `ds_research`) is:
- an **OS process on the pod** — it does not depend on the Anthropic API to keep running;
- hitting a **separate provider on a separate account/key** (this repo's `.env`),
  which an Anthropic session cap does not touch.

So it **keeps executing while the Claude session is capped or ended**, and the results are
waiting in its output files when Anthropic access resumes. This is the primary substrate for
anything that can be expressed as *bounded text-generation over fetched inputs*: web/doc
research, summarisation, batch classification, code/SQL drafting, multi-doc synthesis.

**Rule of thumb:** if a delegated task needs *no live Claude judgment mid-run* — only reading
inputs and generating text — it should run as **background-bash + DeepSeek**, never as a Claude
subagent. Reserve Claude subagents for genuine tool-orchestration + judgment loops.

Caveat: background processes die if the **pod itself** restarts (not on a mere session cap).
Lever 2 covers that.

## Lever 2 — Checkpoint + resume (for any long job, esp. the unavoidably-Claude parts)

Structure every long delegated job as **idempotent units that checkpoint to disk**:
1. Split the work into units (per-file, per-media, per-section, per-question).
2. Before running a unit, check whether its output already exists (non-empty) → skip.
3. Run the unit; write its output **atomically** (tmp + mv); mark done.
4. On kill/cap, completed units persist. Re-running the job resumes from where it stopped.

A cap then costs **at most one unit**. Recovery is just "run the same job again" — from a fresh
session, or automatically (below). Use `resumable_run.sh` (this dir) to get this for free.

## Lever 3 — Auto-resume after the reset (for Claude-subagent work that can't be DeepSeek'd)

When a task *must* use Claude and gets capped, persist its checkpoint (Lever 2) and schedule a
resume for **after the reset time**:
- `ScheduleWakeup` (main-thread self-resume; clamped 60–3600 s) — good for a short wait.
- `CronCreate` a one-shot near the reset timestamp — good for a multi-hour wait across the cap.
On wake, re-dispatch the checkpointed task; it resumes instead of restarting.

## Decision table

| Task shape | Substrate | Survives Anthropic cap? |
|---|---|---|
| Research / doc synthesis / batch text-gen (no mid-run Claude judgment) | **background bash → `ds_flash`/`ds_research`**, via `resumable_run.sh` | **Yes** (keeps running) |
| Tool-orchestration + judgment loop (must be Claude) | Claude subagent, **checkpointed** (Lever 2) + auto-resume (Lever 3) | Pauses at cap, **resumes without loss** |
| Payload-heavy vision/tool extraction (must be Claude) | Haiku subagent, **checkpointed** per item | Pauses at cap, resumes without loss |

## Usage — `resumable_run.sh`

```
resumable_run.sh <job_dir> <units_file> <command_template>
```
- `units_file`: one work-unit token per line (a filename, media_id, section id, or question).
- `command_template`: **trusted, operator-authored shell code** run once per unit.
  `{UNIT}` is replaced with the literal shell variable `${UNIT}` before execution;
  the actual line from `units_file` is passed as an **environment variable** and is
  never interpolated into executable shell source. Always **double-quote each
  `{UNIT}` placeholder** where it represents one shell argument, for example
  `cat "/path/to/{UNIT}"`; otherwise shell word-splitting may still occur.
  The template itself is not a sandbox and must never come from untrusted users.
- For simple alphanumeric/`._-` unit IDs of at most 100 characters,
  checkpoint names remain `<job_dir>/out/<unit>.out` for backward
  compatibility. More complex IDs use a shortened readable prefix and
  SHA-256-derived suffix to prevent different names collapsing together.
  Existing checkpoint files must be regular, nonempty and **not symlinks**.
- Re-running skips completed units. A completed output is published using
  **create-only hard-link semantics**: a competing process cannot overwrite it.
  Incomplete/empty or symlinked destinations are refused, not deleted.
  A failed command or racing publication returns an unsuccessful batch status.
  Launch with `run_in_background` only in an environment you control.
- Final synthesis: a last unit (or a follow-up call) that concatenates `<job_dir>/out/*` and
  pipes to `ds_flash.sh` for the combined result.

Example (cap-immune doc consolidation):
```
printf '%s\n' MASTER.md DECISIONS.md ROADMAP.md > job/units.txt
resumable_run.sh job job/units.txt \
  'cat "/path/to/your/project/{UNIT}" | ds_flash.sh summarise "pathologies + unimplemented ideas in {UNIT}"'
# then: cat job/out/*.out | ds_flash.sh plan "synthesise one canonical-backbone proposal"
```
