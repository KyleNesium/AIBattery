# Multi-Account Overview — Design Spec

**Date:** 2026-10-12
**Status:** Approved in chat (shape: overview grid in the popover; entry: default when 2+ accounts). Refined here.
**Ships as:** v3.1.0, together with the Settings-height fix (#196, held release PR #198) and whichever provider-relevance items (PR #197 plan) land in time.

## Goal

When AI Battery holds two or more accounts, the popover should open on **all of them at once**: one compact card per account with its quota bars, reset countdowns and state, so the user sees headroom across Claude and Codex without switching. Tapping a card drills into today's single-account view for that account; a back control returns to the overview. One account keeps today's popover unchanged.

## Decisions (settled during brainstorming)

| Question | Decision |
|---|---|
| Shape | Overview grid **inside the popover** (one 275 pt column of cards), not columns, not a second window. |
| Entry | **Default** when there are ≥ 2 eligible accounts, on every panel open. One account → today's detail view, unchanged. The mode is not remembered across opens. |
| Architecture | A `PopoverMode` on `UsagePopoverView` (`.overview` / `.detail`), the same pattern as the existing add-account overlay. No `NavigationStack` (directional transitions fight the panel re-anchoring; `.move(edge:)` is banned). No second view model, no second window. |
| Drill-down semantics | Tapping a card **switches the active account** (`UsageViewModel.switchAccount(to:)`, same path as the chip menu) and enters `.detail`. There is exactly one notion of "active": menu bar, notifications, status feed and the detail view all follow it. |
| Back | A chevron left of the account chip in `.detail` (only when ≥ 2 eligible accounts). Returns to `.overview` **without** switching again. Escape in `.detail` goes back first; Escape in `.overview` closes the panel. |
| Fan-out gating | The per-account fan-out runs when the "All accounts in menu bar" toggle is on **or** there are ≥ 2 eligible accounts. The toggle keeps controlling only the menu-bar text. |
| What a card shows | Quota only (windows / credits / per-minute limits), freshness, throttle state, provider status dot. **Never** Insights, Projects or Context: local logs are per provider, so per-account values would be fabricated. |
| API-key accounts | First-class cards (Requests / Tokens per-minute bars). Requires the fan-out to carry `StandardRateLimits` — item 6 of the provider-relevance plan moves here as a prerequisite task; item 9 (other-accounts strip) is **superseded** and dropped from that plan. |
| Provider status | Both providers' feeds are polled while both providers have an eligible account; each card's header shows its provider's dot. |
| Identity | Same `AccountStore.identityLabel` as the chip menu (alias → discovered identity → "Provider N"), masked unless Settings → "Full account email in popover". Plan label as in the chip menu rows. Never copy an identity into `displayName`. |
| Cost framing | Unchanged. The overview shows no cost. |
| Privacy | Unchanged. No new data sources, no new persistence except the per-account fetch metadata already held in memory. |

## Verified ground truth (code, 2026-10-12)

- `UsagePopoverView.body` (`AIBattery/Views/UsagePopoverView.swift:98-126`) already branches on `addingProvider` to show `AuthView` instead of `mainContent`; `mainContent` (L128+) is header → settings | metric toggle → bars → gates → footer. `deferredRender` arms the heavy sections one run-loop after `.panelDidShow` and disarms on `.panelDidDismiss` (L336-360); `resetTransientPopoverState()` runs on dismiss.
- `UsageViewModel.switchAccount(to:)` (`AIBattery/ViewModels/UsageViewModel.swift:771-794`) sets the store's active id, clears the active-account state, and refreshes (which also runs the fan-out at its tail, L539).
- Fan-out: `MultiAccountFanOut.resolve(enabled:seed:provider:fetcher:now:)` returns `[String: RateLimitUsage]?`; `UsageViewModel.fetchAllAccounts` (`+FanOut.swift:34-48`) reads `enabled` from `UserDefaultsKeys.showAllAccountsInMenuBar`; `scheduleFanOut()` coalesces triggers; `perAccountRateLimits: [String: RateLimitUsage]` (`UsageViewModel.swift:25`) is the only per-account state. There is no per-account `fetchedAt` / cached flag and no `StandardRateLimits` map.
- Eligibility: `AccountStore.multiAccountDisplayIDs(accounts:isAuthenticated:)` (`MultiAccountFanOut.swift:63-74`) = `displayOrdered` → not pending → **not API key** → authenticated. `OAuthManager.isAuthenticated(accountId:)` = refresh token present.
- Status feeds: `StatusChecker.shared(for:)` (`StatusChecker.swift:43-48`) picks `.shared` (Claude) or `.codex`; only the **active** provider's feed is fetched, inside `fetchActiveAccount` (`+ProviderRouting.swift:54`). `systemStatus` is cleared on switch (L761/780).
- Components: `GaugeRow` (`Views/Components/GaugeRow.swift`: `percent`, `barColor`, a11y label/value, `headerLeading`/`headerTrailing`/`footer(Date)`), `GaugeBar(percent:barColor:)`, `ProviderBadge(provider:)` (`AccountChipView.swift:215-238`), `PopoverFooterView.relativeTime(_:)` / `staleTooltip(source:lastFresh:)`, `DurationFormatter.compact(_:)`, `ThemeColors.barColor(percent:)`, `UsageBar.AlarmState(percent:isThrottled:confirmed:)`.
- Keyboard: `PopoverPanel.keyDown` (`StatusBarManager+Panel.swift`) closes on Escape itself and forwards `1/2/3/r/left/right` via `.panelKeyPress`; `UsagePopoverView.handleKeyPress` (L367-389) maps them to metric modes / refresh.
- Panel height follows content through `StatusBarManager.scheduleRefit()` (PR #196), so the overview's height needs no special handling.
- Layout: popover width `Layout.popoverWidth` = 275 pt; `Layout.accountChipHeight` = 28; `Spacing.sectionHorizontal` = 16, `Spacing.section` = 8, `Spacing.gap` = 6, `Spacing.inner`, `Spacing.tight` = 2.

## 1. Modes

```swift
enum PopoverMode: Equatable { case overview, detail }
```

- `UsagePopoverView` gains `@State private var mode: PopoverMode = .detail` and a pure rule:
  `PopoverMode.initial(eligibleAccountCount: Int) -> PopoverMode` = `count >= 2 ? .overview : .detail`.
- The rule is applied on every `.panelDidShow` (the existing handler) and whenever the eligible count changes while the panel is open (an `onReceive(accountStore.$accounts)` already exists for the add flow; extend it): if the count drops to 1 while in `.overview`, switch to `.detail`; if it rises to ≥ 2 while in `.detail` **do nothing** (the user is looking at an account; the next open lands on the overview).
- `resetTransientPopoverState()` (dismiss) resets `mode` to `.detail` so the next `.panelDidShow` recomputes from scratch, and clears `showSettings` as today.
- Body: `if let addingProvider { AuthView } else if mode == .overview { overviewContent } else { mainContent }`. The add-account overlay keeps precedence (it is reachable from the overview's footer "Add account…" link and from the chip menu).
- Heavy sections (`deferredRender`) are only inside `mainContent`, so the overview never renders Projects/Insights/Charts. Entering `.detail` from a card re-arms them one run-loop later (post `.panelDidShow`-equivalent: call `deferredRender.appeared()` via `DispatchQueue.main.async` after the switch, mirroring the show handler).

## 2. Data

### 2.1 Fan-out gate

```swift
enum FanOutGate {
    /// The fan-out runs for the menu bar OR for the overview.
    static func enabled(menuBarToggle: Bool, eligibleAccountCount: Int) -> Bool {
        menuBarToggle || eligibleAccountCount >= 2
    }
}
```

`UsageViewModel.fetchAllAccounts` uses it (`eligibleAccountCount = OAuthManager.shared.multiAccountDisplayIDs().count`). `scheduleFanOut()` is also triggered when `accountStore.accounts` changes (add / remove / sign-out), not only by the toggle. The fan-out still seeds the active account's just-fetched reading (no N+1).

### 2.2 Per-account reading

The single map becomes a struct so a card can show freshness and the API-key shape:

```swift
struct AccountReading: Equatable, Sendable {
    /// Windows (Claude, Codex ChatGPT) or credit budget (Codex Business) — nil for API keys.
    var windows: RateLimitUsage?
    /// Per-minute request/token limits — Codex API-key accounts only.
    var apiLimits: StandardRateLimits?
    /// When this reading was produced and whether it came from a cache rather than a fresh fetch.
    var fetchedAt: Date
    var isCached: Bool
    var source: RateLimitSource?
}
```

- `MultiAccountFanOut.resolve` returns `[String: AccountReading]?` (built from `APIFetchResult.rateLimits / standardLimits / fetchedAt / isCached / rateLimitSource`). The normalisation (`withClearedExpiredWindows`, `withClearedRolloverArtifacts`) applies to `windows`; `StandardRateLimits.withClearedExpiredWindows` to `apiLimits`.
- `UsageViewModel.perAccountReadings: [String: AccountReading]` replaces `perAccountRateLimits`. A computed `perAccountRateLimits: [String: RateLimitUsage]` (`compactMapValues(\.windows)`) keeps the menu-bar path and its tests unchanged. The menu bar additionally gets `apiLimits` for API-key slots (= item 6 of the provider-relevance plan; see §7).
- `multiAccountDisplayIDs` stops excluding API-key accounts.

### 2.3 Provider status for both providers

- `UsageViewModel.providerStatuses: [AIProvider: ClaudeSystemStatus]`. `fetchActiveAccount` keeps writing the active provider's result to `systemStatus` **and** to `providerStatuses[provider]`; when the eligible accounts span both providers, the fan-out also calls `StatusChecker.shared(for: other).fetchStatus()` once per cycle (each checker already has its own backoff) and stores it. Notifications stay bound to the active provider's feed (unchanged).

### 2.4 Signed-out accounts

An account in the store without a refresh token (`isAuthenticated(accountId:) == false`) is **not** eligible for the fan-out, but the overview lists it as a **sign-in card** (identity + "Signed out · click to sign in" → `addingProvider = account.provider`), because a signed-out account is exactly what a multi-account user needs to notice. Pending-identity accounts are hidden (as in the menu bar).

## 3. Overview layout

ASCII mockup at 275 pt (dark mode), three accounts (Claude Team subscription, Codex ChatGPT Business, Codex API key):

```
┌───────────────────────────────────────────┐
│ Accounts  3                            ⚙  │   header: title + count, gear
│───────────────────────────────────────────│
│ ✦ Claude Team · Max            ● 34%      │   card 1: mark · identity · plan · status dot · worst %
│  5-Hour   ▓▓▓▓▓▓▓░░░░░░░░░░░░  34%  3h 12m │   bar rows: label · gauge · % · reset
│  7-Day    ▓▓▓▓▓░░░░░░░░░░░░░░  26%  4d 2h  │
│  ~2h 40m to limit                          │   footer only when noteworthy (burn-rate / throttled / cached)
│───────────────────────────────────────────│
│ ⬡ k•••@ringier.co.za · Business ● 61% ▶   │   card 2 (active account marked ▶)
│  Credits  ▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░  61%  12d   │   credits kind: one bar
│───────────────────────────────────────────│
│ ⬡ Codex API Rates · API        ●  80%     │   card 3: API-key kind
│  Requests ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░  80%  42s   │
│  Tokens   ▓▓░░░░░░░░░░░░░░░░░  10%  42s   │
│  Cached 3m                                 │   footer: cached marker
│───────────────────────────────────────────│
│ ⊕ Add account…                             │   footer link (opens the add overlay, provider picker inside)
│ ▮ Usage ↗  ⊗ Status ↗          ⏻ Quit     │   existing footer (status/usage links follow the ACTIVE account)
└───────────────────────────────────────────┘
```

- **Header** (`OverviewHeaderView`): title "Accounts" (`Typography.accountTitle`, primary) + count (`Typography.monoCaption`, secondary) on the left, the existing gear on the right (same `showSettings` binding; Settings opens in place of the cards, exactly as it does over the detail view). No chip in overview mode — the cards *are* the accounts.
- **Cards** (`AccountCardView`, one per `AccountCard` model row), separated by `StyledDivider`, each a single `Button(.plain)` (whole card is the hit target; `.contentShape(Rectangle())`), hover brightens the identity from `.secondaryLabel` to `.primary` like the chip.
  - Header line: `ProviderBadge` (12 pt mark in the provider colour) · identity (`Typography.caption`, `lineLimit(1)`, `.truncationMode(.middle)`) · ` · plan` (secondary, Codex only, as `AccountStore.planLabel`) · `Spacer` · provider status dot (existing status indicator styling, hidden when no status yet) · **worst percent** (`Typography.monoValue`, colour `ThemeColors.barColor(percent:)`) · `▶` (`ThemeColors.success`) when active.
  - Bar rows (`AccountCardBarRow`): label column (`Layout.cardBarLabelWidth` = 52 pt, `Typography.tinyLabel`, secondary, trailing) · `GaugeBar` · percent (`Typography.monoTiny`, 34 pt trailing) · reset countdown (`Typography.monoTiny`, tertiary, 46 pt trailing; "—" when unknown). Rows by `CodexDisplayKind` / provider:
    - `.windows`: "5-Hour" + "7-Day" (Claude) / "Weekly" (Codex), percents `fiveHourPercent` / `sevenDayPercent`, resets `fiveHourReset` / `sevenDayReset`.
    - `.credits`: one row "Credits" (`creditBudget.usedPercent`, reset `resetsAt`); uncapped → percent "—", bar empty, label "No cap".
    - `.apiLimits`: "Requests" (`requestsPercent`, `requestsReset`) + "Tokens" (`tokensPercent`, `tokensReset`).
  - Footer line (`Typography.tinyLabel`), only when one applies, first match wins: "Throttled" (danger) · "Limit reached" (danger) · "Signed out · click to sign in" (caution; sign-in card has no bar rows) · "~X to limit" (caution; `estimatedTimeToLimit` of the binding window, same `confirmed` gate as the bars) · "Cached <relative>" (caution; `isCached`). Otherwise no footer line, so a healthy card is exactly three lines.
  - Per-card alarm derivation reuses `UsageBar.AlarmState(percent:isThrottled:confirmed:)` with `confirmed = !reading.isCached` so an unconfirmed cached 100 % never shows "Limit reached" on a card either (same rule as the bars).
- **Add link**: `LinkActionButton("Add account…", icon: "plus.circle")` shown while `accountStore.canAddAccount(provider:)` is true for either provider; tapping it opens the add overlay for the provider that still has room (if both, Claude first — the overlay has the provider picker).
- **Footer**: the existing `PopoverFooterView`, unchanged; its Usage / Status links and timestamp follow the active account (documented in the tooltip: "for <identity>").
- **Heights** (target, dark & light): header 44, card 3 lines ≈ 66 (header 18 + 2 bars × 18 + gaps) / 4 lines ≈ 82, credits card ≈ 48, add link 24, footer 36. Three windowed accounts ≈ 44 + 3×66 + 2 dividers + 24 + 36 ≈ 300 pt. Six accounts (the cap) ≈ 500 pt — still under the screen-relative max. No scrolling.

## 4. Detail mode changes

- `PopoverHeaderView` gains `showsBack: Bool` and `onBack: () -> Void`. When `showsBack`, a `chevron.left` button (`Typography.headerGear`, same tone/hover as the gear, hit target `accountChipHeight` square, help "All accounts", accessibility label "Back to all accounts") sits **left of the chip**; the chip keeps its menu (switching from the menu stays in `.detail`).
- `showsBack = eligibleAccountCount >= 2` (also true after signing out of one of three accounts, since two remain).
- Escape: `PopoverPanel.keyDown` currently closes on Escape itself. Change: post `.panelKeyPress` with `"escape"` first; `UsagePopoverView.handleKeyPress` returns to `.overview` when in `.detail` with `showsBack`, **else** the panel closes (the panel needs to know whether the view consumed it — use a `NotificationCenter` reply is clumsy; instead `StatusBarManager` exposes `var escapeHandler: (() -> Bool)?` set by the hosting view's root, `PopoverPanel.keyDown` calls it and only closes when it returns `false`). Settings open in `.detail`: Escape first closes Settings (today it closes the panel — keep that unchanged to limit scope; only `.detail`-without-Settings goes back).
- Keys `1/2/3/r` unchanged in `.detail`; in `.overview` `1…6` select the n-th card (switch + detail), `r` refreshes all (fan-out), others ignored.

## 5. Interaction flow

1. Panel opens → `.panelDidShow` → `mode = PopoverMode.initial(eligibleAccountCount:)`.
2. `.overview` renders from `AccountCard.rows(...)` (pure) over `accountStore.accounts`, `viewModel.perAccountReadings`, `viewModel.providerStatuses`, `OAuthManager.isAuthenticated(accountId:)`, the mask toggle, `now`.
3. Tap card N → `viewModel.switchAccount(to: id)` (no-op fast path when already active: skip the clear/refresh and just enter detail) → `mode = .detail` → re-arm deferred sections.
4. Back → `mode = .overview`. The active account stays as is; its card shows `▶`.
5. Dismiss → `resetTransientPopoverState()` → `mode = .detail`, `showSettings = false`.

Animation: mode changes use `withAnimation(MotionConstants.standard)` with `.transition(.opacity)` on both subtrees (the panel re-anchors on height change; opacity only).

## 6. Accessibility

- Each card: `accessibilityElement(children: .combine)`, label = "<Provider> account <identity>, <plan>, 5-hour <n> percent, 7-day <n> percent, resets in <x>" (or Credits / Requests-Tokens variants), value = state line when present, hint "Opens this account". Active card adds ", active".
- Status dot has its own label "<Provider> status: operational / degraded / outage".
- Back button label "Back to all accounts"; overview header is `.isHeader`.
- Colour is never the only signal: percent text, the `▶` glyph, and the words "Throttled" / "Limit reached" / "Cached" carry the state (colour-blind palette applies through `ThemeColors.barColor`).

## 7. Prerequisite folded in from the provider-relevance plan

Item 6 (API-key accounts in the fan-out and menu bar) is implemented here as Task 1 of the plan: `AccountReading.apiLimits`, `multiAccountDisplayIDs` no longer excluding API keys, `MenuBarMultiAccountText.build(order:providers:limits:apiLimits:metricMode:)` with per-minute slots (`peakPercent`, exhausted = requests or tokens exhausted). The provider-relevance plan's Task 7 is marked "done in multi-account overview" and its Task 10 (strip) is deleted.

## 8. Settings

- Settings → Display: "All accounts in menu bar" keeps its name; its hint becomes "The popover shows all accounts whenever you have more than one." so the user understands the overview is not toggle-gated.
- Refresh → poll-cost hint: when the fan-out is active, append " · ×N accounts" (`RefreshSettingsSection.pollCostHint(provider:apiKeyAccount:fanOutAccounts:)`).

## 9. Error handling

- Fan-out failures per account keep the previous `AccountReading` with `isCached = true` (the resolve step merges onto the previous map rather than dropping the id), so cards never blank out between polls. A never-fetched account shows "—" percents and empty bars (track only) with "Fetching…" as its footer line for the first cycle.
- `AccountCard.rows` tolerates: missing readings, readings for ids no longer in the store (ignored), uncapped credit budgets, API-key readings without windows, both providers' statuses missing.
- Switching to an account whose refresh fails falls back exactly as today's detail view does (cached data + "Cached" footer).

## 10. Testing

Pure, headless-safe (no `UsageViewModel()`, `@MainActor` where AppKit colours are touched):

- `PopoverModeTests`: `initial(eligibleAccountCount:)` for 0/1/2/6; transitions on account-count change (2→1 forces detail; 1→2 keeps detail).
- `FanOutGateTests`: toggle × count matrix.
- `AccountReadingTests` / `MultiAccountFanOutTests`: windows vs apiLimits routing, fetchedAt/isCached carried, failed fetch keeps the previous reading as cached, normalisation applied.
- `AccountCardTests`: row order (Claude block first), active flag, worst percent per kind (windows max / credits / API peak), uncapped credits, signed-out card, pending hidden, bar-row labels per provider (7-Day vs Weekly), reset text, footer precedence (throttled > limit > signed-out > burn-rate > cached > none), accessibility label text.
- `MenuBarMultiAccountTextTests`: per-minute slot.
- `PopoverHeaderBackTests`: `showsBack` rule.
- Local build walkthrough per Task (open → overview → card → detail → back → Settings → Escape paths) via accessibility clicks only — **no synthetic keystrokes** (see memory `no-synthetic-keystrokes`); Escape behaviour is verified by a unit test on the handler plus one manual check by Kyle.
- README "Test Coverage" and `CLAUDE.md` counts in the wrap-up task; `spec/UI_SPEC.md` gets a new "❶ Overview mode" section + mockup, `spec/DATA_LAYER.md` the `AccountReading` / `FanOutGate` / `providerStatuses` entries, `spec/CONSTANTS.md` the card layout constants, `spec/ARCHITECTURE.md` the mode in the data-flow paragraph.

## 11. Open research items (resolved during implementation, before coding against them)

| # | Item | Resolution method | Fallback |
|---|---|---|---|
| R1 | Does `StatusChecker.fetchStatus()` tolerate being called for both feeds in the same cycle without defeating its backoff? | Read `StatusChecker.swift` backoff state (per instance) | Fetch the non-active feed only every other cycle |
| R2 | Can `PopoverPanel.keyDown` ask the SwiftUI root whether Escape was consumed synchronously? | Implement `StatusBarManager.escapeHandler` closure set from `PopoverContentView.onAppear` | Keep Escape = close everywhere; back only via the chevron |
| R3 | Six cards of the tallest kind on a 13" display: does the panel hit the screen max? | Compute with the real `Layout` values during Task 4 | Compress card bar rows to 16 pt on ≥ 5 accounts |

## Out of scope

- Aggregate numbers across accounts or providers (no "total" line).
- Per-account Insights / Projects / Context (local logs are per provider).
- Reordering or hiding cards; the order is the chip menu order.
- A separate window or a resizable popover.
- Remembering the last mode across opens.

## Spec/code sync obligations

`spec/ARCHITECTURE.md`, `spec/DATA_LAYER.md`, `spec/UI_SPEC.md`, `spec/CONSTANTS.md`, `README.md`, `CLAUDE.md`, the provider-relevance spec (§6 moved, §9 superseded) and its plan are updated in the same PR. No merge with stale docs.
