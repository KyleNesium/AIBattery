# Architecture Research

**Domain:** macOS menu bar app — chart label readability, false empty states, layout spacing
**Researched:** 2026-03-24
**Confidence:** HIGH (derived entirely from live codebase — no external research needed)

## System Overview

The three target issues each live in a different layer. The chart label and false empty-state fixes
are contained within the InsightsView extension cluster. The spacing fix is in `UsageBarsSection.swift`
and touched by the `Spacing` design token system.

```
┌─────────────────────────────────────────────────────────────────┐
│                   Issue → File Map                               │
│                                                                  │
│  12M label squish  ──→  InsightsCharts.swift (monthlyChart)     │
│  24H label spacing ──→  InsightsCharts.swift (hourlyChart)      │
│  24H false empty   ──→  ActivityChartView.swift (isEmpty)       │
│                         + InsightsGate (UsageGateViews.swift)   │
│                         + todayHourCounts data flow             │
│  Rate limit vpad   ──→  UsageBarsSection.swift                  │
│                         + Spacing.swift (design token)          │
└─────────────────────────────────────────────────────────────────┘
```

## Component Responsibilities — Milestone Scope

| Component | File | Role in This Milestone |
|-----------|------|------------------------|
| `InsightsView` | `ActivityChartView.swift` | Struct declaration, `isEmpty` computed var, `todayHourCounts` usage |
| `InsightsView` (chart extension) | `InsightsCharts.swift` | `hourlyChart` and `monthlyChart` — contains the broken x-axis label configs |
| `InsightsView` (formatter extension) | `InsightsRowsAndHover.swift` | `formatHourLabel` — currently returns "HH" zero-padded strings |
| `ActivityChartData` | `ActivityChartData.swift` | `hourlyData(from:now:)` — produces `HourlyPoint.hour` values consumed by label |
| `InsightsGate` | `UsageGateViews.swift` | Controls whether `InsightsView` is even shown; current gate may hide chart when `todayHourCounts` is empty |
| `UsageAggregator` | `UsageAggregator.swift` | Builds `todayHourCounts` from JSONL `todayEntries` — the root of the false empty-state bug |
| `UsageSnapshot` | `UsageSnapshot.swift` | Stores `todayHourCounts: [String: Int]` — passed through as-is |
| `FiveHourBarSection` | `UsageBarsSection.swift` | Applies `.padding(.vertical, Spacing.section)` — spacing to audit |
| `SevenDayBarSection` | `UsageBarsSection.swift` | Same padding as above |
| `Spacing` | `Utilities/Spacing.swift` | `Spacing.section = 8pt` — token used by all three bar sections |

## Fix 1: 12M Month Labels Squished

### Root Cause

`monthlyChart` in `InsightsCharts.swift` (line 217) uses:

```swift
.chartXAxis {
    AxisMarks(values: dates) { value in
        AxisValueLabel {
            if let date = value.as(Date.self) {
                Text(Self.monthAbbrev(date))
                    .font(Typography.monoTiny)
            }
        }
    }
}
```

`dates` is all 12 `MonthlyPoint.date` values — `AxisMarks(values: dates)` forces the chart to render
a label at every month position. With 12 months squeezed into a 275pt wide, 50pt tall chart, the labels
physically cannot fit without overlapping.

### Fix Surface

**File: `InsightsCharts.swift`** — `monthlyChart` computed var, `.chartXAxis` block only.

**Options (in order of preference):**

1. **Stride by 2 or 3** — `AxisMarks(values: stride(from: 0, to: 12, by: 3).map { dates[$0] })` shows
   4 labels (Jan, Apr, Jul, Oct style) with visible gaps. Simple, readable.

2. **Let Charts decide** — `AxisMarks(values: .automatic(desiredCount: 4))` with a custom label
   formatter. Relies on Charts framework picking reasonable months.

3. **Keep all 12, rotate** — not practical at 50pt height; rotation cuts off vertically.

