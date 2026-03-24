---
phase: 13-chart-data-fixes
verified: 2026-03-24T10:00:00Z
status: gaps_found
score: 6/7 must-haves verified
gaps:
  - truth: "12M chart x-axis shows 4-5 labels (quarterly + current month) with no overlap at 275pt width"
    status: partial
    reason: "quarterlyLabelDates is implemented and tested but never called from InsightsCharts.swift. Monthly chart uses stride(by: .month, count: 3) which generates exactly quarterly marks but does NOT add the current month when it falls between quarterly intervals. The plan key link (InsightsCharts.swift monthlyChart → quarterlyLabelDates) is unwired. Current month label is absent in non-quarterly months (e.g. March 2026 would show only Apr/Jul/Oct/Jan — no March label)."
    artifacts:
      - path: "AIBattery/Views/InsightsRowsAndHover.swift"
        issue: "quarterlyLabelDates is declared and correct but orphaned — zero production call sites"
      - path: "AIBattery/Views/InsightsCharts.swift"
        issue: "monthlyChart uses AxisMarks(values: .stride(by: .month, count: 3)) instead of quarterlyLabelDates — current month never added when non-quarterly"
    missing:
      - "Replace AxisMarks(values: .stride(by: .month, count: 3)) in monthlyChart with AxisMarks(values: Self.quarterlyLabelDates(from: dates)) to wire the tested implementation"
      - "Add .chartXScale(domain: dates.first!...dates.last!) after .chartXAxis block to pin the plot domain (was removed during deviations)"
human_verification:
  - test: "DATA-01 cold start visual check"
    expected: "24H chart shows a zero-filled bar chart on launch before JSONL scan completes — not the 'No activity' empty state"
    why_human: "isEmpty branch depends on timing of JSONL scan relative to dailyActivity fetch; cannot verify dynamically"
  - test: "CHART-02 24H axis label appearance"
    expected: "Exactly 4 labels: 00:00, 06:00, 12:00, 18:00 with equal pixel gaps, no 'Now' label collision"
    why_human: "Visual layout at 275pt popover width requires visual inspection"
  - test: "CHART-01 12M current month label"
    expected: "Current month (e.g. March 2026) appears as a label on the 12M x-axis even when it is not a quarterly anchor month"
    why_human: "stride(by: .month, count: 3) does not include non-quarterly months; must confirm visually whether current month appears"
---

# Phase 13: Chart Data Fixes Verification Report

**Phase Goal:** Insights charts display accurate data and readable labels at all times
**Verified:** 2026-03-24T10:00:00Z
**Status:** gaps_found
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | 24H chart shows zero-filled chart on cold start when daily activity exists — not "No activity" | VERIFIED | `isHourlyEmpty` real impl in InsightsRowsAndHover.swift:180; wired at ActivityChartView.swift:89 |
| 2 | After JSONL scan completes, 24H chart updates to reflect actual hourly data | VERIFIED | isEmpty delegates to `isHourlyEmpty` which falls back to `todayHourCounts.values.allSatisfy { $0 == 0 }` once scan populates counts |
| 3 | 24H chart x-axis shows exactly 4 labels: 00:00, 06:00, 12:00, 18:00 with equal 6-unit gaps | VERIFIED | InsightsCharts.swift:150 `AxisMarks(values: [0, 6, 12, 18])` + InsightsCharts.swift:153 `formatHourLabelFull`; domain pinned at 0...23 (line 159) |
| 4 | 12M chart x-axis shows 4-5 labels (quarterly + current month) with no overlap at 275pt width | FAILED | Monthly chart uses `stride(by: .month, count: 3)` — shows quarterly marks only; current month NOT added when non-quarterly. `quarterlyLabelDates` is orphaned (never called in production code) |
| 5 | 12M chart plot area spans the full 12-month range (not compressed to labeled points only) | UNCERTAIN | Plan required `.chartXScale(domain: dates.first!...dates.last!)` alongside quarterly labels; stride approach omits explicit domain pin. May or may not compress depending on SwiftUI Charts default behavior |
| 6 | Hover tooltip and ActivityChartTrend peak label show correct HH:00 format (no double-suffix) | VERIFIED | InsightsRowsAndHover.swift:137 still calls `formatHourLabel` + `:00`; ActivityChartTrend.swift:40 unchanged |
| 7 | All 12 tests from Plan 01 pass GREEN | VERIFIED | 12 tests in place (4 in ActivityChartIsEmptyTests.swift, 8 in InsightsViewFormatterTests.swift); `swift build` passes; implementation is substantive (no STUBs remain) |

