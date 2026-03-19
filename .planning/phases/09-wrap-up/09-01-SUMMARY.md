---
phase: 09-wrap-up
plan: 01
subsystem: docs
tags: [spec-sync, design-tokens, animation-audit]
dependency_graph:
  requires: [06-design-system, 07-visual-polish, 08-file-extraction]
  provides: [spec-sync-complete, pg-01-verified]
  affects: [spec/ARCHITECTURE.md, spec/CONSTANTS.md, spec/UI_SPEC.md]
tech_stack:
  added: []
  patterns: [spec-driven-workflow]
key_files:
  modified:
    - spec/ARCHITECTURE.md
    - spec/CONSTANTS.md
    - spec/UI_SPEC.md
decisions:
  - "Correct auto mode button spec to match code: static green styling (no repeatForever pulse)"
  - "PG-01 satisfied by SwiftUI view lifecycle gating — no code changes needed"
  - "Design Tokens section in CONSTANTS.md is additive — existing UI Layout and Animations tables retained"
metrics:
  duration: "8 min"
  completed: "2026-03-19T17:48:25Z"
  tasks_completed: 2
  files_modified: 3
---

# Phase 09 Plan 01: Spec Sync and Animation Audit Summary

Closed the spec-code gap opened by Phases 6-8 by updating all three spec files to reflect design token enums, extracted view files, and PG-01 animation safety audit.

## Tasks Completed

| Task | Description | Commit |
|------|-------------|--------|
| 1 | Update ARCHITECTURE.md and CONSTANTS.md with Phase 6-8 structural changes | 431b57c |
| 2 | Update UI_SPEC.md with design token references, auto mode correction, and PG-01 audit note | 623ee32 |

## What Was Built

**ARCHITECTURE.md** — Added three missing file entries to the project tree:
- `Typography.swift` in Utilities/ — named font style tokens (caseless enum namespace)
- `Spacing.swift` in Utilities/ — Spacing/Layout/MotionConstants enums + sectionPadding() View extension (co-located)
- `StyledDivider.swift` in Views/ — standardized 0.3-opacity divider with Spacing.tight vertical padding

**CONSTANTS.md** — Added a new `## Design Tokens` section documenting all four enum namespaces:
- Typography: 15 named font tokens from `Utilities/Typography.swift`
- Spacing: 6 spacing constants from `Utilities/Spacing.swift`
- Layout: 7 dimension constants from `Utilities/Spacing.swift`
- MotionConstants: 2 animation durations from `Utilities/Spacing.swift`
- Cross-reference notes added to UI Layout and Animations sections
- Animations table corrected: auto mode button is static green (not repeating pulse)

**UI_SPEC.md** — Four targeted amendments:
- New `## Design Tokens` subsection with all four enum namespaces and StyledDivider note
- Auto mode button description corrected: static green fill/stroke/shadow, no pulse, no repeating timer
- Animations subsection updated to reference MotionConstants tokens
- New `### Panel Visibility Safety (PG-01)` section documenting SwiftUI lifecycle gating

## Decisions Made

- **Auto mode pulse correction**: The spec described a `repeatForever` pulsing animation on the auto mode button, but the actual code (`MetricToggleView.swift`) uses static green styling. The spec was wrong — Phase 7 landed the green button without the pulse. Corrected spec to match reality.
- **PG-01 via lifecycle, not code**: All 13 animation sites in the popover are gated by SwiftUI's view hierarchy removal when the panel is hidden. No runtime gating logic is needed. Documented in spec with audit evidence.
- **Design Tokens section is additive**: Existing `## UI Layout` and `## Animations` numeric tables retained; new `## Design Tokens` section maps Swift enum names to those values. No duplication.

## Deviations from Plan

None — plan executed exactly as written. The `swift test` command failed with "no such module 'Testing'" as expected (known limitation: Swift Testing framework requires Xcode, not just Command Line Tools). This is a pre-existing constraint unrelated to spec-only changes.

## Success Criteria Verification

- CQ-02 satisfied: All three spec files reflect Phase 6-8 structural changes (design tokens, extracted views, new utilities)
- PG-01 satisfied: Animation safety audit documented in UI_SPEC.md with evidence that all animations are gated by SwiftUI view lifecycle
- No test regressions (spec-only changes, pre-existing test infrastructure constraint unchanged)
- Auto mode button spec matches actual code (static green, no pulse)

## Self-Check: PASSED

Files verified:
- spec/ARCHITECTURE.md: EXISTS, contains "Typography.swift", "Spacing.swift", "StyledDivider.swift"
- spec/CONSTANTS.md: EXISTS, contains "Design Tokens" section with "MotionConstants"
- spec/UI_SPEC.md: EXISTS, contains "Design Tokens", "MotionConstants", "StyledDivider", "PG-01", zero "repeatForever" matches

Commits verified:
- 431b57c: docs(09-01): update ARCHITECTURE.md and CONSTANTS.md with Phase 6-8 structural changes
- 623ee32: docs(09-01): update UI_SPEC.md with design tokens, StyledDivider, auto mode correction, and PG-01 audit
