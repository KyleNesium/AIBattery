# Phase 9: Wrap-Up - Research

**Researched:** 2026-03-19
**Domain:** Spec sync (documentation) + SwiftUI animation lifecycle audit
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
None — all choices at Claude's discretion.

### Claude's Discretion
- Update spec/UI_SPEC.md to reflect new Typography, Spacing, Layout design tokens
- Update spec/ARCHITECTURE.md to reflect extracted view files and new utilities
- Verify animations don't fire when panel is closed (view lifecycle analysis + any needed gating)
- Update spec/CONSTANTS.md with design token values if not already covered

### Deferred Ideas (OUT OF SCOPE)
None.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| CQ-02 | Spec sync — update UI_SPEC.md and ARCHITECTURE.md to reflect any structural changes | Audit below identifies every gap between current spec files and post-phase-6-8 codebase |
| PG-01 | No animation runs when panel is closed — verify all new animations are gated on panel visibility | Lifecycle audit below shows natural SwiftUI view-hierarchy gating satisfies this requirement |
</phase_requirements>

## Summary

Phase 9 is a pure documentation and audit phase with zero new production code. Phases 6-8 introduced three new Utilities files (`Typography.swift`, `Spacing.swift`, and `StyledDivider.swift`), plus a `MotionConstants` enum co-located in `Spacing.swift`, none of which appear in any of the three spec files. The Architecture project tree is missing these files. CONSTANTS.md has no design token section. UI_SPEC.md uses no `Typography.`, `Spacing.`, `Layout.`, or `MotionConstants` references anywhere. All three spec files need targeted additions.

The PG-01 animation audit shows that all SwiftUI animations introduced in phases 6-8 are either (a) data-driven `.animation()` modifiers that only evaluate when a SwiftUI view is in the live hierarchy, (b) `withAnimation {}` blocks triggered by user interaction that cannot occur while the panel is closed, or (c) properly gated by `.onAppear`/`.onDisappear`. The one repeating animation in scope (auto mode glow pulse described in the spec) does not use `repeatForever` in actual code — it was **never implemented with a repeating timer**. `MetricToggleView` uses a static green shadow/stroke with no `repeatForever` call at all. The `StatusBarManager` `breathTimer` runs at the AppKit layer (not inside the NSPanel/NSHostingView), so it is not a popover view animation. The `MarqueeText` view — the only component with an ongoing scroll loop — correctly calls `cancelAndStop()` in `.onDisappear`, halting all `DispatchWorkItem` scheduling when the panel closes.

**Primary recommendation:** Write spec updates as targeted additions/amendments. No code changes are needed to satisfy PG-01.

## Gap Inventory (What to Fix)

### ARCHITECTURE.md — Missing Files

Three new files exist in `AIBattery/Utilities/` and `AIBattery/Views/` that are not in the project tree:

| File | Location | Content |
|------|----------|---------|
| `Typography.swift` | `Utilities/` | `Typography` enum — 15 named font style constants |
| `Spacing.swift` | `Utilities/` | `Spacing` enum, `Layout` enum, `MotionConstants` enum, `sectionPadding()` View extension |
| `StyledDivider.swift` | `Views/` | `StyledDivider` struct — standardized 0.3-opacity divider with tight vertical padding |

The Utilities/ comment line in ARCHITECTURE.md should have two entries added after `ThemeColors.swift`:
```
    Typography.swift       — Named font style tokens (sectionHeader, monoValue, tinyLabel, etc.)
    Spacing.swift          — Spacing/Layout/MotionConstants enums + sectionPadding() View extension
```

The Views/ section should have one entry added after `CollapsibleSectionHeader.swift`:
```
    StyledDivider.swift    — Standardized divider: Divider() at 0.3 opacity, Spacing.tight vertical padding
```

### CONSTANTS.md — Missing Design Tokens Section

No section covers Typography, Spacing, Layout, or MotionConstants. A new "Design Tokens" section is needed with three subsections:

**Typography tokens** (from `Utilities/Typography.swift`):

| Token | Value |
|-------|-------|
| `sectionHeader` | `.subheadline.bold()` |
| `chevronIcon` | `.system(size: 9, weight: .bold)` |
| `heroTitle` | `.system(size: 14)` |
| `heroValue` | `.system(size: 12, weight: .bold)` |
| `bodyLabel` | `.system(size: 11, weight: .medium)` |
| `caption` | `.caption` |
| `tinyLabel` | `.caption2` |
| `monoValue` | `.system(.headline, design: .monospaced, weight: .semibold)` |
| `monoValueMedium` | `.system(.subheadline, design: .monospaced, weight: .semibold)` |
| `monoCaption` | `.system(.caption, design: .monospaced)` |
| `monoCaptionSmall` | `.system(.caption2, design: .monospaced)` |
| `monoTiny` | `.system(size: 9, design: .monospaced)` |
| `badgeLabel` | `.system(size: 9, weight: .medium, design: .monospaced)` |
| `buttonLabel` | `.subheadline.weight(.medium)` |
| `decorativeIcon` | `.system(size: 8)` — 8pt minimum enforcing UI-05 |

