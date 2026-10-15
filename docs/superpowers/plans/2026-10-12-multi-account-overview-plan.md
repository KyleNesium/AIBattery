# Multi-Account Overview Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** With two or more accounts, the popover opens on an overview of one card per account (quota bars, resets, state); tapping a card switches to that account's detail view; a back chevron returns.

**Architecture:** A `PopoverMode` on `UsagePopoverView` (overview / detail), decided per panel show from the eligible account count. The fan-out becomes the overview's data source: it runs whenever ≥ 2 eligible accounts exist, returns an `AccountReading` per account (windows or per-minute limits, freshness), and both providers' status feeds are polled while both have accounts. Cards are built by a pure `AccountCard.rows(...)` model from the store, the readings and the statuses; the view is a thin renderer over `GaugeBar`.

**Tech Stack:** Swift 6 / SwiftUI, SPM, Swift Testing (`import Testing`, `@testable import AIBatteryCore`).

**Spec:** `docs/superpowers/specs/2026-10-12-multi-account-overview-design.md` (§1 modes, §2 data, §3 overview layout, §4 detail changes, §5 flow, §6 a11y, §7 folded prerequisite, §8 settings, §9 errors, §10 testing, §11 research).

## Global Constraints

- macOS 13+, Swift 6 strict concurrency, zero new warnings; `swiftformat AIBattery/ AIBatteryApp/ Tests/` + `swiftlint` clean before every push.
- No `.move(edge:)` transitions (pinned by `MoveTransitionBanTests`); mode changes animate with `.opacity` only.
- Headless-CI rules: suites touching AppKit colours are `@MainActor`; never construct `UsageViewModel()` in tests; never touch `SparkleUpdateService.shared`; no dynamic `NSColor` equality off-main.
- Never copy an identity into `AccountRecord.displayName`; identities are masked by default (`identityLabel(maskEmail:)`).
- Verification on the local build uses accessibility **clicks only** — no System Events `keystroke` / `key code` (they go to the frontmost app).
- Cost framing unchanged; the overview shows no cost.
- One integration branch, one PR, tested locally per task; CI once when marked ready (`workflow_dispatch` for re-runs). Commit per task, `<type>: <description>`, **no Co-Authored-By trailers**.
- README "Test Coverage" table updated in the same commit as any test change; `CLAUDE.md` counts at wrap-up.
- **Executed as Phase 1 of `2026-10-12-v3-1-0-release-plan.md`** on branch `worktree-v3-1-0`, one draft PR for the whole release (stays draft until Kyle says done). Each task that adds user-visible behaviour appends one line under `### Added` in `CHANGELOG.md` (`## [3.1.0] — Unreleased`).

---

## File Structure

| Action | Path | Responsibility |
|---|---|---|
| Create | `AIBattery/Models/AccountReading.swift` | Per-account fan-out result (`windows`, `apiLimits`, `fetchedAt`, `isCached`, `source`) + `FanOutGate` |
| Modify | `AIBattery/ViewModels/MultiAccountFanOut.swift` | `resolve` → `[String: AccountReading]?`, merge-onto-previous, API-key accounts eligible, both status feeds |
| Modify | `AIBattery/ViewModels/UsageViewModel.swift:25`, `UsageViewModel+FanOut.swift` | `perAccountReadings`, computed `perAccountRateLimits`, `providerStatuses`, gate |
| Modify | `AIBattery/Views/MenuBarMultiAccountText.swift`, `StatusBarManager+ButtonUpdate.swift` | per-minute API-key slots (`apiLimits`) |
| Create | `AIBattery/Models/PopoverMode.swift` | `PopoverMode` + `initial(eligibleAccountCount:)` + `next(current:eligibleAccountCount:)` |
| Create | `AIBattery/Models/AccountCard.swift` | Pure card model: `rows(...)`, `BarRow`, `Footer`, worst percent, a11y text |
| Create | `AIBattery/Views/AccountCardView.swift` | Card renderer (header line, bar rows, footer line) |
| Create | `AIBattery/Views/OverviewContentView.swift` | Overview header + card list + add link |
| Modify | `AIBattery/Views/UsagePopoverView.swift` | `mode` state, body branch, show/dismiss/account-change hooks, overview key handling |
| Modify | `AIBattery/Views/PopoverHeaderView.swift` | `showsBack` / `onBack` chevron |
| Modify | `AIBattery/Views/StatusBarManager+Panel.swift`, `StatusBarManager.swift` | `escapeHandler` closure consulted before closing |
| Modify | `AIBattery/Views/Settings/DisplaySettingsSection.swift`, `RefreshSettingsSection.swift` | toggle hint copy; poll-cost "×N accounts" |
| Modify | `AIBattery/Utilities/Spacing.swift` | `Layout.cardBarLabelWidth`, `cardPercentWidth`, `cardResetWidth` |
| Modify | `spec/*.md`, `README.md`, `CLAUDE.md`, provider-relevance spec/plan, `CHANGELOG.md` | sync |
| Tests | create `Tests/AIBatteryCoreTests/Models/AccountReadingTests.swift`, `Models/PopoverModeTests.swift`, `Models/AccountCardTests.swift`, `Views/PopoverHeaderBackTests.swift`; extend `ViewModels/MultiAccountFanOutTests.swift`, `Views/MenuBarMultiAccountTextTests.swift`, `Services/AccountStoreProviderTests.swift`, `Views/RefreshSettingsSectionTests.swift` (or the suite that covers `pollCostHint`) | |

Run all tests with `swift test`; one suite with `swift test --filter "<SuiteName>"`.

---

### Task 1: `AccountReading`, `FanOutGate`, and API-key accounts in the fan-out + menu bar

**Files:**
- Create: `AIBattery/Models/AccountReading.swift`
- Modify: `AIBattery/ViewModels/MultiAccountFanOut.swift:63-74` (eligibility), `:97-154` (`resolve`)
- Modify: `AIBattery/ViewModels/UsageViewModel.swift:23-25`, `AIBattery/ViewModels/UsageViewModel+FanOut.swift:34-48`
- Modify: `AIBattery/Views/MenuBarMultiAccountText.swift:36-74`, `AIBattery/Views/StatusBarManager+ButtonUpdate.swift:46-79`
- Test: `Tests/AIBatteryCoreTests/Models/AccountReadingTests.swift` (new), `Tests/AIBatteryCoreTests/ViewModels/MultiAccountFanOutTests.swift`, `Tests/AIBatteryCoreTests/Views/MenuBarMultiAccountTextTests.swift`, `Tests/AIBatteryCoreTests/Services/AccountStoreProviderTests.swift:51`

**Interfaces:**
- Produces:
  ```swift
  struct AccountReading: Equatable, Sendable {
      var windows: RateLimitUsage?
      var apiLimits: StandardRateLimits?
      var fetchedAt: Date
      var isCached: Bool
      var source: RateLimitSource?
      var worstPercent: Double?   // windows: max(5h, 7d) or credits usedPercent; api: peakPercent; nil if neither
      var isExhausted: Bool       // windows.isThrottled || worst >= 100 || api requests/tokens exhausted
  }
  enum FanOutGate { static func enabled(menuBarToggle: Bool, eligibleAccountCount: Int) -> Bool }
  ```
  `MultiAccountFanOut.resolve(enabled:seed:previous:provider:fetcher:now:) async -> [String: AccountReading]?` (new `previous: [String: AccountReading]` parameter, default `[:]`).
  `UsageViewModel.perAccountReadings: [String: AccountReading]` (`@Published`), computed `perAccountRateLimits: [String: RateLimitUsage]`.
  `MenuBarMultiAccountText.build(order:providers:limits:apiLimits:metricMode:)` (`apiLimits` defaulted `[:]`).
- Consumes: `APIFetchResult.rateLimits / standardLimits / fetchedAt / isCached / rateLimitSource`; `StandardRateLimits.peakPercent / isRequestsExhausted / isTokensExhausted / withClearedExpiredWindows(now:)`.

- [ ] **Step 1: Failing model tests**

Create `Tests/AIBatteryCoreTests/Models/AccountReadingTests.swift`:

```swift
import Foundation
import Testing
@testable import AIBatteryCore

@Suite("AccountReading")
struct AccountReadingTests {
    private func windows(fiveHour: Double, sevenDay: Double, throttled: Bool = false) -> RateLimitUsage {
        RateLimitUsage(
            representativeClaim: "five_hour",
            fiveHourUtilization: fiveHour, fiveHourReset: nil, fiveHourStatus: throttled ? "throttled" : "allowed",
            sevenDayUtilization: sevenDay, sevenDayReset: nil, sevenDayStatus: "allowed",
            overallStatus: throttled ? "throttled" : "allowed"
        )
    }

    private func api(requestsRemaining: String, tokensRemaining: String) -> StandardRateLimits {
        StandardRateLimits.parse(openAIHeaders: [
            "x-ratelimit-limit-requests": "100", "x-ratelimit-remaining-requests": requestsRemaining,
            "x-ratelimit-limit-tokens": "1000", "x-ratelimit-remaining-tokens": tokensRemaining,
        ], now: .now)!
    }

    @Test func worstPercent_windows_isMaxOfBothWindows() {
        let r = AccountReading(windows: windows(fiveHour: 0.34, sevenDay: 0.26), apiLimits: nil, fetchedAt: .now, isCached: false, source: nil)
        #expect(r.worstPercent == 34)
        #expect(r.isExhausted == false)
    }

    @Test func worstPercent_api_isPeakPercent() {
        let r = AccountReading(windows: nil, apiLimits: api(requestsRemaining: "20", tokensRemaining: "900"), fetchedAt: .now, isCached: false, source: nil)
        #expect(r.worstPercent == 80)
    }

    @Test func exhausted_whenThrottledOrApiExhausted() {
        let t = AccountReading(windows: windows(fiveHour: 0.5, sevenDay: 0.1, throttled: true), apiLimits: nil, fetchedAt: .now, isCached: false, source: nil)
        #expect(t.isExhausted)
        let a = AccountReading(windows: nil, apiLimits: api(requestsRemaining: "0", tokensRemaining: "900"), fetchedAt: .now, isCached: false, source: nil)
        #expect(a.isExhausted)
    }

    @Test func noReading_hasNilPercent() {
        let r = AccountReading(windows: nil, apiLimits: nil, fetchedAt: .now, isCached: true, source: nil)
        #expect(r.worstPercent == nil)
    }

    @Test func fanOutGate_toggleOrTwoAccounts() {
        #expect(FanOutGate.enabled(menuBarToggle: false, eligibleAccountCount: 1) == false)
        #expect(FanOutGate.enabled(menuBarToggle: true, eligibleAccountCount: 1) == true)
        #expect(FanOutGate.enabled(menuBarToggle: false, eligibleAccountCount: 2) == true)
        #expect(FanOutGate.enabled(menuBarToggle: false, eligibleAccountCount: 0) == false)
    }
}
```

- [ ] **Step 2: Failing fan-out / menu-bar / eligibility tests**

`AccountStoreProviderTests` — replace `multiAccountDisplayIDs_excludesAPIKeyAccounts` (L51) with `multiAccountDisplayIDs_includesAPIKeyAccounts` asserting the API-key record's id **is** present (same fixture, flipped expectation).

`MultiAccountFanOutTests` — using the suite's existing mock provider / fetcher types (they return an `APIFetchResult` per id), add:

```swift
    @Test func resolve_buildsReadings_routingApiLimits_andKeepsPreviousOnFailure() async {
        let std = StandardRateLimits.parse(openAIHeaders: [
            "x-ratelimit-limit-requests": "100", "x-ratelimit-remaining-requests": "20",
            "x-ratelimit-limit-tokens": "1000", "x-ratelimit-remaining-tokens": "900",
        ], now: .now)!
        let previous: [String: AccountReading] = [
            "dead": AccountReading(windows: makeLimits(fiveHour: 0.5, sevenDay: 0.5), apiLimits: nil, fetchedAt: .now, isCached: false, source: nil),
        ]
        // "api-1" returns standard limits only; "dead" returns nothing (fetch failed)
        let fetcher = MockFetcher(results: [
            "api-1": APIFetchResult(rateLimits: nil, rateLimitSource: nil, standardLimits: std, profile: nil, hasStandardRateLimitHeaders: true, fetchedAt: .now, isCached: false, authError: false, planType: "api", endpointUnavailable: false),
            "dead": APIFetchResult(rateLimits: nil, profile: nil),
        ])
        let result = await MultiAccountFanOut.resolve(enabled: true, seed: nil, previous: previous, provider: MockProvider(ids: ["api-1", "dead"]), fetcher: fetcher)
        #expect(result?["api-1"]?.apiLimits?.peakPercent == 80)
        #expect(result?["api-1"]?.windows == nil)
        #expect(result?["dead"]?.isCached == true)           // kept from `previous`, marked cached
        #expect(result?["dead"]?.windows?.fiveHourPercent == 50)
    }
```

