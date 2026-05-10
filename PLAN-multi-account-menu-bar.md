# PLAN — Show All Accounts in Menu Bar

**Feature:** Display setting that, when enabled, renders the menu bar text as multiple usage percentages joined by ` | ` (e.g., `42% | 23%`) for users with 2–3 OAuth accounts. Off by default; preserves current single-active-account behaviour.

**Status:** Iteration 2 — line numbers verified against current `main`, toggle-propagation gap closed, MetricMode fallback specified, double-fetch behaviour documented. Each phase is self-contained for fresh-context execution.

---

## Phase 0 — Documentation Discovery (verified)

These are the exact, verbatim APIs the plan depends on. Confirmed by reading the files at the cited locations.

### Account & OAuth surface

- `AccountStore.accounts: [AccountRecord]` — published, order-preserved by user (drag-reorder in settings is the source of order). All accounts (including pending) are in this array. — `AIBattery/Services/AccountStore.swift`
- `AccountStore.activeAccountId: String?` — currently active account.
- `AccountStore.maxAccounts == 3`.
- `AccountRecord` — `id: String` (`"pending-<UUID>"` until first API success), `displayName: String?`, `billingType: String?`, `addedAt: Date`. — `AIBattery/Models/AccountRecord.swift:9–18`
- `OAuthManager.shared.getAccessToken(for accountId: String) async -> String?` — async, optional, non-throwing. Refreshes if expired; returns `nil` if no refresh token. — `AIBattery/Services/OAuthManager.swift:70–95`
- `OAuthManager.shared.tokens[accountId]?.refreshToken != nil` — predicate for "this account is authenticated." (Private storage; needs a small public accessor — see Phase 2.)

### Rate limit surface

- `RateLimitFetcher.shared.fetch(accessToken: String, accountId: String) async -> APIFetchResult` — already per-account aware; cache is keyed by accountId.
- `APIFetchResult` fields — `rateLimits: RateLimitUsage?`, `rateLimitSource: RateLimitSource?`, `standardLimits: StandardRateLimits?`, `profile: APIProfile?`, `hasStandardRateLimitHeaders: Bool`, `fetchedAt: Date`, `isCached: Bool`, `authError: Bool`. — `AIBattery/Models/APIFetchResult.swift:3–30`
- `RateLimitUsage` fields — `representativeClaim: String` (`"five_hour"` | `"seven_day"`), `fiveHourUtilization: Double`, `sevenDayUtilization: Double`, `overallStatus: String` (`"allowed"` | `"throttled"`), plus per-window status/reset. — `AIBattery/Models/RateLimitUsage.swift:3–55`
- `RateLimitUsage.fiveHourPercent`, `.sevenDayPercent`, `.requestsPercentUsed` — convenience accessors returning 0–100 doubles.

### Menu bar surface

- `MenuBarIcon.combinedStatusBarImage(text: String, percent: Double, color: NSColor, isBroken: Bool = false, isSparkle: Bool = false, menuBarAppearance: NSAppearance? = nil) -> NSImage` — `text` is freeform; can render `"42% | 23%"` as-is. — `AIBattery/Views/MenuBarIcon.swift:117`
- `MenuBarIcon.cachedIcon(for percent: Double, color: NSColor, isBroken: Bool, isSparkle: Bool, pulseStep: Int, menuBarAppearance: NSAppearance? = nil) -> NSImage` — used internally by `combinedStatusBarImage`. — `AIBattery/Views/MenuBarIcon.swift:168`
- `ThemeColors.barNSColor(percent: Double, isDarkMenuBar: Bool? = nil) -> NSColor` — color for the star + (today) the text. — `AIBattery/Utilities/ThemeColors.swift:279`
- `StatusBarManager.updateButton(_ button: NSStatusBarButton, viewModel: UsageViewModel)` — private; defined at `AIBattery/Views/StatusBarManager.swift:307`. **Called from 4 sites** — must be aware when changing its inputs:
  - Combine sink at line 205 (snapshot/staleness changes)
  - Appearance change handler at line 261 (light/dark menu bar swap)
  - Countdown timer ticks at lines 476, 482 (per-second updates near reset)
- Combine sink shape (verbatim, lines 199–205):
  ```swift
  viewModel.$snapshot
      .combineLatest(viewModel.$lastFreshFetch)
      .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
      .sink { [weak self] _ in
          self?.updateButton(button, viewModel: viewModel)
      }
  ```
  Note: `DispatchQueue.main` (not `RunLoop.main`).

