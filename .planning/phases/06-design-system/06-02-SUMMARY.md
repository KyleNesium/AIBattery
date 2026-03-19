---
phase: 06-design-system
plan: 02
subsystem: ui
tags: [swiftui, design-tokens, typography, spacing, font-migration, view-migration]

requires:
  - 06-01 (Typography, Spacing, Layout enums)
provides:
  - All 16 view files migrated to Typography, Spacing, and Layout constants
  - Zero inline font/spacing literals in view files (except 3 documented one-offs)
  - UI-05 fixed: two size:6 violations bumped to Typography.decorativeIcon (8pt)
  - DS-03 fixed: all outer section padding unified to Spacing.sectionHorizontal + Spacing.section
affects:
  - 07-visual-polish (polish pass now consumes Typography/Spacing tokens)
  - 08-file-extraction (extraction pass operates on files using design tokens)

tech-stack:
  added: []
  patterns:
    - "Typography.X replaces all inline .font() calls in view files (semantic and explicit)"
    - "Spacing.X and Layout.X replace all numeric padding/frame literals"
    - "sectionPadding() View extension used where applicable"
    - "One-offs (size:28, size:13, size:9+heavy+rounded, size:11+semibold+monospaced) kept inline per plan"

key-files:
  created: []
  modified:
    - AIBattery/Views/UsagePopoverView.swift
    - AIBattery/Views/ActivityChartView.swift
    - AIBattery/Views/AuthView.swift
    - AIBattery/Views/ProjectUsageSection.swift
    - AIBattery/Views/TokenHealthSection.swift
    - AIBattery/Views/UsageBarsSection.swift
    - AIBattery/Views/FooterLink.swift
    - AIBattery/Views/CollapsibleSectionHeader.swift
    - AIBattery/Views/TutorialOverlay.swift
    - AIBattery/Views/RefreshButton.swift
    - AIBattery/Views/Settings/SettingsRow.swift
    - AIBattery/Views/Settings/AlertSettingsSection.swift
    - AIBattery/Views/Settings/DisplaySettingsSection.swift
    - AIBattery/Views/Settings/RefreshSettingsSection.swift
    - AIBattery/Views/Settings/LaunchAtLoginSection.swift
    - AIBattery/Views/StatusBarManager.swift

key-decisions:
  - "CopyableText.swift clipboard icon (.system(size:9)) left unchanged — plan explicitly excluded this file"
  - "trendRowTop symbol text (.system(size:11, weight:.semibold, design:.monospaced)) kept inline — no matching token, true one-off"
  - "ActivityChartView size:10+semibold+monospaced trend symbol kept inline — unique one-off without a named token"
  - "DS-03: .padding(.vertical, 6) outer section padding bumped to Spacing.section (8pt) in UsagePopoverView header/footer/metricToggle and SettingsRow"

requirements-completed: [DS-01, DS-02, DS-03, UI-05]

duration: 16min
completed: 2026-03-19
---

# Phase 06 Plan 02: View Migration Summary

**All 16 view files migrated from inline font/spacing literals to Typography, Spacing, and Layout constants in a single atomic pass. Two 6pt font violations fixed to 8pt (UI-05). All outer section padding unified to 16pt/8pt (DS-03). Build passes, zero residual literals.**

## Performance

- **Duration:** 16 min
- **Started:** 2026-03-19T14:50:00Z
- **Completed:** 2026-03-19T15:06:00Z
- **Tasks:** 2
- **Files modified:** 16

## Accomplishments

- Migrated 148+ inline `.font()` calls to Typography constants across 16 view files. Every semantic font (`.caption`, `.caption2`, `.headline`, `.subheadline`) and explicit size call now goes through the `Typography` namespace.
- Migrated 52+ inline `.padding()` and `.frame()` calls to `Spacing.X` and `Layout.X` constants. `.padding(.horizontal, 16)`, `.padding(.vertical, 8)`, `.padding(24)`, bar heights (8pt), chart heights (50pt), popover widths (275pt), dot sizes, and chevron frames all tokenized.
- Fixed UI-05 violations: `FooterLink.swift` and `UsagePopoverView.swift` both had `Image(systemName: "arrow.up.right").font(.system(size: 6))` — both now use `Typography.decorativeIcon` (8pt minimum).
- DS-03 uniformity: `UsagePopoverView` header/footer/metricToggle sections and `SettingsRow` were using `.padding(.vertical, 6)` (inconsistent with the 8pt standard). All bumped to `Spacing.section` (8pt).
- Build verified clean: `swift build` passes with zero errors.
- Residual audit confirmed zero: no bare `.font(.caption)`, `.font(.caption2)`, `.font(.headline)`, `.font(.subheadline)`, `padding(.horizontal, 16)`, `padding(.vertical, 8)`, or `size: 6` remain in view files.

