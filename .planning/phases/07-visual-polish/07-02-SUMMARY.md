---
phase: 07-visual-polish
plan: 02
subsystem: ui
tags: [swiftui, animation, transitions, motion-constants]

requires:
  - phase: 07-visual-polish
    plan: 01
    provides: MotionConstants enum (.standard 0.2s, .snappy 0.15s) in Spacing.swift

provides:
  - Opacity fade transitions on all collapsible section content blocks
  - Numeric text transitions on percentage, cost, and token count Text views
  - All inline easeInOut animation literals migrated to MotionConstants references

affects: [any future view adding collapsible sections or numeric metrics]

tech-stack:
  added: []
  patterns:
    - ".transition(.opacity) on content blocks inside if !collapsed guards"
    - ".contentTransition(.numericText()) on Text views displaying numeric values that change on poll cycles"
    - "MotionConstants.standard / .snappy replace all inline easeInOut(duration:) literals in popover view files"

key-files:
  created: []
  modified:
    - AIBattery/Views/TokenHealthSection.swift
    - AIBattery/Views/ProjectUsageSection.swift
    - AIBattery/Views/ActivityChartView.swift
    - AIBattery/Views/UsageBarsSection.swift
    - AIBattery/Views/CollapsibleSectionHeader.swift
    - AIBattery/Views/UsagePopoverView.swift

key-decisions:
  - "ActivityChartView chart content wrapped in VStack before .transition(.opacity) — switch statement cannot directly receive view modifiers, requires a container"
  - "ActivityChartView insights block (if !collapsed, let snapshot) wrapped in VStack with .transition(.opacity) — plan's trendSummary/costSection/insightRows are @ViewBuilder funcs, not a single value, requiring a container for the transition modifier"

patterns-established:
  - "Collapsible section content: wrap the body of if !collapsed { } in a VStack with .transition(.opacity) at bottom"
  - "Numeric Text views: .contentTransition(.numericText()) with no arguments (macOS 13+ safe; numericText(value:) requires macOS 14)"

requirements-completed: [UI-07]

duration: 6min
completed: 2026-03-19
---

# Phase 07 Plan 02: Visual Polish — Transitions and Numeric Animations Summary

**Opacity fade transitions added to all collapsible section content blocks; .contentTransition(.numericText()) applied to 7 numeric Text views; all inline easeInOut animation duration literals replaced with MotionConstants references**

## Performance

- **Duration:** ~6 min
- **Started:** 2026-03-19T15:44:00Z
- **Completed:** 2026-03-19T15:50:00Z
- **Tasks:** 2
- **Files modified:** 6

## Accomplishments

- Added `.transition(.opacity)` to content blocks in TokenHealthSection, ProjectUsageSection, ActivityChartView (5 instances across 3 files)
- Added `.contentTransition(.numericText())` to 7 numeric Text views: usage bar percentage, health badge percentage, session counter, header cost/tokens in ProjectUsageSection, per-row cost/tokens in ProjectUsageSection
- Replaced 4 `withAnimation(.easeInOut(duration: 0.15))` with `MotionConstants.snappy` in TokenHealthSection
- Replaced 1 `withAnimation(.easeInOut(duration: 0.2))` with `MotionConstants.standard` in ProjectUsageSection
- Replaced 1 `withAnimation(.easeInOut(duration: 0.2))` with `MotionConstants.standard` in CollapsibleSectionHeader
- Replaced 3 `withAnimation(.easeInOut(duration: 0.2))` with `MotionConstants.standard` in UsagePopoverView (settings toggle, account switch, auto mode toggle)
- Replaced 2 `.animation(.easeInOut(duration: 0.15))` with `MotionConstants.snappy` in UsagePopoverView (metricModeRaw, showLogoutConfirm)
- 11 total `MotionConstants.` references now exist across views (up from 0 before this phase)

## Task Commits

Each task was committed atomically:

1. **Task 1: Add opacity transitions and numeric text animations** - `064b6c3` (feat)
2. **Task 2: Migrate remaining animation literals in CollapsibleSectionHeader and UsagePopoverView** - `63c0eac` (feat)

**Plan metadata:** (docs commit follows)

## Files Modified

- `AIBattery/Views/TokenHealthSection.swift` - VStack content block wrapped with .transition(.opacity); session counter + health badge get .contentTransition(.numericText()); 4 withAnimation() calls migrated to MotionConstants.snappy
- `AIBattery/Views/ProjectUsageSection.swift` - VStack content block wrapped with .transition(.opacity); 4 Text views get .contentTransition(.numericText()); 1 withAnimation() call migrated to MotionConstants.standard
- `AIBattery/Views/ActivityChartView.swift` - Chart VStack and insights VStack wrapped with .transition(.opacity); empty state VStack also gets .transition(.opacity)
- `AIBattery/Views/UsageBarsSection.swift` - Percentage Text gets .contentTransition(.numericText())
- `AIBattery/Views/CollapsibleSectionHeader.swift` - withAnimation() migrated to MotionConstants.standard
- `AIBattery/Views/UsagePopoverView.swift` - 5 animation literals migrated to MotionConstants (3x standard, 2x snappy)

## Decisions Made

- ActivityChartView `switch mode { ... }` block wrapped in `VStack` before receiving `.transition(.opacity)` — a `switch` is an expression, not a view type, and cannot directly receive SwiftUI modifiers. The single-child VStack is the conventional container.
- Empty state VStack in ActivityChartView also received `.transition(.opacity)` — consistent fade behavior whether content is empty or chart-filled.

## Deviations from Plan

None — plan executed exactly as written.

## Verification Results

- `swift build` passes with zero errors
- `contentTransition(.numericText())`: 7 matches across Views/ (requirement: >=7) — PASS
- `.transition(.opacity)` in target files: 5 matches (requirement: >=4) — PASS
- `MotionConstants.` across Views/: 11 matches (requirement: >=10) — PASS
- Zero `easeInOut(duration:)` literals in CollapsibleSectionHeader or UsagePopoverView — PASS

## Self-Check

- [x] All 6 modified files are committed
- [x] Task 1 commit `064b6c3` exists
- [x] Task 2 commit `63c0eac` exists
- [x] Build passes
