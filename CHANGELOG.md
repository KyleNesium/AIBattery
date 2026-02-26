# Changelog

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