**Spacing tokens** (from `Utilities/Spacing.swift`):

| Token | Value | Usage |
|-------|-------|-------|
| `Spacing.tight` | 2pt | Divider micro-gap, dot gap |
| `Spacing.small` | 4pt | Badge internal padding, minor offset |
| `Spacing.gap` | 6pt | VStack section spacing, header/footer V padding |
| `Spacing.section` | 8pt | Standard section vertical outer padding |
| `Spacing.sectionHorizontal` | 16pt | Standard section horizontal outer padding |
| `Spacing.overlay` | 24pt | Overlay and tutorial content padding |

**Layout tokens** (from `Utilities/Spacing.swift`, `Layout` enum):

| Token | Value | Usage |
|-------|-------|-------|
| `Layout.popoverWidth` | 275pt | AuthView, StatusBarManager panel width |
| `Layout.chartHeight` | 50pt | ActivityChartView height |
| `Layout.barHeight` | 8pt | UsageBar, TokenHealthSection progress bar |
| `Layout.barCornerRadius` | 3pt | Progress bar corner radius |
| `Layout.chevronFrame` | 22pt | CollapsibleSectionHeader chevron tap target |
| `Layout.dotSize` | 8pt | Health/model status dot diameter |
| `Layout.dotSizeSmall` | 6pt | Token type/status component dot diameter |

**MotionConstants** (from `Utilities/Spacing.swift`, co-located `MotionConstants` enum):

| Token | Value | Usage |
|-------|-------|-------|
| `MotionConstants.standard` | `.easeInOut(duration: 0.2)` | Section expand/collapse, settings toggle, account switch |
| `MotionConstants.snappy` | `.easeInOut(duration: 0.15)` | Session navigation, metric mode change |

The existing CONSTANTS.md `## UI Layout` and `## Animations` tables already list the raw numeric values. The new "Design Tokens" section should cross-reference those tables and note that these are the canonical Swift constants backing the numbers.

### UI_SPEC.md — Typography/Spacing Token References

UI_SPEC.md currently uses inline numeric and SwiftUI font references (e.g. `.headline`, `9pt`, `16pt horizontal`) throughout. The spec does not need a complete rewrite — the existing descriptions remain accurate. The needed update is:

1. Add a short "Design Tokens" subsection (or paragraph) in the "View Hierarchy" or "Section Specs" area noting that the canonical values are defined in `Typography`, `Spacing`, `Layout`, and `MotionConstants` enums in `Utilities/`.

2. The `## Animations` area already describes the durations; add a note that the standard (0.2s) and snappy (0.15s) durations are now accessed as `MotionConstants.standard` and `MotionConstants.snappy`.

3. Note that `StyledDivider` exists as a shared component (Divider at 0.3 opacity) and is used in place of bare `Divider()` calls between sections.

4. The auto mode button description in UI_SPEC.md says the glow uses `repeatForever` — this is **inaccurate**. The actual implementation in `MetricToggleView` uses a static green shadow/stroke controlled by an `autoMetricMode` bool. The `repeatForever` pulsing was described in the spec but not implemented. The spec should be corrected to match reality: the button uses a static green fill/stroke/shadow, no pulse animation.

## Animation Audit (PG-01)

### SwiftUI View Lifecycle = Natural Gate

All SwiftUI views in the popover are hosted inside `NSHostingView` inside `PopoverPanel` (an `NSPanel`). When the panel is hidden (`orderOut`), SwiftUI removes the hosted views from the rendering tree. This means:

- `.animation()` modifiers do not evaluate — no view layout pass occurs
- `withAnimation {}` blocks can only be triggered by user interaction (button taps, swipes) — impossible while panel is hidden
- `.contentTransition(.numericText())` only fires when SwiftUI computes a view diff — no diff occurs when panel is hidden

### Animation-by-Animation Verdict

