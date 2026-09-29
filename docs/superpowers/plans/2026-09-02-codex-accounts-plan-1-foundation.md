# Codex Accounts Plan 1: Foundation, Auth & Rate Limits Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Codex (OpenAI) accounts exist alongside Claude accounts — in-app ChatGPT OAuth, rate-limit fetching from `wham/usage` with session-log fallback, mixed-provider menu bar and account picker.

**Architecture:** Provider seams on the existing architecture (spec Approach A). One `AccountStore`, one `UsageViewModel`; provider dispatch at three boundaries: token refresh inside `OAuthManager`, rate-limit fetch via a `RateLimitFetching` dispatcher, and UI glyphs derived from `AccountRecord.provider`. Plan 2 adds the Codex local data layer + Insights parity.

**Tech Stack:** Swift 6 / SwiftUI, SPM (targets: AIBatteryCore at `AIBattery/`, executable at `AIBatteryApp/`, tests at `Tests/AIBatteryCoreTests/`), Swift Testing (`import Testing`, `@Suite`/`@Test`/`#expect`), Network.framework for the OAuth callback listener.

**Spec:** `docs/superpowers/specs/2026-09-02-codex-support-design.md`. All work on branch `feat/codex-accounts` (exists, draft PR #191's sibling — PR #193).

## Global Constraints

- Swift 6 strict concurrency; services are `@MainActor` singletons (`static let shared`); pure logic is `nonisolated static` for testability.
- Tests: `import Testing` + `@testable import AIBatteryCore`; `@Suite` structs; `@MainActor` on suites touching MainActor types. NEVER touch `SparkleUpdateService.shared`, real Keychain, or live network in tests. No dynamic NSColor equality off-main (headless CI hang).
- Run a task's tests with: `swift test --filter <SuiteName>` (full `swift test` only in the wrap-up task — it takes minutes).
- Never log token values — mask or omit. Never parse/store/display message content from JSONL.
- Never load a whole JSONL file into memory — `FileHandle` streaming/tail reads only.
- No hardcoded secrets; the OAuth client-id is a public constant (same one the Codex CLI ships).
- Commit after every task: `<type>: <description>` format, NO `Co-Authored-By` trailers, author KyleNesium only.
- swiftformat/swiftlint clean before push: `swiftformat AIBattery/ AIBatteryApp/ Tests/ && swiftlint`.
- Verified external constants (do not re-derive, do not change):
  - OAuth client-id `app_EMoamEEZ73f0CkXaXp7hrann`; issuer `https://auth.openai.com`; callback `http://localhost:1455/auth/callback`; authorize `GET {issuer}/oauth/authorize`; token `POST {issuer}/oauth/token`.
  - Authorize query: `response_type=code`, `client_id`, `redirect_uri`, `scope=openid profile email offline_access api.connectors.read api.connectors.invoke`, `code_challenge`, `code_challenge_method=S256`, `id_token_add_organizations=true`, `codex_cli_simplified_flow=true`, `state`, `originator=codex_cli_rs`.
  - Code exchange: `Content-Type: application/x-www-form-urlencoded`, body `grant_type=authorization_code&code=…&redirect_uri=…&client_id=…&code_verifier=…`; response JSON `{id_token, access_token, refresh_token}`.
  - Refresh: JSON body `{"client_id":…, "grant_type":"refresh_token", "refresh_token":…, "scope":"openid profile email"}` to the same token URL.
  - Account identity: id_token JWT claim `["https://api.openai.com/auth"]["chatgpt_account_id"]`.
  - Usage: `GET https://chatgpt.com/backend-api/wham/usage`, headers `Authorization: Bearer <token>`, `ChatGPT-Account-Id: <accountId>`, `Accept: application/json`. Response: `rate_limit.primary_window` / `.secondary_window`, each `{used_percent, reset_at (epoch s), limit_window_seconds}`, plus `plan_type`, optional `rate_limit_reached_type`.
  - Session-log shape (`~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`): `event_msg` lines, `payload.type == "token_count"`, `payload.rate_limits.primary/secondary = {used_percent, window_minutes, resets_at}`.

**Known interim state (acceptable until Plan 2, never released alone):** with a Codex account active, the popover's rate-limit bars are Codex-sourced but Insights/local sections still show Claude JSONL data. Plan 2 gates those by provider.

---

### Task 1: AIProvider enum + AccountRecord.provider

**Files:**
- Create: `AIBattery/Models/AIProvider.swift`
- Modify: `AIBattery/Models/AccountRecord.swift`
- Test: `Tests/AIBatteryCoreTests/Models/AIProviderTests.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces: `public enum AIProvider: String, Codable, CaseIterable, Sendable { case claude, codex }` with `displayName: String`, `glyph: String`, `secondaryWindowLabel: String`, `secondaryWindowShortCode: String`. `AccountRecord.provider: AIProvider` (decode default `.claude`), explicit init `AccountRecord(id:displayName:billingType:addedAt:provider:)` with `provider` defaulting to `.claude`.

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
@testable import AIBatteryCore

@Suite("AIProvider")
struct AIProviderTests {
    @Test func glyphsAndLabels() {
        #expect(AIProvider.claude.glyph == "\u{2726}") // ✦
        #expect(AIProvider.codex.glyph == "\u{2B21}") // ⬡
        #expect(AIProvider.claude.displayName == "Claude")
        #expect(AIProvider.codex.displayName == "Codex")
        #expect(AIProvider.claude.secondaryWindowLabel == "7-Day")
        #expect(AIProvider.codex.secondaryWindowLabel == "Weekly")
        #expect(AIProvider.claude.secondaryWindowShortCode == "7D")
        #expect(AIProvider.codex.secondaryWindowShortCode == "WK")
    }

    @Test func accountRecord_decodesLegacyJSONWithoutProvider() throws {
        // Exactly what v2.6.1 persisted — no `provider` key.
        let legacy = Data("""
        [{"id":"org-abc","displayName":"Kyle","billingType":"pro","addedAt":1234567}]
        """.utf8)
        let decoded = try JSONDecoder().decode([AccountRecord].self, from: legacy)
        #expect(decoded[0].provider == .claude)
        #expect(decoded[0].id == "org-abc")
    }

    @Test func accountRecord_roundTripsCodexProvider() throws {
        let record = AccountRecord(id: "uuid-1", displayName: nil, billingType: "team", addedAt: Date(), provider: .codex)
        let data = try JSONEncoder().encode(record)
        let back = try JSONDecoder().decode(AccountRecord.self, from: data)
        #expect(back.provider == .codex)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AIProviderTests`
Expected: FAIL — `AIProvider` not defined.

- [ ] **Step 3: Write minimal implementation**

`AIBattery/Models/AIProvider.swift`:

```swift
import Foundation

/// Which AI service an account belongs to. Drives auth routing, rate-limit
/// fetching, window labels, and UI glyphs. Exactly two providers by design
/// (spec: no plugin registry).
public enum AIProvider: String, Codable, CaseIterable, Sendable {
    case claude
    case codex

    public var displayName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        }
    }

    /// Menu-bar / picker glyph. Text characters (not SF Symbols) so they can be
    /// baked into the status-item string alongside percentages.
    public var glyph: String {
        switch self {
        case .claude: "\u{2726}" // ✦
        case .codex: "\u{2B21}" // ⬡
        }
    }

    /// Label for the long window: Anthropic calls it 7-day; OpenAI calls it weekly
    /// (it is 7 days for both — 10080 minutes in Codex payloads).
    var secondaryWindowLabel: String {
        switch self {
        case .claude: "7-Day"
        case .codex: "Weekly"
        }
    }

    /// Compact menu-bar code for the long window ("waiting on 7D/WK").
    var secondaryWindowShortCode: String {
        switch self {
        case .claude: "7D"
        case .codex: "WK"
        }
    }
}
```

In `AIBattery/Models/AccountRecord.swift`, add the field, an explicit memberwise init (the custom `init(from:)` suppresses the synthesized one), and tolerant decoding:

```swift
public struct AccountRecord: Codable, Identifiable, Equatable {
    public var id: String
    public var displayName: String?
    public var billingType: String?
    public var addedAt: Date
    /// Which service this account belongs to. Decodes as `.claude` when absent
    /// so records persisted before v2.7 load unchanged (no migration).
    public var provider: AIProvider

    public var isPendingIdentity: Bool { id.hasPrefix("pending-") }

    public init(
        id: String,
        displayName: String? = nil,
        billingType: String? = nil,
        addedAt: Date,
        provider: AIProvider = .claude
    ) {
        self.id = id
        self.displayName = displayName
        self.billingType = billingType
        self.addedAt = addedAt
        self.provider = provider
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        billingType = try container.decodeIfPresent(String.self, forKey: .billingType)
        addedAt = try container.decode(Date.self, forKey: .addedAt)
        provider = try container.decodeIfPresent(AIProvider.self, forKey: .provider) ?? .claude
    }
}
```

Note: keep the existing doc comment on the type; `CodingKeys` is still synthesized (all stored properties). If any call site constructed `AccountRecord` with positional/labeled memberwise arguments in a different order, fix it to the init above.

- [ ] **Step 4: Run tests to verify they pass, and that nothing broke**

Run: `swift test --filter AIProviderTests && swift test --filter AccountStoreTests`
Expected: PASS (AccountStoreTests exercises existing `AccountRecord(id:displayName:billingType:addedAt:)` call shape — compiles thanks to the `provider` default).

- [ ] **Step 5: Commit**

```bash
git add AIBattery/Models/AIProvider.swift AIBattery/Models/AccountRecord.swift Tests/AIBatteryCoreTests/Models/AIProviderTests.swift
git commit -m "feat: add AIProvider enum and AccountRecord.provider with legacy-safe decoding"
```

---

### Task 2: AccountStore per-provider caps + display ordering

**Files:**
- Modify: `AIBattery/Services/AccountStore.swift`
- Test: `Tests/AIBatteryCoreTests/Services/AccountStoreProviderTests.swift`

**Interfaces:**
- Consumes: `AIProvider`, `AccountRecord.provider` (Task 1).
- Produces: `nonisolated static let maxAccountsPerProvider = 3`; `func accounts(for provider: AIProvider) -> [AccountRecord]`; `func canAddAccount(provider: AIProvider) -> Bool`; existing `var canAddAccount: Bool` redefined as "any provider has room"; `nonisolated static func displayOrdered(_ accounts: [AccountRecord]) -> [AccountRecord]` (Claude block first, insertion order preserved within provider — used by picker, fan-out order, and menu bar so they can't drift).

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
@testable import AIBatteryCore

@Suite("AccountStore provider caps")
@MainActor
struct AccountStoreProviderTests {
    private func makeCleanStore() -> AccountStore {
        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.accounts)
        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.activeAccountId)
        return AccountStore()
    }

    private func record(_ id: String, _ provider: AIProvider) -> AccountRecord {
        AccountRecord(id: id, addedAt: Date(), provider: provider)
    }

    @Test func capIsPerProvider() {
        let store = makeCleanStore()
        for i in 1...3 { store.add(record("c\(i)", .claude)) }
        #expect(!store.canAddAccount(provider: .claude))
        #expect(store.canAddAccount(provider: .codex)) // full Claude side must not block Codex
        #expect(store.canAddAccount) // any-provider variant
        for i in 1...3 { store.add(record("x\(i)", .codex)) }
        #expect(store.accounts.count == 6)
        #expect(!store.canAddAccount)
        store.add(record("x4", .codex)) // over cap — must be rejected
        #expect(store.accounts.count == 6)
    }

    @Test func displayOrdered_groupsClaudeFirst_stableWithinProvider() {
        let mixed = [
            record("x1", .codex), record("c1", .claude),
            record("x2", .codex), record("c2", .claude),
        ]
        let ordered = AccountStore.displayOrdered(mixed).map(\.id)
        #expect(ordered == ["c1", "c2", "x1", "x2"])
    }

    @Test func multiAccountDisplayIDs_usesDisplayOrder() {
        let mixed = [record("x1", .codex), record("c1", .claude)]
        let ids = AccountStore.multiAccountDisplayIDs(accounts: mixed, isAuthenticated: { _ in true })
        #expect(ids == ["c1", "x1"])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AccountStoreProviderTests`
Expected: FAIL — `canAddAccount(provider:)` not defined.

- [ ] **Step 3: Implement**

In `AccountStore.swift`:

```swift
/// Maximum number of accounts per provider (3 Claude + 3 Codex).
nonisolated static let maxAccountsPerProvider = 3

public func accounts(for provider: AIProvider) -> [AccountRecord] {
    accounts.filter { $0.provider == provider }
}

public func canAddAccount(provider: AIProvider) -> Bool {
    accounts(for: provider).count < Self.maxAccountsPerProvider
}

public var canAddAccount: Bool {
    AIProvider.allCases.contains { canAddAccount(provider: $0) }
}

/// Claude block first, insertion order preserved within each provider.
/// Single source of display order for picker, fan-out, and menu bar.
nonisolated static func displayOrdered(_ accounts: [AccountRecord]) -> [AccountRecord] {
    accounts.filter { $0.provider == .claude } + accounts.filter { $0.provider == .codex }
}
```

Replace the old `maxAccounts` constant and its two uses: the `add()` guard becomes

```swift
guard accounts(for: record.provider).count < Self.maxAccountsPerProvider else {
    AppLogger.oauth.warning("Cannot add account — max \(Self.maxAccountsPerProvider) \(record.provider.rawValue, privacy: .public) accounts reached")
    return
}
```

and delete `nonisolated static let maxAccounts = 3`. Grep for remaining `maxAccounts` references and update each to `maxAccountsPerProvider` — one KNOWN site: `OAuthManager.AuthError.userMessage` (`OAuthManager.swift` ~line 191) interpolates `AccountStore.maxAccounts`; change its copy to `"Maximum of \(AccountStore.maxAccountsPerProvider) accounts per provider reached. Remove one before adding another."`. In the existing `multiAccountDisplayIDs(accounts:isAuthenticated:)` static, wrap the input: `displayOrdered(accounts).filter { !$0.isPendingIdentity }.filter { isAuthenticated($0.id) }.map(\.id)`.

- [ ] **Step 4: Run tests**

Run: `swift test --filter AccountStoreProviderTests && swift test --filter AccountStoreTests && swift test --filter MultiAccountFanOut`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add AIBattery/Services/AccountStore.swift Tests/AIBatteryCoreTests/Services/AccountStoreProviderTests.swift
git commit -m "feat: per-provider account cap (3+3) and Claude-first display ordering"
```

---

### Task 3: RateLimitUsage provider awareness

**Files:**
- Modify: `AIBattery/Models/RateLimitUsage.swift`
- Modify: `AIBattery/Views/UsageBarsSection.swift` (the `label: "7-Day"` literal)
- Test: `Tests/AIBatteryCoreTests/Models/RateLimitUsageProviderTests.swift`

**Interfaces:**
- Consumes: `AIProvider` (Task 1).
- Produces: `RateLimitUsage.provider: AIProvider` (decode default `.claude`), `fiveHourWindowMinutes: Int?`, `sevenDayWindowMinutes: Int?` (decode default nil), `var sevenDayDisplayLabel: String`. Explicit memberwise init with defaults `provider: .claude, fiveHourWindowMinutes: nil, sevenDayWindowMinutes: nil` so every existing construction site compiles unchanged.

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
@testable import AIBatteryCore

@Suite("RateLimitUsage provider")
struct RateLimitUsageProviderTests {
    @Test func decodesLegacyPersistedJSONWithoutProviderFields() throws {
        // Shape persisted by v2.6.1 under aibattery_rateLimits_* — no provider key.
        let legacy = Data("""
        {"representativeClaim":"five_hour","fiveHourUtilization":0.42,"fiveHourReset":700000000,
         "fiveHourStatus":"allowed","sevenDayUtilization":0.1,"sevenDayReset":700400000,
         "sevenDayStatus":"allowed","overallStatus":"allowed"}
        """.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let usage = try decoder.decode(RateLimitUsage.self, from: legacy)
        #expect(usage.provider == .claude)
        #expect(usage.fiveHourWindowMinutes == nil)
        #expect(usage.sevenDayDisplayLabel == "7-Day")
    }

    @Test func codexProviderDrivesLabels() {
        let usage = RateLimitUsage(
            representativeClaim: RateLimitUsage.fiveHourWindow,
            fiveHourUtilization: 0.21, fiveHourReset: Date(), fiveHourStatus: "allowed",
            sevenDayUtilization: 0.03, sevenDayReset: Date(), sevenDayStatus: "allowed",
            overallStatus: "allowed",
            provider: .codex, fiveHourWindowMinutes: 300, sevenDayWindowMinutes: 10080
        )
        #expect(usage.sevenDayDisplayLabel == "Weekly")
        #expect(usage.provider == .codex)
    }

    @Test func existingCallSitesCompileViaDefaults() {
        let usage = RateLimitUsage(
            representativeClaim: RateLimitUsage.sevenDayWindow,
            fiveHourUtilization: 0.5, fiveHourReset: nil, fiveHourStatus: "allowed",
            sevenDayUtilization: 0.9, sevenDayReset: nil, sevenDayStatus: "allowed",
            overallStatus: "allowed"
        )
        #expect(usage.provider == .claude)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter RateLimitUsageProviderTests`
Expected: FAIL — no `provider` member.

- [ ] **Step 3: Implement**

In `RateLimitUsage.swift` add stored properties + init + decode tolerance:

```swift
/// Which provider produced this reading. Decodes as `.claude` for pre-v2.7
/// persisted snapshots. Drives window labels only — thresholds and guards
/// are provider-neutral.
let provider: AIProvider
/// Actual window durations from the provider payload (Codex sends them;
/// Anthropic doesn't — nil means "assume 300 / 10080").
let fiveHourWindowMinutes: Int?
let sevenDayWindowMinutes: Int?

/// "7-Day" for Claude, "Weekly" for Codex — same 7-day window, provider vocabulary.
var sevenDayDisplayLabel: String { provider.secondaryWindowLabel }

init(
    representativeClaim: String,
    fiveHourUtilization: Double, fiveHourReset: Date?, fiveHourStatus: String,
    sevenDayUtilization: Double, sevenDayReset: Date?, sevenDayStatus: String,
    overallStatus: String,
    provider: AIProvider = .claude,
    fiveHourWindowMinutes: Int? = nil,
    sevenDayWindowMinutes: Int? = nil
) {
    self.representativeClaim = representativeClaim
    self.fiveHourUtilization = fiveHourUtilization
    self.fiveHourReset = fiveHourReset
    self.fiveHourStatus = fiveHourStatus
    self.sevenDayUtilization = sevenDayUtilization
    self.sevenDayReset = sevenDayReset
    self.sevenDayStatus = sevenDayStatus
    self.overallStatus = overallStatus
    self.provider = provider
    self.fiveHourWindowMinutes = fiveHourWindowMinutes
    self.sevenDayWindowMinutes = sevenDayWindowMinutes
}

init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    representativeClaim = try c.decode(String.self, forKey: .representativeClaim)
    fiveHourUtilization = try c.decode(Double.self, forKey: .fiveHourUtilization)
    fiveHourReset = try c.decodeIfPresent(Date.self, forKey: .fiveHourReset)
    fiveHourStatus = try c.decode(String.self, forKey: .fiveHourStatus)
    sevenDayUtilization = try c.decode(Double.self, forKey: .sevenDayUtilization)
    sevenDayReset = try c.decodeIfPresent(Date.self, forKey: .sevenDayReset)
    sevenDayStatus = try c.decode(String.self, forKey: .sevenDayStatus)
    overallStatus = try c.decode(String.self, forKey: .overallStatus)
    provider = try c.decodeIfPresent(AIProvider.self, forKey: .provider) ?? .claude
    fiveHourWindowMinutes = try c.decodeIfPresent(Int.self, forKey: .fiveHourWindowMinutes)
    sevenDayWindowMinutes = try c.decodeIfPresent(Int.self, forKey: .sevenDayWindowMinutes)
}
```

IMPORTANT: every mutating-copy helper on this type (`markedThrottled()`, `withClearedExpiredWindows()`, `withClearedRolloverArtifacts()`, and any other `RateLimitUsage(...)` constructions inside the struct) must pass through `provider:`, `fiveHourWindowMinutes:`, `sevenDayWindowMinutes:` — grep the file for `RateLimitUsage(` and thread all three, otherwise a cleared/normalized Codex reading silently reverts to `.claude` labels. Update `bindingWindowLabel` to `bindingValue(fiveHour: "5-hour", sevenDay: provider == .codex ? "Weekly" : "7-day")` and `bindingWindowShortCode` to `bindingValue(fiveHour: "5H", sevenDay: provider.secondaryWindowShortCode)`. In `UsageBarsSection.swift`, change `label: "7-Day"` to `label: limits.sevenDayDisplayLabel`.

- [ ] **Step 4: Run tests**

Run: `swift test --filter RateLimitUsageProviderTests && swift test --filter RateLimitUsage`
Expected: PASS, including all pre-existing RateLimitUsage suites (spike filter, rollover guard).

- [ ] **Step 5: Commit**

```bash
git add AIBattery/Models/RateLimitUsage.swift AIBattery/Views/UsageBarsSection.swift Tests/AIBatteryCoreTests/Models/RateLimitUsageProviderTests.swift
git commit -m "feat: provider-aware RateLimitUsage with data-driven window durations"
```

---

### Task 4: RateLimitSource Codex cases

**Files:**
- Modify: `AIBattery/Models/RateLimitSource.swift`
- Test: `Tests/AIBatteryCoreTests/Models/RateLimitSourceTests.swift` (create if absent; extend if present)

**Interfaces:**
- Produces: `case codexUsageEndpoint` (shortLabel "Via OpenAI API"), `case codexSessionLog` (shortLabel "Via Codex CLI").

- [ ] **Step 1: Write the failing test**

```swift
import Testing
@testable import AIBatteryCore

@Suite("RateLimitSource codex")
struct RateLimitSourceCodexTests {
    @Test func codexCasesHaveLabels() {
        #expect(RateLimitSource.codexUsageEndpoint.shortLabel == "Via OpenAI API")
        #expect(RateLimitSource.codexSessionLog.shortLabel == "Via Codex CLI")
        #expect(!RateLimitSource.codexUsageEndpoint.explanation.isEmpty)
        #expect(!RateLimitSource.codexSessionLog.explanation.isEmpty)
    }
}
```

- [ ] **Step 2: Run to verify failure** — `swift test --filter RateLimitSourceCodexTests` → FAIL.

- [ ] **Step 3: Implement** — add to the enum:

```swift
case codexUsageEndpoint
case codexSessionLog
```

with `shortLabel` arms `"Via OpenAI API"` / `"Via Codex CLI"` and `explanation` arms `"Usage data from OpenAI's ChatGPT usage endpoint."` / `"Usage data from the newest Codex CLI session log on this Mac (endpoint unreachable)."`.

- [ ] **Step 4: Run tests** — `swift test --filter RateLimitSource` → PASS.

- [ ] **Step 5: Commit**

```bash
git add AIBattery/Models/RateLimitSource.swift Tests/AIBatteryCoreTests/Models/RateLimitSourceTests.swift
git commit -m "feat: add Codex rate-limit source cases"
```

---

### Task 5: Extract OAuthPKCE shared helper

**Files:**
- Create: `AIBattery/Utilities/OAuthPKCE.swift`
- Modify: `AIBattery/Services/OAuthManager.swift` (delete private `generateRandomState()` / `generatePKCE()`, call the helper; the `Data.base64URLEncoded()` extension MOVES to the new file)
- Test: `Tests/AIBatteryCoreTests/Utilities/OAuthPKCETests.swift`

**Interfaces:**
- Produces: `enum OAuthPKCE { static func generateState() -> String; static func generatePKCE() -> (verifier: String, challenge: String) }` — exact behavior of the current OAuthManager privates (verifier: 64 random bytes base64url; challenge: SHA-256 of verifier ASCII, base64url; state: 32 random bytes base64url). Copy the existing implementations verbatim; this is a move, not a rewrite.

- [ ] **Step 1: Write the failing test**

```swift
import CryptoKit
import Foundation
import Testing
@testable import AIBatteryCore

@Suite("OAuthPKCE")
struct OAuthPKCETests {
    @Test func challengeIsSHA256OfVerifier() {
        let (verifier, challenge) = OAuthPKCE.generatePKCE()
        let expected = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded()
        #expect(challenge == expected)
        #expect(verifier.count >= 43) // RFC 7636 minimum
        #expect(!verifier.contains("+") && !verifier.contains("/") && !verifier.contains("="))
    }

    @Test func stateIsUniqueAndURLSafe() {
        let a = OAuthPKCE.generateState()
        let b = OAuthPKCE.generateState()
        #expect(a != b)
        #expect(!a.contains("+") && !a.contains("/") && !a.contains("="))
    }
}
```

- [ ] **Step 2: Run to verify failure** — `swift test --filter OAuthPKCETests` → FAIL.

- [ ] **Step 3: Implement** — create `OAuthPKCE.swift` housing the moved code (bodies copied verbatim from `OAuthManager.generateRandomState` / `generatePKCE`, plus the `Data.base64URLEncoded()` extension currently at the bottom of OAuthManager.swift). In OAuthManager, replace `generateRandomState()` → `OAuthPKCE.generateState()` and `generatePKCE()` → `OAuthPKCE.generatePKCE()` at their call sites (inside `startAuthFlow`).

- [ ] **Step 4: Run tests** — `swift test --filter OAuthPKCETests && swift test --filter OAuth` → PASS (existing OAuth suites prove the move broke nothing).

- [ ] **Step 5: Commit**

```bash
git add AIBattery/Utilities/OAuthPKCE.swift AIBattery/Services/OAuthManager.swift Tests/AIBatteryCoreTests/Utilities/OAuthPKCETests.swift
git commit -m "refactor: extract shared OAuthPKCE helper from OAuthManager"
```

---

### Task 6: CodexPaths, CodexOAuthConstants, JWTDecoder

**Files:**
- Create: `AIBattery/Utilities/CodexPaths.swift`
- Create: `AIBattery/Services/CodexOAuth/CodexOAuthConstants.swift`
- Create: `AIBattery/Utilities/JWTDecoder.swift`
- Test: `Tests/AIBatteryCoreTests/Services/CodexOAuthConstantsTests.swift`, `Tests/AIBatteryCoreTests/Utilities/JWTDecoderTests.swift`

**Interfaces:**
- Produces:
  - `enum CodexPaths { static let root/sessions/authJSON: URL; static let sessionsPath/authJSONPath: String }` (`~/.codex`, `~/.codex/sessions`, `~/.codex/auth.json`).
  - `enum CodexOAuthConstants { static let clientId, issuer, scope, originator: String; static let callbackPort: UInt16; static var redirectURI: String; static var tokenURL: URL; static func buildAuthorizeURL(codeChallenge: String, state: String) -> URL }`.
  - `enum JWTDecoder { static func payload(_ jwt: String) -> [String: Any]?; static func chatGPTAccountId(idToken: String) -> String?; static func expiry(_ jwt: String) -> Date? }`.

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing
@testable import AIBatteryCore

@Suite("CodexOAuthConstants")
struct CodexOAuthConstantsTests {
    @Test func authorizeURLCarriesAllRequiredParams() throws {
        let url = CodexOAuthConstants.buildAuthorizeURL(codeChallenge: "CHAL", state: "STATE123")
        let comps = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(comps.scheme == "https")
        #expect(comps.host == "auth.openai.com")
        #expect(comps.path == "/oauth/authorize")
        let q = Dictionary(uniqueKeysWithValues: (comps.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(q["response_type"] == "code")
        #expect(q["client_id"] == "app_EMoamEEZ73f0CkXaXp7hrann")
        #expect(q["redirect_uri"] == "http://localhost:1455/auth/callback")
        #expect(q["scope"] == "openid profile email offline_access api.connectors.read api.connectors.invoke")
        #expect(q["code_challenge"] == "CHAL")
        #expect(q["code_challenge_method"] == "S256")
        #expect(q["id_token_add_organizations"] == "true")
        #expect(q["codex_cli_simplified_flow"] == "true")
        #expect(q["state"] == "STATE123")
        #expect(q["originator"] == "codex_cli_rs")
    }
}

@Suite("JWTDecoder")
struct JWTDecoderTests {
    /// Build an unsigned test JWT: header.payload.fakesig with base64url segments.
    private func jwt(payload: [String: Any]) -> String {
        let header = Data(#"{"alg":"none"}"#.utf8).base64URLEncoded()
        let body = (try! JSONSerialization.data(withJSONObject: payload)).base64URLEncoded()
        return "\(header).\(body).sig"
    }

    @Test func extractsChatGPTAccountId() {
        let token = jwt(payload: [
            "https://api.openai.com/auth": ["chatgpt_account_id": "acc-uuid-42"],
            "exp": 1_900_000_000,
        ])
        #expect(JWTDecoder.chatGPTAccountId(idToken: token) == "acc-uuid-42")
        #expect(JWTDecoder.expiry(token) == Date(timeIntervalSince1970: 1_900_000_000))
    }

    @Test func malformedTokensReturnNil() {
        #expect(JWTDecoder.payload("not-a-jwt") == nil)
        #expect(JWTDecoder.chatGPTAccountId(idToken: "a.!!!.c") == nil)
        #expect(JWTDecoder.expiry("") == nil)
    }
}
```

- [ ] **Step 2: Run to verify failure** — `swift test --filter CodexOAuthConstantsTests` and `--filter JWTDecoderTests` → FAIL.

- [ ] **Step 3: Implement**

`CodexPaths.swift` (mirror ClaudePaths):

```swift
import Foundation

/// Centralized file paths for Codex CLI data. Read-only — AIBattery never writes here.
enum CodexPaths {
    private static let home = FileManager.default.homeDirectoryForCurrentUser
    /// `~/.codex/`
    static let root: URL = home.appendingPathComponent(".codex")
    /// `~/.codex/sessions/` — rollout JSONL, nested YYYY/MM/DD
    static let sessions: URL = root.appendingPathComponent("sessions")
    static let sessionsPath: String = sessions.path
    /// `~/.codex/auth.json` — the CLI's own login (import convenience)
    static let authJSON: URL = root.appendingPathComponent("auth.json")
    static let authJSONPath: String = authJSON.path
}
```

`CodexOAuthConstants.swift`:

```swift
import Foundation

/// OpenAI OAuth constants — lifted verbatim from the open-source Codex CLI
/// (codex-rs/login). The client-id is the CLI's public app id, not a secret.
enum CodexOAuthConstants {
    static let clientId = "app_EMoamEEZ73f0CkXaXp7hrann"
    static let issuer = "https://auth.openai.com"
    static let callbackPort: UInt16 = 1455
    static var redirectURI: String { "http://localhost:\(callbackPort)/auth/callback" }
    static let scope = "openid profile email offline_access api.connectors.read api.connectors.invoke"
    static let originator = "codex_cli_rs"
    static var tokenURL: URL { URL(string: "\(issuer)/oauth/token")! }

    static func buildAuthorizeURL(codeChallenge: String, state: String) -> URL {
        var comps = URLComponents(string: "\(issuer)/oauth/authorize")!
        comps.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "id_token_add_organizations", value: "true"),
            URLQueryItem(name: "codex_cli_simplified_flow", value: "true"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "originator", value: originator),
        ]
        return comps.url!
    }
}
```

`JWTDecoder.swift`:

```swift
import Foundation

/// Minimal JWT payload reader. NO signature verification — we only read claims
/// from tokens we just received over TLS from the issuer; the tokens are the
/// credential, the claims are informational (account id, expiry).
enum JWTDecoder {
    static func payload(_ jwt: String) -> [String: Any]? {
        let segments = jwt.split(separator: ".")
        guard segments.count == 3 else { return nil }
        var base64 = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }
        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }

    /// ChatGPT account id from the id_token's OpenAI auth claim.
    static func chatGPTAccountId(idToken: String) -> String? {
        let auth = payload(idToken)?["https://api.openai.com/auth"] as? [String: Any]
        return auth?["chatgpt_account_id"] as? String
    }

    /// `exp` claim as a Date (nil when absent/malformed).
    static func expiry(_ jwt: String) -> Date? {
        guard let exp = payload(jwt)?["exp"] as? TimeInterval else { return nil }
        return Date(timeIntervalSince1970: exp)
    }
}
```

- [ ] **Step 4: Run tests** — both filters → PASS.

- [ ] **Step 5: Commit**

```bash
git add AIBattery/Utilities/CodexPaths.swift AIBattery/Utilities/JWTDecoder.swift AIBattery/Services/CodexOAuth/CodexOAuthConstants.swift Tests/AIBatteryCoreTests/Services/CodexOAuthConstantsTests.swift Tests/AIBatteryCoreTests/Utilities/JWTDecoderTests.swift
git commit -m "feat: Codex OAuth constants, paths, and JWT claim reader"
```

---

### Task 7: Codex callback parser + localhost server

**Files:**
- Create: `AIBattery/Services/CodexOAuth/CodexCallbackServer.swift`
- Test: `Tests/AIBatteryCoreTests/Services/CodexCallbackParserTests.swift`

**Interfaces:**
- Consumes: `CodexOAuthConstants.callbackPort` (Task 6).
- Produces:
  - `enum CodexCallbackParser { static func parse(requestHead: String) -> Result<(code: String, state: String), CodexCallbackError> }`
  - `enum CodexCallbackError: Error, Equatable { case notCallbackPath, missingCode, missingState, providerError(String) }`
  - `final class CodexCallbackServer: @unchecked Sendable { init(port: UInt16 = CodexOAuthConstants.callbackPort); func start(onRequest: @escaping @Sendable (Result<(code: String, state: String), CodexCallbackError>) -> Void) throws; func stop() }` — one-shot listener; replies with a small HTML "You're signed in — return to AI Battery." page and stops itself after the first `/auth/callback` hit.

- [ ] **Step 1: Write the failing test** (parser only — the NWListener is exercised in the Task 16 manual smoke test, not unit-tested; port binding on CI is flaky by nature)

```swift
import Testing
@testable import AIBatteryCore

@Suite("CodexCallbackParser")
struct CodexCallbackParserTests {
    @Test func parsesCodeAndState() throws {
        let head = "GET /auth/callback?code=abc123&state=xyz789 HTTP/1.1"
        let parsed = try CodexCallbackParser.parse(requestHead: head).get()
        #expect(parsed.code == "abc123")
        #expect(parsed.state == "xyz789")
    }

    @Test func percentDecodesValues() throws {
        let head = "GET /auth/callback?state=s%2B1&code=c%2Fx HTTP/1.1"
        let parsed = try CodexCallbackParser.parse(requestHead: head).get()
        #expect(parsed.code == "c/x")
        #expect(parsed.state == "s+1")
    }

    @Test func surfacesProviderError() {
        let head = "GET /auth/callback?error=access_denied HTTP/1.1"
        #expect(CodexCallbackParser.parse(requestHead: head) == .failure(.providerError("access_denied")))
    }

    @Test func rejectsOtherPathsAndMissingParams() {
        #expect(CodexCallbackParser.parse(requestHead: "GET /favicon.ico HTTP/1.1") == .failure(.notCallbackPath))
        #expect(CodexCallbackParser.parse(requestHead: "GET /auth/callback?state=s HTTP/1.1") == .failure(.missingCode))
        #expect(CodexCallbackParser.parse(requestHead: "GET /auth/callback?code=c HTTP/1.1") == .failure(.missingState))
    }
}
```

- [ ] **Step 2: Run to verify failure** — `swift test --filter CodexCallbackParserTests` → FAIL.

- [ ] **Step 3: Implement**

```swift
import Foundation
import Network

enum CodexCallbackError: Error, Equatable {
    case notCallbackPath
    case missingCode
    case missingState
    case providerError(String)
}

/// Pure parser for the OAuth redirect's HTTP request line. Split from the
/// server so the extraction contract is unit-testable without sockets.
enum CodexCallbackParser {
    static func parse(requestHead: String) -> Result<(code: String, state: String), CodexCallbackError> {
        // "GET /auth/callback?code=…&state=… HTTP/1.1"
        let parts = requestHead.split(separator: " ")
        guard parts.count >= 2,
              let comps = URLComponents(string: String(parts[1])),
              comps.path == "/auth/callback" else {
            return .failure(.notCallbackPath)
        }
        let items = comps.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        if let error = value("error") { return .failure(.providerError(error)) }
        guard let code = value("code"), !code.isEmpty else { return .failure(.missingCode) }
        guard let state = value("state"), !state.isEmpty else { return .failure(.missingState) }
        return .success((code: code, state: state))
    }
}

/// One-shot localhost HTTP listener for the OpenAI OAuth redirect
/// (`http://localhost:1455/auth/callback`). Started when the Codex sign-in
/// button opens the browser; stops itself after the first callback hit or
/// on `stop()` (cancel / popover closed). Non-callback paths (favicon…)
/// get a 404 and the listener keeps waiting.
final class CodexCallbackServer: @unchecked Sendable {
    private let port: UInt16
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "codex-oauth-callback")

    init(port: UInt16 = CodexOAuthConstants.callbackPort) {
        self.port = port
    }

    func start(onRequest: @escaping @Sendable (Result<(code: String, state: String), CodexCallbackError>) -> Void) throws {
        let listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: port)!)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in
            connection.start(queue: self?.queue ?? .global())
            connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { data, _, _, _ in
                guard let data, let head = String(data: data, encoding: .utf8)?
                    .components(separatedBy: "\r\n").first else {
                    connection.cancel()
                    return
                }
                let result = CodexCallbackParser.parse(requestHead: head)
                if case .failure(.notCallbackPath) = result {
                    Self.respond(connection, status: "404 Not Found", body: "Not found") { }
                    return // keep listening — this was favicon or noise
                }
                let message = (try? result.get()) != nil
                    ? "You're signed in — return to AI Battery."
                    : "Sign-in failed — return to AI Battery and try again."
                Self.respond(connection, status: "200 OK",
                             body: "<html><body style=\"font-family:-apple-system\"><h3>\(message)</h3></body></html>") { [weak self] in
                    self?.stop()
                    onRequest(result)
                }
            }
        }
        listener.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private static func respond(_ connection: NWConnection, status: String, body: String, then: @escaping @Sendable () -> Void) {
        let payload = "HTTP/1.1 \(status)\r\nContent-Type: text/html\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        connection.send(content: Data(payload.utf8), completion: .contentProcessed { _ in
            connection.cancel()
            then()
        })
    }
}
```

- [ ] **Step 4: Run tests** — `swift test --filter CodexCallbackParserTests` → PASS. Also `swift build` (Network.framework import compiles).

- [ ] **Step 5: Commit**

```bash
git add AIBattery/Services/CodexOAuth/CodexCallbackServer.swift Tests/AIBatteryCoreTests/Services/CodexCallbackParserTests.swift
git commit -m "feat: localhost OAuth callback server for Codex sign-in"
```

---

### Task 8: CodexTokenClient (exchange + refresh)

**Files:**
- Create: `AIBattery/Services/CodexOAuth/CodexTokenClient.swift`
- Test: `Tests/AIBatteryCoreTests/Services/CodexTokenClientTests.swift`

**Interfaces:**
- Consumes: `CodexOAuthConstants` (Task 6), existing `OAuthManager.AuthError` (nested enum, OAuthManager.swift:175 — reuse it, qualified as `OAuthManager.AuthError` from other files; do NOT define a new error enum), existing `RetryPolicy.oauth`, `SecureNetworking.data(for:)`.
- Produces:
  - `struct CodexTokenSet: Equatable { let idToken: String; let accessToken: String; let refreshToken: String? }`
  - `enum CodexTokenClient` with:
    - `nonisolated static func interpretTokenResponse(statusCode: Int, data: Data) -> Result<CodexTokenSet, AuthError>` — pure.
    - `static func exchangeCode(_ code: String, verifier: String, transport: @Sendable (URLRequest) async throws -> (Data, URLResponse) = { try await SecureNetworking.data(for: $0) }) async -> Result<CodexTokenSet, AuthError>` — form-urlencoded POST.
    - `static func refresh(refreshToken: String, transport: …same default…) async -> Result<CodexTokenSet, AuthError>` — JSON POST, retries 5xx up to `RetryPolicy.oauth.maxRetries` with its backoff (mirror `OAuthManager.postToken`'s loop — copy the retry loop structure from OAuthManager.swift:427-460, only the request construction differs).

Error mapping in `interpretTokenResponse` (locked; `OAuthManager.AuthError.isTransient` treats `.networkError`/`.serverError` as transient, everything else as fatal-auth): 2xx + parseable `{id_token, access_token, refresh_token?}` → `.success`; 400 → `.failure(.invalidCode)`; 401/403 → `.failure(.expired)`; 5xx → `.failure(.serverError(code))` (transient — retried by the loop, and callers keep auth state); unparseable 2xx body or other statuses → `.failure(.unknownError("Token endpoint returned <code>"))`.

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
@testable import AIBatteryCore

@Suite("CodexTokenClient")
struct CodexTokenClientTests {
    private let goodBody = Data("""
    {"id_token":"id.tok.en","access_token":"at.tok.en","refresh_token":"rt-1"}
    """.utf8)

    @Test func successParsesTokenSet() throws {
        let set = try CodexTokenClient.interpretTokenResponse(statusCode: 200, data: goodBody).get()
        #expect(set == CodexTokenSet(idToken: "id.tok.en", accessToken: "at.tok.en", refreshToken: "rt-1"))
    }

    @Test func missingRefreshTokenIsAllowed() throws {
        let body = Data(#"{"id_token":"i","access_token":"a"}"#.utf8)
        let set = try CodexTokenClient.interpretTokenResponse(statusCode: 200, data: body).get()
        #expect(set.refreshToken == nil)
    }

    @Test func authFailureIsNotTransient() {
        let result = CodexTokenClient.interpretTokenResponse(statusCode: 400, data: Data())
        guard case .failure(let error) = result else { Issue.record("expected failure"); return }
        #expect(!error.isTransient) // adjust to the AuthError API found in OAuthManager.swift
    }

    @Test func exchangeSendsFormEncodedBody() async throws {
        let captured = CapturedRequest()
        _ = await CodexTokenClient.exchangeCode("CODE1", verifier: "VERIF", transport: { request in
            await captured.set(request)
            return (Data("{\"id_token\":\"i\",\"access_token\":\"a\",\"refresh_token\":\"r\"}".utf8),
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let request = await captured.get()!
        #expect(request.url == CodexOAuthConstants.tokenURL)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
        let body = String(data: request.httpBody!, encoding: .utf8)!
        #expect(body.contains("grant_type=authorization_code"))
        #expect(body.contains("code=CODE1"))
        #expect(body.contains("code_verifier=VERIF"))
        #expect(body.contains("client_id=app_EMoamEEZ73f0CkXaXp7hrann"))
    }

    @Test func refreshSendsJSONBody() async throws {
        let captured = CapturedRequest()
        _ = await CodexTokenClient.refresh(refreshToken: "rt-9", transport: { request in
            await captured.set(request)
            return (Data("{\"id_token\":\"i\",\"access_token\":\"a\"}".utf8),
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let request = await captured.get()!
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let json = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: String]
        #expect(json["grant_type"] == "refresh_token")
        #expect(json["refresh_token"] == "rt-9")
        #expect(json["client_id"] == "app_EMoamEEZ73f0CkXaXp7hrann")
        #expect(json["scope"] == "openid profile email")
    }
}

/// Tiny actor to capture the request from the @Sendable transport closure.
actor CapturedRequest {
    private var request: URLRequest?
    func set(_ r: URLRequest) { request = r }
    func get() -> URLRequest? { request }
}
```

