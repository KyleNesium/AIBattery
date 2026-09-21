# Architecture

## App Entry Point

```
@main AIBatteryApp: App
  └─ AppDelegate (NSApplicationDelegateAdaptor)
       └─ StatusBarManager.setup(viewModel:oauthManager:)
            ├─ NSStatusItem: native button with a single combined button.image (text + star baked in)
            └─ PopoverPanel (floating NSPanel, borderless)
                 └─ NSHostingView → PopoverContentView (controlBackgroundColor background)
                      └─ Group { UsagePopoverView | AuthView }
```

`StatusBarManager` owns the `NSStatusItem` and a floating `NSPanel` directly, bypassing SwiftUI's `MenuBarExtra`. The panel uses `hidesOnDeactivate = false`, `isFloatingPanel = true`, and `.statusBar` window level so it stays open regardless of focus changes — only closes on status item click or Escape.

Single `UsageViewModel` owns all state. Views read `viewModel.snapshot`.

Auth gating: `isAuthenticated` drives whether UsagePopoverView or AuthView is shown. Multi-account add-account flow is handled inline by UsagePopoverView (shows AuthView as overlay, parameterised by `AIProvider`).

**Two providers, one pipeline.** Every account carries an `AIProvider` (`.claude` / `.codex`). The architecture is "provider seams on the existing pipeline" (design spec `docs/superpowers/specs/2026-09-02-codex-support-design.md`): one `AccountStore`, one `UsageViewModel`, one `UsageSnapshot`/UI. Provider dispatch happens at exactly these boundaries, always keyed off the **active account's provider**:

| Boundary | Claude | Codex |
|---|---|---|
| Auth | `OAuthManager` paste-code PKCE flow | `CodexAuthSession` + `CodexCallbackServer` (localhost:1455 redirect) + `CodexTokenClient`; one-click `CodexAuthFileImporter` from `~/.codex/auth.json` |
| Token storage | Keychain `refreshToken_<accountId>` | Keychain `refreshToken_codex_<accountId>` (`OAuthManager.tokenStorageKey`) |
| Rate limits | `RateLimitFetcher` (`/api/oauth/usage` → probes) | `CodexRateLimitFetcher` (`chatgpt.com/backend-api/wham/usage` → `CodexSessionRateLimitScanner` session-log fallback), with per-account endpoint backoff |
| Local data | `SessionLogReader` (`~/.claude/projects`) + `StatsCacheReader` | `CodexSessionLogReader` (`~/.codex/sessions`, no stats cache) — both implement `UsageEntrySource` |
| Aggregation | `UsageAggregator(provider: .claude)` | `UsageAggregator(provider: .codex)` — same class, `gpt-` model filter, JSONL-derived `firstSessionDate` |
| Pricing / names / context | Claude tables | `OpenAIModelPricing`, `gpt-` branch in `ModelNameMapper`, `TokenHealthConfig.openAIDefaultContextWindow` |
| Status feed | `StatusChecker.shared` (`StatusFeedConfig.claude`) | `StatusChecker.codex` (`StatusFeedConfig.codex`, filtered to Codex components) |
| File watching | FSEvents on `~/.claude/projects` + DispatchSource on `stats-cache.json` | second FSEvents root on `~/.codex/sessions` |
| UI vocabulary | "7-Day", ✦ glyph, `claude.ai/settings/usage`, `status.claude.com` | "Weekly", ⬡ glyph, `chatgpt.com/codex/settings/usage`, `status.openai.com` |

Local logs are machine-wide per provider: every Codex account shows the same `~/.codex/sessions` analytics (exactly as multiple Claude accounts share `~/.claude`).

## Data Flow

```
                         ┌──────────────────┐
                         │  UsageViewModel   │  active account → AIProvider
                         │  (refresh loop)   │
                         └────────┬─────────┘
                                  │ dispatch by provider
        ┌─────────────────────────┼─────────────────────────┐
        ▼                         ▼                         ▼
 RateLimitFetcher /        StatusChecker.shared /    UsageAggregator(.claude) /
 CodexRateLimitFetcher     StatusChecker.codex       UsageAggregator(.codex)
 → APIFetchResult          (status.claude /          (merge local data → UsageSnapshot.provider)
   (rateLimits +           status.openai, filtered)          │
    provider tag)                              ┌─────────────┴─────────────┐
                                               ▼                           ▼
                                   Claude: StatsCacheReader +    Codex: CodexSessionLogReader
                                           SessionLogReader              (~/.codex/sessions JSONL)
                                           (~/.claude)
```

`refresh()` runs: gets active account + token from `OAuthManager`, resolves the account's provider once, and passes the token to that provider's fetcher (`RateLimitFetcher.fetch` or `CodexRateLimitFetcher.fetch`). The provider's status check runs concurrently. After fetch, Claude accounts resolve pending identity / update metadata (Codex identities are fixed at auth time from the ID token). Aggregation runs off-main in the provider's aggregator; `UsageSnapshot.provider` tells the views which vocabulary and links to use.

