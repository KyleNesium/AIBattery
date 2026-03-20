# Pitfalls Research

**Domain:** macOS menu bar app — adding UX polish to existing stable system
**Researched:** 2026-03-20
**Confidence:** HIGH (derived from project history, spec files, retrospective, and known failure modes in existing codebase)

---

## Critical Pitfalls

### Pitfall 1: Breaking the Hang-Free Guarantee During Visual Changes

**What goes wrong:**
A visual change — adding a transition, changing a modifier order, introducing an animated state — re-introduces the main-thread hang that v1.12 and v1.13 spent significant effort fixing. The hang is intermittent (not caught by unit tests) and only surfaces under normal usage conditions.

**Why it happens:**
The project has specific, hard-won rules about animation placement. `TimelineView` must not contain `.transition()` modifiers; `contentTransition(.numericText())` must not be applied to infrequently-changing values; `Timer.publish` must never appear as a stored property on a SwiftUI struct. These rules are in CLAUDE.md and the retrospective but are not enforced by tests. A polish change that looks innocuous — e.g., wrapping the timestamp in a fade — can silently violate one of these rules.

**How to avoid:**
- Before adding any animation or transition to the footer, header, or any section that contains a `TimelineView`, cross-reference against the known bad patterns in CLAUDE.md's "Important Patterns" section.
- Changes to `PopoverFooterView` (which uses `TimelineView(.periodic)` for the timestamp) are highest risk — treat as requiring explicit hang regression check.
- Prefer `withAnimation` at the call site over `.animation()` modifier on data-driven views.
- Do not add `.transition()` inside any view that is inside a `TimelineView`.

**Warning signs:**
- Any new animation modifier applied to the footer timestamp area
- `.contentTransition(.numericText())` added to values that only change every 60+ seconds
- Any new `@State` driving an animation in `PopoverFooterView` or `StatusBarManager`

**Phase to address:** Every phase touching animation or footer. Treat as a pre-commit check, not a phase-specific concern.

---

### Pitfall 2: Spec Drift During Visual Changes

**What goes wrong:**
A color value, spacing constant, or animation duration is changed in code during polish but not updated in `spec/CONSTANTS.md` or `spec/UI_SPEC.md`. Over time, the spec stops being the source of truth. Future phases make decisions based on stale spec values, causing cascading inconsistency.

**Why it happens:**
Polish phases touch many files quickly. The natural instinct is "I'll update the spec at the end." But when a phase completes and a new one starts, the spec update gets forgotten or deferred again. This happened in v1.11 (retrospective notes "spec sync" as a dedicated step in phases 6 and 8).

**How to avoid:**
- Spec sync is not an end-of-milestone task — it is a per-phase completion criterion. Each phase plan must include a spec verification step.
- When changing a value that lives in `CONSTANTS.md` (e.g., a spacing constant, animation duration, color threshold), the spec change is part of the same commit as the code change.
- Do not mark a plan as complete if any constant in the code diverges from `CONSTANTS.md`.

**Warning signs:**
- A phase that changes `MotionConstants`, `Spacing`, `Typography`, or `Layout` values without a corresponding CONSTANTS.md diff
- Any animation duration appearing as an inline literal (`.easeOut(duration: 0.3)`) instead of referencing `MotionConstants`

**Phase to address:** All phases. Phase that handles code quality / spec audit should run last as a verification sweep.

---

### Pitfall 3: Over-Animating — Making Polish Feel Heavy

**What goes wrong:**
In pursuit of "polish," too many elements gain animations simultaneously. The popover starts to feel sluggish or theatrical. Worst case: the cumulative cost of many small animations causes a measurable frame drop on older hardware (macOS 13 Ventura target includes 2019+ Macs).

**Why it happens:**
Each animation seems reasonable in isolation. A fade here, a scale there. But they compound. The popover already has: settings panel slide, metric mode ForEach animation, section expand/collapse, context health session navigation, progress bar fill, numeric text transitions, copy clipboard overlay, MarqueeText scrolling. Adding more without removing anything makes the UI feel restless.

**How to avoid:**
- New animations must replace existing ones or fill a visible gap — not stack on top.
- The rule from the existing codebase: animations only fire when they carry information (a state change the user needs to notice). Decorative animations that run on every refresh cycle are banned.
- `MotionConstants.standard` (0.15s) and `MotionConstants.snappy` (0.1s) already cover every use case. A new duration constant signals scope creep.
- Review the full animation inventory before adding any new animated element.