(`OAuthManager.AuthError.isTransient` exists — `.networkError`/`.serverError` are transient, everything else is not. 400/401 must map to a NON-transient case: use `.invalidCode` for 400 and `.expired` for 401, matching what the exchange semantically means.)

- [ ] **Step 2: Run to verify failure** — `swift test --filter CodexTokenClientTests` → FAIL.

- [ ] **Step 3: Implement** `CodexTokenClient.swift`: `CodexTokenSet` struct; `interpretTokenResponse` decoding `{id_token, access_token, refresh_token?}` via a private Decodable struct with snake_case keys; `exchangeCode` building the form body via `URLComponents` query items and reading `percentEncodedQuery` (correct form-urlencoding without hand-rolled escaping); `refresh` serializing the JSON dict; both looping attempts per `RetryPolicy.oauth` on 5xx/transport error exactly like `postToken`. Never log token values — log status codes only via `AppLogger.oauth`.

- [ ] **Step 4: Run tests** — `swift test --filter CodexTokenClientTests` → PASS.

- [ ] **Step 5: Commit**

```bash
git add AIBattery/Services/CodexOAuth/CodexTokenClient.swift Tests/AIBatteryCoreTests/Services/CodexTokenClientTests.swift
git commit -m "feat: Codex token exchange and refresh client"
```

