# Stack Research

**Domain:** Swift Charts axis label customization and SwiftUI layout spacing (macOS menu bar app)
**Researched:** 2026-03-24
**Confidence:** HIGH — all APIs verified against existing working codebase; Swift Charts axis APIs stable since iOS 16 / macOS 13

---

## Context

This is a focused fix milestone on top of a validated, shipping stack. The stack is NOT changing. This document covers only the APIs needed to fix three chart rendering issues and one layout spacing inconsistency in AIBattery v1.14.

Existing chart infrastructure (Swift Charts, `AxisMarks`, `AxisValueLabel`, `AxisTick`, `sharedYAxis`) works correctly — we are adjusting axis label density and the empty-state logic only.

---

## The Four Target Issues and Their Root Causes

### Issue 1: 12M chart — month labels squished/illegible

**Root cause:** `AxisMarks(values: dates)` passes all 12 `Date` values explicitly. Swift Charts renders a label at every position. At `Layout.popoverWidth = 275pt` minus the trailing Y-axis (~30pt), the plot area is ~245pt wide. 12 labels at `monoTiny` (10pt monospaced) are each ~20-24pt wide — they collide.

**Fix:** Switch from explicit `values: dates` to `values: .stride(by: .month, count: 1)`. The existing `monthAbbrev()` helper already produces 3-letter abbreviations ("Jan"). At 9pt (`Typography.decorativeIcon`) each abbreviation renders in ~14pt — fits the ~20pt slot with 6pt margin.

**API:**
```swift
.chartXAxis {
    AxisMarks(values: .stride(by: .month, count: 1)) { value in
        AxisValueLabel {
            if let date = value.as(Date.self) {
                Text(Self.monthAbbrev(date))
                    .font(Typography.decorativeIcon) // 9pt — matches Y-axis token
            }
        }
    }
}
```

Why `stride(by: .month, count: 1)` beats `values: dates`: the stride form tells Charts the *semantic interval* so it applies domain clamping correctly and avoids duplicate ticks at month boundaries. Passing raw dates bypasses Charts' internal tick placement logic and can produce boundary duplicates when the domain spans exactly 12 months.

Why drop from `Typography.monoTiny` (10pt) to `Typography.decorativeIcon` (9pt): saves ~1pt per label slot. The Y-axis already uses `decorativeIcon` — using it on X is consistent. 1pt difference is imperceptible to users.

---

### Issue 2: 24H chart — hour labels unevenly spaced at offsets [0,4,8,12,16,20,23]

**Root cause:** The gap 20→23 is 3 while all others are 4. The offset 23 exists to show the current hour, but the irregular gap creates visual asymmetry and risks two labels visually merging.

The hourly chart uses `Int` offsets (0–23) on the X-axis, not `Date`. The `stride(by: .hour)` calendar form does not apply here. Use integer `AxisMarkValues.stride(by:)` instead.

**Fix — uniform stride of 6 (labels at offsets 0, 6, 12, 18):**
```swift
AxisMarks(values: .stride(by: 6)) { value in
    AxisValueLabel {
        if let offset = value.as(Int.self), offset >= 0, offset < data.count {
            Text(Self.formatHourLabel(data[offset].hour))
                .font(Typography.decorativeIcon)
        }
    }
}
```

Produces 4 evenly-spaced labels at offsets 0, 6, 12, 18. These map to midnight, 6am, noon, 6pm — semantic time anchors users recognize. The existing hover tooltip already shows the exact hour on interaction, so losing the static offset-23 label removes no information.

Why stride-6 over stride-8 (which gives labels at 0, 8, 16): stride-6 produces intuitive clock anchors (midnight/6am/noon/6pm). Stride-8 produces 0h/8h/16h which lack common-language names.

Why `.stride(by: 6)` works on Int axes: `AxisMarkValues.stride(by:)` accepts any `Strideable` type including `Int`. The chart domain is already set via `.chartXScale(domain: 0...23)`, so Charts produces ticks at exactly 0, 6, 12, 18.

