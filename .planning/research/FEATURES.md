# Feature Research

**Domain:** macOS menu bar utility app — polish & UX improvements
**Researched:** 2026-03-20
**Confidence:** HIGH (based on Apple HIG, community patterns, existing codebase audit)

---

## Context: What Already Exists

This is a subsequent milestone — the app is feature-complete at v1.13. The full data pipeline
(OAuth, rate limits, JSONL tokens, context health, activity charts, notifications, Sparkle) is
shipped. This research focuses exclusively on polish, UX refinement, and edge case hardening.

What is already implemented (do not re-research):
- Error state (inline retry), empty state, loading state — UI-SPEC section confirmed
- Colorblind mode toggle
- Tutorial overlay (3-step first-run walkthrough)
- VoiceOver labels on insight rows, cost section, usage bars, context health
- `.help()` tooltips on all major interactive elements
- Collapsible sections with `@AppStorage` persistence
- Click-to-copy on all numeric values
- Staleness dimming on menu bar icon (`appearsDisabled` after 5 min)
- MotionConstants (standard 0.15s, snappy 0.1s)

---

## Feature Landscape

### Table Stakes (Users Expect These)

Features users assume exist. Missing these = product feels incomplete or unpolished.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Respect `Reduce Motion` system setting | Users with vestibular sensitivity depend on this; HIG requirement | LOW | Check `UIAccessibility.isReduceMotionEnabled`; gate all `withAnimation` calls. Already have MotionConstants — add a `reduceMotion` guard. |
| Respect `Increase Contrast` system setting | High-contrast users need bolder borders, less opacity-based styling | LOW | `NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast`; affects badge fills, divider opacities, gauge track fills |
| Keyboard dismissal (Escape) | Any floating panel/popover should close on Escape | LOW | Already implemented via `NSEvent.addLocalMonitorForEvents`. Verify works at all states including settings open, tutorial visible |
| Consistent hover cursor (pointer hand) | Clickable text/values should show pointer; non-interactive should show arrow | LOW | `.copyable()` modifier already uses `NSCursor.pointingHand`. Audit buttons and links for cursor consistency |
| Readable text at all system font sizes | macOS allows user to increase font size; layout should not break | MEDIUM | Use `scaledFont` or `.dynamicTypeSize` limits; critical for caption2/tiny labels that break first |
| VoiceOver accessible panel navigation | Full sequential tab-order through the panel; every interactive element labeled | MEDIUM | Existing coverage is partial (insight rows, cost section). Settings controls, footer links, MetricToggle, RefreshButton all need audit |
| Non-ambiguous error messages | "An error occurred" is useless; "Could not reach api.anthropic.com (timeout)" is useful | LOW | Audit existing `PopoverStateViews` error copy; ensure retry button is always reachable |
| Graceful degradation when stale | If data is >5 min old, visually indicate staleness throughout the panel, not just the icon | LOW | `appearDisabled` on status icon exists. Add stale badge or muted styling inside the popover too |
| Settings persist across launches | All user preferences survive app restart | LOW | `@AppStorage` already handles this. Verify all new toggles use `@AppStorage`, not `@State` |
| Clear empty states per section | Each data section needs its own empty state when its data is unavailable (not just the global one) | MEDIUM | Global empty state exists. Section-level: Projects section when no JSONL cwd data; Context Health when no active sessions; Activity chart for no-history state |

### Differentiators (Competitive Advantage)

