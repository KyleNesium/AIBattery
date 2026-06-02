> **ARCHIVED — one-off QA checklist for the v2.3.1 release (current version is v2.4.2+).**
> Kept for historical context only; not a living document. Referenced nowhere in the build.

# v2.3.1 — Manual QA Checklist

A deliberate manual walkthrough of every popover state touched by the v2.3.1
polish sprint. Run before tagging. Anything that fails blocks the release.

**Build to test:** `.build/AIBattery.app` produced by `./scripts/build-app.sh`
on `fix/popover-polish-v2.3.1`.

**Setup:**

```bash
pkill -f "AIBattery.app" 2>/dev/null
SPARKLE_EDDSA_PUBLIC_KEY="6OMshMFo6tpWjrJHcDa1xKK4N0xqgT+gery+xnGJrOU=" ./scripts/build-app.sh
open .build/AIBattery.app
```

> Tester records pass/fail/notes inline. Anything not pass = blocker until
> resolved or explicitly waived.

---

## 1. Header row — alignment + content

Click the menu-bar icon. Look at the top row of the popover.

| # | Check | Pass criteria | Result |
|---|-------|---------------|:------:|
| 1.1 | Title alignment | "AI Battery" baseline ≈ visual center of "User N" picker. Picker is NOT visibly lower than title. | |
| 1.2 | Version | `vX.Y.Z` text reads `v2.3.1` |  |
| 1.3 | Update-check icon | Sits at same visual height as gear icon |  |
| 1.4 | Gear icon | Visually centered with title row |  |
| 1.5 | Hover gear | Hovering brightens gear from .secondary → .primary |  |
| 1.6 | Click gear | Settings panel cross-fades in (no slide-down, no jump) |  |
| 1.7 | Click gear again | Settings cross-fades out, popover height changes smoothly |  |

## 2. Settings panel

Open settings (click gear).

| # | Check | Pass criteria | Result |
|---|-------|---------------|:------:|
| 2.1 | "Add Account" link | Renders with plus.circle icon at `Typography.tinyLabel` size, text at `Typography.caption`, ThemeColors.action blue. Identical visual to before. |  |
| 2.2 | Click "Add Account" | AuthView slides in (this is intentional cross-view, not cross-fade) |  |
| 2.3 | AuthView "Sign in" CTA | Uses `ThemeColors.action` tint (not generic `.accentColor` — should match Add Account blue exactly) |  |
| 2.4 | AuthView cancel | Cancel button works, returns to popover with settings still open |  |
| 2.5 | Refresh slider | Slider still labelled, ticks every 30s/1m/2m/3m/4m/5m |  |
| 2.6 | Hide-idle slider | Six positions: 30m, 1h, 2h, 4h, 8h, ∞ |  |
| 2.7 | "Test" alert button | Renders as a LinkActionButton compact (tinyLabel + action color, no icon) |  |
| 2.8 | Tab between settings controls | Each focusable control receives a visible focus ring (CollapsibleSectionHeader sites at minimum) |  |

## 3. Account picker

With ≥1 account configured, click the picker label.

| # | Check | Pass criteria | Result |
|---|-------|---------------|:------:|
| 3.1 | Menu opens | Each account row shows display name or "Account N" + checkmark on active |  |
| 3.2 | Switch account | Picker label updates, snapshot refreshes |  |
| 3.3 | "Add Account" menu item | Visible when canAddAccount; triggers AuthView |  |
| 3.4 | VoiceOver picker | Reads "Switch account, Select which Claude account to display" (no missing hint) |  |

## 4. Update banner (only verifiable if an update is published)

If `viewModel.availableUpdate` is non-nil:

| # | Check | Pass criteria | Result |
|---|-------|---------------|:------:|
| 4.1 | Banner cross-fades in | Pure opacity, no slide |  |
| 4.2 | "Install Update" button | LinkActionButton compact style with arrow.down.circle icon |  |
| 4.3 | "Download" button | LinkActionButton compact style, no icon |  |
| 4.4 | Dismiss x | xmark.circle.fill at `Typography.bodyLabel` size — NOT visibly larger than sibling icons |  |
| 4.5 | Click dismiss | Banner cross-fades out (no jump) |  |
| 4.6 | Click update-check icon (top right) | Banner re-shows by cross-fade |  |
| 4.7 | VoiceOver Install Update | Reads "Install update version X.Y.Z, Downloads and installs the update" |  |