---

### Task 9: OAuthManager Codex integration (flow, storage routing, refresh routing)

**Files:**
- Create: `AIBattery/Services/CodexOAuth/CodexAuthSession.swift`
- Create: `AIBattery/Services/OAuthManager+Codex.swift`
- Modify: `AIBattery/Services/OAuthManager.swift` (one stored property + provider routing in 4 methods)
- Test: `Tests/AIBatteryCoreTests/Services/OAuthManagerCodexRoutingTests.swift`

**Interfaces:**
- Consumes: Tasks 5–8 outputs, `OAuthTokenStorage`, `AccountStore`.
- Produces:
  - `@MainActor final class CodexAuthSession { let verifier: String; let state: String; let server: CodexCallbackServer; static func begin() throws -> (session: CodexAuthSession, browserURL: URL) }`
  - On `OAuthManager`:
    - stored `var codexAuthSession: CodexAuthSession?` (internal, so the extension file can use it)
    - `func startCodexAuthFlow() -> URL?` — begins session, starts server, returns browser URL (nil + logged error when port 1455 is taken).
    - `func completeCodexAuthFlow() async -> Result<Void, AuthError>` — awaits the server callback (via `withCheckedContinuation` bridged in the session), validates `state`, exchanges code, derives account id from the id_token claim, saves tokens, adds `AccountRecord(id: accountId, billingType: nil, addedAt: .now, provider: .codex)`, `updateAuthState()`. Codex accounts are NEVER `pending-*` — identity is known at exchange time.
    - `func cancelCodexAuthFlow()` — stops server, clears session.
    - `nonisolated static func tokenStorageKey(accountId: String, provider: AIProvider) -> String` → `.codex` → `"codex_\(accountId)"`, `.claude` → `accountId` (Keychain item becomes `refreshToken_codex_<id>` — matches spec §2).
  - Provider routing inside existing methods (each gets a lookup `let provider = accountStore.accounts.first { $0.id == id }?.provider ?? .claude`):
    - `saveTokens(for:)` / `loadTokens(for:)` / `deleteTokens(for:)` route through `tokenStorageKey` (in-memory `tokens` dict stays keyed by RAW account id).
    - `refreshAccessToken(_:accountId:)`: for `.codex`, call `CodexTokenClient.refresh`; on success store `accessToken`, rotate `refreshToken` if returned, `expiresAt = JWTDecoder.expiry(accessToken) ?? Date().addingTimeInterval(3600)`, save; on auth-error sign out (existing behavior); on transient error return nil keeping auth state — mirror the existing Anthropic branch structure line by line.
    - `getAccessToken(for:)` / `isAuthenticated(accountId:)` / `signOut(accountId:)` need NO routing changes (they operate on the `tokens` dict and call the routed internals) — verify by reading them after the change; `signOut` must also call `cancelCodexAuthFlow()` when the removed account is `.codex`.

