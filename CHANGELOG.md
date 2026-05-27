# Changelog

## [2.4.1] — 2026-05-27

Bug fix: the app no longer reports **"Throttled"** when you are simply at 100% of
a rate-limit window but not actually being throttled.

### Fixed
- **100% utilization is no longer treated as "throttled".** A window is shown as
  throttled (red "Throttled" label, ⚠️ icon, broken menu-bar star) only on a
  genuine throttle signal — an explicit API `"throttled"` status or a real HTTP
  429 (via `markedThrottled`, gated at 95%). Hitting 100% of your allotment now
  shows an honest **"Limit reached" / at-capacity** state with a solid red
  (non-broken) menu-bar star. Three independent code paths were conflating the
  two: `RateLimitUsage.parse(clientData:)` synthesized a throttled status at
  utilization ≥ 1.0; `MenuBarMultiAccountText` drove the broken star from
  `percent >= 100`; and `ThrottleTracker` recorded false entries in the 30-day
  throttle-event history. All three now key off the genuine throttle signal only.

### Added
- **Structured throttle-state logging.** One `AppLogger.network` line is emitted
  on each throttle on/off transition (binding window, reset timestamp, source),
  so a stuck or false throttle state is diagnosable after the fact.

## [2.4.0] — 2026-05-26

Internal hygiene release. No user-visible behavior change beyond a Sparkle
patch bump; the work was concentrated on making the codebase ready for the
Swift 6 language-mode flip and on splitting two files that had grown past
the project's 800-line cap.

### Tooling
- **Swift 6 strict-concurrency diagnostics enabled** at warning level.
  `swift-tools-version` bumped 5.9 → 6.0; the `StrictConcurrency` upcoming
  feature is on across all three SPM targets; production code now compiles
  with **zero warnings, zero errors** under strict-concurrency. The
  `.swiftLanguageMode(.v6)` flip is deferred — it requires `isolated deinit`
  on the three `@MainActor` classes that own `Timer` / observer state
  (`UsageViewModel`, `FileWatcher`, `StatusBarManager`), and adopting
  `isolated deinit` deadlocked the Swift Testing parallel runner on this
  codebase in empirical testing. The `nonisolated(unsafe)` annotations
  added on the affected stored properties document the locations that the
  follow-up will revisit. See PR #170 for the deadlock evidence.
- **Sparkle 2.9.0 → 2.9.2** — patch-level update within the existing
  `"2.6.0"..<"3.0.0"` declared range. Picks up upstream fixes between
  Mar 2026 and 17 May 2026.

### Refactored
- **`UsageViewModel.swift` 761 → 457 lines** via three same-type extension
  files (`+Statics`, `+Lifecycle`, `+FanOut`). No behavior change; each
  extracted method group has a single inline narrative comment explaining
  what's in it and why it moved. `spec/ARCHITECTURE.md` updated to reflect
  the new layout.
- **`RateLimitFetcher.swift` 743 → 494 lines** via three same-type
  extension files (`+UsageEndpoint`, `+ClientData`, `+Persistence`).
  The pure `interpret*` functions pinned by v2.3.2's 15 contract tests
  move with the rest of their endpoint logic; tests still address them
  via the canonical class namespace, so no test rewrites.
  `spec/ARCHITECTURE.md` and `spec/DATA_LAYER.md` updated.

### Fixed
- **Midnight-rollover test flake in `SessionInfoFormatter.formatSessionTime`.**
  The formatter called `Date()` and `calendar.isDateInToday(date)` internally,
  so `formatSessionTime_todayShowsTime` (which passed a 2h-earlier session)
  flaked between 00:00 and ~02:00 local: "2 hours ago" crossed the day
  boundary, the formatter (correctly) returned `"Yesterday HH:MM"`, the test
  asserted `"Today"` → fail. Caught running the v2.4.0 verification suite at
  00:07 local. Fix injects `now: Date = Date()` (same pattern
  `UsageAggregator.aggregate(now:)` adopted in v2.3.2); the production path
  is unchanged (default param). The test now pins `now` to noon-on-today,
  and a symmetric `formatSessionTime_yesterdayShowsYesterday` test pins
  the other branch.

### Tests
- 1000 → **1002 tests** across 67 files. The new tests are the
  yesterday-symmetric formatter coverage above; one absolute count is also
  the existing midnight-rollover test now running deterministically.

## [2.3.2] — 2026-05-25

Bug-fix release. Closes the "menu bar stayed depleted past the actual reset"
symptom, ships the contract-test architecture that would have caught it, and
fixes the insights-trend overflow that surfaced "+47999% vs yesterday" after a
quiet weekend. Seven commits, four user-visible fixes, no behavioral changes
beyond the fixes themselves.

### Fixed
- **Insights trend showed nonsense percentages like "+47999% vs yesterday" after a quiet day.**
  `ActivityTrendComputation.percentChangeInfo` divided current by previous with
  only a `previous > 0` guard, so a weekend with stray tokens (e.g. 100 from a
  background hook) followed by a normal Monday rendered as a five-digit spike
  that overflowed the trend row layout and misled rather than informed. Added
  a `meaningfulPreviousThreshold` (1000 tokens — below this the trend is
  suppressed entirely; the user reads the absolute number from the chart) and
  a `maxDisplayedPercent` cap of 999% (above this the label shows `>999%`
  rather than the raw multi-digit figure). Applies to `vs yesterday`,
  `vs last week`, and `vs last month`. 3 new tests pin the threshold,
  cap, and below-threshold suppression behaviors.
- **7-day rate-limit count was biased high by up to 24h of stale tokens.**
  `UsageAggregator.sevenDaysAgo` used calendar-day arithmetic
  (`Calendar.date(byAdding: .day, value: -7, to: today)`) for both the per-model
  weekly UI breakdown *and* the 5h/7d local rate-limit token count. Anthropic's
  7-day quota window is rolling 7×86400, not calendar-day. Split into two
  cutoffs: a new `sevenDayRateLimitCutoff` (rolling 7×86400) drives
  `sevenDayTokens`; calendar-day `sevenDaysAgo` continues to drive
  `weekTokenMap` (where calendar-day semantics are intentional for UI). The
  inflated 7d count had been feeding directly into `LocalUsageEstimate.calibrate`'s
  derived-limit math, where a 24h bias produces a too-low calibrated limit that
  later reads ≥100% even when the API would report well under.
- **OAuth usage endpoint silently dropped 429 responses, never surfacing the throttle.**
  `RateLimitFetcher.fetchUsageEndpoint`'s status-code guard rejected any non-2xx
  response *before* the `markedThrottled`-if-429 normalization could run, making
  that branch unreachable. When the dedicated `/api/oauth/usage` endpoint returned
  429 with quota data in the body, the fetcher returned nil and fell through to
  the Messages API probe instead of using the throttle signal already in hand.
  Brought the guard in line with the sibling `fetchClaudeCodeClientData` path
  (which always allowed 429 through), so the two endpoint handlers now agree on
  status-code semantics. Caught by adversarial review of today's depletion bug
  fix — same code area, different latent bug.

### Refactored
- **Extracted pure response interpreters for both OAuth endpoints.**
  `RateLimitFetcher.interpretUsageEndpoint(statusCode:data:headers:cachedProfile:)`
  and `RateLimitFetcher.interpretClaudeCodeClientData(...)` are now `nonisolated static`
  pure functions. The async `fetchUsageEndpoint` / `fetchClaudeCodeClientData`
  wrappers just do the HTTP call, run diagnostic logging, and delegate. The
  status-code / payload / 429-normalization contract is now testable without
  mocking URLSession. 14 new contract tests pin both interpreters: 2xx success,
  429 with quota-throttle (markedThrottled fires), 429 with low utilization (must
  NOT mark), 401/403/500, malformed body, no rate_limits field, profile cache
  fallback, header-vs-body precedence on client_data.
- **Injected `now: Date = Date()` into `UsageAggregator.aggregate(...)`.**
  Production callers unchanged (default parameter); tests now pin
  window-boundary behavior with deterministic timestamps.

- **Menu bar stayed depleted ("100%" + broken star) past the actual 5h/7d window reset.**
  Anthropic returns unified rate-limit headers on only ~10% of polls, so the snapshot
  falls back to the previously-cached `RateLimitUsage` for up to 24h (`rateLimitStaleTTL`).
  That stale value still reported `fiveHourPercent` (or `sevenDayPercent`) `= 100` and
  `overallStatus = "throttled"` after its `fiveHourReset` / `sevenDayReset` had passed,
  because `withClearedExpiredWindows` only ran inside `RateLimitFetcher.restorePersistedRateLimits`
  at app launch — not on the runtime fallback. Both `UsageViewModel.effectiveRateLimits`
  and `RateLimitFetcher.cachedOrEmpty` now normalize their returned `RateLimitUsage`
  through `withClearedExpiredWindows(now:)`, so a window that has already reset
  immediately drops to `0` / `"allowed"` and the menu bar clears the broken-star
  state on the next display tick (no need to wait for a fresh-headers fetch).
- Regression test in `UsageViewModelTests` pins the stale + expired-binding-window
  scenario; companion test in `RateLimitFetcherTests` pins the cache-hit path on
  cold start / wake from sleep.

## [2.3.1] — 2026-05-17

Popover polish sweep. Two visible bug-fixes, eight design-token /
component refactors, ten accessibility wins, and the spec/code
realignment that goes with it. No data-flow or auth changes.

### Fixed
- **Header alignment** — the account picker no longer sits visibly below "AI Battery". The header HStack used `.firstTextBaseline`, which baseline-aligned the larger title (`sectionHeader`) with the smaller picker (`caption`) and pushed the picker's visual center down. Switched to `.center`. (`PopoverHeaderView.swift`)
- **Settings toggle no longer "jumps down"** — clicking the gear used to combine an `.opacity + .move(edge: .top)` transition with an NSPanel that re-anchors to the menu bar while resizing. The slide and the panel resize fought each other and the whole popover read as jumping. Switched `MotionConstants.expandTransition` (and the one direct call site) to plain `.opacity`. Same fix root-cause-applied to TokenHealthSection's session swap, which was using asymmetric `.move(edge: .trailing/.leading)`.
- **Colorblind-safe status dot** — the footer status dot encoded operational/degraded/partial-outage/major-outage/maintenance with color only on a 6pt circle. Non-operational dots now overlay a small white SF Symbol so the severity is distinguishable without color (`exclamationmark`, `xmark`, `wrench.adjustable`). Operational and unknown stay plain dots.
- **Update-banner dismiss icon size** — the xmark.circle.fill used `Typography.heroTitle`, making it optically larger than the sibling install-update and version icons. Dropped to `Typography.bodyLabel` to match the row.

### Accessibility
- VoiceOver labels added to icon-only buttons that previously read as a generic "button": local-estimate info button, Sparkle Download, Sparkle-error dismiss, update-check button, release-notes link, Install Update, project sort/clear-search, AuthView cancel buttons, TokenHealthSection prev/next session arrows, SettingsRow remove-account `x`, banner dismiss.
- Hints added to every label that was missing one — VoiceOver now announces what activating the control will do, not just what the control is named.
- LocalEstimateSection percent text now anchors with the metric name ("5-Hour usage 73 percent" instead of bare "73 percent").
- InsightsTrendCostSection per-model rows now combine into a single VoiceOver element with active-state context; decorative throttle glyph hidden from a11y; active-model "▶" gets an explicit "Active model" label; copyText includes "active" suffix.

### Design system
- **Extracted `GaugeRow`** — `UsageBar` (5h/7d) and `StandardLimitBar` (per-minute fallback) shared the same VStack[Header HStack + GaugeBar + TimelineView footer] shape with subtle drift. Both now build on the same shell via `headerLeading` / `headerTrailing` / `footer` ViewBuilders.
- **Extracted `LinkActionButton`** — four ad-hoc "small text-styled link button" implementations (Add Account / Test / Download / Install Update) collapsed into one component with `Size.standard` (settings) and `Size.compact` (in-banner) variants. Standardizes color, font, icon-to-label spacing, and a11y-label fallback.
- **`FooterLink` carries Logout and Quit** — both buttons used to re-implement FooterLink's hover-underline pattern inline. `FooterLink` now accepts `showsExternalArrow` (false for inline actions) and `foregroundOverride` (state-driven coloring). Drops ~30 lines of duplicate styling and picks up `@FocusState` for free.
- **`FooterLink` hover and focus unified** — previously, mouse users saw an underline-only signal and keyboard users saw a color-only signal. Both now produce both cues.
- **New `ThemeColors` tokens** — `inactiveStroke` (= `.secondary`) for unselected/inactive outlines; `shadowColor` (= `.black`) for elevated-control shadows. Replaces raw color references in MetricToggleView, TutorialOverlay.
- **`MotionConstants.expandTransition` documented** — token doc-comment now explains why `.move(edge:)` is banned inside the popover (NSPanel resize race), so the slide isn't re-added later.
- **MarqueeText tokenized** — pause/hold/restart/fade-settle durations, scroll speed, and animation curve all moved out of inline literals into `MotionConstants.marquee*` tokens with a `marqueeScroll(travelPoints:)` builder. Default font and color flipped from raw `.caption2` / `.secondary` to `Typography.tinyLabel` / `ThemeColors.secondaryLabel`.
- **`CollapsibleSectionHeader` focus ring via token** — `Color.accentColor` → `ThemeColors.action`.
- **`AuthView` tint via token** — `.tint(.accentColor)` → `.tint(ThemeColors.action)` on both `.borderedProminent` CTAs.