| Location | Animation | Gated How | Safe? |
|----------|-----------|-----------|-------|
| `UsagePopoverView.swift:147` | `.animation(MotionConstants.snappy, value: metricModeRaw)` on ForEach | Value-driven; only evaluates during view layout pass | YES — panel hidden = no layout |
| `UsagePopoverView.swift:82` | `.transition(.opacity.combined(with: .move(edge: .top)))` on settings panel | Paired with `withAnimation` on button tap | YES — tap impossible when hidden |
| `MetricToggleView.swift:39` | `withAnimation(MotionConstants.standard)` on auto mode toggle | Button tap | YES — tap impossible when hidden |
| `CollapsibleSectionHeader.swift:12` | `withAnimation(MotionConstants.standard)` on collapse | Button tap | YES — tap impossible when hidden |
| `PopoverHeaderView.swift:72,178` | `withAnimation(MotionConstants.standard)` on settings/account switch | Button tap | YES — tap impossible when hidden |
| `TokenHealthSection.swift:149,170,190,205` | `withAnimation(MotionConstants.snappy)` on session navigation | Button tap / drag gesture | YES — interaction impossible when hidden |
| `ProjectUsageSection.swift:121` | `withAnimation(MotionConstants.standard)` on show-all toggle | Button tap | YES — tap impossible when hidden |
| `TutorialOverlay.swift:72,85,87` | `withAnimation` on step/dismiss | Button tap | YES — tap impossible when hidden |
| `RefreshButton.swift:12,13` | `withAnimation(.none/.easeInOut)` on rotation | Button tap | YES — tap impossible when hidden |
| `CopyableText.swift:61,67` | `withAnimation(.easeOut/.easeIn)` on clipboard icon | Click event | YES — click impossible when hidden |
| `MarqueeText.swift:74,75` | Scroll animation loop via `DispatchWorkItem` | `.onAppear` starts / `.onDisappear` calls `cancelAndStop()` | YES — `.onDisappear` fires on panel close |
| `.contentTransition(.numericText())` (multiple files) | Numeric text morph | SwiftUI view diff; only runs during layout | YES — no layout when panel hidden |
| `.transition(.opacity)` (multiple files) | Conditional content swap | `if/else` branching; requires layout pass | YES — no layout when panel hidden |
| `StatusBarManager` `breathTimer` | Star glow pulse | AppKit layer, not in NSHostingView | N/A — not a popover animation |

**Conclusion for PG-01:** No animation timer or transition runs while the panel is hidden. All 13 animation sites are gated either by (a) requiring a SwiftUI layout pass that does not occur when the panel is hidden, (b) requiring a user interaction that cannot occur when the panel is not visible, or (c) explicit `.onDisappear` teardown (`MarqueeText`). No code changes are needed.

**Audit artifact:** PG-01 can be satisfied by a code comment in `UsagePopoverView.swift` or a note in the spec — no runtime gating logic is needed because SwiftUI view lifecycle already provides it.

## What CONSTANTS.md Already Has (Do Not Duplicate)

The existing `## UI Layout` and `## Animations` tables in CONSTANTS.md already document the raw numeric values that the new design tokens represent. The new "Design Tokens" section should be **additive**: list the enum token names, their values, and cross-reference the existing tables. Do not replace the existing tables — they serve as the reference for numeric values; the new section maps Swift names to those values.

## Architecture Patterns

### Spec-Driven Workflow (Project Convention)
The `spec/` folder is the project's single source of truth. Any code change that adds files, introduces a new API pattern, or changes constants must be reflected in `spec/` before the change is considered complete. Phase 9 closes the gap opened by phases 6-8.

### Co-located Enums (Established Pattern)
`Spacing.swift` hosts three enums: `Spacing`, `Layout`, and `MotionConstants`. This is consistent with the project's established pattern of grouping related non-font spatial constants together (same decision recorded in STATE.md: "Layout enum co-located in Spacing.swift"). The spec update should note this co-location.

### Caseless Enums as Namespaces (Established Pattern)
`Typography`, `Spacing`, `Layout`, `MotionConstants`, and `ThemeColors` all use the Swift caseless enum namespace pattern. The spec update for ARCHITECTURE.md should describe each new file using this pattern for consistency with the `ThemeColors.swift` entry.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead |
|---------|-------------|-------------|
| Panel visibility detection for animation gating | Custom `isVisible` state tracking | SwiftUI view lifecycle (`.onDisappear` / view hierarchy removal) |
| Spec diffing | Manual file comparison script | Direct code reading + grep audit as done in this research |

## Common Pitfalls

### Pitfall 1: Over-correcting UI_SPEC.md
**What goes wrong:** Rewriting spec sections to use token names everywhere (e.g. replacing `"H 16, V 8"` with `"Spacing.sectionHorizontal x Spacing.section"`) makes the spec harder to scan for designers and reviewers.
**How to avoid:** Keep human-readable values in section specs. Add design token cross-reference only in a dedicated "Design Tokens" subsection or file header area.

