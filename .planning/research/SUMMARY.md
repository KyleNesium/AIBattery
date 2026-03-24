# Project Research Summary

**Project:** AIBattery v1.14 Visual Polish — Chart Label & Spacing Fixes
**Domain:** Swift Charts axis label customization, hourly data persistence, macOS popover layout spacing
**Researched:** 2026-03-24
**Confidence:** HIGH

## Executive Summary

This milestone is a scoped set of four targeted fixes on a shipping, feature-complete macOS menu bar app. No new dependencies, no architectural changes, no data model redesigns. All four issues are presentation-layer or data-loading bugs rooted in specific, identifiable code paths. The stack is already validated; this research purely informs which APIs to use and which anti-patterns to avoid across three Swift files plus one design token audit.

The recommended approach is to fix in dependency order: the false empty state fix is the highest user-impact change and touches only one computed property; the two axis label fixes are literal array and stride changes in the same file (`InsightsCharts.swift`); the spacing fix requires visual inspection before coding but is confirmed to be a one-line padding token change. Each fix is independently releasable. Total code delta across all four fixes is expected to be under 20 changed lines — the research effort is disproportionate to the implementation effort, which reflects the value of getting subtle Swift Charts behaviors exactly right the first time.

The primary risk is the false empty state fix. A naive one-liner (`if todayHourCounts.isEmpty { return false }`) solves the visible symptom but does not address the underlying race condition — `todayHourCounts` starts empty on every cold start and populates only after JSONL scan completes. The pitfalls research flags that the `dataFingerprint` sum-collision pattern can mask the fix: if the fix is not verified with a quit-and-relaunch scenario, it may appear to work in development but regress after shipping. The correct fix uses `dailyActivity` as a loading signal: if today has entries in the stats cache but `todayHourCounts` is still empty, suppress the empty state rather than displaying "No activity."

## Key Findings

### Recommended Stack

No new stack additions. All fixes use APIs already in the codebase: Swift Charts (`AxisMarks`, `AxisMarkValues.stride`, `chartXAxis`, `chartXScale`), SwiftUI layout (`padding`), and existing design tokens (`Typography.decorativeIcon`, `Spacing.section`). The existing `DateFormatters.shortMonth` and `formatHourLabel` helpers require no changes.

**Core APIs in use:**
- `AxisMarkValues.stride(by: Int)` — deterministic tick placement on Int axes (24H chart); avoids the irregular manual array `[0, 4, 8, 12, 16, 20, 23]`
- `AxisMarkValues.stride(by: .month, count: 1)` — calendar-aligned tick placement on Date axes (12M chart); suppresses boundary duplicates caused by passing raw Date arrays
- `.chartXScale(domain:)` — suppresses Swift Charts auto domain padding that shifts tick positions and clips edge labels on continuous axes
- `Typography.decorativeIcon` (9pt) — matches Y-axis token; fits 4-label and quarterly configurations at 50pt chart height without violating the monoTiny floor
- `Spacing.section` (8pt) — the normalizing token for MetricToggleView bottom padding (currently using `Spacing.gap` at 6pt, causing 2pt asymmetry)

### Expected Features

This milestone has no feature additions — it is a bug fix release. The "features" framing maps to the four issues being closed.

**Must fix (table stakes — chart usability broken without these):**
- 12M month labels readable — 12 squished labels at 275pt width are worse than 4 clear quarterly ones; quarterly stride is the established compact chart pattern
- 24H hour labels evenly spaced — irregular final gap at offset 20→23 reads as broken data; `[0, 6, 12, 18]` uses midnight/6am/noon/6pm as natural human time anchors
- 24H false "No activity" after restart — trust-destroying bug; user sees empty chart despite having activity; fix must survive a quit-and-relaunch verification scenario
- Rate limit section vertical padding — cosmetic inconsistency from `MetricToggleView` bottom padding using `Spacing.gap` (6pt) instead of `Spacing.section` (8pt), creating uneven inter-section gaps

**Not in scope (confirmed):**
- Y-axis label changes — `sharedYAxis` with `desiredCount: 3` works correctly
- Tooltip changes — hover tooltips work correctly
- Data model changes — `HourlyPoint`, `MonthlyPoint`, `DailyPoint` structs unchanged
- Label animation or transitions
- Any new SPM dependency

### Architecture Approach

Each of the four fixes lives in an isolated file with no shared code path. The fix surfaces are narrow: `InsightsCharts.swift` (axis mark configs), `ActivityChartView.swift` (isEmpty computed var), and `UsageBarsSection.swift` plus `MetricToggleView.swift` (padding token). The data flow for the false empty state is fully traced — `JSONL → SessionLogReader → UsageAggregator.aggregate() → UsageSnapshot.todayHourCounts → InsightsView.isEmpty` — and the bug exists at the final presentation step, not in the aggregation logic.

