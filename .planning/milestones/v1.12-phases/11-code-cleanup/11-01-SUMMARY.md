---
phase: 11-code-cleanup
plan: 01
subsystem: ui
tags: [swift, swiftui, dead-code, spec-sync, cleanup]

# Dependency graph
requires:
  - phase: 10-popover-performance
    provides: GaugeBar extraction and PERF-10/11 v1.9.4 fixes
provides:
  - Clean Spacing.swift without sectionPadding() dead code
  - Clean PopoverStateViews.swift without PopoverLoadingView dead code
  - Accurate spec/CONSTANTS.md with real MotionConstants values (0.15s/0.1s easeOut)
  - Accurate spec/UI_SPEC.md without stale design tokens
  - Accurate spec/ARCHITECTURE.md without removed symbols
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Spec-driven cleanup: remove orphaned code, then sync all spec files atomically"

key-files:
  created: []
  modified:
    - AIBattery/Utilities/Spacing.swift
    - AIBattery/Views/PopoverStateViews.swift
    - spec/CONSTANTS.md
    - spec/UI_SPEC.md
    - spec/ARCHITECTURE.md

key-decisions:
  - "sectionPadding() removed — no callers found in codebase; inline .padding() calls remain as-is"
  - "PopoverLoadingView removed — replaced by spinner in PopoverHeaderView; no callers in production code"

patterns-established:
  - "Dead code removal paired with spec sync in a single atomic commit"

requirements-completed: [CQ-03, CQ-04, CQ-05]

# Metrics
duration: 2min
completed: 2026-03-19
---

# Phase 11 Plan 01: Dead Code Removal and Spec Sync Summary

**Removed sectionPadding() View extension and PopoverLoadingView struct, and synced CONSTANTS.md/UI_SPEC.md/ARCHITECTURE.md to match actual MotionConstants values (0.15s easeOut standard, 0.1s easeOut snappy)**

## Performance

- **Duration:** 2 min
- **Started:** 2026-03-19T23:45:39Z
- **Completed:** 2026-03-19T23:47:06Z
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments
- Deleted `sectionPadding()` View extension (14 lines) from `Spacing.swift` — zero callers in production code
- Deleted `PopoverLoadingView` struct (17 lines) from `PopoverStateViews.swift` — zero callers in production code
- Updated `spec/CONSTANTS.md` Animations table and MotionConstants table: corrected from `.easeInOut(duration: 0.2/0.15)` to `.easeOut(duration: 0.15/0.1)`
- Updated `spec/UI_SPEC.md`: removed `sectionPadding()` design token bullet, corrected MotionConstants summary
- Updated `spec/ARCHITECTURE.md`: removed `sectionPadding()` and `PopoverLoadingView` from file descriptions
- Verified README test coverage accurate: 716 tests across 46 files (unchanged by dead code removal)

## Task Commits

Each task was committed atomically:

1. **Task 1: Remove dead code and sync specs** - `fc04c00` (refactor)
2. **Task 2: Verify and update README test coverage** - no changes needed (counts verified accurate)

**Plan metadata:** (docs commit below)

## Files Created/Modified
- `AIBattery/Utilities/Spacing.swift` - Removed sectionPadding() View extension (lines 71-83)
- `AIBattery/Views/PopoverStateViews.swift` - Removed PopoverLoadingView struct (lines 1-17)
- `spec/CONSTANTS.md` - Corrected Animations and MotionConstants tables
- `spec/UI_SPEC.md` - Removed sectionPadding() token, fixed MotionConstants values
- `spec/ARCHITECTURE.md` - Removed sectionPadding() and PopoverLoadingView from file descriptions

## Decisions Made
- README test count did not need updating: dead code had no tests, so removing it left count at 716/46

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Phase 11 complete — codebase has zero orphaned dead code references
- All specs accurate and ready for v1.12 milestone closeout

---
*Phase: 11-code-cleanup*
*Completed: 2026-03-19*
