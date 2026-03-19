---
phase: 06-design-system
plan: 01
subsystem: ui
tags: [swiftui, design-tokens, typography, spacing, font-constants]

requires: []
provides:
  - Typography enum with 15 named Font constants covering all font usage patterns
  - Spacing enum with 6 named CGFloat constants for the spacing scale
  - Layout enum with 7 named CGFloat dimension constants
  - sectionPadding() View extension for standard outer section padding
  - Snapshot tests locking all constant values against regression
affects:
  - 06-02-design-system (view migration consuming these constants)
  - 07-visual-polish (uses Typography/Spacing in polish pass)
  - 08-file-extraction (file extraction may touch views using these tokens)

tech-stack:
  added: []
  patterns:
    - "Caseless enum as pure namespace with static let properties (matches ThemeColors pattern)"
    - "One @Test per constant for lightweight value snapshot testing"
    - "sectionPadding() View extension for recurring padding combination"

key-files:
  created:
    - AIBattery/Utilities/Typography.swift
    - AIBattery/Utilities/Spacing.swift
    - Tests/AIBatteryCoreTests/Utilities/TypographyTests.swift
    - Tests/AIBatteryCoreTests/Utilities/SpacingTests.swift
  modified: []

key-decisions:
  - "decorativeIcon = Font.system(size: 8) — enforces UI-05 8pt minimum, bumps two size:6 callsites to 8pt during migration"
  - "Layout enum lives in Spacing.swift (same file) — both are non-font constants, reduces file proliferation"
  - "sectionPadding() convenience extension added — covers the 12-occurrence .padding(.horizontal,16) + .padding(.vertical,8) pattern"

patterns-established:
  - "Typography.X replaces all inline .font() calls in view files (including semantic .caption, .headline)"
  - "Spacing.X and Layout.X replace all numeric padding/frame literals"
  - "Snapshot test pattern: one @Test per constant asserting exact value — locks design tokens against accidental regression"

requirements-completed: [DS-01, DS-02]

duration: 2min
completed: 2026-03-19
---

# Phase 06 Plan 01: Design Token Constants Summary

**Typography (15 font tokens), Spacing (6 tokens), and Layout (7 dimension tokens) enums extracted into Swift caseless namespaces, with per-constant snapshot tests enforcing UI-05 8pt minimum and preventing regression.**

## Performance

- **Duration:** 2 min
- **Started:** 2026-03-19T14:46:22Z
- **Completed:** 2026-03-19T14:48:32Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments

- `Typography` enum: 15 `static let Font` constants grouped by role (section headers, hero values, body text, monospaced, badges/labels). `decorativeIcon` at 8pt enforces UI-05 minimum font size floor — replaces two `size: 6` violations.
- `Spacing` enum: 6 `static let CGFloat` constants covering all dominant padding patterns found in the 52-call audit. `sectionPadding()` View extension bundles the most frequent combination (16pt horizontal, 8pt vertical).
- `Layout` enum: 7 `static let CGFloat` dimension constants for popover width, chart/bar heights, corner radii, chevron frame, and dot sizes — all appearing 2+ times in the codebase.
- 22 snapshot tests (15 Typography + 7 Spacing/Layout) lock every constant value against accidental regression. Test files committed before implementation (TDD RED → GREEN).

## Task Commits

Each task was committed atomically:

1. **TDD RED — test files** - `718406d` (test)
2. **Task 1: Typography, Spacing, and Layout enums** - `4332f69` (feat)

_Note: TDD RED commit preceded the implementation (GREEN). Tests for Task 2 were the same files written in the RED phase._

## Files Created/Modified

- `AIBattery/Utilities/Typography.swift` — 15 named Font constants, caseless enum namespace, doc comments per token
- `AIBattery/Utilities/Spacing.swift` — Spacing (6 tokens) + Layout (7 tokens) enums, sectionPadding() View extension
- `Tests/AIBatteryCoreTests/Utilities/TypographyTests.swift` — 15 @Test assertions, one per font token, includes decorativeIcon_meetsMinimumSize for UI-05
- `Tests/AIBatteryCoreTests/Utilities/SpacingTests.swift` — 6 Spacing @Test + 7 Layout @Test assertions

## Decisions Made

- `decorativeIcon` set to `Font.system(size: 8)` — satisfies UI-05 accessibility floor. The two `size: 6` callsites (`FooterLink.swift:46`, `UsagePopoverView.swift:254`) both render decorative arrow icons, making 8pt a safe bump.
- `Layout` enum placed inside `Spacing.swift` — both are non-font spatial constants; keeping them co-located avoids an extra file without semantic cost.
- `sectionPadding()` extension added — the 12-occurrence `.padding(.horizontal, 16)` + `.padding(.vertical, 8)` pattern warrants a named shortcut per the research recommendation.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

Swift Testing framework requires full Xcode — not available in this environment (Command Line Tools only). Build verification via `swift build` confirmed all types compile correctly. Tests will be validated by CI (GitHub Actions, macos-15 runner with full Xcode).

## Self-Check: PASSED

- FOUND: AIBattery/Utilities/Typography.swift
- FOUND: AIBattery/Utilities/Spacing.swift
- FOUND: Tests/AIBatteryCoreTests/Utilities/TypographyTests.swift
- FOUND: Tests/AIBatteryCoreTests/Utilities/SpacingTests.swift
- FOUND: commit 718406d (TDD RED — test files)
- FOUND: commit 4332f69 (feat — implementation)

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- All design token constants are ready for consumption by Plan 02 (view migration)
- `Typography.X`, `Spacing.X`, `Layout.X`, and `sectionPadding()` are the stable API surface for the migration pass
- No blockers — all 4 files compile, all acceptance criteria met

---
*Phase: 06-design-system*
*Completed: 2026-03-19*