**Components touched per fix:**
1. `InsightsCharts.swift` — `monthlyChart` and `hourlyChart` axis mark configurations (two independent changes in the same file)
2. `ActivityChartView.swift` — `isEmpty` computed var, `.hourly` case only; add `dailyActivity` loading signal guard
3. `MetricToggleView.swift` — one-line padding change: `.padding(.bottom, Spacing.gap)` → `.padding(.bottom, Spacing.section)`
4. `spec/CONSTANTS.md` and `spec/UI_SPEC.md` — spec sync required by project convention after all fixes are confirmed

### Critical Pitfalls

1. **`AxisMarks(values:)` does not control tick spacing — domain padding does** — passing explicit `Date` values without `.chartXScale(domain:)` lets Swift Charts inflate the domain with auto edge padding, shifting tick positions and clipping edge labels. Always pair explicit axis values with a pinned domain on continuous axes.

2. **`isEmpty` empty-dict vs all-zero ambiguity causes false empty state** — Swift's `allSatisfy` returns `true` on an empty collection, so an empty `todayHourCounts` and an all-zero `todayHourCounts` are indistinguishable. The fix must distinguish "data not yet loaded" from "confirmed zero activity" using `dailyActivity` as a corroborating signal.

3. **`dataFingerprint` sum collision can mask the fix** — `todayHourCounts.values.reduce(0, +)` equals 0 both for an empty dict and for the pre-JSONL-scan loading state. Verify the chart actually updates after the first JSONL scan completes — not just that the false empty state is suppressed on first render.

4. **`Spacing.section` is a global token used in 8+ places** — do not change `Spacing.section` to fix rate limit bar padding; that would narrow spacing globally across all sections. The root cause is `MetricToggleView`'s bottom padding using `Spacing.gap` (6pt) instead of `Spacing.section` (8pt). One-line targeted fix — no token value changes.

5. **Font size floor must not drop below `Typography.monoTiny`** — the minimum font size was set by a deliberate v1.11 accessibility audit. Reducing font below this floor to fit 12 month labels violates that audit. Reducing label count (quarterly stride) is the correct fix.

## Implications for Roadmap

Four single-issue phases in dependency order, each independently verifiable:

### Phase 1: Fix 24H False Empty State
**Rationale:** Highest user impact and most deceptive bug — users believe data is lost. Fix first so it has the most test time before shipping. One `isEmpty` guard change in `ActivityChartView.swift`; uses `dailyActivity` as a loading signal to distinguish "loading" from "truly no data."
**Delivers:** 24H chart shows a zero-filled flat chart (not "No activity" message) during the ~2s JSONL scan window on cold start, after app update, and after Sparkle update.
**Addresses:** FEATURES.md "No false empty state" (table stakes), ARCHITECTURE.md Option A fix path
**Avoids:** Pitfall 2 (empty dict vs all-zero), Pitfall 3 (dataFingerprint sum collision)
**Verification:** Quit app mid-day with activity, relaunch without writing new JSONL, open 24H chart — must show a chart (even flat), not "No activity."

### Phase 2: Fix 24H Axis Label Spacing
**Rationale:** Same file as the monthly chart fix (`InsightsCharts.swift`) — batch both axis changes together after the data-layer fix is confirmed. Pure cosmetic change, zero regression risk. One array literal replacement.
**Delivers:** 24H chart shows 4 evenly-spaced hour labels at offsets 0, 6, 12, 18 (midnight/6am/noon/6pm). No irregular trailing gap.
**Addresses:** FEATURES.md "Evenly-spaced axis labels" (table stakes), FEATURES.md "Hour labels show recognizable time-of-day"
**Avoids:** Pitfall 4 (irregular 20→23 gap)
**Verification:** Equal pixel gaps between all 4 adjacent label pairs visible in a screenshot of the running popover.

### Phase 3: Fix 12M Month Label Collision
**Rationale:** Same file as Phase 2 (`InsightsCharts.swift`) — make both chart fixes in one pass. Requires confirming domain-pinning (`.chartXScale`) in addition to the stride change; doing it after Phase 2 means the file already has a confirmed working axis pattern to reference.
**Delivers:** 12M chart shows 4 quarterly labels using `Typography.decorativeIcon` (9pt), no clipping at 275pt popover width.
**Addresses:** FEATURES.md "No label collision on 12-month chart" (table stakes), FEATURES.md "Labels that survive chart resize"
**Avoids:** Pitfall 1 (domain auto-padding clips edge labels), Pitfall 6 (font size below monoTiny floor)
**Verification:** Screenshot running popover at 275pt — all visible labels readable, none clipped. Xcode canvas is insufficient; running app is required.

### Phase 4: Fix Rate Limit Section Vertical Padding
**Rationale:** Last because it requires visual inspection before coding — confirm `StyledDivider.swift` adds no hidden vertical padding, then verify the gap asymmetry source before writing any code. STACK research already identifies root cause (MetricToggleView bottom padding uses `Spacing.gap` not `Spacing.section`); this is a one-line fix once confirmed.
**Delivers:** Uniform 18pt gap between all adjacent section content rows (8pt bottom + 2pt divider + 8pt top).
**Addresses:** FEATURES.md "Fix rate limit vertical spacing" (P1)
**Avoids:** Pitfall 5 (divider and section padding compound asymmetrically), anti-pattern of changing global `Spacing.section` token
**Verification:** Test all three `orderedModes` orderings — consistent visual gap regardless of section order; `StyledDivider` confirmed zero vertical padding.

