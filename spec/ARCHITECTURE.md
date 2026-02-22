# Architecture

## App Entry Point

```
@main AIBatteryApp: App
  └─ MenuBarExtra(.window)
       ├─ label: MenuBarLabel (✦ icon + percentage)
       └─ content: UsagePopoverView (275pt wide popover)
```

Single `@StateObject UsageViewModel` owns all state. Views read `viewModel.snapshot`.

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
       rateLimits +              ┌─────────────┼─────────────┐
       orgProfile                ▼             ▼             ▼
                           StatsCacheReader  SessionLogReader  readAccountInfo()
                           (stats-cache.json) (JSONL files)   (~/.claude.json)
```

`refresh()` runs: gets active account + token from `OAuthManager`, passes both to `RateLimitFetcher.fetch(accessToken:accountId:)` for per-account rate limits + org profile. Status check runs concurrently. After fetch, resolves pending account identity or updates metadata. `Task.detached` for aggregation. Org name from API headers or active account record flows into aggregator.

## Refresh Triggers

| Trigger | Interval | Source |
|---------|----------|--------|
| Timer | refreshInterval (default 60s, user-configurable 10–60s) | UsageViewModel.pollingTimer |
| Stats cache write | 2 sec debounce | FileWatcher (DispatchSource on stats-cache.json) |
| JSONL file change | 2 sec FSEvent latency | FileWatcher (FSEventStream on ~/.claude/projects/) |
| Fallback | 60 sec | FileWatcher fallback timer |
| Account switch | On click | Account picker in header |
| Adaptive extension | Doubles interval (up to 5 min) after 3 unchanged cycles | UsageViewModel |

## Project Tree

```
AIBatteryApp/
  AIBatteryApp.swift              — @main, imports AIBatteryCore, MenuBarExtra with .window style
AIBattery/
  Info.plist                      — LSUIElement = YES (no Dock icon)
  AIBattery.entitlements          — App sandbox disabled
  Models/
    AccountRecord.swift           — Per-account identity record (Codable, Identifiable)
    APIFetchResult.swift          — Combined result from a single Messages API call
    APIProfile.swift              — Organization info from API response headers
    RateLimitUsage.swift          — Unified rate limit header parsing (5h/7d windows)
    StatsCache.swift              — Codable for stats-cache.json
    SessionEntry.swift            — Codable for JSONL lines + AssistantUsageEntry
    UsageSnapshot.swift           — UsageSnapshot, ModelTokenSummary, MetricMode, PlanTier
    TokenHealthConfig.swift       — Health thresholds + context window lookup
    TokenHealthStatus.swift       — HealthBand, HealthWarning, TokenHealthStatus (Identifiable by sessionId)
    ModelPricing.swift            — Per-model pricing lookup + cost calculation
  Services/
    AccountStore.swift            — Multi-account registry (UserDefaults persistence, max 2)
    OAuthManager.swift            — OAuth 2.0 PKCE flow, token storage, auto-refresh
    RateLimitFetcher.swift        — POST /v1/messages, parse unified headers + org profile
    StatsCacheReader.swift        — Reads + decodes stats-cache.json
    SessionLogReader.swift        — JSONL streaming reader (FileHandle, 64KB chunks)
    FileWatcher.swift             — DispatchSource + FSEventStream for live updates
    UsageAggregator.swift         — Merges all data sources → UsageSnapshot
    TokenHealthMonitor.swift      — Analyzes session tokens → health status (single + top N sessions)
    StatusChecker.swift           — Fetches status.claude.com system status
    SingleInstanceGuard.swift     — Prevents duplicate app instances
    NotificationManager.swift     — Status outage + rate limit alerts via osascript
    LaunchAtLoginManager.swift    — SMAppService launch-at-login toggle
    VersionChecker.swift          — GitHub Releases update checker (24h cadence)
  ViewModels/
    UsageViewModel.swift          — @MainActor ObservableObject, single source of truth
  Views/
    MenuBarLabel.swift            — ✦ icon + percentage in menu bar
    MenuBarIcon.swift             — 4-pointed star NSImage (dynamic color)
    UsagePopoverView.swift        — Main popover: header, metric toggle, ordered sections, footer
    AuthView.swift                 — OAuth login/paste-code screen
    TutorialOverlay.swift         — First-launch 3-step walkthrough overlay
    UsageBarsSection.swift        — FiveHourBarSection + SevenDayBarSection rate limit bars
    TokenHealthSection.swift      — Context health gauge + warnings + multi-session chevron toggle
    TokenUsageSection.swift       — Per-model token breakdown with token type tags + optional cost
    InsightsSection.swift         — Today stats, all-time stats
    ActivityChartView.swift        — 24H/7D/12M activity chart (Swift Charts, rolling windows)
    CopyableText.swift            — ViewModifier for click-to-copy with checkmark feedback
  Utilities/
    TokenFormatter.swift          — Format tokens ("18.9M")
    ModelNameMapper.swift         — "claude-opus-4-6-20250929" → "Opus 4.6"
    UserDefaultsKeys.swift        — Centralized @AppStorage / UserDefaults key constants
    AppLogger.swift               — Structured os.Logger instances by category
    ClaudePaths.swift             — Centralized file paths for all Claude Code data locations
    ThemeColors.swift             — Centralized color theming with colorblind-safe palette
