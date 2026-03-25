---
phase: 04-polling-discovery-hardening
plan: 01
subsystem: api
tags: [ratelimit, polling, adaptive-backoff, user-defaults, perf]

requires:
  - phase: 02-model-discovery
    provides: "RateLimitFetcher with saveWorkingModel and observedModels — the persistence infrastructure this plan extends"

provides:
  - "saveWorkingModel called on all four success paths in RateLimitFetcher.tryFetch (200-OK, 429+headers, retry-after, 400+headers)"
  - "FileWatcher no longer resets adaptive polling backoff — only evaluate(dataChanged:true), wake, and manual interval change reset it"

affects: [05-cleanup-polish]

tech-stack:
  added: []
  patterns:
    - "All .success paths in tryFetch must call saveWorkingModel before returning — structural invariant"
    - "FileWatcher owns only cache invalidation and refresh trigger; adaptive polling counter management belongs solely to evaluate()"

key-files:
  created: []
  modified:
    - AIBattery/Services/RateLimitFetcher.swift
    - AIBattery/ViewModels/UsageViewModel.swift
    - Tests/AIBatteryCoreTests/Services/RateLimitFetcherTests.swift
    - Tests/AIBatteryCoreTests/Utilities/AdaptivePollingStateTests.swift

key-decisions:
  - "saveWorkingModel added to retry-after success path (line ~225) per plan — this path was also missing the call alongside the two explicitly named paths"
  - "FileWatcher callback retains restartPolling(interval:) call — it legitimately resets the timer interval to base so the next cycle fires promptly after a file change"

patterns-established:
  - "Invariant: every FetchResult.success return in tryFetch calls saveWorkingModel(model, accountId:) before returning"
  - "Invariant: AdaptivePollingState.unchangedCycles is only externally reset on wake (NSWorkspace.didWakeNotification) and manual interval change (updatePollingInterval) — FileWatcher does not touch it"

requirements-completed: [PERF-07, PERF-08]

duration: 2min
completed: 2026-03-18
---

# Phase 04 Plan 01: Polling Discovery Hardening Summary

**saveWorkingModel added to all four RateLimitFetcher success paths and FileWatcher polling reset removed, eliminating unnecessary probe API calls and adaptive backoff thrash**

## Performance

- **Duration:** 2 min
- **Started:** 2026-03-18T20:30:00Z
- **Completed:** 2026-03-18T20:32:00Z
- **Tasks:** 1
- **Files modified:** 4

## Accomplishments
- Added `saveWorkingModel(model, accountId:)` call to 429+headers, retry-after, and 400+headers success paths in `RateLimitFetcher.tryFetch` — now all 4 success paths persist the probe model
- Removed `self?.adaptivePolling.unchangedCycles = 0` from `setupFileWatcher()` — adaptive backoff now builds correctly across file change events
- Added PERF-07 working-model persistence round-trip regression tests
- Added PERF-08 FileWatcher-style counter accumulation tests verifying counter grows under repeated no-change evaluations

## Task Commits

1. **Task 1: Persist working model on 429/400 success paths and remove FileWatcher polling reset** - `548e6a8` (feat)

**Plan metadata:** (pending final commit)

## Files Created/Modified
- `AIBattery/Services/RateLimitFetcher.swift` - saveWorkingModel now called in all 4 success paths (lines 108, 204, 225, 250)
- `AIBattery/ViewModels/UsageViewModel.swift` - removed adaptivePolling.unchangedCycles = 0 from setupFileWatcher
- `Tests/AIBatteryCoreTests/Services/RateLimitFetcherTests.swift` - added 3 PERF-07 regression tests
- `Tests/AIBatteryCoreTests/Utilities/AdaptivePollingStateTests.swift` - added 3 PERF-08 regression tests

## Decisions Made
- Retry-after success path also needed `saveWorkingModel` — the plan explicitly listed it in the action section; confirmed and added
- FileWatcher `restartPolling(interval:)` call intentionally kept — it correctly resets the timer to base interval so next poll fires promptly after a file change (only the counter reset was the bug)

## Deviations from Plan

None - plan executed exactly as written. All three call-site additions and one line removal matched the plan specifications.

## Issues Encountered
- `swift test` cannot run locally — Command Line Tools only (no Xcode.app installed). Build (`swift build`) confirmed compilation passes. CI (macos-15 runner with full Xcode) will validate tests.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- PERF-07 and PERF-08 fixes in place, ready for plan 04-02
- No blockers

---
*Phase: 04-polling-discovery-hardening*
*Completed: 2026-03-18*

## Self-Check: PASSED

- FOUND: AIBattery/Services/RateLimitFetcher.swift (5 saveWorkingModel occurrences)
- FOUND: AIBattery/ViewModels/UsageViewModel.swift (setupFileWatcher has no adaptivePolling reset)
- FOUND: Tests/AIBatteryCoreTests/Services/RateLimitFetcherTests.swift
- FOUND: Tests/AIBatteryCoreTests/Utilities/AdaptivePollingStateTests.swift
- FOUND: .planning/phases/04-polling-discovery-hardening/04-01-SUMMARY.md
- FOUND: commit 548e6a8