## 5. Usage / rate-limit sections

In default state (5h selected):

| # | Check | Pass criteria | Result |
|---|-------|---------------|:------:|
| 5.1 | 5h gauge renders | Bar fills proportionally, percent text on right |  |
| 5.2 | Reset countdown ticks | "Resets in Xm Ys" updates every 10s, or every 1s if <60s away |  |
| 5.3 | Switch to 7d | Cross-fade only, no slide; new gauge renders |  |
| 5.4 | Switch to Context Health | Cross-fade only |  |
| 5.5 | Auto-mode toggle | "A" button transitions to/from active state; ring color matches |  |

## 6. Context Health — session navigation

With ≥2 sessions visible:

| # | Check | Pass criteria | Result |
|---|-------|---------------|:------:|
| 6.1 | Click right chevron | Session info cross-fades to next session (NO horizontal slide) |  |
| 6.2 | Click left chevron | Cross-fades back (NO slide) |  |
| 6.3 | Swipe right on row | Drag gesture navigates same way as chevron |  |
| 6.4 | Last session | Right chevron disabled |  |
| 6.5 | First session | Left chevron disabled |  |
| 6.6 | VoiceOver prev/next | Each reads label + hint (e.g. "Previous session, Browses to the previous recent session") |  |

## 7. Footer

| # | Check | Pass criteria | Result |
|---|-------|---------------|:------:|
| 7.1 | Status dot — operational | Plain green circle, no glyph inside |  |
| 7.2 | Status dot — degraded | Yellow circle with white "!" SF Symbol inside |  |
| 7.3 | Status dot — partial outage | Orange circle with white "x" inside |  |
| 7.4 | Status dot — major outage | Red circle with white "x" inside |  |
| 7.5 | Status dot — maintenance | Blue circle with white wrench glyph inside |  |
| 7.6 | Usage link hover | Underline appears AND text brightens (.secondary → .primary) |  |
| 7.7 | Usage link focus (Tab key) | Same dual signal as hover |  |
| 7.8 | Status link hover/focus | Same dual signal |  |
| 7.9 | Logout idle | "Logout" in .secondary |  |
| 7.10 | Click Logout once | Text becomes "Confirm?" in ThemeColors.danger red |  |
| 7.11 | Wait 3s after first click | Reverts to "Logout" automatically |  |
| 7.12 | Click Logout twice within 3s | Signs out active account |  |
| 7.13 | Logout hover | Underline + slightly brighter |  |
| 7.14 | Quit hover/focus | Underline + brighter; text uses ThemeColors.secondaryLabel |  |
| 7.15 | Click Quit | App terminates |  |
| 7.16 | Incident banner | If active incident: triangle icon + cycling MarqueeText replaces "Updated Xs ago" |  |

> **States 7.2–7.5 require a degraded/down Anthropic status to verify against
> real data.** If status.claude.com is healthy, mock by temporarily setting
> a fake `ClaudeSystemStatus` in DEBUG. Otherwise capture screenshots once
> a real incident occurs and attach to this checklist.

## 8. Local-estimate fallback

When `snapshot.rateLimits == nil && snapshot.isUsingLocalEstimate`:

| # | Check | Pass criteria | Result |
|---|-------|---------------|:------:|
| 8.1 | Local estimate header renders | Info button beside label with caution-yellow tint |  |
| 8.2 | VoiceOver info button | Reads "Why usage is estimated locally, Opens an explanation in your browser" |  |
| 8.3 | Percent text VoiceOver | Reads with metric anchor: "5-Hour usage X percent" (NOT bare "X percent") |  |

## 9. Insights — cost rows

With Insights section expanded:

| # | Check | Pass criteria | Result |
|---|-------|---------------|:------:|
| 9.1 | Per-model rows render | Model name, optional ▶ for active, cost ~$X, token count |  |
| 9.2 | Active model glyph | ▶ in success-green |  |
| 9.3 | Throttle warning glyph | If throttled count > 0, exclamationmark.triangle.fill appears beside "Throttled: N×" |  |
| 9.4 | VoiceOver per-model row | Reads as ONE combined element: "Sonnet 4.6, active, ~$0.42, 18.3K tokens" |  |
| 9.5 | VoiceOver throttle row | Reads "Throttled: 3×" — does NOT separately announce the warning glyph |  |