### Settings surface

- `UserDefaultsKeys` — convention is `"aibattery_<camelCase>"`. — `AIBattery/Utilities/UserDefaultsKeys.swift` (31 lines total)
- `DisplaySettingsSection` — uses `@AppStorage(UserDefaultsKeys.<key>)`. Existing colorblind toggle is the pattern to copy. — `AIBattery/Views/Settings/DisplaySettingsSection.swift` (73 lines total)
- **Toggle propagation:** `@AppStorage` writes to UserDefaults but does not emit a Combine signal that StatusBarManager can observe. To make the menu bar reflect the toggle within ≤200ms (instead of waiting up to 30s for the next refresh tick), StatusBarManager must subscribe to `UserDefaults.standard.publisher(for: \.aibattery_showAllAccountsInMenuBar)` (KVO-style) — see Phase 3.

### Spec files (line ranges to edit)

- `spec/ARCHITECTURE.md` — Project Tree at 105–107 (MenuBarIcon, StatusBarManager); UsageViewModel at 103.
- `spec/UI_SPEC.md` — Menu Bar section at 409–447.
- `spec/CONSTANTS.md` — Display Settings table at 175–182.
- `spec/DATA_LAYER.md` — UsageViewModel at 587+; AccountStore at 377–388.
- `README.md` — Settings section at 198–223; Test Coverage at 442–455 (currently 893 tests across 59 files).

### Anti-patterns to avoid

- ❌ Don't invent `OAuthManager.accessToken(for:)` — the real method is `getAccessToken(for:)` and is `async`.
- ❌ Don't add a separate dictionary of `UsageSnapshot` per account — only the rate-limit slice is needed for the menu bar; reusing `UsageSnapshot` per account would balloon memory and duplicate JSONL scans.
- ❌ Don't synchronize all account fetches behind a single `await` — they should run concurrently via a `TaskGroup`.
- ❌ Don't change the popover, the breathing animation, or the existing single-account rendering path. The toggle gates the multi-account text only.
- ❌ Don't ratchet the refresh interval to compensate for fan-out — quota multiplication is documented but not throttled.

---

## Resolved design decisions

| # | Decision | Rationale |
|---|----------|-----------|
| Order | `AccountStore.accounts` order (user-controlled) | Predictable; mirrors what the popover account picker shows. |
| Star icon | Single star whose color/breath/broken-state reflects the **worst** account (max percent; throttled if any are) | One status item, one icon. Worst-case is the actionable signal — if any account is at 95% the user wants the red glow. |
| Width | Trust macOS to clip; use the bundled `\u{00A0}|\u{00A0}` (non-breaking spaces) separator and an explicit "max 3 accounts" cap from `AccountStore.maxAccounts`. Worst case `"100% \| 100% \| 100%"` ≈ 17 chars + star is acceptable on a 1440pt+ menu bar. | Truncation logic adds complexity for a rare 3-account-100% edge case. |
| Fan-out | When toggle ON, fetch all authenticated accounts in parallel via `TaskGroup`; each uses its own access token. | Plumbing already exists per-account; cost is 3× per cycle when 3 accounts. Documented, not throttled. |
| Per-account error states | Slot shows last-known percent if available, `"—"` if never fetched / auth-error. Throttled accounts still show their numeric percent (typically 100%) — the broken star (global) communicates throttle. | Avoids special per-slot characters that break monospaced alignment. |
| Countdown mode | Triggered by **worst** account's reset when <5min away; renders single countdown text (`"4m 32s"`), not per-account countdown. | Keeps width manageable; matches "worst account drives icon" policy. |
| Popover | **Unchanged.** Still scoped to active account; popover account switcher still drives `UsageViewModel.switchAccount(to:)`. | Out of scope. |

### Non-goals (explicit)

- No per-account thresholds or alert rules.
- No per-account icon (one star, one bar).
- No reordering UI added in this feature (uses existing AccountStore order).
- No popover changes.
- No new metric mode (fiveHour vs sevenDay still global, drives all slots equally).

---

## Phase 1 — Specs first

**Goal:** Per project CLAUDE.md, spec is updated before code. Self-contained edit list.

### Files to edit

1. **`spec/ARCHITECTURE.md`** — Add a paragraph under the StatusBarManager/MenuBarIcon entries (Project Tree ~105–107) noting that menu bar text rendering supports a multi-account mode driven by `UsageViewModel.perAccountRateLimits` (introduced in Phase 2).