### Phase Ordering Rationale

- Data-layer fix (Phase 1) before cosmetic fixes (Phases 2–3) — if the false empty state fix introduces a regression, it is caught before axis changes add noise to debugging
- Phases 2 and 3 batched against the same file — reduces commit churn on `InsightsCharts.swift` and allows both to be confirmed in a single visual review session
- Phase 4 last — requires visual inspection that cannot be automated; isolating it makes the inspection unambiguous against a stable baseline

### Research Flags

All four phases have standard, well-documented patterns. No phase requires `/gsd:research-phase` during planning.

- **Phase 1:** False empty state fix is fully diagnosed in ARCHITECTURE.md (Option A); STACK.md confirms the `dailyActivity` fallback signal; APIs are in existing import set
- **Phase 2:** Single array literal change; axis values and stride API confirmed in STACK.md and ARCHITECTURE.md
- **Phase 3:** Stride API and `.chartXScale` domain-pinning confirmed in STACK.md; quarterly label pattern confirmed as industry standard in FEATURES.md
- **Phase 4:** Root cause confirmed by STACK.md padding audit; `StyledDivider` source read is a 30-second verification, not research

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All APIs verified against live codebase and Apple Developer Docs + WWDC22; no external dependencies needed |
| Features | HIGH | Fixes are enumerated defects with identified root causes; no feature design decisions required |
| Architecture | HIGH | Derived entirely from live codebase inspection — specific line numbers, file paths, and data flow traced directly |
| Pitfalls | HIGH | Every pitfall grounded in direct code inspection (line numbers cited) or officially documented Swift Charts behavior |

**Overall confidence:** HIGH

### Gaps to Address

- **`StyledDivider` vertical padding** — PITFALLS.md flags that `StyledDivider` may have non-zero vertical padding but this was not confirmed in research. Read `StyledDivider.swift` at the start of Phase 4 before writing any code. If the divider has internal padding, the gap math changes.
- **`dataFingerprint` update after Phase 1 fix** — the STACK.md fix uses `dailyActivity` as a loading signal (not UserDefaults persistence), which preserves the existing fingerprint behavior. After implementing Phase 1, explicitly verify the chart updates when `todayHourCounts` populates from JSONL — not just that the false empty state is suppressed on first render.
- **Monthly chart domain pinning interaction at 275pt** — the `.chartXScale` approach has not been tested against the live popover at exactly 275pt. The running-app screenshot check in Phase 3 verification is mandatory; Xcode canvas renders at a different layout width and is not a reliable proxy.

## Sources

### Primary (HIGH confidence)
- Codebase: `AIBattery/Views/InsightsCharts.swift` — hardcoded `[0, 4, 8, 12, 16, 20, 23]`, `AxisMarks(values: dates)` without domain pinning
- Codebase: `AIBattery/Views/ActivityChartView.swift` — `isEmpty` computed var, `dataFingerprint` implementation
- Codebase: `AIBattery/Services/UsageAggregator.swift` — `todayHourCounts` built from `todayEntries` only, no persistence
- Codebase: `AIBattery/ViewModels/UsageViewModel.swift` — fast-path cached snapshot fires before JSONL scan completes
- Codebase: `AIBattery/Views/UsageBarsSection.swift` and `MetricToggleView.swift` — padding structure for rate limit sections
- Codebase: `AIBattery/Utilities/Spacing.swift` — `Spacing.section = 8pt`, `Spacing.gap = 6pt`
- Apple Developer Documentation — [Customizing axes in Swift Charts](https://developer.apple.com/documentation/charts/customizing-axes-in-swift-charts)
- WWDC22 "Swift Charts: Raise the bar" — `AxisMarkValues.stride` by calendar component

### Secondary (MEDIUM confidence)
- Apple Developer Forums — Swift Charts Int-axis stride behavior confirmed by community
- [Mastering charts in SwiftUI: Customizations — Swift with Majid](https://swiftwithmajid.com/2023/02/15/mastering-charts-in-swiftui-customizations/) — `AxisMarkBuilder` closure API
- [An Adventure with Swift Charts — mobile.blog](https://mobile.blog/2022/07/04/an-adventure-with-swift-charts/) — compact chart label count patterns (quarterly / 5-hour intervals)

### Tertiary (reference)
- [Yellowfin BI — Chart Axis Best Practices](https://www.yellowfinbi.com/best-practice-guide/charts-visualizations/chart-axis-best-practices) — "don't label every tick mark" principle

---
*Research completed: 2026-03-24*
*Ready for roadmap: yes*