## Refresh Triggers

| Trigger | Interval | Source | Scope |
|---------|----------|--------|-------|
| Timer | refreshInterval (default 120s, user-configurable 30–300s) | UsageViewModel.pollingTimer | Full `refresh()` (network + aggregation) |
| Stats cache write | 2 sec debounce | FileWatcher (DispatchSource on stats-cache.json) | **Local-only** `refreshLocalData()` — re-aggregates JSONL with the currently displayed rate limits; no network fetch, no poll-timer reset |
| JSONL file change | 2 sec FSEvent latency | FileWatcher (FSEventStream on ~/.claude/projects/) | **Local-only** `refreshLocalData()` (same as above) |
| Codex rollout write | 2 sec FSEvent latency | FileWatcher (second FSEventStream on ~/.codex/sessions/, only when the directory exists) | **Local-only** `refreshLocalData()` — invalidates only `CodexSessionLogReader` |
| Fallback | 60 sec | FileWatcher fallback timer | **Local-only** `refreshLocalData()` (same as above) |
| Account switch | On click | Account picker in header | Full `refresh()` |
| Sleep/wake | Immediate on wake | NSWorkspace.willSleepNotification / didWakeNotification | Full `refresh()` (after cached instant-paint) |
| Network recovery | On connectivity restored | NetworkMonitor (NWPathMonitor) | Full `refresh()` |
| Adaptive extension | Doubles interval (up to 5 min) after 3 unchanged cycles; local JSONL changes since the last poll count as "changed" so active use never backs off | AdaptivePollingState | Timer cadence only |

## Project Tree