2. **`spec/UI_SPEC.md`** (Menu Bar section, 409–447) — Add a subsection "Multi-account display" describing:
   - Trigger: `UserDefaultsKeys.showAllAccountsInMenuBar == true` AND `AccountStore.accounts.count >= 2`.
   - Format: `"<a>% | <b>%[ | <c>%]"` using non-breaking spaces around `|`.
   - Order: AccountStore order.
   - Star color & broken state: derived from worst account.
   - Countdown: worst-account-driven, single timer.
   - Empty/auth-error slot: `"—"`.

3. **`spec/CONSTANTS.md`** (Display Settings table, 175–182) — Add row:
   ```
   | Show all accounts in menu bar | `aibattery_showAllAccountsInMenuBar` (Bool, default false) |
   ```

4. **`spec/DATA_LAYER.md`** (UsageViewModel section, 587+) — Document new published property `perAccountRateLimits: [String: RateLimitUsage]` and the per-account fan-out fetch path. Note: only populated when toggle is ON.

5. **`README.md`** (Settings section, 198–223) — Add a one-line bullet: "**Show all accounts in menu bar** — when enabled, the menu bar shows usage for every connected account (e.g., `42% | 23%`)."

### Verification

- Grep specs for `aibattery_showAllAccountsInMenuBar` — should appear in CONSTANTS.md.
- Grep specs for `perAccountRateLimits` — should appear in DATA_LAYER.md and ARCHITECTURE.md.
- Read each spec edit and confirm the surrounding section still flows.

### Anti-pattern guards

- ❌ Don't claim the popover changes — it doesn't.
- ❌ Don't promise per-account countdown text in UI_SPEC.

---

## Phase 2 — Per-account fetch fan-out in `UsageViewModel`

**Goal:** Hold per-account rate limit data concurrently when the toggle is ON. Keep single-account path unchanged when OFF.

### Files to edit

1. **`AIBattery/Utilities/UserDefaultsKeys.swift`** — Add:
   ```swift
   static let showAllAccountsInMenuBar = "aibattery_showAllAccountsInMenuBar"
   ```
   Place under the display-mode group near `colorblindMode`.

2. **`AIBattery/Services/OAuthManager.swift`** — Add a public accessor for "is this account authenticated":
   ```swift
   public func isAuthenticated(accountId: String) -> Bool {
       tokens[accountId]?.refreshToken != nil
   }
   ```
   Place adjacent to existing `updateAuthState()`. This is needed because `tokens` is private; we need a per-account predicate without exposing the dictionary.

