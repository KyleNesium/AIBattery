# Phase 13: Chart & Data Fixes - Research

**Researched:** 2026-03-24
**Domain:** Swift Charts axis configuration, SwiftUI state management, chart empty-state logic
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- 24H chart: Replace `[0, 4, 8, 12, 16, 20, 23]` with `[0, 6, 12, 18]` — even 6h intervals mapping to clock anchors (midnight, 6am, noon, 6pm)
- 24H labels use `HH:00` format (e.g. "00:00", "06:00", "12:00", "18:00") — user requested full time display
- 12M chart: Show quarterly month labels plus always include current month (4-5 labels total) — user requires current month visibility
- 12M labels keep `Typography.monoTiny` (10pt mono) — fewer labels removes the cramming problem without needing smaller font
- Guard `isEmpty` with `dailyActivity` check — if daily has messages but hourCounts is empty dict, return false (not truly empty, just loading)
- Show zero-filled chart while loading — chart appears immediately with 24 bars at 0, fills when hourCounts data arrives via JSONL scan
- No fingerprint change needed — existing `dataFingerprint` already triggers refresh when `todayHourCounts` populates

### Claude's Discretion
- Implementation order within the phase
- Whether to add `.chartXScale(domain:)` to monthly chart for domain pinning (research suggests yes)

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| DATA-01 | 24H chart never shows "No activity" when daily activity data exists — uses dailyActivity as loading signal | isEmpty logic in ActivityChartView.swift line 86-92; guard against `todayHourCounts` being empty when `dailyActivity` has records |
| CHART-02 | 24H chart shows 4 evenly-spaced hour labels in `HH:00` format (00:00, 06:00, 12:00, 18:00) | AxisMarks(values:) in InsightsCharts.swift line 150; formatHourLabel in InsightsRowsAndHover.swift line 172 |
| CHART-01 | 12M chart shows quarterly month labels plus current month — no overlapping text | monthlyChart AxisMarks in InsightsCharts.swift line 216-225; need quarterly filter logic + .chartXScale(domain:) |
</phase_requirements>

## Summary

Phase 13 has three narrowly scoped bug fixes, all in the Insights chart subsystem. The code surfaces are small and well-understood: `ActivityChartView.swift` (the `isEmpty` property, ~7 lines) and `InsightsCharts.swift` (two chart axis configurations, ~20 lines each). No new types, services, or data pipelines are introduced.

The false-empty-state bug (DATA-01) is in `ActivityChartView.swift` line 89: the `.hourly` branch of `isEmpty` checks `todayHourCounts.values.allSatisfy { $0 == 0 }`, which is true when the dict is empty (cold start, before JSONL scan completes). The fix guards on `dailyActivity` having records first — if today has daily activity, the chart is loading, not empty.

The 24H axis label bug (CHART-02) is a one-line change in `InsightsCharts.swift` line 150: `[0, 4, 8, 12, 16, 20, 23]` becomes `[0, 6, 12, 18]`. The label format change requires updating `formatHourLabel` (or adding a variant) to produce `"HH:00"` instead of `"HH"`. The tooltip in `hoverTooltipText` (InsightsRowsAndHover.swift line 137) already appends `:00`, so it must be reconciled to avoid double-suffix.

The 12M axis clutter bug (CHART-01) requires computing a filtered date array — quarterly months plus the current month — and passing it to `AxisMarks(values:)`, replacing the current `dates` (all 12 months). Adding `.chartXScale(domain:)` anchors the chart to the full 12-month range so removing labels from the axis doesn't shrink the plot area.

**Primary recommendation:** Fix in dependency order: DATA-01 first (isolated, no chart rendering involved), then CHART-02 (axis-only change), then CHART-01 (requires domain pinning research applied). Write tests before each fix.

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Swift Charts | macOS 13+ built-in | Chart rendering, axis marks | Project already uses it; no alternatives considered |
| SwiftUI | macOS 13+ built-in | State management, view lifecycle | Project standard |
| Swift Testing | Xcode built-in | Unit tests | Project standard (`@Test`, `#expect`) |

No new dependencies. All fixes use existing frameworks.

**Installation:** n/a — no new packages.

## Architecture Patterns

### Recommended Project Structure

No new files required. All changes are within:

```
AIBattery/Views/
├── ActivityChartView.swift     # isEmpty fix (DATA-01)
├── InsightsCharts.swift        # hourlyChart + monthlyChart axis fixes (CHART-02, CHART-01)
└── InsightsRowsAndHover.swift  # formatHourLabel update (CHART-02 side effect)

Tests/AIBatteryCoreTests/Views/
└── ActivityChartDataTests.swift  # extend with new isEmpty-behavior tests
    (or new InsightsViewFormatterTests.swift for label format tests)
```

