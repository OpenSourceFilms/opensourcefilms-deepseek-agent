# ds_research — Source-Backed Web Research for Claude Code

> **Maintenance status (October 2026): historical tool.** OSF retired DeepSeek
> from its active production agent stack. This repository remains public as a
> reusable example of source-backed delegation, but is not a supported part of
> the current OSF deployment. Provider APIs, prices and access rules may have
> changed; verify them before running the scripts.

## The right tool for each job

| Task | Command |
|---|---|
| Live web research (docs, APIs, packages) | `ds_research "question"` |
| Niche technical / package query | `ds_research --jina-search "question"` |
| Fetch a specific URL | `ds_research --url URL "question"` |
| Summarise already-fetched content | `ds_flash.sh web_research "content"` ← not live search |
| No-internet (local+cache only) | `ds_research --no-paid-token-providers "q"` |

**`ds_flash.sh web_research` is a content summariser, not a live search tool.**
It takes content you already have and asks DeepSeek to summarise/analyse it.
Use `ds_research` whenever you need to actually fetch sources.

## Provider routing (automatic, free-first)

1. **Local source resolver** — reads installed package source, binary shebang files.
   Best for CLI tool behaviour, package API, installed config. No network, instant.

2. **Explicit URL** (`--url`) — fetches via Jina Reader `r.jina.ai` (no key needed).
   Cache hit on second run. Key used only if rate-limited.

3. **Cache** — 12-hour TTL. Bypass with `--refresh`.

4. **SearXNG** — if `SEARXNG_URL` is set. Free.

5. **DDGS** — DuckDuckGo via maintained `ddgs` package. Free, unofficial. Good for
   broad/general queries. May return poor results for niche technical queries.

6. **Jina Search** `s.jina.ai` — precise search with content extraction. Requires
   `JINA_API_KEY`. Costs ~10k tokens per request. Auto-triggered when DDGS quality
   is poor for technical queries. Force with `--jina-search`.

7. **Brave Search** — if `BRAVE_SEARCH_API_KEY` is set. Optional.

## Token budget

- Jina free balance: ~10M tokens ≈ ~1,000 searches minimum
- Budget tracked at: `cache/jina_usage.json`
- Warning triggers at 800/1000 searches (80% used)
- Check: `./verify_ds_research.sh --check-balance`
- **There is no auto-renewal.** Get a new free key at https://jina.ai when exhausted.

## Flags

```bash
ds_research "query"                         # standard: local → DDGS → auto-escalate
ds_research --jina-search "query"           # force Jina Search (~10k tokens)
ds_research --deep "query"                  # all providers, up to 3 Jina searches
ds_research --url URL "question"            # fetch specific URL, answer question
ds_research --urls U1,U2 "question"        # fetch multiple URLs
ds_research --refresh "query"               # bypass cache
ds_research --flash "query"                 # use cheaper DeepSeek Flash model
ds_research --no-paid-token-providers "q"   # local + DDGS only, no keyed APIs
ds_research --limit N "query"               # fetch N sources (default 3)
```

## Setup

```bash
git clone <this repo's URL>
cd opensourcefilms-deepseek-agent
bash install_or_update_ds_research.sh
cp .env.example .env   # then fill in your keys
```

## Secrets

The primary path is a local `.env` file (see `.env.example`) — never commit it,
`.gitignore` already excludes it.

If you'd rather keep keys outside the repo entirely (e.g. a shared secrets
directory across multiple tools/pods), set `DEEPSEEK_AGENT_SECRETS_DIR` to a
directory containing one file per key, filename = the env var name lowercased:

```bash
export DEEPSEEK_AGENT_SECRETS_DIR=/path/to/your/secrets
echo "YOUR_JINA_KEY"     > "$DEEPSEEK_AGENT_SECRETS_DIR/jina_api_key"
echo "YOUR_DEEPSEEK_KEY" > "$DEEPSEEK_AGENT_SECRETS_DIR/deepseek_api_key"
```

A third, optional layer reads exported vars from a shell file at
`$DEEPSEEK_AGENT_ENV_SH`, if you set that too. All three layers are additive —
`.env` wins if a key is set in more than one place.

**Never put keys in:**
- prompts or conversation text
- command arguments (visible in shell history)
- log files
- cache entries
- exported bundles

## Running on a persistent-volume pod (e.g. Runpod)

This tool has no GPU dependency of its own — it's a CPU-side CLI. It does work
well on a Runpod pod with a persistent volume, the same way
[opensourcefilms-baton](https://github.com/OpenSourceFilms/opensourcefilms-baton)
does: place this repo on the persistent volume (not the ephemeral container
root) so `.env`, `cache/`, and `logs/` survive a pod restart, and add it to
`PATH` via whatever shell-init convention your pod uses (`DEEPSEEK_AGENT_ENV_SH`,
above, is one way to automate that). Nothing here requires Runpod specifically —
it's just a good fit for the same persistent-volume-vs-ephemeral-container
reasoning documented in BATON's own `RUNPOD.md`.

## Verification

```bash
./verify_ds_research.sh            # fast tests, no API calls
./verify_ds_research.sh --full     # incl. a real Jina Search call
./verify_ds_research.sh --check-balance
```

`tests/selfcheck.sh` is a lighter, no-network syntax + no-committed-secrets
check (same pattern used across OSF's other public repos) — safe to run
without any keys configured at all.

## Update / reinstall

```bash
./install_or_update_ds_research.sh
```

Optionally registers a Claude Code routing block (`CLAUDE_DS_RESEARCH_FRAGMENT.md`)
into `~/.claude/CLAUDE.md` (or `$DEEPSEEK_AGENT_CLAUDE_MD` if set) — skip with
`--skip-claude-md`.

## Export / restore a bundle

Convenience scripts for moving this tool between machines without a full git
clone (e.g. copying a working setup onto a fresh pod):

```bash
./export_ds_research_bundle.sh   # -> ../ds_research_bundle.tar.gz, secrets excluded
./restore_ds_research.sh         # after extracting a bundle elsewhere
```

Set `DEEPSEEK_AGENT_BUNDLE_COPY_TO` before exporting if you also want a copy
placed somewhere durable (e.g. a persistent-volume path).

## Resumable, cap-immune delegation

`resumable_run.sh` and `RESUMABLE_DELEGATION.md` document a pattern for
running long batches of delegated commands with checkpointed output. The
historical explanation of independent-provider execution appears in that
document. `resumable_run.sh` now uses **non-executable unit interpolation**,
collision-resistant filenames for complex unit IDs, and **create-only**
checkpoint publication. Its command template remains **trusted shell code**;
always quote `"{UNIT}"` inside the template when the unit is one argument.
Existing simple-name checkpoints keep their prior filenames. Eight isolated
Bash subprocess regression tests run offline through GitHub Actions. These
tests do not make an API call or establish that the historical DeepSeek
integration is supported, secure to deploy, or current.

## What this is not

Not a polished framework — it's the actual tool OSF uses day to day
(3 commits, June-August 2026, still actively developed). No config-file
format beyond `.env`/env vars, no plugin system. Published because it's real,
working delegation infrastructure, not because it's meant to be a drop-in
library for another team's different setup.

---

[Open Source Films](https://opensourcefilms.org). Runpod-sponsored GPU
compute funds the broader production environment this tool was built inside,
though this specific tool has no GPU dependency of its own.