3. **`AIBattery/ViewModels/UsageViewModel.swift`** — Add:
   - `@Published private(set) var perAccountRateLimits: [String: RateLimitUsage] = [:]` — keyed by `AccountRecord.id`. Empty when toggle is OFF.
   - `@Published private(set) var perAccountFetchedAt: [String: Date] = [:]` — for staleness detection.
   - `@Published private(set) var perAccountThrottled: Set<String> = []` — accounts whose `overallStatus == "throttled"`.
   - A new method:
     ```swift
     /// Fan-out: fetch rate limits for every authenticated, identity-resolved account.
     /// Runs only when the "show all accounts" toggle is ON. Idempotent: clears state if OFF.
     /// **Active-account cost:** the active account is also in the fan-out — but
     /// `RateLimitFetcher.shared` serves it from its per-account cache (the active path
     /// just populated it), so the duplicate is a free cache hit (`isCached == true`).
     /// Net cost: N requests for N authenticated accounts.
     func fetchAllAccounts() async {
         let showAll = UserDefaults.standard.bool(forKey: UserDefaultsKeys.showAllAccountsInMenuBar)
         guard showAll else {
             if !perAccountRateLimits.isEmpty {
                 perAccountRateLimits = [:]
                 perAccountFetchedAt = [:]
                 perAccountThrottled = []
             }
             return
         }
         let records = OAuthManager.shared.accountStore.accounts
             .filter { !$0.isPendingIdentity }
             .filter { OAuthManager.shared.isAuthenticated(accountId: $0.id) }
         var newLimits: [String: RateLimitUsage] = [:]
         var newFetched: [String: Date] = [:]
         var newThrottled: Set<String> = []
         await withTaskGroup(of: (String, APIFetchResult?).self) { group in
             for record in records {
                 group.addTask {
                     guard let token = await OAuthManager.shared.getAccessToken(for: record.id) else {
                         return (record.id, nil)
                     }
                     let result = await RateLimitFetcher.shared.fetch(accessToken: token, accountId: record.id)
                     return (record.id, result)
                 }
             }
             for await (id, result) in group {
                 if let limits = result?.rateLimits {
                     newLimits[id] = limits
                     newFetched[id] = result?.fetchedAt
                     if limits.overallStatus == "throttled" { newThrottled.insert(id) }
                 }
             }
         }
         // Single atomic publish — avoids 3 separate redraws when 3 accounts arrive.
         self.perAccountRateLimits = newLimits
         self.perAccountFetchedAt = newFetched
         self.perAccountThrottled = newThrottled
     }
     ```
   - **Wire `fetchAllAccounts()` into 3 entry points:**
     1. End of `refresh(skipNetworkCheck:)` — after the active-account fetch succeeds. Skip if active fetch returned a network error (no point fanning out when offline). Reads naturally as the last step.
     2. `switchAccount(to:)` — after the existing `refresh()` call so the maps reflect the new active account's perspective (though the data is per-account-keyed, not active-relative, this just keeps timing consistent).
     3. **Toggle flip observer** — add a one-time subscription in `init()` that observes `UserDefaults.standard.publisher(for: \.aibattery_showAllAccountsInMenuBar)` and triggers `Task { await fetchAllAccounts() }` on change. This is what lets the menu bar populate immediately when the user enables the toggle, instead of waiting up to 30s for the next refresh tick.

   **Note on KVO key path:** Swift's KVO bridge needs the key as a `@objc dynamic` property on a `UserDefaults` extension, OR use `NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)` and filter for the key. Pick the notification approach — it's simpler and doesn't require an extension:
     ```swift
     NotificationCenter.default
         .publisher(for: UserDefaults.didChangeNotification)
         .debounce(for: .milliseconds(50), scheduler: DispatchQueue.main)
         .sink { [weak self] _ in
             Task { await self?.fetchAllAccounts() }
         }
         .store(in: &cancellables)
     ```
     This fires for ANY UserDefaults change; `fetchAllAccounts` is a no-op when toggle is OFF and the maps are already empty, so the over-broad signal is harmless. (The debounce also collapses bursts during settings open/close.)

### Tests to write (in this phase)

`Tests/AIBatteryCoreTests/ViewModels/UsageViewModelMultiAccountTests.swift` — new file:
- When toggle is OFF, `perAccountRateLimits` stays empty after `refresh()`.
- When toggle is ON and 2 accounts are authenticated, `perAccountRateLimits` has 2 entries after `refresh()`.
- When an account is `isPendingIdentity`, it's skipped.
- When `getAccessToken` returns nil for an account, that account is omitted (not crashed).
- A throttled account ends up in `perAccountThrottled`.

These will need a fake/test seam for `OAuthManager.getAccessToken` and `RateLimitFetcher.fetch`. Look at `Tests/AIBatteryCoreTests/Services/OAuthManagerTests.swift` and `Tests/AIBatteryCoreTests/Services/AccountStoreTests.swift` for how the existing tests stub these. **Confidence: Medium** — if no existing seam exists, add a `RateLimitFetching` protocol with `RateLimitFetcher.shared` as the default and a `MockRateLimitFetcher` in tests. This is a small refactor but contained.

### Verification

- `swift build` clean.
- New tests pass.
- With toggle OFF, behavior is bit-identical to today (regression test: existing tests still pass unchanged).
- Manual: enable toggle, observe `perAccountRateLimits` populated by checking it via a temporary debug print or breakpoint.

### Anti-pattern guards

- ❌ Don't make `OAuthManager.tokens` public — add the predicate method instead.
- ❌ Don't fetch sequentially — must use `TaskGroup`.
- ❌ Don't write `perAccountRateLimits` from a background context — `UsageViewModel` is `@MainActor`; the assignment must happen on main.

---

## Phase 3 — Menu bar text rendering

**Goal:** Render `"42% | 23%"` in the status bar when toggle is ON; star reflects worst account; countdown reflects worst account.

### Files to edit

