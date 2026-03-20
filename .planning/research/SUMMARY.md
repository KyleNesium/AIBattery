# Project Research Summary

**Project:** AIBattery v1.14 — Polish & UX Refinement Milestone
**Domain:** macOS menu bar utility — UX polish, accessibility, and edge case hardening on a shipped v1.13 base
**Researched:** 2026-03-20
**Confidence:** HIGH

## Executive Summary

AIBattery v1.14 is a polish milestone on a feature-complete, shipping macOS menu bar app. The stack (Swift/SwiftUI, SPM, macOS 13+, Sparkle 2) is stable and not changing. All required APIs for polish work are available in existing Apple frameworks — no new dependencies are needed. The approach is to refine what exists: close accessibility gaps, enforce design token consistency, tighten error and empty state UX, and add missing system preference integrations (`Reduce Motion`, `Increase Contrast`) — without introducing new features or new data sources.

The recommended execution order is bottom-up through the design system: start with token and shared component changes that propagate globally, then work through per-section polish in isolation, then perform a dedicated accessibility pass once visual structure is stable, and finish with a code quality sweep to catch any inline literal or spec drift introduced during the milestone. This order minimizes blast radius: the riskiest changes (global token modifications) happen when the codebase is cleanest, and section-specific changes are isolated by design.

The primary risk is not the polish changes themselves — it is accidental regression of the hang-free guarantee established in v1.12/v1.13. Adding animations or transitions near `TimelineView` (used in `PopoverFooterView`) or applying `.contentTransition(.numericText())` to slowly-changing values can re-introduce main-thread hangs that are invisible in tests but surface under normal usage. Every phase that touches animation must cross-reference the known bad patterns in CLAUDE.md before committing.

## Key Findings

### Recommended Stack

No new dependencies required. All polish-relevant APIs are in `SwiftUI` and `AppKit`, both already imported. The existing design token system (`MotionConstants`, `Typography`, `Spacing`, `Layout`, `ThemeColors`) covers every polish use case. The only meaningful API additions are accessibility modifiers already available on macOS 13+ and `symbolEffect` (macOS 14+, requires `@available` guard). The deployment target stays at macOS 13 — raising it would exclude Ventura users with no user-visible benefit.

**Core technologies:**
- `SwiftUI` animation APIs (`.spring(duration:bounce:)`, `.contentTransition(.numericText())`, `.transition(.asymmetric(...))`) — cover all polish animation needs within existing macOS 13 target
- `SwiftUI` accessibility APIs (`.accessibilityValue`, `.accessibilityAddTraits(.updatesFrequently)`, `.accessibilityHidden`) — complete the partial VoiceOver coverage without structural changes
- `AppKit` (`NSCursor.pointingHand`, `NSStatusItem` accessibility APIs) — hover cursor and menu bar button accessibility via `StatusBarManager`
- `symbolEffect(.bounce/.pulse)` — macOS 14+ only, gated with `@available`; optional upgrade for icon feedback on success/error states

**What NOT to add:** `.phaseAnimator`, `.matchedGeometryEffect`, `SensoryFeedback`, `ContentUnavailableView`, `Timer.publish`, third-party animation libraries.

### Expected Features

The app is feature-complete. This milestone closes quality gaps, not feature gaps. Research identified 7 P1 items (accessibility compliance and UX clarity) and 3 P2 items (low-risk quality-of-life audits).

**Must have (P1 — v1.14):**
- Respect `Reduce Motion` system preference — gates all `withAnimation` calls via `MotionConstants`; HIG requirement for vestibular accessibility
- Respect `Increase Contrast` system preference — adds bolder borders/fills via `ThemeColors` variants; HIG requirement for high-contrast users
- VoiceOver full audit — Settings panel, MetricToggle, footer logout flow, menu bar button are the current gaps
- Tooltip completeness audit — audit remaining unlabeled values (burn rate, cache %, "binding" concept)
- Number formatting consistency audit — sub-1M token values, sub-$1 costs, edge-case time formats
- Section-level empty states — Projects (no JSONL cwd data) and Context Health (no active sessions) need contextual copy
- Contextual error messages — audit for specificity; generic messages must explain the likely cause

**Should have (P2 — v1.14 if no regression risk):**
- Stale data visual indicator inside the panel (icon dimming exists; panel-level reinforcement)
- Collapsed section summary audit — verify all sections show meaningful one-line summaries
- Hover cursor consistency audit — verify all clickable non-button elements use pointer cursor

**Defer (v1.15+):**
- Global keyboard shortcut to open panel — requires `NSEvent.addGlobalMonitorForEvents`, non-trivial
- Copy-entire-section affordance — useful for power users but individually-copyable values cover the need
- Smooth section reorder animation — investigate whether SwiftUI diffing already handles this correctly

**Anti-features confirmed out of scope:** dark/light mode override, custom color themes, animation speed slider, font size slider, notification-per-poll, CSV/JSON data export, multiple simultaneous panels.

### Architecture Approach