**Recommendation: option 1** — stride by 3 gives 4 evenly spaced labels (every quarter), preserving
chart context without overlap. The chart shape communicates trend; 4 anchor labels are sufficient.

**No changes needed in:**
- `ActivityChartData.monthlyData` — data structure is correct
- `InsightsRowsAndHover.monthAbbrev` — formatter is correct
- `Spacing`, `Layout`, `Typography` — no token changes needed

## Fix 2: 24H Hour Labels Unevenly Spaced

### Root Cause

`hourlyChart` in `InsightsCharts.swift` (line 150) uses:

```swift
.chartXAxis {
    AxisMarks(values: [0, 4, 8, 12, 16, 20, 23]) { value in
```

The values `[0, 4, 8, 12, 16, 20, 23]` have consistent 4-step gaps except the last: `20 → 23` is
only 3 steps. This creates a visually cramped final label. The domain is `0...23` (set via
`.chartXScale(domain: 0...23)`).

The x-axis maps integer `offset` (0–23) not hour-of-day. `offset` 0 = the oldest hour in the trailing
window, `offset` 23 = the current hour. The label text comes from `data[offset].hour` — the actual
wall-clock hour.

### Fix Surface

**File: `InsightsCharts.swift`** — `hourlyChart` computed var, `AxisMarks(values:)` literal only.

**Fix:** Replace `[0, 4, 8, 12, 16, 20, 23]` with `[0, 4, 8, 12, 16, 20]` (6 labels, perfectly even
4-step spacing). Dropping the `23` is the minimal change — the current-hour label is redundant given
the chart domain visually communicates "now" at the right edge. Alternatively `stride(from: 0, to: 24, by: 6)`
gives 4 labels (0, 6, 12, 18) — even simpler.

**Recommendation:** Use `Array(stride(from: 0, through: 20, by: 4))` = `[0, 4, 8, 12, 16, 20]`.
Six labels, 4-step spacing throughout, no trailing gap irregularity.

**No changes needed in:**
- `ActivityChartData.hourlyData` — produces correct offset→hour mapping
- `InsightsRowsAndHover.formatHourLabel` — zero-pads correctly (e.g. "04", "08")
- Any other file

## Fix 3: 24H False "No Activity" After App Update

### Root Cause (data flow trace)

`InsightsView.isEmpty` (in `ActivityChartView.swift`) for `.hourly` mode is:

```swift
case .hourly: return todayHourCounts.values.allSatisfy { $0 == 0 }
```

`todayHourCounts` comes from `UsageSnapshot.todayHourCounts`, which is built in `UsageAggregator`:

```swift
var todayHourCounts: [String: Int] = [:]
for entry in todayEntries {
    let hour = String(calendar.component(.hour, from: entry.timestamp))
    todayHourCounts[hour, default: 0] += 1
}
```

`todayEntries` is populated from JSONL entries where `ts >= today` (start of current day).

**The bug:** After an app update, `SessionLogReader` cache is cold. The aggregator runs before JSONL
files are fully scanned — `todayEntries` is empty → `todayHourCounts` is `[:]` → `isEmpty` returns
`true` → false "No activity" is shown.

The `isEmpty` check uses `allSatisfy { $0 == 0 }` on values. An **empty dictionary** trivially satisfies
`allSatisfy`, returning `true`. So an empty `todayHourCounts` and an all-zero `todayHourCounts` are
treated identically — both show the empty state. The fix is to distinguish "no data yet" from "data
confirmed zero."

**Additional data-flow note:** `InsightsGate` also gates on `!snapshot.todayHourCounts.isEmpty` —
if `todayHourCounts` is empty, `InsightsGate` can hide the entire `InsightsView`. However, the gate
condition is actually:

```swift
if !snapshot.dailyActivity.isEmpty || !snapshot.todayHourCounts.isEmpty || snapshot.totalTokens > 0
```

So if `dailyActivity` has entries (which it does for existing users from `stats-cache.json`), the
gate shows `InsightsView` regardless. The false empty state is in `InsightsView.isEmpty`, not the gate.

### Fix Surface

