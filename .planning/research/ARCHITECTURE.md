# Architecture Research

**Domain:** macOS menu bar app — visual polish, UX refinement, accessibility, error/empty states
**Researched:** 2026-03-20
**Confidence:** HIGH (derived entirely from live codebase and spec — no external research needed)

## Standard Architecture

### System Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        AppKit Layer                              │
│  ┌────────────────────┐   ┌──────────────────────────────────┐   │
│  │  NSStatusItem      │   │  PopoverPanel (NSPanel, floating) │   │
│  │  button.image      │   │  NSHostingView                    │   │
│  │  button.title      │   │  └─ PopoverContentView           │   │
│  │  (MenuBarIcon)     │   │     └─ UsagePopoverView          │   │
│  └────────────────────┘   └──────────────────────────────────┘   │
│  StatusBarManager (panel toggle, Combine subscriptions)          │
├─────────────────────────────────────────────────────────────────┤
│                      SwiftUI View Layer                          │
│  UsagePopoverView (thin orchestrator — wires sub-views)         │
│  ├── PopoverHeaderView                                          │
│  ├── SettingsRow (Settings/*)                                   │
│  ├── MetricToggleView                                           │
│  ├── ForEach(orderedModes) → FiveHourBarSection                 │
│  │                         → SevenDayBarSection                 │
│  │                         → TokenHealthSection                 │
│  ├── ProjectUsageGate → ProjectUsageSection                     │
│  ├── InsightsGate → InsightsView (ActivityChartView.swift)      │
│  │                → InsightsCharts (extension)                  │
│  │                → InsightsTrendCostSection (extension)        │
│  │                → InsightsRowsAndHover (extension)            │
│  └── PopoverFooterView                                          │
│  Shared state views: PopoverStateViews (Error / Empty / Idle)  │
├─────────────────────────────────────────────────────────────────┤
│                    Design System Layer                           │
│  Typography  Spacing  Layout  MotionConstants  ThemeColors      │
│  GaugeBar  StyledDivider  CollapsibleSectionHeader              │
│  CopyableText  MarqueeText  RefreshButton  FooterLink           │
├─────────────────────────────────────────────────────────────────┤
│                      ViewModel Layer                             │
│  UsageViewModel (@MainActor ObservableObject)                   │
│  └─ UsageSnapshot (plain struct, consumed by all views)         │
├─────────────────────────────────────────────────────────────────┤
│                      Services Layer                              │
│  OAuthManager  RateLimitFetcher  SessionLogReader               │
│  UsageAggregator  StatusChecker  TokenLedger  FileWatcher       │
└─────────────────────────────────────────────────────────────────┘
```

### Component Responsibilities Relevant to Polish

| Component | Responsibility | Polish Impact |
|-----------|---------------|---------------|
| `UsagePopoverView` | Thin orchestrator; owns `panelHasAppeared`, `showSettings`, logout confirm state | Route-level state changes only; avoid adding visual logic here |
| `PopoverStateViews` | `PopoverErrorView`, `PopoverEmptyView`, `PopoverIdleFilteredView` — the 3 non-data states | Primary target for error/empty state polish |
| `CollapsibleSectionHeader` | Chevron + title + collapse animation; used by 4 sections | Single change propagates to all collapsible sections |
| `GaugeBar` | Shared progress bar used by UsageBar and TokenHealthSection | Single change propagates to all progress gauges |
| `ThemeColors` | All color decisions — adaptive light/dark, colorblind-safe | Add new semantic colors here, never inline |
| `Typography` | All font style tokens — 15 named styles | Add new styles here; never use raw `.font()` calls |
| `Spacing` / `Layout` / `MotionConstants` | Spacing, dimension, animation constants | Add new constants here; never inline magic numbers |
| `StyledDivider` | Standardized divider at 0.3 opacity + `Spacing.tight` padding | Single change propagates to all section dividers |
| `CopyableText` | `CopyableModifier` + `LightCopyableModifier` ViewModifiers | Copy affordance consistency across all numeric values |
| `StatusBarManager` | Panel lifecycle, Combine-driven button updates | Accessibility of menu bar button lives here |

## Recommended Project Structure

```
AIBattery/
├── Views/
│   ├── Components/
│   │   ├── GaugeBar.swift              — modified: animation on fill width
│   │   └── [new shared components]     — extract only when used 3+ places
│   ├── PopoverStateViews.swift         — modified: error/empty state polish
│   ├── CollapsibleSectionHeader.swift  — modified if animation or a11y changes needed
│   ├── UsageBarsSection.swift          — modified for any bar section polish
│   ├── TokenHealthSection.swift        — modified for health section polish
│   ├── PopoverHeaderView.swift         — modified for header UX polish
│   ├── PopoverFooterView.swift         — modified for footer polish
│   └── [section views as needed]
├── Utilities/
│   ├── ThemeColors.swift               — modified: new semantic colors if needed
│   ├── Typography.swift                — modified: new font styles if needed
│   └── Spacing.swift                   — modified: new constants if needed
└── spec/
    ├── UI_SPEC.md                      — update before AND after visual changes
    └── CONSTANTS.md                    — update when constants change
```

### Structure Rationale

- **One primary type per file:** Existing pattern — continue this; do not merge polish into unrelated files.
- **Design token system is the single source of truth:** All spacing, typography, color, animation values flow through enums in `Utilities/`. Polish work that changes any value must update the enum, not inline a new literal.
- **Components only when used 3+ places:** `GaugeBar` and `StyledDivider` were extracted for this reason. New components should meet the same threshold or be extracted for a clear semantic reason (e.g., a reusable error banner).
- **Section views are self-contained:** Each section owns its own `@AppStorage` for collapse state. Polish within a section is isolated; no plumbing changes to `UsagePopoverView`.

## Architectural Patterns

### Pattern 1: Design Token Modification (safest polish path)

**What:** Change a value in a `Utilities/` enum — it propagates to every consumer automatically.
**When to use:** Spacing adjustments, typography tweaks, animation timing changes, color adjustments.
**Trade-offs:** Extremely safe — tests already cover the enum values. Risk is that the change is truly global; verify the constant is used consistently before widening or tightening a value.

**Example:**
```swift
// Utilities/Spacing.swift
enum MotionConstants {
    static let standard: Animation = .easeOut(duration: 0.15)
    // Changing 0.15 here affects all 4 collapsible sections + settings toggle simultaneously
}
```

### Pattern 2: Shared Component Modification

**What:** Modify a shared view (`GaugeBar`, `StyledDivider`, `CollapsibleSectionHeader`) to propagate a visual change to all consumers.
**When to use:** Bar fill animation, divider opacity, chevron behavior, copy affordance feedback.
**Trade-offs:** High leverage — one change reaches all consumers. Requires checking that the change is desired in all contexts (e.g., adding animation to `GaugeBar` affects both rate limit bars and context health bar).

**Example:**
```swift
// Add animated fill to GaugeBar — reaches UsageBarsSection + TokenHealthSection
RoundedRectangle(cornerRadius: Layout.barCornerRadius)
    .fill(barColor)
    .frame(width: ..., height: ...)
    .animation(.easeInOut(duration: 0.4), value: percent) // CONSTANTS.md already documents this
```

### Pattern 3: Isolated Section Polish

**What:** Modify a single section view for polish that is specific to that section.
**When to use:** Label changes, section-specific layout adjustments, adding a section-specific empty state.
**Trade-offs:** Zero blast radius. Safest approach when the change is contextual (e.g., the Insights section has its own empty state logic that differs from the global `PopoverEmptyView`).

**Example:**
```swift
// InsightsCharts.swift — chart-specific empty state
if data.isEmpty {
    VStack(spacing: 4) {
        Image(systemName: "chart.line.flattrend.xyaxis")
            .font(.system(size: 14))
            .foregroundStyle(ThemeColors.tertiaryLabel)
        Text("No activity in \(mode.label) window")
            .font(Typography.tinyLabel)
            .foregroundStyle(ThemeColors.tertiaryLabel)
    }
    .frame(height: Layout.chartHeight)
}
```

### Pattern 4: New Semantic Colors via ThemeColors

**What:** Add a new `static var` to `ThemeColors` rather than inlining an opacity or custom color.
**When to use:** Any new color role needed for polish (e.g., a subtle success tint, a highlight background).
**Trade-offs:** Centralizes color decisions and ensures colorblind-mode handling is considered at definition time. Never inline `Color(...).opacity(...)` in a view for a semantic role.

**Example:**
```swift
// ThemeColors.swift
static var successTint: Color {
    isColorblind ? .blue.opacity(0.08) : .green.opacity(0.08)
}
```

### Pattern 5: ViewModifier for Cross-Cutting UX Concerns

**What:** `CopyableModifier` is the existing example — a ViewModifier encapsulates copy feedback behavior.
**When to use:** When the same UX behavior (hover highlight, tooltip pattern, press feedback) needs to apply to multiple distinct view types.
**Trade-offs:** Keeps individual views clean. Only worth adding a new modifier if it will be applied in 3+ places. For one-off effects, inline is cleaner.

## Data Flow

### Polish-Relevant State Flow

```
UserDefaults (@AppStorage)
    ↓ (direct binding)
Section views (collapse state, chart mode, settings)
    ↓ (no ViewModel involvement)
[Re-render on change]

UsageViewModel.snapshot (@Published)
    ↓ (Combine, @ObservedObject)
UsagePopoverView → section views via init params
    ↓ (pure data, no mutation in views)
[Display-only reads]

ThemeColors.isColorblind (KVO observer on UserDefaults)
    ↓ (static, cached, updated via NotificationCenter)
All views that call ThemeColors.*
    ↓ (views must re-render on colorblind toggle — see pitfall below)
```

### Key Data Flows for Polish Work

1. **Color changes:** All color decisions go through `ThemeColors`. Adding a new color requires adding it there and considering both light/dark mode AND colorblind mode variants.
2. **Spacing/layout changes:** All size and spacing values are defined in `Spacing.swift` (`Spacing`, `Layout`, `MotionConstants` enums). Changing a constant value propagates everywhere it is used.
3. **Error/empty states:** `PopoverStateViews.swift` contains the three global states. Section-specific empty states live within each section view. Neither talks to `UsageViewModel` — they receive data via init params.
4. **Accessibility labels:** VoiceOver labels are on individual views. `CollapsibleSectionHeader` has an `accessibilityLabel` that includes the collapsed state — changes to that component's label affect all 4 collapsible sections.

### Section Rendering Order (build-order dependency)

```
UsagePopoverView (orchestrator)
    ├── Header (no dependencies on other sections)
    ├── Settings (no dependencies on other sections)
    ├── MetricToggle (reads snapshot.autoResolvedMode)
    ├── Rate Limit sections (reads snapshot.rateLimits)
    ├── TokenHealth (reads snapshot.topSessionHealths / tokenHealth)
    ├── ProjectUsage (reads snapshot.projectTokens, gated on panelHasAppeared)
    └── Insights (reads snapshot, gated on panelHasAppeared)
```

Sections gated behind `panelHasAppeared` (`ProjectUsageGate`, `InsightsGate`) defer rendering by one run-loop via `DispatchQueue.main.async` in `.onAppear`. Polish to these sections must account for the deferred appearance — transitions that run on first render will trigger on every panel open, not just first app launch.

## Integration Points for Polish Work

### New vs. Modified Components

| Change Type | Target | New or Modified |
|-------------|--------|-----------------|
| Spacing/layout value | `Utilities/Spacing.swift` | **Modified** |
| Typography value | `Utilities/Typography.swift` | **Modified** |
| Animation duration | `Utilities/Spacing.swift` (MotionConstants) | **Modified** |
| New semantic color | `Utilities/ThemeColors.swift` | **Modified** |
| Progress bar fill animation | `Views/Components/GaugeBar.swift` | **Modified** |
| Error state polish | `Views/PopoverStateViews.swift` | **Modified** |
| Empty state polish | `Views/PopoverStateViews.swift` | **Modified** |
| Section-specific empty state | Individual section file | **Modified** |
| New shared UX pattern (3+ uses) | `Views/Components/` new file | **New** |
| Accessibility label fix | Individual view file where label lives | **Modified** |
| New VoiceOver hint | Individual view file | **Modified** |
| `.help()` tooltip | Individual view file | **Modified** |
| Spec drift fix | `spec/UI_SPEC.md` or `spec/CONSTANTS.md` | **Modified** |
| New constant | `spec/CONSTANTS.md` + `Utilities/` enum | **Modified** (both) |

### Suggested Build Order for Non-Destructive Polish

1. **Design tokens first** — any spacing, color, or animation constant changes. These are pure value changes with no structural impact. Tests already validate enum values; update tests when changing constants.

2. **Shared component modifications** — `GaugeBar`, `StyledDivider`, `CollapsibleSectionHeader`. Changes here have global reach but zero orchestrator coupling. Verify behavior in all consumers (rate limit bars, context health bar, all 4 collapsible sections).

3. **State view polish** — `PopoverStateViews.swift`. Error and empty states are isolated, low-risk, and have a clear UI spec to implement against.

4. **Section-by-section visual polish** — work through individual section files in isolation. Each section is self-contained. Order: rate limit bars → context health → tokens → projects → insights → header → footer. This order matches user visual scanning order.

5. **Accessibility pass** — after visual structure is stable, audit `.accessibilityLabel`, `.accessibilityHint`, `.accessibilityElement(children:)`, and VoiceOver reading order. Changes here are purely additive and never break visual layout.

6. **Spec sync** — after all changes, update `spec/UI_SPEC.md`, `spec/CONSTANTS.md`, and `spec/ARCHITECTURE.md` to reflect actual state.

## Anti-Patterns

### Anti-Pattern 1: Inline Color or Spacing Literals

**What people do:** Add `.foregroundStyle(Color(red: 0.5, green: 0.5, blue: 0.5).opacity(0.7))` directly in a view during polish.
**Why it's wrong:** Bypasses colorblind-mode handling in `ThemeColors`. Creates an inconsistency that is hard to find later. Breaks the single-source-of-truth contract.
**Do this instead:** Add a named constant to `ThemeColors` or reuse an existing one (`ThemeColors.secondaryLabel`, `ThemeColors.tertiaryLabel`, `ThemeColors.caution`, etc.).

### Anti-Pattern 2: Adding @State to UsagePopoverView

**What people do:** Add section-specific UI state (`@State var isHighlighted`, `@State var showTooltip`) to `UsagePopoverView` because it's the "root" view.
**Why it's wrong:** `UsagePopoverView` is intentionally a thin orchestrator. Adding state there couples unrelated sections and causes unnecessary re-renders of the entire popover.
**Do this instead:** Keep state local to the section view that owns it. Section views are self-contained.

### Anti-Pattern 3: Modifying the Shared Timer for Animation

**What people do:** Add a new `Timer.publish` property to a SwiftUI struct for a polish animation (e.g., a pulsing highlight on an idle session).
**Why it's wrong:** `Timer.publish` stored as a property on a SwiftUI struct causes timer accumulation — a known freeze issue documented in the project MEMORY. This was the cause of a past regression.
**Do this instead:** Use `TimelineView(.periodic(...))` for any periodic UI updates within SwiftUI views. For non-SwiftUI animation, use `MotionConstants` with SwiftUI's `.animation()` modifier.

### Anti-Pattern 4: Directly Triggering Refresh from a Visual Polish Change

**What people do:** Wire a new UI affordance (e.g., a pull-to-refresh gesture or a "stale data" banner) to call `viewModel.refresh()` without debouncing.
**Why it's wrong:** `StatusChecker` has a 60s backoff after failures. `RateLimitFetcher` has a 1-hour cache. Direct refresh calls bypass these guards and can cause API hammering.
**Do this instead:** Route user-initiated refreshes through the existing `Task { await viewModel.refresh() }` pattern used throughout the views. The ViewModel has guard logic.

### Anti-Pattern 5: Adding a New ViewModifier Outside CopyableText.swift

**What people do:** Create a new `.swift` file with a ViewModifier for a single-use affordance (e.g., hover highlight, press feedback).
**Why it's wrong:** Fragments the modifier library. `CopyableText.swift` already has two modifier variants (`CopyableModifier` for full affordance, `LightCopyableModifier` for dense areas). New affordance modifiers should extend that file unless they are semantically distinct.
**Do this instead:** Add the modifier to `CopyableText.swift` if it is a copy-related affordance, or create a new file only if it represents a genuinely distinct interaction pattern used 3+ times.

### Anti-Pattern 6: Skipping Spec Sync After Visual Changes

**What people do:** Make a polish change (new spacing value, new color, changed label text) without updating `spec/UI_SPEC.md` or `spec/CONSTANTS.md`.
**Why it's wrong:** The `spec/` folder is the single source of truth by project convention. Spec drift is an explicit anti-requirement — the project has a `CQ-02` requirement for spec sync on structural changes.
**Do this instead:** Treat spec sync as part of the definition of done for every phase, not a separate step.

## Accessibility Integration Points

The existing accessibility coverage is partial. Key gaps and integration points for polish:

| Area | Current State | Integration Point |
|------|--------------|-------------------|
| VoiceOver on rate limit bars | `accessibilityAddTraits(.isHeader)` on label; no combined label for bar + percent | `UsageBarsSection.swift` — add `.accessibilityElement(children: .combine)` on the outer `VStack` with a computed label |
| VoiceOver on metric toggle | `.help()` tooltip present; no explicit `accessibilityLabel` on the segmented picker | `MetricToggleView.swift` |
| VoiceOver on collapsible sections | `CollapsibleSectionHeader` has labels; content inside has individual labels | Verify reading order with VoiceOver — no code change may be needed |
| VoiceOver on footer buttons | No `accessibilityHint` on Logout's two-tap confirm flow | `PopoverFooterView.swift` — add hint explaining two-tap requirement |
| Menu bar button | `NSStatusItem.button` — no `accessibilityLabel` set | `StatusBarManager.swift` — add `button.setAccessibilityLabel(...)` |
| Keyboard navigation | Panel handles Escape; Cmd+Q wired to panel | Verify Tab order within popover content |

**Constraint:** Accessibility changes in `NSStatusItem` use AppKit APIs (`setAccessibilityLabel`, `setAccessibilityRole`), not SwiftUI. These live in `StatusBarManager.swift`.

## Scaling Considerations

Not applicable in the traditional sense — this is a single-user local app. The relevant "scale" is UI complexity:

| Concern | Current | Risk | Mitigation |
|---------|---------|------|------------|
| Popover render time | ~50ms open target (RESP-01 met) | Adding heavy views degrades this | Gate new sections behind `panelHasAppeared` deferred render |
| Animation stacking | 3 independent animation contexts | Adding more `.animation()` modifiers can create compositing conflicts | Keep animations scoped to the specific value they animate (`value:` parameter) |
| Design token sprawl | 15 Typography + 6 Spacing + 7 Layout + 2 Motion = 30 tokens | Adding tokens for every one-off value creates noise | Only add tokens when a value is used 2+ times or represents a named semantic role |
| File size limits | 800-line max per project convention | `UsagePopoverView` is 237 lines — safe | Section extraction pattern already established if sizes approach limit |

## Sources

- `/Users/kyle/workspace/Github/KyleNesium/AIBattery/spec/ARCHITECTURE.md` — live architecture spec
- `/Users/kyle/workspace/Github/KyleNesium/AIBattery/spec/UI_SPEC.md` — live UI specification
- `/Users/kyle/workspace/Github/KyleNesium/AIBattery/spec/CONSTANTS.md` — live constants reference
- `/Users/kyle/workspace/Github/KyleNesium/AIBattery/AIBattery/Views/UsagePopoverView.swift` — orchestrator
- `/Users/kyle/workspace/Github/KyleNesium/AIBattery/AIBattery/Views/PopoverStateViews.swift` — state views
- `/Users/kyle/workspace/Github/KyleNesium/AIBattery/AIBattery/Views/Components/GaugeBar.swift` — shared component
- `/Users/kyle/workspace/Github/KyleNesium/AIBattery/AIBattery/Utilities/ThemeColors.swift` — color system
- `/Users/kyle/workspace/Github/KyleNesium/AIBattery/.planning/PROJECT.md` — milestone context

---
*Architecture research for: AIBattery v1.14 Polish & UX — SwiftUI+AppKit hybrid macOS menu bar app*
*Researched: 2026-03-20*
