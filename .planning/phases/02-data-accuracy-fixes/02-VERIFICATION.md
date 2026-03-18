---
phase: 02-data-accuracy-fixes
verified: 2026-03-18T00:00:00Z
status: passed
score: 7/7 must-haves verified
re_verification: false
---

# Phase 02: Data Accuracy Fixes — Verification Report

**Phase Goal:** Rate limit probe uses a resilient model list, and today's tool call count reflects actual JSONL data
**Verified:** 2026-03-18
**Status:** passed
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Rate limit probe continues working after Anthropic deprecates a model ID | VERIFIED | `observedModels` populated from JSONL each cycle; probe order: `activeUserModel` → `lastWorkingModel` → `observedModels` → `ultimateFallback` (line 97, RateLimitFetcher.swift) |
| 2 | Probe fallback list reflects models the user has actually used | VERIFIED | `UsageAggregator` builds `lastSeenByModel` in the existing single-pass loop and calls `RateLimitFetcher.shared.setObservedModels(_:accountId:)` after each aggregation cycle (lines 83-84, 174-177, UsageAggregator.swift) |
| 3 | Dynamic model list persists across app restarts via UserDefaults | VERIFIED | `setObservedModels` persists to key `aibattery_observedModels_{accountId}` (line 71, RateLimitFetcher.swift); `restoreWorkingModels()` restores on `init` (lines 58-64) |
| 4 | Fresh install with no JSONL still works using hardcoded ultimate fallback | VERIFIED | `static let ultimateFallback = "claude-sonnet-4-6-20250929"` (line 30) included as last element in probe list; test `ultimateFallback_isSingleHardcodedModel` verifies constant value |
| 5 | Today's tool call count reflects tool_use blocks counted from JSONL session logs | VERIFIED | `makeUsageEntry` counts `content?.filter { $0.type == "tool_use" }.count ?? 0` (line 296, SessionLogReader.swift); accumulated in `jsonlTodayToolCalls` inside `if ts >= today` block (line 121, UsageAggregator.swift) |
| 6 | Tool call count uses max(jsonl, statsCache) merge — JSONL supplements stale cache, does not replace fresh cache | VERIFIED | `let todayToolCalls = max(jsonlTodayToolCalls, statsCacheToolCalls)` (line 183, UsageAggregator.swift); daily activity merge loop also uses `max(toolCalls, activity[idx].toolCallCount)` (line 261) |
| 7 | Entries with zero tool calls do not inflate the count | VERIFIED | `count ?? 0` default; test `makeUsageEntry_noContent_returns_zeroToolCallCount` and `makeUsageEntry_emptyContent_returns_zeroToolCallCount` both pass |

