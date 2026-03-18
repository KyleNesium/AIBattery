---
phase: 02-data-accuracy-fixes
plan: "02"
subsystem: session-log-reader
tags: [bug-fix, tool-calls, jsonl, data-accuracy]
dependency_graph:
  requires: [02-01]
  provides: [jsonl-tool-call-count]
  affects: [SessionLogReader, UsageAggregator, SessionEntry]
tech_stack:
  added: []
  patterns: [TDD red-green, max() merge strategy, content block decoding]
key_files:
  created: []
  modified:
    - AIBattery/Models/SessionEntry.swift
    - AIBattery/Services/SessionLogReader.swift
    - AIBattery/Services/UsageAggregator.swift
    - Tests/AIBatteryCoreTests/Services/SessionLogReaderTests.swift
    - Tests/AIBatteryCoreTests/Services/UsageAggregatorTests.swift
decisions:
  - "ContentBlock decoding uses minimal struct (type only) — no need to parse id/name/input fields for counting"
  - "toolCallCount in daily activity merge loop uses jsonlTodayToolCalls (not already-merged todayToolCalls) so the existing max() in DailyActivity construction does the real merge"
metrics:
  duration: ~3 minutes
  completed: "2026-03-18"
  tasks_completed: 2
  files_modified: 5
---

# Phase 02 Plan 02: JSONL Tool Call Count Summary

**One-liner:** Count tool_use content blocks from JSONL assistant messages and merge with stats-cache tool call count using max() strategy, fixing stale-cache undercount for today's tool calls.

## What Was Built

Today's tool call count previously came only from `stats-cache.json`, which can be stale (rebuilt every ~5 minutes). JSONL has ground-truth data in assistant message content blocks (`tool_use` type entries).

The fix adds:
- `ContentBlock` struct nested inside `SessionMessage` — decodes content arrays from JSONL (only `type` field needed for counting)
- `content: [ContentBlock]?` field on `SessionMessage` — populated when JSON contains the array
- `toolCallCount: Int` field on `AssistantUsageEntry` — computed in `makeUsageEntry` as `content?.filter { $0.type == "tool_use" }.count ?? 0`
- `jsonlTodayToolCalls` accumulator in `UsageAggregator.aggregate()` — accumulated inside the existing `if ts >= today` block alongside `todayEntries`
- `max(jsonlTodayToolCalls, statsCacheToolCalls)` merge for `todayToolCalls` — JSONL wins when cache is stale, cache wins when it's fresher

**Merge logic:** JSONL and stats-cache each independently count tool calls. `max()` ensures neither underreports. When stats-cache is fresh (rebuilt after new tool calls), it wins. When JSONL has seen more tool calls than a stale cache, JSONL wins.

## Tasks Completed

| Task | Description | Commit |
|------|-------------|--------|
| 1 | Add tool_use counting to SessionEntry and SessionLogReader (TDD) | 02f2abb |
| 2 | Merge JSONL tool call count with stats-cache in UsageAggregator (TDD) | 81b2e0a |

## Deviations from Plan

None — plan executed exactly as written.

## Tests Added

**SessionLogReaderTests:** 5 new tests covering:
- 2 tool_use blocks → toolCallCount == 2
- No content field → toolCallCount == 0
- Only text blocks → toolCallCount == 0
- Mixed content (1 text + 3 tool_use) → toolCallCount == 3
- Empty content array → toolCallCount == 0

**UsageAggregatorTests:** 4 new tests + `makeAssistantLineWithToolCalls` helper covering:
- JSONL has more tool calls (5) than cache (3) → max wins at 5
- Cache has more tool calls (7) than JSONL (2) → max wins at 7
- No stats-cache daily activity → JSONL tool calls used directly
- No JSONL entries for today → stats-cache tool call count used

## Self-Check: PASSED

- AIBattery/Models/SessionEntry.swift: FOUND
- AIBattery/Services/SessionLogReader.swift: FOUND
- AIBattery/Services/UsageAggregator.swift: FOUND
- Tests/AIBatteryCoreTests/Services/SessionLogReaderTests.swift: FOUND
- Tests/AIBatteryCoreTests/Services/UsageAggregatorTests.swift: FOUND
- Commit 02f2abb (Task 1): FOUND
- Commit 81b2e0a (Task 2): FOUND
- swift build: PASSED
