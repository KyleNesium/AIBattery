# Architecture

## App Entry Point

```
@main AIBatteryApp: App
  └─ AppDelegate (NSApplicationDelegateAdaptor)
       └─ StatusBarManager.setup(viewModel:oauthManager:)
            ├─ NSStatusItem: native button.image + button.title (no NSHostingView)
            └─ PopoverPanel (floating NSPanel, borderless)
                 └─ NSHostingView → PopoverContentView (controlBackgroundColor background)
                      └─ Group { UsagePopoverView | AuthView }
```

`StatusBarManager` owns the `NSStatusItem` and a floating `NSPanel` directly, bypassing SwiftUI's `MenuBarExtra`. The panel uses `hidesOnDeactivate = false` and `.floating` level so it stays open regardless of focus changes — only closes on status item click or Escape.

Single `UsageViewModel` owns all state. Views read `viewModel.snapshot`.

Auth gating: `isAuthenticated` drives whether UsagePopoverView or AuthView is shown. Multi-account add-account flow is handled inline by UsagePopoverView (shows AuthView as overlay).

## Data Flow

```
                    ┌──────────────────┐
                    │  UsageViewModel   │
                    │  (refresh loop)   │
                    └────────┬─────────┘
                             │
              ┌──────────────┼──────────────┐
              ▼              ▼              ▼
     RateLimitFetcher   StatusChecker   UsageAggregator
     (unified API call)  (status.claude)  (merge all data)
     → APIFetchResult:                         │
       rateLimits +              ┌─────────────┤
       orgProfile                ▼             ▼
                           StatsCacheReader  SessionLogReader
                           (stats-cache.json) (JSONL files)
```

`refresh()` runs: gets active account + token from `OAuthManager`, passes both to `RateLimitFetcher.fetch(accessToken:accountId:)` for per-account rate limits + org profile. Status check runs concurrently. After fetch, resolves pending account identity or updates metadata. Aggregation runs on the main actor (same thread as FileWatcher cache invalidation — avoids data races).

## Refresh Triggers