### Spec
- `spec/ARCHITECTURE.md`, `spec/UI_SPEC.md`, `spec/CONSTANTS.md` updated to match the new component list, ThemeColors tokens, MotionConstants tokens, header alignment, session-swap transition, FooterLink contract, and status-dot SF Symbol overlay.

## [2.3.0] — 2026-05-16

### Tooling
- **SwiftLint + SwiftFormat enforced in CI** — added `.swiftlint.yml`, `.swiftformat`, and a new `lint.yml` workflow that runs on every PR. SwiftFormat enforces a uniform style baseline (107 files normalized in this commit). SwiftLint runs conservatively: 0 errors, force-unwrap as advisory warning, plus a custom rule banning `Timer.publish` (regression class documented in `MEMORY.md` and `spec/ARCHITECTURE.md`) to prevent the freeze it caused in v1.9.4.
- **Removed redundant `@available(macOS 13.0, *)`** from `LaunchAtLoginManager.swift` (3 sites). The package's deployment floor is already `macOS 13`, so these attributes were no-ops.

### Refactored
- **Extracted `RetryPolicy`** — a pure, `Sendable`, `nonisolated` struct that consolidates four hand-rolled exponential-backoff implementations (`OAuthManager`, `StatusChecker`, `FileWatcher`, `RateLimitFetcher.parseRetryAfter`) into a single tested utility with presets (`.oauth`, `.statusCheck`, `.fileWatch`, `.rateLimit`). Includes injectable RNG for deterministic jitter testing. 20 new tests, including parity tests pinning the historical formulas to prevent semantic drift. Behaviour is bit-identical to the prior inline math; only the implementation moved.
- **`StatusChecker` HTTP path moved off `@MainActor`** — `fetchAndParse(url:timeout:)` is now `nonisolated static` and returns a `Sendable FetchOutcome`. `parseStatus` and `jsonDecoder` follow. `fetchStatus()` keeps MainActor ownership of cache/backoff state with no `await` between read and write. 2 new concurrency tests pin the structural guarantee (detached-task callability + MainActor-non-blocking).
- **`RateLimitFetcher` actor isolation hygiene** — pure header helpers (`containsStandardRateLimitHeaders`) now explicitly `nonisolated`. Inline doc on `fetch(accessToken:accountId:)` clarifies the suspension model: every `await SecureNetworking.data(for:)` already releases MainActor for the duration of the network call (Swift suspension semantics), so a 30s URLSession timeout cannot freeze the UI. 4 new concurrency tests assert the `nonisolated` promise holds at call sites in detached tasks. Structural extraction of the per-model probe loop is deferred to Phase 4 (where `RateLimitProbeSequence` will be lifted out as part of the file split).
- **`OAuthManager.postToken` moved off `@MainActor`** — token-endpoint HTTP (`exchangeCode` and `refreshAccessToken` callers) now runs in a `nonisolated static` worker. `tokenURL` is `nonisolated private static let`. `TokenResult` and `AuthError` now explicitly conform to `Sendable` so the result can cross the actor boundary. MainActor caller still owns all side effects (Keychain writes, account creation, `isAuthenticated` flips). Documented the concurrent-refresh serialization invariant on `getAccessToken(for:)` — concurrent callers for the same account piggyback on a single in-flight `Task<String?, Never>` via `refreshTasks[accountId]`, with a generation counter to avoid stale-task cleanup. 6 new tests pin Sendable conformance, the transient-vs-auth `isTransient` classifier (the contract that decides "log out vs retry on flaky network"), and a sanity check that 10 concurrent `getAccessToken(for:)` calls for an unknown account never deadlock.
- **Extracted `OAuthTokenStorage` from `OAuthManager`** — the Keychain + UserDefaults persistence layer is now isolated in its own type. `OAuthManager` keeps the auth-flow orchestration; the storage type owns the layout decisions (only refresh tokens in Keychain, expiry timestamps in UserDefaults, access tokens never persisted). One thin typealias keeps the existing OAuthManager body reading naturally.

### Partially completed
- **Phase 4 file splits** — only `OAuthTokenStorage` shipped this milestone. The other 4 planned splits (`UsagePollingCoordinator`, `StatusBarAnimationController`, `RateLimitProbeSequence`, `UsageAggregator+Periods`) require restructuring private members across file boundaries — material refactors that need their own scoped milestones to do carefully. The structural extraction of `RateLimitFetcher.tryFetch` (deferred from Phase 3b) is therefore still outstanding.

### Build hygiene (extended verification)
- **0 build warnings (down from 144)** after a clean release build flushed out Swift 6 strict-concurrency warnings. Five fixes:
  - `OAuthManager.maxRetries` is now `nonisolated private static let` — Phase 3c regression where `Self.maxRetries` was referenced from the `nonisolated postToken` worker but still MainActor-isolated. Would have been a hard error in Swift 6.
  - Removed dead `activeIsExhausted` local from `StatusBarManager.updateButton` (orphaned by the v2.2.1 menu-bar resolver refactor).
  - Wrapped `deactivationObserver`'s closure body in `MainActor.assumeIsolated`, mirroring the resize closure right above it.
  - Added `@preconcurrency import Dispatch` to `StatusBarManager` (compiler-suggested fix for the `DispatchWorkItem` capture pattern).
  - Fixed flaky `observedModels_defaultsToEmpty` test — was breaking under test parallelism because `restoreWorkingModels`'s prefix scan would pick up other tests' UserDefaults keys before their `defer` cleanup ran. Now clears the `aibattery_observedModels_*` prefix explicitly.

### Notes
- Pure tooling/formatting/refactor change. No behaviour change. All 922 tests pass unchanged.

## [2.2.1] — 2026-05-11

### Fixed
- **Menu bar rendered "— | —" instead of percentages with multi-account display on** — v2.2.0's polish pass gated the multi-account branch on the count of *authenticated* accounts (so a slot whose fan-out hadn't landed would show as `—`), but the gate fired before the initial fan-out completed, leaving both slots em-dashed indefinitely on first launch with the toggle on (and persistently when the fan-out failed entirely on transient network/auth issues). Reverted the gate to `perAccountRateLimits.count >= 2` (count of accounts with fetched data). The active account's percent now renders immediately from the snapshot via the single-account path, and the menu bar upgrades to the multi-account strip the moment the fan-out lands. Trade-off acknowledged: in the brief transient window where account A has data but account B's fan-out is still pending, the user sees A's single-account display rather than `A% | —` — strictly better than the broken `— | —` v2.2.0 shipped with.

### Changed
- **Extracted the menu-bar text/percent/countdown decision into `MenuBarMultiAccountText.resolveDisplay(...)`** — a pure, fully-testable function. The v2.2.0 regression was a wiring bug at the `StatusBarManager.updateButton` call site that no unit test could reach. By collapsing the wiring (gate, builder, countdown composition, single-account fallback) into one deterministic function, every reachable display state is now covered by end-to-end tests against the resolver itself — empty `perAccount`, partial fan-out, healthy multi, throttled multi, single-account throttled, worst-percent flooring, single-account-only edge case — making the v2.2.0 mistake unrepresentable.
- **`MenuBarMultiAccountText.shouldRender(toggleOn:accountCount:)` renamed to `shouldRender(toggleOn:fetchedAccountCount:)`** so the parameter name names the contract.

### Tests
- 12 new tests: 10 end-to-end resolver scenarios + 2 explicit v2.2.0 regression pins. Total: **922 tests across 62 suites** (up from 910).

## [2.2.0] — 2026-05-10

### Added
- **"All accounts in menu bar" Display setting** — when enabled with ≥2 connected OAuth accounts, the menu bar text becomes a per-account percent strip (e.g. `42% | 23%`) instead of a single percentage. Off by default; preserves single-account behaviour bit-identically. Star color, breath, broken-star state, and countdown reset are driven by the **worst** account so one icon still communicates the most actionable signal. Per-account fan-out is `O(N)` requests per refresh: the active account's just-fetched data is reused as a seed instead of triggering a duplicate network call. Toggle flips propagate within ~150 ms via a `UserDefaults.didChangeNotification` observer (no need to wait for the next refresh tick). New `MenuBarMultiAccountText` builder is pure (no AppKit) and unit-tested for ordering, missing slots (em-dash fallback), worst-percent selection, throttle detection, metric-mode handling, and rendering gates.

### Fixed
- **Doubled divider above settings footer** — when the settings panel was open, an extra `StyledDivider` rendered just above the always-present footer divider, creating a visible double-line. Removed the redundant divider; the footer's own divider already provides separation.

### Changed
- **Display settings layout** — the "Colorblind" toggle and the new "All accounts in menu bar" toggle now stack vertically under a single `Display` label so the second toggle aligns flush with the first.
- **`OAuthManager.isAuthenticated(accountId:)`** — new public predicate so the multi-account fan-out can filter by per-account auth state without leaking the private `tokens` map.
- **Multi-account countdown semantics** — the multi-account branch only enters countdown mode when **at least one account is actually exhausted** (throttled or 100%+ on a window). `StatusBarManager` reuses the existing `countdownResetDate(for:now:)` per account and picks the minimum, so healthy accounts with normal future resets never pin the menu bar into countdown mode and hide the new `42% | 23%` text. The multi-account gate also keys on the authenticated account count rather than the per-account map size, so a second account whose fan-out hasn't completed yet still shows as `—` instead of dropping back to single-account mode.

### Tests
- 17 new tests across the multi-account text builder (914 → 910 after removing 4 obsolete `worstResetDate` tests; the per-account countdown selection is already covered by `StatusBarCountdownResetDateTests`). Final total: **910 tests across 60 files**.

### Docs
- **`spec/ARCHITECTURE.md`** — registers `MenuBarMultiAccountText.swift` and notes the multi-account text path on `StatusBarManager`.
- **`spec/UI_SPEC.md`** — documents multi-account text format (`X% | Y%`), order rules, worst-account icon semantics, missing-slot em-dash, mode fallbacks, and the new "exhausted-only" countdown rule.
- **`spec/CONSTANTS.md`** — adds `aibattery_showAllAccountsInMenuBar` UserDefaults key.
- **`spec/DATA_LAYER.md`** — documents `UsageViewModel.perAccountRateLimits`, `fetchAllAccounts(seed:)`, and the `UserDefaults.didChangeNotification` observer.
- **`README.md`** — Display settings table gains a row for the new toggle; test count + Views breakdown updated.

## [2.1.8] — 2026-05-07

