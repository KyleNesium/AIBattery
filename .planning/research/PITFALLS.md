# Pitfalls Research

**Domain:** Swift Charts axis labels, hourly data persistence, VStack spacing in macOS menu bar popovers
**Researched:** 2026-03-24
**Confidence:** HIGH (derived from direct codebase inspection of the three specific fix areas)

---

## Critical Pitfalls

### Pitfall 1: Swift Charts `AxisMarks(values:)` Does Not Control Tick Spacing — Domain Padding Does

**What goes wrong:**
The monthly chart uses `.chartXAxis { AxisMarks(values: dates) }` with 12 `Date` values. Swift Charts infers the domain from the data and adds automatic padding on both ends of a continuous time axis. This padding shifts tick positions away from the edges, causing uneven spacing between the first two and last two months relative to the interior months. On the 275pt popover, 12 labels with uneven spacing means the leftmost and rightmost labels can render partially outside the plot area and get clipped.

**Why it happens:**
`AxisMarks(values:)` controls which values receive labels — it does not pin those values to specific pixel positions. Tick position is determined by the underlying scale domain, which Charts inflates with automatic edge padding for continuous axes (`.month` unit). Developers assume providing explicit values gives full control over position, but position and label selection are separate concerns in Swift Charts.

**How to avoid:**
Add `.chartXScale(domain: dates.first!...dates.last!)` to suppress automatic domain padding and force the scale to start and end at the actual data bounds. Alternatively, use categorical string X values (month abbreviation as the axis value) — categorical axes have no domain padding concept and force uniform spacing. The categorical approach is simpler for a fixed 12-slot chart.

**Warning signs:**
- First or last month label is partially clipped when checking in a real popover window
- Adding or removing a month entry shifts all label positions
- Xcode canvas shows correct layout but the running app clips labels (canvas renders at different width)

**Phase to address:** 12M chart label fix phase.

---

### Pitfall 2: `todayHourCounts` Is Built Exclusively From JSONL `todayEntries` — No Persistence, No Fallback

**What goes wrong:**
`UsageAggregator.aggregate()` builds `todayHourCounts` by iterating `todayEntries` — entries whose timestamp is `>= today`. After an app restart or Sparkle update, the first call to `aggregate()` in `UsageViewModel.init` (the fast-path cache warm-up at lines 36–49) runs before JSONL has been scanned for today. If `SessionLogReader` returns fewer entries than actually exist at that moment, `todayHourCounts` comes back empty.

The problem compounds: once `cachedSnapshot` is set with empty `todayHourCounts`, the fingerprint guard (`statsCacheModDate == lastStatsCacheModDate` etc.) keeps returning the cached snapshot for all subsequent calls — until a file change triggers `invalidate()`. The `dataFingerprint` in `InsightsView` uses `todayHourCounts.values.reduce(0, +)`, which equals `0` both before and after the false empty state, so even when the ViewModel does receive a snapshot update the view's `onChange` may not fire if the sums happen to match.

There is no persistence for `todayHourCounts`. `statsCache?.hourCounts` is an all-time peak-hour map, not today's distribution. No UserDefaults key stores today's hourly breakdown.

**How to avoid:**
Persist `todayHourCounts` in UserDefaults keyed by today's date string (e.g. `"todayHourCounts_2026-03-24"`). On `aggregate()`, merge the persisted map with the live-computed map using `max()` per hour bucket — the same pattern already used for the all-time `hourCounts` merge (`max(hourCounts[hour] ?? 0, count)`). Clear stale keys for previous dates on write. This gives the 24H chart correct data from the very first render after a restart.

As a secondary fix, add a `lastAggregatedDate: String` to the fingerprint check in `UsageAggregator`. If the current date string differs from the date at last aggregation, clear `cachedSnapshot` before the fingerprint guard — this forces a fresh scan on the first aggregate of each new day.

**Warning signs:**
- 24H chart shows "No activity" immediately after app launch/restart/update, then populates correctly after the next file write event (FileWatcher triggering `invalidate()`)
- `snapshot.todayHourCounts` is `[:]` while `snapshot.todayMessages > 0` in the same snapshot
- The false empty state duration equals the time between app launch and first new JSONL entry

**Phase to address:** 24H false empty state fix phase.

---

### Pitfall 3: The `dataFingerprint` Sum Collision Masks the Empty-State Bug and Can Mask the Fix

