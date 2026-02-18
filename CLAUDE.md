# AI Battery — AI Agent Guide

macOS menu bar app showing Claude API usage at a glance. Built with Swift/SwiftUI, SPM, macOS 13+.

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

# Bundle and launch
mkdir -p .build/AIBattery.app/Contents/MacOS
cp .build/release/AIBattery .build/AIBattery.app/Contents/MacOS/
cp AIBattery/Info.plist .build/AIBattery.app/Contents/
open .build/AIBattery.app
```

## Testing

```bash
# Run all tests (requires Xcode installed for Swift Testing framework)
swift test
```

Tests use Swift's `Testing` framework with `@testable import AIBatteryCore`.

The package has 3 SPM targets:
- **AIBatteryCore** (`.target`) — all logic: models, services, views, utilities
- **AIBattery** (`.executableTarget`) — thin `@main` entry point, imports AIBatteryCore
- **AIBatteryCoreTests** (`.testTarget`) — unit tests, `@testable import AIBatteryCore`

CI runs on every push via GitHub Actions (`macos-15` runner): build → test → bundle.

## Code Conventions

- **Singletons**: Services use `static let shared`
- **Models**: Plain structs, `Codable` where needed
- **Views**: Data via init params — no `EnvironmentObject`
- **State**: `UsageViewModel` is the only `ObservableObject` (`@MainActor`)
- **Formatting**: `TokenFormatter` for numbers, `ModelNameMapper` for model IDs
- **Dependencies**: Zero — stdlib + Apple frameworks only
- **File naming**: One primary type per file, filename matches type name

## Key Design Decisions

These aren't obvious from reading the code — know them before making changes:

- Rate limit headers use unified `anthropic-ratelimit-unified-*` format (5h + 7d windows, not per-resource)
- Only `/v1/messages` returns rate limit headers — `count_tokens` does not
- JSONL must be streamed via `FileHandle` (never load full file into memory)
- JSONL tokens must not double-count with `stats-cache.json` (see DATA_LAYER.md)
- `OAuthManager.exchangeCode()` returns `Result<Void, AuthError>` — callers handle typed errors. Validates state parameter for CSRF protection.
- `APIFetchResult.isCached` distinguishes fresh API data from stale cache — always check before treating as fresh. Cache expires after 1 hour.
- OAuth refresh: network errors keep `isAuthenticated` true (retry next cycle); only auth errors trigger logout
- StatusChecker backs off 5 min after failures — no immediate retries
- SessionLogReader cache caps at 200 entries with LRU eviction; trailing JSONL lines without closing `}` are skipped
- NotificationManager fires once per outage via `osascript`, deduplicates per component, resets on recovery
- `~/.claude.json` oauthAccount may not match the OAuth token's org if user switched accounts

## Security

- OAuth tokens (access + refresh) live in macOS Keychain under service `"AIBattery"` — never UserDefaults or disk
- Never log token values — mask or redact in error messages
- JSONL reads are token-count-only — never parse, store, or display message content
- `osascript` notifications use shell-escaped strings to prevent injection
- PKCE (SHA-256) protects the OAuth code exchange — the verifier never leaves the process
- App bundle is ad-hoc codesigned with hardened runtime — gives Keychain a stable identity for ACL whitelisting
- All network requests use HTTPS with system certificate validation — no custom trust or pinning overrides
