# Phase 13: Chart & Data Fixes - Context

**Gathered:** 2026-03-24
**Status:** Ready for planning

<domain>
## Phase Boundary

Fix three bugs in the Insights activity charts: 24H false empty state after app restart, 24H uneven hour label spacing, and 12M month label collision. All fixes are in InsightsCharts.swift and ActivityChartView.swift.

</domain>

<decisions>
## Implementation Decisions

### Chart Label Strategy
- 24H chart: Replace `[0, 4, 8, 12, 16, 20, 23]` with `[0, 6, 12, 18]` — even 6h intervals mapping to clock anchors (midnight, 6am, noon, 6pm)
- 24H labels use `HH:00` format (e.g. "00:00", "06:00", "12:00", "18:00") — user requested full time display
- 12M chart: Show quarterly month labels plus always include current month (4-5 labels total) — user requires current month visibility
- 12M labels keep `Typography.monoTiny` (10pt mono) — fewer labels removes the cramming problem without needing smaller font

### False Empty State Fix
- Guard `isEmpty` with `dailyActivity` check — if daily has messages but hourCounts is empty dict, return false (not truly empty, just loading)
- Show zero-filled chart while loading — chart appears immediately with 24 bars at 0, fills when hourCounts data arrives via JSONL scan
- No fingerprint change needed — existing `dataFingerprint` already triggers refresh when `todayHourCounts` populates

### Claude's Discretion
- Implementation order within the phase
- Whether to add `.chartXScale(domain:)` to monthly chart for domain pinning (research suggests yes)

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `ActivityChartData.hourlyData(from:)` — already handles empty input correctly (returns 24 zero-count points)
- `InsightsView.formatHourLabel(_:)` — returns zero-padded hour string, needs `:00` suffix for new format
- `InsightsView.monthAbbrev(_:)` — returns 3-letter month abbreviation via DateFormatters.shortMonth
- `Typography.monoTiny` / `Typography.decorativeIcon` — existing font tokens

### Established Patterns
- Chart axis marks use `AxisMarks(values:)` with explicit value arrays
- Shared `sharedYAxis` for consistent Y-axis across all chart modes
- `cachedMonthly` / `cachedHourly` computed via fingerprint-gated refresh

### Integration Points
- `InsightsCharts.swift` — hourlyChart and monthlyChart computed properties (primary change surface)
- `ActivityChartView.swift` — `isEmpty` computed property (false empty state fix)
- `InsightsRowsAndHover.swift` — `formatHourLabel` helper (may need `HH:00` variant)

</code_context>

<specifics>
## Specific Ideas

- User explicitly requested `HH:00` full time format for 24H labels (not just hour numbers)
- User explicitly requested current month always visible in 12M chart
- Research identified missing `.chartXScale(domain:)` on monthly chart as contributing to label clipping

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>