1. **`AIBattery/Views/StatusBarManager.swift`** — In `updateButton(_:viewModel:)` (line **307**):
   - Read toggle: `let showAll = UserDefaults.standard.bool(forKey: UserDefaultsKeys.showAllAccountsInMenuBar)`.
   - If `showAll` AND `viewModel.perAccountRateLimits.count >= 2` AND not in countdown mode:
     - Resolve the per-account percent source via `MetricMode`:
       - `.fiveHour` → `RateLimitUsage.fiveHourPercent`
       - `.sevenDay` → `RateLimitUsage.sevenDayPercent`
       - `.contextHealth` → **fallback to `.fiveHour`** (context-health is per-session, not per-account; no meaningful per-account number exists). Document fallback in CONSTANTS.md.
     - Build text from `OAuthManager.shared.accountStore.accounts` in store order via the new `MenuBarMultiAccountText.build(...)` helper (extracted for testability — see below). Missing accounts → `"—"`. Joiner: `"\u{00A0}|\u{00A0}"`.
     - Compute "worst" percent: `viewModel.perAccountRateLimits.values.map { percentForMode(...) }.max() ?? activePercent`.
     - Compute `isBroken`: `!viewModel.perAccountThrottled.isEmpty || activeIsBroken`.
     - Pass `text`, `percent: worstPercent`, `color: ThemeColors.barNSColor(percent: worstPercent)`, `isBroken: anyBroken` to `MenuBarIcon.combinedStatusBarImage(...)`.
   - Else: existing single-account path (unchanged).

2. **Extract `MenuBarMultiAccountText` helper** — new file `AIBattery/Views/MenuBarMultiAccountText.swift`:
   ```swift
   import Foundation

   /// Pure text builder for the multi-account menu bar display.
   /// No AppKit / SwiftUI dependency — fully unit-testable.
   enum MenuBarMultiAccountText {
       struct Output: Equatable {
           let text: String          // e.g. "42% | 23%" with non-breaking spaces
           let worstPercent: Double  // for star color & breath
           let anyThrottled: Bool    // for broken-star state
       }

       static func build(
           order: [String],                         // AccountStore.accounts.map(\.id) in store order
           limits: [String: RateLimitUsage],        // viewModel.perAccountRateLimits
           metricMode: MetricMode                   // current active mode
       ) -> Output {
           let resolvedMode: MetricMode = (metricMode == .contextHealth) ? .fiveHour : metricMode
           let parts: [String] = order.map { id in
               guard let usage = limits[id] else { return "—" }
               let pct = percent(for: usage, mode: resolvedMode)
               return "\(Int(pct.rounded()))%"
           }
           let text = parts.joined(separator: "\u{00A0}|\u{00A0}")
           let worst = limits.values.map { percent(for: $0, mode: resolvedMode) }.max() ?? 0
           let throttled = limits.values.contains { $0.overallStatus == "throttled" }
           return Output(text: text, worstPercent: worst, anyThrottled: throttled)
       }

       private static func percent(for usage: RateLimitUsage, mode: MetricMode) -> Double {
           switch mode {
           case .fiveHour: return usage.fiveHourPercent
           case .sevenDay: return usage.sevenDayPercent
           case .contextHealth: return usage.fiveHourPercent  // belt-and-suspenders fallback
           }
       }
   }
   ```

