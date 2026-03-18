---
phase: 05-spec-sync
plan: 01
subsystem: spec
tags: [spec-sync, documentation, drift-fix]
dependency_graph:
  requires: [04-01]
  provides: [accurate-spec-files]
  affects: [all-future-phases]
tech_stack:
  added: []
  patterns: [spec-driven-workflow]
key_files:
  created: []
  modified:
    - spec/ARCHITECTURE.md
    - spec/DATA_LAYER.md
    - spec/CONSTANTS.md
key_decisions:
  - "Placed ThrottleTracker section in Utilities subsection of DATA_LAYER.md (matches file location)"
  - "Used capitalized Downward/Upward in bidirectional tier description (readable prose, not code)"
  - "Added Dynamic Probe Model Storage as a separate CONSTANTS.md section (distinct from UserDefaults key catalog)"
metrics:
  duration: ~20min
  completed: 2026-03-18
  tasks_completed: 2
  files_modified: 3
---

# Phase 05 Plan 01: Spec Sync Summary

Brought all 4 spec files current with the codebase after Phases 1-4, fixing all known drift including ThrottleTracker documentation, AccountStore.canAddAccount correction, and all Phase 1-4 code changes reflected in specs.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Audit all spec files against source code for drift | (audit only, no files) | None |
| 2 | Update all 4 spec files to match current codebase | c4360ce | spec/ARCHITECTURE.md, spec/DATA_LAYER.md, spec/CONSTANTS.md |

## Changes Made

### spec/ARCHITECTURE.md

Added 3 missing entries to the project tree:
- `ThrottleTracker.swift` (Utilities/) — alphabetical after DurationFormatter.swift
- `ThrottleTrackerTests.swift` (Tests/Utilities/)
- `SessionLogReaderDiscoveryTests.swift` (Tests/Services/)

### spec/DATA_LAYER.md

1. **UsageSnapshot.todayToolCalls**: Updated source from "stats-cache dailyActivity for today" to "max(JSONL tool_use count, stats-cache dailyActivity) for today"

2. **SessionEntry**: Added `ContentBlock` nested struct (minimal, `type: String?` only), `content: [ContentBlock]?` on SessionMessage, `toolCallCount: Int` on AssistantUsageEntry

3. **AccountStore.canAddAccount**: Fixed from `(< 2)` to `(< maxAccounts)` — matches `accounts.count < Self.maxAccounts` in code

4. **RateLimitFetcher**: Complete rewrite of probe model description — replaced stale 3-model hardcoded list with: dynamic probe order (activeUserModel → lastWorkingModel → observedModels → ultimateFallback), documented `observedModels`, `setObservedModels`, `restoreWorkingModels`, `saveWorkingModel` on all 4 success paths

5. **TokenHealthMonitor (via TokenHealthConfig)**: Added bidirectional tier adjustment description — upward (existing) plus downward with anti-thrash guard (only downgrades when observedTokens < lowerTier boundary)

6. **SessionLogReader**: Added `discoveryTTL = 60s`, `lastFullEnumerationDate`, `expireDiscoveryTTLForTesting()`. Updated discovery caching description: cache hit requires BOTH unchanged directory mod-dates AND TTL not expired.

7. **UsageAggregator**: Replaced "Tool calls from stats cache only" with `max(jsonlTodayToolCalls, statsCacheToolCalls)` description. Added `lastSeenByModel` tracking that feeds `RateLimitFetcher.setObservedModels`.

8. **UsageViewModel**: Updated throttle helpers (recordThrottleEvent/throttleCount) to note they delegate to ThrottleTracker

9. **ThrottleTracker**: Added new section documenting the pure value type, `wasThrottled`, `evaluate`, `parseTimestamps`, `appendAndPrune`, `count` methods and their roles

### spec/CONSTANTS.md

Added two new sections:
- **Dynamic Probe Model Storage**: `aibattery_observedModels_{accountId}` and `aibattery_probeModel_{accountId}` keys
- **Throttle Event Storage**: `aibattery_throttleTimestamps` key with 30-day pruning window note

### spec/UI_SPEC.md

No changes required — no drift found. `throttleCount(days:)` reference accurate.

## Deviations from Plan

None — plan executed exactly as written.

## Self-Check

Files exist:
- spec/ARCHITECTURE.md: FOUND
- spec/DATA_LAYER.md: FOUND
- spec/CONSTANTS.md: FOUND

Acceptance criteria verified:
- grep "ThrottleTracker" spec/DATA_LAYER.md: 3 matches
- grep "< maxAccounts" spec/DATA_LAYER.md: 1 match
- grep "ThrottleTracker.swift" spec/ARCHITECTURE.md: 1 match
- grep "ThrottleTrackerTests" spec/ARCHITECTURE.md: 1 match
- grep "SessionLogReaderDiscoveryTests" spec/ARCHITECTURE.md: 1 match
- grep "observedModels" spec/DATA_LAYER.md: 4 matches
- grep "discoveryTTL" spec/DATA_LAYER.md: 1 match
- grep -i "downward" spec/DATA_LAYER.md: 2 matches
- grep "Tool calls from stats cache only" spec/DATA_LAYER.md: 0 matches (stale line removed)
- No .swift files modified: CONFIRMED

## Self-Check: PASSED
