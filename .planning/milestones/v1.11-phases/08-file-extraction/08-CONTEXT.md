# Phase 8: File Extraction - Context

**Gathered:** 2026-03-19
**Status:** Ready for planning

<domain>
## Phase Boundary

Split UsagePopoverView (666 lines) and ActivityChartView (711 lines) into focused, composable sub-views that stay under 400 lines each. Pure structural refactoring — no behavioral changes.

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion
All implementation choices are at Claude's discretion — pure infrastructure phase. Key considerations:
- Identify natural section boundaries in each large file
- Extract sub-views as separate files with descriptive names
- Preserve exact existing behavior (no functional changes)
- Each resulting file must be under 400 lines
- Follow existing file naming convention (one primary type per file, filename matches type name)

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `CollapsibleSectionHeader` — already extracted as shared component
- `StyledDivider` — already extracted as shared component (Phase 7)
- `Typography`, `Spacing`, `Layout` enums — all styling centralized (Phase 6)
- `TokenHealthSection`, `ProjectUsageSection`, `UsageBarsSection` — existing extracted sections

### Established Patterns
- Sub-views receive data via init parameters (no EnvironmentObject)
- One primary type per file, filename matches type name
- Views in `AIBattery/Views/` directory

### Integration Points
- `UsagePopoverView.swift` (666 lines) — main popover container with header, metric toggle, settings, footer, account picker
- `ActivityChartView.swift` (711 lines) — hourly/daily/monthly charts, trend section, cost section, insight rows

</code_context>

<specifics>
## Specific Ideas

No specific requirements — infrastructure phase.

</specifics>

<deferred>
## Deferred Ideas

None.

</deferred>
