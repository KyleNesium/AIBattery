# Phase 8: File Extraction - Research

**Researched:** 2026-03-19
**Domain:** SwiftUI view decomposition (structural refactoring only)
**Confidence:** HIGH

## Summary

Phase 8 is a pure structural refactoring phase: no behavioral changes, no new logic. Both target files were read line-by-line to identify natural section boundaries aligned with existing MARK comments and logical groupings. The extraction plan is deterministic — the code itself reveals its own seams.

`UsagePopoverView.swift` (666 lines) has four clearly separated concerns beyond its core orchestrator body: the header/account-picker, the metric toggle with auto-mode button, state placeholder views (loading/error/empty), and the footer with status/logout/quit. Extracting these yields a core file under 180 lines.

`ActivityChartView.swift` (711 lines) is already organized by MARK sections. Three extraction targets are natural: the three chart implementations (daily/hourly/monthly) as a single charts file, the trend-and-cost section, and the insight rows plus hover/tooltip helpers. The core `InsightsView` with its caching/fingerprinting/body stays at ~184 lines after extraction.

**Primary recommendation:** Extract 7 new files (4 from UsagePopoverView, 3 from ActivityChartView). Keep both originals as thin orchestrators that wire sub-views together via init parameters.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
None — all implementation choices at Claude's discretion.

### Claude's Discretion
All implementation choices are at Claude's discretion — pure infrastructure phase. Key considerations:
- Identify natural section boundaries in each large file
- Extract sub-views as separate files with descriptive names
- Preserve exact existing behavior (no functional changes)
- Each resulting file must be under 400 lines
- Follow existing file naming convention (one primary type per file, filename matches type name)

### Deferred Ideas (OUT OF SCOPE)
None.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| CQ-01 | Extract large view files — break UsagePopoverView (666 lines) and ActivityChartView (704 lines) into focused sub-views under 400 lines each | Full extraction plan below; 7 new files identified with line-count estimates and exact boundary lines |
</phase_requirements>

---

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| SwiftUI | macOS 13+ | View decomposition target | Project is already 100% SwiftUI |
| Swift Testing | Xcode bundled | Test verification | Project test suite uses `@Test`/`#expect` |

No new dependencies. This phase is pure file surgery.

**Installation:** None required.

## Architecture Patterns

### Recommended Project Structure
```
AIBattery/Views/
├── UsagePopoverView.swift         # Core orchestrator (~170 lines after extraction)
├── PopoverHeaderView.swift        # NEW: header + account picker + update banner (~120 lines)
├── MetricToggleView.swift         # NEW: metric picker + auto mode button (~75 lines)
├── PopoverStateViews.swift        # NEW: loading/error/empty/idle state placeholders (~75 lines)
├── PopoverFooterView.swift        # NEW: footer links + logout + status + timestamp (~155 lines)
├── ActivityChartView.swift        # Core InsightsView orchestrator (~184 lines after extraction)
├── InsightsCharts.swift           # NEW: dailyChart + hourlyChart + monthlyChart + sharedYAxis (~235 lines)
├── InsightsTrendCostSection.swift # NEW: trendSummary + trendRows + costSection (~120 lines)
├── InsightsRowsAndHover.swift     # NEW: insightRows + hover helpers + formatters (~175 lines)
└── [existing files unchanged]
```

### Pattern 1: Thin Orchestrator with Init-Param Sub-Views
**What:** The large file becomes a thin struct that owns state and wires sub-views together via init parameters. Sub-views receive only the data they display.
**When to use:** When a file contains multiple logically distinct sections that can receive their data as value types.
**Example:**
```swift
// UsagePopoverView.swift after extraction — orchestrator only
private var headerSection: some View {
    PopoverHeaderView(
        snapshot: viewModel.snapshot,
        accountStore: accountStore,
        showSettings: $showSettings,
        isAddingAccount: $isAddingAccount
    )
}
```

### Pattern 2: Private State Stays in the Owning File
**What:** `@State`, `@AppStorage`, `@ObservedObject` properties that drive a section stay in `UsagePopoverView` (or `InsightsView`), not in the extracted sub-view — UNLESS the sub-view exclusively owns that state.
**When to use:** Always. Avoids pushing binding complexity into sub-views unnecessarily.
**Key judgment calls:**
- `showSettings`, `isAddingAccount`, `showLogoutConfirm`, `logoutRevertTask` — owned by `UsagePopoverView`, passed as `Binding<Bool>` or callbacks to `PopoverFooterView`/header
- `selectedDailyId`, `selectedHourlyOffset`, `selectedMonthlyId` — hover state lives in `InsightsView`, passed as `Binding` into `InsightsCharts`
- `cachedOrderedModes`, `recomputeOrderedModes()` — stays in `UsagePopoverView` (drives body ForEach)
- `autoModeButton` auto-mode state (`@AppStorage autoMetricMode`) — the button lives in `MetricToggleView` but the AppStorage key is already stored there independently; the extracted view re-declares the same `@AppStorage` key

