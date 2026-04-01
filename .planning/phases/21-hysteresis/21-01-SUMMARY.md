---
phase: 21-hysteresis
plan: 01
status: complete
started: 2026-04-01
completed: 2026-04-01
---

# Plan 21-01: Hysteresis Logic — Summary

## What Was Built

Added hysteresis to auto mode to prevent view flip-flopping when metric values hover near escalation thresholds. Implemented a 10pp de-escalation band: once a mode is selected, it stays until the underlying metric drops 10 percentage points below its escalation threshold.

### Key Implementation

- **`UsageSnapshot.applyHysteresis(candidate:previous:snapshot:)`** — Pure static function that decides whether to hold the previous mode or accept the new candidate. Release thresholds: rate limit modes at 70% (80% - 10pp), context health at 50% (60% - 10pp).
- **`UsageViewModel.lastResolvedMode`** — Cross-poll state storing the previously displayed mode.
- **`UsageViewModel.resolvedMetricMode`** — Published property consumed by views (replaces direct `snapshot.autoResolvedMode` access).
- **`UsageViewModel.resetHysteresis()`** — Clears state on manual mode override and account switch.

### Hysteresis Rules

1. **No previous state** (first poll/after reset) → accept candidate as-is
2. **Throttle** → always immediate (Tier 1 bypass)
3. **Same mode** → no change needed
4. **Rate limit mode held** → stay if current RL% >= 70%, release if below
5. **Context health held** → stay if active session AND context% >= 50%, release otherwise
6. **Session staleness** → hard gate, overrides hysteresis
7. **Upward escalation** → immediate (candidate wins)

## Key Files

### key-files.created
- (none — all modifications to existing files)

### key-files.modified
- `AIBattery/Models/UsageSnapshot.swift` — `applyHysteresis` static function + `hysteresisDeescalationBand` constant
- `AIBattery/ViewModels/UsageViewModel.swift` — `lastResolvedMode`, `resolvedMetricMode`, `resetHysteresis()`, hysteresis wiring in `updateSnapshot`
- `AIBattery/Views/UsagePopoverView.swift` — Reads `viewModel.resolvedMetricMode` instead of `snapshot.autoResolvedMode`
- `AIBattery/Views/StatusBarManager.swift` — Reads `viewModel.resolvedMetricMode` instead of `snapshot.autoResolvedMode`
- `Tests/AIBatteryCoreTests/Models/UsageSnapshotTests.swift` — 11 hysteresis test cases
- `spec/DATA_LAYER.md` — Documented hysteresis function and ViewModel state
- `spec/CONSTANTS.md` — Added hysteresis de-escalation band constant

## Commits

1. `78dda0d` — test(21-01): add failing hysteresis tests and stub function
2. `3d6d9bb` — feat(21-01): implement hysteresis logic and wire views

## Decisions

- Made `hasActiveSession` internal (was private) so `applyHysteresis` static function can access it
- `resetHysteresis()` called from 3 keyboard shortcut handlers in UsagePopoverView for manual mode changes
- Hysteresis state reset in `switchAccount` alongside snapshot reset

## Self-Check: PASSED

- [x] All tasks executed (2/2)
- [x] Each task committed individually (2 commits)
- [x] `swift build` succeeds
- [x] No `snapshot.autoResolvedMode` in views (all replaced with `viewModel.resolvedMetricMode`)
- [x] Specs updated (CONSTANTS.md, DATA_LAYER.md)
