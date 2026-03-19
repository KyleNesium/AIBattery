# Phase 6: Design System - Research

**Researched:** 2026-03-19
**Domain:** SwiftUI design tokens — typography and spacing constants for a macOS menu bar app
**Confidence:** HIGH

## Summary

This phase extracts hardcoded font and spacing literals across ~15 view files into two new utility enums (`Typography` and `Spacing`/`Layout`) following the established `ThemeColors` pattern. The codebase was directly audited to produce exact counts and a complete token inventory.

There are **148 total `.font()` calls** across all view files: 42 `.caption2`, 35 `.caption`, 33 monospaced variants, and 38 explicit `size:` pixel calls. There are **52 `.padding()` calls** with numeric values. The dominant outer-section pattern is `.padding(.horizontal, 16)` (12 uses) + `.padding(.vertical, 8)` (5 uses), which maps to `Spacing.sectionHorizontal` and `Spacing.section`. The 6-point font appears in exactly two places: `FooterLink.swift:46` (external-link arrow icon) and `UsagePopoverView.swift:254` (update badge arrow icon) — both are `Image(systemName: "arrow.up.right")` decorators, not body text.

**Primary recommendation:** Create `Typography.swift` and `Spacing.swift` in `AIBattery/Utilities/`, then do a single-pass migration across all view files, bumping the two 6pt icon calls to 8pt minimum.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Static `Font` properties on a `Typography` enum (e.g., `Typography.sectionHeader`) — matches ThemeColors pattern, grep-friendly
- ~8-10 named styles covering actual usage: heroTitle, sectionHeader, bodyLabel, caption, tinyLabel, monoValue, monoCaption, badgeLabel, buttonLabel
- Minimum font size is 8pt — the two 6pt instances (FooterLink superscript, UsagePopoverView badge) must be bumped
- File location: `AIBattery/Utilities/Typography.swift` alongside ThemeColors.swift
- Enum `Spacing` with static `CGFloat` properties (e.g., `Spacing.section`, `Spacing.gap`) — type-safe namespace
- ~6 tokens based on actual usage: `tight` (2), `small` (4), `gap` (6), `section` (8), `sectionHorizontal` (16), `overlay` (24)
- Frame dimensions (chart height: 50, bar height: 8, popover width: 275) extracted to a separate `Layout` enum in the same file
- File location: `AIBattery/Utilities/Spacing.swift` (Spacing + Layout enums)
- One-pass migration across all views — atomic change
- Semantic SwiftUI fonts (.caption, .headline) also replaced with Typography constants — entire app goes through one system
- Consistent outer padding via `Spacing.sectionHorizontal` pattern applied uniformly to all popover sections (DS-03)
- Compile verification + unit tests that snapshot constant values to prevent regression