**Score:** 6/7 truths verified (Truth 4 failed; Truth 5 uncertain)

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `AIBattery/Views/InsightsRowsAndHover.swift` | isHourlyEmpty, formatHourLabelFull, quarterlyLabelDates real impls | VERIFIED | All three declared at lines 180, 190, 198; no STUB comments remain |
| `AIBattery/Views/ActivityChartView.swift` | isEmpty uses isHourlyEmpty static helper | VERIFIED | Line 89: `return Self.isHourlyEmpty(todayHourCounts: todayHourCounts, dailyActivity: dailyActivity)` |
| `AIBattery/Views/InsightsCharts.swift` | hourlyChart uses [0,6,12,18] + formatHourLabelFull; monthlyChart uses quarterlyLabelDates + .chartXScale | PARTIAL | hourlyChart: VERIFIED (lines 150, 153, 159). monthlyChart: formatHourLabelFull NOT used; quarterlyLabelDates NOT called; stride used instead |
| `Tests/AIBatteryCoreTests/Views/ActivityChartIsEmptyTests.swift` | 4 tests for DATA-01 isEmpty logic | VERIFIED | 4 @Test functions present; tests call InsightsView.isHourlyEmpty |
| `Tests/AIBatteryCoreTests/Views/InsightsViewFormatterTests.swift` | 8 tests for CHART-02 and CHART-01 | VERIFIED | 8 @Test functions present (5 formatHourLabelFull, 3 quarterlyLabelDates) |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| ActivityChartView.swift isEmpty | InsightsRowsAndHover.swift isHourlyEmpty | `InsightsView.isHourlyEmpty(todayHourCounts:dailyActivity:)` | WIRED | Line 89 in ActivityChartView.swift |
| InsightsCharts.swift hourlyChart | InsightsRowsAndHover.swift formatHourLabelFull | `Self.formatHourLabelFull(data[offset].hour)` | WIRED | Lines 150 + 153 in InsightsCharts.swift |
| InsightsCharts.swift monthlyChart | InsightsRowsAndHover.swift quarterlyLabelDates | `Self.quarterlyLabelDates(from: dates)` | NOT WIRED | Monthly chart uses `stride(by: .month, count: 3)` — quarterlyLabelDates has zero production call sites |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| DATA-01 | 13-01, 13-02 | 24H chart never shows "No activity" when daily activity data exists — uses dailyActivity as loading signal | SATISFIED | isHourlyEmpty implemented and wired into ActivityChartView.isEmpty |
| CHART-02 | 13-01, 13-02 | 24H chart shows 4 evenly-spaced hour labels in HH:00 format (00:00, 06:00, 12:00, 18:00) | SATISFIED | [0,6,12,18] axis values with formatHourLabelFull in InsightsCharts.swift |
| CHART-01 | 13-01, 13-02 | 12M chart shows quarterly month labels plus current month — no overlapping text | BLOCKED | stride approach shows quarterly months but does NOT include current month when non-quarterly; quarterlyLabelDates (the implementation designed to satisfy this) is orphaned |

No orphaned requirements — all three Phase 13 IDs (DATA-01, CHART-02, CHART-01) appear in both plans' frontmatter.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `AIBattery/Views/InsightsRowsAndHover.swift` | 198 | `quarterlyLabelDates` declared but zero production call sites | Warning | Implementation and tests exist for CHART-01 but production chart ignores them |

No TODO/FIXME/placeholder comments remain. No empty implementations. Build is clean.

### Human Verification Required

#### 1. DATA-01 Cold Start Empty State

**Test:** Quit AIBattery fully, relaunch, immediately open popover and switch to 24H tab.
**Expected:** A chart with bars visible (possibly all at 0) — NOT the "No activity in 24H window" empty state message. After ~5 seconds, chart should update to show actual hourly data.
**Why human:** Timing-dependent: depends on relative speed of dailyActivity fetch vs. JSONL scan completion.

#### 2. CHART-02 24H Axis Visual Appearance

**Test:** Open popover, navigate to Insights, view 24H chart x-axis.
**Expected:** Exactly 4 labels (00:00, 06:00, 12:00, 18:00) with equal pixel spacing. No truncation, no "Now" label collision.
**Why human:** Visual layout at 275pt width cannot be verified programmatically.

#### 3. CHART-01 Current Month on 12M Axis

**Test:** Open popover, navigate to Insights, switch to 12M chart. Today is March 2026.
**Expected per requirement:** "Mar" should appear as a label on the x-axis even though March is not a quarterly anchor month.
**What will likely happen:** The `stride(by: .month, count: 3)` implementation will show Apr, Jul, Oct, Jan — but NOT Mar. This is the gap to confirm visually.
**Why human:** Axis label presence at runtime requires visual inspection.

### Gaps Summary

One functional gap blocks full goal achievement:

**CHART-01 incomplete wiring.** The `quarterlyLabelDates` static helper was built and tested in Plan 01, and Plan 02 was supposed to wire it into the monthly chart. However, Plan 02 deviated and used `stride(by: .month, count: 3)` instead. The stride approach satisfies the "no overlapping text" part of CHART-01 but fails the "plus current month" part — in March 2026, the current month would not appear as a label.

The fix is straightforward: replace `AxisMarks(values: .stride(by: .month, count: 3))` with `AxisMarks(values: Self.quarterlyLabelDates(from: dates))` in `InsightsCharts.swift`'s `monthlyChart`. This wires the already-implemented and already-tested function into production use.

---

_Verified: 2026-03-24T10:00:00Z_
_Verifier: Claude (gsd-verifier)_