**Warning signs:**
- A third value added to `MotionConstants`
- Any animation with duration > 0.3s (already longer than the current maximum)
- Animations triggering on timer-driven state changes (rather than user interactions)

**Phase to address:** Any phase touching visual refinement. Enforce animation inventory review as a phase gate.

---

### Pitfall 4: Accessibility Regressions from Visual Changes

**What goes wrong:**
A label is restructured for visual clarity but the `.accessibilityElement(children: .combine)` or `.accessibilityLabel()` modifier is not updated. VoiceOver users hear fragmented or missing information. This is especially risky in the insight rows, token usage section, and context health session info — all of which have explicit accessibility work documented in `UI_SPEC.md`.

**Why it happens:**
Accessibility modifiers are applied separately from visual structure. When a view's layout changes (e.g., a row is split into two views for alignment), the accessibility annotation on the old structure no longer reflects the new structure. The change passes visual review and tests but is invisible to VoiceOver.

**How to avoid:**
- When modifying any view that has an explicit accessibility annotation in `UI_SPEC.md` (insight rows, usage bars binding badge, token section header, context health detail row), verify the VoiceOver label still makes sense after the change.
- Structural refactors (splitting HStack into sub-views, adding a wrapper for alignment) must carry accessibility annotations forward.
- The `.help()` tooltip inventory in `UI_SPEC.md` is exhaustive — if a new interactive element is added, it needs a `.help()` modifier.

**Warning signs:**
- A view with `.accessibilityElement(children: .combine)` being split into sub-views without re-annotating
- New interactive elements (buttons, toggles) without `.help()` and `.accessibilityLabel()`
- Removing a label for visual reasons when the label was carrying semantic meaning

**Phase to address:** Visual refinement phase. Add accessibility check to completion criteria.

---

### Pitfall 5: Scope Creep — "While I'm Here" Feature Additions

**What goes wrong:**
During a polish pass, a developer notices that the Projects section could show a sparkline, or that the header could show connection quality, or that the chart could add a zoom gesture. These are features, not polish. Adding them during a polish milestone bypasses requirements validation, adds untested surface area, and often doesn't get spec'd. v1.14's goal is "refine what exists" — new data or new interactions are out of scope.

**Why it happens:**
The codebase is clean and approachable. Adding a feature feels low-cost when you're already in the file. But each addition extends the milestone timeline, adds test surface, and risks introducing edge cases in otherwise stable code.

**How to avoid:**
- Define "polish" at phase planning time: spacing adjustments, color consistency, state handling completeness, error message clarity. If a change adds a new data source, new interaction model, or new section, it is a feature — defer to requirements backlog.
- The test-first rule applies here: if you can't write a unit test for a polish change, question whether it's actually polish.
- Use the PROJECT.md requirements list as the gate: does this requirement already exist in "Validated"? If not, it goes in "Active" for future consideration, not into v1.14.

**Warning signs:**
- A new `@AppStorage` key being added during a phase described as "visual refinement"
- New network calls or data sources introduced under "edge case hardening"
- Phase plan growing beyond its stated scope mid-execution

**Phase to address:** Planning phase (roadmap). Each phase plan must have explicit out-of-scope list.

---

### Pitfall 6: Design Token Bypass — Inline Literals Creeping Back

**What goes wrong:**
After v1.11 established the design token system, a polish change introduces a new inline literal: `.font(.system(size: 10))` instead of `Typography.tinyLabel`, or `.padding(12)` instead of `Spacing.sectionHorizontal`. The token system degrades incrementally. Within 2-3 milestones, the codebase is back to mixed inline/token usage, and a future consistency sweep is needed.

**Why it happens:**
The fastest path to "make this look right" is to try a literal value and move on. The designer instinct during polish is to tweak, not to look up the token name. This is especially common for one-off adjustments that "don't quite fit" any existing token.

**How to avoid:**
- All font, spacing, and animation values must use tokens. No exceptions.
- If a polish change genuinely requires a value that doesn't exist in the token system, the correct action is: add the token to the appropriate file, add it to `CONSTANTS.md`, then use it. Not: add an inline literal.
- CI does not enforce this — it must be enforced at code review.

**Warning signs:**
- `.font(.system(size: N))` anywhere outside of `Typography.swift` itself
- `.padding(N)` where N is not a `Spacing.*` value
- `.easeOut(duration: N)` where N is not `MotionConstants.*`

