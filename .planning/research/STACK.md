# Stack Research

**Domain:** macOS menu bar app — UX polish & visual refinement milestone
**Researched:** 2026-03-20
**Confidence:** HIGH (Apple frameworks verified via official docs + community sources)

---

## Context

This is a polish milestone on top of a validated, shipping stack. The existing stack (Swift/SwiftUI, SPM, macOS 13+, Sparkle 2, Apple frameworks) is NOT changing. This document covers only the **APIs and techniques needed for polish work** and what to avoid over-engineering.

Existing design token system: `MotionConstants` (standard 0.15s easeOut, snappy 0.1s easeOut), `Typography`, `Spacing`, `Layout`, `ThemeColors`.

---

## Recommended Stack — Polish-Specific Additions

### Animation APIs

| API | Availability | Purpose | Why Recommended |
|-----|-------------|---------|-----------------|
| `.spring(duration:bounce:)` | macOS 13+ | Interactive feel for expand/collapse | More natural than easeOut for state-driven layout changes; `.bounce: 0` gives easeOut-equivalent without overshoot |
| `.symbolEffect(.bounce)` | macOS 14+ | One-shot icon feedback on success/error states | Discrete, plays once, zero overhead when not triggered; gated by `@available` |
| `.symbolEffect(.pulse)` | macOS 14+ | Indefinite low-key pulse for "loading" icon states | Better than a spinner overlay; requires macOS 14 guard |
| `.contentTransition(.numericText())` | macOS 13+ | Digit-roll animation when counters update | Already partially used — verify all numeric values have it consistently |
| `.transition(.asymmetric(...))` | macOS 13+ | Different in/out transitions for banners and state cards | Already available; use for enter=slide+fade, exit=fade only |

**Key constraint:** `symbolEffect` requires macOS 14+. The app targets macOS 13+, so any `symbolEffect` usage needs `@available(macOS 14, *)` guards. Do NOT raise the deployment target for this.

### Accessibility APIs

| API | Availability | Purpose | Why |
|-----|-------------|---------|-----|
| `.accessibilityValue(_:)` | macOS 13+ | Dynamic state values on sliders, progress bars | Existing sliders use this — audit for gaps in gauge bars and percentage displays |
| `.accessibilityAdjustableAction` | macOS 13+ | Increment/decrement for VoiceOver on custom controls | Already on TokenHealthSection session toggle — apply pattern to MetricToggle |
| `.accessibilityAddTraits(.updatesFrequently)` | macOS 13+ | Marks live-updating labels so VoiceOver re-reads | Apply to countdown timers and percentage labels that change each poll |
| `.accessibilityHidden(true)` | macOS 13+ | Suppress decorative elements from VoiceOver tree | Apply to star icons, dividers, decorative dots |
| `.accessibilityAction(named:_:)` | macOS 13+ | Named custom actions on complex views | Expose "Copy details" as a named action on session info rows |

### Visual Refinement APIs

| API | Availability | Purpose | Why |
|-----|-------------|---------|-----|
| `.help(_:)` | macOS 13+ | Hover tooltip text | Already used widely — audit for missing tooltips on icon-only buttons |
| `NSCursor.pointingHand` via `.onHover` | macOS 13+ | Pointer cursor on clickable elements | Already on `CopyableModifier` — audit that all tappable non-button elements use it |
| `.buttonStyle(.plain)` + manual hover state | macOS 13+ | Custom button hover styling | Prefer over `.borderedProminent` in dense popover context — matches existing patterns |
| `RoundedRectangle(cornerRadius:style: .continuous)` | macOS 13+ | Squircle corners vs circular corners | Continuous curve style matches macOS system UI more closely than `.circular` |
| `Color.primary.opacity(0.05)` hover fills | macOS 13+ | Subtle row hover states | Use for any clickable row that lacks hover feedback; consistent with `CopyableModifier` pattern |

### No New Dependencies

Do not add any new SPM packages for polish work. All required APIs are in Apple frameworks. Adding a library to solve a polish problem (e.g., a "better animations" library) adds maintenance surface for zero gain on macOS.

