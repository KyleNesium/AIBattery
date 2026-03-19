# Phase 7: Visual Polish - Research

**Researched:** 2026-03-19
**Domain:** SwiftUI animations, contentTransition, view consistency patterns
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Unified divider style: `.opacity(0.3)` with `Spacing.tight` vertical padding — matches ActivityChartView which looks cleanest
- Rate Limit bars stay non-collapsible — they're always-visible primary indicators
- Collapsed summary values stay as-is (contextually useful) — only typography/color is standardized (already done in Phase 6)
- Extract a reusable `StyledDivider` view — single source of truth, replaces ~10 callsites
- Expand/collapse content: `.opacity` transition on section content with 0.2s easeInOut — smooth fade, matches existing chevron timing
- Metric value changes: `contentTransition(.numericText())` on Text views showing numbers — SwiftUI native, smooth digit rolling
- Animation duration standard: 0.2s easeInOut for all section interactions (matches existing pattern)
- All new animations gated on panel visibility (popover open) — PG-01 prep for Phase 9
- Central `MotionConstants` enum (or Animation extension) for durations/curves — single place to tune
- `numericText()` applied to all numeric Text views in popover: token counts, cost values, percentages, session counts
- Compile check + visual inspection for verification (animations are inherently visual)

### Claude's Discretion
- Exact file placement for MotionConstants (alongside Typography/Spacing or separate)
- Whether StyledDivider is a View struct or a ViewModifier
- Specific numericText() callsite selection (all numeric Text views, use judgment for edge cases)

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| UI-06 | Section visual consistency — uniform dividers, header styles, and collapse behavior across all popover sections | StyledDivider replaces ~20 raw Divider() calls across 6 files; 2 divergent opacity values (0.5 in SettingsRow, bare in UsagePopoverView) unified to 0.3 with Spacing.tight padding |
| UI-07 | Subtle transition animations on section expand/collapse and metric changes (must not impact poll-cycle performance) | contentTransition(.numericText()) confirmed macOS 13+ compatible (no availability guard needed); .opacity transitions on collapsed content already pattern-established in codebase |
</phase_requirements>

## Summary

Phase 7 delivers two focused improvements: (1) a `StyledDivider` component that unifies ~20 raw `Divider()` calls scattered across 6 files into a single styled source of truth, and (2) SwiftUI animation additions that make section expand/collapse and numeric value changes feel smooth rather than abrupt.

The most important research finding is the `contentTransition(.numericText())` availability question. Verification against Apple's documentation API confirms `numericText(countsDown:)` and the plain `numericText()` call are available from macOS 13.0 — the project's minimum deployment target. No `#available` guard is required. However, the `numericText(value:)` variant (which takes a `BinaryFloatingPoint`) was introduced in macOS 14.0 / iOS 17.0 and must NOT be used without an availability check.

Animation patterns are already well-established in the codebase: `withAnimation(.easeInOut(duration: 0.2))` appears in 6 callsites, `.transition(.opacity)` in 4 places, and `CollapsibleSectionHeader` already uses `withAnimation(.easeInOut(duration: 0.2))` for chevron rotation. Phase 7 standardizes these patterns rather than introducing anything new.

**Primary recommendation:** Use `contentTransition(.numericText())` (no arguments) for all numeric Text views — it is macOS 13 compatible. Centralize animation constants in a `MotionConstants` enum co-located with `Spacing.swift` (following the existing namespace pattern). Make `StyledDivider` a plain `View` struct, not a `ViewModifier`, because it has no parameters beyond its own visual definition.

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| SwiftUI | macOS 13 SDK | `.contentTransition`, `.transition`, `.animation` | Built-in, no dependency |
| Swift | 5.9 (Package.swift) | `@available` guards if needed | Project standard |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| AppKit (via SwiftUI) | macOS 13 | `NSPanel.animationBehavior` | Already set to `.none` in StatusBarManager — do not change |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `contentTransition(.numericText())` | Manual `AnimatableModifier` | numericText is zero-overhead, native, handles digit-by-digit rolling; custom solution is complex and fragile |
| `StyledDivider` as View struct | ViewModifier | ViewModifier requires `.modifier(...)` call syntax everywhere; a View struct is used with `StyledDivider()` which reads identically to `Divider()` |
| Co-locate MotionConstants in Spacing.swift | Separate file | Fewer files is better given ~5 constants; Spacing.swift already follows the caseless-enum namespace pattern the project uses for ThemeColors and Typography |