**Phase to address:** Code quality sweep phase (should run last, as a verification pass over all changes made during the milestone).

---

## Technical Debt Patterns

Shortcuts that seem reasonable but create long-term problems.

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Inline animation literal instead of MotionConstants | Faster to write | Token system degrades, future consistency sweep needed | Never |
| Skipping spec sync until "end of milestone" | Saves a few minutes per phase | Spec/code drift; future phases make wrong assumptions | Never |
| Adding `.animation()` to a full VStack instead of scoping it | Easier to apply | Causes entire section to animate on every state change, frame drops | Never |
| Deferring test for a "tiny visual change" | Faster iteration | Visual regressions uncatchable without snapshot tests | Only if change is a pure cosmetic constant (verified by audit) |
| Adding a new UserDefaults key without adding to UserDefaultsKeys.swift | Quick hack | Collision risk, hard to audit stored state | Never |

---

## Integration Gotchas

Common mistakes when touching the existing integrations.

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| `TimelineView` in footer | Adding `.transition()` or `.animation()` inside its content | Keep `TimelineView` content animation-free; animate parent or siblings outside |
| `NSPanel` / AppKit boundary | Using SwiftUI `.onAppear` to trigger layout dependent on panel position | Use `NSView.frameDidChangeNotification` for geometry-dependent setup |
| `@AppStorage` settings | Adding new setting without updating `UserDefaultsKeys.swift` | Always register new keys in the centralized enum first |
| Colorblind mode | Hardcoding a color instead of routing through `ThemeColors` | All color decisions go through `ThemeColors`; never use `.red`, `.orange` etc. directly in views |
| Multi-account | Testing only with single account | Always verify edge cases with the account picker visible (multi-account state) |
| `CollapsibleSectionHeader` | Duplicating collapsed state logic in a new section | Reuse `CollapsibleSectionHeader` + `@AppStorage` pattern exactly as existing sections do |

---

## Performance Traps

Patterns that work fine in tests but degrade at runtime.

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| `.animation()` on a view driven by a polling timer | Subtle jank on every 60s refresh, main thread time increases | Scope animations to user-interaction state only; never apply to `snapshot`-driven values | Immediately on every refresh cycle |
| New `GeometryReader` in a frequently-redrawn view | Layout pass storms, frame drops when panel is open | Use `GaugeBar` (single `GeometryReader`) for progress bars; use `PreferenceKey` pattern for size measurement | At any polling interval when panel is open |
| `contentTransition(.numericText())` on slowly-changing values | Unnecessary animation work on each refresh | Only apply to values that meaningfully change every poll cycle (percentages, countdown timers) | Every refresh cycle while panel is open |
| New `@Published` property driving frequent view redraws | Entire view tree re-evaluates on every change | Keep `UsageViewModel` snapshot-based; batch state changes into `UsageSnapshot` | At high polling frequency (10s interval) |

---

## Security Mistakes

Domain-specific security issues for this codebase.

| Mistake | Risk | Prevention |
|---------|------|------------|
| Logging any token value during OAuth debugging | Refresh token exposed in system logs (Console.app readable by any process) | CLAUDE.md rule: never log token values — mask or redact |
| Adding a new network call outside `SecureNetworking` | Bypasses 2MB response size guard and 30s resource timeout | All network requests must use `SecureNetworking.session` |
| Storing new sensitive data in UserDefaults instead of Keychain | Plaintext on disk, iCloud sync risk | Keychain for secrets, UserDefaults only for non-sensitive preferences |
| Adding a `.help()` tooltip that echoes sensitive data | Token values or org IDs visible in tooltip, logged by accessibility services | Tooltips must never display values from Keychain or API auth headers |

---

## UX Pitfalls

