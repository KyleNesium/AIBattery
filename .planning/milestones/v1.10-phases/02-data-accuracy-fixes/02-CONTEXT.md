# Phase 2: Data Accuracy Fixes - Context

**Gathered:** 2026-03-18
**Status:** Ready for planning

<domain>
## Phase Boundary

Fix two data accuracy issues: (1) rate limit probe model list is hardcoded — make it dynamically populated from observed JSONL models so it self-heals when Anthropic deprecates model IDs; (2) today's tool call count relies exclusively on stats-cache.json which can be stale — supplement with JSONL-derived tool call counts.

</domain>

<decisions>
## Implementation Decisions

### Probe Model List (BUG-01)
- The fallback list at `RateLimitFetcher.swift:30-36` has 5 hardcoded model IDs — these will break when deprecated
- Already has `activeUserModel` from JSONL as first choice and `lastWorkingModel` from UserDefaults as second
- Fix: populate the fallback list dynamically from models observed in JSONL sessions (via `SessionLogReader` or `UsageAggregator`)
- Keep 1-2 hardcoded models as ultimate fallback (newest Claude model) in case JSONL is empty (fresh install)
- The dynamic list should be sorted by recency (most recently seen model first)
- `restoreWorkingModels()` on launch should also restore the dynamic list from UserDefaults

### Tool Call Counting (BUG-04)
- Currently `todayToolCalls` at `UsageAggregator.swift:164-165` comes only from `statsCache?.dailyActivity`
- JSONL entries contain `tool_use` content blocks in assistant messages — these can be counted
- Fix: count `tool_use` blocks per JSONL entry during the existing parsing pass in `SessionLogReader`
- Add a `toolCallCount` field to the JSONL entry model (or accumulate during aggregation)
- Use `max(jsonlToolCalls, statsCacheToolCalls)` merge strategy (same pattern as messages/sessions)
- This supplements stale stats-cache data without replacing it when cache is fresh

### Claude's Discretion
- Whether to store the dynamic model list in UserDefaults or derive it fresh each aggregation cycle
- Exact field name and type for JSONL-derived tool call counts
- Whether to count tool_use blocks or tool_result blocks (tool_use is the correct choice — it's what the user invoked)

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `RateLimitFetcher.fallbackModels` — current hardcoded list at lines 30-36
- `RateLimitFetcher.activeUserModel` — already populated from JSONL
- `UsageAggregator.buildProjectTokens` — existing per-entry iteration that could count tool_use
- `SessionLogReader` — parses JSONL entries, could extract tool_use count per entry
- `StatsCache.DailyActivity.toolCallCount` — existing stats-cache source

### Established Patterns
- Model persistence: UserDefaults keyed by `aibattery_probeModel_{accountId}`
- Merge strategy: `max(jsonl, statsCache)` used for messages and sessions at UsageAggregator lines 231-259
- Cache invalidation: FileWatcher triggers StatsCacheReader and UsageAggregator
- Probe order: activeUserModel → lastWorkingModel → fallback list (deduped via Set)

### Integration Points
- `UsageAggregator` sets `activeUserModel` on `RateLimitFetcher` after JSONL read
- `UsageAggregator` merges stats-cache and JSONL data in `buildDailyActivity`
- `SessionLogReader.parseEntry()` already reads JSON — tool_use counting fits here
- `UsageSnapshot.todayToolCalls` consumed by `ActivitySection` view

</code_context>

<specifics>
## Specific Ideas

No specific requirements — well-defined data accuracy fixes with clear patterns to follow.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>