## 10. Tutorial overlay (first launch only)

If you've never dismissed the tutorial OR you reset `tutorialShown`:

| # | Check | Pass criteria | Result |
|---|-------|---------------|:------:|
| 10.1 | Backdrop renders | Dim black overlay over popover content |  |
| 10.2 | Step indicators | 3 dots — active = action blue, inactive = secondary at 0.45 opacity |  |
| 10.3 | Tap step indicator | Advances to that step |  |
| 10.4 | "Got it" closes overlay | Popover content visible again |  |

## 11. Light mode / dark mode

System Settings → Appearance → toggle between Light, Dark, Auto.

| # | Check | Pass criteria | Result |
|---|-------|---------------|:------:|
| 11.1 | Popover background | Adapts (panelBackground token) |  |
| 11.2 | Status dot SF Symbol contrast | White glyph still readable in both modes |  |
| 11.3 | FooterLink hover/focus brightening | Visible in both modes |  |
| 11.4 | Metric toggle pill shadow | Visible in both modes (ThemeColors.shadowColor on selected tab) |  |

## 12. Keyboard

With popover open:

| # | Check | Pass criteria | Result |
|---|-------|---------------|:------:|
| 12.1 | `1` | Switches to 5h mode |  |
| 12.2 | `2` | Switches to 7d mode |  |
| 12.3 | `3` | Switches to Context Health mode |  |
| 12.4 | `r` | Refreshes |  |
| 12.5 | `←` / `→` | In Context Health mode, navigates sessions |  |
| 12.6 | `esc` | Closes popover |  |
| 12.7 | `Tab` through controls | Focus ring visible on each step on CollapsibleSectionHeader sites |  |

## 13. Accessibility — VoiceOver smoke test

Enable VoiceOver (Cmd+F5). Open the popover. Navigate with VO+→ from top to bottom.

| # | Check | Pass criteria | Result |
|---|-------|---------------|:------:|
| 13.1 | Title | "AI Battery" |  |
| 13.2 | Account picker | "Switch account, Select which Claude account to display" |  |
| 13.3 | Update icon | "Check for updates" OR "Version X.Y.Z available" |  |
| 13.4 | Gear icon | "Settings, Open settings" (or "Close settings" when open) |  |
| 13.5 | Each FooterLink | Reads label + hint, NEVER falls back to generic "button" |  |
| 13.6 | Status dot | Reads the tooltip text (e.g. "All systems operational") |  |
| 13.7 | Cost row | One combined utterance per model |  |
| 13.8 | No double-announcements | Decorative glyphs (throttle triangle, active arrow already labelled separately) don't get spoken twice |  |

## 14. Stress / edge cases

| # | Check | Pass criteria | Result |
|---|-------|---------------|:------:|
| 14.1 | Open and close popover 20× rapidly | No crash, no detached panel, no leaked window |  |
| 14.2 | Toggle settings 10× rapidly | Smooth cross-fade each time, panel height settles correctly |  |
| 14.3 | Resize Dynamic Type (System Settings → Display → Text Size) | Header still .center-aligns; popover stays within 1.3× width cap |  |
| 14.4 | Colorblind mode on (Settings) | Bar colors switch to colorblind-safe palette; status-dot SF Symbols still visible |  |
| 14.5 | Two accounts, one auth-expired | Active-account snapshot still renders for the valid one |  |
| 14.6 | No data state | "No Claude Code data found" empty view renders |  |

## 15. Build / install

| # | Check | Pass criteria | Result |
|---|-------|---------------|:------:|
| 15.1 | `swift build -c release` clean | Exit 0, zero warnings |  |
| 15.2 | `swift test` clean | All 980+ tests pass (954 from v2.3.0 + new pins) |  |
| 15.3 | `swiftlint --quiet` | No new warnings from v2.3.1 files (12 force_unwrapping pre-existing in Services/ + Tests/, all from earlier releases) |  |
| 15.4 | `./scripts/build-app.sh` | Produces .build/AIBattery.app + .dmg + .zip cleanly |  |
| 15.5 | Bundle launches | `open .build/AIBattery.app` → menu bar icon appears in <2s |  |

---

## Sign-off

- [ ] Every row marked pass OR has an explicit waiver note
- [ ] CHANGELOG entry matches what was actually verified
- [ ] Tester: ____________________
- [ ] Date: ____________________