### Pattern 1: AxisMarks with Explicit Value Array

**What:** Pass a hand-crafted array to `AxisMarks(values:)` to control exactly which ticks appear. Swift Charts renders one label per value; omitted values have no label or tick.

**When to use:** When automatic tick placement produces too many or unevenly spaced labels.

**Current (broken) 24H:**
```swift
// Source: InsightsCharts.swift line 150
AxisMarks(values: [0, 4, 8, 12, 16, 20, 23]) { value in
    // Last interval 20→23 is only 3 units wide vs 4 units elsewhere — visually uneven
```

**Fixed 24H:**
```swift
AxisMarks(values: [0, 6, 12, 18]) { value in
    AxisValueLabel {
        if let offset = value.as(Int.self), offset >= 0, offset < data.count {
            Text(Self.formatHourLabel(data[offset].hour))
                .font(Typography.decorativeIcon)
        }
    }
}
```

### Pattern 2: chartXScale(domain:) for Domain Pinning

**What:** Fixes the chart's x-axis domain to a specified range regardless of what labels are shown. Without it, reducing AxisMarks values can cause Swift Charts to shrink the visible range to fit only the labeled points.

**When to use:** Monthly chart after reducing from 12 labels to 4-5 — prevents plot area shrinkage.

**Example (monthly chart):**
```swift
// Add after .chartXAxis { ... }
.chartXScale(domain: dates.first!...dates.last!)
// OR using explicit Date range if dates might be empty:
// .chartXScale(domain: startDate...endDate)
```

The 24H chart already has `.chartXScale(domain: 0...23)` (line 159) — this is the correct pattern to replicate for the monthly chart.

### Pattern 3: Quarterly Label Filtering

**What:** Compute which months to label from the full 12-month `dates` array. Quarterly = months at indices where `month % 3 == 1` (Jan, Apr, Jul, Oct). Always include current month.

**When to use:** 12M chart axis (CHART-01).

**Example:**
```swift
// In monthlyChart computed property
let cal = Calendar.current
let currentMonthKey = data.last?.key  // data is ordered chronologically, last = current month
let labelDates: [Date] = dates.filter { date in
    let month = cal.component(.month, from: date)
    let isQuarterly = (month % 3 == 1)  // Jan=1, Apr=4, Jul=7, Oct=10
    let isCurrent = data.first(where: { $0.date == date })?.key == currentMonthKey
    return isQuarterly || isCurrent
}
// Pass labelDates to AxisMarks(values:)
```

Note: The CONTEXT.md says "quarterly month labels plus always include current month (4-5 labels total)". If current month happens to already be a quarterly anchor, result is 4 labels. Otherwise 5. The filter above handles both cases naturally.

### Pattern 4: isEmpty Guard for Loading State (DATA-01)

**What:** The `.hourly` branch of `isEmpty` treats an empty `todayHourCounts` dict the same as "all zeros" — but empty dict means "still loading from JSONL scan", not "truly no activity today". Guard with `dailyActivity` presence.

**Current (broken):**
```swift
// ActivityChartView.swift line 89
case .hourly: return todayHourCounts.values.allSatisfy { $0 == 0 }
```

**Fixed:**
```swift
case .hourly:
    // If daily activity exists for today, hourCounts is still loading — not truly empty
    let todayKey = DateFormatters.dateKey.string(from: Date())
    let hasTodayActivity = dailyActivity.contains { $0.date == todayKey && $0.messageCount > 0 }
    if hasTodayActivity { return false }
    return todayHourCounts.values.allSatisfy { $0 == 0 }
```

Alternative (simpler, per CONTEXT.md): guard `dailyActivity` generally — if any daily activity exists, hourly is loading not empty:
```swift
case .hourly:
    if dailyActivity.contains(where: { $0.messageCount > 0 }) { return false }
    return todayHourCounts.values.allSatisfy { $0 == 0 }
```

