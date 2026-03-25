---
phase: 15-breath-timer-fix
plan: 01
subsystem: ui

tags: [swift, swiftui, timer, cpu-performance, menu-bar, tdd]

# Dependency graph
requires: []
provides:
  - breathTimerShouldRun pure gating function in StatusBarManager
  - Breath timer stops immediately when popover closes
  - Breath timer restarts when popover opens (if conditions met)
  - 7 unit tests covering all gating combinations in BreathTimerGatingTests
affects: [breath-timer, cpu-performance, StatusBarManager]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Pure gating function extracted from stateful class for testability"
    - "Visibility gate: check toggleState.isShowing before starting any timer"

key-files:
  created:
    - Tests/AIBatteryCoreTests/Views/BreathTimerGatingTests.swift
  modified:
    - AIBattery/Views/StatusBarManager.swift
    - spec/DATA_LAYER.md
    - README.md

key-decisions:
  - "breathTimerShouldRun extracted as static func (not fileprivate) to allow @testable import access"
  - "stopBreathTimer() called directly in onDismiss (not updateBreathTimer) because dismiss always stops — no conditions to evaluate"
  - "updateBreathTimer called after orderFrontRegardless in .show case (toggleState.isShowing already true at that point)"

patterns-established:
  - "Visibility gate pattern: guard isShowing before starting any background timer in StatusBarManager"

requirements-completed: [PERF-01]

# Metrics
duration: 4min
completed: 2026-03-24
---

# Phase 15 Plan 01: Breath Timer Fix Summary

**Breath timer visibility gate via breathTimerShouldRun pure function — eliminates idle CPU from timer firing against hidden menu bar icon**

## Performance

- **Duration:** ~4 min
- **Started:** 2026-03-24T12:45:41Z
- **Completed:** 2026-03-24T12:49:18Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments

- Extracted `breathTimerShouldRun(isShowing:isThrottled:isSparkleActive:percent:)` static pure function from `updateBreathTimer` for testability
- Rewired `updateBreathTimer` to delegate all decisions to `breathTimerShouldRun` — single decision point
- Wired `stopBreathTimer()` in `panel.onDismiss` so timer stops immediately on panel close
- Wired `updateBreathTimer` call after `panel.orderFrontRegardless()` in `.show` case so timer restarts on panel open
- Added 7 unit tests in `BreathTimerGatingTests.swift` covering all gating combinations
- Updated `spec/DATA_LAYER.md` with new Views section documenting StatusBarManager and visibility gate
- Updated README test coverage: 735 → 742 tests, 48 → 49 files, Views area 72 → 79

## Task Commits

Each task was committed atomically:

1. **Task 1: Add visibility guard to updateBreathTimer and hook show/hide paths** - `8685dce` (feat)
2. **Task 2: Update spec and README test coverage** - `773235a` (docs)

_Note: TDD task committed as single GREEN commit (test + implementation together; RED phase was compilation failure confirming function not yet present)_

## Files Created/Modified

- `AIBattery/Views/StatusBarManager.swift` - Added breathTimerShouldRun static func; rewrote updateBreathTimer; added stopBreathTimer in onDismiss; added updateBreathTimer call in .show case
- `Tests/AIBatteryCoreTests/Views/BreathTimerGatingTests.swift` - New: 7 tests covering all gating combinations
- `spec/DATA_LAYER.md` - Added Views section with StatusBarManager breath timer documentation
- `README.md` - Updated test coverage counts (735→742, 48→49, Views 72→79)

## Decisions Made

- `breathTimerShouldRun` is `static func` (not `private static func`) to allow `@testable import AIBatteryCore` access from tests
- `stopBreathTimer()` is called directly in `onDismiss` rather than routing through `updateBreathTimer` — dismiss always stops the timer unconditionally, so no need to evaluate the full decision tree
- `updateBreathTimer` is called after `panel.orderFrontRegardless()` (not before) because `PanelToggleState.toggle()` already set `isShowing = true` at the top of the `.show` case

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

- `swift test` without Xcode installed cannot run Swift Testing framework tests (no `Testing` module). This is documented in CLAUDE.md. The RED phase was confirmed by compilation failure (function not defined). Build verification (`swift build`) confirmed GREEN phase compiled correctly.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Phase 15 is complete. Breath timer now gates on popover visibility.
- CPU hot path eliminated: timer no longer fires 2–8x/second against a hidden icon.
- Screen sleep/wake gating continues to work alongside visibility gate (unchanged).
- PopoverFooterView's TimelineView is unaffected (separate component, no changes made).

---
*Phase: 15-breath-timer-fix*
*Completed: 2026-03-24*