---

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| `.phaseAnimator` / `.keyframeAnimator` | macOS 14+ only, heavyweight for simple state changes | `withAnimation(.spring(...))` for state transitions |
| `SensoryFeedback` / `.sensoryFeedback` | macOS 14+ haptics, but macOS menu bar context gives no trackpad feedback benefit | Skip — adds complexity with no perceptible UX gain |
| `ContentUnavailableView` | macOS 14+ only, and existing empty state views are already designed and tested | Keep the existing `PopoverStateViews` pattern |
| `.matchedGeometryEffect` | High complexity, causes layout thrash in VStack-based popovers with dynamic height | Use `.transition` + `withAnimation` instead |
| Raising deployment target to macOS 14 | Excludes Ventura users; no user-visible benefit that justifies it | Gate macOS 14+ features with `@available` |
| Third-party animation libraries | No existing SPM dependency, adds maintenance surface | SwiftUI native animations cover all polish needs |
| `Timer.publish` in SwiftUI structs | Causes timer accumulation freeze (known project pitfall from v1.9 performance work) | `TimelineView(.periodic(...))` — already the project standard |

---

## Stack Patterns by Variant

**For state-driven expand/collapse (settings panel, sections):**
- Use `withAnimation(MotionConstants.standard)` — existing standard
- Consider `MotionConstants.standard` with `.spring(duration: 0.15, bounce: 0)` as a drop-in refinement (same feel, more natural deceleration curve)

**For icon feedback on user actions (copy, refresh, success):**
- macOS 13 path: swap symbol + brief `@State` toggle with `withAnimation(MotionConstants.snappy)` — already the pattern in `CopyableModifier`
- macOS 14+ path: `.symbolEffect(.bounce, value: triggered)` inside `@available(macOS 14, *)` — cleaner but optional upgrade

**For numeric values that update on each poll:**
- `.contentTransition(.numericText())` on `Text` views showing counts, percentages, token totals — already used in some places, audit for consistency

**For hover feedback on interactive rows:**
- `.onHover { isHovering in }` + `@State var isHovering` + `Color.primary.opacity(isHovering ? 0.07 : 0)` background — the `CopyableModifier` pattern, reuse it

**For accessibility on progress indicators:**
- `.accessibilityValue("\(Int(percent))%")` on `GaugeBar` views
- `.accessibilityAddTraits(.updatesFrequently)` on timer-driven labels (countdown, timestamps)

---

## Version Compatibility

| API | macOS 13 | macOS 14 | macOS 15 | Notes |
|-----|----------|----------|----------|-------|
| `contentTransition(.numericText())` | YES | YES | YES | Safe for all targets |
| `withAnimation(.spring(...))` | YES | YES | YES | Safe for all targets |
| `.symbolEffect(.bounce)` | NO | YES | YES | Requires `@available(macOS 14, *)` guard |
| `.symbolEffect(.pulse)` | NO | YES | YES | Requires `@available(macOS 14, *)` guard |
| `.sensoryFeedback` | NO | YES | YES | Skip — not worth the guard complexity |
| `.phaseAnimator` | NO | YES | YES | Skip for polish milestone |
| `ContentUnavailableView` | NO | YES | YES | Skip — existing pattern is fine |

---

## Installation

No new packages. All APIs are in the existing import set:

```swift
import SwiftUI   // all animation, transition, accessibility APIs
import AppKit    // NSCursor for hover cursors
```

---

## Sources

- Apple WWDC23 "Animate symbols in your app" — `symbolEffect` requires iOS 17 / macOS 14 (HIGH confidence, official Apple session)
- Apple Developer Forums thread on `contentTransition(.numericText())` — confirmed macOS 13+ availability (MEDIUM confidence)
- SwiftUI for Mac 2024 (TrozWare) — macOS-specific SwiftUI behavior and availability (MEDIUM confidence, community source)
- Existing codebase audit — confirmed current patterns: `CopyableModifier`, `MotionConstants`, `accessibilityAdjustableAction`, `contentTransition(.numericText())` partial usage (HIGH confidence, primary source)
- `spec/UI_SPEC.md` + `AIBattery/Utilities/Spacing.swift` — existing animation and spacing token definitions (HIGH confidence, codebase)

---
*Stack research for: AIBattery v1.14 Polish & UX milestone*
*Researched: 2026-03-20*
