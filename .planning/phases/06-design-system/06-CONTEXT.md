# Phase 6: Design System - Context

**Gathered:** 2026-03-19
**Status:** Ready for planning

<domain>
## Phase Boundary

Establish a centralized design token system (typography, spacing, layout) that replaces all inline font and spacing literals across the popover UI. This phase creates the foundation that Phase 7 (visual polish) and Phase 8 (file extraction) depend on.

</domain>

<decisions>
## Implementation Decisions

### Typography Scale
- Static `Font` properties on a `Typography` enum (e.g., `Typography.sectionHeader`) — matches ThemeColors pattern, grep-friendly
- ~8-10 named styles covering actual usage: heroTitle, sectionHeader, bodyLabel, caption, tinyLabel, monoValue, monoCaption, badgeLabel, buttonLabel
- Minimum font size is 8pt — the two 6pt instances (FooterLink superscript, UsagePopoverView badge) must be bumped
- File location: `AIBattery/Utilities/Typography.swift` alongside ThemeColors.swift

### Spacing Scale
- Enum `Spacing` with static `CGFloat` properties (e.g., `Spacing.section`, `Spacing.gap`) — type-safe namespace
- ~6 tokens based on actual usage: `tight` (2), `small` (4), `gap` (6), `section` (8), `sectionHorizontal` (16), `overlay` (24)
- Frame dimensions (chart height: 50, bar height: 8, popover width: 275) extracted to a separate `Layout` enum in the same file
- File location: `AIBattery/Utilities/Spacing.swift` (Spacing + Layout enums)

### Migration Strategy
- One-pass migration across all views — ~120 font calls and ~50 spacing calls across ~15 files; small enough for atomic change
- Semantic SwiftUI fonts (.caption, .headline) also replaced with Typography constants — entire app goes through one system
- Consistent outer padding via `Spacing.sectionHorizontal` pattern applied uniformly to all popover sections (DS-03)
- Compile verification + unit tests that snapshot constant values to prevent regression

### Claude's Discretion
- Exact naming of each typography/spacing token (as long as they're descriptive and consistent)
- Internal organization within Typography.swift and Spacing.swift (grouping, comments)
- Whether to add any convenience View extensions for common padding patterns

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `ThemeColors.swift` — established pattern for design constants (static properties on enum, adaptive light/dark)
- Existing semantic fonts in use: `.headline`, `.caption`, `.caption2`, `.subheadline` — all to be wrapped
- `spec/UI_SPEC.md` — documents semantic font roles (reference for naming)
- `spec/CONSTANTS.md` — existing constants reference (add design tokens here after)

### Established Patterns
- Enums with static properties for constants (ThemeColors)
- `.font()` modifier on Text views (standard SwiftUI)
- `.padding(.horizontal, 16)` is the de facto section horizontal standard (12 uses)
- `.padding(.vertical, 8)` and `.padding(.vertical, 6)` are the two common vertical patterns
- Monospaced fonts use `.system(..., design: .monospaced)` — 11+ instances

### Integration Points
- Every view file in `AIBattery/Views/` — font and spacing calls to migrate
- `spec/CONSTANTS.md` — needs design token additions after implementation
- ThemeColors.swift — sibling file, same Utilities directory

</code_context>

<specifics>
## Specific Ideas

No specific requirements — standard design system extraction following established ThemeColors pattern.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>