**Installation:** No new packages. All APIs are from SwiftUI system framework.

## Architecture Patterns

### Recommended Project Structure
```
AIBattery/Utilities/
├── Spacing.swift            # Add MotionConstants enum here (alongside Layout enum)
├── Typography.swift         # Existing — no change
└── ThemeColors.swift        # Existing — no change

AIBattery/Views/
├── StyledDivider.swift      # New — extracted from Divider() pattern
├── CollapsibleSectionHeader.swift  # Existing — no change needed
├── UsagePopoverView.swift   # Update raw Divider() calls → StyledDivider()
├── TokenHealthSection.swift # Add .contentTransition to numeric Text views
├── ProjectUsageSection.swift # Add .contentTransition to numeric Text views
├── ActivityChartView.swift  # Already uses .opacity(0.3).padding(.vertical, 2) — update to StyledDivider
├── UsageBarsSection.swift   # Add .contentTransition to percent Text
├── UsageGateViews.swift     # Update Divider() → StyledDivider()
├── AuthView.swift           # Update Divider() → StyledDivider() (AuthView dividers are contextually appropriate)
└── Settings/
    └── SettingsRow.swift    # Update Divider().opacity(0.5) → StyledDivider() (standardize to 0.3)
```

### Pattern 1: StyledDivider — single-definition divider
**What:** A View struct wrapping `Divider().opacity(0.3).padding(.vertical, Spacing.tight)` — drop-in replacement for all `Divider()` callsites in the popover.
**When to use:** Every section boundary inside the popover. NOT in AuthView structural dividers if they serve a different purpose (use judgment per CONTEXT.md discretion).
**Example:**
```swift
// Source: Project pattern — ActivityChartView.swift:159 (the "looks cleanest" baseline)
struct StyledDivider: View {
    var body: some View {
        Divider()
            .opacity(0.3)
            .padding(.vertical, Spacing.tight)
    }
}
```

### Pattern 2: MotionConstants enum co-located in Spacing.swift
**What:** Caseless enum namespace for animation duration constants, following the existing ThemeColors/Typography/Spacing enum pattern.
**When to use:** Any `withAnimation` call in the popover. Add `.standard` (0.2s) and `.snappy` (0.15s) to cover both durations that already exist.
**Example:**
```swift
// Add to bottom of Spacing.swift, below Layout enum
enum MotionConstants {
    /// Standard section expand/collapse and metric value animation: 0.2s easeInOut.
    static let standard: Animation = .easeInOut(duration: 0.2)

    /// Snappy gesture-driven animation (session swipe, nav): 0.15s easeInOut.
    static let snappy: Animation = .easeInOut(duration: 0.15)
}
```

### Pattern 3: contentTransition for numeric Text views
**What:** Attach `.contentTransition(.numericText())` to `Text` views displaying numbers. Wrap their parent state update in `withAnimation(MotionConstants.standard)`.
**When to use:** Token counts (`TokenFormatter.format(...)`), percentages (`"\(Int(percent))%"`), cost values (`ModelPricing.formatCompactCost(...)`), session counts.
**Example:**
```swift
// Source: Apple Developer Documentation — ContentTransition.numericText(countsDown:)
// Available macOS 13.0+ (confirmed via Apple docs API JSON)
Text("\(Int(percent))%")
    .font(Typography.monoValue)
    .contentTransition(.numericText())
```

### Pattern 4: .transition(.opacity) on collapsible content
**What:** Existing `.transition(.opacity)` pattern applied to the `if !collapsed { ... }` content block in collapsible sections.
**When to use:** TokenHealthSection expanded content, ProjectUsageSection expanded content, ActivityChartView expanded content. Already exists on UsageBarsSection celebration text swap.
**Example:**
```swift
// Based on existing pattern: UsageBarsSection.swift:115
if !collapsed {
    VStack { ... }
        .transition(.opacity)
}
// Inside a withAnimation(MotionConstants.standard) { collapsed.toggle() } call
```

Note: `CollapsibleSectionHeader` already calls `withAnimation(.easeInOut(duration: 0.2)) { collapsed.toggle() }` — this is the animation driver. The `.transition(.opacity)` modifier on content blocks rides on that existing animation context. No additional `withAnimation` call needed in the section body itself.