---

### Issue 3: 24H chart falsely shows "No activity" after app update

**Root cause:** `todayHourCounts` is derived entirely from live JSONL reads in `UsageAggregator`. On first launch after an update, the JSONL scan runs off the main thread and completes ~2s after init. The `cachedOrEmpty` fast-path in `UsageViewModel.init` produces a `UsageSnapshot` where `todayHourCounts = [:]`.

The `isEmpty` check in `InsightsView` for `.hourly` mode is:
```swift
case .hourly: return todayHourCounts.values.allSatisfy { $0 == 0 }
```
An empty dictionary satisfies `allSatisfy` — returns `true` → "No activity" shown.

Meanwhile `dailyActivity` from `stats-cache.json` IS available immediately (read synchronously). The chart mode defaults to `.hourly` via `@AppStorage`, so if the user last left the panel on 24H mode, the false empty state appears on every cold start until the 2s JSONL scan completes.

**Fix — use `dailyActivity` as a loading signal:**
```swift
// In InsightsView.isEmpty, .hourly case:
case .hourly:
    // todayHourCounts is JSONL-only (async). If it's empty but today's stats-cache
    // entry has messages, the scan is still in flight — suppress false empty state.
    let todayKey = DateFormatters.dateKey.string(from: .now)
    let hasTodayInCache = dailyActivity.contains { $0.date == todayKey && $0.messageCount > 0 }
    if todayHourCounts.isEmpty && hasTodayInCache {
        return false // Loading — show zero-filled chart, not "No activity"
    }
    return todayHourCounts.values.allSatisfy { $0 == 0 }
```

This is a pure logic fix in `ActivityChartView.swift`. No new state, no persistence, no async changes. The chart briefly shows zero-filled hourly bars (all zeros) until JSONL completes (~2s), then `onChange(of: dataFingerprint)` fires and updates to real data. A flat-line chart for 2s is accurate and honest — it correctly communicates "data loading" rather than asserting "nothing happened today."

Do NOT persist `todayHourCounts` to disk. Stale hourly data from yesterday would be actively misleading.

---

### Issue 4: Rate limit sections — uneven vertical padding

**Root cause:** The padding stack when all three sections render:

| Element | Top padding | Bottom padding |
|---------|------------|----------------|
| `MetricToggleView` | `Spacing.section` (8pt) | `Spacing.gap` (6pt) |
| `StyledDivider` | `Spacing.tight` (2pt) | `Spacing.tight` (2pt) |
| `FiveHourBarSection` | `Spacing.section` (8pt) | `Spacing.section` (8pt) |
| `StyledDivider` | `Spacing.tight` (2pt) | `Spacing.tight` (2pt) |
| `SevenDayBarSection` | `Spacing.section` (8pt) | `Spacing.section` (8pt) |

Gap from MetricToggleView content to FiveHourBarSection content: `6pt + 2pt + 8pt = 16pt`
Gap from FiveHourBarSection content to SevenDayBarSection content: `8pt + 2pt + 8pt = 18pt`