Tests/AIBatteryCoreTests/
  Utilities/
    TokenFormatterTests.swift     — format() for 0, 500, 1K, 2.5K, 15K, 1M, 3.2M, 150M + negatives + boundaries
    ModelNameMapperTests.swift    — displayName() for all model families, edge cases, empty, multi-hyphens
    UserDefaultsKeysTests.swift   — prefix validation, uniqueness
    ClaudePathsTests.swift        — path suffixes, URL↔path consistency, absolute paths
    ThemeColorsTests.swift        — Color theme tests (both modes, all bands)
  Models/
    AccountRecordTests.swift      — Codable round-trip, pending identity, equatable
    PlanTierTests.swift           — fromBillingType() for all known tiers + unknown + empty
    MetricModeTests.swift         — rawValues, labels, shortLabels, allCases
    RateLimitUsageTests.swift     — parse() with full/partial/missing headers; computed properties
    APIProfileTests.swift         — parse() with both/one/no headers
    APIFetchResultTests.swift     — defaults, explicit cached flag, profile preservation
    TokenHealthConfigTests.swift  — contextWindow() exact/prefix/fallback; default thresholds
    StatsCacheTests.swift         — DailyActivity.parsedDate, LongestSession.durationFormatted, Codable round-trip
    ModelTokenSummaryTests.swift  — totalTokens sum
    TokenHealthStatusTests.swift  — suggestedAction per band, HealthBand rawValues
    SessionEntryTests.swift       — Codable decode from real JSONL, minimal entry, round-trip
    UsageSnapshotTests.swift      — totalTokens, percent(for:), planTier
    ModelPricingTests.swift       — pricing lookup, cost calculation, formatCost, edge cases
  Services/
    AccountStoreTests.swift       — Add/remove/update/merge, persistence, migration
    StatusIndicatorTests.swift    — from() all status strings, severity ordering, displayName
    StatusCheckerParsingTests.swift — incident impact escalation, component ID constants
    SessionLogReaderTests.swift   — SessionEntry decoding, AssistantUsageEntry construction
    TokenHealthMonitorTests.swift — band classification, overflow guards, turn warnings, velocity
    NotificationManagerTests.swift — shouldAlert() pure function threshold tests
    VersionCheckerTests.swift     — semver comparison, tag stripping
.github/workflows/
  ci.yml                          — Build + test + bundle on push/PR (macos-15)
  release.yml                     — Release: build → GitHub Release → update Homebrew cask (macos-15)
scripts/
  build-app.sh                    — Build release binary + .app bundle + zip/dmg
  update-homebrew.sh              — Auto-update KyleNesium/homebrew-tap cask (version + SHA256)
  generate-icon.swift             — Generate AppIcon.icns (sparkle star, all macOS sizes)
project.yml                       — XcodeGen project spec (optional, SPM is primary)
Package.swift                     — SPM manifest: AIBatteryCore, AIBattery, AIBatteryCoreTests
CHANGELOG.md                      — Release notes per version
```

## Build Configuration

- **SPM**: swift-tools-version 5.9, 3 targets: AIBatteryCore (library), AIBattery (executable), AIBatteryCoreTests (tests)
- **Platform**: macOS 13+ (Ventura)
- **Sandbox**: Disabled (needs Keychain + filesystem access)
- **Codesigning**: Ad-hoc (`codesign --sign -`) with hardened runtime (`--options runtime`), entitlements embedded, bundle identifier sealed — gives the app a stable identity for Keychain ACL whitelisting without requiring an Apple Developer account
- **App icon**: Generated at build time via `scripts/generate-icon.swift` (sparkle star, all macOS sizes). Embedded in `Contents/Resources/AppIcon.icns` and used as DMG volume icon.
- **Dock icon**: None (LSUIElement = true)
- **Dependencies**: None (Apple frameworks only: SwiftUI, Charts, Security, Foundation, AppKit, ServiceManagement)

## Release Pipeline

1. Tag a version: `git tag v1.x.x && git push --tags`
2. `release.yml` builds the app, creates a GitHub Release with `.zip` and `.dmg`
3. `scripts/update-homebrew.sh` auto-updates `KyleNesium/homebrew-tap` — downloads the zip, computes SHA256, commits updated cask formula
4. Requires `HOMEBREW_TAP_TOKEN` repo secret (GitHub PAT with `repo` scope for the homebrew-tap repo)

**Important**: Every release must update the Homebrew cask. The automation handles this when the secret is configured.

## Network Calls (exhaustive)

1. `POST https://api.anthropic.com/v1/messages?beta=true` — unified rate limit headers + org profile (every refresh interval)
2. `GET https://status.claude.com/api/v2/summary.json` — system status (every refresh interval)
3. `POST https://console.anthropic.com/v1/oauth/token` — OAuth token exchange + auto-refresh
4. `GET https://claude.ai/oauth/authorize` — OAuth login (opens in browser, one-time)
5. `GET https://api.github.com/repos/KyleNesium/AIBattery/releases/latest` — update check (once per 24h)

## Local File Access (exhaustive)

1. macOS Keychain, service `"AIBattery"` — Per-account OAuth tokens (prefixed: accessToken_{accountId}, refreshToken_{accountId}, expiresAt_{accountId})
2. UserDefaults `aibattery_accounts` + `aibattery_activeAccountId` — Multi-account registry (JSON-encoded [AccountRecord])
3. `~/.claude.json` → `oauthAccount` — billingType
4. `~/.claude/stats-cache.json` — historical usage (daily activity, model totals, peak hours)
5. `~/.claude/projects/*/[session-id].jsonl` — per-message token data
6. `~/.claude/projects/*/subagents/*.jsonl` — subagent session data