**Option A (simplest): Special-case empty dict in `isEmpty`**

In `ActivityChartView.swift`, change `isEmpty` for `.hourly`:

```swift
case .hourly:
    // Empty dict = data not yet loaded; show chart rather than empty state
    if todayHourCounts.isEmpty { return false }
    return todayHourCounts.values.allSatisfy { $0 == 0 }
```

This makes "no JSONL data loaded yet" show a flat chart (all zeros) rather than the empty state.
A flat chart with 24 zero-height bars is honest: the window exists, we just have no messages yet today.

**Option B: Persist `todayHourCounts` in `StatsCache` / `UserDefaults`**

Store yesterday's and today's hourly data in a persistent cache so the chart pre-populates on launch.
This is heavier — `StatsCache` does not currently store `todayHourCounts` separately from `hourCounts`.

**Recommendation: Option A.** The false empty state is a presentation-layer bug — the distinction
between "empty dict" and "all-zero values" is entirely within `ActivityChartView.swift`. No data model
changes, no persistence changes, one-line fix in `isEmpty`. The flat chart on first load is semantically
correct: we have no recorded messages this hour, which is different from "no data exists."

**Files touched:** `ActivityChartView.swift` only — `isEmpty` computed var.

**No changes needed in:**
- `UsageAggregator` — `todayHourCounts` is built correctly from available JSONL
- `UsageSnapshot` — storage is correct
- `InsightsGate` — gate condition is already permissive for existing users
- `ActivityChartData.hourlyData` — handles empty input correctly (returns 24 zero-count points)

## Fix 4: Rate Limit Sections Uneven Vertical Spacing

### Root Cause

`FiveHourBarSection` and `SevenDayBarSection` in `UsageBarsSection.swift` both use:

```swift
.padding(.horizontal, Spacing.sectionHorizontal)
.padding(.vertical, Spacing.section)
```

`Spacing.section = 8pt`. This is the outer section padding. The MetricToggleView above the rate limit
bars and the `StyledDivider` between sections use different implicit spacing, creating visual
inconsistency between the auto mode section and the 5h/7d sections.

The "auto mode" section is `MetricToggleView`, which uses its own internal padding. The `StyledDivider`
between sections uses `Spacing.tight` (2pt) vertically. The rate limit sections' 8pt top + 8pt bottom
padding then stacks with the divider's 2pt, producing different inter-section gaps depending on which
sections are adjacent.

### Fix Surface

This requires understanding the actual visual output to determine what gap sizes are causing the
unevenness. The architectural options are:

**Option A: Audit and normalize via existing tokens**

Check the actual rendered spacing: `MetricToggleView` internal padding + `StyledDivider` 2pt padding +
`FiveHourBarSection` 8pt top padding. If the gap between MetricToggleView and FiveHourBarSection
differs from the gap between FiveHourBarSection and SevenDayBarSection, the fix is to adjust one
section's padding.

**Option B: Extract a new `Spacing` token**

If the desired section gap requires a value not currently in the token system (e.g., 6pt vertical
instead of 8pt), add it to `Utilities/Spacing.swift` and update the affected padding calls.

**Files touched:** `UsageBarsSection.swift` (padding adjustments) and possibly `Utilities/Spacing.swift`
(new or adjusted token). Always update `spec/CONSTANTS.md` when changing design token values.

**Constraint:** Any change to `Spacing.section` affects all 8+ consumers of that token globally
(verified via grep: `UsageBarsSection`, `InsightsView`, error view, footer, etc.). If only the rate
limit sections need adjustment, use a new token or a local literal rather than changing the global token.

## Data Flow: `todayHourCounts` Lifecycle

This traces the full pipeline for the false empty-state fix:

```
JSONL files (~/.claude/projects/*/[session].jsonl)
    ↓ FileHandle streaming (SessionLogReader.readAllUsageEntries)
    ↓ [off main thread, @unchecked Sendable + NSLock]
UsageAggregator.aggregate(rateLimits:accountId:)
    ↓ Filters entries where ts >= today
    todayEntries: [AssistantUsageEntry]
    ↓ Groups by calendar.component(.hour)
    todayHourCounts: [String: Int]  ← key is "0"..."23" (not zero-padded)
    ↓
UsageSnapshot(todayHourCounts: todayHourCounts)
    ↓ @Published on UsageViewModel
InsightsGate → InsightsView(todayHourCounts: snapshot.todayHourCounts)
    ↓ @State cachedHourly (via ActivityChartData.hourlyData)
    ↓ isEmpty check (bug lives here)
    hourlyChart or "No activity" empty state
```

**Key invariant:** `ActivityChartData.hourlyData(from: hourCounts)` always returns exactly 24 points
regardless of input — missing hours default to count 0. So an empty `todayHourCounts` dict produces
a valid 24-point array of all-zero counts. The chart would render (flat line at y=0), but `isEmpty`
short-circuits rendering before `hourlyData` is ever called.

**AppStorage persistence note:** `cachedHourly` is `@State`, not `@AppStorage`. It does not persist
across app launches. Every cold start recomputes from JSONL. The fix (Option A) embraces this — rather
than adding persistence, it simply shows the flat chart while JSONL loads.

## Integration Points: New vs. Modified

| Change | File | New or Modified |
|--------|------|-----------------|
| 12M axis label stride | `AIBattery/Views/InsightsCharts.swift` | **Modified** — `monthlyChart` `.chartXAxis` block |
| 24H axis label values | `AIBattery/Views/InsightsCharts.swift` | **Modified** — `hourlyChart` `AxisMarks(values:)` literal |
| 24H false empty state | `AIBattery/Views/ActivityChartView.swift` | **Modified** — `isEmpty` computed var, `.hourly` case |
| Rate limit spacing | `AIBattery/Views/UsageBarsSection.swift` | **Modified** — `.padding(.vertical, ...)` on bar sections |
| New spacing token (if needed) | `AIBattery/Utilities/Spacing.swift` | **Modified** — add token only if needed |
| Spec sync | `spec/CONSTANTS.md` and/or `spec/UI_SPEC.md` | **Modified** — required per project convention |

## Suggested Build Order

Dependencies between the four fixes are minimal — each is isolated. Suggested order minimizes
review risk:

1. **24H false empty state** (`ActivityChartView.swift`) — one-line change, highest user impact,
   zero risk of visual regression. Fix and test first.

2. **24H label spacing** (`InsightsCharts.swift`) — literal array change, zero logic risk.
   Single line in `hourlyChart`.

3. **12M label squish** (`InsightsCharts.swift`) — same file as fix 2, same pattern.
   Change `AxisMarks(values: dates)` to strided subset.

4. **Rate limit spacing** (`UsageBarsSection.swift` + possibly `Spacing.swift`) — audit actual
   rendered spacing first, then adjust padding. This fix requires visual inspection to confirm
   correctness; do it last so chart fixes can be confirmed independently.

**Spec sync goes last** — after all four fixes are confirmed correct, update `spec/CONSTANTS.md`
and `spec/UI_SPEC.md` in a single commit. Update `spec/DATA_LAYER.md` only if `UsageSnapshot` or
`UsageAggregator` changes (they should not for the recommended fix paths).

## Anti-Patterns to Avoid

### Anti-Pattern 1: Adding @AppStorage to Cache `todayHourCounts`

**What people do:** Persist `todayHourCounts` to `UserDefaults` so the chart is non-empty on first load.
**Why it's wrong:** `todayHourCounts` is per-account, time-bounded (resets each day), and derived from
JSONL. Persisting it adds stale-data risk. The empty-dict distinction fix (Option A) is the right
approach — it is zero-cost and semantically correct.
**Do this instead:** Fix `isEmpty` to treat empty dict as "not yet loaded" rather than "truly empty."

### Anti-Pattern 2: Changing `Spacing.section` to Fix Rate Limit Spacing