**Score:** 7/7 truths verified

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `AIBattery/Services/RateLimitFetcher.swift` | Dynamic `observedModels` property replacing hardcoded `fallbackModels` | VERIFIED | Contains `observedModels`, `ultimateFallback`, `setObservedModels(_:accountId:)`, `aibattery_observedModels_` prefix; old 5-model `fallbackModels` array is absent |
| `AIBattery/Services/UsageAggregator.swift` | Sets observed models on RateLimitFetcher from JSONL data; JSONL tool call merge | VERIFIED | Contains `lastSeenByModel`, `observedModels`, `setObservedModels`, `jsonlTodayToolCalls`, `statsCacheToolCalls`, `max(jsonlTodayToolCalls` |
| `AIBattery/Models/SessionEntry.swift` | `content` array on `SessionMessage` for tool_use counting; `toolCallCount` on `AssistantUsageEntry` | VERIFIED | `struct ContentBlock: Codable { let type: String? }`, `let content: [ContentBlock]?` inside `SessionMessage`, `let toolCallCount: Int` on `AssistantUsageEntry` |
| `AIBattery/Services/SessionLogReader.swift` | Counts tool_use blocks in `makeUsageEntry` | VERIFIED | `let toolCallCount = message.content?.filter { $0.type == "tool_use" }.count ?? 0` at line 296, passed into `AssistantUsageEntry` initializer |
| `Tests/AIBatteryCoreTests/Services/RateLimitFetcherTests.swift` | Tests for dynamic model list behavior | VERIFIED | 6 new tests: `observedModels_defaultsToEmpty`, `setObservedModels_updatesInMemoryList`, `setObservedModels_persistsToUserDefaults`, `observedModels_restoredOnInit`, `setObservedModels_emptyList_fallsBackToUltimateFallback`, `ultimateFallback_isSingleHardcodedModel`, `hardcodedFallbackModels_noLongerExists` |
| `Tests/AIBatteryCoreTests/Services/SessionLogReaderTests.swift` | Tests for tool_use counting in `makeUsageEntry` | VERIFIED | 5 tests covering 2-tool count, no content, text-only, mixed content, empty array |
| `Tests/AIBatteryCoreTests/Services/UsageAggregatorTests.swift` | Tests for observed models after aggregation and max() merge strategy | VERIFIED | `makeAssistantLineWithToolCalls` helper; 4 tool call merge tests (JSONL wins, cache wins, no cache, no JSONL today); 2 observed models tests (sorted by recency, no-op when accountId nil) |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `UsageAggregator.swift` | `RateLimitFetcher.shared.observedModels` | Sets observed models after JSONL read | WIRED | `RateLimitFetcher.shared.setObservedModels(observedModels, accountId: accountId)` at line 176; guarded by `if let accountId` |
| `RateLimitFetcher.swift` | `UserDefaults` | Persists and restores observed models via `aibattery_observedModels_` | WIRED | `UserDefaults.standard.set(models, forKey: Self.observedModelsKeyPrefix + accountId)` in `setObservedModels`; `defaults.stringArray(forKey: key)` in `restoreWorkingModels()` |
| `SessionLogReader.swift` | `SessionEntry.SessionMessage.content` | Counts content blocks where `type == "tool_use"` | WIRED | `message.content?.filter { $0.type == "tool_use" }.count ?? 0` at line 296 of `makeUsageEntry` |
| `UsageAggregator.swift` | `UsageSnapshot.todayToolCalls` | `max(jsonlToolCalls, statsCacheToolCalls)` merge | WIRED | `let todayToolCalls = max(jsonlTodayToolCalls, statsCacheToolCalls)` at line 183; passed as `todayToolCalls: todayToolCalls` into `UsageSnapshot` initializer at line 316 |

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| BUG-01 | 02-01-PLAN.md | Rate limit probe model list is dynamically maintained, not hardcoded — app recovers when Anthropic deprecates model IDs | SATISFIED | `observedModels` dynamic list in `RateLimitFetcher`; hardcoded 5-model `fallbackModels` array removed; single `ultimateFallback` constant remains for fresh installs |
| BUG-04 | 02-02-PLAN.md | Today's tool call count reflects JSONL data, not just stats-cache | SATISFIED | `jsonlTodayToolCalls` accumulated from `entry.toolCallCount` in `UsageAggregator`; merged with stats-cache via `max()` at line 183 |

Both requirements marked complete in `REQUIREMENTS.md` (`[x]` checkboxes).

---

### Anti-Patterns Found

None detected. Scanned all modified files for TODO/FIXME/placeholder patterns, empty return stubs, and console-log-only handlers.

---

### Human Verification Required

None. All goal truths are verifiable programmatically from the codebase structure.

---

### Commits Verified

All 4 commits documented in phase summaries exist in git history:

| Commit | Description |
|--------|-------------|
| `015393c` | feat(02-01): dynamic probe model list in RateLimitFetcher |
| `4eac768` | feat(02-01): wire UsageAggregator to populate observed models |
| `02f2abb` | feat(02-02): add tool_use counting to SessionEntry and SessionLogReader |
| `81b2e0a` | feat(02-02): merge JSONL tool call count with stats-cache using max() strategy |

---

### Summary

Phase 02 fully achieves its goal. Both bug fixes are implemented, substantive, wired, and covered by tests.

**BUG-01 (resilient probe list):** The hardcoded 5-model `fallbackModels` array is gone. `RateLimitFetcher` now uses a dynamic `observedModels` list sourced from JSONL data, persisted to UserDefaults under a per-account key, and restored on every launch. The single `ultimateFallback` constant (`"claude-sonnet-4-6-20250929"`) guards fresh installs with no usage history. Probe order is fully documented in code and verified by tests.

**BUG-04 (accurate tool call count):** `SessionEntry.SessionMessage` now decodes a `content: [ContentBlock]?` array. `SessionLogReader.makeUsageEntry` counts `tool_use` type blocks and attaches the count to `AssistantUsageEntry.toolCallCount`. `UsageAggregator` accumulates `jsonlTodayToolCalls` in the existing single-pass loop and merges with stats-cache using `max()`, ensuring neither source underreports. The daily activity merge loop applies the same `max()` strategy when updating `DailyActivity.toolCallCount`.

---

_Verified: 2026-03-18_
_Verifier: Claude (gsd-verifier)_