Polish work operates entirely within the existing layered architecture (AppKit layer → SwiftUI view layer → design system layer → ViewModel → services). The design system (`Utilities/`) is the single source of truth for all token values. Three archetypal change paths exist: (1) modify a `Utilities/` enum value to propagate globally, (2) modify a shared component (`GaugeBar`, `StyledDivider`, `CollapsibleSectionHeader`) to reach all consumers, or (3) make an isolated change in a single section file. Path 1 and 2 have high leverage and require verifying all downstream consumers; path 3 has zero blast radius.

**Major components affected by polish:**
1. `ThemeColors` — add `Reduce Motion` guard in `MotionConstants`, add `Increase Contrast` variants in `ThemeColors`; these two changes cascade to the entire app
2. `PopoverStateViews` — primary target for error/empty state UX; isolated, low-risk
3. `GaugeBar`, `CollapsibleSectionHeader` — shared components; single change reaches all gauges and all collapsible sections respectively
4. Individual section files — `UsageBarsSection`, `TokenHealthSection`, `ProjectUsageSection`, `InsightsView` — section-level polish in isolation
5. `StatusBarManager` — AppKit layer; sets `NSStatusItem` accessibility label (only place for menu bar button accessibility)

### Critical Pitfalls

1. **Breaking the hang-free guarantee** — adding `.transition()` inside a `TimelineView`, applying `.contentTransition(.numericText())` to slowly-changing values, or using `Timer.publish` as a stored property on a SwiftUI struct re-introduces the main-thread hang fixed in v1.12/v1.13. Gate check: before committing any animation change touching the footer, cross-reference CLAUDE.md "Important Patterns."

2. **Spec drift** — changing a constant in code without updating `spec/CONSTANTS.md` or `spec/UI_SPEC.md`. The spec is the source of truth by project convention. Prevention: spec sync is a per-phase completion criterion, not an end-of-milestone task.

3. **Over-animating** — each animation seems reasonable in isolation but compounds. The popover already has 8+ animation contexts. New animations must replace or fill a visible gap, not stack. `MotionConstants.standard` (0.15s) and `MotionConstants.snappy` (0.1s) cover every use case — a new duration constant is a scope creep signal.

4. **Accessibility regressions from visual changes** — restructuring a view layout without carrying `.accessibilityElement(children: .combine)` or `.accessibilityLabel()` forward produces silent regressions invisible to visual review. Every modified view with existing accessibility annotations must be VoiceOver-verified after the change.

5. **Design token bypass** — inline literals (`.font(.system(size: N))`, `.padding(N)`, `.easeOut(duration: N)`) degrade the token system incrementally. If a needed value doesn't exist as a token, add the token first, then use it. No exceptions.

6. **Scope creep** — polish changes that introduce new data sources, new interactions, or new `@AppStorage` keys during a "visual refinement" phase. Gate check: does this requirement exist in the validated requirements list? If not, defer.

## Implications for Roadmap

Based on combined research, a 4-phase structure is recommended. All phases are polish-only — no new features, no new data sources.

### Phase 1: System Preference Integration & Design Token Foundation
**Rationale:** The highest-leverage, lowest-risk changes come first. `Reduce Motion` and `Increase Contrast` integrations touch `MotionConstants` and `ThemeColors` — the same files that will be referenced throughout all subsequent phases. Establishing correct token behavior first ensures later changes inherit the right behavior automatically. These are also the most important accessibility compliance items.
**Delivers:** `Reduce Motion` gating on all animations, `Increase Contrast` variants in `ThemeColors`, updated `CONSTANTS.md` for any new constants added
**Addresses:** Respect Reduce Motion (P1), Respect Increase Contrast (P1)
**Avoids:** Design token bypass (Pitfall 6), spec drift (Pitfall 2)

### Phase 2: Visual Polish & Shared Component Refinement
**Rationale:** With the token foundation stable, shared component changes propagate safely. GaugeBar fill animation, StyledDivider consistency, and any spacing/typography adjustments benefit from Phase 1's token correctness. Section-by-section visual polish follows the scanning order (rate limit bars → context health → tokens → projects → insights → header → footer). Footer changes are last due to `TimelineView` hang risk.
**Delivers:** Consistent hover cursor behavior, updated `GaugeBar` fill animation, number formatting consistency, stale data panel-level indicator, section collapsed summary audit
**Addresses:** Number formatting consistency (P1), Stale data indicator (P2), Collapsed summary audit (P2), Hover cursor audit (P2)
**Avoids:** Breaking hang-free guarantee (Pitfall 1) by treating footer as highest-risk last; over-animating (Pitfall 3) via animation inventory review gate

### Phase 3: Error State, Empty State & Contextual Messaging
**Rationale:** Error and empty states are isolated in `PopoverStateViews` and per-section gate views — zero blast radius changes that don't interact with the design token or animation systems. Doing this after visual polish means the visual context (spacing, typography) is stable before copy/messaging is finalized.
**Delivers:** Contextual error messages with specific failure causes, section-level empty states for Projects and Context Health, improved empty state copy throughout
**Addresses:** Section-level empty states (P1), Contextual error messages (P1)
**Avoids:** Scope creep (Pitfall 5) by keeping changes to copy and conditional rendering only