The 2pt asymmetry (`Spacing.gap` vs `Spacing.section` on the toggle's bottom) is the entire source of the visual inconsistency.

**Fix:** Change `MetricToggleView`'s bottom padding from `Spacing.gap` to `Spacing.section`:
```swift
// MetricToggleView.body — change one line:
.padding(.bottom, Spacing.gap)    // 6pt — current, causes asymmetry
.padding(.bottom, Spacing.section) // 8pt — normalized
```

Every gap between adjacent section content rows becomes uniformly `8 + 2 + 8 = 18pt`. One-line change, no tests required, no layout structure changes.

---

## API Reference — Swift Charts Axis Customization

### `AxisMarkValues` constructors (macOS 13+, HIGH confidence)

| Constructor | Type | Behavior |
|-------------|------|----------|
| `AxisMarkValues.stride(by: Int)` | Int axes | Places marks at every N integer steps |
| `AxisMarkValues.stride(by: Calendar.Component, count: Int)` | Date axes | Places marks at calendar-aligned intervals |
| `AxisMarkValues.automatic(desiredCount: Int)` | Any | Approximates N marks (already used on Y-axis) |
| `[T]` (explicit array) | Any | Exact positions — bypasses overflow handling |

### `AxisMarks` modifier (macOS 13+, HIGH confidence)

```swift
AxisMarks(position: .trailing, values: .stride(by: ...)) { value in
    AxisGridLine(stroke: ...)
    AxisTick(stroke: ...)
    AxisValueLabel { /* custom Text */ }
}
```

The `AxisMarkBuilder` closure receives an `AxisValue` — call `value.as(Int.self)` or `value.as(Date.self)` to extract the typed value. Returns `nil` when the cast fails (e.g., at scale boundaries), so always guard.

### `chartXAxis` modifier (macOS 13+, HIGH confidence)

```swift
.chartXAxis {
    AxisMarks(values: .stride(by: 6)) { ... }
}
```

Replaces the default X-axis rendering entirely. When `values:` is provided, only those positions receive marks. Combined with `.chartXScale(domain: 0...23)` (already present on hourlyChart), Charts constrains mark placement to the domain.

---

## Integration with Existing Design Tokens

| Token | Value | Usage in fixes |
|-------|-------|----------------|
| `Typography.decorativeIcon` | 9pt | Month labels on 12M chart, hour labels on 24H chart — matches Y-axis |
| `Typography.monoTiny` | 10pt mono | Currently on monthly/daily charts — can stay on dailyChart (7 labels = less crowded) |
| `Spacing.section` | 8pt | Normalize MetricToggleView bottom padding |
| `Spacing.gap` | 6pt | Source of asymmetry in MetricToggleView — replace with `section` |
| `Layout.chartHeight` | 50pt | Fixed chart height — axis labels render in the reserved space below |

---

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| `AxisValueLabel(orientation: .vertical)` | Label rotation at 9pt produces illegible glyphs in a 50pt-tall chart | 3-letter abbreviation at 9pt horizontal |
| `desiredCount:` on X-axis | Approximates — does not guarantee exactly 12 or exactly 4 marks | `stride` is deterministic |
| `chartXVisibleDomain` | For scrollable charts with panning; not applicable to fixed-width charts | N/A |
| `chartScrollableAxes` | Adds scroll interaction to a fixed-width glanceable chart | N/A |
| Persisting `todayHourCounts` to UserDefaults | Yesterday's hourly data shown as "today" would be misleading | Suppress false empty via `dailyActivity` fallback |
| New SPM dependencies | Project constraint: Sparkle + Apple frameworks only | All fixes use Apple framework APIs |

---

## Sources

- Apple Developer Documentation — Customizing axes in Swift Charts: https://developer.apple.com/documentation/charts/customizing-axes-in-swift-charts (HIGH confidence)
- WWDC22 "Swift Charts: Raise the bar": https://developer.apple.com/videos/play/wwdc2022/10137/ — stride by calendar component (HIGH confidence)
- Apple Developer Forums — Swift Charts: https://developer.apple.com/forums/tags/swift-charts — Int-axis stride confirmed (MEDIUM confidence)
- "Mastering charts in SwiftUI. Customizations." (Majid Jabrayilov): https://swiftwithmajid.com/2023/02/15/mastering-charts-in-swiftui-customizations/ — AxisMarkBuilder closure API (MEDIUM confidence)
- Codebase analysis (PRIMARY source, HIGH confidence): `InsightsCharts.swift`, `ActivityChartView.swift`, `ActivityChartData.swift`, `UsageBarsSection.swift`, `MetricToggleView.swift`, `StyledDivider.swift`, `Spacing.swift`, `Typography.swift`, `UsageGateViews.swift`

---
*Stack research for: AIBattery v1.14 Visual Polish milestone — chart label and spacing fixes*
*Researched: 2026-03-24*
