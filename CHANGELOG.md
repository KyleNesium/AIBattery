# Changelog

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