### Phase 4: Accessibility Audit & Code Quality Sweep
**Rationale:** Accessibility changes are purely additive (labels, hints, traits) and never affect visual layout — they are safest to do last when visual structure is stable. The code quality sweep (grep for inline literals, spec audit) is a verification pass over everything done in Phases 1-3. Running it last ensures it catches any token bypasses or spec drift introduced during execution.
**Delivers:** Complete VoiceOver coverage (Settings panel, MetricToggle, footer logout, menu bar button, rate limit bars), `.help()` tooltip completeness, spec sync verification, inline literal sweep
**Addresses:** VoiceOver full audit (P1), Tooltip completeness audit (P1)
**Avoids:** Accessibility regressions (Pitfall 4) by treating this as a dedicated sweep; spec drift (Pitfall 2) via final verification

### Phase Ordering Rationale

- Token system first: `Reduce Motion` and `Increase Contrast` changes cascade through the entire app — establishing these before any other visual change ensures correctness is inherited, not retrofitted
- Footer last within Phase 2: `PopoverFooterView` uses `TimelineView` and is the highest hang-regression risk; isolating it as the last visual touch point minimizes cascading risk
- Accessibility after visual: structural changes to views during Phase 2 can affect accessibility tree shape; auditing after visual work is stable avoids double-verification
- Code quality sweep last: catches any bypass or drift introduced during execution of Phases 1-3; cannot meaningfully run earlier

### Research Flags

Phases with standard patterns (skip additional research):
- **Phase 1 (System Preferences):** `NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast` and `UIAccessibility.isReduceMotionEnabled` are well-documented; existing `MotionConstants` and `ThemeColors` provide the integration points — no research needed
- **Phase 2 (Visual Polish):** All APIs are in existing import set, well-understood within the codebase
- **Phase 3 (Error/Empty States):** Pure copy and conditional rendering changes in isolated files
- **Phase 4 (Accessibility):** Patterns established in existing code (`CopyableModifier`, `CollapsibleSectionHeader` accessibility label); audit methodology is well-understood

No phases require `/gsd:research-phase` during planning — the codebase itself is the primary reference source for all implementation decisions.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All APIs verified against official Apple docs + existing codebase; no new dependencies or external integrations |
| Features | HIGH | Derived from Apple HIG requirements, competitor analysis, and direct codebase audit; all P1 items have clear implementation paths |
| Architecture | HIGH | Research derived entirely from live codebase and spec — not inferred from external sources |
| Pitfalls | HIGH | Derived from project retrospective, CLAUDE.md documented failure modes, and v1.9/v1.12/v1.13 performance fix history |

**Overall confidence:** HIGH

### Gaps to Address

- **VoiceOver reading order verification:** The architecture research identifies known gaps (metric toggle, footer, menu bar button) but cannot confirm whether additional gaps exist without a live VoiceOver sweep. Handle during Phase 4 execution — treat as discovery work, not pre-known fixes.
- **`Increase Contrast` integration depth:** The correct API is `NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast` but the specific list of views/colors requiring contrast variants will only be fully known after a visual audit pass. Treat Phase 1 as establishing the infrastructure; Phase 4 as the verification.
- **Animation inventory completeness:** PITFALLS.md identifies 8+ existing animation contexts but the full count is not confirmed. Perform explicit animation inventory at Phase 2 start before adding any new animated element.

## Sources

### Primary (HIGH confidence)
- `/Users/kyle/workspace/Github/KyleNesium/AIBattery/spec/ARCHITECTURE.md` — live architecture spec
- `/Users/kyle/workspace/Github/KyleNesium/AIBattery/spec/UI_SPEC.md` — accessibility annotations, tooltip inventory, animation inventory
- `/Users/kyle/workspace/Github/KyleNesium/AIBattery/spec/CONSTANTS.md` — design token definitions
- `/Users/kyle/workspace/Github/KyleNesium/AIBattery/CLAUDE.md` — documented failure modes (Timer.publish rule, TimelineView animation rule)
- Project MEMORY.md — performance fix history (v1.9.4, v1.12, v1.13)
- Project retrospective `.planning/RETROSPECTIVE.md` — v1.11 and v1.13 lessons

### Secondary (MEDIUM confidence)
- Apple WWDC23 "Animate symbols in your app" — `symbolEffect` macOS 14+ availability confirmed
- Apple Human Interface Guidelines — Popovers, Designing for macOS, Accessibility
- Apple Developer Forums — `contentTransition(.numericText())` macOS 13+ availability
- SwiftUI for Mac 2024 (TrozWare) — macOS-specific SwiftUI behavior

### Tertiary (MEDIUM confidence)
- iStat Menus, Stats (open source) — menu bar utility UX patterns for competitor reference
- Smashing Magazine — Graceful Degradation in Accessible Interface Design (2024)
- A11Y Collective — Keyboard Navigation on macOS

---
*Research completed: 2026-03-20*
*Ready for roadmap: yes*