(Adjust the `APIFetchResult` memberwise call to the real initializer order in `AIBattery/Models/APIFetchResult.swift`; the suite's existing `makeLimits` helper builds a `RateLimitUsage`.)

`MenuBarMultiAccountTextTests`:

```swift
    @Test func build_apiKeySlot_usesPeakPercent_andCountsTowardWorst() {
        let std = StandardRateLimits.parse(openAIHeaders: [
            "x-ratelimit-limit-requests": "100", "x-ratelimit-remaining-requests": "20",
            "x-ratelimit-limit-tokens": "1000", "x-ratelimit-remaining-tokens": "900",
        ], now: .now)!
        let out = MenuBarMultiAccountText.build(
            order: ["c1", "k1"], providers: ["c1": .claude, "k1": .codex],
            limits: ["c1": makeLimits(fiveHour: 0.3, sevenDay: 0.1)],
            apiLimits: ["k1": std], metricMode: .fiveHour
        )
        #expect(out.text.contains("30%"))
        #expect(out.text.contains("80%"))
        #expect(out.worstPercent == 80)
        #expect(out.anyThrottled == false)
    }
```

- [ ] **Step 3: Run to verify failure**

Run: `swift test --filter "AccountReading|MultiAccountFanOut|MenuBarMultiAccountText|AccountStoreProvider"`
Expected: compile errors (`AccountReading`, `FanOutGate`, `previous:`, `apiLimits:`).

- [ ] **Step 4: Implement the model**

Create `AIBattery/Models/AccountReading.swift`:

```swift
import Foundation

/// One account's latest quota reading from the multi-account fan-out. Windowed plans and
/// Codex credit budgets arrive as `windows`; Codex API keys as per-minute `apiLimits`.
/// Kept apart on purpose — nothing is coerced into the other shape.
struct AccountReading: Equatable, Sendable {
    var windows: RateLimitUsage?
    var apiLimits: StandardRateLimits?
    var fetchedAt: Date
    /// True when this reading did not come from a fresh fetch (served from cache or
    /// carried over after a failed fetch).
    var isCached: Bool
    var source: RateLimitSource?

    /// The number a card or menu-bar slot leads with: the fuller window, the credit
    /// budget, or the busier per-minute limit. nil when nothing has been read yet.
    var worstPercent: Double? {
        if let windows {
            if let budget = windows.creditBudget {
                return budget.isUncapped ? nil : budget.usedPercent
            }
            return max(windows.fiveHourPercent, windows.sevenDayPercent)
        }
        return apiLimits?.peakPercent
    }

    var isExhausted: Bool {
        if let windows {
            return windows.isThrottled || (worstPercent ?? 0) >= 100
        }
        if let apiLimits {
            return apiLimits.isRequestsExhausted || apiLimits.isTokensExhausted
        }
        return false
    }

    /// Build from a fetch result; nil when the result carries neither shape.
    init?(api: APIFetchResult) {
        guard api.rateLimits != nil || api.standardLimits != nil else { return nil }
        windows = api.rateLimits
        apiLimits = api.rateLimits == nil ? api.standardLimits : nil
        fetchedAt = api.fetchedAt
        isCached = api.isCached
        source = api.rateLimitSource
    }

    init(windows: RateLimitUsage?, apiLimits: StandardRateLimits?, fetchedAt: Date, isCached: Bool, source: RateLimitSource?) {
        self.windows = windows; self.apiLimits = apiLimits; self.fetchedAt = fetchedAt
        self.isCached = isCached; self.source = source
    }

    /// The same reading, normalised for display at `now` (expired windows cleared,
    /// rollover artifacts suppressed).
    func normalized(now: Date) -> AccountReading {
        var copy = self
        copy.windows = windows?.withClearedExpiredWindows(now: now).withClearedRolloverArtifacts(now: now)
        copy.apiLimits = apiLimits?.withClearedExpiredWindows(now: now)
        return copy
    }

    /// The reading to keep when a fetch fails: the previous one, marked cached.
    func carriedForward() -> AccountReading {
        var copy = self
        copy.isCached = true
        return copy
    }
}

/// When the per-account fan-out runs: for the menu bar (toggle) or for the overview
/// (two or more eligible accounts).
enum FanOutGate {
    static func enabled(menuBarToggle: Bool, eligibleAccountCount: Int) -> Bool {
        menuBarToggle || eligibleAccountCount >= 2
    }
}
```

- [ ] **Step 5: Fan-out + eligibility**

`MultiAccountFanOut.swift`:
- In `multiAccountDisplayIDs`, delete the `.filter { !$0.isAPIKeyAccount }` line and its comment.
- Change `resolve` to:

```swift
    static func resolve(
        enabled: Bool,
        seed: (accountId: String, rateLimits: RateLimitUsage)?,
        previous: [String: AccountReading] = [:],
        provider: MultiAccountTokenProviding,
        fetcher: RateLimitFetching,
        now: Date = .now
    ) async -> [String: AccountReading]? {
        guard enabled else { return nil }
        let idsToFetch = provider.multiAccountDisplayIDs().filter { $0 != seed?.accountId }
        if idsToFetch.isEmpty, seed == nil { return nil }

        var collected: [String: AccountReading] = [:]
        if let seed {
            collected[seed.accountId] = AccountReading(windows: seed.rateLimits, apiLimits: nil, fetchedAt: now, isCached: false, source: nil)
        }
        if !idsToFetch.isEmpty {
            let fetched = await withTaskGroup(of: (String, AccountReading?).self) { group -> [String: AccountReading?] in
                for id in idsToFetch {
                    group.addTask {
                        guard let token = await provider.accessToken(for: id) else {
                            AppLogger.network.info("Fan-out skipped \(id, privacy: .public): no access token")
                            return (id, nil)
                        }
                        let api = await fetcher.fetch(accessToken: token, accountId: id)
                        let reading = AccountReading(api: api)
                        if reading == nil {
                            AppLogger.network.info("Fan-out skipped \(id, privacy: .public): fetch returned no limits")
                        }
                        return (id, reading)
                    }
                }
                var inner: [String: AccountReading?] = [:]
                for await (id, reading) in group { inner[id] = reading }
                return inner
            }
            for id in idsToFetch {
                if let reading = fetched[id] ?? nil {
                    collected[id] = reading
                } else if let old = previous[id] {
                    collected[id] = old.carriedForward()   // never blank a card between polls
                }
            }
        }
        return collected.mapValues { $0.normalized(now: now) }
    }
```

`UsageViewModel.swift:23-25` → replace with:

```swift
    /// Per-account readings from the multi-account fan-out (menu bar + overview).
    @Published var perAccountReadings: [String: AccountReading] = [:]
    /// Windowed readings only — the menu-bar text path and its tests consume this shape.
    var perAccountRateLimits: [String: RateLimitUsage] { perAccountReadings.compactMapValues(\.windows) }
    var perAccountAPILimits: [String: StandardRateLimits] { perAccountReadings.compactMapValues(\.apiLimits) }
```

Search for every write to `perAccountRateLimits` (`UsageViewModel+FanOut.swift`, `clearAccountDisplayState`, sign-out/prune paths) and point them at `perAccountReadings`. `fetchAllAccounts`:

```swift
    func fetchAllAccounts(seed: (accountId: String, rateLimits: RateLimitUsage)? = nil) async {
        let toggle = UserDefaults.standard.bool(forKey: UserDefaultsKeys.showAllAccountsInMenuBar)
        let eligible = OAuthManager.shared.multiAccountDisplayIDs().count
        let resolved = await MultiAccountFanOut.resolve(
            enabled: FanOutGate.enabled(menuBarToggle: toggle, eligibleAccountCount: eligible),
            seed: seed,
            previous: perAccountReadings,
            provider: OAuthManager.shared,
            fetcher: ProviderDispatchingFetcher.live(accountStore: OAuthManager.shared.accountStore)
        )
        if let resolved {
            perAccountReadings = resolved
        } else if !perAccountReadings.isEmpty {
            perAccountReadings = [:]
        }
    }
```

Also call `scheduleFanOut()` from the existing `accountStore.$accounts` sink in `UsageViewModel.init` (where the toggle observer lives, L187) so adding/removing an account re-runs the fan-out.

- [ ] **Step 6: Menu bar per-minute slots**

`MenuBarMultiAccountText.build` — new signature `build(order:providers: = [:], limits:, apiLimits: [String: StandardRateLimits] = [:], metricMode:)`. In `parts`, before `guard let usage = limits[id]`: `if let std = apiLimits[id] { return "\(Int(std.peakPercent.rounded()))%" }`. `worstPercent` = max over `shown` windows **and** `order.compactMap { apiLimits[$0]?.peakPercent }`; `anyThrottled` also `|| order.contains { id in apiLimits[id].map { $0.isRequestsExhausted || $0.isTokensExhausted } ?? false }`. `shouldRender(toggleOn:fetchedAccountCount:)` callers pass `perAccountReadings.count`. `StatusBarManager+ButtonUpdate.updateButton`: pass `apiLimits: viewModel.perAccountAPILimits`.

- [ ] **Step 7: Run tests, smoke test, commit**

`swift test --filter "AccountReading|MultiAccountFanOut|MenuBarMultiAccountText|AccountStoreProvider|StatusBar|UsageViewModel"` → PASS; then `swift test` (full) → PASS. Build (`./scripts/build-app.sh && open .build/AIBattery.app`), enable "All accounts in menu bar": the API-key account now shows `⬡ NN%`.
Docs: `spec/DATA_LAYER.md` (`AccountReading`, `FanOutGate`, fan-out merge-onto-previous, `perAccountReadings`), `spec/UI_SPEC.md` menu bar (per-minute slot replaces the exclusion sentence), `spec/ARCHITECTURE.md` dispatch table "Rate limits" row. README Models/ViewModels/Views rows.

```bash
swiftformat AIBattery/ Tests/ && swiftlint --quiet
git add -A
git commit -m "feat: per-account readings in the fan-out; API-key accounts in the menu bar"
```

---

### Task 2: Both providers' status feeds

**Files:**
- Modify: `AIBattery/ViewModels/UsageViewModel.swift` (new `@Published var providerStatuses: [AIProvider: ClaudeSystemStatus] = [:]`; write-through at L391), `AIBattery/ViewModels/UsageViewModel+FanOut.swift` (fetch the other feed)
- Test: `Tests/AIBatteryCoreTests/ViewModels/MultiAccountFanOutTests.swift`

**Interfaces:**
- Produces: `UsageViewModel.providerStatuses`; `MultiAccountFanOut.otherProviders(eligible: [AccountRecord], active: AIProvider) -> [AIProvider]` (pure).

- [ ] **Step 1: Failing test**

```swift
    @Test func otherProviders_listsProvidersWithEligibleAccountsOtherThanActive() {
        let accounts = [
            AccountRecord(id: "c1", addedAt: .now, provider: .claude),
            AccountRecord(id: "x1", addedAt: .now, provider: .codex),
        ]
        #expect(MultiAccountFanOut.otherProviders(eligible: accounts, active: .claude) == [.codex])
        #expect(MultiAccountFanOut.otherProviders(eligible: [accounts[0]], active: .claude) == [])
    }
```

- [ ] **Step 2: Run to verify failure** — `swift test --filter MultiAccountFanOut` → compile error.

- [ ] **Step 3: Implement**

```swift
    /// Providers (other than the active one) that have an eligible account, so the
    /// overview can show their status dot. Each `StatusChecker` instance keeps its own
    /// cache + backoff, so polling both per cycle is safe (spec R1).
    nonisolated static func otherProviders(eligible: [AccountRecord], active: AIProvider) -> [AIProvider] {
        Array(Set(eligible.map(\.provider)).subtracting([active])).sorted { $0.rawValue < $1.rawValue }
    }
```

In `fetchAllAccounts`, after the readings are stored:

```swift
        let store = OAuthManager.shared.accountStore
        let eligibleRecords = OAuthManager.shared.multiAccountDisplayIDs().compactMap { store.account(id: $0) }
        let active = store.activeAccount?.provider ?? .claude
        for provider in MultiAccountFanOut.otherProviders(eligible: eligibleRecords, active: active) {
            providerStatuses[provider] = await StatusChecker.shared(for: provider).fetchStatus()
        }
```

At `UsageViewModel.swift:391` (`systemStatus = status`) add `providerStatuses[activeProvider] = status` (use the provider resolved in that refresh). `switchAccount` / `clearAccountDisplayState` leave `providerStatuses` alone (it is per provider, not per account).

- [ ] **Step 4: Run tests + commit**

`swift test --filter "MultiAccountFanOut|UsageViewModel"` → PASS. Docs: `spec/DATA_LAYER.md` `UsageViewModel` (+ `providerStatuses`), status feed paragraph in `spec/ARCHITECTURE.md`.

```bash
swiftformat AIBattery/ Tests/ && swiftlint --quiet
git add -A
git commit -m "feat: poll both providers' status feeds when both have accounts"
```

---

### Task 3: `PopoverMode` and the view-level mode switch (no overview UI yet)

**Files:**
- Create: `AIBattery/Models/PopoverMode.swift`
- Modify: `AIBattery/Views/UsagePopoverView.swift` (`@State mode`, body branch, `.panelDidShow` / dismiss / `$accounts` hooks)
- Test: `Tests/AIBatteryCoreTests/Models/PopoverModeTests.swift` (new)

**Interfaces:**
- Produces:
  ```swift
  enum PopoverMode: Equatable { case overview, detail
      static func initial(eligibleAccountCount: Int) -> PopoverMode
      static func next(current: PopoverMode, eligibleAccountCount: Int) -> PopoverMode }
  ```
- Consumes: `OAuthManager.shared.multiAccountDisplayIDs()` for the eligible count (plus signed-out accounts, see Task 5 — the count used for the mode is `AccountCard.eligibleCount`, defined in Task 5; until then use `multiAccountDisplayIDs().count`).

- [ ] **Step 1: Failing tests**

```swift
import Testing
@testable import AIBatteryCore

@Suite("PopoverMode")
struct PopoverModeTests {
    @Test func initial_overviewOnlyWithTwoOrMore() {
        #expect(PopoverMode.initial(eligibleAccountCount: 0) == .detail)
        #expect(PopoverMode.initial(eligibleAccountCount: 1) == .detail)
        #expect(PopoverMode.initial(eligibleAccountCount: 2) == .overview)
        #expect(PopoverMode.initial(eligibleAccountCount: 6) == .overview)
    }

    @Test func next_dropsToDetailWhenOneAccountRemains_keepsDetailOtherwise() {
        #expect(PopoverMode.next(current: .overview, eligibleAccountCount: 1) == .detail)
        #expect(PopoverMode.next(current: .overview, eligibleAccountCount: 2) == .overview)
        #expect(PopoverMode.next(current: .detail, eligibleAccountCount: 3) == .detail)
        #expect(PopoverMode.next(current: .detail, eligibleAccountCount: 1) == .detail)
    }
}
```

- [ ] **Step 2: Run to verify failure** — `swift test --filter PopoverMode` → compile error.

- [ ] **Step 3: Implement**

```swift
import Foundation

/// Which face the popover shows: all accounts at once, or the active account's detail.
enum PopoverMode: Equatable, Sendable {
    case overview
    case detail

    /// On every panel open: two or more eligible accounts land on the overview.
    static func initial(eligibleAccountCount: Int) -> PopoverMode {
        eligibleAccountCount >= 2 ? .overview : .detail
    }

    /// While open: losing accounts down to one leaves the overview; gaining accounts
    /// never yanks the user out of a detail view.
    static func next(current: PopoverMode, eligibleAccountCount: Int) -> PopoverMode {
        if current == .overview, eligibleAccountCount < 2 { return .detail }
        return current
    }
}
```

`UsagePopoverView`:
- `@State private var mode: PopoverMode = .detail`
- `private var eligibleAccountCount: Int { OAuthManager.shared.multiAccountDisplayIDs().count }`
- Body: `if let addingProvider { … } else if mode == .overview { overviewContent } else { mainContent }` — for this task `overviewContent` is a placeholder `Text("Accounts")` padded to 60 pt so the branch compiles (replaced in Task 5).
- In the `.panelDidShow` handler: `mode = PopoverMode.initial(eligibleAccountCount: eligibleAccountCount)` before arming `deferredRender`.
- In `resetTransientPopoverState()`: `mode = .detail`.
- Add `.onReceive(accountStore.$accounts) { _ in mode = PopoverMode.next(current: mode, eligibleAccountCount: eligibleAccountCount) }` on `mainContent`'s container (the add-overlay `onReceive` stays where it is).
- `deferredRender.appeared()` must only fire when `mode == .detail`; add that guard in the show handler, and arm it when entering `.detail` later (Task 5).

- [ ] **Step 4: Run tests + commit**

`swift test --filter "PopoverMode|MoveTransitionBan"` → PASS; `swift build` clean. Local check: with 2 accounts the popover now opens on the placeholder; with 1 it is unchanged.

```bash
swiftformat AIBattery/ Tests/ && swiftlint --quiet
git add -A
git commit -m "feat: popover mode (overview/detail) decided per open from the account count"
```

---

### Task 4: `AccountCard` pure model

**Files:**
- Create: `AIBattery/Models/AccountCard.swift`
- Modify: `AIBattery/Utilities/Spacing.swift` (`Layout.cardBarLabelWidth = 52`, `cardPercentWidth = 34`, `cardResetWidth = 46`)
- Test: `Tests/AIBatteryCoreTests/Models/AccountCardTests.swift` (new)

**Interfaces:**
- Produces:
  ```swift
  struct AccountCard: Identifiable, Equatable {
      enum State: Equatable { case throttled, limitReached, signedOut, timeToLimit(TimeInterval), cached(Date), fetching, none }
      struct BarRow: Equatable { let label: String; let percent: Double?; let reset: Date?; let uncapped: Bool }
      let id: String; let provider: AIProvider; let identity: String; let plan: String?
      let isActive: Bool; let status: StatusIndicator?; let worstPercent: Double?
      let bars: [BarRow]; let state: State
      var accessibilityLabel: String
      static func rows(accounts: [AccountRecord], activeId: String?, readings: [String: AccountReading],
                       statuses: [AIProvider: ClaudeSystemStatus], isAuthenticated: (String) -> Bool,
                       maskEmail: Bool, now: Date) -> [AccountCard]
      static func eligibleCount(accounts: [AccountRecord], isAuthenticated: (String) -> Bool) -> Int
      static func stateText(_ state: State, now: Date) -> String?
  }
  ```
- Consumes: `AccountReading` (Task 1), `AccountStore.displayOrdered / providerIndex / identityLabel / planLabel`, `RateLimitUsage.estimatedTimeToLimit(for:)`, `CodexCreditBudget`, `StandardRateLimits`, `UsageBar.AlarmState`.

- [ ] **Step 1: Failing tests**

```swift
import Foundation
import Testing
@testable import AIBatteryCore

@Suite("AccountCard")
struct AccountCardTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func rec(_ id: String, _ provider: AIProvider, name: String? = nil, billing: String? = nil, apiKey: Bool = false) -> AccountRecord {
        AccountRecord(id: id, displayName: name, billingType: billing, addedAt: now, provider: provider,
                      codexAccessMode: apiKey ? .apiKey : nil, discoveredIdentity: nil)
    }

    private func windows(_ five: Double, _ seven: Double, throttled: Bool = false, resetIn: TimeInterval = 3600) -> AccountReading {
        let rl = RateLimitUsage(
            representativeClaim: "five_hour",
            fiveHourUtilization: five, fiveHourReset: now.addingTimeInterval(resetIn), fiveHourStatus: throttled ? "throttled" : "allowed",
            sevenDayUtilization: seven, sevenDayReset: now.addingTimeInterval(resetIn * 24), sevenDayStatus: "allowed",
            overallStatus: throttled ? "throttled" : "allowed"
        )
        return AccountReading(windows: rl, apiLimits: nil, fetchedAt: now, isCached: false, source: nil)
    }

    @Test func rows_claudeFirst_activeFlag_worstPercent_andLabels() {
        let accounts = [rec("x1", .codex, name: "Work Codex", billing: "business"), rec("c1", .claude, name: "Claude Team")]
        let cards = AccountCard.rows(
            accounts: accounts, activeId: "x1",
            readings: ["c1": windows(0.34, 0.26), "x1": windows(0.12, 0.08)],
            statuses: [:], isAuthenticated: { _ in true }, maskEmail: true, now: now
        )
        #expect(cards.map(\.id) == ["c1", "x1"])
        #expect(cards[0].isActive == false)
        #expect(cards[1].isActive == true)
        #expect(cards[0].worstPercent == 34)
        #expect(cards[0].bars.map(\.label) == ["5-Hour", "7-Day"])
        #expect(cards[1].bars.map(\.label) == ["5-Hour", "Weekly"])
        #expect(cards[1].plan == "Business")
        #expect(cards[0].state == .none)
    }

    @Test func rows_signedOutAccount_isASignInCard_pendingHidden() {
        let accounts = [rec("c1", .claude), rec("c2", .claude), rec("pending-9", .codex)]
        let cards = AccountCard.rows(accounts: accounts, activeId: "c1", readings: ["c1": windows(0.1, 0.1)],
                                     statuses: [:], isAuthenticated: { $0 != "c2" }, maskEmail: true, now: now)
        #expect(cards.map(\.id) == ["c1", "c2"])
        #expect(cards[1].state == .signedOut)
        #expect(cards[1].bars.isEmpty)
        #expect(AccountCard.eligibleCount(accounts: accounts, isAuthenticated: { $0 != "c2" }) == 2) // signed-out still counts for the overview
    }

    @Test func rows_statePrecedence() {
        let accounts = [rec("c1", .claude), rec("c2", .claude)]
        let throttled = windows(1.0, 0.2, throttled: true)
        var cached = windows(0.5, 0.2); cached.isCached = true
        let cards = AccountCard.rows(accounts: accounts, activeId: "c1", readings: ["c1": throttled, "c2": cached],
                                     statuses: [:], isAuthenticated: { _ in true }, maskEmail: true, now: now)
        #expect(cards[0].state == .throttled)
        if case .cached = cards[1].state {} else { Issue.record("expected cached, got \(cards[1].state)") }
    }

    @Test func rows_noReadingYet_isFetching() {
        let accounts = [rec("c1", .claude), rec("c2", .claude)]
        let cards = AccountCard.rows(accounts: accounts, activeId: "c1", readings: [:],
                                     statuses: [:], isAuthenticated: { _ in true }, maskEmail: true, now: now)
        #expect(cards[0].state == .fetching)
        #expect(cards[0].worstPercent == nil)
        #expect(cards[0].bars.allSatisfy { $0.percent == nil })
    }

    @Test func rows_creditsAndApiKinds() {
        let budget = CodexCreditBudget(usedPercent: 61, used: 61, limit: 100, remaining: 39, unit: "credit",
                                       resetsAt: now.addingTimeInterval(12 * 86_400), reached: false, hasCredits: true, unlimited: false, planType: "business")
        let credits = RateLimitUsage(representativeClaim: "credits", fiveHourUtilization: 0.61, fiveHourReset: nil, fiveHourStatus: "allowed",
                                     sevenDayUtilization: 0.61, sevenDayReset: nil, sevenDayStatus: "allowed", overallStatus: "allowed",
                                     provider: .codex, creditBudget: budget)
        let std = StandardRateLimits.parse(openAIHeaders: [
            "x-ratelimit-limit-requests": "100", "x-ratelimit-remaining-requests": "20",
            "x-ratelimit-limit-tokens": "1000", "x-ratelimit-remaining-tokens": "900",
        ], now: now)!
        let accounts = [rec("x1", .codex, billing: "business"), rec("k1", .codex, billing: "api", apiKey: true)]
        let cards = AccountCard.rows(
            accounts: accounts, activeId: "x1",
            readings: ["x1": AccountReading(windows: credits, apiLimits: nil, fetchedAt: now, isCached: false, source: nil),
                       "k1": AccountReading(windows: nil, apiLimits: std, fetchedAt: now, isCached: false, source: nil)],
            statuses: [.codex: ClaudeSystemStatus(indicator: .operational, description: "", incidentNames: [], statusPageURL: "")],
            isAuthenticated: { _ in true }, maskEmail: true, now: now
        )
        #expect(cards[0].bars.map(\.label) == ["Credits"])
        #expect(cards[0].worstPercent == 61)
        #expect(cards[0].status == .operational)
        #expect(cards[1].bars.map(\.label) == ["Requests", "Tokens"])
        #expect(cards[1].worstPercent == 80)
    }

    @Test func stateText_formats() {
        #expect(AccountCard.stateText(.throttled, now: now) == "Throttled")
        #expect(AccountCard.stateText(.limitReached, now: now) == "Limit reached")
        #expect(AccountCard.stateText(.signedOut, now: now) == "Signed out · click to sign in")
        #expect(AccountCard.stateText(.timeToLimit(2 * 3600), now: now)?.hasPrefix("~") == true)
        #expect(AccountCard.stateText(.cached(now.addingTimeInterval(-180)), now: now)?.hasPrefix("Cached") == true)
        #expect(AccountCard.stateText(.fetching, now: now) == "Fetching…")
        #expect(AccountCard.stateText(.none, now: now) == nil)
    }
}
```

(`ClaudeSystemStatus` memberwise init: check `AIBattery/Models/ClaudeSystemStatus.swift:10-14` for the exact labels; adjust if it has more fields.)

- [ ] **Step 2: Run to verify failure** — `swift test --filter AccountCard` → compile error.

- [ ] **Step 3: Implement**

Add to `Layout` in `AIBattery/Utilities/Spacing.swift`:

```swift
    /// Overview card: bar-row label column, percent column, reset column (pt).
    static let cardBarLabelWidth: CGFloat = 52
    static let cardPercentWidth: CGFloat = 34
    static let cardResetWidth: CGFloat = 46
```

Create `AIBattery/Models/AccountCard.swift`:

```swift
import Foundation

/// Everything an overview card shows, computed once per render from the store, the
/// fan-out readings and the provider statuses. Pure so it is testable headlessly.
struct AccountCard: Identifiable, Equatable {
    enum State: Equatable {
        case throttled, limitReached, signedOut, timeToLimit(TimeInterval), cached(Date), fetching, none
    }

    struct BarRow: Equatable {
        let label: String
        /// 0…100; nil = no reading yet (empty track).
        let percent: Double?
        let reset: Date?
        /// Credits with no spend cap: bar empty, percent "—".
        let uncapped: Bool
    }

    let id: String
    let provider: AIProvider
    let identity: String
    let plan: String?
    let isActive: Bool
    let status: StatusIndicator?
    let worstPercent: Double?
    let bars: [BarRow]
    let state: State

    /// Accounts the overview lists: identity resolved (not pending); signed-out ones
    /// are listed as sign-in cards, so they count. Mirrors the menu bar's eligibility
    /// except for the auth filter.
    static func eligibleCount(accounts: [AccountRecord], isAuthenticated: (String) -> Bool) -> Int {
        accounts.filter { !$0.isPendingIdentity }.count
    }

    static func rows(
        accounts: [AccountRecord],
        activeId: String?,
        readings: [String: AccountReading],
        statuses: [AIProvider: ClaudeSystemStatus],
        isAuthenticated: (String) -> Bool,
        maskEmail: Bool,
        now: Date
    ) -> [AccountCard] {
        AccountStore.displayOrdered(accounts)
            .filter { !$0.isPendingIdentity }
            .map { account in
                let index = AccountStore.providerIndex(of: account, in: accounts)
                let identity = AccountStore.identityLabel(for: account, providerIndex: index, maskEmail: maskEmail)
                let plan = account.provider == .codex ? AccountStore.planLabel(account.billingType) : nil
                let status = statuses[account.provider]?.indicator
                let active = account.id == activeId

                guard isAuthenticated(account.id) else {
                    return AccountCard(id: account.id, provider: account.provider, identity: identity, plan: plan,
                                       isActive: active, status: status, worstPercent: nil, bars: [], state: .signedOut)
                }
                let reading = readings[account.id]
                let bars = barRows(for: account, reading: reading)
                return AccountCard(id: account.id, provider: account.provider, identity: identity, plan: plan,
                                   isActive: active, status: status, worstPercent: reading?.worstPercent,
                                   bars: bars, state: state(for: reading, now: now))
            }
    }

    private static func barRows(for account: AccountRecord, reading: AccountReading?) -> [BarRow] {
        let secondary = account.provider.secondaryWindowLabel // "7-Day" / "Weekly"
        guard let reading else {
            if account.isAPIKeyAccount { return [BarRow(label: "Requests", percent: nil, reset: nil, uncapped: false),
                                                 BarRow(label: "Tokens", percent: nil, reset: nil, uncapped: false)] }
            return [BarRow(label: "5-Hour", percent: nil, reset: nil, uncapped: false),
                    BarRow(label: secondary, percent: nil, reset: nil, uncapped: false)]
        }
        if let std = reading.apiLimits {
            return [BarRow(label: "Requests", percent: std.requestsPercent, reset: std.requestsReset, uncapped: false),
                    BarRow(label: "Tokens", percent: std.tokensPercent, reset: std.tokensReset, uncapped: false)]
        }
        guard let windows = reading.windows else { return [] }
        if let budget = windows.creditBudget {
            return [BarRow(label: "Credits", percent: budget.isUncapped ? nil : budget.usedPercent,
                           reset: budget.resetsAt, uncapped: budget.isUncapped)]
        }
        return [BarRow(label: "5-Hour", percent: windows.fiveHourPercent, reset: windows.fiveHourReset, uncapped: false),
                BarRow(label: secondary, percent: windows.sevenDayPercent, reset: windows.sevenDayReset, uncapped: false)]
    }

    /// First match wins: throttled > limit reached > burn-rate estimate > cached > none.
    private static func state(for reading: AccountReading?, now: Date) -> State {
        guard let reading else { return .fetching }
        let confirmed = !reading.isCached
        if let windows = reading.windows {
            let alarm = UsageBar.AlarmState(percent: reading.worstPercent ?? 0, isThrottled: windows.isThrottled, confirmed: confirmed)
            if alarm.throttled { return .throttled }
            if alarm.limitReached { return .limitReached }
            if confirmed, windows.creditBudget == nil {
                let binding: String = windows.fiveHourPercent >= windows.sevenDayPercent ? RateLimitUsage.fiveHourWindow : RateLimitUsage.sevenDayWindow
                if let eta = windows.estimatedTimeToLimit(for: binding) { return .timeToLimit(eta) }
            }
        } else if let std = reading.apiLimits, std.isRequestsExhausted || std.isTokensExhausted {
            return .limitReached
        }
        if reading.isCached { return .cached(reading.fetchedAt) }
        return .none
    }

    static func stateText(_ state: State, now: Date) -> String? {
        switch state {
        case .throttled: "Throttled"
        case .limitReached: "Limit reached"
        case .signedOut: "Signed out · click to sign in"
        case let .timeToLimit(eta): "~\(DurationFormatter.compact(eta)) to limit"
        case let .cached(at): "Cached \(PopoverFooterView.relativeTime(at))"
        case .fetching: "Fetching…"
        case .none: nil
        }
    }

    var accessibilityLabel: String {
        var parts = ["\(provider.displayName) account \(identity)"]
        if let plan { parts.append(plan) }
        if isActive { parts.append("active") }
        for bar in bars {
            if let percent = bar.percent { parts.append("\(bar.label) \(Int(percent.rounded())) percent") }
            else if bar.uncapped { parts.append("\(bar.label) no cap") }
        }
        if let status { parts.append("\(provider.displayName) status \(status.rawValue)") }
        return parts.joined(separator: ", ")
    }
}
```

Check the exact names of `RateLimitUsage.fiveHourWindow` / `sevenDayWindow` (used by `rateLimitPercentConfirmed(for:)` in `UsagePopoverView`) and `AIProvider.secondaryWindowLabel`; `PopoverFooterView.relativeTime` must be `nonisolated static` (it is used from a `TimelineView` already — if it is `@MainActor`, add a `nonisolated` variant).

- [ ] **Step 4: Run tests + commit**

`swift test --filter "AccountCard"` → PASS. Docs: `spec/DATA_LAYER.md` (new `AccountCard` entry: inputs, state precedence), `spec/CONSTANTS.md` (card widths).

```bash
swiftformat AIBattery/ Tests/ && swiftlint --quiet
git add -A
git commit -m "feat: AccountCard model for the multi-account overview"
```

---

### Task 5: Overview UI — `AccountCardView`, `OverviewContentView`, wiring

**Files:**
- Create: `AIBattery/Views/AccountCardView.swift`, `AIBattery/Views/OverviewContentView.swift`
- Modify: `AIBattery/Views/UsagePopoverView.swift` (replace the Task 3 placeholder; card tap; add link; deferred re-arm)
- Test: none new beyond Task 4 (views are thin); manual walkthrough.

**Interfaces:**
- Produces: `OverviewContentView(cards:canAddClaude:canAddCodex:showSettings:onSelect:onAdd:)`, `AccountCardView(card:now:onSelect:)`.
- Consumes: `AccountCard` (Task 4), `PopoverMode` (Task 3), `viewModel.perAccountReadings / providerStatuses` (Tasks 1–2).

- [ ] **Step 1: Card view**

Create `AIBattery/Views/AccountCardView.swift`:

```swift
import SwiftUI

/// One account on the overview: header line, one gauge row per quota window, and a
/// state line only when there is something to say. The whole card is the hit target.
struct AccountCardView: View {
    let card: AccountCard
    let onSelect: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: onSelect) {
            TimelineView(.periodic(from: .now, by: 10)) { context in
                VStack(alignment: .leading, spacing: Spacing.inner) {
                    header
                    ForEach(Array(card.bars.enumerated()), id: \.offset) { _, bar in
                        AccountCardBarRow(bar: bar, now: context.date)
                    }
                    if let text = AccountCard.stateText(card.state, now: context.date) {
                        Text(text)
                            .font(Typography.tinyLabel)
                            .foregroundStyle(stateColor)
                    }
                }
            }
            .padding(.horizontal, Spacing.sectionHorizontal)
            .padding(.vertical, Spacing.section)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help("\(card.identity) — click to open")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(card.accessibilityLabel)
        .accessibilityValue(AccountCard.stateText(card.state, now: Date()) ?? "")
        .accessibilityHint(card.state == .signedOut ? "Signs in to this account" : "Opens this account")
    }

    private var header: some View {
        HStack(spacing: Spacing.xsmall) {
            ProviderBadge(provider: card.provider)
            Text(card.identity)
                .font(Typography.caption)
                .foregroundStyle(hovered || card.isActive ? .primary : ThemeColors.secondaryLabel)
                .lineLimit(1)
                .truncationMode(.middle)
            if let plan = card.plan {
                Text("· \(plan)")
                    .font(Typography.tinyLabel)
                    .foregroundStyle(ThemeColors.tertiaryLabel)
                    .lineLimit(1)
            }
            Spacer(minLength: Spacing.gap)
            if let status = card.status {
                Circle()
                    .fill(ThemeColors.statusColor(status))
                    .frame(width: Layout.statusDotSize, height: Layout.statusDotSize)
                    .accessibilityHidden(true)
            }
            Text(card.worstPercent.map { "\(Int($0.rounded()))%" } ?? "—")
                .font(Typography.monoValueMedium)
                .foregroundStyle(card.worstPercent.map { ThemeColors.barColor(percent: $0) } ?? ThemeColors.tertiaryLabel)
            if card.isActive {
                Text("▶")
                    .font(Typography.decorativeIcon)
                    .foregroundStyle(ThemeColors.success)
                    .accessibilityHidden(true)
            }
        }
    }

    private var stateColor: Color {
        switch card.state {
        case .throttled, .limitReached: ThemeColors.danger
        case .signedOut, .timeToLimit, .cached: ThemeColors.caution
        case .fetching, .none: ThemeColors.tertiaryLabel
        }
    }
}

/// label · gauge · percent · reset — fixed columns so cards align.
struct AccountCardBarRow: View {
    let bar: AccountCard.BarRow
    let now: Date

    var body: some View {
        HStack(spacing: Spacing.gap) {
            Text(bar.uncapped ? "No cap" : bar.label)
                .font(Typography.tinyLabel)
                .foregroundStyle(ThemeColors.secondaryLabel)
                .frame(width: Layout.cardBarLabelWidth, alignment: .trailing)
            GaugeBar(percent: bar.percent ?? 0, barColor: ThemeColors.barColor(percent: bar.percent ?? 0))
            Text(bar.percent.map { "\(Int($0.rounded()))%" } ?? "—")
                .font(Typography.monoTiny)
                .frame(width: Layout.cardPercentWidth, alignment: .trailing)
            Text(resetText)
                .font(Typography.monoTiny)
                .foregroundStyle(ThemeColors.tertiaryLabel)
                .frame(width: Layout.cardResetWidth, alignment: .trailing)
        }
    }

    private var resetText: String {
        guard let reset = bar.reset, reset > now else { return "—" }
        return DurationFormatter.compact(reset.timeIntervalSince(now))
    }
}
```

If `Layout.statusDotSize` does not exist, reuse the footer's dot size constant (search `PopoverFooterView` for the `Circle().frame(width:` value and name it in `Layout` + `spec/CONSTANTS.md`).

- [ ] **Step 2: Overview content**

Create `AIBattery/Views/OverviewContentView.swift`:

```swift
import SwiftUI

/// The popover's overview face: title + count, one card per account, an add link.
struct OverviewContentView: View {
    let cards: [AccountCard]
    let canAddClaude: Bool
    let canAddCodex: Bool
    @Binding var showSettings: Bool
    let onSelect: (AccountCard) -> Void
    let onAdd: (AIProvider) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Spacing.gap) {
                Text("Accounts")
                    .font(Typography.accountTitle)
                    .accessibilityAddTraits(.isHeader)
                Text("\(cards.count)")
                    .font(Typography.monoCaption)
                    .foregroundStyle(ThemeColors.secondaryLabel)
                Spacer()
                SettingsGearButton(showSettings: $showSettings)
            }
            .padding(.horizontal, Spacing.sectionHorizontal)
            .padding(.vertical, Spacing.section)

            ForEach(cards) { card in
                StyledDivider()
                AccountCardView(card: card, onSelect: { onSelect(card) })
            }

            if canAddClaude || canAddCodex {
                StyledDivider()
                HStack {
                    LinkActionButton(
                        label: "Add account…",
                        icon: "plus.circle",
                        help: canAddClaude ? "Sign in with another Claude or Codex account" : "Sign in with another Codex account",
                        accessibilityLabel: "Add another account"
                    ) { onAdd(canAddClaude ? .claude : .codex) }
                    Spacer()
                }
                .padding(.horizontal, Spacing.sectionHorizontal)
                .padding(.vertical, Spacing.section)
            }
        }
    }
}
```

`SettingsGearButton` — extract the gear from `PopoverHeaderView.gearButton` (L51-71) into its own small view file (`AIBattery/Views/SettingsGearButton.swift`) so both headers share it; `PopoverHeaderView` calls it. (Check `LinkActionButton`'s actual initializer labels in `Views/Components/LinkActionButton.swift` and match them.)

- [ ] **Step 3: Wire into `UsagePopoverView`**

Replace the Task 3 placeholder with:

```swift
    private var overviewContent: some View {
        let store = OAuthManager.shared.accountStore
        let cards = AccountCard.rows(
            accounts: accountStore.accounts,
            activeId: accountStore.activeAccountId,
            readings: viewModel.perAccountReadings,
            statuses: viewModel.providerStatuses,
            isAuthenticated: { OAuthManager.shared.isAuthenticated(accountId: $0) },
            maskEmail: !showFullAccountIdentity,
            now: Date()
        )
        return VStack(alignment: .leading, spacing: 0) {
            if showSettings {
                HStack { Spacer(); SettingsGearButton(showSettings: $showSettings) }
                    .padding(.horizontal, Spacing.sectionHorizontal).padding(.vertical, Spacing.section)
                SettingsRow(viewModel: viewModel, accountStore: accountStore, onAddAccount: { addingProvider = $0 })
                    .transition(.opacity)
            } else {
                OverviewContentView(
                    cards: cards,
                    canAddClaude: store.canAddAccount(provider: .claude),
                    canAddCodex: store.canAddAccount(provider: .codex),
                    showSettings: $showSettings,
                    onSelect: { card in select(card) },
                    onAdd: { addingProvider = $0 }
                )
                .transition(.opacity)
            }
            StyledDivider()
            footer   // factor the existing PopoverFooterView(...) call out of mainContent into `private var footer`
        }
    }

    private func select(_ card: AccountCard) {
        if card.state == .signedOut {
            addingProvider = card.provider
            return
        }
        withAnimation(MotionConstants.standard) {
            if card.id != accountStore.activeAccountId {
                viewModel.switchAccount(to: card.id)
            }
            mode = .detail
        }
        DispatchQueue.main.async { deferredRender.appeared() }
    }
```

`showFullAccountIdentity` is `@AppStorage(UserDefaultsKeys.showFullAccountIdentity) private var showFullAccountIdentity = false` (add it next to the other `@AppStorage`s). Replace `eligibleAccountCount` (Task 3) with `AccountCard.eligibleCount(accounts: accountStore.accounts, isAuthenticated: { OAuthManager.shared.isAuthenticated(accountId: $0) })`.

- [ ] **Step 4: Build, walk through, commit**

`swift build` clean; `swift test` → PASS. Local: `./scripts/build-app.sh && open .build/AIBattery.app`; open the popover (click the status item via System Events `click menu bar item 1 of menu bar 2`): overview with one card per account, correct bars per kind, active `▶`; click a card (AX `click button N of group 1 of window 1`) → detail for that account; the panel height follows at each step. Capture the overview with `screencapture -R` for the PR.
Docs: `spec/UI_SPEC.md` new "❶ Overview mode" section with the spec's mockup + the card anatomy, hierarchy tree updated; README feature bullet "Multi-account overview".

```bash
swiftformat AIBattery/ Tests/ && swiftlint --quiet
git add -A
git commit -m "feat: multi-account overview cards in the popover"
```

---

### Task 6: Back chevron in the detail header + Escape routing

**Files:**
- Modify: `AIBattery/Views/PopoverHeaderView.swift` (`showsBack`, `onBack`)
- Modify: `AIBattery/Views/StatusBarManager.swift` (`var escapeHandler: (() -> Bool)?`), `AIBattery/Views/StatusBarManager+Panel.swift` (`PopoverPanel.keyDown`, `PopoverContentView`)
- Modify: `AIBattery/Views/UsagePopoverView.swift` (`handleKeyPress` for overview digits; back; escape handler registration)
- Test: `Tests/AIBatteryCoreTests/Views/PopoverHeaderBackTests.swift` (new)

**Interfaces:**
- Produces: `PopoverHeaderView.showsBack(eligibleAccountCount:) -> Bool` (pure); `PopoverEscapeRouting.consume(mode:showSettings:showsBack:) -> PopoverEscapeAction` with `enum PopoverEscapeAction { case backToOverview, close }`; `StatusBarManager.escapeHandler`.

- [ ] **Step 1: Failing tests**

```swift
import Testing
@testable import AIBatteryCore

@Suite("PopoverHeader back + escape")
struct PopoverHeaderBackTests {
    @Test func showsBack_onlyWithTwoOrMoreAccounts() {
        #expect(PopoverHeaderView.showsBack(eligibleAccountCount: 1) == false)
        #expect(PopoverHeaderView.showsBack(eligibleAccountCount: 2) == true)
    }

    @Test func escape_goesBackFromDetailWithoutSettings_elseCloses() {
        #expect(PopoverEscapeRouting.consume(mode: .detail, showSettings: false, showsBack: true) == .backToOverview)
        #expect(PopoverEscapeRouting.consume(mode: .detail, showSettings: true, showsBack: true) == .close)
        #expect(PopoverEscapeRouting.consume(mode: .detail, showSettings: false, showsBack: false) == .close)
        #expect(PopoverEscapeRouting.consume(mode: .overview, showSettings: false, showsBack: true) == .close)
    }
}
```

- [ ] **Step 2: Run to verify failure** — `swift test --filter "PopoverHeader back"` → compile error.

- [ ] **Step 3: Implement**

`PopoverHeaderView`: add `var showsBack: Bool = false`, `var onBack: () -> Void = {}`, and

```swift
    nonisolated static func showsBack(eligibleAccountCount: Int) -> Bool { eligibleAccountCount >= 2 }
```

In the header `HStack`, before `AccountChipView`:

```swift
                if showsBack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(Typography.headerGear)
                            .frame(width: Layout.accountChipHeight, height: Layout.accountChipHeight)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(backHovered ? .primary : .secondary)
                    .onHover { backHovered = $0 }
                    .help("All accounts")
                    .accessibilityLabel("Back to all accounts")
                }
```

(`@State private var backHovered = false`.) Add to `AIBattery/Models/PopoverMode.swift`:

```swift
enum PopoverEscapeAction: Equatable { case backToOverview, close }

enum PopoverEscapeRouting {
    /// Escape in a detail view that has somewhere to go back to returns to the overview;
    /// everywhere else (overview, Settings open, single account) it closes the panel.
    static func consume(mode: PopoverMode, showSettings: Bool, showsBack: Bool) -> PopoverEscapeAction {
        (mode == .detail && !showSettings && showsBack) ? .backToOverview : .close
    }
}
```

`StatusBarManager`: `var escapeHandler: (() -> Bool)?` (returns true when consumed). `PopoverPanel`: `var escapeHandler: (() -> Bool)?`; in `keyDown`, `if event.keyCode == 53 { if escapeHandler?() == true { return }; orderOut(nil) }`. The `escapeMonitor` in `StatusBarManager` (local monitor for `.keyDown`) must consult the same closure before `orderOut`. `UsagePopoverView` registers it through a notification-free seam: `PopoverContentView` takes `escapeHandlerSink: ((@escaping () -> Bool) -> Void)` from `StatusBarManager.setup` and `UsagePopoverView` calls it in `.onAppear` with:

```swift
            { [self] in
                switch PopoverEscapeRouting.consume(mode: mode, showSettings: showSettings, showsBack: PopoverHeaderView.showsBack(eligibleAccountCount: eligibleAccountCount)) {
                case .backToOverview: withAnimation(MotionConstants.standard) { mode = .overview }; return true
                case .close: return false
                }
            }
```

(Because `UsagePopoverView` is a struct, capture the state through a small `@StateObject` box `PopoverModeBox: ObservableObject { @Published var mode }` **or** keep `mode` in the view and register the closure on every `onChange(of: mode)` / `onChange(of: showSettings)`; the box is simpler — do that and migrate `mode` from `@State` to the box.)

`handleKeyPress` in `.overview`: `"1"…"6"` → select card at index n-1 (via the same `select(_:)`); `"r"` → `viewModel.scheduleFanOut()`; others ignored. Extend `PopoverPanel.keyDown` forwarding to include `"4"`, `"5"`, `"6"`.

Pass `showsBack:` / `onBack:` from `mainContent`: `showsBack: PopoverHeaderView.showsBack(eligibleAccountCount: eligibleAccountCount)`, `onBack: { withAnimation(MotionConstants.standard) { mode = .overview } }`.

- [ ] **Step 4: Run tests, walkthrough, commit**

`swift test` → PASS. Local: detail header shows the chevron with 2+ accounts; AX-click it → overview; Kyle verifies Escape manually (no synthetic keystrokes).
Docs: `spec/UI_SPEC.md` ❶ header (back chevron), Keyboard section (Escape routing, overview digits); `spec/DATA_LAYER.md` (`PopoverEscapeRouting`); `spec/ARCHITECTURE.md` panel keyDown paragraph.

```bash
swiftformat AIBattery/ Tests/ && swiftlint --quiet
git add -A
git commit -m "feat: back chevron and Escape routing between overview and detail"
```

---

### Task 7: Settings copy and poll-cost hint

**Files:**
- Modify: `AIBattery/Views/Settings/DisplaySettingsSection.swift` (toggle hint), `AIBattery/Views/Settings/RefreshSettingsSection.swift:43-49` (`pollCostHint(provider:apiKeyAccount:fanOutAccounts:)`)
- Test: the suite covering `pollCostHint` (search `Tests/` for `pollCostHint`)

- [ ] **Step 1: Failing test**

```swift
    @Test func pollCostHint_appendsFanOutMultiplier() {
        #expect(RefreshSettingsSection.pollCostHint(provider: .claude, apiKeyAccount: false, fanOutAccounts: 3).hasSuffix(" · ×3 accounts"))
        #expect(RefreshSettingsSection.pollCostHint(provider: .claude, apiKeyAccount: false, fanOutAccounts: 1) == RefreshSettingsSection.pollCostHint(provider: .claude, apiKeyAccount: false))
    }
```

- [ ] **Step 2: Run to verify failure** — compile error (`fanOutAccounts:`).

- [ ] **Step 3: Implement**

```swift
    nonisolated static func pollCostHint(provider: AIProvider, apiKeyAccount: Bool, fanOutAccounts: Int = 1) -> String {
        let base: String = switch (provider, apiKeyAccount) {
        case (.codex, true): "~16 output tokens/poll, billed at API rates · data kept until next update"
        case (.codex, false): "Reads OpenAI's usage endpoint · no tokens spent · data kept until next update"
        default: "~3 tokens/poll · API data kept until next update"
        }
        return fanOutAccounts >= 2 ? "\(base) · ×\(fanOutAccounts) accounts" : base
    }
```

Call site passes `fanOutAccounts: viewModel.perAccountReadings.count`. In `DisplaySettingsSection`, the "All accounts in menu bar" toggle gets `.help("The popover shows all accounts whenever you have more than one; this adds them to the menu bar too.")`.

- [ ] **Step 4: Run tests + commit**

`swift test --filter "RefreshSettings|DisplaySettings"` → PASS. Docs: `spec/UI_SPEC.md` Settings (hint texts). README Views row.

```bash
swiftformat AIBattery/ Tests/ && swiftlint --quiet
git add -A
git commit -m "feat: settings copy for the overview and per-account poll cost"
```

---

### Task 8: Provider-relevance plan bookkeeping — DONE

Already applied on the release branch (the provider-relevance spec marks §6 as implemented here and §9 as superseded; its plan's Task 7 and Task 10 are pointers). Nothing to do.

---

### Task 9: Spec sync for this phase

**Files:** `spec/ARCHITECTURE.md` (data-flow paragraph: mode; project tree: `AccountReading.swift`, `PopoverMode.swift`, `AccountCard.swift`, `AccountCardView.swift`, `OverviewContentView.swift`, `SettingsGearButton.swift`), `spec/DATA_LAYER.md`, `spec/UI_SPEC.md` (❶ Overview mode section + mockup, keyboard), `spec/CONSTANTS.md` (card widths, status dot), `README.md` (feature bullet "Multi-account overview" + `screenshots/overview.png`), `CLAUDE.md` Key Design Decisions bullet (*the fan-out is the overview's data source and runs for ≥ 2 accounts regardless of the menu-bar toggle; cards never show per-provider local analytics*).

- [ ] **Step 1:** Re-read the four spec files against the code; fix drift.
- [ ] **Step 2:** Full verification: `swiftformat AIBattery/ AIBatteryApp/ Tests/ && swiftlint`; `swift test`; `./scripts/build-app.sh && open .build/AIBattery.app`; walk open → overview → each card → detail → back → Settings from both modes → sign out one account → sign-in card → sign back in. Capture `screenshots/overview.png` (2× `screencapture -R`, rounded corners per the screenshot recipe). Accessibility clicks only.
- [ ] **Step 3:** Commit with message `docs: sync specs and README for the multi-account overview`. Version, changelog heading, test counts and the PR are owned by the release plan's wrap-up.

---

## Self-review against the spec

- §1 modes → Task 3 (+ Task 5 select/back, Task 6 escape). §2.1 gate → Task 1. §2.2 readings → Task 1. §2.3 statuses → Task 2. §2.4 signed-out cards → Task 4 (`eligibleCount`, `.signedOut`) + Task 5 (`select` opens the add overlay). §3 layout → Tasks 4–5 (widths in `Layout`, header, cards, add link, footer reuse). §4 detail changes → Task 6. §5 flow → Tasks 3, 5, 6. §6 a11y → Task 4 (`accessibilityLabel`) + Task 5 (element config). §7 folded item 6 → Task 1 (bookkeeping already applied, Task 8 is a pointer). §8 settings → Task 7. §9 errors → Task 1 (`carriedForward`), Task 4 (`.fetching`, nil-tolerant rows). §10 testing → each task. §11: R1 resolved (per-instance backoff, Task 2 comment); R2 → Task 6 (`escapeHandler` closure; fallback stated in spec); R3 → checked in Task 5's walkthrough with six accounts if available, else computed from `Layout` values and noted in the PR.
- Names consistent across tasks: `AccountReading`, `FanOutGate.enabled(menuBarToggle:eligibleAccountCount:)`, `perAccountReadings` / `perAccountRateLimits` / `perAccountAPILimits`, `providerStatuses`, `PopoverMode.initial/next`, `AccountCard.rows/eligibleCount/stateText`, `AccountCardView`, `AccountCardBarRow`, `OverviewContentView`, `SettingsGearButton`, `PopoverHeaderView.showsBack(eligibleAccountCount:)`, `PopoverEscapeRouting.consume`, `pollCostHint(provider:apiKeyAccount:fanOutAccounts:)`.
- Implementer must confirm on the spot (named in steps): `APIFetchResult` initializer order, `ClaudeSystemStatus` init labels, `RateLimitUsage.fiveHourWindow/sevenDayWindow` names, `LinkActionButton` init labels, status-dot size constant, `PopoverFooterView.relativeTime` isolation, mock types in `MultiAccountFanOutTests`.
