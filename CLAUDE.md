# AI Battery — AI Agent Guide

macOS menu bar app showing Claude API usage at a glance. Built with Swift 6 / SwiftUI, SPM, macOS 13+.

## Spec-Driven Workflow

The `spec/` folder is the single source of truth.

1. **Spec first** — describe the desired state in the relevant spec file
2. **Code second** — update code to match the spec
3. **Never diverge** — if you find spec/code drift, fix the spec first
4. **Before any push to main** — ensure all spec files and `README.md` reflect the current state of the code. No merge goes out with stale docs.

| File | Covers |
|------|--------|
| `spec/ARCHITECTURE.md` | App structure, data flow, project tree, build config |
| `spec/DATA_LAYER.md` | Models, services, algorithms, ViewModel |
| `spec/UI_SPEC.md` | Views, layout, colors, typography, ASCII mockup |
| `spec/CONSTANTS.md` | Every hardcoded value: thresholds, URLs, timings |

## Build & Run

```bash
swift build -c release

# Quick bundle for local smoke-testing — no codesign, no Sparkle.framework
mkdir -p .build/AIBattery.app/Contents/MacOS
cp .build/release/AIBattery .build/AIBattery.app/Contents/MacOS/
cp AIBattery/Info.plist .build/AIBattery.app/Contents/
open .build/AIBattery.app

# Full signed bundle (what CI/release actually ships): entitlements,
# Sparkle.framework, codesign, zip + dmg
./scripts/build-app.sh
```

## Testing

```bash
# Run all tests (requires Xcode for the Swift Testing framework)
swift test
```

1116 tests across 72 files, using `import Testing` + `@testable import AIBatteryCore`.

The package has 3 SPM targets:
- **AIBatteryCore** (`.target`, path `AIBattery/`) — all logic: models, services, views, utilities
- **AIBattery** (`.executableTarget`, path `AIBatteryApp/`) — thin `@main` entry point, imports AIBatteryCore
- **AIBatteryCoreTests** (`.testTarget`) — unit tests, `@testable import AIBatteryCore`

CI (`macos-15`): build → test → verify signed bundle. Runs on push to `main`, and once when a PR leaves draft — **not** on later pushes to that PR (force a re-run via `workflow_dispatch`). A separate Lint job (SwiftLint + SwiftFormat) runs on every PR push touching `.swift`/lint-config files; run `swiftformat AIBattery/ AIBatteryApp/ Tests/` and `swiftlint` locally before pushing to avoid a red check.

## Code Conventions

- **Singletons**: Services use `static let shared`
- **Models**: Plain structs, `Codable` where needed
- **Views**: Data via init params — no `EnvironmentObject`
- **State**: Three `@MainActor` `ObservableObject`s — `UsageViewModel`, `AccountStore`, `OAuthManager` — injected via `@ObservedObject`
- **Formatting**: `TokenFormatter` for numbers, `ModelNameMapper` for model IDs
- **Dependencies**: Sparkle 2 for auto-update + Apple frameworks only
- **File naming**: One primary type per file, filename matches type name

## Key Design Decisions

These aren't obvious from reading the code — know them before making changes:

- Claude Code 5-hour / 7-day usage may come from Claude Code client metadata rather than public `/v1/messages` headers
- Legacy unified `anthropic-ratelimit-unified-*` headers still exist in some paths, but public Anthropic API docs now describe standard `anthropic-ratelimit-*` headers instead
- JSONL must be streamed via `FileHandle` (never load full file into memory)
- JSONL tokens must not double-count with `stats-cache.json` (see DATA_LAYER.md)
- `OAuthManager.exchangeCode()` returns `Result<Void, AuthError>` — callers handle typed errors. Validates state parameter for CSRF protection.
- `APIFetchResult.isCached` distinguishes fresh API data from stale cache — always check before treating as fresh. The `RateLimitFetcher` cache never expires (stale data beats empty bars); individual rate-limit windows are cleared at their own reset via `withClearedExpiredWindows`.
- OAuth refresh: transient errors (network + server 5xx) keep `isAuthenticated` true (retry next cycle); only auth errors trigger logout. Token endpoint retries 5xx up to 2 times with backoff. Token refresh fires 5 min before expiry to avoid clock-skew 401s. Concurrent refresh attempts are serialized via a shared task.
- StatusChecker backs off exponentially after failures (60s → 120s → 240s, capped at 5 min, ±20% jitter) — no immediate retries
- SessionLogReader per-file cache stores fingerprints only (modDate + fileSize); raw entry arrays released after merge into cachedAllEntries. On dirty cycle, only changed files re-parsed — eliminates double-storage. Trailing JSONL lines without closing `}` are skipped; leftover buffer capped at 1MB (oversized lines discarded)
- NotificationManager fires once per outage via `UNUserNotificationCenter`, deduplicates per component, resets on recovery

## Security

- OAuth refresh token lives in macOS Keychain under service `"AIBattery"` — access token is memory-only (re-derived from refresh on launch), expiry timestamp in UserDefaults. Only 1 Keychain item per account to minimize Sparkle update prompts.
- Never log token values — mask or redact in error messages
- JSONL reads are token-count-only — never parse, store, or display message content
- Notifications use `UNUserNotificationCenter` — no shell process or string escaping needed
- PKCE (SHA-256) protects the OAuth code exchange — the verifier never leaves the process
- `SecureNetworking` uses an ephemeral `URLSession` (no disk cache/cookies) and caps responses at 2MB, discarding anything larger
- App bundle is codesigned with hardened runtime — ad-hoc locally, Developer ID + notarization in CI release builds — giving Keychain a stable identity for ACL whitelisting
- All network requests use HTTPS with system certificate validation — no custom trust or pinning overrides
