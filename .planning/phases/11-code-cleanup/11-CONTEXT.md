# Phase 11: Code Cleanup - Context

**Gathered:** 2026-03-20
**Status:** Ready for planning

<domain>
## Phase Boundary

Remove dead code from v1.11 (sectionPadding(), PopoverLoadingView), sync specs with v1.9.4 performance changes, and update README test coverage.

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion
All implementation choices are at Claude's discretion — pure cleanup phase:
- Remove unused `sectionPadding()` View extension from Spacing.swift
- Remove unused `PopoverLoadingView` struct from PopoverStateViews.swift
- Update spec/CONSTANTS.md with new MotionConstants values (0.15s/0.1s easeOut)
- Update spec/UI_SPEC.md for performance behavior changes
- Note: Phase 10 executor may have already updated README and some specs — check before duplicating

</decisions>

<code_context>
## Existing Code Insights

### Dead Code Identified
- `sectionPadding()` in Spacing.swift — defined but 0 callsites (views use explicit double-padding)
- `PopoverLoadingView` in PopoverStateViews.swift — defined but UsagePopoverView inlines simpler loading state

### Spec Drift
- CONSTANTS.md: MotionConstants may still show old 0.2s/0.15s values
- UI_SPEC.md: May not reflect frame resize debounce, activation reorder, GaugeBar component

### Integration Points
- Spacing.swift, PopoverStateViews.swift (dead code removal)
- spec/CONSTANTS.md, spec/UI_SPEC.md (spec sync)
- README.md (test coverage)

</code_context>

<specifics>
## Specific Ideas

No specific requirements — cleanup phase.

</specifics>

<deferred>
## Deferred Ideas

None.

</deferred>