**What people do:** Change `Spacing.section` from 8pt to 6pt to reduce rate limit bar padding.
**Why it's wrong:** `Spacing.section` is used in 8+ places. Narrowing it globally would reduce
padding in `InsightsView`, the error view, and the inline error banner — all of which may look correct
at 8pt.
**Do this instead:** Audit which specific gap is uneven, then either add a targeted padding override
on the affected section or introduce a new named token (`Spacing.sectionCompact` or similar) that
is used only where the tighter padding is needed.

### Anti-Pattern 3: Extending `ActivityChartData` for the False Empty Fix

**What people do:** Add a `hasData` flag to `HourlyPoint` or add an `isEmpty` method to `ActivityChartData`.
**Why it's wrong:** The presentation-layer distinction (empty dict vs all-zero values) belongs in
the view. `ActivityChartData` is a pure data transformation layer — it should not carry view-state semantics.
**Do this instead:** Fix the `isEmpty` computed var in `ActivityChartView.swift`. The data layer does not change.

### Anti-Pattern 4: Adding a PointMark to hourlyChart to "Fix" Empty Display

**What people do:** Add `PointMark` at (0, 0) to prevent the chart from showing as empty.
**Why it's wrong:** This is a workaround that changes data semantics (falsely shows a data point).
The correct fix is one line in the `isEmpty` check, not a phantom data point.
**Do this instead:** Fix `isEmpty`.

## Constraints

- `hourlyChart` uses `AxisMarks(values: [0, 4, 8, 12, 16, 20, 23])` with `Int` typed axis values.
  The axis domain is `0...23` (offsets). Labels call `data[offset].hour` to get the wall-clock hour.
  Any change to the `values` array must stay within `0...23` range and index `data` safely.

- `monthlyChart` passes all 12 `Date` values as `AxisMarks(values: dates)`. The chart renders
  the `Date`-typed x-axis natively. Striding requires subsetting the `dates` array — no type changes.

- `Spacing.section` is used in `FiveHourBarSection`, `SevenDayBarSection`, `InsightsView`,
  `PopoverFooterView`, `PopoverHeaderView`, and inline error display. Any change to the token is global.

- Tests for `ActivityChartData` exist in `ActivityChartTests` (if present) and `UsageAggregatorTests`.
  The `isEmpty` fix is in `ActivityChartView.swift` (a view) — views are not currently directly tested.
  The fix is a guard clause change, not logic change; no new tests strictly required, but a behavioral
  note in `UsageAggregatorTests` may clarify the empty-dict contract.

## Sources

- `/Users/kyle/workspace/Github/KyleNesium/AIBattery/AIBattery/Views/InsightsCharts.swift`
- `/Users/kyle/workspace/Github/KyleNesium/AIBattery/AIBattery/Views/ActivityChartView.swift`
- `/Users/kyle/workspace/Github/KyleNesium/AIBattery/AIBattery/Views/InsightsRowsAndHover.swift`
- `/Users/kyle/workspace/Github/KyleNesium/AIBattery/AIBattery/Views/ActivityChartData.swift`
- `/Users/kyle/workspace/Github/KyleNesium/AIBattery/AIBattery/Views/UsageGateViews.swift`
- `/Users/kyle/workspace/Github/KyleNesium/AIBattery/AIBattery/Views/UsageBarsSection.swift`
- `/Users/kyle/workspace/Github/KyleNesium/AIBattery/AIBattery/Services/UsageAggregator.swift`
- `/Users/kyle/workspace/Github/KyleNesium/AIBattery/AIBattery/Models/UsageSnapshot.swift`
- `/Users/kyle/workspace/Github/KyleNesium/AIBattery/AIBattery/Utilities/Spacing.swift`
- `/Users/kyle/workspace/Github/KyleNesium/AIBattery/spec/CONSTANTS.md`
- `/Users/kyle/workspace/Github/KyleNesium/AIBattery/.planning/PROJECT.md`

---
*Architecture research for: AIBattery v1.14 Visual Polish — chart labels, false empty states, layout spacing*
*Researched: 2026-03-24*
