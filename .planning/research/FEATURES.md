# Feature Research

**Domain:** Compact chart label readability — macOS menu bar utility (v1.14 Visual Polish)
**Researched:** 2026-03-24
**Confidence:** HIGH (codebase audit + Swift Charts docs + data visualization patterns)

---

## Context: What This Milestone Fixes

This is a scoped milestone — the app is feature-complete at v1.14. The three active issues are:

1. **12M chart month labels squished/illegible** — `AxisMarks(values: dates)` passes all 12 `Date`
   values and renders 3-char "MMM" labels (e.g. "Jan") for every one. At `chartHeight = 50pt` width,
   12 × ~24pt labels (~288pt) overflow a ~300pt chart. Swift Charts clips or squishes them.

2. **24H chart hour labels unevenly spaced** — `values: [0, 4, 8, 12, 16, 20, 23]` creates gaps of
   4, 4, 4, 4, 4, **3** — the trailing `23` is 3 offsets from `20`, not 4. This makes the last
   segment visually narrower than the rest.

3. **24H chart false "No activity" after app update** — `isEmpty` checks
   `todayHourCounts.values.allSatisfy { $0 == 0 }`. On app launch, `todayHourCounts` is populated
   from the ViewModel's last fetch/refresh cycle. If the refresh hasn't completed yet (or the
   ViewModel hydrates from cache), the dict starts empty even though JSONL activity exists.

4. **Rate limit section uneven vertical padding** — separate layout issue, not chart-related.

---

## Existing Chart Infrastructure (Do Not Re-Implement)

- `ActivityChartData.hourlyData()` — generates `HourlyPoint(offset:, hour:, count:)` for offsets 0–23
- `ActivityChartData.monthlyData()` — generates `MonthlyPoint(key:, date:, count:)` for 12 months
- `InsightsView.formatHourLabel(_:)` — formats `Int` hour as `"00"–"23"` (zero-padded 24h)
- `InsightsView.monthAbbrev(_:)` — formats `Date` as `"Jan"`, `"Feb"`, etc. via `DateFormatters.shortMonth`
- `DateFormatters.shortMonth` — `DateFormatter` with `dateFormat = "MMM"` (3-char locale-stable)
- Hover tooltips on all three chart modes already work
- `Layout.chartHeight = 50pt` — the chart is genuinely small; labels fight for ~300pt width

---

## Feature Landscape

### Table Stakes (Users Expect These)

Features users assume exist in any chart widget. Missing these = chart feels broken.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Evenly-spaced axis labels | Visual rhythm communicates equal time intervals; uneven spacing implies data gaps | LOW | Fix 24H by using `[0, 6, 12, 18]` (4 labels, uniform 6-offset gaps) instead of `[0, 4, 8, 12, 16, 20, 23]` |
| No label collision on 12-month chart | Dense labels are unreadable; worse than no labels | LOW | Show every-3rd month (4 labels: Jan/Apr/Jul/Oct or similar quarterly) OR switch to single-char narrow format ("J","F","M"...) |
| Consistent label format within a chart | Mixing "Jan" and "J" in the same axis is disorienting | LOW | Pick one format per mode and apply uniformly |
| Labels that survive chart resize | Menu bar popovers have fixed width — labels must not overflow at `chartHeight = 50pt` | LOW | Narrow/single-char format is safe; 3-char "MMM" at 12 ticks is not |
| No false empty state | If data exists anywhere in the window, the chart should show data not "No activity" | MEDIUM | Fix: also check `cachedHourly` (already computed) OR delay empty-state rendering until first refresh completes |
| Hour labels show recognizable time-of-day | "00", "06", "12", "18" (or "12am", "6am", "12pm", "6pm") — users need to orient the 24h span | LOW | Current `formatHourLabel` produces "00"–"23"; that's fine. The fix is choosing the right 4 offsets, not the format |

### Differentiators (Nice to Have Within Scope)

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Single-char month labels for 12M ("J F M A M J J A S O N D") | Maximum density without collision; matches iOS Widget / Fitness chart convention | LOW | `DateFormatter` with `dateFormat = "MMMMM"` produces single initial; some months share initials (J for Jan/Jun/Jul) but context makes them clear by position |
| Quarter markers only for 12M (4 labels) | Clearest hierarchy — shows macro trend without noise | LOW | Show labels only at months 0, 3, 6, 9 (Jan, Apr, Jul, Oct) of the 12-slot window. Does not depend on actual calendar month. |
| Midnight/noon highlights for 24H | Anchoring "12" (noon) and "00" (midnight) labels in a slightly different weight helps users orient | LOW | Can use different font weight or color in `AxisValueLabel` for offset == 0 (midnight bucket) and offset ~= 12 (noon bucket) |