| Trigger | Interval | Source |
|---------|----------|--------|
| Timer | refreshInterval (default 60s, user-configurable 10–60s) | UsageViewModel.pollingTimer |
| Stats cache write | 2 sec debounce | FileWatcher (DispatchSource on stats-cache.json) |
| JSONL file change | 2 sec FSEvent latency | FileWatcher (FSEventStream on ~/.claude/projects/) |
| Fallback | 60 sec | FileWatcher fallback timer |
| Account switch | On click | Account picker in header |
| Sleep/wake | Immediate on wake | NSWorkspace.willSleepNotification / didWakeNotification |
| Network recovery | On connectivity restored | NetworkMonitor (NWPathMonitor) |
| Adaptive extension | Doubles interval (up to 5 min) after 3 unchanged cycles | AdaptivePollingState |

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
    AccountRecord.swift           — Per-account identity record (Codable, Identifiable)
    APIFetchResult.swift          — Combined result from a single Messages API call
    APIProfile.swift              — Organization info from API response headers
    RateLimitUsage.swift          — Unified rate limit header parsing (5h/7d windows)
    StatsCache.swift              — Codable for stats-cache.json
    SessionEntry.swift            — Codable for JSONL lines + AssistantUsageEntry
    UsageSnapshot.swift           — UsageSnapshot, ModelTokenSummary
    ProjectTokenSummary.swift     — Per-project token totals + cost from JSONL cwd
    MetricMode.swift              — MetricMode enum (5h / 7d / context)
    TrendDirection.swift          — TrendDirection enum (up / down / flat)
    ClaudeSystemStatus.swift      — ClaudeSystemStatus, StatusIndicator, StatusComponent
    TokenHealthConfig.swift       — Health thresholds + context window lookup
    TokenHealthStatus.swift       — HealthBand, HealthWarning, TokenHealthStatus (Identifiable by sessionId)
    ModelPricing.swift            — Per-model pricing lookup + cost calculation
  Services/
    AccountStore.swift            — Multi-account registry (UserDefaults persistence, max 3)
    OAuthManager.swift            — OAuth 2.0 PKCE flow, token storage, auto-refresh
    RateLimitFetcher.swift        — POST /v1/messages, parse unified headers + org profile
    StatsCacheReader.swift        — Reads + decodes stats-cache.json
    SessionLogReader.swift        — JSONL streaming reader (FileHandle, 64KB chunks)
    FileWatcher.swift             — DispatchSource + FSEventStream for live updates
    UsageAggregator.swift         — Merges all data sources → UsageSnapshot
    TokenHealthMonitor.swift      — Analyzes session tokens → health status (single + top N sessions)
    TokenLedger.swift             — Persistent per-model token high-water marks (Application Support)
    NetworkMonitor.swift          — NWPathMonitor connectivity observer (triggers refresh on recovery)
    StatusChecker.swift           — Fetches status.claude.com system status
    SingleInstanceGuard.swift     — POSIX flock single-instance guard, SIGTERM handler
    NotificationManager.swift     — Status outage + rate limit alerts via UNUserNotificationCenter
    LaunchAtLoginManager.swift    — SMAppService launch-at-login toggle
    VersionChecker.swift          — GitHub Releases update checker (24h cadence)
    SparkleUpdateService.swift     — Sparkle 2 wrapper for user-initiated auto-update
  ViewModels/
    UsageViewModel.swift          — @MainActor ObservableObject, single source of truth
  Views/
    StatusBarManager.swift        — NSStatusItem + floating NSPanel, native AppKit button, controlBackgroundColor, Combine-driven updates
    MenuBarIcon.swift             — 4-pointed star NSImage: breathing glow, broken star (throttled), recovery sparkle; quantized cache
    MenuBarIconGeometry.swift     — Star path geometry helpers (starPath, brokenStarFragments, drawStroke) + NSBezierPath→CGPath
    UsagePopoverView.swift        — Thin popover orchestrator: wires sub-views via init params, owns state
    PopoverHeaderView.swift       — Header row, account picker, update banner (ENABLE_VERSION_CHECKER)
    MetricToggleView.swift        — Segmented metric picker + auto mode button + ordered modes cache
    PopoverStateViews.swift       — PopoverLoadingView, PopoverErrorView, PopoverEmptyView, PopoverIdleFilteredView
    PopoverFooterView.swift       — Footer links, logout confirm, status indicator, timestamp
    UsageGateViews.swift          — ProjectUsageGate, InsightsGate — data-availability wrappers
    Settings/
      SettingsRow.swift           — Inline settings container: account names + sub-sections
      RefreshSettingsSection.swift — Refresh interval slider + sliderMarks() helper
      DisplaySettingsSection.swift — Display toggles + idle session cutoff slider
      AlertSettingsSection.swift  — Status alerts + rate limit alerts
      LaunchAtLoginSection.swift  — Launch at Login toggle
    AuthView.swift                 — OAuth login/paste-code screen
    TutorialOverlay.swift         — First-launch 3-step walkthrough overlay
    UsageBarsSection.swift        — FiveHourBarSection + SevenDayBarSection rate limit bars
    TokenHealthSection.swift      — Context health gauge + warnings + multi-session chevron toggle
    TokenHealthSessionInfo.swift  — Session detail computation: label parts, tooltip, idle detection, time formatting, clipboard export
    ProjectUsageSection.swift     — Per-project token breakdown with cost (top 5 default, expand to 10)
    ActivityChartView.swift        — InsightsView core: struct declaration, @State/@AppStorage, cache logic, fingerprinting, and body
    InsightsCharts.swift           — extension InsightsView: areaGradient, chartLineStyle, sharedYAxis, dailyChart, hourlyChart, monthlyChart
    InsightsTrendCostSection.swift — extension InsightsView: trendSummary, trendRowTop/Bottom, windowedModelTokens, costSection
    InsightsRowsAndHover.swift     — extension InsightsView: insightRows, hover helpers, static formatters (formatHourLabel, compactCount, monthAbbrev)
    ActivityChartData.swift       — Chart data transformation layer (daily/hourly/monthly points)
    ActivityChartTrend.swift      — Trend computation: vs-yesterday/week/month comparisons + copy text
    CollapsibleSectionHeader.swift — Shared collapsible header with rotating chevron, used by 4 sections
    StyledDivider.swift            — Standardized divider: Divider() at 0.3 opacity, Spacing.tight vertical padding
    FooterLink.swift              — Footer link button with hover underline and external arrow
    RefreshButton.swift           — Refresh button with brief spin animation
    CopyableText.swift            — ViewModifier for click-to-copy: full CopyableModifier + lightweight LightCopyableModifier for dense areas
    MarqueeText.swift             — News-ticker scrolling text, supports multi-text cycling with cross-fade
  Utilities/
    TokenFormatter.swift          — Format tokens ("18.9M")
    ModelNameMapper.swift         — "claude-opus-4-6-20250929" → "Opus 4.6"
    UserDefaultsKeys.swift        — Centralized @AppStorage / UserDefaults key constants
    DateFormatters.swift          — Shared DateFormatter / ISO8601DateFormatter instances (allocated once)
    AdaptivePollingState.swift    — Pure struct state machine for adaptive polling interval logic
    AppLogger.swift               — Structured os.Logger instances by category
    ClaudePaths.swift             — Centralized file paths for all Claude Code data locations
    SecureNetworking.swift        — Ephemeral URLSession + response size guard (2 MB limit) + resource timeout (30s)
    DurationFormatter.swift       — Compact time duration formatting ("2h 5m", "1d 1h", "soon")
    ThemeColors.swift             — Centralized color theming with colorblind-safe palette
    ThrottleTracker.swift         — Pure value type tracking throttle event transitions for trend display
    Typography.swift              — Named font style tokens (sectionHeader, monoValue, tinyLabel, decorativeIcon, etc.) — caseless enum namespace
    Spacing.swift                 — Spacing/Layout/MotionConstants enums + sectionPadding() View extension — caseless enum namespaces co-located
    KeychainHelper.swift          — Low-level macOS Keychain CRUD (extracted from OAuthManager)