### Pattern 5: Panel visibility gating (prep for PG-01)
**What:** The CONTEXT.md requires animations be gated on panel visibility. Currently `isPanelShowing` lives as a private `Bool` in `StatusBarManager`. Phase 7 does NOT need to implement full gating — the `onAppear`/`onDisappear` lifecycle of `UsagePopoverView` serves as the natural gate, since the view is only in the hierarchy when the panel is showing.
**When to use:** Verify that no `TimelineView` or timer-driven animation fires when `UsagePopoverView` is not visible. The existing `TimelineView` in `UsageBarsSection` is already scoped to reset countdown display — not a SwiftUI animation. Phase 9 will add explicit `isPanelOpen` propagation.
**Example:**
```swift
// The view's lifecycle already gates animations naturally:
// .onAppear — panel just opened, start rendering with transitions
// .onDisappear — panel closed, view removed from hierarchy, no animations fire
```

### Anti-Patterns to Avoid
- **Using `numericText(value:)` without #available check:** This variant requires macOS 14.0. Use `numericText()` (no arguments) which is macOS 13.0+.
- **Putting MotionConstants in its own file:** The project pattern is caseless enums co-located with related constants. `Spacing.swift` already holds both `Spacing` and `Layout` enums.
- **Adding `.animation()` modifiers to the outermost VStack:** UsagePopoverView already has `.animation(.easeInOut(duration: 0.15), value: metricModeRaw)` scoped to the ForEach section. Adding an unscoped `.animation()` higher in the tree would cause unintended animation of unrelated view changes.
- **Animating SettingsRow dividers:** SettingsRow is a settings panel, not a data display. Updating to `StyledDivider()` for visual consistency is correct, but `SettingsRow` content should NOT receive `contentTransition` on text values (settings labels are not numeric data).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Digit-rolling number animation | Custom `AnimatableModifier` or `GeometryEffect` | `.contentTransition(.numericText())` | Native SwiftUI, handles partial digit changes, composites correctly with other transitions |
| Animation constant management | Scattered literal `0.2` values | `MotionConstants` enum | Codebase already has 6 hardcoded `0.2` and 4 hardcoded `0.15` — centralize, don't duplicate the pattern |
| Conditional opacity on dividers | Per-site `.opacity(0.3)` calls | `StyledDivider` struct | 20 callsites currently diverge (bare, 0.3, 0.5) — a single struct prevents drift |

**Key insight:** SwiftUI's `.contentTransition` is designed precisely for this use case. The API understands numeric character changes and only animates the digits that change — no custom implementation can match this with less complexity.

## Common Pitfalls

### Pitfall 1: Using numericText(value:) instead of numericText()
**What goes wrong:** Code compiles against the current SDK but crashes or fails to build against macOS 13 at runtime.
**Why it happens:** There are two variants — `numericText(countsDown:)` (iOS 16/macOS 13) and `numericText(value:)` (iOS 17/macOS 14). The docs URL for `numericText(value:)` is more prominent in web search results.
**How to avoid:** Use `ContentTransition.numericText()` (the no-argument form). If counts-down direction matters, use `ContentTransition.numericText(countsDown: true/false)`. Never use `numericText(value:)` without `#available(macOS 14, *)`.
**Warning signs:** Compiler warning "is only available in macOS 14 or newer" — treat as a build failure.

### Pitfall 2: Adding transitions to views that don't update in-place
**What goes wrong:** `.contentTransition` has no effect on Text views whose value changes because SwiftUI re-creates the view (identity changes).
**Why it happens:** SwiftUI matches views by structural identity. If the parent `if/else` branch changes, the view is destroyed and recreated, not updated.
**How to avoid:** The `contentTransition` only works when the view's identity is stable and only the string content changes. For numeric displays in a stable layout (like `Text("\(Int(percent))%")`), identity is stable. For switching between `if isThrottled { Text("Throttled") } else { Text(...) }` branches, use `.transition(.opacity)` instead.
**Warning signs:** Animation plays on first appear but not on subsequent value changes.

### Pitfall 3: Breaking the existing `metricModeRaw` animation scope
**What goes wrong:** New `.animation()` modifiers interfere with the existing `ForEach` animation scoping in UsagePopoverView.
**Why it happens:** UsagePopoverView line 130 uses `.animation(.easeInOut(duration: 0.15), value: metricModeRaw)` to scope the mode-switch animation to the ForEach block. An unscoped `.animation()` further up the tree would capture all state changes.
**How to avoid:** Only add `.contentTransition` to leaf `Text` views. Do not add `.animation()` to VStack containers unless scoped to a specific value.
**Warning signs:** Sections animate unexpectedly when switching metric modes.