### Fixed
- **False "Throttled" display when the API returns a non-quota 429** — `RateLimitFetcher` previously called `markedThrottled()` unconditionally on any HTTP 429, even when the parsed unified headers reported the binding window as `allowed` with low utilization. The active Anthropic incident "Connection failures for organizations restricting GitHub access by IP address" was returning 429s on probe requests, and the 5-Hour bar locked into a fake `Throttled` / `100%` state with `7-Day` simultaneously at `0%` (the smoking gun). New helper `RateLimitFetcher.quotaThrottleLikely(_:)` only treats a 429 as a quota throttle when headers explicitly say so or the binding utilization is ≥ 95% (`quotaExhaustionThreshold`). Applied at all four 429 call sites.
- **Stale persisted `throttled` flag survived across launch** — `restorePersistedRateLimits()` always restored the cached `RateLimitUsage` verbatim, including a `fiveHourStatus: "throttled"` left over from before a long absence. New helper `RateLimitUsage.withClearedExpiredWindows(now:)` normalizes any window whose reset is in the past to utilization 0 / status "allowed", so the bar reflects reality on first launch instead of waiting for the first fresh fetch.
- **`LocalUsageEstimate.calibrateFrom429()` silently ratcheted precise calibrations down** — when a 429 fires without rate-limit headers (which is exactly the case where we have no signal it's a quota throttle), the function previously overwrote the existing calibrated limit with a guess derived from local tokens. Policy change: only seed *uncalibrated* limits (== 0). Once `calibrate()` has run against real utilization headers, that number is treated as authoritative and never overwritten by a header-less 429.
- **Persistent Messages API auth failures were silent** — when the Messages API rejected the access token (token revoked server-side, org access changed) but OAuth refresh kept succeeding, the user saw stale data forever with no signal that they needed to reconnect. `RateLimitFetcher` now tracks consecutive 401/403s per account; at or above `authErrorThreshold` (3), the returned `APIFetchResult.authError = true` and the popover footer shows: *"Authentication failed — please log out and reconnect this account."*
- **Marquee initial pause** — the footer incident banner paused 2.0s before scrolling, long enough that a screenshot or quick glance caught the static truncated head of a long incident name (e.g., the GitHub-IP-restriction one truncating mid-word). Pause shortened to 0.5s.

### Changed
- **`.gitignore`** — added `.build-local/`, `.claude/`, `.gstack/`, and `.planning/quick/` so local agent + planning scratch dirs no longer surface in `git status` on every checkout.
- **Swift 6 warnings cleared** — `LocalUsageEstimate.fiveHourLimitKey` / `sevenDayLimitKey` are now `nonisolated`, matching the nonisolated getters that read them (4 main-actor isolation warnings silenced).

### Tests
- 17 new tests across 4 suites (893 total, +17): `RateLimitUsageTests` (5 cases for `withClearedExpiredWindows`), `LocalUsageEstimateTests` (4 cases for the calibration policy, new file), `RateLimitFetcherTests` (6 cases for `quotaThrottleLikely`), `UsageViewModelTests` (2 cases for the `authError` reconnect message).

### Docs
- **`spec/CONSTANTS.md`** — added `quotaExhaustionThreshold` (0.95) and `authErrorThreshold` (3).
- **`spec/DATA_LAYER.md`** — documented `RateLimitUsage.withClearedExpiredWindows`, `RateLimitFetcher.quotaThrottleLikely`, and the new `APIFetchResult.authError` field.
- **`README.md`** — test count + per-area breakdown brought back in sync with code (also reconciles drift that pre-dated this release).

## [2.1.7] — 2026-04-19

### Fixed
- **Menu bar star invisible on light backgrounds** — the 50–80% usage band used `systemYellow`, which washes out against a light or wallpaper-tinted menu bar. A dedicated `menuBarGold` (#B88F00) now renders when `isDarkMenuBar` is false; dark menu bars and colorblind mode retain their existing system colors
- **Menu bar colors wrong on wallpaper-tinted bars** — `MenuBarIcon` derived light/dark mode from `NSApp.effectiveAppearance` (system-wide), which doesn't reflect the actual menu bar backdrop. All icon rendering now uses `button.effectiveAppearance` from the status item, matching the real bar appearance
- **Timestamp edge cases** — `dateFromUnix()` rejects timestamps ≤ 0 or > 8 days in the future (longest rate limit window is 7 days); `restorePersistedRateLimits()` clamps `fetchedAt` to `Date()` when the system clock has drifted backward; daily activity bucketing uses fixed 86400s intervals instead of `Calendar.date(byAdding: .day)` to avoid DST boundary misalignment

### Changed
- **Design system consistency** — replaced 31 uses of `.foregroundStyle(.secondary)` across 12 view files with `ThemeColors.secondaryLabel` for better contrast on light backgrounds (black 70% vs system secondary). Interactive hover states intentionally keep hierarchical `.secondary`
- **`Layout.borderWidth`** — new 1.5pt design token replaces hardcoded `lineWidth` in auto-mode button stroke and collapsible-section focus ring

### Accessibility
- **Decorative icons hidden from VoiceOver** — added `.accessibilityHidden(true)` to clipboard feedback, info/warning, search, state, and auth icons that duplicated adjacent text labels
- **Missing labels added** — "Clear search" on project filter clear button, "Retry" on error state retry button

### Docs
- **Spec drift** — removed phantom "Tokens" section from UI_SPEC (referenced nonexistent `TokenUsageSection.swift`); added `LocalEstimateSection` and `StandardLimitsSection` fallback view specs; updated menu bar spec to match single-combined-image implementation (`button.effectiveAppearance`, no stroke, `.statusBar` panel level); documented `menuBarGold` in CONSTANTS.md and DATA_LAYER.md
- **`.secondary` references** — UI_SPEC updated to `ThemeColors.secondaryLabel` for account picker, update banner, dismiss button, clipboard icon, tutorial skip

## [2.1.6] — 2026-04-15

### Changed
- **Tighter menu bar pill** — text and the star are now baked into a single `NSImage` via `MenuBarIcon.combinedStatusBarImage(...)` with `button.title = ""`, which eliminates AppKit's bezel padding around a separate `title + image` layout. `statusItem.length` is set to exactly `image.size.width` (makes `NSButtonCell.imageRect(forBounds:)` return `origin.x = 0`, flush against both edges), and the icon's canvas trim bumped 3pt → 4pt on each side (star still fully visible; only ~0.6pt of the red-band halo's outermost <15% alpha ring is clipped). A further 16pt of `NSStatusBarWindow` chrome (8pt per side) is enforced by AppKit for third-party status items and cannot be removed via public API — documented in `spec/UI_SPEC.md`

### Fixed
- **Menu bar `"soon"` text** — when a rate-limit window hit 100% the countdown ticked to `"soon"`, which truncated to `"so"` in the narrow menu bar; `DurationFormatter` now returns `"0s"` for zero/negative durations, and `StatusBarManager` filters past reset dates and refreshes the display on expiry instead of setting a stale countdown title
- **`TokenLedger` write race** — `flushForTesting()` always wrote the file even when no merge had mutated state, and raced the async `save()` Task which also wrote unconditionally; both paths now share a `flushIfDirty()` helper gated on an `isDirty` flag, so back-to-back no-op merges stop touching the file twice
- **`TokenLedger` silent data loss on write failure** — `flushIfDirty()` cleared `isDirty` before the atomic write, so a transient disk-full / permissions / FS error left the flag false and every subsequent `save()` became a no-op until the next merge mutated state, silently dropping high-water marks on restart; write failures now re-acquire the lock and restore `isDirty = true` so the next flush retries
- **Dual-exhausted countdown regression** — in `countdownResetDate`, when both 5-hour and 7-day windows were exhausted the code applied `min(fiveHourReset, sevenDayReset)` *before* filtering past dates, so once the earlier 5-hour reset fired the menu bar dropped to `"100%"` instead of handing off to the still-valid 7-day countdown; the helper now filters past dates per-window before selecting the earliest future reset
- **Menu bar text colour stale on appearance change** — `combinedStatusBarImage` bakes the text colour (black / white) from `NSApp.effectiveAppearance` at render time, and the `appearanceObserver` only repainted the popover panel, so switching light / dark or "Increase Contrast" while the app was idle left the baked text in the wrong colour until the next VM poll; the observer now also rebuilds the status-bar image via `updateButton(...)` and hops onto MainActor via `Task { @MainActor in ... }` instead of `MainActor.assumeIsolated { }` — the KVO callback isn't contractually on main, so an explicit hop is safer than an assertion
- **`TokenLedger` flush ordering race** — two rapid merges could race: flush A encodes state A and releases the lock, merge B mutates state to B, flush B encodes and writes state B, then flush A's later atomic write overwrites the disk with the older snapshot. All flushes now run on a dedicated serial `DispatchQueue` ("TokenLedger.write"), so encoding order == write order — the latest state always lands last on disk
- **Force-unwrap crash risks** — replaced `SessionLogReader` `discoveredFiles!` and `PopoverFooterView` `alternateText!` with guarded paths that fall through cleanly instead of crashing

### Docs
- **Spec drift** — `CONSTANTS.md` token-endpoint timeout corrected 15s → 30s (matches `OAuthManager.swift:359`); OAuth usage URL added as the primary fetch URL with the Messages API entry re-labelled `(fallback)`; `DATA_LAYER.md` `DurationFormatter` docs now match code (`"soon"` → `"0s"`, `"1m" minimum` → `"Xs" (min "1s")`)
- **`RateLimitUsage.countdownText()` docstring** — updated to reflect the `"0s"` behaviour
- **`UI_SPEC.md` / `ARCHITECTURE.md`** — menu bar section rewritten to describe the single-combined-image approach (previous `button.image + button.title` description drifted from code)
- **Countdown refresh cadence** — `CONSTANTS.md` and `UI_SPEC.md` updated from "Per polling cycle (10–60 sec)" to the actual behaviour (`Timer.scheduledTimer` ticking every 1 s when <60 s remain, 10 s otherwise) so future readers don't expect a slower refresh
- **`project.yml`** — `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` bumped 2.1.3 → 2.1.6 to match `Info.plist` (the Xcode-project generator config had drifted three releases behind)

### Tests
- **16 pre-existing drift failures repaired** — `TokenHealthConfig` / `TokenHealthMonitor` rescaled for 1M context windows + `usableContextRatio` 0.8 → 1.0; `ActivityChartData` month-key format corrected (daily → month lookup); `Typography` font sizes updated (10pt mono, 9pt icon)
- **Test isolation** — `RateLimitFetcherTests.setObservedModels_updatesInMemoryList` now uses a unique account ID + defer cleanup so `["model-a", "model-b"]` no longer leaks into the `aibattery_observedModels_*` fallback used by three downstream tests; `MenuBarIconTests.contextHealthColor_matchesHealthBandThresholds` relocated into the `.serialized` `ThemeColorsTests` suite so it no longer races parallel colorblind-flag flips
- **`claude-sonnet-4-6-20250929` coverage** — added to `TokenHealthConfigTests.contextWindow_allKnownModels_4x`; it was present in `TokenHealthConfig.contextWindows` but untested
- **`countdownResetDate` handoff regression pinned** — new `StatusBarCountdownResetDateTests` suite (11 tests) locks in dual-exhausted past/future handoff, throttled binding-reset handling, and nil edge cases. The static helper on `StatusBarManager` is now `nonisolated` so the tests can call it synchronously
- **`TokenLedger` write-failure retry pinned** — new `flush_retriesAfterWriteFailure` test creates a ledger with a missing parent directory, merges, flushes (write fails), creates the dir, flushes again, and verifies the merge actually persisted on retry — catching any future regression of the "silent no-op after failure" bug
- **866 tests across 58 files — all 12 new tests pass individually**; a clean full-suite run was verified before the pre-landing polish fixes

## [2.1.5] — 2026-04-13

### Fixed
- **Popover detaching from the menu bar** — after expanding Settings (or any content resize) the popover sometimes floated mid-screen instead of staying pinned to the menu bar icon; the resize observer now re-derives the top anchor from the status button's current position each time instead of relying on a cached value
- **Crash risks from force unwraps** — replaced three `!` sites (`StatusBarManager` global mouse monitor, `SingleInstanceGuard` + `TokenLedger` Application Support lookups) with guarded paths that fail loudly instead of crashing silently

### Changed
- **Token-accumulation dedup** — `UsageAggregator` collapses nine identical `(input + output + cacheRead + cacheWrite)` blocks into two `accumulate()` overloads, and `RateLimitFetcher` replaces three duplicate header-parse paths with a shared `buildHeaderResult()` helper
- **Named time constants** — `5 * 3600`, `86400`, `900`, `19` replaced with `fiveHourSeconds`, `oneDaySeconds`, `fifteenMinuteSeconds`, `maxBucketsPerDay`
- **Shared mode ordering** — `MetricMode.orderedModes(current:)` replaces duplicated inline "current first" ordering in `MetricToggleView` and `UsagePopoverView`
- **Refresh interval constants** — `UsageViewModel` exposes `defaultRefreshInterval` / `minRefreshInterval` / `maxRefreshInterval` / `initialPollDelay` as `nonisolated` statics to keep `clampedRefreshInterval` warning-free under Swift 6 isolation

### Docs
- **Spec drift** — `CONSTANTS.md` cache-write pricing corrected (six entries were 10× too low; code had been right since 2.1.4), `DATA_LAYER.md` `rateLimitStaleTTL` fixed (300s → 86,400s), `ARCHITECTURE.md` now includes `IdleSuspendPolicy.swift` in the Utilities tree, `README.md` concurrency-fix version reference corrected (v1.2.3+ → v2.0.3+)
- **New helpers documented** — `TokenMap` typealias, `accumulate()` overloads, `buildHeaderResult()`, and `MetricMode.orderedModes(current:)` now appear in the relevant specs

### Tests
- **Suite compiles again** — repaired 13 test files against recent model-layer changes: `estimatedCost` on `ModelTokenSummary`, `standardLimits` on `UsageSnapshot`, `content` on `SessionEntry.SessionMessage`, internal visibility on `RateLimitFetcher.init()`, renamed `addJSONLFileToProject` helper
- **Test hygiene** — removed stale `MenuBarIcon.brokenStarFragments` test (API deleted), updated `ModelPricingTests` to seed non-zero `estimatedCost`

## [2.1.4] — 2026-04-08

### Fixed
- **Consistent token counting** — all display areas (charts, summaries, model breakdown, projects, All Time) now use the same token counting method (all 4 types: input, output, cache read, cache write), fixing massive discrepancies where 7D chart showed 200K while the summary said 515.9M
- **"vs yesterday"/"vs last week" compared messages, not tokens** — trend comparisons now use token counts matching the charts
- **12M stat showed current month only** — now shows full 12-month total to match 5H/7D pattern
- **Projects could exceed All Time** — added JSONL floor guarantee so All Time is never less than Projects
- **Billion formatting** — TokenFormatter and chart axes now handle billion-scale values (previously 1.5B displayed as "1500M")

### Added
- **Token totals on rate limit bars** — 5-Hour and 7-Day bars show total tokens consumed in the active window, aligned to the actual rate limit boundary so the count resets with the window

## [2.1.3] — 2026-04-08

### Fixed
- **7-day false throttle state** — when Anthropic reports an overall throttled state without explicit per-window statuses, the app now marks only the binding window as throttled instead of showing both 5-hour and 7-day as blocked
- **Footer source rotation** — the footer now stays on `Updated …` / `Cached …` instead of alternating to `Via Anthropic API`

### Changed
- **Menu bar pill spacing** — tightened the trailing icon inset so the menu bar capsule hugs the content more closely

## [2.1.1] — 2026-04-04

### Added
- **Local token usage estimation** — when Anthropic's unified rate limit headers are unavailable, the app estimates 5-hour and 7-day usage from local JSONL session data (input + output tokens)
- **Auto-calibration** — when API headers return, the app derives and persists token limits so future estimates show accurate percentages
- **5-hour token chart** — Insights chart now shows 20 x 15-minute token buckets with clock-time x-axis labels (replaces 24H message chart)
- **LocalUsageEstimate model** — calibration storage for derived 5h/7d token limits with manual override support

### Changed
- **Insights charts show tokens** — all three chart modes (5H, 7D, 12M) now display token counts instead of message counts
- **Chart windows** — segmented control changed from 24H|7D|12M to 5H|7D|12M, aligning with rate limit windows
- **All Time row** — shows input + output tokens (excluding cache) instead of message count
- **Project totals** — display input + output tokens (excluding cache) for consistent numbers
- **Mode selector works with estimates** — 5H/7D/Context toggle and auto-mode all function with local token estimates
- **All sections always visible** — 5-hour, 7-day, and context health sections render regardless of selected mode

### Fixed
- **Stale rate limit treadmill** — API returning nil rate limits no longer carries forward stale data indefinitely; TTL-based expiry (5 min) transitions to local estimates
- **Aggregator cache fingerprint** — added standardLimits and rateLimitSource to the cache-skip comparison so changes in fallback data trigger snapshot rebuilds
- **All Time < Projects bug** — model tokens now include all uncached JSONL dates, not just today's; previously missed weeks of data when stats-cache was stale
- **Bare 429 handling** — API returning 429 with no headers now returns immediately instead of cycling through all probe models
- **Token display consistency** — all user-facing token counts use input + output only, excluding cache read/write inflation

## [2.1.0] — 2026-04-03

### Added
- **Standard rate limit fallback** — when Anthropic's unified 5-hour / 7-day usage headers are unavailable, the app now parses standard per-minute API rate limit headers and displays request and token utilization bars as a fallback
- **Standard limits persistence** — standard rate limits survive app restarts and are shown instantly on launch

### Improved
- **Client data diagnostic logging** — the Claude Code client_data endpoint now logs response status and body preview for easier debugging of API format changes
- **Smarter cache display on launch** — cached standard limits show immediately on wake/restart, even when unified 5h/7d data is unavailable

### Fixed
- **Warning suppression with standard limits** — "Claude Code usage unavailable" warning no longer shows when the app has standard rate limit data to display
- **Client data fallback preserves standard limits** — the client_data fallback path no longer drops standard rate limit headers parsed from the original Messages API response

## [2.0.9] — 2026-04-02

### Improved
- **Rate-limit semantics messaging** — the app now keeps Anthropic API header semantics explicit without permanently occupying the top of the popover; the note rotates in the footer alongside the refresh timestamp

### Fixed
- **False resetting state** — partially used windows no longer show `Resetting…` when the reset timestamp is stale or rolling over
- **Claude `/usage` mismatch framing** — 5-hour and 7-day bars now describe Anthropic API header semantics more clearly so the UI does not imply exact parity with Claude Code `/usage`

## [2.0.8] — 2026-04-01

### Fixed
- **Case-insensitive Anthropic header parsing** — rate limit and organization headers now parse correctly even when `HTTPURLResponse.allHeaderFields` returns mixed-case header names
- **429 throttle state fallback** — when Anthropic returns a real `429` but the unified rate-limit headers lag behind or are partially missing, the app now forces the binding window into a throttled state instead of reusing a normal `99%` display
- **Rate limit diagnostics** — when profile data arrives without parseable unified rate-limit headers, the app now surfaces an explicit API-format warning and logs the header names present for debugging

## [2.0.7] — 2026-04-01

### Added
- **Smart Auto Mode** — deterministic 4-tier escalation ladder (Throttle > RL>=80% > Context>=60% > Binding RL) replaces urgency scoring for auto metric selection
- **Hysteresis** — 10pp de-escalation band prevents mode flip-flopping (e.g., RL holds until 70%, context holds until 50%)
- **Stale data indicator** — footer shows "Cached Xm ago" in orange when rate limits come from cache instead of fresh API data

### Fixed
- **Empty bars after sleep** — rate limit cache no longer expires; stale data persists across app restarts and long sleep/wake cycles
- **Idle suspension not resuming** — clicking the menu bar icon now resumes polling even without Accessibility permission
- **Reset countdown for past timestamps** — shows "Resetting..." instead of negative countdown when API reset time is in the past
- **Headerless 429 recovery** — when Anthropic returns 429 without rate limit headers, the app now tries lighter probe models instead of giving up
- **Usage link** — footer "Usage" link now points to `claude.ai/settings/usage`

### Known Issues
- **Stale API rate limit headers** — Anthropic's `anthropic-ratelimit-unified-*` headers may return frozen utilization values that don't match the claude.ai dashboard. This is an API-side issue affecting all consumers.

## [2.0.6] — 2026-03-31

### Fixed
- **24H chart empty in morning** — chart data source only included entries from midnight today; now uses a trailing 24-hour window so yesterday evening's activity displays correctly
- **Cursor flashing on error state** — `NSCursor.push()/pop()` stacked on SwiftUI re-renders causing rapid cursor flashing; replaced with underline-on-hover pattern
- **Division by zero crash** — `TokenHealthMonitor` percentage now guards against zero usable window
- **Root path project name** — `cwd: "/"` now maps to "Other" instead of creating a project named `/`
- **Loading spinner inconsistency** — unified loading spinner from 12pt to 10pt across all states

### Improved
- **Complete design token system** — all hardcoded spacing, corner radius, opacity, and frame values replaced with named tokens (27 Layout, 11 Spacing, 10 opacity tokens across 32 view files)
- **Tooltips everywhere** — all settings controls, rate limit bars (%, binding status, reset time), and interactive elements now show contextual tooltips on hover
- **Keyboard shortcut hints** — tooltips show `(R)` for refresh, `(1, 2, 3)` for metric tabs, `(← →)` for session browsing
- **Empty state polish** — SF Symbol icons for empty (`tray`), idle (`moon.zzz`), and monthly chart (`calendar.badge.clock`) states
- **Accessibility** — GaugeBar height scales with Dynamic Type via `@ScaledMetric` (capped at 1.5x)
- **Throttle count** — removed background pill for cleaner visual weight
- **Removed `contentTransition(.numericText())`** — from infrequently-updating values to reduce rendering overhead

### Added
- **ClaudeSystemStatusTests** — 11 tests for status indicator parsing, severity ordering, display names
- **TokenHealthMonitor tests** — 2 new tests for zero-tokens and unknown model safety

## [2.0.5] — 2026-03-30

### Improved
- **Metric tab picker redesign** — replaced native `NSSegmentedControl` with a custom tab bar matching the app's design language; selected tab shows a raised pill with subtle shadow, unselected tabs use secondary text with hover highlights
- **CI hardening** — pinned GitHub Actions to immutable commit SHAs to prevent supply chain attacks
- **Sparkle update verification** — added EdDSA public key to Info.plist for cryptographic signature verification of auto-updates
- **Reproducible builds** — `Package.resolved` now tracked in version control for deterministic dependency resolution

## [2.0.4] — 2026-03-28

### Fixed
- **Idle resume stuck** — after 5 minutes of inactivity, polling suspended and never restarted because the idle check only ran inside the timer callback it just killed; now installs a global NSEvent monitor that resumes on the first mouse/keyboard event
- **Monthly chart crash** — Swift Charts `EXC_BREAKPOINT` when rendering an empty 12M chart with axis stride configuration; guarded with empty-state fallback

## [2.0.3] — 2026-03-27

### Fixed
- **Menu bar countdown desync** — countdown timer in the menu bar lagged behind the popover by up to 60s because it only updated on API refresh cycles; now ticks independently (10s normally, 1s when <60s remain)
- **Launch at Login lost after updates** — ad-hoc re-signing during Sparkle updates invalidated the SMAppService registration; now re-registers on every launch when the preference is enabled
- **TokenLedger data race** — concurrent `Task.detached` calls could race on dictionary mutation causing EXC_BAD_ACCESS crashes; added NSLock
- **SwiftUI AttributeGraph crash** — conditional Binding swap in MetricToggleView caused use-after-free during view teardown; replaced with a single stable binding that routes internally

### Improved
- **Dark mode panel background** — panel now uses a custom `TransparentHostingView` to suppress NSHostingView's default opaque background, matching the darker tone of native macOS panels (Battery, Wi-Fi)
- **Health warning severity** — added `.info` tier for low-priority warnings (extended conversation, high input ratio) so they're visually distinct from actionable `.mild`/`.strong` warnings
- **Design system tokens** — consolidated hardcoded values into `ThemeColors.hoverFill`, `disabledOpacity`, `Layout.settingsLabel`, `Typography.stateIcon`, `panelBackground`
- **Throttle badge** — throttle count in Insights now shows warning icon with colored pill background

## [2.0.2] — 2026-03-25

### Fixed
- **Settings panel overflow** — settings pushed metric sections off-screen, clipping the panel and making the gear icon unreachable; settings now hide metrics while open
- **StatsCacheReader data race** — `invalidate()` on main thread raced with `read()` on background aggregation thread; added NSLock
- **SessionLogReader data race** — `pendingInvalidation` flag written without lock protection; replaced with lock-protected AtomicBool
- **Wrong account model list** — `observedModels` restored from arbitrary account on launch instead of active account
- **Stale section order** — toggling auto metric mode didn't recompute section display order until next manual mode change
- **Unbounded project search** — filtered project list ignored the 10-item cap, returning all matches for broad queries

## [2.0.1] — 2026-03-25

### Fixed
- **Settings panel blank space** — opening settings, then dismissing the popover (click outside, Escape, app switch) left a large blank area at the top when reopening. Root cause: settings state wasn't reset on dismiss, and the panel preserved the expanded frame. Fixed with a dismiss notification that collapses settings immediately, plus a panel refit on show.

## [2.0.0] — 2026-03-25

### Performance
- **CPU usage eliminated** — idle CPU dropped from 83% to 0.0% (was consuming an entire core scanning 3,103 JSONL files every polling cycle)
- **Memory footprint reduced 8×** — RSS dropped from 409 MB to 52 MB by evicting parsed entries for inactive sessions after merge
- **Aggregation 100× faster** — from seconds to under 100ms via incremental dirty-flag rebuild (only changed files re-parsed)
- **Chart hover optimized** — replaced Calendar.dateComponents() with TimeInterval comparison in hover snap-to-nearest (fires on every mouse move)
- **Calendar caching** — cached Calendar.startOfDay() across sorted entries in aggregate loop, avoiding ICU lock contention per-entry

### Added
- **Incremental JSONL scanning** — per-file fingerprint cache (modDate + fileSize) skips unchanged files entirely; only new or modified session logs are re-parsed
- **Per-directory discovery** — directory modification dates tracked so unchanged project directories skip enumeration; 60s TTL fallback for filesystems where directory mtime doesn't update
- **Entry eviction** — after merge into the authoritative array, raw entry arrays are released for files not modified today; fingerprints and message IDs retained for incremental rebuilds
- **Integration tests** — 8 new tests covering the full incremental scanning and aggregation pipelines end-to-end

### Changed
- **Cache architecture** — LRU cap of 200 files removed (was causing 94% eviction on a real 3,103-file dataset); cache is now unbounded per-file with fingerprint-only storage after eviction
- **Test coverage** — 756 → 784 tests across 52 → 54 files

### Fixed
- **Dead code removed** — legacy `renderBrokenIcon` and supporting geometry (103 lines) replaced by `renderThrottledIcon` in v1.14 but never cleaned up
- **Stale spec** — CONSTANTS.md still referenced the removed 200-file LRU cache cap
- **Duplicate comment** — removed repeated doc comment line in MenuBarIcon sparkle section
- **Comment typo** — fixed duplicate word "hardcoded" in RateLimitFetcher

## [1.9.9] — 2026-03-25

### Fixed
- **Crash: use-after-free (EXC_BAD_ACCESS)** — concurrent `Task.detached` aggregation calls raced on `UsageAggregator`'s mutable cached state, corrupting reference counts during SwiftUI view teardown. Added NSLock to guard cached state and task serialization in `UsageViewModel` to prevent overlapping background work
- **"~0s to limit" at 100%** — when a rate limit window hit 100% before the API reported throttled, the bar showed "soon to limit" instead of indicating the limit was reached. Now shows "Limit reached" in red
- **Menu bar icon still animated at 100%** — breathing animation continued when a window was exhausted but not yet throttled. Icon now shows a static broken star when any window reaches 100%

### Changed
- **Breathing animation removed** — the pulsing glow effect at ≥95% usage is replaced by a static broken star icon when exhausted/throttled. Zero CPU wakeups for icon animation; the distinct 12-pointed star shape communicates the state without motion
- **Design system colors** — 22 hardcoded `.blue`/`.green`/`.yellow`/`.red` values replaced with semantic `ThemeColors` tokens (`action`, `success`, `updateAvailable`, `danger`, `caution`), restoring colorblind-safe palette support across the entire UI
- **Design system tokens** — added `Spacing.micro` (1pt), `Spacing.xsmall` (3pt), `MotionConstants.fadeOut`/`dialog`/`spin`, `Typography.authIcon`/`largeIcon`; replaced 11 raw padding values, 7 raw animation durations, and 2 raw font sizes with tokens
- **Microcopy** — "Loading..." replaced with contextual messages ("Fetching usage data…", "Updating…"); chart empty state now includes a call-to-action
- **Accessibility** — status dot and health badge dot now have accessibility labels

## [1.9.8] — 2026-03-24

### Added
- **Idle/lock detection** — all timers (polling, FileWatcher fallback) suspend after 5 minutes of system idle or when the screen is locked; resume on wake or unlock with an immediate refresh to catch up on missed events
- **IdleSuspendPolicy** — pure enum for idle threshold logic, fully testable without system dependencies

### Improved
- **Sleep/wake lifecycle** — consolidated timer pause/resume into shared `suspendTimers()`/`resumeTimers()` methods, used by sleep, wake, lock, and unlock observers
- **Visual hierarchy** — reduced 5-Hour/7-Day bar label weight from bold to medium so they match the visual weight of collapsible section headers

## [1.9.7] — 2026-03-21

### Improved
- **Typography system** — 19 tokens with documented minor-third scale (9pt icons → 10pt base → 11pt body → 12pt emphasis → 14pt hero); icon floor unified at 9pt; all inline `.system(size:)` calls in views replaced with tokens
- **Design token coverage** — 7 spacing tokens (added `inner` 4pt), 11 layout tokens (added `autoModeSize`, `bannerCornerRadius`, `costColumn`, `tokenColumn`), 4 motion tokens (added `smooth` 0.4s, `expandTransition` slide+fade)
- **Interaction states** — hover feedback on all interactive elements: section headers (subtle fill), footer buttons (underline), gear/update icons (brighten), auto mode button (stroke + fill), sort button (underline + brighten), refresh button (brighten), "Show more" link (underline)
- **Motion polish** — gauge bars animate fill width and color transitions; sections slide+fade on expand/collapse; chart modes crossfade; context health percentage uses numeric text transition; health dot animates color changes
- **Keyboard shortcuts** — `1`/`2`/`3` switch metric modes, `←`/`→` navigate sessions, `R` refreshes data
- **Responsive layout** — popover width scales with macOS text size via `@ScaledMetric` (capped at 130%); panel frame tracks SwiftUI content width; account picker widened 80→100pt; cost column widened 38→46pt to handle 5-digit values; project names use middle truncation
- **Panel positioning** — right-aligns to status item when near screen edge instead of clamping

### Fixed
- **Double divider below Insights** — removed duplicate `StyledDivider` between Insights section and footer
- **Stray divider above metric toggle** — removed redundant divider between header and grey toggle band (background fill provides separation)
- **Hardcoded panel width** — replaced 3 literal `275` values in StatusBarManager with `Layout.popoverWidth`
- **"Show more" link color** — changed from orange (data color) to blue (action color) for semantic consistency

## [1.9.6] — 2026-03-20

### Fixed
- **16-second main thread stall** — `SessionLogReader.invalidate()` blocked on `NSLock` while a background JSONL scan (57K+ entries) held it. Now uses `tryLock()` with atomic pending-invalidation flag — FileWatcher on main never blocks
- **JSONL I/O still on main thread** — moved `UsageAggregator`, `SessionLogReader`, `StatsCacheReader`, and `TokenLedger` off `@MainActor`. Aggregate runs entirely in `Task.detached`; only snapshot assignment and two property updates hop back to main
- **Multiple concurrent refreshes** — `$isAuthenticated` publisher and polling timer both triggered `refresh()` at startup, causing redundant 19-second JSONL scans fighting over the lock

### Changed
- **Auto mode button** — "A" glow color changed from green to blue

## [1.9.5] — 2026-03-20

### Fixed
- **Panel freeze on open** — JSONL session log scanning (16+ seconds of file I/O) was running on the main thread via `@MainActor`, starving the run loop and blocking all user interaction. Moved to background thread via `Task.detached` with `NSLock`-protected caching
- **Panel dismissed immediately after opening** — click-outside monitor was treating the status bar click itself as an "outside click" on LSUIElement apps. Now checks click location against the status item button frame
- **NSApp.activate blocking** — removed `NSApp.activate(ignoringOtherApps:)` entirely from the panel show path. Menu bar panels use `.statusBar` window level + `orderFrontRegardless()` instead, matching the pattern used by Ice, Bartender, and other production menu bar apps

### Improved
- **Panel appears above all windows** — window level raised from `.floating` to `.statusBar`, with `.moveToActiveSpace` and `.fullScreenAuxiliary` collection behaviors
- **SwiftUI pre-warm** — panel is briefly shown offscreen at launch to pay the first-layout cost upfront instead of on first click
- **Click debounce** — rapid clicks within 100ms are dropped to prevent toggle state thrashing

## [1.9.4] — 2026-03-20

### Added
- **Design token system** — Typography (15 tokens), Spacing (6), Layout (7), MotionConstants (2) centralize all font, spacing, and animation values — no more inline literals scattered across views
- **StyledDivider component** — unified divider styling (opacity 0.3, tight padding) replaces 19 inconsistent `Divider()` calls
- **Section animations** — smooth opacity fade on expand/collapse, digit-rolling transitions on rate limit percentages
- **Snapshot tests** — 28 new tests locking design token constant values against regression

### Improved
- **Popover snappiness** — panel now shows before app activation (removed ~200ms blocking `NSApp.activate` delay)
- **File structure** — UsagePopoverView split from 666→210 lines (4 sub-views), ActivityChartView from 711→185 lines (3 extension files); no view file exceeds 400 lines
- **Spec sync** — ARCHITECTURE.md, CONSTANTS.md, and UI_SPEC.md updated to reflect all structural changes
- **Minimum font size** — two 6pt accessibility violations bumped to 8pt floor
- **Consistent outer padding** — all popover sections use uniform horizontal/vertical spacing

### Fixed
- **Popover hang on open/close** — removed `.transition(.opacity)` inside `TimelineView` that fired on every 10-second tick, blocking the main thread with animation renders
- **Animation pipeline overhead** — removed unnecessary `contentTransition(.numericText())` from infrequently-changing values (project tokens, health percentages) to reduce SwiftUI render cost

## [1.9.3] — 2026-03-19

### Fixed
- **Context window detection** — removed downward tier adjustment that incorrectly showed 200K for 1M-context sessions (any session under 500K tokens was wrongly downgraded)
- **API Equivalent label** — removed summary row from cost section; per-model breakdown remains
- **Projection threshold docs** — corrected stale 50% references to 20% in DATA_LAYER and UI_SPEC

### Improved
- **Dynamic probe model list** — rate limit probes now use models observed in JSONL sessions instead of a hardcoded list; self-heals when Anthropic deprecates model IDs
- **JSONL tool call counting** — today's tool calls now sourced from JSONL (supplements stale stats-cache via max() merge)
- **Probe model persistence** — working model saved on all success paths (429, 400+headers, retry-after), eliminating redundant re-probing
- **Adaptive polling** — FileWatcher no longer resets the backoff counter; interval only resets when data actually changes
- **JSONL discovery TTL** — 60-second fallback re-enumeration catches new files even when directory mod-time is unchanged
- **Performance regression tests** — 6 new tests codifying write-batching and aggregation-skip guarantees

### Changed
- **Auto mode button** — green glow instead of blue, matching website theme
- **Spec sync** — all 4 spec files updated to reflect current codebase (ThrottleTracker, AccountStore, dynamic probes, tool call merge, discovery TTL)

## [1.9.2] — 2026-03-17

### Fixed
- **Cache write pricing** — rates were 10x too low (0.125x input instead of 1.25x), all API-equivalent cost estimates underreported. Opus $1.875→$18.75, Sonnet $0.375→$3.75, Haiku $0.10→$1.00
- **Subagent JSONL discovery** — now scans UUID session directories for subagent files (`project/UUID/subagents/*.jsonl`). Previously all subagent token usage was invisible
- **Probe model fallback** — added older models (`claude-3-5-sonnet`, `claude-3-haiku`) as fallbacks when newer model IDs return 404 via OAuth. Persists last working model to UserDefaults; uses the user's active Claude Code model as first probe
- **400 response handling** — generic 400 errors from the Messages API now try the next model instead of stopping (was treating all 400s as network errors)
- **Sleep/wake recovery** — show cached rate limits immediately on wake, bypass NWPathMonitor network check (was reporting offline for minutes), 3s WiFi reconnect delay
- **Inline error with retry** — when rate limits unavailable, shows orange warning with copiable message and Retry button instead of silent empty bars
- **Auto mode button** — removed shadow animation that caused visual bouncing; static shadow only
- **Menu bar grey-out removed** — icon never dims, matching macOS Battery/WiFi behavior
- **Equatable completeness** — added 11 missing fields to UsageSnapshot equality check
- **Double-hyphen filter** — decodes directory path to check for hidden components instead of false-positive raw `--` match
- **Session ID copy** — full UUID in both collapsed and expanded context health views
- **Context windows** — Claude 4.x models updated to 1M (was 200K), usable ratio 1.0. Auto-detects from token usage if hardcoded value is too low
- **Launch lag** — show cached rate limits instantly from UserDefaults, delay full JSONL refresh 2s. Panel opens immediately on first click
- **Panel close** — click-away and app-switch now dismiss the panel reliably

### Improved
- **JSONL discovery** — single recursive enumerator per project dir instead of per-directory calls (469→215 syscalls)
- **No background animations** — removed all data-driven `.animation()` and `.contentTransition()` that ran on every poll cycle even with panel closed
- **Debounced Combine** — StatusBarManager button updates coalesced by 200ms
- **Loading indicator** — tiny spinner in footer instead of large centered spinner

### Changed
- **"Account" → "User"** — shorter label in header picker and settings
- **Header spacing** — tighter icon-to-title gap, user name truncates with `...` instead of wrapping

### Removed
- Dead code: `copyDetailsButton`, `detailsCopied`, `showCostEstimate` key, `tokensCollapsed` key, staleness grey-out logic

## [1.9.1] — 2026-03-17

### Added
- **Instant rate limits on launch** — persists last rate limit data per account to UserDefaults. On restart, 5-hour and 7-day bars appear immediately from cache while the API call runs in the background.

### Fixed
- **Throttle display** — restored correct condition: "Throttled" only shows when the API confirms throttling, not just at 100% usage. Fixes reset celebration being blocked.
- **Idle slider sync** — slider position stays in sync when the idle setting changes externally.

## [1.9.0] — 2026-03-16

### Added
- **Insights section** — merged Tokens + Activity into a unified section with activity chart, time-windowed API-equivalent cost breakdown, and cumulative stats (Period, Longest, All Time)
- **Windowed cost breakdown** — per-model API-equivalent cost filtered by chart time window (24H = today, 7D = this week, 12M = this month)
- **Per-project token usage** — Projects section groups tokens by working directory with sort (tokens/cost/name), search, and expand/collapse
- **Copy session details** — clipboard button in Context Health copies full session info
- **Pre-computed project totals** — `totalProjectTokens` and `totalProjectCost` on `UsageSnapshot`
- **README project tracking docs** — explains how Claude stores JSONL data per project and how totals are calculated

### Improved
- **Panel crash fix** — `DispatchQueue.main.async` in frame observer prevents re-entering SwiftUI constraint update cycle
- **Activity chart hover** — tooltip renders as floating overlay, preventing layout shifts
- **Equatable conformances** on 5 model types for efficient SwiftUI diffing
- **KeychainHelper extraction** from OAuthManager (650→590 lines)
- **Breath timer optimization** — red band uses 4 wakeups/cycle instead of 8
- **`formatCompactCost` fix** — ≥$1000 shows `"$1.2K"` format
- **Selective FileWatcher invalidation** — only invalidates affected caches
- **Menu bar font** — 12pt → 11pt to match macOS Battery percentage size
- **Projects** — top 5 default (was 6), expand to 10, show more + sort on same line

### Changed
- **Token Usage section removed** — merged into Insights as API-equivalent cost block
- **"Activity" → "Insights"** — renamed to reflect combined scope
- **Cost always visible** — removed settings toggle, API-equivalent cost shown everywhere
- **Header logo** — white sparkle SF Symbol matching website icon (was plain text `✦`)
- **Metric toggle** — tinted background, tighter layout
- **Insight rows reordered** — Period → Longest → All Time (at bottom)

## [1.8.5] — 2026-03-12

### Improved
- **Native dark mode** — panel background uses `controlBackgroundColor` matching macOS Battery, Clipy, and other menu bar apps in both light and dark mode
- **Static throttle icon** — broken star frozen at peak intensity when throttled (no breathing animation), saving CPU wake-ups and image renders
- **Panel stability** — collapse/expand sections no longer causes panel to drift downward; resize observer uses fixed top anchor

### Changed
- **Removed NSVisualEffectView** — replaced with system `controlBackgroundColor` for reliable appearance across all macOS display modes (translucent, opaque, high contrast)

## [1.8.4] — 2026-03-11

### Added
- **Collapsible Insights** — Insights section now collapses like other sections, with 5 expanded rows: Today, All Time, Longest Session, Tools, and data Period (date range)
- **Two-tap logout** — logout button requires confirmation tap (auto-reverts after 3s) to prevent accidental sign-out
- **"Updated X ago" timestamp** — footer shows relative time since last fetch (refreshes every 10s); replaced by incident banner when active
- **Star-shaped glow system** — menu bar icon uses severity-based visual effects: no glow below 80%, static star glow at 80–95%, breathing star glow at 95%+, starburst rays when throttled
- **Time-proximity boost** — auto mode urgency scoring now factors in estimated time to rate limit, not just percentage
- **Shared components** — extracted `CollapsibleSectionHeader`, `FooterLink`, and `RefreshButton` into reusable views
- **Date range formatter** — `DateFormatters.formatDateRange` with same-year/cross-year handling + 2 tests
- **Activity collapsed summary** — shows vs-yesterday change indicator inline with header
- **Copyable estimates** — time-to-limit and reset countdown values are now click-to-copy

### Improved
- **Menu bar layout** — text-first icon layout (imageTrailing) with 12pt monospaced digits matching macOS battery indicator
- **Panel behavior** — dynamic height resizing, Cmd+Q support, left-aligned to status item
- **Loading/error states** — centered vertical layout with retry icon, clearer "Fetching usage data..." message
- **Accessibility** — VoiceOver announcements for auto mode toggle, accessibility hints on account picker, loading spinner, and quit button
- **CI workflow** — skip doc-only changes, skip draft PRs, added manual workflow_dispatch trigger
- **Unified colors** — menu bar icon and in-app views now share the same ThemeColors palette
- **Animation efficiency** — timer stopped below 80% usage (no visible effect), orange band uses static glow without timer

### Fixed
- **Insights abbreviation** — collapsed summary now shows "sessions" instead of unrecognizable "sess" abbreviation

## [1.8.3] — 2026-03-10

### Added
- **Idle-filtered empty state** — shows "No active sessions" when all sessions are filtered out by the idle cutoff setting
- **Relative timestamps** — context health sessions show "just now", "5m ago" etc. instead of absolute times for recent activity

### Improved
- **VoiceOver** — collapsible sections (Tokens, Activity, Context Health) now announce expanded/collapsed state; copy actions announce confirmation
- **Lazy chart computation** — chart data is only computed for the active mode; other modes load on first switch (reduces initial render work)
- **Token ledger resilience** — save failures now log warnings instead of silently failing
- **Panel height** — increased to accommodate expanded content without scrolling

### Removed
- **Copy JSON button** — removed from Insights section (all values are already click-to-copy via `.copyable()`)

## [1.8.2] — 2026-03-10

### Added
- **Persistent token ledger** — token totals now survive Claude Code stats-cache rebuilds via a high-water-mark ledger at `~/Library/Application Support/AIBattery/token-ledger.json`; per-model, per-account, per-token-type maximums are preserved forever
- **Seconds countdown** — rate limit reset timers now count down in seconds below 60s (e.g. "42s", "3s") instead of showing "1m"
- **Reset celebration** — green sparkle "Reset" indicator when a rate limit window resets after being exhausted; "Resets soon" fallback when timer expires but API hasn't confirmed
- **Session hash on collapse** — collapsed Context Health shows the 8-char session ID (copyable) next to the health badge
- **Observer session filter** — MCP observer sessions (hidden path components) are now excluded from context health display
- 9 new TokenLedger tests, 3 new DurationFormatter tests — 564 total

### Improved
- **Compact layout** — reduced section padding (12→8pt), header/footer padding (10→6pt), and VStack spacing (8→6pt) across all sections
- **Metric picker** — labels changed from "5h/7d/Ctx" to "5 Hour/7 Day/Context"; auto mode now highlights the selected segment; removed "Showing X" subtitle
- **Performance** — consolidated trend data computation (single Date/Calendar/throttleCount per render instead of duplicated); single Date() call per rate limit bar; cached chart transforms; fingerprint-first aggregation; async ViewModel init; reduced animation fps (16→8 pulse steps)
- **Week-over-week comparison** — now compares same days (Mon vs Mon, Mon–Tue vs Mon–Tue) instead of requiring Wednesday for a full-week comparison
- **Token section** — individual values copyable instead of whole rows
- **Auto mode** — picker selection syncs to auto-resolved mode via read-only binding

### Fixed
- **7-day stats hidden** — reset celebration/soon states no longer incorrectly trigger on normal low-usage windows where the rolling reset timestamp is in the past

## [1.8.1] — 2026-03-09

### Improved
- **Instant panel open** — removed utility window fade-in animation and reordered app activation before panel display, eliminating perceived delay when clicking the menu bar icon
- **Code organization** — extracted `MetricMode`, `TrendDirection`, and `ClaudeSystemStatus` types into dedicated model files (were inlined in service/aggregate files)
- **Y-axis deduplication** — consolidated identical Y-axis configuration across 3 chart modes into shared `sharedYAxis` computed property
- **MenuBarIcon accessibility** — replaced per-frame `accessibilityDisplayShouldIncreaseContrast` polling with notification-based observer (updates only when system settings change)

### Added
- 7 new edge case tests: auto mode tie-breaking, 95% threshold boundary, nil rate limits, negative percentage clamping, urgency score consistency, reset-in-past, exact-threshold — 549 total

## [1.8.0] — 2026-03-09

### Added
- **Collapsible sections** — Context Health, Tokens, and Activity sections now collapse/expand with a rotating chevron; state persists across restarts
- **Activity collapsed summary** — collapsed Activity header shows "vs yesterday" change at a glance

### Removed
- **Daily Pace metric** — removed the Pace metric mode; picker reduced from 4 to 3 segments (5h / 7d / Ctx)
- **Show/hide settings toggles** — replaced by inline collapse on each section header

### Improved
- **Menu bar performance** — breathing animation timer now only runs at ≥80% usage, throttled, or sparkle active; saves 4 wake-ups/sec during normal operation
- **Dead code cleanup** — removed orphaned `showTokens`/`showActivity` UserDefaults keys

## [1.7.2] — 2026-03-08

### Improved
- **Defensive rate limit parsing** — utilization values clamped to [0.0, 1.0] on parse, preventing >100% or negative UI percentages from unexpected API responses
- **Build reliability** — PlistBuddy key injection is now idempotent (Set with Add fallback), notarization retries 3× with 30s backoff
- **Sparkle version pin** — dependency constrained to 2.x to prevent breaking major-version upgrades
- **Menu bar accessibility** — VoiceOver now reads "AI Battery" with current percentage on the status bar button
- **Chart data testability** — extracted daily/hourly/monthly transformations from view into pure static functions with 14 new tests
- **Hourly chart safety** — added missing lower bounds check in axis label rendering
- **Cache eviction** — `SessionLogReader` uses O(n) min-find instead of O(n log n) sort for single-entry eviction
- **Spec updates** — documented all rate limit header names in CONSTANTS.md

## [1.7.1] — 2026-03-06

### Fixed
- **Throttle event tracking** — throttle counter now detects per-window throttle status, not just overall. Previously, a window-level throttle (e.g. 5h "throttled") could go unrecorded if the overall status hadn't updated yet
- **Token exchange resilience** — malformed 200 responses from the token endpoint now retry instead of hard-failing
- **Crash on corrupt stats-cache** — duplicate dates in `dailyActivity` no longer crash the aggregator (was using `Dictionary(uniqueKeysWithValues:)` which fatally traps on duplicates)
- **Missing model in context windows** — added `claude-haiku-3-5-20241022` alias to prevent fallback to default if context windows ever diverge

### Improved
- **12M chart performance** — replaced 4× full scans of daily activity with single-pass month aggregation shared between chart and trend summary
- **Activity merge** — daily activity merge and delta computation consolidated into a single pass, eliminating a redundant dictionary and second loop
- **Keychain code** — extracted shared base query to reduce duplication across set/get/delete
- **Status parsing** — consolidated 3-pass component parsing into single pass
- **CI reliability** — retry logic for flaky macOS runner crashes (signal 11)

## [1.7.0] — 2026-03-06

### Added
- **Animated menu bar star** — 3 render modes: breathing glow (scales with usage), broken star (throttled), and recovery sparkle (30s celebration when throttle clears)
- **Context health color** — star color matches health band thresholds (green/orange/red at 60/80%) when in context health mode
- **Countdown at 100%** — menu bar shows time until capacity returns when any rate limit window is exhausted (not just when throttled)
- **Trailing 12-hour activity chart** — chart now shows last 12 hours instead of fixed 24-hour window
- **3-account support** — monitor up to 3 Claude orgs simultaneously (was 2)

### Changed
- **Auto mode priority** — rate limits at ≥95% now unconditionally beat context health (was ≥90% and only when higher than context)

### Improved
- **Smoother animation** — 16-step breathing cycle (250ms ticks) with sine-wave easing; `MainActor.assumeIsolated` eliminates async dispatch overhead
- **Code quality** — extracted settings sections into dedicated views, removed dead code, cleaned up imports
- **Keychain consolidation** — deduplicated Keychain logic, fixed task leak in iteration helpers

### Fixed
- **Throttled bar visibility** — usage bars at 100% now show "Rate limited" state when overall throttled, even if per-window status header doesn't say "throttled"
- **Recovery sparkle visibility** — boosted sparkle alpha (0.7), arm length (1.6pt), and 2-3 sparkles per frame for a more visible celebration effect
- **"Throttled" vs countdown** — menu bar shows countdown only for non-throttled 100% windows; throttled state shows "soon" when reset date has passed
- **Cache key collision** — broken and normal star icons at 100% no longer share cache keys
- **Test stability** — fixed timezone-dependent activity stats test, flexible elementCount assertions for macOS 15.5

## [1.6.8] — 2026-03-05

### Improved
- **Duration formatting** — `LongestSession.durationFormatted` now uses shared `DurationFormatter.compact` (0ms shows "soon", sub-minute shows "1m", durations ≥24h get "Xd Yh")
- **Defensive coding** — replaced force-unwraps in monthly chart data with guard-let early return; guarded request body serialization in `RateLimitFetcher` with log + error return
- **Error logging** — `AccountStore` and `SingleInstanceGuard` now log warnings on previously silent failures (JSON encode, directory creation)
- **View performance** — eliminated duplicate `TokenFormatter.format` / `ModelPricing.formatCost` calls in `TokenUsageSection` and `TokenHealthSection` (stored in `let` bindings)

### Removed
- **Dead code** — removed `StatusComponent.fireKey` alias (was identical to `alertKey`), removed trivial `formatDuration` passthrough wrapper in `UsageBar`

## [1.6.7] — 2026-03-05

### Changed
- **Lock file location** — moved from `~/.claude/` to `~/Library/Application Support/AIBattery/` (sandbox-writable path, App Store ready)
- **Appearance tracking** — replaced private `DistributedNotificationCenter` API with KVO on `NSApp.effectiveAppearance` (documented API)

### Removed
- **Quarantine detection** — removed `checkQuarantine()` alert (irrelevant for App Store; Sparkle handles direct-download codesigning)

### Added
- **Network entitlement** — `com.apple.security.network.client` (required when sandbox is enabled, no effect while off)
- **Marketing icon** — 1024×1024 PNG for App Store Connect (`screenshots/icon-1024.png`)
- **README app icon** — logo in header, updated tagline, sponsor section, badge cache fixes

## [1.6.6] — 2026-03-05

### Fixed
- **Context health double-counting** — output tokens for context calculation now uses latest entry only (was summing all entries, inflating usage percentage)
- **Session deduplication** — messageId fallback uses stable composite key instead of random UUID (fixes count inflation after LRU cache eviction)
- **Throttle indicator color** — throttle trend now shows orange/caution instead of green
- **Add-account detection** — tracks account count at flow start to detect actual additions
- **Idle session visibility** — current session always appears in session browser even when idle past cutoff
- **Trend direction** — requires 14 days of data for symmetric 7-vs-7 comparison (was 8)
- **Duration formatting** — exactly 24 hours now shows "1d 0h" instead of "24h 0m"
- **Token formatting** — 999,999 displays as "1.0M" instead of "1000K" (both TokenFormatter and chart labels)
- **Multi-monitor positioning** — panel positioned relative to status item's screen, not primary screen
- **Negative remaining** — usage bars clamp remaining percentage to 0 instead of showing negative values
- **Monthly projection** — skips projection for first 3 days of month (insufficient data for meaningful estimate)
- **Monthly accessibility** — uses actual message total instead of projected data for a11y labels
- **Quarantine alert** — path is now quoted in the fix command text

### Improved
- **Click-outside dismiss** — panel closes when clicking outside or switching apps (standard menu bar behavior)
- **Adaptive polling** — progressive exponential backoff (2x → 4x → 8x) instead of fixed 2x doubling
- **FileWatcher fallback** — starts fallback timer when either watcher fails (was requiring both to fail)
- **Session list reset** — selectedIndex resets when sessions list shrinks past current position
- **Locale-aware times** — session timestamps use user's locale formatting instead of POSIX 24h
- **MarqueeText** — text width updates on geometry change, not just on appear
- **7D chart labels** — shows day abbreviation for all days (removed special "Today" label)

### Added
- 4 new tests: progressive doubling, 24h boundary, 13-day trend, idle session inclusion — 475 total across 35 files

## [1.6.5] — 2026-03-05

### Fixed
- **Activity charts showing stale data** — 7D and 12M charts now merge JSONL entries for all dates (not just today) into `dailyActivity`, filling gaps between the last stats-cache rebuild and the present. Fixes charts showing a cliff to zero after the cache rebuild date.
- **All Time stats double-counting** — `totalMessages`/`totalSessions` dedup now iterates all dates instead of only today, preventing inflation when stats-cache already includes recent data.
- **24H chart using all-time data** — hourly chart now uses `todayHourCounts` (today's JSONL only) instead of cumulative `hourCounts` from stats-cache.
- **Token totals lower than dashboard** — removed 72-hour model recency filter that was excluding older models from `modelTokens` and `totalTokens`.

### Added
- **Mode-aware trend summary** — Activity chart trend stats change per selected mode: 24H shows vs-yesterday + peak hour; 7D shows weekly trend + avg/day + busiest day; 12M shows vs-last-month (projected) + busiest month.
- **Throttle tracking** — records rate limit events on each not-throttled→throttled transition (one count per throttle session). 30-day retention. Trend summary shows "0 throttles today/this week/this month" or "N× throttled" per chart mode.
- **12M current month projection** — current month extrapolated to full-month pace (`total × daysInMonth / dayOfMonth`) for fair comparison with completed months.
- **Y-axis labels** — all three chart modes now show 3 trailing Y-axis marks with compact labels ("2K", "3M") and tick marks.
- **Menu bar icon glow** — star icon now has a subtle glow effect behind the fill (usage-colored, 0.35 alpha, 2.5pt blur).
- **Auth view app icon** — sign-in screen displays the real app icon instead of a text sparkle.
- 13 new tests: throttle recording/counting (6), aggregator accuracy (7) — 471 total across 35 files

## [1.6.4] — 2026-03-04

### Changed
- **Simplified alerts** — replaced 5 per-component status toggles with a single Status on/off. When enabled, notifies on any component outage (claude.ai, Console, API, Code, Gov).
- **Idle session filter** — replaced "Models" time window (1–7d) with "Hide idle" session cutoff (30m–8h or Never). Hides stale sessions from context health instead of filtering token history.
- **Settings layout** — Status and Rate Limit alerts on same row. Launch at Login moved below alerts.

### Fixed
- **Thread safety** — added `@MainActor` to `FileWatcher`, `SessionLogReader`, `StatsCacheReader`, `UsageAggregator`. Fixed nested lock in `ModelPricing` (could deadlock with `ModelNameMapper`). Inlined `FileWatcher.deinit` cleanup (nonisolated deinit can't call actor methods).
- **ThemeColors** — changed `secondaryLabel`/`tertiaryLabel`/`trackFill`/`badgeFill` from computed to `static let` (dynamic `NSColor` adapts at draw time, no need for recomputation).

### Improved
- **UsageViewModel** — extracted 3 static helpers (`clampedRefreshInterval`, `refreshErrorMessage`, `hasDataChanged`) for testability. Removed dead code (`metricMode`, `menuBarPercent`, `hasData`).
- **Alert migration** — one-time migration consolidates all legacy per-component keys into unified `alertStatus` toggle.

### Added
- 22 new tests: ViewModel helpers (15), migration (4), status component catalog (3) — 458 total across 35 files

## [1.6.3] — 2026-03-04

### Fixed
- **Auto mode context health** — auto mode now uses the highest context health percentage across all tracked sessions, not just the most recent. Fixes menu bar showing wrong metric when an older session had higher context usage.
- **Light mode colors** — bar gauge colors (gold, orange) now use system palette in both modes. The opaque light-mode background provides sufficient contrast, so the custom dark variants are no longer needed.

### Improved
- **Cache race windows** — `ModelPricing` and `ModelNameMapper` caches use atomic `withLock {}` instead of manual lock/unlock pairs, closing a double-checked locking race window.
- **TokenHealthMonitor performance** — pre-filters stale sessions before `Dictionary(grouping:)` to avoid allocating dictionary buckets for months of inactive sessions. Binds timestamps once in `assess()` to avoid repeated optional chain traversals.
- **StatsCacheReader** — collapsed `fileExists` + `attributesOfItem` into a single `stat()` syscall per read.
- **FileWatcher** — removed redundant `DispatchQueue.main.async` hop in FSEvent callback (already dispatched on `.main`).
- **NotificationManager** — `hasFired` uses `Set<String>` instead of `[String: Bool]` for clearer intent.
- **UsageViewModel** — single account lookup in `resolveAccountIdentity` (was scanning twice).
- **TokenHealthSection** — removed redundant `max(idx, 0)` guard (index is always non-negative).

### Added
- 4 new auto mode / context health tests (436 total across 34 test files)

## [1.6.2] — 2026-03-03

### Changed
- **Native notifications** — replaced `osascript display notification` with `UNUserNotificationCenter`. Notifications now show the AIBattery app icon instead of Script Editor. First toggle prompts macOS notification permission dialog.
- **DurationFormatter** — extracted shared compact duration formatting (`"2h 5m"`, `"1d 1h"`, `"soon"`) into a dedicated utility, replacing 4 duplicate implementations across views and models.

### Improved
- **Code quality** — simplified `StatsCacheReader`, named `FileWatcher` magic constants, removed redundant nil initializers, fixed `ModelNameMapper` data race with `nonisolated(unsafe)` cache
- **Reduced redundant work** — extracted `buildModelTokens` helper in `UsageAggregator`, cached dictionary lookup in `RateLimitFetcher.tryFetch`, eliminated double account lookup and cached `systemIndicator` in `UsagePopoverView`
- **Removed dead code** — `applescriptQuoted` helper and 6 associated tests

### Added
- 10 new `DurationFormatter` tests (410 total across 34 test files)

## [1.6.1] — 2026-03-03

### Fixed
- **Light mode readability** — popover now has a solid opaque background in light mode (no desktop bleed-through). Dark mode retains the translucent vibrancy material.
- **Adaptive text colors** — replaced all `.tertiary` / `.quaternary` foreground styles with `ThemeColors.tertiaryLabel` (55% black in light, 35% white in dark) for much better contrast on light backgrounds.
- **Orange text contrast** — caution/warning orange uses a deeper `(0.85, 0.45, 0.0)` in light mode instead of system orange which washes out on white. Affects usage bars (80–94%), context health bands, status indicators, and warning labels.
- **Adaptive bar/badge fills** — bar gauge tracks use 14% black (light) / 10% white (dark); badge fills use 9% black (light) / 6% white (dark) instead of hardcoded opacity values.
- **Gold replaces yellow** — 50–80% usage bars use a darker gold `(0.75, 0.58, 0.0)` in light mode for ≥4.5:1 contrast ratio against white; system yellow in dark mode.
- **Chart area gradient** — bottom opacity increased from 5% to 10% for visibility on white backgrounds. Chart accent uses deeper orange in light mode.
- **Panel appearance tracking** — popover follows system light/dark appearance changes in real time.

## [1.6.0] — 2026-03-03

### Added
- **Menu bar throttle countdown** — when rate-limited, menu bar shows countdown to reset (e.g., "2h 15m", "45m") instead of "100%". Updates on each polling cycle, overrides metric mode while throttled.
- **Live activity chart** — 7D and 12M charts now merge today's live JSONL messages into `dailyActivity`, showing current-day usage even when `stats-cache.json` is stale.
- 7 new tests: countdown formatter (6), throttled header parsing (1) — 421 → 428 total

### Changed
- **StatusBarManager rewrite** — replaced SwiftUI `MenuBarExtra` with native AppKit `NSStatusItem` + floating `NSPanel`. Menu bar button uses native `button.image` + `button.title` with system monospaced-digit font (matches macOS battery indicator). Removed `PanelAccessor.swift` and `MenuBarLabel.swift`.
- **Context health sorted by usage** — sessions ordered by highest context consumption (position 1 = most-consumed) instead of recency.
- **Improved context health navigation** — chevron buttons enlarged to 22pt hit targets with press highlight for easier clicking.

### Fixed
- **Popover stays open** — panel no longer dismisses when mouse moves away or focus shifts. `PopoverPanel` overrides `hidesOnDeactivate` getter to always return `false`, with a deactivation observer fallback. Only closes on status item click or Escape key.
- **Blank menu bar icon** — `NSHostingView` inside `NSStatusBarButton` doesn't render; replaced with native AppKit properties (`button.image`, `button.title`).
- **Rate limit bars vanishing when throttled** — 429 responses now parse rate limit headers directly instead of discarding them. Usage bars and reset times remain visible while rate-limited.
- **7D activity chart empty** — chart showed "No activity data" because today's JSONL messages weren't included in `dailyActivity`. Now merged before snapshot construction.

## [1.5.5] — 2026-03-03

### Added
- **Defense-in-depth security hardening** — ephemeral URLSession (no disk cache/cookies), 2 MB response size guard, 10 MB stats-cache file size guard, symlink boundary check for JSONL discovery, Keychain accessibility migration (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`)
- **Performance caching** — ModelNameMapper result cache, UsageAggregator redundant aggregation skip (fingerprint-based), StatsCacheReader exposes `lastModificationDate` for change detection
- **NotificationManager concurrency** — `@MainActor` annotation, structured concurrency batching (replaces DispatchSource timer), `shouldAlert` marked `nonisolated`
- 13 new tests (408 → 421 total): SecureNetworking, SessionLogReader symlink boundary, StatsCacheReader file size guard, UsageAggregator redundant skip, ModelNameMapper result cache

## [1.5.4] — 2026-03-02

### Fixed
- **Popover mouse pass-through** — hovering over the popover no longer interacts with windows beneath it. Configured the MenuBarExtra NSPanel (`becomesKeyOnlyIfNeeded = false`, `acceptsMouseMovedEvents = true`) and added `contentShape(Rectangle())` to close SwiftUI hit-testing gaps.

## [1.5.3] — 2026-02-26

### Fixed
- **Sparkle update Keychain prompts** — reduced Keychain items from 3 to 1 per account (refresh token only). Access token is now memory-only (re-derived on launch), expiry timestamp moved to UserDefaults. Sparkle updates now trigger at most 1 Keychain prompt instead of 3.

### Added
- One-time migration (`migrateStaleKeychainItems`) cleans up legacy `accessToken` and `expiresAt` entries from Keychain on first launch after upgrade

## [1.5.2] — 2026-02-26

### Improved
- **Wake/sleep lifecycle** — polling pauses on sleep, immediate refresh on wake, adaptive polling resets
- **Network awareness** — skip API calls when offline via NWPathMonitor, show cached data with "No internet" message
- **SwiftUI redraw optimization** — decomposed SettingsRow into 3 focused sub-views; toggling a display setting no longer redraws unrelated sections
- **Deprecated API fix** — replaced `lockFocus`/`unlockFocus` with `NSImage(size:flipped:drawingHandler:)`
- **Testability** — extracted `AdaptivePollingState`, `parseRetryAfter`, and `TokenHealthConfig` thresholds into testable units
- **Centralized date formatters** — shared `DateFormatter` instances allocated once and reused
- **Activity chart accessibility** — added VoiceOver labels to chart data points

### Added
- 26 new tests (382 → 408 total): DateFormatters, AdaptivePollingState, parseRetryAfter, rapid consumption detection, custom health thresholds, Retry-After parsing

## [1.5.1] — 2026-02-26

### Fixed
- **Stale update banner after upgrade** — `VersionChecker` now validates the cached update version against the current app version on startup, discarding stale entries (e.g. "v1.4.1 available" no longer shows after upgrading to v1.5.0)
- **Release workflow Homebrew step** — appcast deploy checked out `gh-pages`, losing the source tree for the subsequent Homebrew cask update step; added checkout restore

## [1.5.0] — 2026-02-25

### Added
- **Sparkle auto-update** — in-app download, verify, and install via Sparkle 2. Click "Install Update" in the update banner to update without leaving the app. Falls back to GitHub release page if Sparkle is not ready.
- **Update banner redesign** — bordered card with version link (opens release page), Install Update button, and dismiss (✕). Yellow icon re-shows the banner after dismiss.
- **EdDSA signing** — release pipeline signs zips and generates appcast.xml, deployed to gh-pages for Sparkle feed
- `SparkleUpdateServiceTests` — 8 tests for Sparkle configuration verification

### Changed
- Build script bundles Sparkle.framework into `.app/Contents/Frameworks/` with proper rpath and codesigning
- Release workflow deploys appcast.xml to gh-pages branch on each tagged release

## [1.4.1] — 2026-02-25

### Fixed
- **Layout jump bug** — sections no longer jump to top-left on state changes. Root causes: `.animation()` was scoped to the entire VStack instead of just the ForEach; `withAnimation(.repeatForever)` for auto-mode glow leaked a global repeating animation transaction; `withAnimation` on update check caused global layout animation.

### Improved
- **Gate views** — `TokenUsageGate` and `ActivityChartGate` now own their `@AppStorage` toggles, preventing parent view redraws when display settings change
- **TutorialOverlay** — self-managing visibility via own `@AppStorage(hasSeenTutorial)`, parent passes only `hasData: Bool`
- **Auto-mode glow** — uses scoped `.animation()` modifiers on stroke/shadow views instead of global `withAnimation(.repeatForever)`

## [1.4.0] — 2026-02-25

### Improved
- **Update button indicator** — replaced the "vX.Y.Z available" banner below the header with persistent button color states: yellow when an update is available (click opens release page), green flash when up to date, gray default

### Removed
- Update banner and "Up to date" text block below header (button color now communicates state)

## [1.3.0] — 2026-02-23

### Added
- **Auto mode** — (A) button on metric toggle automatically selects whichever metric (5h/7d/context) has the highest percentage, applied to both popover and menu bar
- **Incident marquee** — scrolling `MarqueeText` view in footer cycles through active incident names with cross-fade transitions and severity-colored text
- `OAuthManagerTests` — 10 tests (AuthError user messages, transient error classification)
- `UsageAggregatorTests` — 2 additional tests (stats+JSONL merge, all-time mode)

### Improved
- **UsageSnapshot stored properties** — `totalTokens`, `dailyAverage`, `trendDirection`, and `busiestDayOfWeek` pre-computed at construction via static factory methods (avoids per-render iteration in SwiftUI body recomputation)
- **SessionLogReader statics** — `assistantMarkers`, `usageMarker`, `jsonDecoder`, and `isoFormatter` promoted to static lets (avoids per-file allocation)
- **StatsCacheReader static decoder** — shared `JSONDecoder` instance avoids per-read allocation
- **UsageAggregator static formatters** — `DateFormatter` and `ISO8601DateFormatter` created once at load time
- **ModelNameMapper native string ops** — replaced `NSRegularExpression` with manual character iteration for date stripping (eliminates ObjC bridging overhead)
- **ModelPricing lookup cache** — `pricingCache` dictionary avoids repeated `displayName` + linear scan on every call
- **MenuBarIcon band caching** — NSImage cached by color band (4 bands × 2 colorblind modes), only re-rendered when band changes
- **DailyActivity static formatter** — shared `DateFormatter` for `parsedDate` computed property
- **SessionLogReader buffer compaction** — leftover Data slices re-allocated to drop references to old backing buffers
- **Auto mode color** — changed from cyan to blue for better visual consistency

### Fixed
- **Auto mode button hit target** — added `.contentShape(Circle())` so the full 20pt circle is tappable, not just the "A" glyph
- **Rate limit slider tick marks** — added missing 95% endpoint label
- **Tutorial overlay backdrop** — changed from `Color.primary.opacity(0.35)` to `Color.black.opacity(0.4)` (primary is white in dark mode, making backdrop invisible)

### Removed
- `PlanTier` model type (billing type now stored directly as string via `aibattery_plan` UserDefaults key)

## [1.2.3] — 2026-02-23

### Fixed
- **Runtime crash (app disappears after running)** — removed `Task.detached` data race between background aggregation and main-thread cache invalidation; aggregation now runs on the main actor
- **Sleep/wake crash** — replaced unsafe `signal(SIGTERM)` handler (used `DispatchQueue.main.async`, which can deadlock during sleep/wake) with `DispatchSource.makeSignalSource`
- **Dual-launch race condition** — `SingleInstanceGuard` now uses POSIX file lock (`flock`) as primary mechanism instead of kill-based detection; atomic and race-free
- **Weekday bounds safety** — `busiestDayOfWeek` now guards against out-of-range weekday indices from non-Gregorian calendars
- **StatusChecker backoff jitter** — stored computed backoff instead of re-randomizing on every check (was undermining exponential backoff)
- **OAuthManager retry efficiency** — moved `URLRequest` construction outside the retry loop in `postToken()`

### Improved
- **Quarantine detection** — new `checkQuarantine()` alert on launch when macOS quarantine xattr is detected, with "Copy Fix Command" button
- **Update indicator moved to header** — "vX.Y.Z available" now shows below the title (yellow arrow icon + View link), matching "Up to date" placement; removed footer update banner
- **ClaudePaths static let** — converted computed `var` properties to stored `let` (avoids repeated URL construction)
- **TokenHealthMonitor single-pass** — new `assessSessions()` groups entries once, returns current + top N in a single pass (was doing two separate grouping passes)
- **UsageAggregator Date consolidation** — captured `Date()` and `Calendar.current` once at top of `aggregate()` instead of 5+ separate calls
- **SessionLogReader optimizations** — use prefetched `isDirectoryKey` instead of redundant stat; guard nonexistent subagents dirs; compact leftover Data slices to release backing buffer
- **UsageSnapshot weekday lookup** — replaced `DateFormatter` with `Calendar.current.weekdaySymbols` for busiest-day-of-week calculation

### Added
- `RateLimitFetcherTests` — 6 tests (cache expiry, stale marking, multi-account isolation)
- `StatsCacheReaderTests` — 12 tests (decode, caching, invalidation, full payload)
- `UsageAggregatorTests` — 8 tests (empty state, stats-only, JSONL-only, rate limit pass-through, model filtering, windowed tokens, deduplication)

## [1.2.1] — 2026-02-22

### Improved
- **Session carousel** — lower drag threshold (20pt) with velocity detection for snappier swipe navigation
- **VoiceOver session navigation** — added adjustable action (increment/decrement) for accessible session browsing
- **Empty chart placeholder** — icon + text instead of plain text label
- **Account switch reliability** — identity resolution now runs after stale-result guard, preventing unnecessary Keychain writes
- **PKCE state validation** — rejects missing or empty state parameters (previously only checked mismatches)
- **429 Retry-After** — OAuthManager now honors `Retry-After` header on rate-limited token requests
- Corrected README test counts to match actual (335 tests across 25 files)

### Removed
- **Settings export/import** — removed (OAuth tokens are Keychain-bound and can't be exported; a clipboard-only preferences backup wasn't useful)
- **Staleness indicator** — removed "Updated just now" label from popover footer (menu bar staleness dimming still works)

## [1.2.0] — 2026-02-22

### Added
- **Launch at login** via SMAppService
- **Click-to-copy** on stat values (percentages, tokens, costs) with clipboard icon feedback
- **Rate limit approaching alerts** with configurable threshold (50–95%, default 80%)
- **API cost estimation** — optional display of what token usage would cost at API rates
- **Adaptive polling** — polling interval doubles after 3 unchanged cycles (up to 5 min), resets on data change or file watcher trigger
- **Predictive rate limit estimate** — "~Xh Ym to limit" shown when utilization exceeds 50%, based on current burn rate
- **Usage projections** — trend arrow (↑/↓/→) comparing this week vs last, busiest day of the week
- **Session anomaly detection** — warnings for zero-output sessions, rapid token consumption, and stale idle sessions
- **JSONL corruption tracking** — counts and logs skipped/failed decode lines per scan
- **Batch notifications** — multiple alerts within 500ms combined into a single notification
- **Help tooltips** — `.help()` modifiers across all view sections for hover descriptions
- **Expanded session details** — hover tooltip shows full session info; stale sessions get amber "Idle Xm" badge
- **Swipe navigation** — horizontal drag gesture to browse between sessions in Context Health
- **Colorblind mode** — blue/cyan/amber/purple palette via centralized `ThemeColors`
- **First-launch tutorial** — 3-step walkthrough overlay (Rate Limits, Context Health, Settings)
- **Manual update check** — arrow button in header to force-check for new versions, with "Up to date" feedback
- **Update checker** — footer banner when new GitHub release available, with skip option
- **Tokens/Activity/Cost display toggles** in Settings
- **Smooth animations** for settings toggle, metric mode change, account switch, progress bars
- **VoiceOver accessibility** labels across all sections

### Improved
- **Exponential backoff with jitter** in StatusChecker (base 60s, doubles per failure, caps at 5 min, ±20% jitter)
- **429 retry handling** in OAuthManager token endpoint (parses `Retry-After` header)
- **Account identity timeout** — warns after 1 hour if pending identity hasn't resolved
- Removed organization name from menu bar and account picker — accounts now show user-editable display names only
- Cleaned up menu bar label to show only percentage and version
- CI now caches SPM dependencies and skips redundant builds
- Build script uses canonical Info.plist instead of inline heredoc
- Extended test coverage

## [1.1.0] — 2026-02-21

### Added
- **Multi-account support** — connect up to 2 Claude accounts (separate orgs) and switch between them from the header dropdown
- `AccountRecord` model and `AccountStore` service for per-account identity persistence
- Per-account Keychain token storage (prefixed entries: `accessToken_{accountId}`, etc.)
- Account picker dropdown in header — always visible, shows active account with switch and "Add Account" options
- Per-account name editing in Settings (replaces global Name/Org fields)
- Per-account rate limit caching and model fallback in `RateLimitFetcher`
- Pending identity resolution — new accounts start as `"pending-<UUID>"` and resolve to real org ID after first API call
- Duplicate account detection and merge (same org authed twice)
- Legacy migration — existing single-account Keychain entries automatically migrate to the new prefixed format
- Stale-result guard in `UsageViewModel` — discards API results if active account changed mid-flight
- 35 new unit tests (AccountRecord, AccountStore)

### Removed
- Manual refresh button from header (data refreshes automatically via polling + file watchers)

## [1.0.3] — 2026-02-20

### Fixed
- **Frequent logouts** — transient server errors (5xx) during token refresh no longer trigger logout; auth state is preserved and retried next cycle
- **"Server returned status 500" during auth** — token endpoint now retries up to 2 times with exponential backoff (1s, 2s) on 5xx errors
- **Clock-skew logouts** — access tokens now refresh 5 minutes before expiry, preventing 401s from timing mismatches
- **Concurrent refresh races** — multiple polling cycles seeing an expired token now share a single in-flight refresh instead of firing parallel requests
- **OAuth PKCE state reuse** — state parameter is now generated separately from the PKCE verifier (prevents verifier leakage via redirect URLs)
- **API 400 fallthrough** — non-model 400/404 errors no longer silently fall through to success with no data
- **DateFormatter locale safety** — fixed-format date formatters now use `en_US_POSIX` locale to prevent incorrect parsing on non-Gregorian calendars
- **Empty sessions crash** — TokenHealthSection now guards against empty session arrays
- **Zombie processes** — osascript notifications now reap child processes via background `waitUntilExit()`
- **Force-unwrap removals** — replaced remaining force-unwraps with safe alternatives

### Added
- `ClaudePaths` utility for centralized Claude Code file paths
- JSONL leftover buffer capped at 1MB (prevents unbounded memory growth from malformed data)
- `TokenHealthStatus.empty` placeholder for defensive code paths
- `SessionLogReader.makeUsageEntry(from:)` shared helper (DRY)
- `AuthError.serverError(Int)` with `isTransient` classification
- 23 new unit tests (ClaudePaths, APIFetchResult, UsageSnapshot, TokenFormatter boundaries, ModelNameMapper edge cases)

## [1.0.2] — 2026-02-18

### Added
- App icon — sparkle star matching the menu bar icon, generated at build time
- DMG volume icon for a polished install experience
- `scripts/generate-icon.swift` for reproducible icon generation

### Fixed
- Install instructions now include Gatekeeper approval steps (System Settings → Privacy & Security → Open Anyway)

## [1.0.1] — 2026-02-18

### Fixed
- Ad-hoc codesign the app bundle so macOS Keychain can identify the app — eliminates repeated Keychain access prompts on launch

### Removed
- Dead `KeychainReader.swift` (unused Claude Code API key reader)

## [1.0.0] — 2026-02-18

Initial public release.

- OAuth 2.0 authentication with PKCE (same protocol as Claude Code)
- Real-time rate limit monitoring (5-hour burst + 7-day sustained windows)
- Context health tracking across your 5 most recent sessions
- Per-model token breakdown (input, output, cache read, cache write)
- Activity charts (24H hourly, 7D daily, 12M monthly)
- Today's stats: messages, sessions, tool calls
- System status integration via status.claude.com
- Outage notifications for Claude.ai and Claude Code (via osascript)
- VoiceOver accessibility labels on all interactive elements
- Structured logging via os.Logger
- Unit test suite with ~130 test cases
- GitHub Actions CI (build → test → bundle)