### Anti-Features (Avoid These)

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Show all 12 month labels | "Show all data" instinct | Guaranteed collision at 50pt height; unreadable | 4-label quarterly strategy or single-char initials |
| Show all 24 hour labels | Complete time axis | 24 labels × ~18pt each = 432pt on a ~300pt chart | 4 labels at 6-hour intervals |
| Rotate labels 45° | "Fix collision without hiding labels" | Increases chart height requirement; breaks compact layout; unusual for menu bar widgets | Fewer labels or shorter format |
| Use `Date`-typed x-axis for hourly chart | Allows `stride(by: .hour, count: 6)` | Requires converting offset-based `HourlyPoint.id` to `Date`; adds complexity and test surface to a working architecture | Keep `Int` domain; manually specify `values: [0, 6, 12, 18]` — simpler and already correct |

---

## Feature Dependencies

```
Fix 12M labels
    └──uses──> DateFormatters.shortMonth (existing, no change needed for 3-char)
    └──OR uses──> new single-char formatter (MMMMM format) added to DateFormatters
    └──requires──> change AxisMarks values from all 12 dates → every-3rd date (or [0,3,6,9] index)

Fix 24H labels
    └──uses──> existing formatHourLabel (no change)
    └──requires──> change values: [0, 4, 8, 12, 16, 20, 23] → [0, 6, 12, 18]
    └──no data model changes

Fix 24H false empty state
    └──uses──> existing cachedHourly (already computed on onAppear)
    └──requires──> change isEmpty check to also consult cachedHourly
    └──OR requires──> add a "loading" flag that prevents empty-state render until first refresh

Fix rate limit spacing
    └──independent of all chart fixes
    └──requires──> audit VStack padding in rate limit section views
```

### Dependency Notes

- **12M label fix does not require data model changes.** `MonthlyPoint.date` is already a `Date`; only the `AxisMarks` `values:` argument and label format need changing.
- **24H label fix is purely cosmetic.** `HourlyPoint.offset` drives the x-axis; changing which offsets get labels has no data or performance implications.
- **False empty state fix is independent of label fixes.** It touches `InsightsView.isEmpty` (a computed property) or the rendering guard, not the `AxisMarks` configuration.
- **Rate limit spacing fix is fully independent** — separate views, no shared code with charts.

---

## Implementation Patterns (Table Stakes for Compact Charts)

Research across Swift Charts docs, mobile.blog WWDC implementation notes, and Carbon Design System
establishes these as standard practice for small/compact chart contexts:

### 12-Month Label Patterns

| Pattern | Labels Shown | Format | Used By |
|---------|-------------|--------|---------|
| **Quarterly (recommended)** | 4 (every 3rd month) | "Jan", "Apr", "Jul", "Oct" | Most dashboard/widget charts |
| **Single-char initials** | All 12 | "J", "F", "M", "A", "M", "J", "J", "A", "S", "O", "N", "D" | iOS Fitness, Apple Watch Activity |
| **Every 2nd month** | 6 | "Jan", "Mar", "May", etc. | Moderate density, still risk collision at tiny sizes |
| **First + last only** | 2 | "Apr 2025", "Mar 2026" | Sparkline-style, no axis ticks |

Quarterly (4 labels) is the best fit for AIBattery: clear, readable at 50pt, and provides enough
reference points to orient the 12-bar span without cognitive load.

### 24-Hour Label Patterns

| Pattern | Labels | Offsets | Spacing |
|---------|--------|---------|---------|
| **6-hour intervals (recommended)** | 4 | 0, 6, 12, 18 | Uniform 6 |
| **4-hour intervals** | 6 | 0, 4, 8, 12, 16, 20 | Uniform 4 (crowded at 50pt) |
| **8-hour intervals** | 3 | 0, 8, 16 | Uniform 8 (too sparse) |
| **Midnight + noon only** | 2 | 0, 12 | Sparkline-style |

**Key insight:** "6 hours" maps cleanly to midnight/6am/noon/6pm — the four natural human
time anchors. Users immediately recognize these without reading the labels. This is the standard
used in Apple's own weather, Fitness, and Clock apps for compact 24h displays.