## Task Commits

1. **Task 1: Migrate all view files** - `e67e677` (feat)
   - 16 files changed, 190 insertions, 189 deletions
2. **Task 2: Verification** — no separate commit (all fixes made in Task 1)

## Files Modified

| File | Key Changes |
|------|-------------|
| `UsagePopoverView.swift` | 35+ Typography/Spacing/Layout tokens; UI-05 fix (decorativeIcon); DS-03 outer padding bumped |
| `ActivityChartView.swift` | 22+ tokens; chart height Layout.chartHeight; tooltip/axis font tokens |
| `AuthView.swift` | 16+ tokens; .padding(16) → Spacing.sectionHorizontal; .frame(275) → Layout.popoverWidth |
| `ProjectUsageSection.swift` | 13+ tokens; monoValueMedium for header token total |
| `TokenHealthSection.swift` | 9+ tokens; bar/dot Layout constants; session info caption tokens |
| `UsageBarsSection.swift` | 12+ tokens; bar height/radius Layout constants; binding badge badgeLabel |
| `FooterLink.swift` | UI-05 critical fix: size:6 → Typography.decorativeIcon |
| `CollapsibleSectionHeader.swift` | chevronIcon + sectionHeader tokens |
| `TutorialOverlay.swift` | .padding(24) → Spacing.overlay; title/caption tokens |
| `RefreshButton.swift` | monoTiny for icon |
| `Settings/SettingsRow.swift` | DS-03: .padding(.vertical, 6) → Spacing.section; caption tokens |
| `Settings/AlertSettingsSection.swift` | caption + monoCaption tokens |
| `Settings/DisplaySettingsSection.swift` | caption + monoCaption tokens |
| `Settings/RefreshSettingsSection.swift` | caption + monoCaption + decorativeIcon for slider marks |
| `Settings/LaunchAtLoginSection.swift` | caption tokens |
| `StatusBarManager.swift` | Layout.popoverWidth for PopoverContentView frame |

## Decisions Made

- `CopyableText.swift` excluded per plan — the `.font(.system(size: 9))` is an internal clipboard icon overlay, not a parameter pass-through, but the plan explicitly said DO NOT MODIFY.
- `ActivityChartView` trend symbol text (size:11+semibold+monospaced) kept inline — no matching Typography token; designated a one-off in the research's open questions.
- DS-03 bump was applied to all four previously-inconsistent padding sites (UsagePopoverView: header, footer, metricToggle + SettingsRow). Inner VStack spacing retained as local constants.

## Deviations from Plan

None — plan executed exactly as written.

## Self-Check: PASSED

- Commit e67e677 exists: `feat(06-02): migrate all view files to Typography, Spacing, and Layout constants`
- `grep -rn '\.font(\.system(size: 6)' AIBattery/Views/` → 0 results (UI-05)
- `grep -rn '\.font(\.caption2)' AIBattery/Views/` → 0 results
- `grep -rn '\.font(\.caption)' AIBattery/Views/` → 0 results
- `grep -rn 'padding(.horizontal, 16)' AIBattery/Views/` → 0 results
- `grep -rn 'Typography\.' AIBattery/Views/UsagePopoverView.swift` → 35 results
- `grep -rn 'Typography\.decorativeIcon' AIBattery/Views/FooterLink.swift` → 1 result
- `grep -rn 'Typography\.decorativeIcon' AIBattery/Views/UsagePopoverView.swift` → 1 result
- `swift build` → Build complete (zero errors)

## User Setup Required

None.

## Next Phase Readiness

- Design system adoption is complete across all view files
- Phase 07 (visual polish) and Phase 08 (file extraction) can now consume `Typography.X`, `Spacing.X`, and `Layout.X` as stable tokens
- No blockers — all 16 files compile, all acceptance criteria met

---
*Phase: 06-design-system*
*Completed: 2026-03-19*