### Pattern 3: Static Helpers and Formatters Move with Their Owner
**What:** Static methods and formatters (`relativeTime`, `absoluteFormatter`, `dayShortLabel`, `compactCount`, etc.) move to whichever file uses them. If used only in one extracted file, they move there.
**When to use:** Always prefer colocation over shared utilities unless two+ files need the same helper.

### Anti-Patterns to Avoid
- **Splitting a sub-view across two files:** Each type stays in exactly one file (CLAUDE.md: "filename matches type name").
- **Creating thin wrapper types:** Don't wrap extracted code in an extra struct just to namespace it — use MARK sections if grouping is needed within a file.
- **Moving shared constants:** `ActivityChartMode` enum at top of ActivityChartView.swift stays in `ActivityChartView.swift` (it's the canonical home; all consumers import it from there).
- **Breaking the no-EnvironmentObject rule:** Sub-views receive data via init parameters only (per CLAUDE.md and project conventions).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| State hoisting | Custom observer/delegate | SwiftUI `Binding<T>` | Already used throughout; consistent pattern |
| Shared static formatters | Duplicate implementations | Move once, reference from new file | Swift's module system makes all public/internal types available within the same SPM target |

**Key insight:** Because all extracted files are in the same SPM target (`AIBatteryCore`), no `import` or `public` changes are needed — internal access level works across files in the same module.

## Common Pitfalls

### Pitfall 1: Compiler Isolation of Private MARK Members
**What goes wrong:** Methods marked `private` in `UsagePopoverView` cannot be called from an extracted sub-view file, even if both are in the same target. Swift's `private` is file-scoped.
**Why it happens:** `private` in Swift means private to the current declaration scope (effectively the file for top-level declarations).
**How to avoid:** When extracting a section, move its supporting private helpers into the new file. Any helper that UsagePopoverView still calls must remain in UsagePopoverView or be promoted to `internal` (which is the default — just remove `private`).
**Warning signs:** "Use of unresolved identifier" errors at compile time for moved helpers.

### Pitfall 2: @MainActor Static Methods in ActivityChartTrend
**What goes wrong:** `ActivityTrendComputation` is `@MainActor`. Its static methods call `InsightsView.formatHourLabel`, `InsightsView.monthAbbrev`, and `InsightsView.compactCount` — all static methods currently on `InsightsView`. After extraction, if these move to `InsightsCharts.swift` or `InsightsRowsAndHover.swift`, the call sites in `ActivityChartTrend.swift` must still resolve.
**Why it happens:** The formatters are currently accessed as `InsightsView.formatHourLabel` — they're static on the view type.
**How to avoid:** Keep the three public static formatters (`formatHourLabel`, `dayShortLabel`, `monthAbbrev`, `compactCount`) in `ActivityChartView.swift` on `InsightsView`, OR move them to `InsightsRowsAndHover.swift` and update `ActivityChartTrend.swift` call sites. Either approach works; the simplest is to leave them on `InsightsView` until this phase explicitly needs to move them.
**Warning signs:** Compile errors in `ActivityChartTrend.swift` after extraction.

### Pitfall 3: Conditional Compilation Blocks (#if ENABLE_VERSION_CHECKER)
**What goes wrong:** The update banner in `PopoverHeaderView` is wrapped in `#if ENABLE_VERSION_CHECKER`. The `@State` variables for `updateCheckMessage`, `updateCheckDismissTask`, `updateBannerDismissed` are also inside this flag. They must move together to the extracted header file.
**Why it happens:** The conditional state and conditional view code are interleaved.
**How to avoid:** Move all three `#if ENABLE_VERSION_CHECKER` state vars to `PopoverHeaderView` along with the header view body. The parent `UsagePopoverView` removes them from its state.
**Warning signs:** Compiler errors about missing `updateCheckMessage` / `updateBannerDismissed` references.

### Pitfall 4: Hover State Bindings in Chart Views
**What goes wrong:** `selectedDailyId`, `selectedHourlyOffset`, `selectedMonthlyId` are `@State` in `InsightsView` but are read and written by the chart sub-views. If charts become a separate struct, they need `Binding` parameters or the state moves into the charts file.
**Why it happens:** Chart overlay closures set these values via `self.selectedDailyId = ...`.
**How to avoid:** The cleanest approach is to keep charts as `@ViewBuilder` computed properties within `InsightsView` (not separate structs) — they stay in `InsightsCharts.swift` but remain `private var` extensions on `InsightsView`. This avoids all binding complexity. See Code Examples below.
**Warning signs:** "Cannot assign to property: 'selectedDailyId' is a 'let' constant" if extracted incorrectly.

### Pitfall 5: Line Count After Extraction Exceeds 400
**What goes wrong:** Naive split of a 711-line file into two halves still yields files near 350 lines, leaving little room for future growth.
**Why it happens:** Not counting lines carefully before committing to a split boundary.
**How to avoid:** Use the line estimates in the extraction plan below. Target each output file at 120-240 lines, not just "under 400."

## Code Examples

### Extension Pattern for Chart Sub-Views (avoids Binding complexity)
```swift
// Source: Swift language — private extensions on a type can live in separate files
// InsightsCharts.swift — same module, extends InsightsView
extension InsightsView {
    // All chart views share InsightsView's state directly via self
    var dailyChart: some View { ... }
    var hourlyChart: some View { ... }
    var monthlyChart: some View { ... }
    static let areaGradient: LinearGradient = ...
    static let chartLineStyle = StrokeStyle(lineWidth: 1.5)
    var sharedYAxis: some AxisContent { ... }
}
```
This pattern is the recommended approach for `InsightsView` because chart views access `@State` directly — no Binding plumbing needed.

### Extension Pattern for UsagePopoverView Sub-Sections
```swift
// PopoverFooterView.swift — NOT an extension; standalone View struct
struct PopoverFooterView: View {
    let systemStatus: SystemStatus?
    let isLoading: Bool
    let lastFreshFetch: Date?
    @Binding var showLogoutConfirm: Bool
    var onLogout: () -> Void
    // ...
}
```
UsagePopoverView footer is simpler as a standalone struct because it needs minimal state from the parent.

### Sharing @AppStorage Keys Across Files
```swift
// MetricToggleView.swift — re-declares the same AppStorage key
@AppStorage(UserDefaultsKeys.autoMetricMode) private var autoMetricMode: Bool = false
// This is correct — @AppStorage reads/writes the same UserDefaults key regardless of declaration location
```

## Extraction Plan (Detailed)

### UsagePopoverView.swift (666 → ~165 lines)

| New File | Source Lines | Est. Lines | Content |
|----------|-------------|------------|---------|
| `PopoverHeaderView.swift` | 172–319 | ~120 | `headerSection`, `accountPicker`, `accountLabel`, update banner `#if ENABLE_VERSION_CHECKER` block, 3 `@State` vars for version checker |
| `MetricToggleView.swift` | 443–510 | ~75 | `metricToggle`, `autoModeButton`, `announceAutoMode`, `cachedOrderedModes` state, `recomputeOrderedModes` |
| `PopoverStateViews.swift` | 373–441 | ~75 | `loadingView`, `errorView`, `emptyView`, `idleFilteredEmptyState` (these are simple value views, standalone structs work well) |
| `PopoverFooterView.swift` | 512–666 | ~155 | `footerSection`, `statusColor`, `systemIndicator`, `relativeTime`, `absoluteFormatter`, `absoluteTime`, `statusTooltip` |
| **UsagePopoverView.swift (after)** | 1–171 | ~165 | Struct/init/state/body routing/`mainContent`/`autoResolvedBinding`/`metricMode` |

**Note:** `showLogoutConfirm` and `logoutRevertTask` stay in UsagePopoverView and are passed as `Binding<Bool>` and a callback to `PopoverFooterView`.

### ActivityChartView.swift (711 → ~184 lines)

| New File | Source Lines | Est. Lines | Content |
|----------|-------------|------------|---------|
| `InsightsCharts.swift` | 186–422 | ~235 | `extension InsightsView` with `areaGradient`, `chartLineStyle`, `sharedYAxis`, `dailyChart`, `hourlyChart`, `monthlyChart` |
| `InsightsTrendCostSection.swift` | 424–539 | ~120 | `extension InsightsView` with `trendSummary`, `trendRowTop`, `trendRowBottom`, `costSection`, `windowedModelTokens`, `isActive`, `costColumnWidth`, `tokenColumnWidth` |
| `InsightsRowsAndHover.swift` | 541–711 | ~175 | `extension InsightsView` with `insightRows`, `insightRow`, `insightLabelWidth`, `tooltipLabel`, `chartHoverOverlay`, `currentHoverX`, `hoverTooltipText`, `selectionRuleStyle`, `dayShortLabel`, `monthAbbrev`, `compactCount`, `formatHourLabel`, `hourLabels` |
| **ActivityChartView.swift (after)** | 1–184 | ~184 | `ActivityChartMode` enum, `InsightsView` struct with all state/cache/fingerprint/body |

**Note:** Static formatters (`formatHourLabel`, `dayShortLabel`, `compactCount`, `monthAbbrev`) move to `InsightsRowsAndHover.swift`. Update `ActivityChartTrend.swift` call sites from `InsightsView.formatHourLabel` to `InsightsView.formatHourLabel` — no change needed if using extensions (still `InsightsView.formatHourLabel`).

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Single monolithic view file | Extracted sub-views per section | Standard Swift/SwiftUI practice | Faster compile times, easier navigation |
| Private nested types | One primary type per file | Project convention (CLAUDE.md) | Consistent codebase |

## Open Questions

1. **Should PopoverStateViews be standalone structs or extensions on UsagePopoverView?**
   - What we know: The loading/error/empty views don't read any `@State` — they're pure display from params
   - What's unclear: Whether the `errorView` needs a `viewModel.refresh()` callback or can inline an `onRetry` closure param
   - Recommendation: Make them standalone `View` structs taking only what they display (`message: String`, `onRetry: () -> Void`). This maximizes testability.

2. **AutoModeButton — standalone struct or MetricToggleView private var?**
   - What we know: `autoModeButton` uses `@AppStorage` and calls `announceAutoMode` (NSAccessibility)
   - Recommendation: Keep as `private var` inside `MetricToggleView` (not a separate struct) — it's tightly coupled to the toggle context.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Swift Testing (bundled with Xcode) |
| Config file | `Package.swift` — `AIBatteryCoreTests` target |
| Quick run command | `swift test --filter AIBatteryCoreTests 2>&1 \| tail -20` |
| Full suite command | `swift test` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| CQ-01 | All extracted files compile | Build verification | `swift build` | ❌ Wave 0 (implicit — no new test file needed) |
| CQ-01 | No view file exceeds 800 lines | Static analysis | `wc -l AIBattery/Views/*.swift \| awk '$1 > 800'` | N/A — shell check |
| CQ-01 | No view file exceeds 400 lines (success criteria) | Static analysis | `wc -l AIBattery/Views/*.swift \| awk '$1 > 400'` | N/A — shell check |

**Note:** This phase has no behavior changes, so no new unit tests are required. The existing test suite (`swift test`) serves as the regression gate. A successful build + all tests green = phase verified.

### Sampling Rate
- **Per task commit:** `swift build -c release` (catches compile errors immediately)
- **Per wave merge:** `swift test` (full regression)
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
None — existing test infrastructure covers all phase requirements. No new test files needed (pure structural refactoring with no behavior changes).

## Sources

### Primary (HIGH confidence)
- Direct file read: `/AIBattery/Views/UsagePopoverView.swift` — line-by-line boundary analysis
- Direct file read: `/AIBattery/Views/ActivityChartView.swift` — line-by-line boundary analysis
- Direct file read: `/AIBattery/Views/ActivityChartTrend.swift` — cross-reference for `InsightsView` static method call sites
- CLAUDE.md project instructions — "one primary type per file, filename matches type name", no EnvironmentObject

### Secondary (MEDIUM confidence)
- Swift language documentation: `private` is file-scoped for top-level declarations — verified via language reference
- Swift extension pattern for splitting a type across files — standard Swift practice, well-documented

### Tertiary (LOW confidence)
None.

## Metadata

**Confidence breakdown:**
- Extraction plan: HIGH — based on direct file reads with exact line numbers
- Extension-vs-struct recommendation: HIGH — based on state ownership analysis
- Line count estimates: MEDIUM — estimates; actual counts may vary ±10 lines due to import statements and blank line conventions

**Research date:** 2026-03-19
**Valid until:** 2026-04-19 (stable Swift/SwiftUI — no rapid churn expected)