```
AIBatteryApp/
  AIBatteryApp.swift              — @main, imports AIBatteryCore, AppDelegate + Settings { EmptyView() }, initializes StatusBarManager
AIBattery/
  Info.plist                      — LSUIElement = YES (no Dock icon)
  AIBattery.entitlements          — Direct-download entitlements (sandbox disabled)
  AIBattery-AppStore.entitlements — App Store entitlements (sandbox + network.client + .claude/ read)
  PrivacyInfo.xcprivacy           — Privacy manifest (UserDefaults + FileTimestamp API declarations)
  Models/
    AIProvider.swift              — `.claude` / `.codex` enum: display name, glyph (✦ / ⬡), secondary-window label ("7-Day" / "Weekly")
    AccountRecord.swift           — Per-account identity record (Codable, Identifiable); `provider` decodes as `.claude` for pre-Codex records
    APIFetchResult.swift          — Combined result from a single Messages API call
    APIProfile.swift              — Organization info from API response headers
    RateLimitUsage.swift          — Unified rate limit header parsing (5h/7d windows); provider tag + optional window minutes (Codex payloads)
    CodexUsageParser.swift        — Parses `wham/usage` JSON and session-log `rate_limits` snapshots into RateLimitUsage
    OpenAIModelPricing.swift      — `gpt-5.x` pricing table (longest-prefix match on the raw model ID)
    StatsCache.swift              — Codable for stats-cache.json
    SessionEntry.swift            — Codable for JSONL lines + AssistantUsageEntry
    UsageSnapshot.swift           — UsageSnapshot (carries `provider`), ModelTokenSummary
    ProjectTokenSummary.swift     — Per-project token totals + cost from JSONL cwd
    MetricMode.swift              — MetricMode enum (5h / 7d / context)
    TrendDirection.swift          — TrendDirection enum (up / down / flat)
    ClaudeSystemStatus.swift      — ClaudeSystemStatus (provider-neutral despite the name), StatusIndicator, StatusComponent
    TokenHealthConfig.swift       — Health thresholds + context window lookup
    TokenHealthStatus.swift       — HealthBand, HealthWarning, TokenHealthStatus (Identifiable by sessionId)
    ModelPricing.swift            — Per-model pricing lookup + cost calculation
    LocalUsageEstimate.swift      — Fallback token estimation when unified headers unavailable (calibration + plan tier)
    PlanTier.swift                — Claude plan tiers (Pro/Max 5×/Max 20×/Team) with estimated 5h/7d limits
    RateLimitSource.swift         — Enum tracking where rate limit data came from (API / local estimate / standard)
    StandardRateLimits.swift      — Standard per-model request/token rate limits from API headers
  Services/
    AccountStore.swift            — Multi-account registry (UserDefaults persistence, max 3 per provider; Claude-first `displayOrdered`)
    OAuthManager.swift            — OAuth 2.0 PKCE flow, auto-refresh; `postToken` is `nonisolated static` so the network call releases MainActor cleanly. Concurrent-refresh serialization preserved via `refreshTasks[accountId]`
    OAuthManager+Codex.swift      — Codex provider routing: `tokenStorageKey`, `startCodexAuthFlow` / `completeCodexAuthFlow` / `cancelCodexAuthFlow`, `registerCodexAccount` (cap-guarded, returns Result)
    CodexOAuth/
      CodexOAuthConstants.swift   — client-id, port 1455, scopes, authorize/token URLs lifted from codex-rs
      CodexAuthSession.swift      — In-flight PKCE state + `OneShotMailbox` (buffers a redirect that lands before the UI awaits it)
      CodexCallbackServer.swift   — One-shot NWListener on 127.0.0.1:1455, parses the OAuth redirect (`CodexCallbackParser`)
      CodexTokenClient.swift      — Code exchange (form-encoded) + refresh (JSON) against auth.openai.com
      CodexAuthFileImporter.swift — Read-only import of `~/.codex/auth.json` (ChatGPT mode only) to seed the first Codex account
    CodexRateLimitFetcher.swift   — `chatgpt.com/backend-api/wham/usage` fetch, per-account cache/persistence (`aibattery_codexRateLimits_`), auth-failure counter, endpoint backoff, session-log fallback
    CodexSessionRateLimitScanner.swift — Tail-scans the newest rollout for the last `rate_limits` snapshot (fallback source, always `isCached`)
    UsageEntrySource.swift        — Protocol both session-log readers implement (readAllUsageEntries / invalidate / lastCorruptLineCount)
    CodexSessionLogParser.swift   — Per-file state machine: session_meta → identity, turn_context → model, token_count.last_token_usage → AssistantUsageEntry
    CodexSessionLogReader.swift   — Streaming reader over `~/.codex/sessions/YYYY/MM/DD/*.jsonl` (fingerprint cache, eviction, symlink boundary)
    OpenAIStatusFeed.swift        — `StatusFeedConfig.codex`: status.openai.com filtered to the five Codex components
    OAuthTokenStorage.swift       — Keychain (refresh token) + UserDefaults (expiry) persistence layer extracted from OAuthManager
    RateLimitFetcher.swift        — Main orchestration: `fetch()` entry point, `cachedOrEmpty` / `setCachedResult` public API, observed/working-model bookkeeping, Messages-API path (`buildHeaderResult` + `tryFetch`), and the pure helpers `parseRetryAfter` / `quotaThrottleLikely` (`nonisolated static`)
    RateLimitFetcher+UsageEndpoint.swift  — Dedicated `/api/oauth/usage` primary path: `interpretUsageEndpoint` (pure) + async `fetchUsageEndpoint` wrapper
    RateLimitFetcher+ClientData.swift     — Claude Code `/api/oauth/claude_cli/client_data` fallback path: `interpretClaudeCodeClientData` (pure), async `fetchClaudeCodeClientData` wrapper, and `containsStandardRateLimitHeaders` (`nonisolated static`, called from the Messages path too)
    RateLimitFetcher+Persistence.swift    — UserDefaults-backed per-account cache: `PersistedRateLimits` (file-private), `persistRateLimits` (called by `fetch` on success), `restorePersistedRateLimits` (called from init; runs `withClearedExpiredWindows()` so a stale `"throttled"` flag from before a long absence is dropped)
    StatsCacheReader.swift        — Reads + decodes stats-cache.json
    SessionLogReader.swift        — Claude JSONL streaming reader (FileHandle, 64KB chunks)
    FileWatcher.swift             — DispatchSource + two FSEventStreams (~/.claude/projects, ~/.codex/sessions) for live updates
    UsageAggregator.swift         — Merges a provider's data sources → UsageSnapshot (one instance per provider)
    TokenHealthMonitor.swift      — Analyzes session tokens → health status (single + top N sessions)
    TokenLedger.swift             — Persistent per-model token high-water marks (Application Support)
    NetworkMonitor.swift          — NWPathMonitor connectivity observer (triggers refresh on recovery)
    StatusChecker.swift           — Feed-configurable Statuspage client (`StatusFeedConfig`; `.shared` = Claude, `.codex` = OpenAI); HTTP fetch + decode + parse via `nonisolated static func fetchAndParse(config:timeout:)` returning a `Sendable FetchOutcome`; optional component filter
    SingleInstanceGuard.swift     — POSIX flock single-instance guard, SIGTERM handler
    NotificationManager.swift     — Status outage + rate limit alerts via UNUserNotificationCenter
    LaunchAtLoginManager.swift    — SMAppService launch-at-login toggle
    VersionChecker.swift          — GitHub Releases update checker (24h cadence)
    SparkleUpdateService.swift     — Sparkle 2 wrapper for user-initiated auto-update
    SparkleUpdateDelegate.swift   — SPUUpdaterDelegate: error tracking + update cycle logging
  ViewModels/
    UsageViewModel.swift          — @MainActor ObservableObject, single source of truth (state + init + refresh orchestration + throttle bookkeeping + deinit); owns one `UsageAggregator` per provider and routes every fetch/aggregate/status call by the active account's provider
    UsageViewModel+Statics.swift  — `nonisolated static` pure helpers: refresh-interval clamping, error-message string, change detection, TTL-guarded effective rate-limits / values
    UsageViewModel+Lifecycle.swift — File watcher setup, sleep/wake/screen-lock observers, idle-suspend + activity-monitor resume, polling timer (start/restart/updateInterval)
    UsageViewModel+FanOut.swift   — Thin wrapper: `scheduleFanOut` + `fetchAllAccounts(seed:)` delegate to `MultiAccountFanOut.resolve` and assign the result to `perAccountRateLimits`
    MultiAccountFanOut.swift      — Multi-account fan-out orchestration (`ProviderDispatchingFetcher` routes each account to its provider's fetcher) (toggle-gated, coalesced, seeded to avoid an N+1 fetch) + the `RateLimitFetching` / `MultiAccountTokenProviding` dependency seams (singletons in prod, mocks in tests) + the shared `multiAccountDisplayIDs` filter (non-pending AND authenticated). Standalone, not a `UsageViewModel` method, so it's unit-tested end-to-end without spinning up the VM's timers/watchers.
  Views/
    StatusBarManager.swift        — NSStatusItem + floating NSPanel core: stored state, setup (observers/monitors/panel construction), deinit. Split per the UsageViewModel precedent; shared state declared non-private for cross-file extensions
    StatusBarManager+ButtonUpdate.swift — Menu-bar image rendering (`updateButton`), `MenuBarRenderKey` render-skip (image rebuilt only when text/percent-bucket/color/broken/sparkle/appearance changed), recovery sparkle
    StatusBarManager+Countdown.swift — Adaptive countdown ticker (1s/10s) + pure `countdownResetDate(for:now:)` reset selection
    StatusBarManager+Panel.swift  — Panel toggle/positioning (shared `buttonScreenRect`), `PopoverPanel`, `PopoverContentView`, `TransparentHostingView`
    MenuBarIcon.swift             — 4-pointed star NSImage (static): usage-band glow, broken star (throttled), recovery sparkle; quantized cache
    MenuBarIconGeometry.swift     — Star path geometry helpers (starPath, multiPointStarPath) + NSBezierPath→CGPath
    MenuBarMultiAccountText.swift — Pure builder for multi-account menu bar text (`42% | 23%`); worst-account percent + throttle + reset selection. Unit-tested without AppKit.
    UsagePopoverView.swift        — Thin popover orchestrator: wires sub-views via init params, owns state
    PopoverHeaderView.swift       — Header row, account picker, update banner (ENABLE_VERSION_CHECKER)
    MetricToggleView.swift        — Segmented metric picker + auto mode button + ordered modes cache
    PopoverStateViews.swift       — PopoverErrorView, PopoverEmptyView, PopoverIdleFilteredView
    PopoverFooterView.swift       — Footer links (provider-aware Usage/Status targets), logout confirm, status indicator, timestamp
    UsageGateViews.swift          — ProjectUsageGate, InsightsGate — data-availability wrappers
    Settings/
      SettingsRow.swift           — Inline settings container: account names + sub-sections
      RefreshSettingsSection.swift — Refresh interval slider + sliderMarks() helper
      DisplaySettingsSection.swift — Display toggles + idle session cutoff slider
      AlertSettingsSection.swift  — Status alerts + rate limit alerts
      LaunchAtLoginSection.swift  — Launch at Login toggle
    AuthView.swift                 — OAuth login screen, parameterised by provider: Claude paste-code flow / Codex browser round-trip + "Import Codex CLI login"
    TutorialOverlay.swift         — First-launch 3-step walkthrough overlay
    Components/
      GaugeBar.swift              — Reusable progress gauge bar (single GeometryReader, clamps percent 0–100, uses Layout + ThemeColors)
      GaugeRow.swift              — Shared "labelled gauge row" shell: VStack[Header HStack + GaugeBar + TimelineView footer]. Accepts headerLeading / headerTrailing / footer ViewBuilders. Owns accessibility wiring and timeline schedule. Backs UsageBar (5h/7d) and StandardLimitBar.
      LinkActionButton.swift      — Inline link-styled action button (Size.standard for settings, .compact for in-banner). One canonical implementation for Add Account, Test, Download, Install Update — all routed through ThemeColors.action with consistent icon/label spacing.
    UsageBarsSection.swift        — FiveHourBarSection + SevenDayBarSection rate limit bars; UsageBar.AlarmState gates throttle/limit alarm on confirmed (fresh) data
    LocalEstimateSection.swift    — Local token estimate display when unified headers unavailable (window label follows provider vocabulary)
    StandardLimitsSection.swift   — Standard per-model API rate limit display (fallback)
    TokenHealthSection.swift      — Context health gauge + warnings + multi-session chevron toggle
    TokenHealthSessionInfo.swift  — Session detail computation: label parts, tooltip, idle detection, time formatting, clipboard export
    ProjectUsageSection.swift     — Per-project token breakdown with cost (top 5 default, expand to 10)
    ActivityChartView.swift        — InsightsView core: struct declaration, @State/@AppStorage, cache logic, fingerprinting, and body
    InsightsCharts.swift           — extension InsightsView: areaGradient, chartLineStyle, sharedYAxis, dailyChart, hourlyChart, monthlyChart
    InsightsTrendCostSection.swift — extension InsightsView: trendSummary, trendRowTop/Bottom, windowedModelTokens, costSection
    InsightsRowsAndHover.swift     — extension InsightsView: insightRows, hover helpers, static formatters (formatHourLabel, compactCount, monthAbbrev)
    ActivityChartData.swift       — Chart data transformation layer (daily/hourly/monthly points)
    ActivityChartTrend.swift      — Trend computation: vs-yesterday/week/month comparisons + copy text
    CollapsibleSectionHeader.swift — Shared collapsible header with rotating chevron, used by 3 sections (Context, Projects, Insights)
    StyledDivider.swift            — Standardized divider: Divider() at 0.3 opacity, Spacing.tight vertical padding
    FooterLink.swift              — Footer link button with hover underline and external arrow
    RefreshButton.swift           — Refresh button with brief spin animation
    CopyableText.swift            — ViewModifier for click-to-copy: full CopyableModifier + lightweight LightCopyableModifier for dense areas
    MarqueeText.swift             — News-ticker scrolling text, supports multi-text cycling with cross-fade
  Utilities/
    TokenFormatter.swift          — Format tokens ("18.9M")
    ModelNameMapper.swift         — "claude-opus-4-6-20250929" → "Opus 4.6"; "gpt-5.6-sol" → "GPT-5.6 Sol"
    UserDefaultsKeys.swift        — Centralized @AppStorage / UserDefaults key constants
    DateFormatters.swift          — Shared DateFormatter / ISO8601DateFormatter instances (allocated once)
    AdaptivePollingState.swift    — Pure struct state machine for adaptive polling interval logic
    AppLogger.swift               — Structured os.Logger instances by category
    ClaudePaths.swift             — Centralized file paths for all Claude Code data locations
    CodexPaths.swift              — `~/.codex/sessions`, `~/.codex/auth.json` (read-only)
    JWTDecoder.swift              — Unverified-claims decode of the Codex ID/access token (account id, expiry)
    OAuthPKCE.swift               — Shared PKCE S256 verifier/challenge + state generation for both providers
    AppPaths.swift                — AIBattery's own Application Support directory (shared by SingleInstanceGuard + TokenLedger)
    SecureNetworking.swift        — Ephemeral URLSession + response size guard (2 MB limit) + resource timeout (30s)
    DurationFormatter.swift       — Compact time duration formatting ("2h 5m", "1d 1h", "soon")
    ThemeColors.swift             — Centralized color theming with colorblind-safe palette
    ThrottleTracker.swift         — Pure value type tracking throttle event transitions for trend display
    IdleSuspendPolicy.swift       — Pure idle-suspension policy (5-min threshold) — used by UsageViewModel to skip polling when machine idle
    Typography.swift              — Named font style tokens (sectionHeader, monoValue, tinyLabel, decorativeIcon, etc.) — caseless enum namespace
    Spacing.swift                 — Spacing/Layout/MotionConstants enums — caseless enum namespaces co-located
    KeychainHelper.swift          — Low-level macOS Keychain CRUD (extracted from OAuthManager)
    RetryPolicy.swift             — Pure value-type exponential-backoff + jitter policy with `nonisolated static` API. 4 presets (`oauth`, `statusCheck`, `fileWatch`, `rateLimit`) carry historical values from CONSTANTS.md. Used by OAuthManager, StatusChecker, FileWatcher, RateLimitFetcher
Tests/AIBatteryCoreTests/
  MetricToggleViewTests.swift     — orderedModes ordering, allCases completeness, stable remaining order
  Utilities/
    TokenFormatterTests.swift     — format() for 0, 500, 1K, 2.5K, 15K, 1M, 3.2M, 150M, 1B, 3.2B, 10B + negatives + boundaries
    ModelNameMapperTests.swift    — displayName() for all model families, edge cases, empty, multi-hyphens
    UserDefaultsKeysTests.swift   — prefix validation, uniqueness
    ClaudePathsTests.swift        — path suffixes, URL↔path consistency, absolute paths
    ThemeColorsTests.swift        — Color theme tests (both modes, all bands)
    DateFormattersTests.swift     — format strings, round-trips, locale pinning
    AdaptivePollingStateTests.swift — threshold, doubling, cap, reset, constants
    SecureNetworkingTests.swift   — Ephemeral session config, singleton, size limit constant
    DurationFormatterTests.swift  — compact format, boundaries, days/hours/minutes
    RetryPolicyTests.swift        — exponential growth at multiple multipliers, cap behaviour, jitter bounds (200-sample fuzz), Retry-After parsing edge cases, preset value pinning, parity tests against pre-refactor OAuth/StatusCheck/FileWatch formulas
    ThrottleTrackerTests.swift    — Throttle transition detection, timestamp parsing, pruning, counting
    IdleSuspendPolicyTests.swift  — idle threshold, suspend policy edge cases
    MenuBarIconTests.swift        — cache key collisions, cache identity, boundary values
    SpacingTests.swift            — spacing constant values
    TypographyTests.swift         — typography token values
  Models/
    AccountRecordTests.swift      — Codable round-trip, pending identity, equatable
    MetricModeTests.swift         — rawValues, labels, allCases
    RateLimitUsageTests.swift     — parse() with full/partial/missing headers; computed properties
    APIProfileTests.swift         — parse() with both/one/no headers
    APIFetchResultTests.swift     — defaults, explicit cached flag, profile preservation
    TokenHealthConfigTests.swift  — contextWindow() exact/prefix/fallback; default thresholds
    StatsCacheTests.swift         — DailyActivity.parsedDate, LongestSession.durationFormatted, Codable round-trip
    ModelTokenSummaryTests.swift  — totalTokens sum
    ProjectTokenSummaryTests.swift — totalTokens sum
    TokenHealthStatusTests.swift  — suggestedAction per band, HealthBand rawValues
    SessionEntryTests.swift       — Codable decode from real JSONL, minimal entry, round-trip
    UsageSnapshotTests.swift      — totalTokens, percent(for:), projections, trends, busiest day
    ModelPricingTests.swift       — pricing lookup, cost calculation, formatCost, edge cases
    ClaudeSystemStatusTests.swift — status indicator parsing, severity, display names
    StandardRateLimitsTests.swift — standard rate limit header parsing + computed properties
    LocalUsageEstimateTests.swift — calibration band policy, predictive estimate thresholds
  Services/
    AccountStoreTests.swift       — Add/remove/update/merge, persistence, migration
    StatusIndicatorTests.swift    — from() all status strings, severity ordering, displayName
    StatusCheckerParsingTests.swift — incident impact escalation, component ID constants
    StatusCheckerConcurrencyTests.swift — nonisolated `fetchAndParse` callable from detached task; doesn't block MainActor
    SessionLogReaderTests.swift   — SessionEntry decoding, AssistantUsageEntry construction
    SessionLogReaderSymlinkTests.swift — Symlink boundary check (exclude outside, include inside)
    SessionLogReaderDiscoveryTests.swift — TTL-based discovery fallback, cache expiry
    SessionLogReaderIntegrationTests.swift — End-to-end JSONL scanning + merge behavior
    CodexSessionLogParserTests.swift — Codex rollout line state machine + AssistantUsageEntry field mapping (real-fixture lines)
    CodexSessionLogReaderTests.swift — Nested date-dir discovery, fingerprint cache, eviction, deletion, partial tail, symlink boundary
    CodexRateLimitFetcherTests.swift / CodexRateLimitFetcherBackoffTests.swift — wham/usage interpretation, spike write-back, endpoint backoff
    CodexSessionRateLimitScannerTests.swift — session-log rate_limits fallback
    CodexAuthFileImporterTests / CodexCallbackParserTests / CodexOAuthConstantsTests / CodexTokenClientTests / OAuthManagerCodexRoutingTests / OneShotMailboxTests — Codex auth pieces
    StatusCheckerComponentFilterTests.swift / OpenAIStatusFeedTests.swift — feed config + Codex component filter
    TokenHealthMonitorTests.swift — band classification, overflow guards, turn warnings, velocity, rapid consumption, custom config
    TokenLedgerTests.swift        — high-water-mark merge, historical model restoration, per-account isolation, persistence, sort, file size guard
    NotificationManagerTests.swift — shouldAlert() pure function threshold tests
    VersionCheckerTests.swift     — semver comparison, tag stripping, cache behavior, persistence
    SparkleUpdateServiceTests.swift — Sparkle configuration verification via the never-started testable init (auto-check disabled; NEVER touches .shared — a started updater's failure alert hangs the suite)
    RateLimitFetcherTests.swift   — cache expiry, stale marking, multi-account isolation, Retry-After parsing, pending→resolved cache migration + launch orphan pruning
    RateLimitFetcherConcurrencyTests.swift — nonisolated header helpers (`parseRetryAfter`, `quotaThrottleLikely`) callable + actor-independent
    StatsCacheReaderTests.swift   — decode, caching, invalidation, full payload, file size guard
    UsageAggregatorTests.swift    — empty state, stats-only, JSONL-only, model filtering, dedup, project grouping
    UsageAggregatorIntegrationTests.swift — Full pipeline integration tests
    OAuthManagerTests.swift       — AuthError user messages, transient error classification
    OAuthManagerConcurrencyTests.swift — `postToken` callable from detached task; TokenResult/AuthError Sendable conformance; `isTransient` classifier pins the auth-vs-transient invariant; 10 concurrent `getAccessToken` calls don't deadlock
  ViewModels/
    UsageViewModelTests.swift     — Refresh interval clamping, error messages, effective value guard
    UsageViewModelIdleTests.swift — Idle threshold constants, suspend policy
    MultiAccountFanOutTests.swift — Fan-out orchestration (seed dedup, toggle-off clear, missing-token skip) + eligible-account filter
  Views/
    ActivityChartDataTests.swift  — 5H/7D/12M chart data transforms
    ActivityChartIsEmptyTests.swift — Empty state detection for chart modes
    ActivityTrendTests.swift      — Token-based trend computation (vs-yesterday/week/month)
    DeferredRenderingTests.swift  — Deferred rendering state machine
    GaugeBarTests.swift           — Percent clamping, bar rendering edge cases
    UsageBarAlarmStateTests.swift — Popover bar throttle/limit alarm gated on confirmed data (no false "Limit reached" on cached)
    InsightsViewFormatterTests.swift — Insights section formatting helpers
    SessionInfoFormatterTests.swift — Session detail formatting, idle detection, time
    StatusBarToggleTests.swift    — Status bar show/dismiss state transitions
    StatusBarCountdownResetDateTests.swift — Countdown reset-date selection (throttle/100%)
    MenuBarMultiAccountTextTests.swift — Multi-account text builder + display resolver
    LinkActionButtonTests.swift   — Link action button behavior
    PopoverFooterStatusSymbolTests.swift — Footer status symbol mapping
    MoveTransitionBanTests.swift  — Guards against `.move(edge:)` transitions in the popover
.github/workflows/
  ci.yml                          — Build + test + bundle on push/PR (macos-15)
  lint.yml                        — SwiftFormat + SwiftLint on PRs targeting main (macos-15)
  release.yml                     — Release: build → GitHub Release → update Homebrew cask (macos-15)
scripts/
  build-app.sh                    — Build release binary + .app bundle + zip/dmg
  update-homebrew.sh              — Auto-update KyleNesium/homebrew-tap cask (version + SHA256)
  generate-appcast.sh            — Generate appcast.xml for Sparkle update feed
  generate-icon.swift             — Generate AppIcon.icns (sparkle star, all macOS sizes)
  verify-release.sh               — Pre-release verification checks
project.yml                       — XcodeGen project spec (optional, SPM is primary)
Package.swift                     — SPM manifest: AIBatteryCore, AIBattery, AIBatteryCoreTests
CHANGELOG.md                      — Release notes per version
```

## Build Configuration

- **SPM**: swift-tools-version 6.0, Swift 5 language mode (`.swiftLanguageMode(.v5)`) with the `StrictConcurrency` upcoming feature on all targets, 3 targets: AIBatteryCore (library), AIBattery (executable), AIBatteryCoreTests (tests). (The `.v6` language-mode flip is deferred — it surfaces SDK-version-dependent isolation/data-race errors on the CI runner that don't appear on newer local SDKs, so it needs iterative CI validation in its own PR.)
- **Platform**: macOS 13+ (Ventura)
- **Sandbox**: Disabled (needs Keychain + filesystem access)
- **Codesigning**: Ad-hoc by default (`codesign --sign -`), parameterized via `CODE_SIGN_IDENTITY` env var for Developer ID signing. Hardened runtime (`--options runtime`), entitlements embedded, bundle identifier sealed — gives the app a stable identity for Keychain ACL whitelisting. Entitlements file selected automatically (`AIBattery-AppStore.entitlements` when `APP_STORE_BUILD` is set)
- **Notarization**: Optional — when `APPLE_ID` + `APPLE_TEAM_ID` + `APPLE_APP_PASSWORD` env vars are set, `build-app.sh` submits to `notarytool`, staples the ticket, and re-packages zip/DMG. Skipped when unset (current default)
- **App icon**: Generated at build time via `scripts/generate-icon.swift` (sparkle star, all macOS sizes). Embedded in `Contents/Resources/AppIcon.icns` and used as DMG volume icon.
- **Dock icon**: None (LSUIElement = true)
- **Dependencies**: Sparkle 2 (SPM, auto-update framework) — all other dependencies are Apple frameworks only (SwiftUI, Charts, Security, Foundation, AppKit, ServiceManagement)
- **Compiler flag**: `ENABLE_SPARKLE` — defined in all 3 SPM targets via `swiftSettings`. Guards all Sparkle imports/usage. Remove the define to build without Sparkle (App Store variant)
- **Compiler flag**: `ENABLE_VERSION_CHECKER` — defined in all 3 SPM targets. Guards VersionChecker + update UI. Remove to build App Store variant (guideline 3.1.1)
- **Compiler flag**: `APP_SANDBOX` — NOT defined by default. Reserved for future App Store sandbox support. Only set for App Store builds
- **Privacy manifest**: `PrivacyInfo.xcprivacy` bundled as SPM resource, also copied to `Contents/Resources/` by build script

## Release Pipeline

1. Tag a version: `git tag v1.x.x && git push --tags`
2. `release.yml` builds the app, creates a GitHub Release with `.zip` and `.dmg`
3. `scripts/generate-appcast.sh` generates `appcast.xml` with EdDSA signature, pushes to `gh-pages` branch (requires `SPARKLE_EDDSA_KEY` repo secret)
4. `scripts/update-homebrew.sh` auto-updates `KyleNesium/homebrew-tap` — downloads the zip, computes SHA256, commits updated cask formula
5. Requires `HOMEBREW_TAP_TOKEN` and `SPARKLE_EDDSA_KEY` repo secrets (GitHub PAT with `repo` scope for the homebrew-tap repo; Sparkle EdDSA private key for appcast signing)
6. Optional: `CODE_SIGN_IDENTITY`, `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_PASSWORD` secrets enable Developer ID signing + notarization (no-op when unset)

**Important**: Every release must update the Homebrew cask. The automation handles this when the secret is configured.

## Network Calls (exhaustive)

**Claude accounts**

1. `GET https://api.anthropic.com/api/oauth/usage` — **primary** rate-limit fetch (dedicated usage endpoint, no model probe needed; first call every cycle)
2. `GET https://api.anthropic.com/api/oauth/claude_cli/client_data` — Claude Code usage windows + account metadata (fallback)
3. `POST https://api.anthropic.com/v1/messages?beta=true` — legacy unified/public rate-limit headers + org profile (probe fallback, ~10% hit rate)
4. `GET https://status.claude.com/api/v2/summary.json` — system status (every refresh interval)
5. `POST https://console.anthropic.com/v1/oauth/token` — OAuth token exchange + auto-refresh
6. `GET https://claude.ai/oauth/authorize` — OAuth login (opens in browser, one-time)
7. `GET https://api.github.com/repos/KyleNesium/AIBattery/releases/latest` — update check (once per 24h)
8. `GET https://kylenesium.github.io/AIBattery/appcast.xml` — Sparkle update feed (on user-initiated update check)

**Codex accounts** (only when a Codex account exists / is active)

9. `GET https://chatgpt.com/backend-api/wham/usage` — Codex rate limits (`Authorization: Bearer`, `ChatGPT-Account-Id`); per-account exponential backoff on failure, session-log fallback
10. `GET https://status.openai.com/api/v2/summary.json` — OpenAI system status, filtered to Codex components (every refresh interval while a Codex account is active)
11. `GET https://auth.openai.com/oauth/authorize` — Codex OAuth login (opens in browser, one-time; redirects to `http://localhost:1455/auth/callback`)
12. `POST https://auth.openai.com/oauth/token` — Codex token exchange + auto-refresh

## Local File Access (exhaustive)

1. macOS Keychain, service `"AIBattery"` — Per-account OAuth refresh token only (`refreshToken_{accountId}` for Claude, `refreshToken_codex_{accountId}` for Codex); access token held in memory, expiry in UserDefaults
2. UserDefaults `aibattery_accounts` + `aibattery_activeAccountId` — Multi-account registry (JSON-encoded [AccountRecord])
3. `~/.claude/stats-cache.json` — historical usage (daily activity, model totals, peak hours)
4. `~/.claude/projects/*/[session-id].jsonl` — per-message token data
5. `~/.claude/projects/*/subagents/*.jsonl` — subagent session data
6. `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl` — Codex CLI rollouts, **token counts only** (`session_meta`, `turn_context`, `token_count`; `response_item` content is never decoded)
7. `~/.codex/auth.json` — read once, on the user's explicit "Import Codex CLI login" click (never watched, never written)
8. UserDefaults `aibattery_codexRateLimits_{accountId}` — persisted Codex rate-limit snapshot (mirror of `aibattery_rateLimits_`)

## App Store Distribution (Future — Blockers)

Not currently planned, but documented here for reference. These are the architectural changes required before an App Store submission would be possible.

| Blocker | Impact | Status |
|---------|--------|--------|
| App Sandbox | Can't read `~/.claude/` — App Store requires sandbox | `AIBattery-AppStore.entitlements` has `user-selected.read-only` + `bookmarks.app-scope`; needs NSOpenPanel + bookmark persistence implementation (behind `APP_SANDBOX` flag) |
| Sparkle framework | App Store rejects third-party update mechanisms | `ENABLE_SPARKLE` flag gates all Sparkle code; remove define for App Store build |
| Version checker | App Store rejects apps that check for updates outside the store (guideline 3.1.1) | `ENABLE_VERSION_CHECKER` flag gates VersionChecker + update UI; remove define for App Store build |
| `disable-library-validation` entitlement | Rejected by App Store review (only needed for Sparkle's dynamic loading) | Not in `AIBattery-AppStore.entitlements` — resolved when Sparkle is disabled |
| SUFeedURL in Info.plist | App Store may flag Sparkle feed URL | `build-app.sh` strips SUFeedURL when `APP_STORE_BUILD` env is set |
| Privacy manifest | Required for App Store submission | `PrivacyInfo.xcprivacy` added (UserDefaults + FileTimestamp) |
| LSApplicationCategoryType | Required App Store metadata | Set to `public.app-category.developer-tools` in Info.plist |
| Apple Developer certificate | App Store requires signed builds ($99/yr) | Enroll in Apple Developer Program |

Remaining blockers are non-trivial and should be addressed as a dedicated effort, not mixed into routine code changes.