**Current bug:** `[0, 4, 8, 12, 16, 20, 23]` has a trailing gap of 3 (20→23 = 3 offsets) because
`offset 23` is the last data point, not a time boundary. The fix is `[0, 6, 12, 18]` — four clean
offsets within the 0–23 domain that are equidistant.

### False Empty State Pattern

The standard pattern for widgets and compact charts: **do not render the empty state until the first
data fetch has completed**. Show a loading placeholder or nothing (not "No activity") while initial
data loads.

In AIBattery's case, `todayHourCounts` is populated from a ViewModel refresh, but the `isEmpty`
check runs in the view render path before the async refresh completes. Options:

1. **Check `cachedHourly` instead of `todayHourCounts`** — `cachedHourly` is computed from
   `todayHourCounts` via `onAppear`, so if `cachedHourly` is empty AND `todayHourCounts` is empty,
   the data may not have loaded yet. But this doesn't solve the root problem.

2. **Add a `isDataLoaded` flag** — set to `true` after first `refreshCachedData()` completes.
   Gate the empty-state render on `isDataLoaded`. This is the cleaner fix: never show "No activity"
   before the first refresh cycle.

3. **Check JSONL-based data directly** — `dailyActivity` is populated from JSONL (not the API
   call), so it may be non-empty even when `todayHourCounts` is still zeroed. The 24H mode could
   fall back to checking `dailyActivity` for today's date when `todayHourCounts` is empty on first
   render.

Option 2 is the table-stakes pattern. Option 3 is a bonus fallback.

---

## MVP Definition

Since this is a scoped fix milestone, "MVP" means: all three active issues resolved cleanly.

### Must-Fix (v1.14 — all three issues)

- [ ] **12M labels** — show 4 quarterly labels, not all 12. Use existing 3-char "MMM" format or
  single-char initials. Either works; 4-label quarterly is more readable.
- [ ] **24H labels** — change `values: [0, 4, 8, 12, 16, 20, 23]` to `values: [0, 6, 12, 18]`.
  Labels already use `formatHourLabel` correctly — only the offsets need fixing.
- [ ] **24H false empty state** — add `isDataLoaded` guard or equivalent; suppress "No activity"
  until after first `refreshCachedData()` completes.
- [ ] **Rate limit spacing** — audit and equalize vertical padding in rate limit section.

### Not In Scope

- Label animation or transitions — the chart already uses `.animation(MotionConstants.standard)`
- Y-axis label changes — `sharedYAxis` with `desiredCount: 3` is working correctly
- Tooltip changes — hover tooltips are working correctly
- Data model changes — `HourlyPoint`, `MonthlyPoint`, `DailyPoint` structs unchanged

---

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Fix 24H label spacing | HIGH (current spacing looks broken) | LOW (1-line change) | P1 |
| Fix 12M label collision | HIGH (currently unreadable) | LOW (filter values list, same formatter) | P1 |
| Fix 24H false empty state | HIGH (misleads user into thinking no data) | LOW-MEDIUM (add loaded flag) | P1 |
| Fix rate limit vertical spacing | MEDIUM (cosmetic inconsistency) | LOW (padding audit) | P1 |

---

## Sources

- Apple Swift Charts WWDC22 — [Raise the bar](https://developer.apple.com/videos/play/wwdc2022/10137/)
- [Customizing axes in Swift Charts — Apple Developer Documentation](https://developer.apple.com/documentation/charts/customizing-axes-in-swift-charts)
- [An Adventure with Swift Charts — mobile.blog](https://mobile.blog/2022/07/04/an-adventure-with-swift-charts/) — "Today: 5-hour intervals; This year: 3-month intervals" pattern
- [Mastering charts in SwiftUI: Customizations — Swift with Majid](https://swiftwithmajid.com/2023/02/15/mastering-charts-in-swiftui-customizations/) — conditional `AxisTick`/`AxisValueLabel` per value
- [Yellowfin BI — Chart Axis Best Practices](https://www.yellowfinbi.com/best-practice-guide/charts-visualizations/chart-axis-best-practices) — "Don't label every tick mark"
- Codebase audit: `InsightsCharts.swift`, `ActivityChartData.swift`, `InsightsRowsAndHover.swift`, `DateFormatters.swift`, `Spacing.swift`

---

*Feature research for: chart label readability and layout fixes (v1.14 Visual Polish)*
*Researched: 2026-03-24*