### Pitfall 4: StyledDivider in non-popover contexts
**What goes wrong:** Using `StyledDivider` in AuthView or SettingsRow where a stronger visual divider is appropriate.
**Why it happens:** Blanket replacement of all `Divider()` without considering context.
**How to avoid:** Only replace dividers within the main popover data sections. AuthView structural dividers (lines 40 and 149) and SettingsRow sub-section dividers (lines 39–45) serve structural rather than decorative purposes — evaluate whether 0.3 opacity looks too faint in those contexts. SettingsRow's current 0.5 is already low; standardizing to 0.3 is the locked decision but visually verify it doesn't disappear.
**Warning signs:** Settings sub-sections visually merge together with too-faint dividers.

## Code Examples

Verified patterns from official sources and existing codebase:

### StyledDivider (new file)
```swift
// Source: Derived from ActivityChartView.swift:159 pattern (project baseline)
// File: AIBattery/Views/StyledDivider.swift
import SwiftUI

/// Standardized divider for AI Battery popover sections.
/// Opacity 0.3 with Spacing.tight (2pt) vertical padding — matches ActivityChartView baseline.
struct StyledDivider: View {
    var body: some View {
        Divider()
            .opacity(0.3)
            .padding(.vertical, Spacing.tight)
    }
}
```

### MotionConstants (add to Spacing.swift)
```swift
// Source: Derived from CollapsibleSectionHeader.swift:12 (0.2s dominant pattern)
// and TokenHealthSection.swift:146 (0.15s gesture pattern)
enum MotionConstants {
    /// Standard section expand/collapse and metric value transitions.
    static let standard: Animation = .easeInOut(duration: 0.2)

    /// Snappy gesture-driven transitions (session swipe, navigation).
    static let snappy: Animation = .easeInOut(duration: 0.15)
}
```

### contentTransition on a percentage Text
```swift
// Source: Apple Developer Documentation
// ContentTransition.numericText(countsDown:) — iOS 16.0+, macOS 13.0+
// (Verified via Apple docs API JSON: introducedAt "13.0" for macOS)
Text("\(Int(percent))%")
    .font(Typography.monoValue)
    .contentTransition(.numericText())
```

### Collapsible content with .transition(.opacity)
```swift
// Source: Existing pattern — UsageBarsSection.swift:115
// The withAnimation driver is already in CollapsibleSectionHeader — content just needs the transition
if !collapsed {
    VStack(alignment: .leading, spacing: Spacing.gap) {
        // ... section content ...
    }
    .transition(.opacity)
}
```

### Replacing raw Divider() with StyledDivider
```swift
// Before (UsagePopoverView.swift:63):
Divider()

// After:
StyledDivider()

// Before (ActivityChartView.swift:159):
Divider().opacity(0.3).padding(.vertical, 2)

// After:
StyledDivider()

// Before (SettingsRow.swift:39):
Divider().opacity(0.5)

// After:
StyledDivider()
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Manual number animation with `AnimatableModifier` | `.contentTransition(.numericText())` | WWDC 2022 (iOS 16/macOS 13) | Zero-boilerplate digit-rolling animation |
| Per-site opacity/padding on Divider | `StyledDivider` view component | Phase 7 | Single truth, drift-proof |
| Hardcoded `0.2` / `0.15` animation literals | `MotionConstants.standard` / `MotionConstants.snappy` | Phase 7 | Tunable from one location |

**Deprecated/outdated:**
- Bare `Divider()` in section context: replaced by `StyledDivider()`
- `Divider().opacity(0.5)` in SettingsRow: standardized to `StyledDivider()`
- Inline `easeInOut(duration: 0.2)` literals: replaced by `MotionConstants.standard`

## Open Questions

1. **SettingsRow divider visual result**
   - What we know: Locked decision is to standardize to 0.3 opacity. Current value is 0.5.
   - What's unclear: Whether 0.3 provides sufficient visual separation between RefreshSettingsSection, DisplaySettingsSection, AlertSettingsSection, LaunchAtLoginSection in the settings panel.
   - Recommendation: Apply `StyledDivider` as decided, do a quick visual inspection during implementation. If 0.3 is too faint in that context, the discretion-area could allow SettingsRow to keep its own divider or a `StyledDivider(opacity: 0.5)` variant — but only escalate this if the visual inspection fails.

2. **AuthView divider treatment**
   - What we know: AuthView has 2 `Divider()` calls (lines 40, 149) used as structural separators in a distinct view.
   - What's unclear: Whether standardizing AuthView to `StyledDivider` provides visual benefit or just adds 0.3 opacity to already-styled structural dividers.
   - Recommendation: Apply `StyledDivider` to AuthView dividers (consistency over exceptions). AuthView is part of the same popover. Verify visually.

3. **UsageGateViews divider treatment**
   - What we know: `UsageGateViews.swift` has 2 bare `Divider()` calls at lines 12 and 29, used within gate wrapper views that sit inside `UsagePopoverView`.
   - What's unclear: Whether these are structural (between-section boundary) or content dividers.
   - Recommendation: Replace with `StyledDivider()` since they appear in the popover flow.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Swift Testing (`@Test`, `#expect`) |