- [ ] **Step 1: Write the failing test** (pure parts only — flow needs a browser; storage-key routing and record creation are testable)

```swift
import Foundation
import Testing
@testable import AIBatteryCore

@Suite("OAuthManager codex routing")
@MainActor
struct OAuthManagerCodexRoutingTests {
    @Test func storageKeyIsProviderScoped() {
        #expect(OAuthManager.tokenStorageKey(accountId: "acc-1", provider: .codex) == "codex_acc-1")
        #expect(OAuthManager.tokenStorageKey(accountId: "org-1", provider: .claude) == "org-1")
    }

    @Test func codexAccountRecordFromIdToken() {
        // The account-creation helper (extracted for testability) builds a
        // non-pending record with provider .codex from a raw account id.
        let record = OAuthManager.makeCodexAccountRecord(accountId: "acc-uuid-7", addedAt: Date(timeIntervalSince1970: 1000))
        #expect(record.id == "acc-uuid-7")
        #expect(record.provider == .codex)
        #expect(!record.isPendingIdentity)
    }
}
```

- [ ] **Step 2: Run to verify failure** — `swift test --filter OAuthManagerCodexRoutingTests` → FAIL.

- [ ] **Step 3: Implement**

`CodexAuthSession.swift`:

```swift
import Foundation

/// Holds the in-flight Codex OAuth state: PKCE verifier, CSRF state, and the
/// one-shot localhost callback server. One stored property on OAuthManager
/// instead of three; discarded when the flow completes or is cancelled.
@MainActor
final class CodexAuthSession {
    let verifier: String
    let state: String
    let server: CodexCallbackServer
    private var continuation: CheckedContinuation<Result<(code: String, state: String), CodexCallbackError>, Never>?

    private init(verifier: String, state: String, server: CodexCallbackServer) {
        self.verifier = verifier
        self.state = state
        self.server = server
    }

    /// Generate PKCE + state, bind the callback port, and produce the browser URL.
    static func begin() throws -> (session: CodexAuthSession, browserURL: URL) {
        let (verifier, challenge) = OAuthPKCE.generatePKCE()
        let state = OAuthPKCE.generateState()
        let server = CodexCallbackServer()
        let session = CodexAuthSession(verifier: verifier, state: state, server: server)
        try server.start { result in
            Task { @MainActor in session.deliver(result) }
        }
        return (session, CodexOAuthConstants.buildAuthorizeURL(codeChallenge: challenge, state: state))
    }

    /// Await the browser redirect. Times out after 180 s so an abandoned
    /// sign-in can't hold port 1455 forever.
    func awaitCallback() async -> Result<(code: String, state: String), CodexCallbackError> {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(180))
                self?.deliver(.failure(.providerError("timeout")))
            }
        }
    }

    private func deliver(_ result: Result<(code: String, state: String), CodexCallbackError>) {
        guard let continuation else { return } // already delivered
        self.continuation = nil
        server.stop()
        continuation.resume(returning: result)
    }

    func cancel() { deliver(.failure(.providerError("cancelled"))) }
}
```