Tests/AIBatteryCoreTests/
  Utilities/
    TokenFormatterTests.swift     — format() for 0, 500, 1K, 2.5K, 15K, 1M, 3.2M, 150M + negatives + boundaries
    ModelNameMapperTests.swift    — displayName() for all model families, edge cases, empty, multi-hyphens
    UserDefaultsKeysTests.swift   — prefix validation, uniqueness
    ClaudePathsTests.swift        — path suffixes, URL↔path consistency, absolute paths
    ThemeColorsTests.swift        — Color theme tests (both modes, all bands)
    DateFormattersTests.swift     — format strings, round-trips, locale pinning
    AdaptivePollingStateTests.swift — threshold, doubling, cap, reset, constants
    SecureNetworkingTests.swift   — Ephemeral session config, singleton, size limit constant
    DurationFormatterTests.swift  — compact format, boundaries, days/hours/minutes
    ThrottleTrackerTests.swift    — Throttle transition detection, timestamp parsing, pruning, counting
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
  Services/
    AccountStoreTests.swift       — Add/remove/update/merge, persistence, migration
    StatusIndicatorTests.swift    — from() all status strings, severity ordering, displayName
    StatusCheckerParsingTests.swift — incident impact escalation, component ID constants
    SessionLogReaderTests.swift   — SessionEntry decoding, AssistantUsageEntry construction
    SessionLogReaderSymlinkTests.swift — Symlink boundary check (exclude outside, include inside)
    SessionLogReaderDiscoveryTests.swift — TTL-based discovery fallback, cache expiry
    TokenHealthMonitorTests.swift — band classification, overflow guards, turn warnings, velocity, rapid consumption, custom config
    TokenLedgerTests.swift        — high-water-mark merge, historical model restoration, per-account isolation, persistence, sort, file size guard
    NotificationManagerTests.swift — shouldAlert() pure function threshold tests
    VersionCheckerTests.swift     — semver comparison, tag stripping, cache behavior, persistence
    SparkleUpdateServiceTests.swift — Sparkle configuration verification (auto-check disabled, singleton)
    RateLimitFetcherTests.swift   — cache expiry, stale marking, multi-account isolation, Retry-After parsing
    StatsCacheReaderTests.swift   — decode, caching, invalidation, full payload, file size guard
    UsageAggregatorTests.swift    — empty state, stats-only, JSONL-only, model filtering, dedup, project grouping
    OAuthManagerTests.swift       — AuthError user messages, transient error classification
.github/workflows/
  ci.yml                          — Build + test + bundle on push/PR (macos-15)
  release.yml                     — Release: build → GitHub Release → update Homebrew cask (macos-15)
scripts/
  build-app.sh                    — Build release binary + .app bundle + zip/dmg
  update-homebrew.sh              — Auto-update KyleNesium/homebrew-tap cask (version + SHA256)
  generate-appcast.sh            — Generate appcast.xml for Sparkle update feed
  generate-icon.swift             — Generate AppIcon.icns (sparkle star, all macOS sizes)
project.yml                       — XcodeGen project spec (optional, SPM is primary)
Package.swift                     — SPM manifest: AIBatteryCore, AIBattery, AIBatteryCoreTests
CHANGELOG.md                      — Release notes per version
```

## Build Configuration

- **SPM**: swift-tools-version 5.9, 3 targets: AIBatteryCore (library), AIBattery (executable), AIBatteryCoreTests (tests)
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

1. `POST https://api.anthropic.com/v1/messages?beta=true` — unified rate limit headers + org profile (every refresh interval)
2. `GET https://status.claude.com/api/v2/summary.json` — system status (every refresh interval)
3. `POST https://console.anthropic.com/v1/oauth/token` — OAuth token exchange + auto-refresh
4. `GET https://claude.ai/oauth/authorize` — OAuth login (opens in browser, one-time)
5. `GET https://api.github.com/repos/KyleNesium/AIBattery/releases/latest` — update check (once per 24h)
6. `GET https://kylenesium.github.io/AIBattery/appcast.xml` — Sparkle update feed (on user-initiated update check)

## Local File Access (exhaustive)

1. macOS Keychain, service `"AIBattery"` — Per-account OAuth refresh token only (`refreshToken_{accountId}`); access token held in memory, expiry in UserDefaults
2. UserDefaults `aibattery_accounts` + `aibattery_activeAccountId` — Multi-account registry (JSON-encoded [AccountRecord])
3. `~/.claude/stats-cache.json` — historical usage (daily activity, model totals, peak hours)
4. `~/.claude/projects/*/[session-id].jsonl` — per-message token data
5. `~/.claude/projects/*/subagents/*.jsonl` — subagent session data

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