| Config file | `Package.swift` — `.testTarget("AIBatteryCoreTests", ...)` |
| Quick run command | `swift test --filter "SpacingTests\|TypographyTests"` |
| Full suite command | `swift test` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| UI-06 | StyledDivider is the only divider definition used in popover | unit (compile-time) | `swift build` — verifies all callsites compile with StyledDivider | ❌ Wave 0 |
| UI-06 | MotionConstants provides .standard (0.2s) and .snappy (0.15s) | unit | `swift test --filter "MotionConstantsTests"` | ❌ Wave 0 |
| UI-07 | contentTransition is macOS 13+ (no #available guard required) | manual-only | Visual inspection — animations are inherently visual, not unit-testable | N/A |
| UI-07 | Section content wraps in .transition(.opacity) | manual-only | Visual inspection | N/A |

Note: SwiftUI view rendering cannot be unit-tested with the current test infrastructure (Swift Testing framework, no XCUITest). Animation correctness is verified through compile-time checks (APIs exist) and visual inspection.

### Sampling Rate
- **Per task commit:** `swift build` (compile-time verification all callsites updated)
- **Per wave merge:** `swift test` (full suite to ensure no regressions in Spacing/Typography tests)
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `Tests/AIBatteryCoreTests/Utilities/MotionConstantsTests.swift` — unit tests for MotionConstants.standard and MotionConstants.snappy values (REQ UI-07)
- [ ] `Tests/AIBatteryCoreTests/Views/StyledDividerTests.swift` — compile-time confirmation StyledDivider exists as a View (REQ UI-06)

Note: Existing `SpacingTests.swift` and `TypographyTests.swift` provide the pattern to follow for `MotionConstantsTests.swift`.

## Sources

### Primary (HIGH confidence)
- Apple Developer Documentation API JSON — `ContentTransition.numericText(countsDown:)` macOS 13.0+ confirmed via `https://developer.apple.com/tutorials/data/documentation/swiftui/contenttransition/numerictext(countsdown:).json`
- Apple Developer Documentation API JSON — `contentTransition(_:)` View modifier macOS 13.0+ confirmed via `https://developer.apple.com/tutorials/data/documentation/swiftui/view/contenttransition(_:).json`
- Apple Developer Documentation API JSON — `numericText(value:)` macOS 14.0 confirmed via `https://developer.apple.com/tutorials/data/documentation/swiftui/contenttransition/numerictext(value:).json`
- Project codebase — existing Divider() callsites, animation patterns, Typography/Spacing enum structure

### Secondary (MEDIUM confidence)
- Compiler verification — `xcrun swiftc -target arm64-apple-macos13.0` compiles `contentTransition(.numericText())` with exit code 0 and zero warnings

### Tertiary (LOW confidence)
- WebSearch results re: contentTransition introduction at WWDC 2022 — not independently verified against Apple source but consistent with macOS 13 introduced-at confirmation

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — Built-in SwiftUI APIs, confirmed via Apple docs JSON
- Architecture: HIGH — Directly derived from existing codebase patterns
- Pitfalls: HIGH — numericText availability confirmed authoritatively; other pitfalls from direct codebase analysis
- contentTransition macOS 13 availability: HIGH — verified via Apple Developer Documentation API JSON endpoint

**Research date:** 2026-03-19
**Valid until:** 2026-09-19 (stable SwiftUI APIs, no fast-moving parts)