### Pitfall 2: repeatForever Spec Discrepancy
**What goes wrong:** UI_SPEC.md describes the auto mode button as having a pulsing `.animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: autoGlowing)`. The actual code does not implement this — there is no `autoGlowing` state variable and no `repeatForever` animation in `MetricToggleView.swift`.
**How to avoid:** Update the spec to match the actual implementation: static green styling controlled by `autoMetricMode` boolean, no pulse. The "Phase 7-02" decision log says the button is green with glow — that landed without the pulse.
**Warning sign:** Grepping the codebase for `repeatForever` returns zero results in Views/.

### Pitfall 3: Asserting PG-01 Without Evidence
**What goes wrong:** Marking PG-01 complete without a documented audit trail.
**How to avoid:** The verification task should reference this audit table explicitly. The spec update for PG-01 should note "verified by code audit — all animation sites gated by SwiftUI view lifecycle."

## Code Examples

### How View Lifecycle Gates Animations (SwiftUI + NSPanel)
```swift
// Source: UIBattery/Views/StatusBarManager.swift (panel show/hide)
// When panel.orderOut(nil) is called:
// 1. NSHostingView stops rendering
// 2. SwiftUI removes all views from the live hierarchy
// 3. .onDisappear fires on every view that was visible
// 4. No further layout passes occur → no .animation() modifiers evaluate
// 5. withAnimation {} blocks are unreachable (no user input)

// MarqueeText correctly handles this:
.onAppear { beginCycle() }      // starts DispatchWorkItem scroll loop
.onDisappear { cancelAndStop() } // cancels all pending work items
```

### Design Token Usage Pattern
```swift
// Source: AIBattery/Utilities/Spacing.swift
extension View {
    func sectionPadding() -> some View {
        self
            .padding(.horizontal, Spacing.sectionHorizontal)  // 16pt
            .padding(.vertical, Spacing.section)               // 8pt
    }
}

// Source: AIBattery/Utilities/Typography.swift
enum Typography {
    static let sectionHeader: Font = .subheadline.bold()
    static let monoValue: Font = .system(.headline, design: .monospaced, weight: .semibold)
    static let tinyLabel: Font = .caption2
    static let decorativeIcon: Font = .system(size: 8)  // enforces UI-05 8pt minimum
}
```

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Swift Testing (`@Test`, `#expect`) — requires Xcode |
| Config file | `Package.swift` (`.testTarget(name: "AIBatteryCoreTests")`) |
| Quick run command | `swift test` |
| Full suite command | `swift test` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Notes |
|--------|----------|-----------|-------|
| CQ-02 | Spec files updated to match codebase | Manual review | No automated test possible for doc content accuracy |
| PG-01 | No animation fires when panel hidden | Manual / code audit | SwiftUI lifecycle behavior cannot be unit tested without a running macOS UI; verified by code audit in this research |

### Sampling Rate
- **Per task commit:** `swift test` (full suite — 706 tests, ~2 min)
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
None — existing test infrastructure covers all phase requirements. Phase 9 adds no production code and requires no new tests.

## Open Questions

1. **Auto mode pulse: spec correction vs. implementation addition**
   - What we know: spec says `repeatForever` pulse, code has static green styling
   - What's unclear: was the pulse intentionally dropped in phase 7, or was it forgotten?
   - Recommendation: STATE.md shows "green auto mode button with glow effect" in recent commits — the static glow was the intentional landing. Correct the spec to match code (static green, no pulse). Do not add the pulse implementation — it is out of scope for this phase.

## Sources

### Primary (HIGH confidence)
- Direct file reads: `AIBattery/Utilities/Typography.swift`, `Spacing.swift` — design token enum content
- Direct file reads: `AIBattery/Views/StyledDivider.swift`, `MetricToggleView.swift`, `MarqueeText.swift` — animation implementation
- Direct file reads: `spec/ARCHITECTURE.md`, `spec/UI_SPEC.md`, `spec/CONSTANTS.md` — current spec state
- Grep audit: all `withAnimation`, `.animation(`, `.transition(`, `repeatForever`, `.onAppear`, `.onDisappear` occurrences in `AIBattery/Views/` — complete animation site inventory

### Secondary (MEDIUM confidence)
- STATE.md accumulated decisions — phase 6-8 decision log confirms design token landing details

## Metadata

**Confidence breakdown:**
- Gap inventory (CQ-02): HIGH — direct file comparison, no inference
- Animation audit (PG-01): HIGH — exhaustive grep of all animation keywords, cross-referenced with SwiftUI lifecycle documentation
- Spec update prescriptions: HIGH — derived from actual file content

**Research date:** 2026-03-19
**Valid until:** Until any further spec-affecting code lands (stable — wrap-up phase, no new production code)