Features that elevate the experience beyond the baseline. Not strictly required, but they're what
makes an app feel crafted vs. merely functional.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Smooth section reorder animation | When auto-mode switches the primary section, sections reorder with a fluid animation rather than a hard swap | MEDIUM | `ForEach` with `.animation(MotionConstants.snappy)` already scoped. Verify IDs are stable across reorder so SwiftUI diffing animates rather than rebuilds |
| Contextual empty state copy | Empty states that explain *why* there is no data ("Rate limit data updates after your first API call") vs. generic "No data" | LOW | High signal-to-noise value. Requires knowing which data source is missing per section |
| Number formatting consistency | Tokens: "18.9M", Cost: "~$12", Times: "4h 32m" — all use compact forms. Audit for inconsistencies (e.g. "0.3M" should be "300K") | LOW | Audit `TokenFormatter` and cost formatters for sub-1M token values and sub-$1 cost values |
| Subtle loading skeleton on refresh | Instead of spinner-on-blank, show the last data with a shimmer/pulse overlay while refreshing | HIGH | Complex to implement well; existing cached data display (`APIFetchResult.isCached`) already covers this partially. Only worthwhile if refresh feels jarring in practice |
| Tooltip for every non-obvious value | Values like "API Equivalent" cost, burn rate, "binding" badge, cache hit % all deserve tooltip explanations | LOW | `.help()` tooltips exist for most. Audit remaining unlabeled values: burn rate projections, cache % meaning, "binding" concept for new users |
| Section collapse preserves summary | Collapsed section header shows a one-line summary (Tokens: "~$12 · 18.9M", Activity: "+12% vs yesterday") | LOW | Already implemented for Tokens, Projects, Activity. Verify Context Health collapsed summary is meaningful |
| Copy entire section as text | "Copy section" affordance on each section header for power users who want to paste stats into a report or message | MEDIUM | `.copyable()` exists on individual values. Section-level copy needs a `SectionCopyFormatter` per section |
| Keyboard shortcut to open | Global hotkey (Cmd+Shift+A or user-configured) to show/focus the panel without clicking the menu bar | HIGH | Requires `NSEvent.addGlobalMonitorForEvents`. Configurability adds significant complexity. Likely v2+ unless trivial to add a hardcoded shortcut |

### Anti-Features (Commonly Requested, Often Problematic)

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Dark/light mode toggle in settings | Users want to override system appearance | Diverges from system appearance contract; causes visual inconsistency with other menu bar apps; maintenance burden | App already adapts to system appearance automatically. If user wants different appearance, they use System Settings |
| Custom color themes | Personalization | Multiplies test surface; color accessibility becomes unverifiable; most users never use it after novelty wears off | Colorblind mode already addresses the real accessibility need |
| Animation speed slider | "Control over animations" | Almost no user changes it; adds settings complexity; `Reduce Motion` system preference handles the real use case | Respect system `Reduce Motion` preference — this covers 95% of the actual need |
| Font size slider | Readability control | Breaks carefully tuned layouts; macOS `Larger Text` in Accessibility covers this at system level | Test with system Larger Text accessibility setting; don't add a separate in-app control |
| Notification for every poll cycle | "Always know what's happening" | Notification spam; defeats the purpose of a glanceable utility | Status icon + optional threshold-based alerts already cover the real need |
| Historical data export (CSV/JSON) | Power users want data portability | Reads JSONL which is already the source — no new data. Heavy implementation for a niche use case | The JSONL files themselves are the export; document where they live |
| Multiple simultaneous panels | "See all accounts at once" | Breaks the menu bar utility mental model; complex window management; multi-account support already exists via account switcher | Account switcher in header handles this cleanly |

---

## Feature Dependencies

```
Respect Reduce Motion
    └──requires──> MotionConstants (already exists)
    └──enables──> disable/reduce withAnimation calls throughout

Respect Increase Contrast
    └──requires──> ThemeColors (already exists)
    └──enables──> thicker borders, higher opacity fills, bolder track backgrounds

Section-level empty states
    └──requires──> Gate views (ProjectUsageGate, InsightsGate) — already exist
    └──enhances──> contextual empty state copy

VoiceOver full coverage
    └──requires──> accessibilityLabel on all controls
    └──enhances──> accessibilityHint for complex interactions (metric toggle, session swipe)

Number formatting consistency audit
    └──enhances──> all display values (no direct dependency)

Tooltip completeness audit
    └──enhances──> all .help() sites (no structural dependency)
```

### Dependency Notes

- **Reduce Motion requires MotionConstants:** The existing `MotionConstants` enum is the single place to add a `reduceMotion` computed property. All call sites use these constants so a single change gates all animations.
- **Increase Contrast requires ThemeColors:** `ThemeColors` centralizes all opacity-based colors. Adding `increasedContrast` variants is additive and safe.
- **Section-level empty states require Gate views:** `ProjectUsageGate` and `InsightsGate` are already the right place to add per-section empty state rendering — no new architecture needed.

---

## MVP Definition

Since this is a polish milestone, "MVP" here means: the minimum set of polish features that meaningfully raise the quality bar without risk of regressions.

### Must-Do (v1.14)

These are gaps or rough edges that a quality-conscious user will notice:

- [ ] Respect `Reduce Motion` system preference — gates all animation calls, prevents discomfort for accessibility users
- [ ] Respect `Increase Contrast` system preference — improves readability for high-contrast users without visual regression risk
- [ ] VoiceOver audit — complete the existing partial coverage; Settings panel and MetricToggle are currently the biggest gaps
- [ ] Tooltip completeness audit — verify every non-obvious value has a `.help()` tooltip; add missing ones
- [ ] Number formatting consistency audit — audit sub-1M token values, sub-$1 costs, edge-case time formats
- [ ] Section-level empty states — Projects (no JSONL cwd data) and Context Health (no active sessions) need contextual empty copy
- [ ] Contextual error messages — audit existing error states for specificity; generic messages should explain the likely cause

### Add When Straightforward (v1.14 if low-risk)

- [ ] Stale data visual indicator inside the panel (not just menu bar icon dimming)
- [ ] Section collapsed summary audit — verify all sections show a useful summary when collapsed
- [ ] Hover cursor consistency audit — verify all clickable elements use pointer cursor

### Future Consideration (v1.15+)

- [ ] Keyboard shortcut to open panel — requires global event monitoring, non-trivial
- [ ] Copy-entire-section affordance — useful for power users but not broadly needed
- [ ] Smooth section reorder animation — investigate whether SwiftUI diffing already handles this correctly

---

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Respect Reduce Motion | HIGH (accessibility compliance) | LOW (MotionConstants gate) | P1 |
| Respect Increase Contrast | HIGH (accessibility compliance) | LOW (ThemeColors variants) | P1 |
| VoiceOver full audit | HIGH (accessibility compliance) | MEDIUM (many touch points) | P1 |
| Tooltip completeness | MEDIUM (discoverability) | LOW (add .help() calls) | P1 |
| Number formatting consistency | MEDIUM (trust/polish) | LOW (audit + fix formatter) | P1 |
| Section-level empty states | MEDIUM (UX clarity) | LOW (gate view copy changes) | P1 |
| Contextual error messages | MEDIUM (debuggability) | LOW (copy changes only) | P1 |
| Stale data inside-panel indicator | LOW (icon dimming covers this) | LOW | P2 |
| Collapsed summary audit | LOW (already mostly correct) | LOW (audit + copy tweaks) | P2 |
| Hover cursor audit | LOW (mostly correct already) | LOW | P2 |
| Copy-entire-section | LOW (values are individually copyable) | MEDIUM | P3 |
| Smooth section reorder animation | LOW (current snap is acceptable) | MEDIUM | P3 |
| Global keyboard shortcut | LOW (menu bar is easy to click) | HIGH | P3 |

**Priority key:**
- P1: Must have for v1.14 milestone
- P2: Include if no regression risk
- P3: Defer to later milestone

---

## Competitor / Reference Analysis

Reference apps studied for patterns (macOS menu bar utilities):

| Pattern | iStat Menus | Stats (open source) | AIBattery current | AIBattery v1.14 target |
|---------|-------------|---------------------|-------------------|------------------------|
| Reduce Motion respect | Yes | Partial | Not implemented | Add via MotionConstants gate |
| Increase Contrast adapt | Yes | No | Not implemented | Add via ThemeColors |
| VoiceOver labels | Comprehensive | Basic | Partial | Complete audit |
| Per-section empty states | Yes | Yes | Global only | Add section-level copy |
| Stale data indicator | Icon-level | Icon-level | Icon-level only | Add panel-level hint |
| Tooltip / .help() coverage | Comprehensive | Basic | Good (most values) | Complete the remaining gaps |
| Copy-to-clipboard | Select values | No | All values | No change needed |
| First-run tutorial | Modal | None | 3-step overlay | No change needed |

---

## Sources

- Apple Human Interface Guidelines — [Popovers](https://developer.apple.com/design/human-interface-guidelines/popovers), [Designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos)
- Apple Accessibility — [Developer resources](https://developer.apple.com/accessibility/), macOS `NSAccessibility`, `NSWorkspace` accessibility display options
- [Smashing Magazine — Graceful Degradation in Accessible Interface Design (2024)](https://www.smashingmagazine.com/2024/12/importance-graceful-degradation-accessible-interface-design/)
- [A11Y Collective — Keyboard Navigation on macOS](https://www.a11y-collective.com/blog/how-to-activate-keyboard-navigation-on-macos/)
- Existing codebase — `spec/UI_SPEC.md`, `spec/CONSTANTS.md`, `.planning/PROJECT.md` (v1.13 shipped state)
- Community: macOS menu bar utility patterns observed in iStat Menus, Stats (open source), Bartender, Ice

---

*Feature research for: macOS menu bar app polish & UX improvements (v1.14)*
*Researched: 2026-03-20*
