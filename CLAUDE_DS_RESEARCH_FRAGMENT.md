## ds_research — Web Research Routing

For source-backed research, run:
  ds_research "<question>"

Do not answer from prior knowledge for current docs/API/tooling claims.
Fetch sources first through ds_research.

For live/source-backed web research: use `ds_research`.
Do NOT use `ds_flash.sh web_research` unless source content has already
been fetched externally — it is a summariser, not a live search tool.

### Provider priority (automatic)
1. **Local/source resolver** — installed package source, binary shebang (free, instant)
2. **Explicit URL** — `--url URL` via no-key Jina Reader (free)
3. **Cache** — 12h TTL, bypassed with `--refresh`
4. **SearXNG** — if `SEARXNG_URL` is set (free)
5. **DDGS** — maintained DuckDuckGo package (free, unofficial)
6. **Jina Search** — `--jina-search` or auto-escalate for niche queries (~10k tokens/request)
7. **Brave/Serper** — only if keys are set (optional)

### Key flags
```
ds_research "query"                         # standard search
ds_research --jina-search "query"           # force Jina Search (finite tokens)
ds_research --url URL "question"            # fetch specific URL only
ds_research --no-paid-token-providers "q"   # DDGS/local only
ds_research --flash "query"                 # cheaper DeepSeek model
ds_research --refresh "query"               # bypass cache
```

### Escalation rule
If ds_research answer is uncertain on a high-stakes decision (destructive
commands, legal/pricing/API details, doc-vs-behaviour discrepancies),
escalate to a human maintainer for final verification rather than guessing.

### Token budget
Jina Search free balance: ~10M tokens ≈ 1,000 searches minimum.
Cache protects repeat queries. Monitor via `verify_ds_research.sh --check-balance`.
