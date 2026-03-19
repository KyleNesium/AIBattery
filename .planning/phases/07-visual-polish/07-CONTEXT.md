# Phase 7: Visual Polish - Context

**Gathered:** 2026-03-19
**Status:** Ready for planning

<domain>
## Phase Boundary

Unify divider styling, add smooth expand/collapse transitions, and introduce metric value animations across all popover sections. All animations must be subtle, performant, and gated on panel visibility.

</domain>

<decisions>
## Implementation Decisions

### Divider & Header Consistency
- Unified divider style: `.opacity(0.3)` with `Spacing.tight` vertical padding — matches ActivityChartView which looks cleanest
- Rate Limit bars stay non-collapsible — they're always-visible primary indicators
- Collapsed summary values stay as-is (contextually useful) — only typography/color is standardized (already done in Phase 6)
- Extract a reusable `StyledDivider` view — single source of truth, replaces ~10 callsites

### Section Animations
- Expand/collapse content: `.opacity` transition on section content with 0.2s easeInOut — smooth fade, matches existing chevron timing
- Metric value changes: `contentTransition(.numericText())` on Text views showing numbers — SwiftUI native, smooth digit rolling
- Animation duration standard: 0.2s easeInOut for all section interactions (matches existing pattern)
- All new animations gated on panel visibility (popover open) — PG-01 prep for Phase 9

### Implementation Scope
- Central `MotionConstants` enum (or Animation extension) for durations/curves — single place to tune
- `numericText()` applied to all numeric Text views in popover: token counts, cost values, percentages, session counts
- Compile check + visual inspection for verification (animations are inherently visual)

### Claude's Discretion
- Exact file placement for MotionConstants (alongside Typography/Spacing or separate)
- Whether StyledDivider is a View struct or a ViewModifier
- Specific numericText() callsite selection (all numeric Text views, use judgment for edge cases)

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `CollapsibleSectionHeader` — shared component already used by 4 sections, chevron rotation at 0.2s easeInOut
- `Typography` enum (Phase 6) — all section headers use `Typography.sectionHeader`
- `Spacing` enum (Phase 6) — `Spacing.tight` (2pt) available for divider padding
- Existing `.transition(.opacity)` pattern in UsageBarsSection (celebration text swap)

### Established Patterns
- `withAnimation(.easeInOut(duration: 0.2))` — dominant animation pattern (6 callsites)
- `withAnimation(.easeInOut(duration: 0.15))` — snappier variant for nav gestures
- `.transition(.opacity)` — used in 4 places already
- `contentTransition(.numericText())` — SwiftUI built-in, requires macOS 14+ (project targets macOS 13+, need compatibility check)

### Integration Points
- Every view file with `Divider()` — ~10 callsites across 5 files
- All collapsible sections: TokenHealthSection, ProjectUsageSection, ActivityChartView (Insights)
- All numeric Text views in popover sections
- UsagePopoverView — main container, controls section visibility

</code_context>

<specifics>
## Specific Ideas

- `contentTransition(.numericText())` requires macOS 14+. If targeting macOS 13+, may need availability check or fallback.
- Existing dividers in SettingsRow use `.opacity(0.5)` — these should also standardize to 0.3 for consistency.
- The `.animation(.easeInOut(duration: 0.15), value: metricModeRaw)` in UsagePopoverView already scopes animation to metric mode changes — new animations should be similarly scoped to avoid interference.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>
