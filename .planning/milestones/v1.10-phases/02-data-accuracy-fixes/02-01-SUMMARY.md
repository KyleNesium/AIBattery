---
phase: 02-data-accuracy-fixes
plan: "01"
subsystem: rate-limit-probe
tags: [bug-fix, resilience, persistence, dynamic-config]
dependency_graph:
  requires: []
  provides: [dynamic-probe-model-list]
  affects: [RateLimitFetcher, UsageAggregator]
tech_stack:
  added: []
  patterns: [UserDefaults persistence, single-pass aggregation]
key_files:
  created: []
  modified:
    - AIBattery/Services/RateLimitFetcher.swift
    - AIBattery/Services/UsageAggregator.swift
    - Tests/AIBatteryCoreTests/Services/RateLimitFetcherTests.swift
    - Tests/AIBatteryCoreTests/Services/UsageAggregatorTests.swift
decisions:
  - "Single hardcoded ultimateFallback (newest Sonnet) instead of a 5-model list — minimal surface area for fresh installs"
  - "lastSeenByModel folded into existing for-loop in UsageAggregator to avoid a second O(n) pass"
  - "Restore best-effort: takes first matching key from UserDefaults (any account) on init, overwritten on first aggregation cycle"
metrics:
  duration: ~8 minutes
  completed: "2026-03-18"
  tasks_completed: 2
  files_modified: 4
---

# Phase 02 Plan 01: Dynamic Probe Model List Summary

**One-liner:** Replace 5-model hardcoded fallback in RateLimitFetcher with a UserDefaults-persisted dynamic list populated from JSONL-observed models, sorted by recency, with a single ultimateFallback for fresh installs.

## What Was Built

`RateLimitFetcher` previously had a hardcoded array of 5 model IDs as a fallback probe list. If Anthropic deprecated any of those IDs, every probe attempt would cycle through dead models until falling back on the last one or failing.

The fix replaces that array with:
- `static let ultimateFallback` — single newest Sonnet, used only if no JSONL data exists yet
- `private(set) var observedModels: [String]` — populated from JSONL, most-recently-seen first
- `func setObservedModels(_:accountId:)` — persists to UserDefaults under `aibattery_observedModels_{accountId}`
- Restore logic in `restoreWorkingModels()` — reloads `observedModels` from UserDefaults on app start

`UsageAggregator` now tracks `lastSeenByModel: [String: Date]` inside the existing single-pass for-loop (no additional iteration cost). After the loop, it sorts by recency and calls `RateLimitFetcher.shared.setObservedModels(_:accountId:)` when an `accountId` is available.

**Probe order:** `activeUserModel` → `lastWorkingModel[accountId]` → `observedModels` → `ultimateFallback`

## Tasks Completed

| Task | Description | Commit |
|------|-------------|--------|
| 1 | Dynamic probe model list in RateLimitFetcher (TDD) | 015393c |
| 2 | Wire UsageAggregator to populate observed models | 4eac768 |

## Deviations from Plan

None — plan executed exactly as written.

## Tests Added

**RateLimitFetcherTests:** 6 new tests covering:
- `observedModels` defaults to empty
- `setObservedModels` updates in-memory list
- `setObservedModels` persists to UserDefaults
- `restoreWorkingModels` also restores observedModels on init
- `ultimateFallback` constant value verified
- Documents that hardcoded fallbackModels is replaced

**UsageAggregatorTests:** 2 new tests covering:
- Observed models set after aggregation, sorted by recency (most recent first)
- No persistence when accountId is nil

## Self-Check: PASSED

- RateLimitFetcher.swift: FOUND
- UsageAggregator.swift: FOUND
- 02-01-SUMMARY.md: FOUND
- Commit 015393c (Task 1): FOUND
- Commit 4eac768 (Task 2): FOUND