The CONTEXT.md locked decision is "if daily has messages but hourCounts is empty dict, return false". The today-scoped version is more precise (avoids showing a chart on a day where there's prior-day data but literally nothing today). The planner should implement the today-scoped guard.

### Anti-Patterns to Avoid

- **Shrinking 12M plot area:** Passing fewer dates to `AxisMarks(values:)` without adding `.chartXScale(domain:)` causes Swift Charts to compress the visible range. Always pin the domain.
- **Double `:00` suffix in tooltip:** `hoverTooltipText` for `.hourly` already appends `:00` to `formatHourLabel` output (InsightsRowsAndHover.swift line 137: `"\(Self.formatHourLabel(point.hour)):00 — \(point.count) msgs"`). If `formatHourLabel` is changed to return `"HH:00"`, this concatenation becomes `"HH:00:00"`. Fix the tooltip call site to remove the manual `:00`, OR add a new `formatHourLabelFull` function and update only the axis call site.
- **ActivityChartTrend.swift also uses formatHourLabel:** Line 40 in ActivityChartTrend.swift: `"Peak: \(InsightsView.formatHourLabel($0)):00"`. Same double-suffix issue. Audit all call sites before changing the function signature.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Quarterly date filtering | Custom calendar math | Swift `Calendar.component(.month, from:)` | Already used throughout codebase |
| Chart domain clamping | Manual axis scaling | `.chartXScale(domain:)` | Swift Charts built-in modifier |
| Zero-filled hourly data | Custom fallback array | `ActivityChartData.hourlyData(from:)` | Already returns 24 zero-count points for empty input |

**Key insight:** `ActivityChartData.hourlyData(from: [:])` already produces 24 zero-count `HourlyPoint` values — the chart can render immediately on cold start. The only change needed is suppressing the `isEmpty` guard that prevents the chart from rendering.

## Common Pitfalls

### Pitfall 1: Double `:00` Suffix After formatHourLabel Change
**What goes wrong:** `formatHourLabel` currently returns `"HH"` (e.g. `"06"`). Three call sites append `:00` manually. Changing the function to return `"HH:00"` without updating all three call sites produces `"06:00:00"` in tooltips and trend labels.
**Why it happens:** `formatHourLabel` is used in 3 places: InsightsCharts.swift (axis label), InsightsRowsAndHover.swift (hover tooltip), ActivityChartTrend.swift (peak label in trend summary).
**How to avoid:** Either (a) rename to `formatHourLabelFull` returning `"HH:00"` and only update the axis call site, keeping `formatHourLabel` for the other two sites; or (b) change `formatHourLabel` and update all 3 call sites to drop their manual `:00`.
**Warning signs:** Search for `formatHourLabel` across all files before changing the function — there are 3 call sites plus the accessibility label in InsightsCharts.swift line 119.

### Pitfall 2: dataFingerprint Sum Collision Masking DATA-01 Fix
**What goes wrong:** The `dataFingerprint` includes `todayHourCounts.values.reduce(0, +)`. When `todayHourCounts` is empty, the sum is 0. When populated with e.g. `["14": 3, "15": 2]`, sum is 5. This triggers a fingerprint change and `refreshCachedData()` correctly. However if the sum accidentally matches a previous fingerprint value, no refresh fires. The STATE.md explicitly calls this out as a concern.
**Why it happens:** Hash collisions are possible but unlikely. The real risk is that the fix suppresses the false empty state on first render but the chart doesn't update when `todayHourCounts` later populates (if fingerprint somehow matches).
**How to avoid:** After implementing DATA-01, write a test that: (1) starts with empty `todayHourCounts` + non-empty `dailyActivity`, (2) verifies chart is NOT in empty state, (3) populates `todayHourCounts` and verifies fingerprint changed. Manual verification in the running app is also required (per STATE.md blockers).

### Pitfall 3: Monthly Domain Pinning Required After Label Reduction
**What goes wrong:** Without `.chartXScale(domain:)`, reducing from 12 AxisMarks values to 4-5 causes Swift Charts to render only the labeled range, clipping the chart visually.
**Why it happens:** Swift Charts infers domain from the axis mark values when no explicit domain is set.
**How to avoid:** Add `.chartXScale(domain: dates.first!...dates.last!)` to `monthlyChart` before reducing the label array. The 24H chart already demonstrates this pattern correctly (`.chartXScale(domain: 0...23)` at line 159).
**Warning signs:** Must be verified in the running app at 275pt popover width — Xcode canvas is not a reliable proxy (per STATE.md blockers).

### Pitfall 4: HourlyPoint.id vs HourlyPoint.offset Confusion
**What goes wrong:** `HourlyPoint.id` returns `offset` (0–23), not `hour` (0–23 calendar hour). The axis mark values `[0, 6, 12, 18]` are offset indices, not hours. `data[offset].hour` gives the actual calendar hour for formatting.
**Why it happens:** The 24H window is a rolling 24 hours — offset 0 is the oldest hour, offset 23 is the current hour. At 14:00, offset 0 is hour 15 (yesterday), offset 23 is hour 14 (now).
**How to avoid:** When changing axis marks from `[0, 4, 8, 12, 16, 20, 23]` to `[0, 6, 12, 18]`, the label lookup `data[offset].hour` remains correct — offset 0 always maps to the oldest hour in the window, which at midnight would be hour 1 of yesterday. The axis will show 4 evenly spaced labels by offset position, each labeled with its calendar hour. This is the existing behavior — just fewer labels.

## Code Examples

Verified patterns from the existing codebase:

### DATA-01: isEmpty fix
```swift
// ActivityChartView.swift — .hourly branch of isEmpty (line 89)
// BEFORE:
case .hourly: return todayHourCounts.values.allSatisfy { $0 == 0 }

// AFTER (today-scoped guard):
case .hourly:
    let todayKey = DateFormatters.dateKey.string(from: Date())
    if dailyActivity.contains(where: { $0.date == todayKey && $0.messageCount > 0 }) {
        return false
    }
    return todayHourCounts.values.allSatisfy { $0 == 0 }
```

### CHART-02: 24H axis labels
```swift
// InsightsCharts.swift — hourlyChart axis (line 149-158)
// BEFORE:
.chartXAxis {
    AxisMarks(values: [0, 4, 8, 12, 16, 20, 23]) { value in
        AxisValueLabel {
            if let offset = value.as(Int.self), offset >= 0, offset < data.count {
                Text(Self.formatHourLabel(data[offset].hour))
                    .font(Typography.decorativeIcon)
            }
        }
    }
}

// AFTER:
.chartXAxis {
    AxisMarks(values: [0, 6, 12, 18]) { value in
        AxisValueLabel {
            if let offset = value.as(Int.self), offset >= 0, offset < data.count {
                Text(Self.formatHourLabelFull(data[offset].hour))
                    .font(Typography.decorativeIcon)
            }
        }
    }
}
```

### CHART-02: New formatHourLabelFull formatter
```swift
// InsightsRowsAndHover.swift — alongside existing formatHourLabel
static func formatHourLabelFull(_ hour: Int) -> String {
    guard hour >= 0 && hour < 24 else { return String(format: "%02d:00", hour) }
    return String(format: "%02d:00", hour)
}
```

### CHART-01: Monthly chart quarterly labels + domain pinning
```swift
// InsightsCharts.swift — monthlyChart (replaces lines 216-225)
var monthlyChart: some View {
    let data = cachedMonthly
    let dates = data.map(\.date)

    // Quarterly months (Jan, Apr, Jul, Oct) + current month
    let cal = Calendar.current
    let currentMonthKey = data.last?.key
    let labelDates: [Date] = dates.filter { date in
        let month = cal.component(.month, from: date)
        let isQuarterly = (month % 3 == 1)
        let isCurrent = data.first(where: { $0.date == date })?.key == currentMonthKey
        return isQuarterly || isCurrent
    }

    return Chart { ... }
        .chartXAxis {
            AxisMarks(values: labelDates) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(Self.monthAbbrev(date))
                            .font(Typography.monoTiny)
                    }
                }
            }
        }
        .chartXScale(domain: dates.first!...dates.last!)  // pin domain — prevents plot shrinkage
        ...
}
```

Note: `dates` is guaranteed non-empty because `monthlyData` always returns 12 points. Force-unwrap is safe.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| All 12 month labels on 12M chart | 4-5 quarterly labels | Phase 13 | Eliminates label collision at 275pt width |
| Uneven 7-point 24H axis `[0,4,8,12,16,20,23]` | Even 4-point `[0,6,12,18]` | Phase 13 | Equal pixel gaps, clock-anchor alignment |
| Empty `todayHourCounts` → "No activity" | `dailyActivity` as loading signal | Phase 13 | Chart visible immediately after cold start |

**No deprecated patterns in this phase.**

## Open Questions

1. **Quarterly anchor months when current month is a boundary**
   - What we know: Filter `month % 3 == 1` selects Jan(1), Apr(4), Jul(7), Oct(10)
   - What's unclear: Is this the correct quarterly cadence for all months in the 12-month window? In February (month=2), no quarterly month falls in the range Feb–Jan (next year). The window always covers exactly 12 months starting from 12 months ago — e.g. in March 2026 the window is Apr 2025–Mar 2026. Quarterly anchors would be Apr, Jul, Oct (2025) and Jan (2026) = 4 labels. Current month (Mar 2026) adds a 5th.
   - What needs validation: Run the quarterly filter mentally for the current date (March 2026) and confirm 4-5 labels result. No code change needed — just a pre-implementation sanity check.
   - Recommendation: Implement as described. Write a test with a fixed `now` date to assert exactly which months are labeled.

2. **`data.first(where: { $0.date == date })` lookup in quarterly filter**
   - What we know: `MonthlyPoint.date` is a `Date` (start-of-month). The filter compares `Date` equality — which is exact to the nanosecond. `dates` is derived from `data.map(\.date)`, so the same `Date` instances are used.
   - What's unclear: Whether `Date` equality holds across the filter. Since `dates` comes from `data.map(\.date)` and the filter iterates `dates`, the same `Date` instances from `data` are in both — equality is guaranteed.
   - Recommendation: Safe as written. Alternatively, use index-based approach: `data.last?.key` and compare against month component.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Swift Testing (built-in, Xcode required) |
| Config file | Package.swift `.testTarget("AIBatteryCoreTests")` |
| Quick run command | `swift test --filter ActivityChartDataTests` |
| Full suite command | `swift test` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| DATA-01 | `isEmpty` returns `false` when `dailyActivity` has today's records but `todayHourCounts` is empty | unit | `swift test --filter "ActivityChartViewTests"` | ❌ Wave 0 |
| DATA-01 | `isEmpty` returns `false` when `todayHourCounts` has all-zero values but today has daily activity | unit | `swift test --filter "ActivityChartViewTests"` | ❌ Wave 0 |
| DATA-01 | `isEmpty` returns `true` when both `dailyActivity` and `todayHourCounts` are genuinely empty | unit | `swift test --filter "ActivityChartViewTests"` | ❌ Wave 0 |
| CHART-02 | `formatHourLabelFull(0)` returns `"00:00"` | unit | `swift test --filter "InsightsViewFormatterTests"` | ❌ Wave 0 |
| CHART-02 | `formatHourLabelFull(6)` returns `"06:00"` | unit | `swift test --filter "InsightsViewFormatterTests"` | ❌ Wave 0 |
| CHART-02 | `formatHourLabelFull(18)` returns `"18:00"` | unit | `swift test --filter "InsightsViewFormatterTests"` | ❌ Wave 0 |
| CHART-01 | Quarterly filter for March 2026 produces `["Apr", "Jul", "Oct", "Jan", "Mar"]` labels | unit | `swift test --filter "InsightsViewFormatterTests"` | ❌ Wave 0 |
| CHART-01 | Current month always appears in label set regardless of quarter | unit | `swift test --filter "InsightsViewFormatterTests"` | ❌ Wave 0 |

Note: `isEmpty` is a computed property on `InsightsView` (a `View`). It cannot be tested directly without a host view. Extract the logic into a pure static helper in a testable extension, or test indirectly via `ActivityChartData` inputs. The planner should extract the `isEmpty` logic into a testable free function or static method.

### Sampling Rate
- **Per task commit:** `swift test --filter ActivityChartDataTests`
- **Per wave merge:** `swift test`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `Tests/AIBatteryCoreTests/Views/ActivityChartViewTests.swift` — covers DATA-01 isEmpty behavior
- [ ] `Tests/AIBatteryCoreTests/Views/InsightsViewFormatterTests.swift` — covers CHART-02 (formatHourLabelFull) and CHART-01 (quarterly filter logic)

*(Both test files must be created before implementation begins.)*

## Sources

### Primary (HIGH confidence)
- Direct code inspection — `ActivityChartView.swift`, `InsightsCharts.swift`, `InsightsRowsAndHover.swift`, `ActivityChartData.swift`, `ActivityChartTrend.swift`
- `CONTEXT.md` — user decisions locked before research phase
- `REQUIREMENTS.md` — formal requirement definitions
- `STATE.md` — accumulated project decisions and explicit pitfall warnings

### Secondary (MEDIUM confidence)
- Existing Swift Charts usage patterns in codebase — `.chartXScale(domain:)` already used on hourly chart (line 159), confirming the API is available and working on this macOS target

### Tertiary (LOW confidence)
- None — all findings are code-verified

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no new libraries, all changes are in existing files
- Architecture: HIGH — change surfaces identified precisely, patterns verified from existing working code
- Pitfalls: HIGH — double-suffix pitfall confirmed by reading all 3 call sites; domain pinning confirmed by existing 24H chart usage; sum collision concern documented in STATE.md

**Research date:** 2026-03-24
**Valid until:** 2026-04-24 (stable domain — Swift Charts API, SwiftUI state management)