**What goes wrong:**
`InsightsView.dataFingerprint` combines `dailyActivity.count`, `snapshot?.totalMessages`, and `todayHourCounts.values.reduce(0, +)`. If `todayHourCounts` changes from `[:]` (sum=0) to a non-empty map with sum > 0, the fingerprint changes and the cache refreshes correctly. But if a persisted fallback is added that also starts with sum=0 (e.g. the previous day's data was accidentally loaded), the fingerprint does not change and the cached chart data is not refreshed.

More subtly: after adding UserDefaults persistence, the initial fingerprint from the first render may differ from the fingerprint after the real JSONL scan populates the snapshot. If the fix does not account for this, the chart could show stale cached data from the persist-restored snapshot.

**How to avoid:**
After implementing hourly persistence, explicitly test: (1) quit app mid-day with activity, (2) relaunch before any new JSONL is written, (3) open the 24H chart. Verify the chart shows the persisted data immediately. Then write a new message in Claude, wait for the refresh cycle, and verify the chart updates to include the new entry. The fingerprint must change in step 3.

**Warning signs:**
- Chart shows correct data on first open after restart (persistence working) but does not update after new activity (fingerprint not changing)
- `lastHourlyFingerprint` equals `dataFingerprint` even though `todayHourCounts` changed

**Phase to address:** 24H false empty state fix phase — include in the verification criteria.

---

### Pitfall 4: The 24H Axis `[0, 4, 8, 12, 16, 20, 23]` Creates a Narrower Final Interval

**What goes wrong:**
The explicit tick positions `[0, 4, 8, 12, 16, 20, 23]` with `.chartXScale(domain: 0...23)` create intervals of [4, 4, 4, 4, 4, **3**]. At a ~230pt plot width (275pt minus Y-axis labels), the final tick pair is visibly closer together than the rest. "23" appears crowded against the right edge.

**Why it happens:**
23 is not evenly divisible by any tick count that would produce a clean endpoint. The current values attempt to show "round hours plus the final hour" but the final gap is inevitably shorter.

**How to avoid:**
Use even-stride ticks that fit cleanly. Two options:
- `[0, 6, 12, 18]` — 4 labels, 6-hour stride, perfectly even, readable at 50pt chart height
- `[0, 4, 8, 12, 16, 20]` — 6 labels, 4-hour stride, even, but drops the 23:00 end anchor

The 6-hour stride (`[0, 6, 12, 18]`) is the better choice: fewer labels reduces crowding in the 50pt chart, and 6-hour intervals (midnight, 6am, noon, 6pm) are instantly recognizable to users.

**Warning signs:**
- The gap between the last two labels is visibly narrower than between any other adjacent pair
- The "23" label is flush against the trailing edge of the chart

**Phase to address:** 24H chart axis label fix phase (chart labels phase, same as 12M fix).

---

### Pitfall 5: Rate Limit Section Spacing — Dividers and Section Padding Compound Asymmetrically

**What goes wrong:**
`FiveHourBarSection` and `SevenDayBarSection` both apply `.padding(.vertical, Spacing.section)` (8pt) on the `UsageBar` wrapper. The `UsagePopoverView` main VStack uses `spacing: 0` with explicit `StyledDivider()` between sections. The visual gap between two bars is: 8pt (bottom of bar A) + divider height + 8pt (top of bar B) = ~17pt total.

The "uneven" appearance is most likely caused by the context health section having a different internal structure than the rate limit bars. When auto mode is active, `orderedModes` reorders sections dynamically. The section that appears first gets the same 8pt top padding, but the header content height differs between a `UsageBar` (3-line content: header + gauge + footer row) and `TokenHealthSection` (variable content height depending on session count). The padding is technically equal but the visual weight differs.

A secondary cause: `StyledDivider` itself may have non-zero vertical padding. If it does, the gap between sections that include a divider differs from sections that don't.

**How to avoid:**
First, confirm `StyledDivider` contributes 0pt of vertical padding beyond its 1pt line. Check its implementation — if it has `.padding(.vertical, Spacing.tight)` or similar, that adds 2–4pt per divider. Every divider adds this, making divider-separated sections have a larger gap than expected.

Second, verify all three section types (`FiveHourBarSection`, `SevenDayBarSection`, and `TokenHealthSection`) use identical vertical padding patterns: same token, same application point (on the outermost wrapper, not nested inside the content). Do not rely on token equality — verify the actual SwiftUI view hierarchy.

**Warning signs:**
- Measured gap between the 5h bar and its adjacent divider is larger than the gap between the 7d bar and its adjacent divider
- `StyledDivider` source shows any `.padding()` modifier
- `TokenHealthSection` has `.padding(.top, X)` in addition to `.padding(.vertical, Y)`

**Phase to address:** Rate limit spacing fix phase.

---

### Pitfall 6: Fixing Labels With Font Size Reduction Conflicts With the Minimum Font Audit

**What goes wrong:**
To fit 12 month labels in ~275pt width, a naive fix reduces the label font below `Typography.monoTiny` (the current smallest font token, set during v1.11's minimum font size audit). This conflicts with the audit's accessibility findings and the design token system.

**Why it happens:**
The axis label space is genuinely tight. 12 labels at 3 characters each, needing ~20pt per label, sum to 240pt — right at the edge for 275pt. Reducing font is the most obvious fix. But `Typography.monoTiny` is already the floor established by a deliberate audit.

**How to avoid:**
Do not reduce font size below `Typography.monoTiny`. Instead, fix the layout: pin the domain with `.chartXScale` to eliminate auto-padding (recovers ~10-15pt of wasted space at the edges), and keep the font token unchanged. If labels still clip after the domain fix, switch to a 2-character format (`"Ja"`, `"Fe"` etc.) rather than shrinking text.

**Warning signs:**
- A new `Typography` token appearing with a size smaller than `monoTiny`
- `.font(.system(size: N))` inline in `InsightsCharts.swift` where N < the `monoTiny` size
- Axis labels passing visual inspection on Retina but clipping on non-Retina displays

**Phase to address:** 12M chart label fix phase.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Hardcoded axis tick values `[0, 4, 8, 12, 16, 20, 23]` | Explicit control | Irregular spacing, invisible until screenshotted | Never — use a stride expression or uniform array |
| Building `todayHourCounts` from JSONL only, no persistence | Correct when JSONL is warm | False empty state on every restart/update | Never for a visible chart metric |
| No `.chartXScale` on the monthly chart | Less code | Domain auto-padding causes label clipping | Never when label count is tight |
| Adding `.padding(.vertical)` only to bar sections without auditing `TokenHealthSection` | Looks balanced in single-section test | Spacing diverges when auto mode changes section order | Never — audit all three sections together |

---

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| Swift Charts `AxisMarks(values:)` | Assuming it controls tick spacing | Also set `.chartXScale(domain:)` to suppress auto domain padding |
| Swift Charts monthly `.month` unit axis | Using `Date` values without a domain override | Pin domain: `.chartXScale(domain: firstDate...lastDate)` or use categorical string X values |
| `UsageAggregator` fingerprint cache | Adding UserDefaults persistence without accounting for the cached-snapshot guard | After adding persistence, verify `invalidate()` is called or the fingerprint actually changes when restored data differs from in-memory data |
| `dataFingerprint` in `InsightsView` | Sum-based fingerprint (`reduce(0, +)`) — two different hour distributions with equal sums compare equal | If the fix introduces a scenario where sum stays 0 but content changes (e.g. all hours become 0 after a day boundary), the fingerprint still correctly equals 0 — not a bug, but worth knowing |
| UserDefaults for `[String: Int]` | Writing directly as `Any` then reading as `[String: Int]` fails type check | Use `JSONEncoder/Decoder` or write as `NSDictionary` and cast — or store as `Data` with Codable |
| `StyledDivider` padding | Assuming divider is zero-height — it may have internal padding | Read `StyledDivider.swift` before diagnosing spacing inconsistencies |

---

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Writing `todayHourCounts` to UserDefaults on every `aggregate()` call | Disk write every polling cycle (30–300s) | Compare before writing: skip write if new map equals stored map | Immediately — continuous polling |
| Triggering a full JSONL rescan to rebuild hourly data when the fingerprint guard would have skipped it | Defeats the O(1) cache hit | Use the persisted map as the initial value in the aggregate, merge with JSONL-computed map (same as `hourCounts` merge pattern) | At every polling cycle |
| Using `.chartXScale` domain computed inline in the Chart body | Recalculates on every render pass | Compute in `ensureCachedData(for:)` or as a `let` before the `Chart { }` call | Any time the chart renders (hover, scroll, panel open) |

---

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| 24H shows "No activity" after app update | Trust erosion — user thinks data was lost | Persist `todayHourCounts` so data appears from first render |
| 12M clipped month labels | Time axis unreadable — defeats the chart | Pin domain + keep `monoTiny` font, or switch to 2-char format |
| Irregular 24H axis spacing at 20→23 | Visual irregularity draws the eye, feels broken | Use `[0, 6, 12, 18]` — 4 even labels |
| Uneven rate limit section spacing | Popover looks unpolished, builds distrust | Audit all sections simultaneously, not one at a time |

---

## "Looks Done But Isn't" Checklist

- [ ] **12M label fix:** Screenshot the running popover at default width (275pt). Confirm all 12 labels are visible and none are clipped. Xcode canvas is not sufficient — it may use a different layout width.
- [ ] **12M font size:** Confirm no font token smaller than `Typography.monoTiny` was introduced.
- [ ] **24H false empty state:** Test the restart scenario specifically: quit app mid-day with activity, relaunch without writing new JSONL, open 24H chart. It must show data.
- [ ] **24H axis spacing:** Verify equal inter-label gaps with `[0, 6, 12, 18]` or your chosen values. Count pixel distances in a screenshot, not just visual inspection.
- [ ] **Hourly persistence key:** Confirm old date keys are cleaned up on write (no unbounded UserDefaults growth).
- [ ] **`dataFingerprint` still triggers update:** After restart with persisted data, write a new message, wait for refresh, confirm chart adds the new data point.
- [ ] **`UsageSnapshot.==` completeness:** If any field is added to `UsageSnapshot` to support hourly persistence, verify it is included in the custom `==` implementation — omitting it causes the ViewModel to suppress updates.
- [ ] **Rate limit spacing:** Test all three `orderedModes` orderings (5h first, 7d first, context health first). Auto mode changes the order dynamically — spacing must be consistent regardless of order.
- [ ] **`StyledDivider` zero padding:** Confirm `StyledDivider` adds no vertical padding beyond its line. Read the source; do not assume.

---

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| 12M label clipping shipped | LOW | Update `.chartXAxis` and `.chartXScale` in `InsightsCharts.swift` — no data migration |
| 24H false empty state without persistence shipped | MEDIUM | Add UserDefaults persistence + merge in `UsageAggregator`; update `UsageSnapshot.==` if new field added; add restart-scenario test |
| Hourly persistence key collision (old date keys not cleaned) | LOW | Add cleanup on write: delete keys not matching today's date key prefix |
| Rate limit spacing still uneven after fix | LOW | Audit `StyledDivider` source for hidden padding; check `TokenHealthSection` for asymmetric vertical padding |
| Irregular axis spacing at 20→23 shipped | LOW | Change the hardcoded array in `InsightsCharts.swift` line 150 — one-line fix |

---

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| 12M axis label clipping | Phase: 12M chart label fix | Running-app screenshot at 275pt, all 12 months visible |
| Font size below `monoTiny` floor | Phase: 12M chart label fix | No new `Typography` token below `monoTiny`; no inline `.system(size:)` in chart files |
| 24H false empty state | Phase: 24H data persistence | Quit + relaunch scenario shows correct data before any new JSONL write |
| `dataFingerprint` sum collision after persistence | Phase: 24H data persistence | New activity after restart increments the chart correctly |
| 24H irregular axis spacing at 20→23 | Phase: 24H axis label fix | Equal pixel gaps between all adjacent label pairs |
| Rate limit section uneven spacing | Phase: Rate limit spacing | Consistent gap in all three `orderedModes` orderings; `StyledDivider` confirmed zero vertical padding |

---

## Sources

- Direct inspection: `AIBattery/Views/InsightsCharts.swift` lines 149–158 — hardcoded `[0, 4, 8, 12, 16, 20, 23]`, no `.chartXScale` on monthly chart
- Direct inspection: `AIBattery/Services/UsageAggregator.swift` lines 282–286 — `todayHourCounts` built from `todayEntries` only; lines 289–292 — `hourCounts` uses `statsCache?.hourCounts` as base (all-time, not today's)
- Direct inspection: `AIBattery/ViewModels/UsageViewModel.swift` lines 36–59 — fast-path cached snapshot before JSONL scan completes
- Direct inspection: `AIBattery/Views/ActivityChartView.swift` lines 77–83 — `dataFingerprint` uses `todayHourCounts.values.reduce(0, +)`
- Direct inspection: `AIBattery/Views/ActivityChartView.swift` lines 86–92 — `isEmpty` checks `todayHourCounts.values.allSatisfy { $0 == 0 }` — triggers false empty state
- Direct inspection: `AIBattery/Views/UsageBarsSection.swift` lines 17–38 — identical `Spacing.section` vertical padding; `StyledDivider` padding status requires reading `StyledDivider.swift`
- Direct inspection: `AIBattery/Utilities/Spacing.swift` — `Spacing.section = 8pt`
- Swift Charts documented behavior: `AxisMarks(values:)` specifies which values to label, not tick positions; domain padding requires `.chartXScale(domain:)` to suppress — HIGH confidence

---
*Pitfalls research for: AIBattery v1.14 Visual Polish — chart label fixes, hourly data persistence, rate limit spacing*
*Researched: 2026-03-24*