`OAuthManager+Codex.swift` — the flow driver:

```swift
import AppKit
import Foundation

extension OAuthManager {
    nonisolated static func tokenStorageKey(accountId: String, provider: AIProvider) -> String {
        provider == .codex ? "codex_\(accountId)" : accountId
    }

    nonisolated static func makeCodexAccountRecord(accountId: String, addedAt: Date = Date()) -> AccountRecord {
        AccountRecord(id: accountId, addedAt: addedAt, provider: .codex)
    }

    /// Start the Codex browser sign-in. Returns the URL to open, or nil when
    /// the callback port couldn't be bound (typically: Codex CLI login in
    /// progress, or a previous flow still winding down).
    func startCodexAuthFlow() -> URL? {
        cancelCodexAuthFlow()
        do {
            let (session, url) = try CodexAuthSession.begin()
            codexAuthSession = session
            return url
        } catch {
            AppLogger.oauth.error("Codex auth: cannot bind localhost:1455 — \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Await redirect → validate state → exchange code → derive identity → persist.
    func completeCodexAuthFlow() async -> Result<Void, AuthError> {
        guard let session = codexAuthSession else { return .failure(.unknownError("No auth flow in progress")) }
        defer { codexAuthSession = nil }

        let callback = await session.awaitCallback()
        switch callback {
        case .failure(let error):
            return .failure(.unknownError("Sign-in did not complete (\(String(describing: error)))"))
        case .success(let payload):
            guard payload.state == session.state else {
                return .failure(.unknownError("State mismatch — possible CSRF, sign-in aborted"))
            }
            let exchanged = await CodexTokenClient.exchangeCode(payload.code, verifier: session.verifier)
            switch exchanged {
            case .failure(let error):
                return .failure(error)
            case .success(let tokenSet):
                guard let accountId = JWTDecoder.chatGPTAccountId(idToken: tokenSet.idToken) else {
                    return .failure(.unknownError("Could not read account identity from sign-in response"))
                }
                registerCodexAccount(accountId: accountId, tokenSet: tokenSet)
                return .success(())
            }
        }
    }

    func cancelCodexAuthFlow() {
        codexAuthSession?.cancel()
        codexAuthSession = nil
    }

    /// Shared by the OAuth flow and the auth.json importer (Task 10).
    func registerCodexAccount(accountId: String, tokenSet: CodexTokenSet) {
        storeTokens(
            accountId: accountId,
            provider: .codex,
            accessToken: tokenSet.accessToken,
            refreshToken: tokenSet.refreshToken,
            expiresAt: JWTDecoder.expiry(tokenSet.accessToken) ?? Date().addingTimeInterval(3600)
        )
        if !accountStore.accounts.contains(where: { $0.id == accountId }) {
            accountStore.add(Self.makeCodexAccountRecord(accountId: accountId))
        }
        accountStore.setActive(id: accountId)
        updateAuthState()
    }
}
```

In `OAuthManager.swift`:
1. Add `var codexAuthSession: CodexAuthSession?` next to the other flow state.
2. Add the internal helper the extension calls (place near `saveTokens`):

```swift
/// Write a token set into the in-memory cache + persistent storage for any provider.
func storeTokens(accountId: String, provider: AIProvider, accessToken: String?, refreshToken: String?, expiresAt: Date?) {
    tokens[accountId] = OAuthTokenStorage.AccountTokens(
        accessToken: accessToken, refreshToken: refreshToken, expiresAt: expiresAt
    )
    OAuthTokenStorage.save(tokens[accountId]!, for: Self.tokenStorageKey(accountId: accountId, provider: provider))
    if let expiresAt {
        UserDefaults.standard.set(expiresAt.timeIntervalSince1970,
                                  forKey: UserDefaultsKeys.tokenExpiresAtPrefix + Self.tokenStorageKey(accountId: accountId, provider: provider))
    }
}
```