### Claude's Discretion
- Exact naming of each typography/spacing token (as long as they're descriptive and consistent)
- Internal organization within Typography.swift and Spacing.swift (grouping, comments)
- Whether to add any convenience View extensions for common padding patterns

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| DS-01 | Typography constants — named font styles replacing 30+ inline `.font()` calls | Audit found 148 total `.font()` calls; token inventory below maps each to a named constant |
| DS-02 | Spacing constants — unified scale replacing 8+ hardcoded spacing values | Audit found 52 padding calls; 6-token scale covers all dominant patterns |
| DS-03 | Consistent outer padding — all sections use the same horizontal/vertical pattern | 12 files use `.padding(.horizontal, 16)` already; 5 use `.padding(.vertical, 8)`, 6 use `.padding(.vertical, 6)` — one pattern needed |
| UI-05 | Minimum font size audit — no text below 8pt | Exactly 2 occurrences of `size: 6` found: FooterLink.swift:46 and UsagePopoverView.swift:254 (both decorative arrow icons) |
</phase_requirements>

---

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| SwiftUI | macOS 13+ (built-in) | Font/padding modifier system | Already in use throughout app |
| Swift | 5.9+ (built-in) | Enum + static property pattern | Zero dependencies, matches ThemeColors pattern |

No external libraries needed. This is pure Swift/SwiftUI constant extraction.

**Installation:** None required.

---

## Architecture Patterns

### Recommended File Structure
```
AIBattery/Utilities/
├── ThemeColors.swift         # existing — sibling pattern to follow
├── Typography.swift          # NEW — Typography enum with static Font properties
└── Spacing.swift             # NEW — Spacing enum (CGFloat) + Layout enum (CGFloat)
```

### Pattern 1: ThemeColors-style Enum with Static Properties

**What:** Caseless enum used as a namespace. Static `let` properties return the typed constant. No instances needed.

**When to use:** Any app-wide constant set where consumers need autocomplete and the type system to prevent misuse.

**Example (matching existing ThemeColors pattern):**
```swift
// Typography.swift
import SwiftUI

enum Typography {
    // MARK: - Section headers
    /// CollapsibleSectionHeader title text
    static let sectionHeader: Font = .subheadline.bold()
    /// Chevron icon inside section headers
    static let chevronIcon: Font = .system(size: 9, weight: .bold)

    // MARK: - Hero / large values
    /// Large numeric displays (e.g. rate limit %, session count)
    static let heroTitle: Font = .system(size: 14)
    /// Primary bold metric (e.g. token count in UsagePopoverView)
    static let heroValue: Font = .system(size: 12, weight: .bold)

    // MARK: - Body text
    /// Standard body label in settings rows and auth view
    static let bodyLabel: Font = .system(size: 11, weight: .medium)
    /// Section sub-labels, footer text
    static let caption: Font = .caption
    /// Small auxiliary text, timestamps
    static let tinyLabel: Font = .caption2

    // MARK: - Monospaced values
    /// Primary monospaced numeric display (rate limit %, large values)
    static let monoValue: Font = .system(.headline, design: .monospaced, weight: .semibold)
    /// Medium monospaced value (project names, token counts)
    static let monoValueMedium: Font = .system(.subheadline, design: .monospaced, weight: .semibold)
    /// Standard monospaced caption (model IDs, small tokens)
    static let monoCaption: Font = .system(.caption, design: .monospaced)
    /// Small monospaced caption (byte counts, secondary metrics)
    static let monoCaptionSmall: Font = .system(.caption2, design: .monospaced)
    /// Tiny monospaced label (inline session dot labels)
    static let monoTiny: Font = .system(size: 9, design: .monospaced)

    // MARK: - Badges & labels
    /// Badge/tag label text (e.g. "binding" pill)
    static let badgeLabel: Font = .system(size: 9, weight: .medium, design: .monospaced)
    /// Button/action label text (e.g. "Install Update")
    static let buttonLabel: Font = .subheadline.weight(.medium)
    /// Minimum decorative icon — 8pt floor (replaces all size:6 calls)
    static let decorativeIcon: Font = .system(size: 8)
}
```

**Note on 8pt minimum:** The two `size: 6` calls in `FooterLink.swift:46` and `UsagePopoverView.swift:254` are both `Image(systemName: "arrow.up.right")` decorative icons. They map to `Typography.decorativeIcon` (size: 8), satisfying UI-05.

```swift
// Spacing.swift
import CoreGraphics

/// Spacing scale — use these instead of hardcoded numeric padding values.
enum Spacing {
    /// 2pt — divider micro-gap, dot gap
    static let tight: CGFloat = 2
    /// 4pt — badge internal padding, minor offset
    static let small: CGFloat = 4
    /// 6pt — VStack section spacing, header/footer vertical padding
    static let gap: CGFloat = 6
    /// 8pt — standard section vertical outer padding
    static let section: CGFloat = 8
    /// 16pt — standard section horizontal outer padding (12 uses in codebase)
    static let sectionHorizontal: CGFloat = 16
    /// 24pt — overlay/tutorial padding
    static let overlay: CGFloat = 24
}

/// Fixed frame dimensions — pixel values that describe UI geometry, not spacing rhythm.
enum Layout {
    /// Popover panel width (2 uses: AuthView, StatusBarManager)
    static let popoverWidth: CGFloat = 275
    /// Activity/token health chart height (4 uses)
    static let chartHeight: CGFloat = 50
    /// Progress bar height (UsageBar, TokenHealthSection)
    static let barHeight: CGFloat = 8
    /// Bar corner radius
    static let barCornerRadius: CGFloat = 3
    /// Chevron button tap target
    static let chevronFrame: CGFloat = 22
    /// Health/model status dot diameter
    static let dotSize: CGFloat = 8
    /// Token type / status component dot diameter
    static let dotSizeSmall: CGFloat = 6
}
```

### Pattern 2: Consistent Outer Section Padding (DS-03)

**What:** All popover sections use identical outer padding: `Spacing.sectionHorizontal` horizontal, `Spacing.section` vertical. Currently there is inconsistency — some sections use `.vertical, 8`, others use `.vertical, 6`.

**Audit findings:**
- `.padding(.horizontal, 16)` + `.padding(.vertical, 8)`: ActivityChartView, ProjectUsageSection, TokenHealthSection, UsageBarsSection (×2) — these are correct
- `.padding(.horizontal, 16)` + `.padding(.vertical, 6)`: UsagePopoverView (cost section, status section, model tokens section), SettingsRow — these need bumping to `.section` (8pt) for DS-03

**Decision required during planning:** Whether `.vertical, 6` sections should become 8pt (pure DS-03 conformance) or whether 6pt is intentional for those denser sections. The CONTEXT.md says "all sections use the same horizontal/vertical pattern" — treat 8pt as the universal standard.

**Optional convenience extension (Claude's discretion):**
```swift
extension View {
    /// Applies the standard popover section outer padding.
    func sectionPadding() -> some View {
        self
            .padding(.horizontal, Spacing.sectionHorizontal)
            .padding(.vertical, Spacing.section)
    }
}
```

### Anti-Patterns to Avoid

- **Mixing old and new:** After migration, zero bare `.font(.system(size: N))` calls should remain in view files. The compile check catches residue.
- **Testing the view layer directly:** Do not try to write SwiftUI snapshot tests. The test strategy (snapshot constant values) tests the constants themselves, not the views.
- **Partial migration:** The CONTEXT.md decision is one-pass atomic — do not leave some files migrated and others not. Inconsistency is worse than the starting state.
- **Over-extracting Layout:** Only extract frame dimensions that appear 2+ times or are semantically significant (popover width, chart height). One-off values like column widths computed at runtime do not belong in Layout.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Font system | Custom font loading, dynamic type scaling | Static SwiftUI Font constants | macOS menu bar app uses fixed-size design; dynamic type is iOS-focused |
| Spacing system | Protocol-based or generics-heavy system | Plain enum with static CGFloat | Matches ThemeColors pattern; simpler, grep-friendly |
| Constant snapshots | Reflection-based generic test utility | Direct `#expect(Typography.caption == .caption)` per token | Compiler verifies types; test just locks values |

**Key insight:** In a macOS menu bar app at a fixed 275pt width, a minimal token vocabulary (8-10 type styles, 6 spacing values) is sufficient and preferable to a full-scale design system. Do not import or mimic iOS design token libraries.

---

## Common Pitfalls

### Pitfall 1: Incomplete Font Inventory Leads to Residue
**What goes wrong:** Migrating only the obvious `.font(.system(size: N))` calls while leaving `.font(.caption2)`, `.font(.headline)`, etc. untouched.
**Why it happens:** Semantic font names look "clean" and don't feel like literals.
**How to avoid:** Replace ALL `.font()` calls including semantic ones — the CONTEXT.md decision is explicit that semantic fonts also go through Typography.
**Warning signs:** Grep for `.font(.caption` after migration; should return zero results in view files.

### Pitfall 2: The `.vertical, 6` vs `.vertical, 8` Inconsistency
**What goes wrong:** Migrating some sections to `Spacing.section` (8) and others to `Spacing.gap` (6), preserving the inconsistency in constant form.
**Why it happens:** Developer preserves existing numeric values when assigning tokens.
**How to avoid:** DS-03 requires uniformity. Every outer-section vertical padding becomes `Spacing.section` (8pt). Sections currently at 6pt get bumped. Inner spacing (e.g., VStack spacing, badge padding) can use `Spacing.gap`.

### Pitfall 3: Layout Enum Scope Creep
**What goes wrong:** Extracting every frame dimension into Layout, including one-off column widths, icon sizes, etc.
**Why it happens:** Once the enum exists, it's tempting to move everything there.
**How to avoid:** Layout only contains values that define the outer skeleton (popover width, chart height, bar height, corner radius, dot sizes, chevron frame). Column widths computed from GeometryReader stay local.

### Pitfall 4: Test Strategy Mismatch
**What goes wrong:** Writing UI snapshot tests (which don't work without a running app/renderer) or skipping tests entirely.
**Why it happens:** Confusion about what to test for a "constants" file.
**How to avoid:** Tests assert the constant values themselves:
```swift
@Test func typography_caption_isCaption() {
    #expect(Typography.caption == Font.caption)
}
@Test func spacing_sectionHorizontal_is16() {
    #expect(Spacing.sectionHorizontal == 16)
}
```
This is lightweight and prevents accidental value changes during future refactors.

### Pitfall 5: MarqueeText Font Parameter
**What goes wrong:** Trying to replace the `.font(font)` call in `MarqueeText.swift` — this is a parameter, not a literal.
**Why it happens:** The grep finds it as a `.font()` call.
**How to avoid:** `MarqueeText` receives `font: Font` as an init parameter and passes it through. The callers of `MarqueeText` that pass a specific font value are the ones to migrate. Do not change the pass-through itself.

---

## Code Examples

Verified patterns from codebase audit:

### Before / After Migration Example
```swift
// BEFORE
Text("5h Usage")
    .font(.subheadline.bold())
// AFTER
Text("5h Usage")
    .font(Typography.sectionHeader)

// BEFORE
Text(tokenCount)
    .font(.system(.headline, design: .monospaced, weight: .semibold))
// AFTER
Text(tokenCount)
    .font(Typography.monoValue)

// BEFORE
.padding(.horizontal, 16)
.padding(.vertical, 8)
// AFTER
.padding(.horizontal, Spacing.sectionHorizontal)
.padding(.vertical, Spacing.section)
// OR using the convenience extension:
.sectionPadding()

// BEFORE (UI-05 violation)
Image(systemName: "arrow.up.right")
    .font(.system(size: 6))
// AFTER
Image(systemName: "arrow.up.right")
    .font(Typography.decorativeIcon)  // size: 8
```

### Test Pattern (matching ThemeColorsTests.swift style)
```swift
// Tests/AIBatteryCoreTests/Utilities/TypographyTests.swift
import Testing
import SwiftUI
@testable import AIBatteryCore

@Suite("Typography")
struct TypographyTests {
    @Test func caption_isCaption() {
        #expect(Typography.caption == Font.caption)
    }
    @Test func tinyLabel_isCaption2() {
        #expect(Typography.tinyLabel == Font.caption2)
    }
    @Test func decorativeIcon_meetsMinimumSize() {
        // Minimum 8pt — verifies UI-05 floor
        // Font equality is sufficient; size:8 >= size:6
        #expect(Typography.decorativeIcon == Font.system(size: 8))
    }
}

// Tests/AIBatteryCoreTests/Utilities/SpacingTests.swift
@Suite("Spacing")
struct SpacingTests {
    @Test func sectionHorizontal_is16() {
        #expect(Spacing.sectionHorizontal == 16)
    }
    @Test func section_is8() {
        #expect(Spacing.section == 8)
    }
    @Test func gap_is6() {
        #expect(Spacing.gap == 6)
    }
}

@Suite("Layout")
struct LayoutTests {
    @Test func popoverWidth_is275() {
        #expect(Layout.popoverWidth == 275)
    }
    @Test func chartHeight_is50() {
        #expect(Layout.chartHeight == 50)
    }
    @Test func barHeight_is8() {
        #expect(Layout.barHeight == 8)
    }
}
```

---

## Migration Scope (Full Audit)

Files requiring migration (all in `AIBattery/Views/`):

| File | Font calls | Padding calls | Notes |
|------|-----------|---------------|-------|
| UsagePopoverView.swift | ~50 | 8 | Contains both 6pt violations |
| ActivityChartView.swift | ~22 | 4 | chart height frame uses; outer padding correct already |
| AuthView.swift | ~16 | 2 | `.padding(16)` uniform — maps to `sectionPadding()` |
| ProjectUsageSection.swift | ~13 | 2 | outer padding correct already |
| TokenHealthSection.swift | ~9 | 2 | outer padding correct already |
| UsageBarsSection.swift | ~12 | 4 | outer padding correct (×2 sections) |
| FooterLink.swift | 3 | 0 | Contains 1 of the 6pt violations |
| Settings/SettingsRow.swift | 7 | 2 | Uses `.vertical, 6` — bump to 8 for DS-03 |
| Settings/AlertSettingsSection.swift | 5 | 1 | |
| Settings/DisplaySettingsSection.swift | 4 | 2 | |
| Settings/RefreshSettingsSection.swift | 4 | 2 | |
| Settings/LaunchAtLoginSection.swift | 2 | 1 | |
| CollapsibleSectionHeader.swift | 2 | 0 | `size: 8, weight: .bold` → `Typography.chevronIcon` |
| CopyableText.swift | 1 | 2 | `.font(font)` is pass-through — skip |
| TutorialOverlay.swift | 4 | 1 | `.padding(24)` → `Spacing.overlay` |
| RefreshButton.swift | 1 | 0 | |

**MarqueeText.swift:** The `.font(font)` call is a parameter pass-through — do not replace it. Callers using MarqueeText that specify fonts are in the list above.

---

## Typography Token Map (Exhaustive)

| Raw Pattern (most used) | Count | Proposed Token |
|-------------------------|-------|----------------|
| `.caption2` | 42 | `Typography.tinyLabel` |
| `.caption` | 35 | `Typography.caption` |
| `.system(.caption, design: .monospaced)` | 11 | `Typography.monoCaption` |
| `.system(size: 9)` | 9 | `Typography.monoTiny` (where monospaced context) or `Typography.tinyLabel` |
| `.system(.caption2, design: .monospaced)` | 7 | `Typography.monoCaptionSmall` |
| `.system(size: 9, design: .monospaced)` | 5 | `Typography.monoTiny` |
| `.system(size: 8)` | 5 | `Typography.decorativeIcon` (min 8pt floor) |
| `.system(size: 10)` | 4 | review in context — likely `Typography.tinyLabel` or new token |
| `.headline` | 3 | `Typography.sectionHeader` (non-bold usage) |
| `.system(size: 6)` | 2 | `Typography.decorativeIcon` (bumped to 8pt, UI-05 fix) |
| `.system(size: 14)` | 2 | `Typography.heroTitle` |
| `.system(size: 11, weight: .medium)` | 2 | `Typography.bodyLabel` |
| `.system(.headline, design: .monospaced, weight: .semibold)` | 2 | `Typography.monoValue` |
| `.subheadline.weight(.medium)` | 2 | `Typography.buttonLabel` |
| `.subheadline.bold()` | 2 | `Typography.sectionHeader` |
| `.system(.subheadline, design: .monospaced, weight: .semibold)` | 1 | `Typography.monoValueMedium` |
| `.system(.caption2, design: .monospaced, weight: .medium)` | 1 | `Typography.monoCaptionSmall` (or new weighted variant) |
| `.system(.caption, design: .monospaced, weight: .medium)` | 1 | `Typography.monoCaption` (or new weighted variant) |
| `.caption.weight(.semibold)` | 1 | `Typography.caption` with `.fontWeight(.semibold)` inline, or dedicated token |
| `.system(size: 9, weight: .medium, design: .monospaced)` | 1 | `Typography.badgeLabel` |
| `.system(size: 9, weight: .heavy, design: .rounded)` | 1 | one-off — keep inline or add `Typography.autoModeLabel` |
| `.system(size: 9, weight: .bold)` | 1 | `Typography.chevronIcon` (or `Typography.monoTiny`) |
| `.system(size: 8, weight: .bold)` | 1 | `Typography.chevronIcon` |
| `.system(size: 28)` | 1 | `Typography.heroTitle` (TutorialOverlay large icon — may need dedicated token) |
| `.system(size: 13)` | 1 | review — AuthView step number |
| `.system(size: 12, weight: .bold)` | 1 | `Typography.heroValue` |
| `.system(size: 11, weight: .semibold, design: .monospaced)` | 1 | `Typography.monoCaption` with semibold or new token |
| `.system(size: 10, weight: .semibold, design: .monospaced)` | 1 | `Typography.badgeLabel` variant |
| `.title3` | 1 | one-off in settings — keep inline or add `Typography.settingsTitle` |

**Planner note:** The "Claude's Discretion" items (exact token naming) mean the planner can refine the names above, but the mapping strategy is established.

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Inline `.font(.system(size: N))` | Named Typography constants | This phase | Grep-friendly, prevents magic numbers |
| Inline padding numbers | `Spacing.X` constants | This phase | Consistent rhythm, one-edit changes |
| `spec/CONSTANTS.md` lacking UI section | Add Design Tokens section after implementation | This phase | Spec stays in sync |

**Deprecated/outdated after this phase:**
- Bare `.font(.caption)` in view files: replaced by `Typography.caption`
- Bare `.font(.system(size: 6))` anywhere: removed entirely (8pt floor)
- `.padding(.horizontal, 16)`: replaced by `Spacing.sectionHorizontal`

---

## Open Questions

1. **`size: 10` context — 4 uses**
   - What we know: Appears in ActivityChartView, SettingsRow, RefreshButton, ProjectUsageSection
   - What's unclear: Whether these are the same semantic role (small value display) or different
   - Recommendation: Planner should read each callsite — if same role, one token; if different, 2 tokens

2. **`.padding(16)` in AuthView vs `.padding(.horizontal, 16)` + `.padding(.vertical, 8)`**
   - What we know: `AuthView` uses `.padding(16)` (uniform all-sides), not the two-part section pattern
   - What's unclear: Whether AuthView should get the `sectionPadding()` treatment or keep its distinct uniform padding
   - Recommendation: AuthView is a full-screen auth flow, not a popover section — keep `.padding(Spacing.sectionHorizontal)` uniform or add a dedicated `Layout.authPadding = 16` constant

3. **`size: 28` in TutorialOverlay (emoji icon)**
   - What we know: `TutorialOverlay.swift:43` uses `size: 28` for a large instruction icon
   - What's unclear: Whether a dedicated Typography token is needed for a view used once
   - Recommendation: This is a one-off overlay; inline `.font(.system(size: 28))` is acceptable, or add `Typography.overlayIcon` — planner decides

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Swift Testing (`@Test`, `#expect`) |
| Config file | `Package.swift` — `.testTarget("AIBatteryCoreTests", ...)` |
| Quick run command | `swift test --filter TypographyTests` |
| Full suite command | `swift test` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| DS-01 | Typography constants have correct values | unit | `swift test --filter TypographyTests` | ❌ Wave 0 |
| DS-02 | Spacing constants have correct values | unit | `swift test --filter SpacingTests` | ❌ Wave 0 |
| DS-02 | Layout constants have correct values | unit | `swift test --filter LayoutTests` | ❌ Wave 0 |
| DS-03 | Outer padding is uniform (structural — no bare 16/8 in views) | compile-time (grep post-migration) | `grep -rn 'padding(.horizontal, 16)' AIBattery/Views/ \| wc -l` should be 0 | N/A |
| UI-05 | No font below 8pt (no `size: 6` in views) | compile-time (grep post-migration) | `grep -rn 'size: 6' AIBattery/Views/ \| wc -l` should be 0 | N/A |

### Sampling Rate
- **Per task commit:** `swift test --filter TypographyTests && swift test --filter SpacingTests`
- **Per wave merge:** `swift test`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `Tests/AIBatteryCoreTests/Utilities/TypographyTests.swift` — covers DS-01
- [ ] `Tests/AIBatteryCoreTests/Utilities/SpacingTests.swift` — covers DS-02 (Spacing + Layout)

*(Framework and test infrastructure already exist — only new test files needed)*

---

## Sources

### Primary (HIGH confidence)
- Direct codebase audit — `AIBattery/Views/**/*.swift` (grep, Read tool)
- `AIBattery/Utilities/ThemeColors.swift` — established enum-with-static-properties pattern
- `spec/CONSTANTS.md` — existing UI Layout constants section (popover width 275, bar height 8, etc.)
- `Tests/AIBatteryCoreTests/Utilities/ThemeColorsTests.swift` — test pattern to replicate

### Secondary (MEDIUM confidence)
- CONTEXT.md locked decisions — all token names and values from user decisions

### Tertiary (LOW confidence)
- None

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no external libraries, pure Swift pattern extraction
- Architecture: HIGH — directly modeled on ThemeColors.swift which is already in the codebase
- Pitfalls: HIGH — found via direct code audit (exact file/line numbers for 6pt violations, exact counts)
- Token inventory: HIGH — every `.font()` call was enumerated; mapping is thorough

**Research date:** 2026-03-19
**Valid until:** Stable — these constants describe the current codebase state. Re-audit if new views are added before planning begins.
