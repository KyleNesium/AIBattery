---
phase: 01-context-projection-fixes
plan: "01"
subsystem: token-health
tags: [bug-fix, monitoring, context-window, rate-limit, documentation]
dependency_graph:
  requires: []
  provides: [bidirectional-tier-detection, accurate-projection-threshold-docs]
  affects: [TokenHealthMonitor, RateLimitUsage, spec/CONSTANTS.md]
tech_stack:
  added: []
  patterns: [bidirectional-tier-detection, anti-thrash-guard]
key_files:
  created: []
  modified:
    - AIBattery/Services/TokenHealthMonitor.swift
    - Tests/AIBatteryCoreTests/Services/TokenHealthMonitorTests.swift
    - Tests/AIBatteryCoreTests/Models/RateLimitUsageTests.swift
    - spec/CONSTANTS.md
decisions:
  - "Downward tier adjustment only triggers when observed tokens fall below the next-lower tier boundary (e.g. <500K for a 1M default window) to prevent thrash on small/early sessions"
  - "Corrected 0.30 test value to 0.15 to actually exercise the 0.20 threshold guard rather than relying on burn-rate math returning nil"
metrics:
  duration: "3 minutes"
  completed: "2026-03-18"
  tasks_completed: 2
  files_modified: 4
---

# Phase 01 Plan 01: Context Projection Fixes Summary

Bidirectional context window tier detection added to TokenHealthMonitor and stale 50% projection threshold documentation corrected to the actual 20% value across spec and tests.

## Tasks Completed

| # | Task | Commit | Status |
|---|------|--------|--------|
| 1 | Add downward context window tier adjustment with tests | ace3752, 8b7f3bc | Done |
| 2 | Fix CONSTANTS.md and stale test comments for projection threshold | 3f093b2 | Done |

## What Was Built

### Task 1: Bidirectional Context Window Tier Detection

**Before:** `TokenHealthMonitor.assess()` only adjusted the context window upward when `observedTokens > contextWindow`. A session with model `claude-opus-4-6` (default 1M) but only 150K observed tokens was assessed against a 1M window, reporting artificially low usage percentages.

**After:** Added a downward adjustment branch. After the upward check, if the current `contextWindow` is found in the tiers array and `observedTokens < lowerTier` (the tier one step below), the context window is downgraded to the smallest tier that still fits the observed tokens.

Anti-thrash guard: downgrade only fires when `observedTokens < lowerTier` (not just below the current tier). A session at 600K tokens on a 1M window does NOT downgrade, because 600K >= 500K (the tier below 1M). Only a session clearly in a lower tier's range (e.g. 400K < 500K) triggers the adjustment.

**New tests (5):**
- `contextWindow_downwardAdjustment_150K_to_200K` — 150K observed → window = 200K
- `contextWindow_downwardAdjustment_400K_to_500K` — 400K observed → window = 500K
- `contextWindow_noDownward_900K_stays_1M` — 900K observed → window stays 1M (no thrash)
- `contextWindow_upwardAdjustment_1_2M_to_2M` — 1.2M observed → window = 2M (upward unchanged)
- `contextWindow_verySmall_50K_stays_200K` — 50K observed → window = 200K (smallest available tier)

### Task 2: Correct Projection Threshold Documentation

**Before:** `spec/CONSTANTS.md` documented the minimum utilization as 50%. `RateLimitUsageTests` had comments referencing ">50%" and a test value of 0.30 (which is above the actual 0.20 threshold — the test passed by coincidence via burn-rate math returning nil, not the threshold guard). A second test's comment said "threshold is > 0.50" while checking 0.50 exactly.

**After:**
- `spec/CONSTANTS.md` now reads `20% (below this, estimate not shown)` — matches the actual code guard `utilization > 0.20`
- `estimatedTimeToLimit_lowUtilization_returnsNil` now uses `fiveHourUtil: 0.15` (genuinely below the threshold) — the test now verifies the threshold guard, not burn-rate math
- `estimatedTimeToLimit_exactlyAtThreshold_returnsNil` corrected to check `0.20` exactly with comment "threshold is > 0.20"
- New test `estimatedTimeToLimit_justAboveThreshold_returnsEstimate` proves projections work at 25% utilization (in the 20-50% range): 0.25 util with 0.5h elapsed and 4.5h remaining produces a ~1.5h estimate

## Deviations from Plan

### Environment Note

The `Testing` framework requires Xcode (not just Command Line Tools). This machine has only CLT installed. `swift test` fails with "no such module 'Testing'" — this is a pre-existing environment constraint not caused by these changes. Build succeeds (`swift build`). CI (GitHub Actions macos-15 runner with full Xcode) will execute the full test suite.

None of the logic changes deviated from the plan. All code follows the exact implementation described in the plan's `<action>` blocks.

## Self-Check: PASSED

All modified files exist. All 3 task commits (ace3752, 8b7f3bc, 3f093b2) confirmed in git log.