3. **Combine sink expansion** (lines **199–205**) — add `perAccountRateLimits` so the button redraws when secondary accounts arrive. Use `Publishers.CombineLatest3` (Swift's `combineLatest(_:_:)` produces this):
   ```swift
   viewModel.$snapshot
       .combineLatest(viewModel.$lastFreshFetch, viewModel.$perAccountRateLimits)
       .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
       .sink { [weak self] _ in
           self?.updateButton(button, viewModel: viewModel)
       }
       .store(in: &cancellables)
   ```
   Note: keep `DispatchQueue.main` (matches existing pattern); the closure parameter is a single tuple, hence `_ in`.

4. **Toggle observer for instant propagation** — add a separate sink in StatusBarManager so the menu bar redraws within ≤200ms when the user flips the toggle (independent of the 30s refresh tick):
   ```swift
   NotificationCenter.default
       .publisher(for: UserDefaults.didChangeNotification)
       .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
       .sink { [weak self, weak viewModel] _ in
           guard let self, let viewModel else { return }
           self.updateButton(button, viewModel: viewModel)
       }
       .store(in: &cancellables)
   ```
   This is the visual companion to the `UsageViewModel`-side observer in Phase 2 — the VM observer triggers a fan-out fetch; this observer triggers a redraw with whatever data is currently in the maps.

5. **Countdown mode** (`startCountdownTimer` at lines ~466 and adjacent — note: file grew, line ranges shifted; locate by symbol, not by line):
   - When `showAll` is ON and 2+ accounts have data, "worst" reset = `min` over `perAccountRateLimits.values.compactMap { resetForMode($0, mode) }`.
   - If worst reset < 5 min away → countdown text from worst reset (no per-account countdown).
   - Existing single-countdown rendering path is reused; only the **source of the reset Date** changes.

### Other call sites of `updateButton` to be aware of

The function is called from 4 places in StatusBarManager.swift:
- Line **205** — Combine sink (snapshot/staleness changes) → covered by #3 above.
- Line **261** — appearance change handler (light/dark menu bar swap) → already calls `updateButton`; multi-account branch will rebuild correctly because it reads toggle + maps freshly.
- Line **476** — countdown timer first tick → already calls `updateButton`; covered by #5.
- Line **482** — countdown timer recurring tick → same.

No new call sites needed. All existing redraw paths produce consistent output because `updateButton` is the single source of truth.

### Tests to write

`Tests/AIBatteryCoreTests/Views/MenuBarMultiAccountTextTests.swift` — new file. Tests the pure builder (no AppKit dependency):

- **Format basics**
  - 2 accounts (42%, 23%) in store order → text == `"42%\u{00A0}|\u{00A0}23%"`.
  - 3 accounts (42%, 23%, 99%) → text == `"42%\u{00A0}|\u{00A0}23%\u{00A0}|\u{00A0}99%"`.
  - Order is `order` array order, NOT max-first or active-first.
- **Missing data**
  - One account in `order` has no entry in `limits` → that slot is `"—"`.
  - All accounts missing → text is `"—\u{00A0}|\u{00A0}—"` (still renders, doesn't crash).
- **Single-account fallback**
  - Only 1 entry in `order` → text has no separator, just `"42%"`. (Caller guards on `count >= 2`, but the builder must not crash if called with 1.)
- **Worst-percent**
  - mixed (12%, 87%, 45%) → `worstPercent == 87`.
  - empty `limits` → `worstPercent == 0`.
- **AnyThrottled**
  - all `overallStatus == "allowed"` → `anyThrottled == false`.
  - one `"throttled"` → `anyThrottled == true`.
- **MetricMode**
  - `.fiveHour` reads `fiveHourPercent`.
  - `.sevenDay` reads `sevenDayPercent`.
  - `.contextHealth` falls back to `fiveHourPercent` (regression-guard for the fallback rule).
- **Rounding**
  - 42.4% → `"42%"`, 42.6% → `"43%"` (uses `Int(pct.rounded())`).

### Verification

- `swift build` clean.
- New tests pass.
- Manual: toggle ON in settings, verify menu bar shows `"X% | Y%"` for 2 accounts and `"X% | Y% | Z%"` for 3.
- Manual: toggle OFF, verify single-account display is bit-identical.
- Manual: switch active account in popover, verify the order in the menu bar text doesn't change (it's AccountStore order, not active-first).

### Anti-pattern guards

- ❌ Don't render per-slot stars — one star, worst-account-derived.
- ❌ Don't bake the text builder into `updateButton` — extract for tests.
- ❌ Don't change the breathing animation pulse step logic — `pulseStep` continues to come from the existing breathing source, keyed only to worst percent.

---

## Phase 4 — Settings toggle

**Goal:** Surface the toggle under Display.

### Files to edit

1. **`AIBattery/Views/Settings/DisplaySettingsSection.swift`** — Add a new `@AppStorage` and toggle, copying the colorblind pattern at lines 51–62:
   ```swift
   @AppStorage(UserDefaultsKeys.showAllAccountsInMenuBar) private var showAllAccountsInMenuBar: Bool = false
   ```
   Inside the `// Display toggles` HStack, add a second toggle alongside Colorblind:
   ```swift
   Toggle("All accounts", isOn: $showAllAccountsInMenuBar)
       .toggleStyle(.checkbox)
       .font(Typography.caption)
       .help("Show every connected account's usage in the menu bar (e.g., 42% | 23%)")
   ```
   If the row gets too wide for the popover, split into two rows under the same "Display" label using a `VStack` — check the actual rendered width during manual verification before deciding.

### Tests to write

None for the toggle binding itself (`@AppStorage` is framework-tested). The behavioral tests in Phases 2 and 3 cover the effect.

### Verification

- `swift build` clean.
- Manual: open settings, toggle on, see menu bar update within ≤200ms (debounce); toggle off, see it revert.
- Manual: reopen the app, verify the toggle persisted.

### Anti-pattern guards

- ❌ Don't add a separate "Menu Bar" settings section — the user request was specifically "under Display."
- ❌ Don't make the toggle disabled when only 1 account is connected — when ON with 1 account, the menu bar quietly falls back to single-account display (covered by test in Phase 3). Disabling the toggle creates a state that "appears" once a second account is added, which is more confusing.

---

## Phase 5 — Tests consolidation

**Goal:** Make sure the test count and coverage table reflect reality.

### Files to verify / update

1. **`README.md`** Test Coverage section (442–455):
   - Update total test count (was 893; new tests in Phase 2 + Phase 3 add ~10 — **count exactly after Phase 2 and 3 land**, don't pre-fill).
   - Update test file count (was 59; we added 2 new files — `UsageViewModelMultiAccountTests.swift` and `StatusBarMultiAccountTextTests.swift` — so 61).
   - Update the "ViewModels" row count (+5 ish) and "Views" row count (+5 ish) — exact deltas come from the actual `@Test` count after writing.

### Verification

- `swift test` runs clean, count matches README.
- Run `grep -r "@Test" Tests/ | wc -l` to confirm test count.

---

## Phase 6 — Final verification

**Goal:** Prove the feature works end-to-end and nothing regressed.

### Checks

1. **Build:** `swift build` — clean.
2. **Tests:** `swift test` — all green; count matches README.
3. **Spec drift grep:**
   - `grep -r "aibattery_showAllAccountsInMenuBar" .` should hit CONSTANTS.md, UserDefaultsKeys.swift, DisplaySettingsSection.swift, StatusBarManager.swift (or the helper).
   - `grep -r "perAccountRateLimits" .` should hit UsageViewModel.swift, StatusBarManager.swift, the new test file, DATA_LAYER.md.
4. **Manual matrix** (using `./scripts/build-app.sh` per project memory):
   - 1 account, toggle OFF → unchanged.
   - 1 account, toggle ON → unchanged (single-account fallback).
   - 2 accounts, toggle OFF → unchanged.
   - 2 accounts, toggle ON → `"X% | Y%"` in menu bar; popover unchanged.
   - 3 accounts, toggle ON → `"X% | Y% | Z%"`.
   - 2 accounts, ON, one throttled → broken star pulses; both percents still shown.
   - 2 accounts, ON, one's reset is <5min away → countdown text replaces percents (worst-account-driven).
   - Toggle OFF mid-session → reverts to single-account at next refresh tick or sooner.
5. **API quota check:** Confirm one fetch cycle with toggle ON issues **exactly N requests for N authenticated accounts** — not N+1. The active account is in the fan-out but is served from `RateLimitFetcher`'s per-account cache (`APIFetchResult.isCached == true`). Verify by:
   - Add temporary `AppLogger.api.debug("fetch \(accountId) cached=\(result.isCached)")` in `RateLimitFetcher.fetch`.
   - Trigger one refresh cycle with 3 accounts, toggle ON.
   - Expect: 3 log lines, 1 with `cached=false` (active account, fresh) and 2 with `cached=false` (other two accounts, fresh) on first cycle; subsequent cycles within cache TTL show `cached=true` for the active account on the second (fan-out) call.
   - Remove the debug log before commit.
6. **Icon cache sanity:** Toggle ON should not balloon `MenuBarIcon` cache — text changes don't invalidate the icon cache (cache key is `(percent, color, isBroken, isSparkle, pulseStep)`); only star visuals do. Manual check: toggle ON, observe in Activity Monitor that memory doesn't grow with each refresh tick.
7. **Toggle propagation timing:** Flip the toggle ON in settings; expect menu bar text to switch from `"42%"` to `"42% | 23%"` within ~200ms (visual confirmation; no need to instrument). Flip OFF; expect immediate revert.
8. **CI parity:** Run `swift build --build-tests && swift test --skip-build` locally (matches the CI workflow steps after commit 4fe8c89). All green before tagging — this is the v2.1.8 lesson.

---

## Risk register

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| API quota multiplier (3× per cycle for 3 accounts) | Certain | Documented as cost of feature; no auto-throttle. User controls refresh interval globally. **Note:** active account is fetched twice per cycle (once via the existing single-account path, once via fan-out). RateLimitFetcher's per-account cache makes the duplicate a free cache hit (`APIFetchResult.isCached == true`), so net cost is N requests for N accounts, not N+1. Verify in Phase 6 by inspecting fetch logs. |
| Width clipping on small displays / many menu bar items | Possible | macOS auto-clips; we use non-breaking spaces to keep `42% | 23%` from breaking inside a slot. If users complain, add a "compact mode" later (`42|23`). Not in scope. |
| Race between active-account refresh and fan-out fetch | Low | Both go through `@MainActor` assignment; fan-out runs after active to avoid blocking the active account's UX. |
| `MockRateLimitFetcher` seam may not exist | Medium | If absent, add a `RateLimitFetching` protocol — small, contained, doesn't change runtime behavior. **Verify before Phase 2** by reading `Tests/AIBatteryCoreTests/Services/` for any existing fakes. |
| Breathing animation pulses on each fan-out tick | Low | Pulse step source is the existing breathing timer, not the fetch event. Combine sink debounce (200ms) prevents redraw storms. |
| One slow account blocks fan-out completion | Low | `TaskGroup` returns whichever completes first; we wait for all but the active path is unaffected (already complete). Worst-case latency = slowest account, which is bounded by the existing per-fetch timeout in `RateLimitFetcher`. |
| Pending-identity accounts have no real org ID | Certain | Filter via `!record.isPendingIdentity` before fanning out. |
| Toggle flip doesn't propagate until next refresh tick | Certain without fix | Phase 3 adds a `UserDefaults.standard.publisher(for:)` observer on the toggle key in StatusBarManager so the redraw fires within debounce window (≤200ms). |
| `MetricMode.contextHealth` doesn't apply per-account | Certain | When current mode is `.contextHealth`, the multi-account text builder falls back to `.fiveHour` percents (rationale: context-health is per-session, not per-account; the menu bar still needs a meaningful per-account number). Documented in Phase 3 and CONSTANTS.md. |
| `updateButton` has 4 call sites | Low | All 4 call sites pass through the same function — no per-site change needed. The multi-account branch reads toggle + maps freshly each call, so all redraw paths produce consistent output. |
| CI test bundle missing on first run | Low | Project memory: v2.1.8 hit this when test files changed but `--build-tests` flag was missing. Fix is now in `release.yml` and `ci.yml` (commit 4fe8c89). Phase 6 verifies by running `swift test` locally before tagging. |

---

## Summary of files touched

**New:**
- `AIBattery/Views/MenuBarMultiAccountText.swift` (pure text builder, fully testable)
- `Tests/AIBatteryCoreTests/ViewModels/UsageViewModelMultiAccountTests.swift`
- `Tests/AIBatteryCoreTests/Views/MenuBarMultiAccountTextTests.swift`

**Edited:**
- `AIBattery/Utilities/UserDefaultsKeys.swift` (+1 key)
- `AIBattery/Services/OAuthManager.swift` (add `isAuthenticated(accountId:) -> Bool`)
- `AIBattery/ViewModels/UsageViewModel.swift` (3 new `@Published` maps + `fetchAllAccounts()` + UserDefaults observer in `init`)
- `AIBattery/Views/StatusBarManager.swift` (multi-account branch in `updateButton` + 3-publisher Combine sink + UserDefaults toggle observer + countdown source switch)
- `AIBattery/Views/Settings/DisplaySettingsSection.swift` (toggle)
- `spec/ARCHITECTURE.md`
- `spec/UI_SPEC.md`
- `spec/CONSTANTS.md`
- `spec/DATA_LAYER.md`
- `README.md` (settings bullet + test count)

---

## Estimated effort

- Phase 0: done.
- Phase 1: 30 min (specs — 5 files, mostly small inserts).
- Phase 2: 2–3 hr (fan-out + 3 wiring sites + UserDefaults observer + tests + possible `RateLimitFetching` protocol seam if absent).
- Phase 3: 2–2.5 hr (extract `MenuBarMultiAccountText`, multi-account branch in `updateButton`, expand Combine sink, add UserDefaults observer for toggle, countdown source switch, tests).
- Phase 4: 20 min (toggle binding + manual verification of popover width with two checkboxes side-by-side; split into rows if cramped).
- Phase 5: 15 min (README test count + bullet).
- Phase 6: 45–60 min (8-step manual matrix + grep checks + temporary debug log for cache-hit verification + clean up).

**Total: ~7–8 hr** for a single working session, including manual verification.

---

## Pre-flight before each phase

Before starting any phase in a fresh context:
1. `git status` — confirm clean tree (or expected branch state).
2. Re-grep the symbols cited in that phase to verify line numbers haven't drifted (this iteration verified 2026-05-07; lines move when the file is edited).
3. `swift build` — confirm baseline green before adding code.

This catches drift early and keeps each phase self-contained.