Common user experience mistakes specific to menu bar apps.

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| Adding a loading state to a section that previously showed instantly | Panel feels slower after polish — regression | Polish should never introduce new loading delays; cached data must remain available instantly |
| Changing color thresholds during a "polish" pass | Users who've calibrated their mental model of green/yellow/orange get confused | Threshold changes require explicit requirement; visual-only polish does not touch thresholds |
| Making the panel taller without checking screen edge clamping | Panel content clips off-screen on smaller displays (MacBook Air 13") | `StatusBarManager` already clamps to `screen.visibleFrame.height - 40pt`; adding content height requires verifying against minimum display |
| Error messages that show internal identifiers | Confusing to non-technical users | Error copy must be user-facing prose; internal IDs go in `os.Logger` only |
| Adding hover effects to non-interactive elements | Users expect pointer cursor = clickable | Reserve `NSCursor.pointingHand` for elements that actually respond to clicks |

---

## "Looks Done But Isn't" Checklist

Things that appear complete in isolation but are missing critical pieces.

- [ ] **New animated element**: Verify it does not fire during background refresh (panel-closed state). Check CLAUDE.md "No animation when panel closed" (PG-01) — SwiftUI lifecycle handles this naturally only if no background timers are involved.
- [ ] **New color usage**: Verify it routes through `ThemeColors` and respects colorblind mode. Test with `aibattery_colorblindMode = true`.
- [ ] **New section or row**: Verify it has a `.help()` tooltip. Check `UI_SPEC.md > Help Tooltips` to confirm coverage.
- [ ] **Visual change to an existing section**: Verify the section's accessibility label still reads correctly with VoiceOver (`UI_SPEC.md > Accessibility`).
- [ ] **New `@AppStorage` key**: Verify it is registered in `UserDefaultsKeys.swift` and documented in `CONSTANTS.md`.
- [ ] **Spec-affecting change**: Verify `spec/CONSTANTS.md` and/or `spec/UI_SPEC.md` updated in same commit as code change.
- [ ] **New animation**: Verify duration uses `MotionConstants.*`, not an inline literal.
- [ ] **Progress bar or gauge**: Uses `GaugeBar` shared component, not a new `GeometryReader`.
- [ ] **Error or empty state change**: Verify the state height matches spec (Error: 100pt, Empty: 80pt, Loading: 80pt) to prevent layout jank.
- [ ] **Footer change**: Confirm no new animation inside `TimelineView` content.

---

## Recovery Strategies

When pitfalls occur despite prevention.

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Hang re-introduced by visual change | MEDIUM | `git bisect` to find the offending commit; remove the animation modifier; document the specific failure mode in CLAUDE.md |
| Spec drift discovered | LOW | Run spec audit (compare all constants in code against CONSTANTS.md); update spec in a dedicated commit; mark affected phases as needing verification |
| Over-animation causing sluggishness | LOW | Profile with Instruments (os_signpost hooks already in place from v1.13); remove animation modifiers from timer-driven state; simplify to static transitions |
| Design token bypass discovered | LOW | Grep for inline literals (`.system(size:`, `.padding(`, `.easeOut(duration:`); replace with token references; no behavior change |
| Scope creep shipped | HIGH | Roll back the feature-level change; add requirement to PROJECT.md Active list; re-scope the phase to polish-only |

---

## Pitfall-to-Phase Mapping

How roadmap phases should address these pitfalls.

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| Breaking hang-free guarantee | Every phase touching animation or footer | Manual: open/close panel 10x after each change; automated: existing hang regression tests still pass |
| Spec drift | Per-phase completion criterion | Diff `spec/` against code constants before marking phase done |
| Over-animating | Visual refinement phase (gate: animation inventory review) | Animation count in `CONSTANTS.md > Animations` should not grow |
| Accessibility regressions | Visual refinement phase | VoiceOver manual sweep on modified sections |
| Scope creep | Roadmap/planning phase (explicit out-of-scope list per phase) | Phase plan review: no new `@AppStorage` keys, network calls, or data sources introduced |
| Design token bypass | Code quality sweep (final phase of milestone) | Grep sweep for inline literals across all changed files |
| Performance traps | Any phase touching `GeometryReader`, `@Published`, or timer-driven state | Profile panel open with Instruments after each phase that touches rendering |
| Multi-account edge cases | Edge case hardening phase | Test with 2-3 accounts active; verify account picker, settings, and all data sections |

---

## Sources

- Project retrospective: `.planning/RETROSPECTIVE.md` — v1.11 and v1.13 lessons
- Project CLAUDE.md: known failure modes (Timer.publish rule, TimelineView animation rule, contentTransition rule)
- Project memory (MEMORY.md): performance fix history from v1.9.4 and v1.12
- `spec/UI_SPEC.md`: existing accessibility annotations, help tooltip inventory, animation inventory
- `spec/CONSTANTS.md`: design token system, animation constants
- `spec/ARCHITECTURE.md`: component boundaries, data flow, known constraints

---
*Pitfalls research for: macOS menu bar app — UX polish on existing stable system (v1.14)*
*Researched: 2026-03-20*
