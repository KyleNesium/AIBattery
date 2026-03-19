---
phase: 07-visual-polish
plan: 01
subsystem: ui
tags: [swiftui, divider, animation, spacing, motion]

requires:
  - phase: 06-design-system
    provides: Spacing/Layout/Typography token enums consumed by StyledDivider and all migrated views

provides:
  - StyledDivider reusable component (opacity 0.3, Spacing.tight padding)
  - MotionConstants enum (.standard 0.2s, .snappy 0.15s) in Spacing.swift
  - All 19 visual popover Divider() callsites replaced with StyledDivider()

affects: [08-file-extraction, any future view adding section dividers]

tech-stack:
  added: []
  patterns:
    - StyledDivider replaces bare Divider() in all popover section boundaries
    - MotionConstants centralizes animation duration constants (matches ThemeColors/Typography/Spacing pattern)

key-files:
  created:
    - AIBattery/Views/StyledDivider.swift
  modified:
    - AIBattery/Utilities/Spacing.swift
    - Tests/AIBatteryCoreTests/Utilities/SpacingTests.swift
    - AIBattery/Views/UsagePopoverView.swift
    - AIBattery/Views/ActivityChartView.swift
    - AIBattery/Views/AuthView.swift
    - AIBattery/Views/UsageGateViews.swift
    - AIBattery/Views/Settings/SettingsRow.swift

key-decisions:
  - "Menu Divider() in accountPicker kept as bare Divider() — SwiftUI Menu content uses native menu separators, not visual view dividers; StyledDivider would be architecturally incorrect there"

patterns-established:
  - "StyledDivider: all popover section visual dividers use opacity 0.3 + Spacing.tight (2pt) padding"
  - "MotionConstants: caseless enum namespace for animation durations, co-located in Spacing.swift"

requirements-completed: [UI-06]

duration: 4min
completed: 2026-03-19
---

# Phase 07 Plan 01: Visual Polish — Divider Standardization Summary

**StyledDivider component and MotionConstants enum created; 19 of 20 Divider() callsites in popover views replaced with uniform opacity-0.3 + 2pt-padded dividers**

## Performance

- **Duration:** ~4 min
- **Started:** 2026-03-19T15:38:00Z
- **Completed:** 2026-03-19T15:42:58Z
- **Tasks:** 2
- **Files modified:** 7 (1 created)

## Accomplishments
- Created `StyledDivider.swift` — standardized divider with opacity 0.3 and `Spacing.tight` (2pt) vertical padding
- Added `MotionConstants` enum to `Spacing.swift` with `.standard` (0.2s) and `.snappy` (0.15s) animation constants
- Added `MotionConstantsTests` suite to `SpacingTests.swift` verifying both animation values
- Replaced all 19 visual section `Divider()` calls across 5 popover view files with `StyledDivider()`

## Task Commits

Each task was committed atomically:

1. **Task 1: Create MotionConstants, StyledDivider, and tests** - `1a6acdf` (feat)
2. **Task 2: Replace all Divider() callsites with StyledDivider()** - `534de87` (feat)

**Plan metadata:** (docs commit follows)

## Files Created/Modified
- `AIBattery/Views/StyledDivider.swift` - New reusable styled divider view
- `AIBattery/Utilities/Spacing.swift` - Added MotionConstants enum
- `Tests/AIBatteryCoreTests/Utilities/SpacingTests.swift` - Added MotionConstantsTests suite + import SwiftUI
- `AIBattery/Views/UsagePopoverView.swift` - 9 Divider() → StyledDivider() (1 menu separator kept)
- `AIBattery/Views/ActivityChartView.swift` - 2 inline Divider().opacity(0.3).padding(.vertical, 2) → StyledDivider()
- `AIBattery/Views/AuthView.swift` - 2 Divider() → StyledDivider()
- `AIBattery/Views/UsageGateViews.swift` - 2 Divider() → StyledDivider()
- `AIBattery/Views/Settings/SettingsRow.swift` - 4 Divider().opacity(0.5) → StyledDivider()

## Decisions Made
- Menu separator in `accountPicker` kept as bare `Divider()`: SwiftUI `Menu` content uses native platform menu items; `StyledDivider` (a custom `View` struct) cannot serve as a menu separator and would produce incorrect behavior. The plan's listed line count assumed it was a visual divider.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Menu separator preserved as bare Divider()**
- **Found during:** Task 2 (Replace all Divider() callsites)
- **Issue:** `UsagePopoverView.swift` line 340 `Divider()` is inside a SwiftUI `Menu` `@ViewBuilder` block — it's a native menu item separator, not a visual section divider. Replacing with `StyledDivider()` would not compile or would behave incorrectly.
- **Fix:** Kept as `Divider()` — 19 replacements made instead of 20. Build passes and all popover visual dividers are standardized.
- **Files modified:** UsagePopoverView.swift (no change to that line)
- **Verification:** `swift build` succeeds; grep confirms only that one menu `Divider()` remains
- **Committed in:** `534de87` (Task 2 commit)

---

**Total deviations:** 1 auto-assessed (1 Rule 1 scope clarification — 19/20 replacements correct)
**Impact on plan:** No functional impact. The menu separator is correct as `Divider()`. All popover visual section dividers are now StyledDivider().

## Issues Encountered
- `swift test --filter MotionConstants` fails with "no such module 'Testing'" — pre-existing environment issue (Command Line Tools only, no Xcode). Build passes; test framework requires Xcode as documented in CLAUDE.md.

## Next Phase Readiness
- StyledDivider and MotionConstants foundation ready for Phase 07 Plan 02 (header style and collapse behavior standardization)
- All visual popover section dividers are now uniform — opacity 0.3, 2pt padding

---
*Phase: 07-visual-polish*
*Completed: 2026-03-19*
