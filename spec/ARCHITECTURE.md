# Architecture

## App Entry Point

```
@main AIBatteryApp: App
  └─ AppDelegate (NSApplicationDelegateAdaptor)
       └─ StatusBarManager.setup(viewModel:oauthManager:)
            ├─ NSStatusItem: native button.image + button.title (no NSHostingView)
            └─ PopoverPanel (floating NSPanel, borderless)
                 └─ NSVisualEffectView (.popover material)
                      └─ NSHostingView → PopoverContentView
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
    UsageSnapshot.swift           — UsageSnapshot, ModelTokenSummary, MetricMode
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
    StatusBarManager.swift        — NSStatusItem + floating NSPanel, native AppKit button, NSVisualEffectView, Combine-driven updates
    MenuBarIcon.swift             — 4-pointed star NSImage: breathing glow, broken star (throttled), recovery sparkle; quantized cache
    UsagePopoverView.swift        — Main popover: header, metric toggle, ordered sections, footer
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
    TokenUsageSection.swift       — Per-model token breakdown with token type tags + optional cost
    InsightsSection.swift         — Today stats, all-time stats
    ActivityChartView.swift        — 12H/7D/12M activity chart (Swift Charts, rolling windows)
    CopyableText.swift            — ViewModifier for click-to-copy with clipboard icon feedback
    MarqueeText.swift             — News-ticker scrolling text, supports multi-text cycling with cross-fade
    SandboxOnboardingView.swift   — Folder access prompt for App Sandbox (APP_SANDBOX flag)
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
  Models/
    AccountRecordTests.swift      — Codable round-trip, pending identity, equatable
    MetricModeTests.swift         — rawValues, labels, allCases
    RateLimitUsageTests.swift     — parse() with full/partial/missing headers; computed properties
    APIProfileTests.swift         — parse() with both/one/no headers
    APIFetchResultTests.swift     — defaults, explicit cached flag, profile preservation
    TokenHealthConfigTests.swift  — contextWindow() exact/prefix/fallback; default thresholds
    StatsCacheTests.swift         — DailyActivity.parsedDate, LongestSession.durationFormatted, Codable round-trip
    ModelTokenSummaryTests.swift  — totalTokens sum
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
    TokenHealthMonitorTests.swift — band classification, overflow guards, turn warnings, velocity, rapid consumption, custom config
    NotificationManagerTests.swift — shouldAlert() pure function threshold tests
    VersionCheckerTests.swift     — semver comparison, tag stripping, cache behavior, persistence
    SparkleUpdateServiceTests.swift — Sparkle configuration verification (auto-check disabled, singleton)
    RateLimitFetcherTests.swift   — cache expiry, stale marking, multi-account isolation, Retry-After parsing
    StatsCacheReaderTests.swift   — decode, caching, invalidation, full payload, file size guard
    UsageAggregatorTests.swift    — empty state, stats-only, JSONL-only, model filtering, dedup
    OAuthManagerTests.swift       — AuthError user messages, transient error classification
.github/workflows/
  ci.yml                          — Build + test + bundle on push/PR (macos-15)
  release.yml                     — Release: build → GitHub Release → update Homebrew cask (macos-15)
scripts/
  build-app.sh                    — Build release binary + .app bundle + zip/dmg (direct download)
  build-appstore.sh               — XcodeGen + xcodebuild archive for App Store submission
  ExportOptions-AppStore.plist    — Export options for App Store Connect upload
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
- **Codesigning**: Developer ID Application certificate via CI (ad-hoc fallback for local dev). Hardened runtime (`--options runtime`), entitlements embedded, bundle identifier sealed — gives the app a stable signing identity for Keychain ACL (no prompts after Sparkle updates). Entitlements file selected automatically (`AIBattery-AppStore.entitlements` when `APP_STORE_BUILD` is set)
- **Notarization**: Both `.zip` and `.dmg` submitted to `notarytool`, tickets stapled for offline Gatekeeper verification. Skipped when `APPLE_ID`/`APPLE_TEAM_ID` env vars are unset (local dev)
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
6. `DEVELOPER_ID_CERT_BASE64`, `DEVELOPER_ID_CERT_PASSWORD` — Developer ID `.p12` for CI signing
7. `CODE_SIGN_IDENTITY`, `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_PASSWORD` — signing identity + notarization credentials
8. Optional App Store: `APPLE_DISTRIBUTION_CERT_BASE64`, `APPLE_DISTRIBUTION_CERT_PASSWORD`, `APP_STORE_PROVISION_PROFILE_BASE64`, `APP_STORE_CONNECT_KEY`, `APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID` + `ENABLE_APPSTORE_BUILD` repository variable

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

## Distribution

Two parallel distribution channels from the same codebase:

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

### Direct Download (GitHub / Homebrew / Sparkle)

- **Signing**: Developer ID Application certificate — eliminates Gatekeeper warnings
- **Notarization**: Both `.zip` and `.dmg` submitted to `notarytool`, tickets stapled for offline verification
- **Updates**: Sparkle 2 auto-update via appcast on gh-pages
- **Homebrew**: `brew install --cask kylenesium/tap/aibattery` — auto-updated on release
- **Entitlements**: `AIBattery.entitlements` — sandbox disabled, `disable-library-validation` for Sparkle
- **Compiler flags**: `ENABLE_SPARKLE`, `ENABLE_VERSION_CHECKER`

### App Store

- **Signing**: Apple Distribution certificate + Mac App Store provisioning profile
- **Build**: XcodeGen → `xcodebuild archive` with `AppStore` configuration (no SPM `swift build`)
- **Entitlements**: `AIBattery-AppStore.entitlements` — sandbox enabled, `network.client`, `user-selected.read-only`, `bookmarks.app-scope`
- **Compiler flags**: `APP_SANDBOX` only (no Sparkle, no VersionChecker — App Store guideline 3.1.1)
- **Sandbox flow**: `SandboxAccessManager` prompts user for `~/.claude/` access via NSOpenPanel, persists security-scoped bookmark. `ClaudePaths` uses `getpwuid` to resolve real home (not container). `SandboxOnboardingView` shown before auth screen when no bookmark exists
- **Upload**: CI job uploads to App Store Connect via API key (gated behind `ENABLE_APPSTORE_BUILD` variable)
- **Scripts**: `scripts/build-appstore.sh` + `scripts/ExportOptions-AppStore.plist`

### Shared Infrastructure

| Item | Direct Download | App Store |
|------|----------------|-----------|
| Bundle ID | `com.KyleNesium.AIBattery` | Same |
| Privacy manifest | `PrivacyInfo.xcprivacy` | Same |
| Category | `public.app-category.developer-tools` | Same |
| CI | `release.yml` → `release` job | `release.yml` → `appstore` job |
| Build script | `scripts/build-app.sh` | `scripts/build-appstore.sh` |