(Adjust to reality: `OAuthTokenStorage.save` already writes the expiry — read that file and don't double-write; the point is: ONE path that maps accountId+provider → storage key.)
3. Route `saveTokens(for:)`, `loadTokens(for:)`, `deleteTokens(for:)` through `tokenStorageKey` — each currently passes the raw `accountId` to `OAuthTokenStorage`; look up the account's provider from `accountStore` (accounts not in the store — mid-add — are `.claude` by default, which is correct because the Anthropic flow is the only one that stores tokens before the record exists).
4. In `refreshAccessToken(_:accountId:)`, branch at the top:

```swift
let provider = accountStore.accounts.first { $0.id == accountId }?.provider ?? .claude
if provider == .codex {
    let result = await CodexTokenClient.refresh(refreshToken: refresh)
    switch result {
    case .success(let set):
        let expires = JWTDecoder.expiry(set.accessToken) ?? Date().addingTimeInterval(3600)
        tokens[accountId] = OAuthTokenStorage.AccountTokens(
            accessToken: set.accessToken,
            refreshToken: set.refreshToken ?? refresh, // rotate only when a new one arrives
            expiresAt: expires
        )
        saveTokens(for: accountId)
        return set.accessToken
    case .failure(let error):
        // Identical disposition to the Anthropic arm below: transient errors
        // (network, 5xx) keep isAuthenticated and retry next cycle; only
        // genuine auth errors sign the account out.
        if error.isTransient {
            AppLogger.oauth.warning("Codex OAuth refresh failed for account \(accountId, privacy: .public) (\(String(describing: error))), will retry next cycle")
        } else {
            signOut(accountId: accountId)
        }
        return nil
    }
}
```

On the success path also call `updateAuthState()` after `saveTokens(for:)` — the Anthropic arm does, and the Codex arm must match.
5. In `signOut`, after `deleteTokens(for: id)` add: if the removed account was `.codex`, `cancelCodexAuthFlow()`.

- [ ] **Step 4: Run tests** — `swift test --filter OAuthManagerCodexRoutingTests && swift test --filter OAuth` → PASS (all existing OAuth suites still green — the Anthropic paths must be untouched behaviorally).

- [ ] **Step 5: Commit**

```bash
git add AIBattery/Services/CodexOAuth/CodexAuthSession.swift AIBattery/Services/OAuthManager+Codex.swift AIBattery/Services/OAuthManager.swift Tests/AIBatteryCoreTests/Services/OAuthManagerCodexRoutingTests.swift
git commit -m "feat: Codex OAuth flow and provider-routed token lifecycle in OAuthManager"
```

---

### Task 10: auth.json importer

**Files:**
- Create: `AIBattery/Services/CodexOAuth/CodexAuthFileImporter.swift`
- Test: `Tests/AIBatteryCoreTests/Services/CodexAuthFileImporterTests.swift`

**Interfaces:**
- Consumes: `CodexPaths.authJSON` (Task 6), `OAuthManager.registerCodexAccount` (Task 9), `CodexTokenSet` (Task 8).
- Produces:
  - `struct CodexImportedAuth: Equatable { let accountId: String; let idToken: String; let accessToken: String; let refreshToken: String }`
  - `enum CodexAuthFileImporter { nonisolated static func parse(_ data: Data) -> CodexImportedAuth?; static var cliLoginAvailable: Bool; @MainActor static func importCurrentLogin(into manager: OAuthManager) -> Result<String, AuthError> }`
  - Import is ONE-TIME SEEDING (spec §2/§6): after import AIBattery refreshes independently; CLI rotation invalidating the seed surfaces as a normal auth failure → re-login.

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
@testable import AIBatteryCore

@Suite("CodexAuthFileImporter")
struct CodexAuthFileImporterTests {
    @Test func parsesChatGPTModeAuthJSON() {
        // Field names verified against a real ~/.codex/auth.json (values faked).
        let json = Data("""
        {"auth_mode":"chatgpt","OPENAI_API_KEY":null,
         "tokens":{"id_token":"id.a.b","access_token":"at.a.b","refresh_token":"rt-1","account_id":"acc-77"},
         "last_refresh":"2026-09-01T09:26:07.000Z"}
        """.utf8)
        let imported = CodexAuthFileImporter.parse(json)
        #expect(imported == CodexImportedAuth(accountId: "acc-77", idToken: "id.a.b", accessToken: "at.a.b", refreshToken: "rt-1"))
    }

    @Test func rejectsAPIKeyModeAndMalformed() {
        let apiKeyMode = Data(#"{"auth_mode":"apikey","OPENAI_API_KEY":"sk-x","tokens":null}"#.utf8)
        #expect(CodexAuthFileImporter.parse(apiKeyMode) == nil)
        #expect(CodexAuthFileImporter.parse(Data("nonsense".utf8)) == nil)
        let missingRefresh = Data(#"{"tokens":{"id_token":"i","access_token":"a","account_id":"x"}}"#.utf8)
        #expect(CodexAuthFileImporter.parse(missingRefresh) == nil)
    }
}
```

- [ ] **Step 2: Run to verify failure** — `swift test --filter CodexAuthFileImporterTests` → FAIL.

- [ ] **Step 3: Implement**

```swift
import Foundation

struct CodexImportedAuth: Equatable {
    let accountId: String
    let idToken: String
    let accessToken: String
    let refreshToken: String
}

/// One-click "Import current Codex CLI login": reads ~/.codex/auth.json and
/// seeds a Codex account from it. One-time seeding — AIBattery refreshes
/// independently afterwards. Never writes back to the file.
enum CodexAuthFileImporter {
    nonisolated static func parse(_ data: Data) -> CodexImportedAuth? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = root["tokens"] as? [String: Any],
              let accountId = tokens["account_id"] as? String,
              let idToken = tokens["id_token"] as? String,
              let accessToken = tokens["access_token"] as? String,
              let refreshToken = tokens["refresh_token"] as? String else {
            return nil
        }
        return CodexImportedAuth(accountId: accountId, idToken: idToken, accessToken: accessToken, refreshToken: refreshToken)
    }

    /// Whether the CLI has a ChatGPT-mode login to import.
    static var cliLoginAvailable: Bool {
        guard let data = try? Data(contentsOf: CodexPaths.authJSON) else { return false }
        return parse(data) != nil
    }

    @MainActor
    static func importCurrentLogin(into manager: OAuthManager) -> Result<String, AuthError> {
        guard let data = try? Data(contentsOf: CodexPaths.authJSON), let imported = parse(data) else {
            return .failure(.unknownError("No Codex CLI login found at ~/.codex/auth.json"))
        }
        guard manager.accountStore.canAddAccount(provider: .codex)
            || manager.accountStore.accounts.contains(where: { $0.id == imported.accountId }) else {
            return .failure(.unknownError("Codex account limit reached (max \(AccountStore.maxAccountsPerProvider))"))
        }
        manager.registerCodexAccount(
            accountId: imported.accountId,
            tokenSet: CodexTokenSet(idToken: imported.idToken, accessToken: imported.accessToken, refreshToken: imported.refreshToken)
        )
        return .success(imported.accountId)
    }
}
```

(If `AuthError` has no `.unknownError` case, use whatever generic case exists — check the enum first.)

- [ ] **Step 4: Run tests** — `swift test --filter CodexAuthFileImporterTests` → PASS.

- [ ] **Step 5: Commit**

```bash
git add AIBattery/Services/CodexOAuth/CodexAuthFileImporter.swift Tests/AIBatteryCoreTests/Services/CodexAuthFileImporterTests.swift
git commit -m "feat: one-click import of Codex CLI login from auth.json"
```

---

### Task 11: CodexUsageParser (wham/usage + session-log snapshots → RateLimitUsage)

**Files:**
- Create: `AIBattery/Models/CodexUsageParser.swift`
- Test: `Tests/AIBatteryCoreTests/Models/CodexUsageParserTests.swift`

**Interfaces:**
- Consumes: `RateLimitUsage` provider-aware init (Task 3).
- Produces:
  - `enum CodexUsageParser`:
    - `nonisolated static func parseUsageResponse(_ data: Data) -> RateLimitUsage?` — wham/usage body.
    - `nonisolated static func parseSessionRateLimits(_ rateLimits: [String: Any]) -> RateLimitUsage?` — the `rate_limits` object from a `token_count` event.
    - `nonisolated static func planType(_ data: Data) -> String?` — `plan_type` from wham/usage (stored as the account's `billingType`).
  - Semantics (locked here, single source of truth):
    - Codex `used_percent` is 0–100 (may be Int or Double in JSON) → divide by 100 for `*Utilization`.
    - wham/usage windows: `rate_limit.primary_window` → fiveHour fields, `.secondary_window` → sevenDay fields; `reset_at`/`resets_at` (accept both spellings) are epoch seconds → `Date(timeIntervalSince1970:)`; `limit_window_seconds/60` or `window_minutes` → `*WindowMinutes`.
    - `representativeClaim` = window with the HIGHER utilization (`seven_day` wins ties only if strictly greater — default `five_hour`).
    - A window with `used_percent >= 100`, or a non-null `rate_limit_reached_type`, marks that window (and `overallStatus`) `"throttled"`; otherwise all statuses `"allowed"`. (`rate_limit_reached_type` values name the exhausted window; when it's non-null but unrecognized, throttle the binding window.)
    - Missing BOTH windows → nil. One missing window → its utilization 0, reset nil, status "allowed".
    - Output always `provider: .codex`.

- [ ] **Step 1: Write the failing test** (fixtures are the real shapes captured during design, values changed)

```swift
import Foundation
import Testing
@testable import AIBatteryCore

@Suite("CodexUsageParser")
struct CodexUsageParserTests {
    // Shape verified against chatgpt.com/backend-api/wham/usage via CodexBar's decoder.
    private let whamBody = Data("""
    {"plan_type":"team",
     "rate_limit":{
       "primary_window":{"used_percent":21,"reset_at":1788267090,"limit_window_seconds":18000},
       "secondary_window":{"used_percent":63.5,"reset_at":1788853890,"limit_window_seconds":604800}}}
    """.utf8)

    @Test func parsesWhamUsage() throws {
        let usage = try #require(CodexUsageParser.parseUsageResponse(whamBody))
        #expect(usage.provider == .codex)
        #expect(abs(usage.fiveHourUtilization - 0.21) < 0.0001)
        #expect(abs(usage.sevenDayUtilization - 0.635) < 0.0001)
        #expect(usage.fiveHourReset == Date(timeIntervalSince1970: 1_788_267_090))
        #expect(usage.fiveHourWindowMinutes == 300)
        #expect(usage.sevenDayWindowMinutes == 10080)
        #expect(usage.representativeClaim == RateLimitUsage.sevenDayWindow) // 63.5 > 21
        #expect(usage.overallStatus == "allowed")
        #expect(CodexUsageParser.planType(whamBody) == "team")
    }

    @Test func hundredPercentWindowIsThrottled() throws {
        let body = Data("""
        {"rate_limit":{"primary_window":{"used_percent":100,"reset_at":1788267090,"limit_window_seconds":18000},
                       "secondary_window":{"used_percent":10,"reset_at":1788853890,"limit_window_seconds":604800}}}
        """.utf8)
        let usage = try #require(CodexUsageParser.parseUsageResponse(body))
        #expect(usage.fiveHourStatus == "throttled")
        #expect(usage.overallStatus == "throttled")
        #expect(usage.sevenDayStatus == "allowed")
    }

    // Shape verified against a live ~/.codex/sessions token_count event (2026-09-01).
    @Test func parsesSessionSnapshot() throws {
        let rateLimits: [String: Any] = [
            "limit_id": "codex",
            "primary": ["used_percent": 21.0, "window_minutes": 300, "resets_at": 1_788_267_090],
            "secondary": ["used_percent": 3.0, "window_minutes": 10080, "resets_at": 1_788_853_890],
            "plan_type": "team",
        ]
        let usage = try #require(CodexUsageParser.parseSessionRateLimits(rateLimits))
        #expect(usage.provider == .codex)
        #expect(abs(usage.fiveHourUtilization - 0.21) < 0.0001)
        #expect(usage.sevenDayWindowMinutes == 10080)
        #expect(usage.representativeClaim == RateLimitUsage.fiveHourWindow)
    }

    @Test func missingWindowsReturnNil() {
        #expect(CodexUsageParser.parseUsageResponse(Data("{}".utf8)) == nil)
        #expect(CodexUsageParser.parseSessionRateLimits([:]) == nil)
    }
}
```

- [ ] **Step 2: Run to verify failure** — `swift test --filter CodexUsageParserTests` → FAIL.

- [ ] **Step 3: Implement** — one private window struct `(usedPercent: Double, resetAt: Date?, windowMinutes: Int?)` extracted by a helper accepting `[String: Any]` and tolerating Int/Double `used_percent`, `reset_at`/`resets_at`, `limit_window_seconds`/`window_minutes`; a shared private `assemble(primary:secondary:reachedType:) -> RateLimitUsage?` implementing the semantics table above; both public entry points parse JSON → call `assemble`. Use `JSONSerialization` (matches `RateLimitUsage.parse(clientData:)` style in this codebase, not Codable — mixed dynamic shapes).

- [ ] **Step 4: Run tests** — `swift test --filter CodexUsageParserTests` → PASS.

- [ ] **Step 5: Commit**

```bash
git add AIBattery/Models/CodexUsageParser.swift Tests/AIBatteryCoreTests/Models/CodexUsageParserTests.swift
git commit -m "feat: parse Codex wham/usage and session-log rate limits into RateLimitUsage"
```

---

### Task 12: CodexSessionRateLimitScanner (fallback source)

**Files:**
- Create: `AIBattery/Services/CodexSessionRateLimitScanner.swift`
- Test: `Tests/AIBatteryCoreTests/Services/CodexSessionRateLimitScannerTests.swift`

**Interfaces:**
- Consumes: `CodexPaths.sessions`, `CodexUsageParser.parseSessionRateLimits` (Task 11).
- Produces: `enum CodexSessionRateLimitScanner`:
  - `nonisolated static func extractLatestRateLimits(fromTail data: Data) -> RateLimitUsage?` — pure: scans the tail bytes line-by-line BACKWARDS for the last complete `token_count` event carrying `rate_limits`.
  - `nonisolated static func newestSessionFile(in root: URL, fileManager: FileManager = .default) -> URL?` — newest `*.jsonl` by modification date, recursive.
  - `nonisolated static func latestRateLimits(sessionsRoot: URL = CodexPaths.sessions) -> (rateLimits: RateLimitUsage, asOf: Date)?` — tail-reads (last 256 KB via `FileHandle.seek`, NEVER the whole file — session files run to tens of MB) the newest file; `asOf` = file modification date.

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
@testable import AIBatteryCore

@Suite("CodexSessionRateLimitScanner")
struct CodexSessionRateLimitScannerTests {
    private func tokenCountLine(primaryPercent: Double) -> String {
        """
        {"timestamp":"2026-09-01T09:26:07.000Z","type":"event_msg","payload":{"type":"token_count",\
        "info":{"total_token_usage":{"input_tokens":1,"cached_input_tokens":0,"cache_write_input_tokens":0,\
        "output_tokens":1,"reasoning_output_tokens":0,"total_tokens":2}},\
        "rate_limits":{"limit_id":"codex","primary":{"used_percent":\(primaryPercent),"window_minutes":300,"resets_at":1788267090},\
        "secondary":{"used_percent":3.0,"window_minutes":10080,"resets_at":1788853890}}}}
        """
    }

    @Test func picksLastRateLimitsEvent() throws {
        let lines = [
            #"{"type":"session_meta","payload":{"id":"s1"}}"#,
            tokenCountLine(primaryPercent: 10),
            #"{"type":"response_item","payload":{}}"#,
            tokenCountLine(primaryPercent: 55),
            "", // trailing newline
        ].joined(separator: "\n")
        let usage = try #require(CodexSessionRateLimitScanner.extractLatestRateLimits(fromTail: Data(lines.utf8)))
        #expect(abs(usage.fiveHourUtilization - 0.55) < 0.0001) // the LAST event wins
    }

    @Test func skipsTruncatedTrailingLine() throws {
        // Tail reads can slice mid-line; a partial trailing line must be ignored.
        let lines = tokenCountLine(primaryPercent: 42) + "\n" + #"{"type":"event_msg","payload":{"type":"token_count","rate_li"#
        let usage = try #require(CodexSessionRateLimitScanner.extractLatestRateLimits(fromTail: Data(lines.utf8)))
        #expect(abs(usage.fiveHourUtilization - 0.42) < 0.0001)
    }

    @Test func noRateLimitsReturnsNil() {
        let lines = #"{"type":"session_meta","payload":{}}"# + "\n" + #"{"type":"response_item","payload":{}}"#
        #expect(CodexSessionRateLimitScanner.extractLatestRateLimits(fromTail: Data(lines.utf8)) == nil)
    }

    @Test func newestSessionFileWins() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("codex-scanner-\(UUID().uuidString)/2026/09/01")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let old = dir.appendingPathComponent("rollout-old.jsonl")
        let new = dir.appendingPathComponent("rollout-new.jsonl")
        try Data("old".utf8).write(to: old)
        try Data("new".utf8).write(to: new)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -3600)], ofItemAtPath: old.path)
        let root = dir.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        #expect(CodexSessionRateLimitScanner.newestSessionFile(in: root) == new)
        try? FileManager.default.removeItem(at: root)
    }
}
```

- [ ] **Step 2: Run to verify failure** — `swift test --filter CodexSessionRateLimitScannerTests` → FAIL.

- [ ] **Step 3: Implement**

```swift
import Foundation

/// Fallback rate-limit source: the Codex CLI writes a `rate_limits` snapshot
/// into every `token_count` event in its session logs. When the wham/usage
/// endpoint is unreachable, the newest session file's last snapshot is the
/// best local truth. Always surfaced as CACHED data (alarm-suppressed) —
/// it's as old as the user's last Codex turn.
enum CodexSessionRateLimitScanner {
    /// How much of the file tail to scan. token_count events recur every few
    /// turns; 256 KB of tail reliably contains several.
    private static let tailBytes = 256 * 1024

    static func latestRateLimits(sessionsRoot: URL = CodexPaths.sessions) -> (rateLimits: RateLimitUsage, asOf: Date)? {
        guard let file = newestSessionFile(in: sessionsRoot),
              let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let start = size > UInt64(tailBytes) ? size - UInt64(tailBytes) : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd(),
              let usage = extractLatestRateLimits(fromTail: data) else { return nil }
        let attrs = try? FileManager.default.attributesOfItem(atPath: file.path)
        let modDate = attrs?[.modificationDate] as? Date ?? Date()
        return (usage, modDate)
    }

    static func newestSessionFile(in root: URL, fileManager: FileManager = .default) -> URL? {
        guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return nil
        }
        var newest: (url: URL, date: Date)?
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if newest == nil || date > newest!.date { newest = (url, date) }
        }
        return newest?.url
    }

    static func extractLatestRateLimits(fromTail data: Data) -> RateLimitUsage? {
        // Split on newlines; the FIRST line of a tail slice may be partial —
        // JSON parse failure naturally skips it. Scan backwards for the last
        // token_count event carrying rate_limits. Never reads message content:
        // only payload.type and payload.rate_limits are touched.
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n").reversed() {
            guard line.contains("\"rate_limits\""),
                  let lineData = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let payload = obj["payload"] as? [String: Any],
                  payload["type"] as? String == "token_count",
                  let rateLimits = payload["rate_limits"] as? [String: Any] else {
                continue
            }
            return CodexUsageParser.parseSessionRateLimits(rateLimits)
        }
        return nil
    }
}
```

- [ ] **Step 4: Run tests** — `swift test --filter CodexSessionRateLimitScannerTests` → PASS.

- [ ] **Step 5: Commit**

```bash
git add AIBattery/Services/CodexSessionRateLimitScanner.swift Tests/AIBatteryCoreTests/Services/CodexSessionRateLimitScannerTests.swift
git commit -m "feat: session-log fallback scanner for Codex rate limits"
```

---

### Task 13: CodexRateLimitFetcher

**Files:**
- Create: `AIBattery/Services/CodexRateLimitFetcher.swift`
- Test: `Tests/AIBatteryCoreTests/Services/CodexRateLimitFetcherTests.swift`

**Interfaces:**
- Consumes: `CodexUsageParser` (11), `CodexSessionRateLimitScanner` (12), `RateLimitSource.codex*` (4), `SecureNetworking`, `APIFetchResult`.
- Produces: `@MainActor final class CodexRateLimitFetcher`:
  - `static let shared = CodexRateLimitFetcher()`
  - `nonisolated static let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!`
  - `enum UsageOutcome: { case success(APIFetchResult); case authFailed; case unavailable }`
  - `nonisolated static func interpretUsageResponse(statusCode: Int, data: Data) -> UsageOutcome` — 401/403 → `.authFailed`; 2xx or 429 with parseable body → `.success` (429 additionally runs `rateLimits.markedThrottled()`); everything else → `.unavailable`. Result carries `rateLimitSource: .codexUsageEndpoint`, `profile: nil`.
  - `func fetch(accessToken: String, accountId: String) async -> APIFetchResult` — request with headers per Global Constraints; on `.success` reset that account's auth-failure count, cache + persist, return. On `.authFailed` increment count; at ≥3 return `cachedOrEmpty(accountId:, authError: true)` (mirror `RateLimitFetcher`'s `consecutiveAuthFailures` behavior — read that first). On `.unavailable`/transport error: try `CodexSessionRateLimitScanner.latestRateLimits()`; if found return it as `APIFetchResult(rateLimits: …, rateLimitSource: .codexSessionLog, profile: nil, fetchedAt: asOf, isCached: true)` (ALSO cache it, do NOT persist a fallback over real endpoint data); else `cachedOrEmpty(accountId:)`.
  - `func cachedOrEmpty(accountId: String, authError: Bool = false) -> APIFetchResult` — same contract as RateLimitFetcher's: cached result re-tagged `isCached: true` or an empty result.
  - Persistence: private `PersistedCodexRateLimits: Codable { rateLimits, rateLimitSource, fetchedAt }` under key `"aibattery_codexRateLimits_" + accountId`, restored in `init` — copy the structure of `RateLimitFetcher+Persistence.swift`, with `defaults: UserDefaults = .standard` injection for tests.
  - `func clearCache(accountId: String)` — called from sign-out paths later; removes memory + persisted entry.

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
@testable import AIBatteryCore

@Suite("CodexRateLimitFetcher")
@MainActor
struct CodexRateLimitFetcherTests {
    private let goodBody = Data("""
    {"plan_type":"plus","rate_limit":{
      "primary_window":{"used_percent":30,"reset_at":1788267090,"limit_window_seconds":18000},
      "secondary_window":{"used_percent":5,"reset_at":1788853890,"limit_window_seconds":604800}}}
    """.utf8)

    @Test func interpret200IsFreshCodexResult() throws {
        guard case .success(let result) = CodexRateLimitFetcher.interpretUsageResponse(statusCode: 200, data: goodBody) else {
            Issue.record("expected success"); return
        }
        #expect(result.rateLimits?.provider == .codex)
        #expect(result.rateLimitSource == .codexUsageEndpoint)
        #expect(result.isCached == false)
        #expect(abs((result.rateLimits?.fiveHourUtilization ?? 0) - 0.30) < 0.0001)
    }

    @Test func interpret429MarksThrottled() throws {
        guard case .success(let result) = CodexRateLimitFetcher.interpretUsageResponse(statusCode: 429, data: goodBody) else {
            Issue.record("expected success"); return
        }
        #expect(result.rateLimits?.overallStatus == "throttled")
    }

    @Test func interpretAuthAndServerFailures() {
        guard case .authFailed = CodexRateLimitFetcher.interpretUsageResponse(statusCode: 401, data: Data()) else {
            Issue.record("401 must be authFailed"); return
        }
        guard case .unavailable = CodexRateLimitFetcher.interpretUsageResponse(statusCode: 503, data: Data()) else {
            Issue.record("503 must be unavailable"); return
        }
        guard case .unavailable = CodexRateLimitFetcher.interpretUsageResponse(statusCode: 200, data: Data("junk".utf8)) else {
            Issue.record("unparseable 200 must be unavailable"); return
        }
    }
}
```

- [ ] **Step 2: Run to verify failure** — `swift test --filter CodexRateLimitFetcherTests` → FAIL.

- [ ] **Step 3: Implement** per the interface block. Request construction:

```swift
var request = URLRequest(url: Self.usageURL)
request.httpMethod = "GET"
request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
request.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
request.setValue("application/json", forHTTPHeaderField: "Accept")
request.setValue(userAgent, forHTTPHeaderField: "User-Agent") // same "AIBattery/<version>" string RateLimitFetcher builds — copy that property
request.timeoutInterval = 30
```

Wrap the transport in `SecureNetworking.data(for:)`, catch → fallback path. Diagnostic logging mirrors `RateLimitFetcher` (status code + which source served the result; never the token).

- [ ] **Step 4: Run tests** — `swift test --filter CodexRateLimitFetcherTests` → PASS.

- [ ] **Step 5: Commit**

```bash
git add AIBattery/Services/CodexRateLimitFetcher.swift Tests/AIBatteryCoreTests/Services/CodexRateLimitFetcherTests.swift
git commit -m "feat: Codex rate-limit fetcher with endpoint, 429 normalization, and session-log fallback"
```

---

### Task 14: Provider dispatch — ViewModel fetch path + fan-out

**Files:**
- Modify: `AIBattery/ViewModels/MultiAccountFanOut.swift` (add dispatcher + CodexRateLimitFetcher conformance)
- Modify: `AIBattery/ViewModels/UsageViewModel.swift` (`fetchAPIData`, instant-paint `cachedOrEmpty`, `resolveAccountIdentity` guard)
- Modify: `AIBattery/ViewModels/UsageViewModel+FanOut.swift` (inject dispatcher)
- Test: `Tests/AIBatteryCoreTests/ViewModels/ProviderDispatchingFetcherTests.swift`

**Interfaces:**
- Consumes: `RateLimitFetching` protocol (exists), `CodexRateLimitFetcher` (13), `AccountRecord.provider` (1).
- Produces:

```swift
extension CodexRateLimitFetcher: RateLimitFetching {}

/// Routes a per-account rate-limit fetch to the provider's fetcher.
/// The seams stay protocol-typed so MultiAccountFanOut tests keep working
/// with pure mocks.
@MainActor
struct ProviderDispatchingFetcher: RateLimitFetching {
    let providerForAccount: (String) -> AIProvider
    let claude: any RateLimitFetching
    let codex: any RateLimitFetching

    func fetch(accessToken: String, accountId: String) async -> APIFetchResult {
        switch providerForAccount(accountId) {
        case .claude: await claude.fetch(accessToken: accessToken, accountId: accountId)
        case .codex: await codex.fetch(accessToken: accessToken, accountId: accountId)
        }
    }

    /// Production wiring: unknown ids default to .claude (pre-provider behavior).
    static func live(accountStore: AccountStore) -> ProviderDispatchingFetcher {
        ProviderDispatchingFetcher(
            providerForAccount: { id in accountStore.accounts.first { $0.id == id }?.provider ?? .claude },
            claude: RateLimitFetcher.shared,
            codex: CodexRateLimitFetcher.shared
        )
    }
}
```

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
@testable import AIBatteryCore

@Suite("ProviderDispatchingFetcher")
@MainActor
struct ProviderDispatchingFetcherTests {
    /// Mock fetcher that records which account ids it served.
    final class SpyFetcher: RateLimitFetching {
        var served: [String] = []
        let tag: RateLimitSource
        init(tag: RateLimitSource) { self.tag = tag }
        func fetch(accessToken: String, accountId: String) async -> APIFetchResult {
            served.append(accountId)
            return APIFetchResult(rateLimits: nil, rateLimitSource: tag, profile: nil)
        }
    }

    @Test func routesByProvider() async {
        let claude = SpyFetcher(tag: .oauthUsageEndpoint)
        let codex = SpyFetcher(tag: .codexUsageEndpoint)
        let dispatcher = ProviderDispatchingFetcher(
            providerForAccount: { $0.hasPrefix("x") ? .codex : .claude },
            claude: claude, codex: codex
        )
        _ = await dispatcher.fetch(accessToken: "t", accountId: "c1")
        _ = await dispatcher.fetch(accessToken: "t", accountId: "x1")
        _ = await dispatcher.fetch(accessToken: "t", accountId: "x2")
        #expect(claude.served == ["c1"])
        #expect(codex.served == ["x1", "x2"])
    }
}
```

(If `RateLimitFetching` demands `Sendable` conformance a class can't satisfy cleanly, make the spy an actor-isolated @MainActor final class — mirror how existing MultiAccountFanOut tests build their mocks; read one first.)

- [ ] **Step 2: Run to verify failure** — `swift test --filter ProviderDispatchingFetcherTests` → FAIL.

- [ ] **Step 3: Implement + integrate**

1. Add the dispatcher + conformance to `MultiAccountFanOut.swift` (bottom of file, same seam section).
2. `UsageViewModel+FanOut.swift`: where `fetchAllAccounts` passes `fetcher: RateLimitFetcher.shared` to `MultiAccountFanOut.resolve`, pass `fetcher: ProviderDispatchingFetcher.live(accountStore: OAuthManager.shared.accountStore)` instead.
3. `UsageViewModel.fetchAPIData` (UsageViewModel.swift:448): replace the direct `RateLimitFetcher.shared.fetch` call:

```swift
let provider = oauthManager.accountStore.accounts.first { $0.id == accountId }?.provider ?? .claude
let api: APIFetchResult = if let token = accessToken, let id = accountId {
    provider == .codex
        ? await CodexRateLimitFetcher.shared.fetch(accessToken: token, accountId: id)
        : await RateLimitFetcher.shared.fetch(accessToken: token, accountId: id)
} else {
    APIFetchResult(rateLimits: nil, profile: nil)
}
```

4. Instant-paint path (UsageViewModel.swift `refresh()`, the `wasEmpty` block): route `RateLimitFetcher.shared.cachedOrEmpty(accountId:)` the same way (`CodexRateLimitFetcher.shared.cachedOrEmpty(accountId:)` for `.codex` accounts).
5. `resolveAccountIdentity` (UsageViewModel.swift:473): first line, add `guard … provider == .claude else { return }` — Codex identities are resolved at auth time; the Anthropic pending-identity machinery must never touch them.
6. Account-switch path (`switchAccount(to:)`) needs no change — it funnels into `refresh()`.

- [ ] **Step 4: Run tests** — `swift test --filter ProviderDispatchingFetcherTests && swift test --filter MultiAccountFanOut && swift test --filter UsageViewModel` → PASS.

- [ ] **Step 5: Commit**

```bash
git add AIBattery/ViewModels/MultiAccountFanOut.swift AIBattery/ViewModels/UsageViewModel.swift AIBattery/ViewModels/UsageViewModel+FanOut.swift Tests/AIBatteryCoreTests/ViewModels/ProviderDispatchingFetcherTests.swift
git commit -m "feat: route rate-limit fetches by account provider in refresh and fan-out"
```

---

### Task 15: MenuBarMultiAccountText provider grouping

**Files:**
- Modify: `AIBattery/Views/MenuBarMultiAccountText.swift`
- Modify: the call site that builds the menu-bar output (grep `MenuBarMultiAccountText.build` — it's in `StatusBarManager+ButtonUpdate.swift` or `StatusBarManager.swift`; pass the providers map from `OAuthManager.shared.accountStore.accounts`)
- Test: extend `Tests/AIBatteryCoreTests/Views/MenuBarMultiAccountTextTests.swift` (existing suite — find exact path with `grep -r "MenuBarMultiAccountText" Tests/`)

**Interfaces:**
- Consumes: `AIProvider.glyph` (1), `AccountStore.displayOrdered` ordering guarantee (2 — `order` arrives Claude-first already).
- Produces: `build(order: [String], providers: [String: AIProvider] = [:], limits: [String: RateLimitUsage], metricMode: MetricMode) -> Output`. Rendering rule (LOCKED):
  - Single-provider account set (all Claude OR all Codex, or `providers` empty): text is EXACTLY today's format — `"42%\u{00A0}|\u{00A0}23%"` — no glyphs, zero visual change for existing users.
  - Mixed: `"✦\u{00A0}42%\u{00A0}|\u{00A0}23%  ⬡\u{00A0}57%"` — glyph + NBSP before each provider group, groups joined by two plain spaces, existing NBSP-`|` separator within a group. Missing limits render `"—"` as today.
  - `worstPercent`/`anyThrottled` unchanged: computed across ALL accounts regardless of provider (one icon, worst signal wins — existing doctrine).

- [ ] **Step 1: Write the failing test** (add to the existing suite)

```swift
@Test func mixedProvidersGetGlyphGroups() {
    let limits = [
        "c1": TestFixtures.rateLimits(fiveHour: 0.42),
        "c2": TestFixtures.rateLimits(fiveHour: 0.23),
        "x1": TestFixtures.rateLimits(fiveHour: 0.57, provider: .codex),
    ]
    let output = MenuBarMultiAccountText.build(
        order: ["c1", "c2", "x1"],
        providers: ["c1": .claude, "c2": .claude, "x1": .codex],
        limits: limits,
        metricMode: .fiveHour
    )
    #expect(output.text == "\u{2726}\u{00A0}42%\u{00A0}|\u{00A0}23%  \u{2B21}\u{00A0}57%")
    #expect(Int(output.worstPercent.rounded()) == 57)
}

@Test func singleProviderKeepsLegacyFormat() {
    let limits = ["c1": TestFixtures.rateLimits(fiveHour: 0.42), "c2": TestFixtures.rateLimits(fiveHour: 0.23)]
    let output = MenuBarMultiAccountText.build(
        order: ["c1", "c2"],
        providers: ["c1": .claude, "c2": .claude],
        limits: limits, metricMode: .fiveHour
    )
    #expect(output.text == "42%\u{00A0}|\u{00A0}23%")
}
```

(`TestFixtures.rateLimits` — if no such helper exists in the suite, construct `RateLimitUsage` inline exactly as the suite's existing tests do, adding `provider:` where needed.)

- [ ] **Step 2: Run to verify failure** — the suite's filter → FAIL (no `providers:` parameter).

- [ ] **Step 3: Implement** — inside `build`, partition `order` into per-provider runs using `providers[id] ?? .claude`; compute each account's part string exactly as today; if the distinct provider set has ≤1 member emit the legacy join, else emit glyph-prefixed groups joined by `"  "`. Update the production call site to pass `providers: Dictionary(uniqueKeysWithValues: accountStore.accounts.map { ($0.id, $0.provider) })` and `order` from the display-ordered IDs it already uses (which are Claude-first after Task 2).

- [ ] **Step 4: Run tests** — suite filter → PASS including all pre-existing cases (legacy format tests must not change).

- [ ] **Step 5: Commit**

```bash
git add AIBattery/Views/MenuBarMultiAccountText.swift AIBattery/Views/StatusBarManager*.swift Tests/AIBatteryCoreTests/Views/MenuBarMultiAccountTextTests.swift
git commit -m "feat: provider-glyph grouping in multi-account menu bar text"
```

---

### Task 16: UI — account picker, Add Account split, Codex AuthView

**Files:**
- Modify: `AIBattery/Views/PopoverHeaderView.swift` (picker glyphs + Add menu split; `onAddAccount` closure becomes `(AIProvider) -> Void`)
- Modify: `AIBattery/Views/UsagePopoverView.swift` (`isAddingAccount: Bool` → `addingProvider: AIProvider?`)
- Modify: `AIBattery/Views/AuthView.swift` (provider parameter + Codex browser-wait branch + CLI import button)
- Modify: `AIBattery/Views/PopoverStateViews.swift` / wherever the top-level `AuthView(oauthManager:)` is constructed for the signed-out state (grep `AuthView(`) — signed-out default stays the Claude flow with a secondary "Sign in with Codex instead" link switching the provider state.
- Test: none (SwiftUI bodies — this project doesn't unit-test view bodies; behavior verified in the smoke test). Pure additions from earlier tasks already carry the logic tests.

**Steps:**

- [ ] **Step 1: PopoverHeaderView** — in `accountLabel(_:index:)`, prefix the glyph only when the account set spans both providers:

```swift
private var showsProviderGlyphs: Bool {
    Set(accountStore.accounts.map(\.provider)).count > 1
}

private func accountLabel(_ account: AccountRecord, index: Int) -> String {
    let base: String = if let name = account.displayName, !name.isEmpty { name } else { "User \(index + 1)" }
    return showsProviderGlyphs ? "\(account.provider.glyph) \(base)" : base
}
```

Iterate the picker over `AccountStore.displayOrdered(accountStore.accounts)` instead of `accountStore.accounts` (keeps groups contiguous). Replace the single add button:

```swift
if accountStore.canAddAccount(provider: .claude) {
    Button { onAddAccount(.claude) } label: { Label("Add Claude Account…", systemImage: "plus") }
}
if accountStore.canAddAccount(provider: .codex) {
    Button { onAddAccount(.codex) } label: { Label("Add Codex Account…", systemImage: "plus") }
}
```

- [ ] **Step 2: UsagePopoverView** — replace `@State private var isAddingAccount = false` with `@State private var addingProvider: AIProvider?`; the overlay condition becomes `if let addingProvider { AuthView(oauthManager: …, provider: addingProvider, isAddingAccount: true, onCancel: { self.addingProvider = nil }) }`; the account-count `onChange` that auto-dismisses keeps working (set `addingProvider = nil`). `onAddAccount: { addingProvider = $0 }`.

- [ ] **Step 3: AuthView** — add `var provider: AIProvider = .claude`. Claude branch: untouched (paste-code flow). Codex branch replaces the paste-code UI:
  - Copy: title line "Add a Codex account" / "Sign in with your Codex (ChatGPT) account"; body "Connect your OpenAI account to see Codex usage and rate limits."
  - Primary button "Sign In with ChatGPT" → `startCodexAuth()`:

```swift
private func startCodexAuth() {
    guard let url = oauthManager.startCodexAuthFlow() else {
        errorMessage = "Couldn't start sign-in (port 1455 busy — is a Codex CLI login running?)"
        return
    }
    isWaitingForCode = true
    NSWorkspace.shared.open(url)
    Task {
        let result = await oauthManager.completeCodexAuthFlow()
        isWaitingForCode = false
        if case .failure(let error) = result {
            errorMessage = error.userMessage
        }
        // Success needs no handling here — the account lands in AccountStore
        // and UsagePopoverView's onChange dismisses the overlay.
    }
}
```

  - Waiting state: "Complete the sign-in in your browser…" + spinner + Cancel (`oauthManager.cancelCodexAuthFlow()`; `isWaitingForCode = false`).
  - Below the primary button, when `provider == .codex && CodexAuthFileImporter.cliLoginAvailable`: secondary button "Import Codex CLI login" → `CodexAuthFileImporter.importCurrentLogin(into: oauthManager)`, surfacing `.failure` in `errorMessage`.
- [ ] **Step 4: Signed-out root** — where the app shows `AuthView` for the fully signed-out state, add a footnote-styled toggle button ("Sign in with Codex instead" / "Sign in with Claude instead") flipping a local `@State var provider: AIProvider = .claude` passed to AuthView.
- [ ] **Step 5: Build + verify + smoke test**

```bash
swift build -c release
mkdir -p .build/AIBattery.app/Contents/MacOS
cp .build/release/AIBattery .build/AIBattery.app/Contents/MacOS/
cp AIBattery/Info.plist .build/AIBattery.app/Contents/
open .build/AIBattery.app
```

Manual checklist (user memory: test before committing UI changes):
- Existing Claude account still renders identically (menu bar, popover, picker).
- "Add Codex Account…" appears; clicking opens browser to auth.openai.com; completing lands a ⬡ account; menu bar (with "show all accounts" on) shows the glyph groups.
- "Import Codex CLI login" seeds an account without a browser round-trip.
- Switching to the Codex account shows Codex 5h/Weekly bars ("Weekly" label present).
- Cancel mid-flow releases port 1455 (start again immediately — must not error).

- [ ] **Step 6: Commit**

```bash
git add AIBattery/Views/
git commit -m "feat: mixed-provider account picker, Codex sign-in flow, and CLI import UI"
```

---

### Task 17: Plan 1 wrap-up — lint, full suite, README, spec sync note

**Files:**
- Modify: `README.md` (Test Coverage section — new counts and rows)
- Modify: `docs/superpowers/specs/2026-09-02-codex-support-design.md` (§2 refinement)
- Test: full suite.

**Steps:**

- [ ] **Step 1: Format + lint**

```bash
swiftformat AIBattery/ AIBatteryApp/ Tests/ && swiftlint
```
Fix anything reported.

- [ ] **Step 2: Full test suite**

Run: `swift test`
Expected: ALL tests pass (1116 pre-existing + every suite added by Tasks 1–15). Any hang → check for accidental `SparkleUpdateService`/NSColor/network usage in new tests before touching timeouts (see CLAUDE.md test-hang postmortem).

- [ ] **Step 3: README Test Coverage** — update total count, file count, and add/adjust rows for the new suites (Models: AIProvider, RateLimitUsage provider, CodexUsageParser; Services: AccountStore caps, Codex OAuth pieces, scanner, fetcher; ViewModels: dispatcher; Views: menu-bar grouping). Counts come from the `swift test` summary, not estimates.

- [ ] **Step 4: Spec refinement note** — in the spec's §2, replace the sentence naming a single "`CodexOAuthClient`" with the as-built decomposition: "Codex auth is implemented as `CodexAuthSession` + `CodexCallbackServer` (flow), `CodexTokenClient` (exchange/refresh HTTP), and provider routing inside `OAuthManager` (storage keys, refresh dispatch, account registration) — same observable contract: PKCE S256, state validation, Keychain `refreshToken_codex_<accountId>`, identical token-lifecycle policies." (Spec-first rule: docs match code before any push.)

- [ ] **Step 5: Commit + push**

```bash
git add README.md docs/superpowers/specs/2026-09-02-codex-support-design.md
git commit -m "docs: Plan 1 wrap-up — coverage table and spec auth-component refinement"
git push
```

(PR #193 stays draft — Plan 2 lands on the same branch next.)

---

## Plan 2 preview (separate document, written after Plan 1 executes)

Codex local data layer + Insights parity: `CodexSessionLogReader` (streaming, fingerprint cache, `AssistantUsageEntry` mapping per spec §4 table), `FileWatcher` second FSEvents root, provider-gated Insights/local sections, OpenAI pricing in `ModelPricing` + `ModelNameMapper`, StatusChecker OpenAI status feed (`https://status.openai.com/api/v2/summary.json` — verified same Statuspage schema), spec/ + README full sync, release prep.
