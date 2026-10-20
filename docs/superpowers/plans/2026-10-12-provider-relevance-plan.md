# Provider-Relevant Display Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the popover and menu bar show what is actually relevant for the active provider — per-record Codex context windows, reasoning/thinking share and effort for both providers, Codex limit names, (conditionally) Claude per-model weekly windows, Codex API-key accounts in the menu bar, a credit-budget runway, a dated Codex All-Time, and an other-accounts strip.

**Architecture:** Every item rides the existing provider seams: new optional fields on `AssistantUsageEntry` → `UsageAggregator` → `ModelTokenSummary` / `TokenHealthStatus` → views; new optional fields on `RateLimitUsage` / `CodexCreditBudget` → fetchers → bars; the multi-account fan-out gains a second map (`apiLimits`) that both the menu bar and the new strip read. All new fields are optional-with-default so persisted blobs and existing call sites keep working.

**Tech Stack:** Swift 6 / SwiftUI, SPM, Swift Testing (`import Testing`, `@testable import AIBatteryCore`).

**Spec:** `docs/superpowers/specs/2026-10-12-provider-relevance-design.md` (§1–§5, §7, §8 map to Tasks 1–6, 8, 9; §6 is done by the overview plan's Task 1; §9 is superseded; §10 error handling, §11 testing, research items R1–R3). Executed as Task 4 of `2026-10-19-v3-3-0-release-plan.md`, which owns the branch (`worktree-v3-3-0`), the changelog heading (`## [3.3.0] — Unreleased`), the counts and the PR.

## Global Constraints

- macOS 13+, Swift 6 strict concurrency, zero new warnings; `swiftformat AIBattery/ AIBatteryApp/ Tests/` + `swiftlint` clean before every push.
- JSONL reads are **token-count-only**; `response_item` lines are never decoded; no message content is read, stored or logged. `~/.codex` and `~/.claude` are read-only.
- Cost framing: "API-equivalent cost" for subscriptions; real bill only when `snapshot.costIsBilled`. Reasoning tokens never change cost.
- Headless-CI rules: suites touching AppKit colours are `@MainActor`; never construct `UsageViewModel()` in tests; never touch `SparkleUpdateService.shared`; no dynamic `NSColor` equality off-main.
- Every new persisted field is `decodeIfPresent` with a default (ledger, `PersistedCodexRateLimits`, `aibattery_rateLimits_*`).
- Branch `worktree-v3-3-0`, one draft PR for the whole v3.3.0 release (stays draft until Kyle says done). Commit per task, `<type>: <description>`, **no Co-Authored-By trailers**. Each task that adds user-visible behaviour appends one line under `### Added` in `CHANGELOG.md` (`## [3.3.0] — Unreleased`).
- New model fields are `var … = default` trailing the existing ones (every task).
- README "Test Coverage" table updated in the same commit as any test change; `CLAUDE.md` counts at wrap-up (Task 11).
- Model-ID prefixes: Claude `claude-`, Codex `gpt-`.
- Vocabulary: Claude "Thinking" / "7-Day"; Codex "Reasoning" / "Weekly".

---

## File Structure

| Action | Path | Responsibility |
|---|---|---|
| Modify | `AIBattery/Models/SessionEntry.swift` | `AssistantUsageEntry` + `contextWindow`, `reasoningTokens`, `effortLabel`; `SessionEntry.TokenUsage` decodes `output_tokens_details.thinking_tokens`, `speed` |
| Modify | `AIBattery/Services/SessionLogReader.swift:492-523` | `makeUsageEntry` fills the three new fields (Claude) |
| Modify | `AIBattery/Services/CodexSessionLogParser.swift:122-207` | `turn_context.effort` → `currentEffort`; `model_context_window`, `reasoning_output_tokens` → entry |
| Create | `AIBattery/Utilities/ReasoningVocabulary.swift` | `label(forModel:)` → "thinking" / "reasoning" |
| Modify | `AIBattery/Services/UsageAggregator.swift:83-97, 556-575` | `TokenMap` + `reasoning`; `buildModelTokens`; `ledgerSince` |
| Modify | `AIBattery/Models/UsageSnapshot.swift:409-434, 60-110` | `ModelTokenSummary.reasoningTokens/reasoningShare`; `UsageSnapshot.ledgerSince` |
| Modify | `AIBattery/Services/TokenLedger.swift` | `ModelTokenRecord.reasoning`; `LedgerData.firstScan`; `firstScanDate(ledgerKey:)` |
| Modify | `AIBattery/Services/TokenHealthMonitor.swift:111-272` | per-record window; `reasoningTokens`; `effortLabel` |
| Modify | `AIBattery/Models/TokenHealthStatus.swift:33-63` | `reasoningTokens`, `effortLabel`, `reasoningShare` |
| Modify | `AIBattery/Views/TokenHealthSection.swift:30-95` | detail row shows share + effort via pure `detailTrailingText` |
| Modify | `AIBattery/Views/InsightsTrendCostSection.swift:93-135` | copy/accessibility text gains the share |
| Modify | `AIBattery/Models/CodexCreditBudget.swift`, `AIBattery/Models/CodexUsageParser.swift:84-125` | `limitName`; `periodAnchor`; `estimatedTimeToExhaustion(now:)` |
| Modify | `AIBattery/Views/CreditBudgetSection.swift` | tooltip uses `limitName`; footer runway |
| Modify | `AIBattery/Services/CodexRateLimitFetcher.swift` | carry / reset `periodAnchor` on fresh readings |
| Modify (conditional) | `AIBattery/Models/RateLimitUsage.swift` (`modelWindows` field) and `AIBattery/Models/RateLimitUsage+Parsing.swift` (parse) | `modelWindows` parsed from `seven_day_<model>` keys |
| Create (conditional) | `AIBattery/Views/ModelWindowRows.swift` | compact per-model weekly rows under the 7-Day bar |
| Modify | `AIBattery/ViewModels/MultiAccountFanOut.swift` | `FanOutResult { windows, apiLimits }`; API-key accounts eligible |
| Modify | `AIBattery/ViewModels/UsageViewModel.swift:25`, `UsageViewModel+FanOut.swift` | `perAccountAPILimits` |
| Modify | `AIBattery/Views/MenuBarMultiAccountText.swift`, `StatusBarManager+ButtonUpdate.swift` | per-minute slots |
| Modify | `AIBattery/Views/InsightsRowsAndHover.swift:33-51`, `AIBattery/Views/ActivityChartView.swift` | "since <date>" |
| Modify | `spec/DATA_LAYER.md`, `spec/UI_SPEC.md`, `spec/CONSTANTS.md`, `spec/ARCHITECTURE.md`, `docs/superpowers/specs/2026-09-02-codex-support-design.md`, `README.md`, `CLAUDE.md` | sync |
| Tests | extend `Tests/AIBatteryCoreTests/Services/CodexSessionLogParserTests.swift`, `SessionLogReaderTests.swift`, `UsageAggregatorTests.swift`, `TokenLedgerTests.swift`, `TokenHealthMonitorTests.swift`, `Models/CodexCreditBudgetTests.swift`, `Models/CodexUsageParserTests.swift`, `Models/RateLimitUsageTests.swift`, `ViewModels/MultiAccountFanOutTests.swift`, `Views/MenuBarMultiAccountTextTests.swift`, `Services/AccountStoreProviderTests.swift`; create `Utilities/ReasoningVocabularyTests.swift`, `Views/TokenHealthSectionTextTests.swift`, `Views/OtherAccountsStripTests.swift`, `Views/InsightsAllTimeCaveatTests.swift` (exists; append) | |

Line numbers in this plan predate v3.2.0; locate every anchor by symbol. Task 3 of the v3.3.0
plan (commit `7ced164`) moved the aggregator's entry loop into `UsageAggregator.AggregationPass`
(`add(_:)` = loop body, `finish(entries:…)` = post-loop assembly); Task 2's "accumulate reasoning
in the loop" edits target `AggregationPass.add` and `finish`.

Run all tests with `swift test`; a single suite with `swift test --filter "<SuiteName>"`.

---

### Task 0: Verify the Claude usage payload keys (research item R1)

**Files:**
- Modify (temporarily): `AIBattery/Services/RateLimitFetcher+UsageEndpoint.swift:31-62` (`interpretUsageEndpoint`)
- Modify: `docs/superpowers/specs/2026-10-12-provider-relevance-design.md` ("Verified ground truth")

**Interfaces:**
- Produces: a decision for Task 6 (`modelWindows` present or absent), recorded in the spec.

- [ ] **Step 1: Add a keys-only log line (no values), at a level that is actually retrievable**

Inside `interpretUsageEndpoint` (`AIBattery/Services/RateLimitFetcher+UsageEndpoint.swift:31`), right after the JSON is decoded and before `RateLimitUsage.parse(clientData:)`:

```swift
if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
    let topKeys = dict.keys.sorted().joined(separator: ",")
    let nested = dict.compactMap { key, value -> String? in
        guard let obj = value as? [String: Any] else { return nil }
        return "\(key){\(obj.keys.sorted().joined(separator: ","))}"
    }.sorted().joined(separator: " ")
    AppLogger.network.error("usage endpoint keys: \(topKeys, privacy: .public) nested: \(nested, privacy: .public)")
}
```

`.error`, not `.notice`: on this machine `.notice`/`.info` lines never reach the persisted store and `log show` returns nothing for the subsystem.

- [ ] **Step 2: Stream first, then build and run once**

In one terminal, **before** launching:

```bash
log stream --predicate 'subsystem == "com.KyleNesium.AIBattery" AND eventMessage CONTAINS "usage endpoint keys"' --style compact
```

In another:

```bash
./scripts/build-app.sh && open .build/AIBattery.app
```

An ad-hoc rebuild blocks on a Keychain prompt — click **Always Allow**. Within one poll the stream prints one line with the top-level keys and each nested object's keys. Copy it, quit the build, relaunch `/Applications/AIBattery.app`.

- [ ] **Step 3: Revert the log line**

```bash
git checkout -- AIBattery/Services/RateLimitFetcher+UsageEndpoint.swift
git status --short   # must be clean apart from the spec
```

- [ ] **Step 4: Record the key set in the spec**

Under "Verified ground truth" add a bullet `Claude /api/oauth/usage (captured <date>): top-level keys … ; nested …`. Then in §5 replace "**Task 0 (verification, before any code)**" paragraph's status with one of:
- `**Result: present** — keys <list>. Task 6 is IN.` or
- `**Result: absent** — Task 6 is DROPPED; no per-model windows exist in this payload.`

- [ ] **Step 5: Commit**

```bash
git add docs/superpowers/specs/2026-10-12-provider-relevance-design.md
git commit -m "docs: record live /api/oauth/usage key set (research item R1)"
```

---

### Task 1: New entry fields from both session-log parsers

**Files:**
- Modify: `AIBattery/Models/SessionEntry.swift:24-37` (`TokenUsage`), `:41-53` (`AssistantUsageEntry`)
- Modify: `AIBattery/Services/SessionLogReader.swift:492-523` (`makeUsageEntry`)
- Modify: `AIBattery/Services/CodexSessionLogParser.swift:22` (state), `:126-130` (`turn_context`), `:180-206` (`makeEntry`)
- Test: `Tests/AIBatteryCoreTests/Services/SessionLogReaderTests.swift`, `Tests/AIBatteryCoreTests/Services/CodexSessionLogParserTests.swift`

**Interfaces:**
- Produces on `AssistantUsageEntry`: `var contextWindow: Int? = nil`, `var reasoningTokens: Int = 0` (subset of `outputTokens`), `var effortLabel: String? = nil`, `var creatorAccountId: String? = nil`. Memberwise init keeps every existing call site compiling (the new parameters are defaulted and trail the old ones). Codex fills it from `session_meta.payload.creator_account_id` (non-empty string; every `session_meta` line is applied, so a later one wins for later entries); Claude leaves it nil.
- Produces on `CodexSessionLogParser`: `private(set) var currentEffort: String?`.

- [ ] **Step 1: Write the failing Codex parser tests**

Append to `CodexSessionLogParserTests`:

```swift
    private let turnContextEffort = #"{"timestamp":"2026-10-11T20:49:40.000Z","ordinal":3,"type":"turn_context","payload":{"cwd":"/Users/me/work/proj","model":"gpt-6-astra","effort":"XHigh ","summary":"auto"}}"#
    private let tokenCountReasoning = #"{"timestamp":"2026-10-11T20:50:00.000Z","ordinal":4,"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1000,"cached_input_tokens":0,"cache_write_input_tokens":0,"output_tokens":400,"reasoning_output_tokens":120,"total_tokens":1400},"last_token_usage":{"input_tokens":1000,"cached_input_tokens":0,"cache_write_input_tokens":0,"output_tokens":400,"reasoning_output_tokens":120,"total_tokens":1400},"model_context_window":258400},"rate_limits":null}}"#
    private let tokenCountReasoningOverflow = #"{"timestamp":"2026-10-11T20:51:00.000Z","ordinal":5,"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":2000,"cached_input_tokens":0,"cache_write_input_tokens":0,"output_tokens":10,"reasoning_output_tokens":50,"total_tokens":2010},"last_token_usage":{"input_tokens":1000,"cached_input_tokens":0,"cache_write_input_tokens":0,"output_tokens":10,"reasoning_output_tokens":50,"total_tokens":1010},"model_context_window":0},"rate_limits":null}}"#

    @Test func tokenCount_carriesContextWindowReasoningAndEffort() throws {
        var parser = CodexSessionLogParser(fallbackSessionId: "rollout-x")
        _ = parser.consume(line: line(sessionMeta), lineIndex: 0)
        _ = parser.consume(line: line(turnContextEffort), lineIndex: 1)
        let entry = try #require(parser.consume(line: line(tokenCountReasoning), lineIndex: 2))
        #expect(entry.contextWindow == 258_400)
        #expect(entry.reasoningTokens == 120)
        #expect(entry.outputTokens == 400)
        #expect(entry.effortLabel == "xhigh") // trimmed, lower-cased
    }

    @Test func tokenCount_clampsReasoningAndDropsZeroWindow() throws {
        var parser = CodexSessionLogParser(fallbackSessionId: "rollout-x")
        _ = parser.consume(line: line(sessionMeta), lineIndex: 0)
        _ = parser.consume(line: line(turnContext), lineIndex: 1) // no effort key
        let entry = try #require(parser.consume(line: line(tokenCountReasoningOverflow), lineIndex: 2))
        #expect(entry.reasoningTokens == 10) // min(reasoning, output)
        #expect(entry.contextWindow == nil) // 0 is not a window
        #expect(entry.effortLabel == nil)
    }
```

Also add fixtures and tests for `creatorAccountId` (consumed by §3 of the v3.3.0 spec's Codex
per-account attribution):

```swift
    private let sessionMetaWithAccount = #"{"timestamp":"2026-10-11T20:49:34.000Z","ordinal":0,"type":"session_meta","payload":{"id":"0199d7a0-0000-7000-8000-000000000001","cwd":"/Users/me/work/proj","originator":"codex_cli_rs","cli_version":"0.160.1","source":"cli","model_provider":"openai","creator_account_id":"b0776e30-1111-2222-3333-444444444444","git":{"branch":"main"},"base_instructions":{"text":"You are Codex"}}}"#
    private let sessionMetaEmptyAccount = #"{"timestamp":"2026-10-11T20:49:34.000Z","ordinal":0,"type":"session_meta","payload":{"id":"s-empty","cwd":"/x","creator_account_id":""}}"#

    @Test func sessionMeta_carriesCreatorAccountIdOntoEntries() throws {
        var parser = CodexSessionLogParser(fallbackSessionId: "rollout-x")
        _ = parser.consume(line: line(sessionMetaWithAccount), lineIndex: 0)
        _ = parser.consume(line: line(turnContext), lineIndex: 1)
        let entry = try #require(parser.consume(line: line(tokenCount), lineIndex: 2))
        #expect(entry.creatorAccountId == "b0776e30-1111-2222-3333-444444444444")
    }

    @Test func sessionMeta_withoutOrEmptyAccountId_leavesNil() throws {
        var parser = CodexSessionLogParser(fallbackSessionId: "rollout-x")
        _ = parser.consume(line: line(sessionMetaEmptyAccount), lineIndex: 0)
        _ = parser.consume(line: line(turnContext), lineIndex: 1)
        let entry = try #require(parser.consume(line: line(tokenCount), lineIndex: 2))
        #expect(entry.creatorAccountId == nil)
    }

    /// Two session_meta lines in one file (observed on disk): entries after the second
    /// take its account; entries before it keep whatever the first said.
    @Test func laterSessionMeta_overridesAccountForLaterEntries() throws {
        var parser = CodexSessionLogParser(fallbackSessionId: "rollout-x")
        _ = parser.consume(line: line(sessionMeta), lineIndex: 0) // no account
        _ = parser.consume(line: line(turnContext), lineIndex: 1)
        let before = try #require(parser.consume(line: line(tokenCount), lineIndex: 2))
        _ = parser.consume(line: line(sessionMetaWithAccount), lineIndex: 3)
        let after = try #require(parser.consume(line: line(tokenCountCacheWrite), lineIndex: 4))
        #expect(before.creatorAccountId == nil)
        #expect(after.creatorAccountId == "b0776e30-1111-2222-3333-444444444444")
    }
```

In Task 1 Step 6's parser implementation: a `private(set) var creatorAccountId: String?` next to
`cwd`; in `applySessionMeta`: `if let account = payload["creator_account_id"] as? String,
!account.isEmpty { creatorAccountId = account }`; in `makeEntry`'s `AssistantUsageEntry(…)` add
`creatorAccountId: creatorAccountId` after the three Phase 2 fields. `SessionLogReader.makeUsageEntry`
passes nothing (defaults to nil).

- [ ] **Step 2: Write the failing Claude reader tests**

Append to `SessionLogReaderTests`:

```swift
    @Test func makeUsageEntry_readsThinkingTokensAndSpeed() throws {
        let json = """
        {"type":"assistant","timestamp":"2026-10-12T10:00:00.000Z","sessionId":"s-1",
         "message":{"role":"assistant","model":"claude-opus-5","id":"msg-9",
           "usage":{"input_tokens":100,"output_tokens":226,"cache_read_input_tokens":0,
                    "cache_creation_input_tokens":0,"service_tier":"standard","speed":"fast",
                    "output_tokens_details":{"thinking_tokens":139}}}}
        """
        let decoded = try JSONDecoder().decode(SessionEntry.self, from: Data(json.utf8))
        let entry = try #require(SessionLogReader.makeUsageEntry(from: decoded))
        #expect(entry.reasoningTokens == 139)
        #expect(entry.effortLabel == "fast")
        #expect(entry.contextWindow == nil)
    }

    @Test func makeUsageEntry_standardSpeedAndNoDetails_defaults() throws {
        let json = """
        {"type":"assistant","timestamp":"2026-10-12T10:00:00.000Z","sessionId":"s-1",
         "message":{"role":"assistant","model":"claude-opus-5","id":"msg-10",
           "usage":{"input_tokens":100,"output_tokens":20,"speed":"standard"}}}
        """
        let decoded = try JSONDecoder().decode(SessionEntry.self, from: Data(json.utf8))
        let entry = try #require(SessionLogReader.makeUsageEntry(from: decoded))
        #expect(entry.reasoningTokens == 0)
        #expect(entry.effortLabel == nil)
    }
```

- [ ] **Step 3: Run to verify they fail**

Run: `swift test --filter "CodexSessionLogParser|SessionLogReader"`
Expected: compile errors — `contextWindow`, `reasoningTokens`, `effortLabel` do not exist.

- [ ] **Step 4: Extend the models**

In `AIBattery/Models/SessionEntry.swift` replace the `TokenUsage` struct with:

```swift
    struct TokenUsage: Codable {
        let inputTokens: Int?
        let outputTokens: Int?
        let cacheCreationInputTokens: Int?
        let cacheReadInputTokens: Int?
        let serviceTier: String?
        /// `"standard"` or `"fast"` (Claude fast mode). Absent on older logs.
        let speed: String?
        /// `output_tokens_details.thinking_tokens` — a subset of `output_tokens`.
        let outputTokensDetails: OutputTokensDetails?

        struct OutputTokensDetails: Codable {
            let thinkingTokens: Int?

            private enum CodingKeys: String, CodingKey {
                case thinkingTokens = "thinking_tokens"
            }
        }

        private enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
            case cacheCreationInputTokens = "cache_creation_input_tokens"
            case cacheReadInputTokens = "cache_read_input_tokens"
            case serviceTier = "service_tier"
            case speed
            case outputTokensDetails = "output_tokens_details"
        }
    }
```

Then add the three fields to `AssistantUsageEntry` **after** `toolCallCount`:

```swift
    let toolCallCount: Int
    /// Context window the provider reported for this turn (Codex `model_context_window`).
    /// nil → fall back to `TokenHealthConfig.contextWindow(for:)`.
    var contextWindow: Int? = nil
    /// Thinking (Claude) / reasoning (Codex) tokens — a SUBSET of `outputTokens`,
    /// never added to any total.
    var reasoningTokens: Int = 0
    /// Codex `turn_context.effort` (e.g. "xhigh") or Claude `usage.speed` when not
    /// "standard" (e.g. "fast"). nil when the provider reports nothing notable.
    var effortLabel: String? = nil
```

- [ ] **Step 5: Fill the fields in the Claude reader**

In `SessionLogReader.makeUsageEntry`, after `let toolCallCount = …` add:

```swift
        let output = usage.outputTokens ?? 0
        let thinking = min(max(usage.outputTokensDetails?.thinkingTokens ?? 0, 0), output)
        let speed = usage.speed?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let effort: String? = (speed == nil || speed == "standard" || speed == "") ? nil : speed
```

and extend the returned initializer:

```swift
            toolCallCount: toolCallCount,
            contextWindow: nil,
            reasoningTokens: thinking,
            effortLabel: effort
```

- [ ] **Step 6: Fill the fields in the Codex parser**

In `CodexSessionLogParser` add state next to `currentModel`:

```swift
    private(set) var currentEffort: String?
```

Replace the `turn_context` case with:

```swift
        case "turn_context":
            let payload = object["payload"] as? [String: Any]
            if let model = payload?["model"] as? String, !model.isEmpty {
                currentModel = model
            }
            if let effort = payload?["effort"] as? String {
                let cleaned = effort.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                currentEffort = cleaned.isEmpty ? nil : String(cleaned.prefix(8))
            }
            return nil
```

In `makeEntry`, after `let output = Self.int(last["output_tokens"])` add:

```swift
        let reasoning = min(max(Self.int(last["reasoning_output_tokens"]), 0), output)
        let window = Self.int(info["model_context_window"])
```

and extend the returned initializer:

```swift
            toolCallCount: 0, // would require decoding response_item lines — skipped for privacy
            contextWindow: window > 0 ? window : nil,
            reasoningTokens: reasoning,
            effortLabel: currentEffort
```

- [ ] **Step 7: Run the tests**

Run: `swift test --filter "CodexSessionLogParser|SessionLogReader"`
Expected: PASS (including the pre-existing suites).

- [ ] **Step 8: Update docs + commit**

`spec/DATA_LAYER.md`: in the `AssistantUsageEntry` description and the CodexSessionLogParser mapping table add the three fields with their sources (`model_context_window`, `reasoning_output_tokens` / `output_tokens_details.thinking_tokens`, `turn_context.effort` / `usage.speed`). README Services row: add "entry fields: context window, reasoning subset, effort/speed". 

```bash
swiftformat AIBattery/ Tests/ && swiftlint --quiet
git add -A
git commit -m "feat: carry context window, reasoning tokens and effort on usage entries"
```

---

### Task 2: Reasoning share through the aggregator, summaries and ledger

**Files:**
- Create: `AIBattery/Utilities/ReasoningVocabulary.swift`
- Modify: `AIBattery/Services/UsageAggregator.swift:83-97, 556-575`
- Modify: `AIBattery/Models/UsageSnapshot.swift:409-434`
- Modify: `AIBattery/Services/TokenLedger.swift:42-105, 214-225`
- Test: `Tests/AIBatteryCoreTests/Utilities/ReasoningVocabularyTests.swift` (new), `Tests/AIBatteryCoreTests/Services/UsageAggregatorTests.swift`, `Tests/AIBatteryCoreTests/Services/TokenLedgerTests.swift`

**Interfaces:**
- Produces: `ModelTokenSummary.reasoningTokens: Int` (defaulted init param) and `var reasoningShare: Double?` (0…1, nil when `outputTokens == 0`); `TokenLedger.ModelTokenRecord.reasoning: Int`; `ReasoningVocabulary.label(forModel:) -> String`.
- Consumes: `AssistantUsageEntry.reasoningTokens` (Task 1).

- [ ] **Step 1: Failing vocabulary test**

Create `Tests/AIBatteryCoreTests/Utilities/ReasoningVocabularyTests.swift`:

```swift
import Testing
@testable import AIBatteryCore

@Suite("ReasoningVocabulary")
struct ReasoningVocabularyTests {
    @Test func claudeModels_sayThinking() {
        #expect(ReasoningVocabulary.label(forModel: "claude-opus-5") == "thinking")
    }

    @Test func gptModels_sayReasoning() {
        #expect(ReasoningVocabulary.label(forModel: "gpt-6-astra") == "reasoning")
    }

    @Test func unknownModels_sayReasoning() {
        #expect(ReasoningVocabulary.label(forModel: "") == "reasoning")
    }
}
```

- [ ] **Step 2: Failing summary + aggregator + ledger tests**

Append to `UsageAggregatorTests` (use the suite's existing entry helper; if it has none, build entries with the memberwise init as in Task 1):

```swift
    @Test func modelTokenSummary_reasoningShare() {
        let summary = ModelTokenSummary(
            id: "gpt-6-astra", displayName: "GPT-6 Astra",
            inputTokens: 10, outputTokens: 400, cacheReadTokens: 0, cacheWriteTokens: 0,
            estimatedCost: 0, reasoningTokens: 120
        )
        #expect(summary.reasoningShare == 0.3)
        let silent = ModelTokenSummary(
            id: "x", displayName: "x", inputTokens: 1, outputTokens: 0,
            cacheReadTokens: 0, cacheWriteTokens: 0, estimatedCost: 0
        )
        #expect(silent.reasoningTokens == 0)
        #expect(silent.reasoningShare == nil)
    }
```

Append to `TokenLedgerTests`:

```swift
    @Test func merge_keepsReasoningHighWater_andDecodesLegacyRecords() throws {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        // Legacy blob without `reasoning`
        let legacy = #"{"accounts":{"acc":{"gpt-6-astra":{"input":1,"output":100,"cacheRead":0,"cacheWrite":0}}}}"#
        try Data(legacy.utf8).write(to: url)
        let ledger = TokenLedger(fileURL: url)
        var token = makeToken(id: "gpt-6-astra", output: 100)
        token = ModelTokenSummary(
            id: token.id, displayName: token.displayName, inputTokens: token.inputTokens,
            outputTokens: 100, cacheReadTokens: 0, cacheWriteTokens: 0, estimatedCost: 0,
            reasoningTokens: 30
        )
        let merged = ledger.merge([token], ledgerKey: "acc")
        #expect(merged.first?.reasoningTokens == 30)
        let lower = ModelTokenSummary(
            id: "gpt-6-astra", displayName: "GPT-6 Astra", inputTokens: 1, outputTokens: 100,
            cacheReadTokens: 0, cacheWriteTokens: 0, estimatedCost: 0, reasoningTokens: 5
        )
        #expect(ledger.merge([lower], ledgerKey: "acc").first?.reasoningTokens == 30)
    }
```

`merge(_:accountId:)` is now `merge(_:ledgerKey:)`. The key is whatever the aggregator passes
(`TokenLedger.key(accountId:provider:attribution:)`, v3.3.0 plan §3 "Ledger") — for every
existing user it is the plain account id, unchanged.

- [ ] **Step 3: Run to verify failure**

Run: `swift test --filter "ReasoningVocabulary|UsageAggregator|TokenLedger"`
Expected: compile errors (`ReasoningVocabulary`, `reasoningTokens:` label).

- [ ] **Step 4: Implement**

Create `AIBattery/Utilities/ReasoningVocabulary.swift`:

```swift
import Foundation

/// Provider vocabulary for the output-token subset spent before answering:
/// Anthropic calls it thinking, OpenAI calls it reasoning.
enum ReasoningVocabulary {
    nonisolated static func label(forModel model: String) -> String {
        model.hasPrefix("claude-") ? "thinking" : "reasoning"
    }
}
```

`AIBattery/Models/UsageSnapshot.swift` — in `ModelTokenSummary` add after `estimatedCost`:

```swift
    /// Thinking / reasoning tokens — a subset of `outputTokens` (never added to totals).
    var reasoningTokens: Int = 0

    /// Share of output spent on thinking / reasoning (0…1); nil when there is no output.
    var reasoningShare: Double? {
        guard outputTokens > 0 else { return nil }
        return min(Double(reasoningTokens) / Double(outputTokens), 1)
    }
```

`AIBattery/Services/UsageAggregator.swift` — change the tuple and both `accumulate` overloads:

```swift
    private typealias TokenMap = [String: (input: Int, output: Int, cacheRead: Int, cacheWrite: Int, reasoning: Int)]

    private static func accumulate(into map: inout TokenMap, key: String, entry: AssistantUsageEntry) {
        let e = map[key] ?? (0, 0, 0, 0, 0)
        map[key] = (e.input + entry.inputTokens, e.output + entry.outputTokens,
                    e.cacheRead + entry.cacheReadTokens, e.cacheWrite + entry.cacheWriteTokens,
                    e.reasoning + entry.reasoningTokens)
    }

    private static func accumulate(into map: inout TokenMap, key: String, tokens: TokenMap.Value) {
        let e = map[key] ?? (0, 0, 0, 0, 0)
        map[key] = (e.input + tokens.input, e.output + tokens.output,
                    e.cacheRead + tokens.cacheRead, e.cacheWrite + tokens.cacheWrite,
                    e.reasoning + tokens.reasoning)
    }
```

Every other place that builds a `TokenMap.Value` literal `(a, b, c, d)` (search `(0, 0, 0, 0)` and tuple constructions from stats-cache data) gets a fifth element `0` (the stats cache has no reasoning split). In `buildModelTokens` pass `reasoningTokens: tokens.reasoning`.

`AIBattery/Services/TokenLedger.swift` — `ModelTokenRecord`:

```swift
    struct ModelTokenRecord: Codable, Equatable {
        let input: Int
        let output: Int
        let cacheRead: Int
        let cacheWrite: Int
        var reasoning: Int = 0

        init(input: Int, output: Int, cacheRead: Int, cacheWrite: Int, reasoning: Int = 0) {
            self.input = input; self.output = output; self.cacheRead = cacheRead
            self.cacheWrite = cacheWrite; self.reasoning = reasoning
        }

        private enum CodingKeys: String, CodingKey { case input, output, cacheRead, cacheWrite, reasoning }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            input = try c.decode(Int.self, forKey: .input)
            output = try c.decode(Int.self, forKey: .output)
            cacheRead = try c.decode(Int.self, forKey: .cacheRead)
            cacheWrite = try c.decode(Int.self, forKey: .cacheWrite)
            reasoning = try c.decodeIfPresent(Int.self, forKey: .reasoning) ?? 0
        }
    }
```

In `merge`, the `merged` record gains `reasoning: max(model.reasoningTokens, stored?.reasoning ?? 0)`, and **both** `ModelTokenSummary(...)` constructions in `merge` (the seen-model one and the historical-model one) pass `reasoningTokens: merged.reasoning` / `reasoningTokens: record.reasoning`.

- [ ] **Step 5: Run the tests**

Run: `swift test --filter "ReasoningVocabulary|UsageAggregator|TokenLedger|UsageSnapshot"`
Expected: PASS.

- [ ] **Step 6: Docs + commit**

`spec/DATA_LAYER.md`: `ModelTokenSummary` (+ `reasoningTokens`, `reasoningShare`), `TokenLedger` (+ `reasoning`, legacy decode), `UsageAggregator` (TokenMap 5-tuple). README: Utilities row + "reasoning vocabulary"; Services row + "ledger reasoning high-water".

```bash
swiftformat AIBattery/ Tests/ && swiftlint --quiet
git add -A
git commit -m "feat: aggregate reasoning tokens per model and keep them in the ledger"
```

---

### Task 3: Context window, reasoning and effort on `TokenHealthStatus`

**Files:**
- Modify: `AIBattery/Models/TokenHealthStatus.swift:33-63`
- Modify: `AIBattery/Services/TokenHealthMonitor.swift:111-142, 250-272`
- Test: `Tests/AIBatteryCoreTests/Services/TokenHealthMonitorTests.swift` (helper `makeEntry` at ~L482)

**Interfaces:**
- Produces on `TokenHealthStatus`: `var reasoningTokens: Int = 0`, `var effortLabel: String? = nil`, `var reasoningShare: Double?`.
- Consumes: `AssistantUsageEntry.contextWindow / reasoningTokens / effortLabel` (Task 1).

- [ ] **Step 1: Extend the test helper and write failing tests**

In `TokenHealthMonitorTests`, add three defaulted parameters to the private `makeEntry(...)` helper — `reasoning: Int = 0, contextWindow: Int? = nil, effort: String? = nil` — and pass them through (`reasoningTokens: reasoning, contextWindow: contextWindow, effortLabel: effort`). Then append:

```swift
    @Test func assess_usesPerRecordContextWindow() {
        let entries = [makeEntry(sessionId: "s1", input: 100_000, output: 1_000, contextWindow: 258_400)]
        let result = monitor.assessCurrentSession(entries: entries)
        #expect(result?.contextWindow == 258_400)
        #expect(result?.usableWindow == 258_400)
    }

    @ test func assess_perRecordWindow_stillTierBumpsWhenExceeded() {
        // Record claims 200K but the turn already used 300K → bump to the next tier (500K)
        let entries = [makeEntry(sessionId: "s1", input: 300_000, output: 1_000, contextWindow: 200_000)]
        let result = monitor.assessCurrentSession(entries: entries)
        #expect(result?.contextWindow == 500_000)
        #expect((result?.usagePercentage ?? 0) < 100)
    }

    @Test func assess_sumsReasoningAndCarriesLatestEffort() {
        let entries = [
            makeEntry(sessionId: "s1", input: 1_000, output: 100, reasoning: 40, effort: "high"),
            makeEntry(sessionId: "s1", input: 2_000, output: 100, reasoning: 20, effort: "xhigh"),
        ]
        let result = monitor.assessCurrentSession(entries: entries)
        #expect(result?.reasoningTokens == 60)
        #expect(result?.reasoningShare == 0.3)
        #expect(result?.effortLabel == "xhigh")
    }
```

(Fix the typo `@ test` → `@Test` before running; it is written here only to make you read the test.)

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter TokenHealthMonitor`
Expected: compile errors (`contextWindow:` label on the helper, `reasoningTokens` on the status).

- [ ] **Step 3: Implement**

`TokenHealthStatus` — after `lastActivity` add:

```swift
    /// Thinking / reasoning tokens across the session — a subset of `outputTokens`.
    var reasoningTokens: Int = 0
    /// Latest turn's effort label ("xhigh", "fast", …); nil when the provider reports none.
    var effortLabel: String? = nil

    var reasoningShare: Double? {
        guard outputTokens > 0 else { return nil }
        return min(Double(reasoningTokens) / Double(outputTokens), 1)
    }
```

(`static let empty` keeps compiling because the new properties are defaulted `var`s.)

`TokenHealthMonitor.assess` — replace `var contextWindow = TokenHealthConfig.contextWindow(for: model)` with:

```swift
        // The provider's own figure wins (Codex writes `model_context_window` on every
        // token_count); the table is the fallback (Claude logs carry no window).
        var contextWindow = latestEntry.contextWindow ?? TokenHealthConfig.contextWindow(for: model)
```

(The upward tier bump that follows is unchanged and still applies.) Next to `let totalOutputTokens = …` add:

```swift
        let totalReasoningTokens = sessionEntries.reduce(0) { $0 + $1.reasoningTokens }
```

and extend the returned `TokenHealthStatus(...)`:

```swift
            lastActivity: lastTimestamp,
            reasoningTokens: min(totalReasoningTokens, totalOutputTokens),
            effortLabel: latestEntry.effortLabel
```

- [ ] **Step 4: Run the tests**

Run: `swift test --filter TokenHealthMonitor`
Expected: PASS.

- [ ] **Step 5: Docs + commit**

`spec/DATA_LAYER.md` `TokenHealthStatus` + `TokenHealthMonitor` (per-record window precedence, tier bump still applies); `spec/CONSTANTS.md` "Context Windows": `openAIDefaultContextWindow` is now the **fallback**. README Services row.

```bash
swiftformat AIBattery/ Tests/ && swiftlint --quiet
git add -A
git commit -m "feat: per-record context window, reasoning share and effort in context health"
```

---

### Task 4: Show share and effort in the Context row and Insights copy text

**Files:**
- Modify: `AIBattery/Views/TokenHealthSection.swift:30-95`
- Modify: `AIBattery/Views/InsightsTrendCostSection.swift:93-135`
- Test: `Tests/AIBatteryCoreTests/Views/TokenHealthSectionTextTests.swift` (new)

**Interfaces:**
- Produces: `TokenHealthSection.detailTrailingText(turnCount:model:effort:reasoningShare:reasoningTokens:) -> String` (pure, `nonisolated static`).

- [ ] **Step 1: Failing text test**

Create `Tests/AIBatteryCoreTests/Views/TokenHealthSectionTextTests.swift`:

```swift
import Testing
@testable import AIBatteryCore

@Suite("TokenHealthSection text")
struct TokenHealthSectionTextTests {
    @Test func codexRow_showsEffortAndReasoning() {
        let text = TokenHealthSection.detailTrailingText(
            turnCount: 12, model: "gpt-6-astra", effort: "xhigh", reasoningShare: 0.29, reasoningTokens: 36_226
        )
        #expect(text == "12 turns · GPT-6 Astra · xhigh · 29% reasoning")
    }

    @Test func claudeRow_showsThinkingAndFast() {
        let text = TokenHealthSection.detailTrailingText(
            turnCount: 3, model: "claude-opus-5", effort: "fast", reasoningShare: 0.615, reasoningTokens: 139
        )
        #expect(text.hasSuffix("· fast · 62% thinking"))
    }

    @Test func noExtras_matchesLegacyFormat() {
        let text = TokenHealthSection.detailTrailingText(
            turnCount: 3, model: "claude-opus-5", effort: nil, reasoningShare: nil, reasoningTokens: 0
        )
        #expect(text == "3 turns · \(ModelNameMapper.displayName(for: "claude-opus-5"))")
    }

    @Test func zeroReasoning_hidesShare() {
        let text = TokenHealthSection.detailTrailingText(
            turnCount: 1, model: "gpt-6-astra", effort: nil, reasoningShare: 0, reasoningTokens: 0
        )
        #expect(!text.contains("reasoning"))
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter "TokenHealthSection text"`
Expected: compile error, `detailTrailingText` not found.

- [ ] **Step 3: Implement the formatter and wire it**

In `TokenHealthSection` add:

```swift
    /// Trailing text of the detail row: turns · model [· effort] [· NN% thinking|reasoning].
    /// The share is omitted when there are no reasoning tokens so the legacy row is unchanged.
    nonisolated static func detailTrailingText(
        turnCount: Int, model: String, effort: String?, reasoningShare: Double?, reasoningTokens: Int
    ) -> String {
        let modelDisplay = model.isEmpty ? "unknown" : ModelNameMapper.displayName(for: model)
        var parts = ["\(turnCount) turns", modelDisplay]
        if let effort, !effort.isEmpty {
            parts.append(effort)
        }
        if let share = reasoningShare, reasoningTokens > 0 {
            parts.append("\(Int((share * 100).rounded()))% \(ReasoningVocabulary.label(forModel: model))")
        }
        return parts.joined(separator: " · ")
    }
```

Replace the detail row's `let turnsModelText = "\(health.turnCount) turns · \(modelDisplay)"` with:

```swift
                        let turnsModelText = Self.detailTrailingText(
                            turnCount: health.turnCount, model: health.model, effort: health.effortLabel,
                            reasoningShare: health.reasoningShare, reasoningTokens: health.reasoningTokens
                        )
```

Change its `.help(...)` to:

```swift
                            .help(health.reasoningTokens > 0
                                ? "Conversation turns, model, effort, and the share of this session's output spent on \(ReasoningVocabulary.label(forModel: health.model))"
                                : "Conversation turns in this session")
```

and the combined accessibility label to use `turnsModelText`:

```swift
                    .accessibilityLabel("~\(remainingText) of \(usableText) usable, \(turnsModelText)")
```

In `InsightsTrendCostSection.costSection`, after `let activeSuffix = …` add:

```swift
                    let shareSuffix: String = {
                        guard let share = model.reasoningShare, model.reasoningTokens > 0 else { return "" }
                        return " \u{00B7} \(Int((share * 100).rounded()))% \(ReasoningVocabulary.label(forModel: model.id))"
                    }()
```

and append `\(shareSuffix)` to both `copyText` and the `.accessibilityLabel(...)` string (visible columns unchanged).

- [ ] **Step 4: Run tests, then look at it**

Run: `swift test --filter "TokenHealthSection text|Insights"`
Expected: PASS.

```bash
./scripts/build-app.sh && open .build/AIBattery.app
```

Open the popover, switch to Context: with a Codex session active the row ends in `· xhigh · NN% reasoning`; with a Claude session `· NN% thinking`. If a Keychain prompt blocks the rebuilt app, click Always Allow.

- [ ] **Step 5: Docs + commit**

`spec/UI_SPEC.md` Context section (detail row format, help text) and Insights rows (copy text suffix). README Views row.

```bash
swiftformat AIBattery/ Tests/ && swiftlint --quiet
git add -A
git commit -m "feat: show effort and thinking/reasoning share in the Context row"
```

---

### Task 5: Limit name on the Codex credits bar

**Files:**
- Modify: `AIBattery/Models/CodexCreditBudget.swift:6-30`
- Modify: `AIBattery/Models/CodexUsageParser.swift:84-125`
- Modify: `AIBattery/Views/CreditBudgetSection.swift:12-35` (`headerTooltip`)
- Test: `Tests/AIBatteryCoreTests/Models/CodexUsageParserTests.swift`, `Tests/AIBatteryCoreTests/Models/CodexCreditBudgetTests.swift`

**Interfaces:**
- Produces: `CodexCreditBudget.limitName: String?`; `CreditBudgetSection.planLine(limitName:planType:) -> String?` (pure).

- [ ] **Step 1: Failing tests**

Append to `CodexUsageParserTests`:

```swift
    @Test func parseCreditBudget_readsLimitName() throws {
        let dict: [String: Any] = [
            "plan_type": "business",
            "limit_name": "Engineering monthly cap",
            "spend_control": ["individual_limit": ["limit": 100, "used": 25, "remaining": 75, "used_percent": 25, "unit": "credit"], "reached": false],
        ]
        let budget = try #require(CodexUsageParser.parseCreditBudget(dict))
        #expect(budget.limitName == "Engineering monthly cap")
    }
```

Append to `CodexCreditBudgetTests`:

```swift
    @Test func planLine_prefersLimitName() {
        #expect(CreditBudgetSection.planLine(limitName: "Eng cap", planType: "business") == "Plan: Eng cap")
        #expect(CreditBudgetSection.planLine(limitName: nil, planType: "business") == "Plan: business")
        #expect(CreditBudgetSection.planLine(limitName: "  ", planType: nil) == nil)
    }

    @Test func legacyBudgetBlob_decodesWithoutLimitName() throws {
        let json = #"{"usedPercent":10,"used":1,"limit":10,"remaining":9,"unit":"credit","resetsAt":null,"reached":false,"hasCredits":true,"unlimited":false,"planType":"business"}"#
        let budget = try JSONDecoder().decode(CodexCreditBudget.self, from: Data(json.utf8))
        #expect(budget.limitName == nil)
    }
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter "CodexUsageParser|CodexCreditBudget"`
Expected: compile errors.

- [ ] **Step 3: Implement**

`CodexCreditBudget` after `uncapped`:

```swift
    /// `limit_name` from the payload (e.g. a workspace's named spend cap). Optional so
    /// persisted blobs decode.
    var limitName: String? = nil
```

`CodexUsageParser.parseCreditBudget`: add `let limitName = (dict["limit_name"] as? String)` after `let planType = …`, and on **both** `CodexCreditBudget(...)` constructions append `limitName: limitName` (after `balance:`). Keep `rolledOver()` passing `limitName` through (it is a property of the plan, like `planType`).

`CreditBudgetSection`:

```swift
    nonisolated static func planLine(limitName: String?, planType: String?) -> String? {
        let name = limitName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !name.isEmpty { return "Plan: \(name)" }
        if let planType, !planType.isEmpty { return "Plan: \(planType)" }
        return nil
    }
```

and in `headerTooltip` replace `if let planType = budget.planType { parts.append("Plan: \(planType)") }` with `if let line = Self.planLine(limitName: budget.limitName, planType: budget.planType) { parts.append(line) }`.

- [ ] **Step 4: Run tests + commit**

Run: `swift test --filter "CodexUsageParser|CodexCreditBudget|CodexRateLimitFetcher"` → PASS.
Docs: `spec/DATA_LAYER.md` `CodexCreditBudget` fields; `spec/UI_SPEC.md` §❷a tooltip. README Models row.

```bash
swiftformat AIBattery/ Tests/ && swiftlint --quiet
git add -A
git commit -m "feat: name the Codex credit cap from limit_name"
```

---

### Task 6: Claude per-model weekly windows (ONLY if Task 0 recorded "present")

If Task 0 recorded **absent**, skip this task entirely and note "Task 6 skipped per R1" in the PR description.

**Files:**
- Modify: `AIBattery/Models/RateLimitUsage.swift:41-70` (fields), `:88-110` (init), `:112-126` (decoder), `:620-640` (parse construction)
- Create: `AIBattery/Views/ModelWindowRows.swift`
- Modify: `AIBattery/Views/UsagePopoverView.swift` (`.sevenDay` case, after `SevenDayBarSection`)
- Test: `Tests/AIBatteryCoreTests/Models/RateLimitUsageTests.swift`, `Tests/AIBatteryCoreTests/Views/ModelWindowRowsTests.swift` (new)

**Interfaces:**
- Produces: `struct ModelWindow: Codable, Equatable, Sendable { let model: String; let utilization: Double; let reset: Date?; let status: String }`; `RateLimitUsage.modelWindows: [ModelWindow]` (default `[]`); `ModelWindowRows.rowText(window:now:) -> String`.

- [ ] **Step 1: Failing parse test**

Append to `RateLimitUsageTests` (adapt the key names to exactly what Task 0 recorded):

```swift
    @Test func parse_clientDataJSON_readsPerModelWeeklyWindows() throws {
        let json = """
        {"five_hour":{"utilization":10,"resets_at":"2026-10-12T12:00:00Z"},
         "seven_day":{"utilization":40,"resets_at":"2026-10-15T00:00:00Z"},
         "seven_day_opus":{"utilization":62,"resets_at":"2026-10-15T00:00:00Z"},
         "seven_day_sonnet":{"utilization":5,"resets_at":"2026-10-15T00:00:00Z"}}
        """
        let usage = try #require(RateLimitUsage.parse(clientData: Data(json.utf8)))
        #expect(usage.modelWindows.map(\.model) == ["opus", "sonnet"])
        #expect(usage.modelWindows.first?.utilization == 0.62)
        #expect(usage.modelWindows.first?.reset != nil)
    }

    @Test func legacyPersistedRateLimits_decodeWithoutModelWindows() throws {
        let json = #"{"representativeClaim":"five_hour","fiveHourUtilization":0.1,"fiveHourReset":null,"fiveHourStatus":"allowed","sevenDayUtilization":0.2,"sevenDayReset":null,"sevenDayStatus":"allowed","overallStatus":"allowed"}"#
        let usage = try JSONDecoder().decode(RateLimitUsage.self, from: Data(json.utf8))
        #expect(usage.modelWindows.isEmpty)
    }
```

- [ ] **Step 2: Run to verify failure** — `swift test --filter RateLimitUsage` → compile error.

- [ ] **Step 3: Implement the model**

In `RateLimitUsage.swift` add the nested type and field:

```swift
struct ModelWindow: Codable, Equatable, Sendable {
    /// Model family as named by the payload key suffix (`seven_day_opus` → "opus").
    let model: String
    let utilization: Double // 0…1
    let reset: Date?
    let status: String
}
```

```swift
    /// Per-model weekly windows some Claude plans report (`seven_day_<model>`). Empty for
    /// Codex and for payloads without them. Display only — never feeds the menu bar,
    /// notifications or the spike filter.
    var modelWindows: [ModelWindow] = []
```

In the custom `init(from:)` add `modelWindows = try c.decodeIfPresent([ModelWindow].self, forKey: .modelWindows) ?? []` (add the case to `CodingKeys`). In `parse(clientDataJSON:)`, right before the final construction, derive:

```swift
        let modelWindows: [ModelWindow] = json.keys.sorted().compactMap { key in
            guard key.hasPrefix("seven_day_"), let obj = json[key] as? [String: Any] else { return nil }
            let model = String(key.dropFirst("seven_day_".count))
            guard !model.isEmpty, let raw = obj["utilization"] as? Double else { return nil }
            let utilization = raw > 1 ? raw / 100 : raw
            let reset = (obj["resets_at"] as? String).flatMap(DateFormatters.parseISO8601)
            return ModelWindow(model: model, utilization: min(max(utilization, 0), 1),
                               reset: reset, status: (obj["status"] as? String) ?? "allowed")
        }
```

and assign it to the constructed value (`var usage = RateLimitUsage(...); usage.modelWindows = modelWindows; return usage`). Reuse the file's existing utilization-normalising helper if one exists instead of the inline `raw > 1` rule.

- [ ] **Step 4: Failing row-text test + view**

Create `Tests/AIBatteryCoreTests/Views/ModelWindowRowsTests.swift`:

```swift
import Foundation
import Testing
@testable import AIBatteryCore

@Suite("ModelWindowRows")
struct ModelWindowRowsTests {
    @Test func rowText_formatsModelPercentAndReset() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let window = ModelWindow(model: "opus", utilization: 0.62, reset: now.addingTimeInterval(2 * 86_400), status: "allowed")
        #expect(ModelWindowRows.rowText(window: window, now: now) == "Opus weekly 62% · resets in 2d")
    }

    @Test func rowText_withoutReset() {
        let window = ModelWindow(model: "sonnet", utilization: 0.05, reset: nil, status: "allowed")
        #expect(ModelWindowRows.rowText(window: window, now: Date()) == "Sonnet weekly 5%")
    }
}
```

Create `AIBattery/Views/ModelWindowRows.swift`:

```swift
import SwiftUI

/// Compact per-model weekly rows under the 7-Day bar (Claude plans that report them).
struct ModelWindowRows: View {
    let windows: [ModelWindow]

    nonisolated static func rowText(window: ModelWindow, now: Date) -> String {
        let name = window.model.prefix(1).uppercased() + window.model.dropFirst()
        var text = "\(name) weekly \(Int((window.utilization * 100).rounded()))%"
        if let reset = window.reset, reset > now {
            text += " · resets in \(DurationFormatter.compact(reset.timeIntervalSince(now)))"
        }
        return text
    }

    var body: some View {
        if !windows.isEmpty {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                VStack(alignment: .leading, spacing: Spacing.tight) {
                    ForEach(windows, id: \.model) { window in
                        let text = Self.rowText(window: window, now: context.date)
                        Text(text)
                            .font(Typography.tinyLabel)
                            .foregroundStyle(ThemeColors.secondaryLabel)
                            .copyable(text)
                            .help("Weekly limit for \(window.model) models on this plan")
                    }
                }
                .padding(.horizontal, Spacing.sectionHorizontal)
                .padding(.bottom, Spacing.section)
            }
        }
    }
}
```

In `UsagePopoverView` `.sevenDay` case, directly after `SevenDayBarSection(...)` (before the credit-balance row):

```swift
                            if limits.provider == .claude {
                                ModelWindowRows(windows: limits.modelWindows)
                            }
```

- [ ] **Step 5: Run tests + smoke test + commit**

`swift test --filter "RateLimitUsage|ModelWindowRows"` → PASS. Build and open the popover on the Claude account; rows appear only if the live payload has them.
Docs: `spec/DATA_LAYER.md` `RateLimitUsage` (+ `modelWindows`), `spec/UI_SPEC.md` ❷ 7-Day section, `spec/CONSTANTS.md` URLs unchanged. README Models + Views rows.

```bash
swiftformat AIBattery/ Tests/ && swiftlint --quiet
git add -A
git commit -m "feat: show Claude per-model weekly windows under the 7-Day bar"
```

---

### Task 7: Codex API-key accounts in the fan-out and the menu bar — DONE ELSEWHERE

Implemented by `2026-10-12-multi-account-overview-plan.md` **Task 1** (`AccountReading`, `FanOutGate`, API-key eligibility, per-minute menu-bar slots), which runs in Phase 1 of the release plan. Nothing to do here; later tasks may rely on `UsageViewModel.perAccountAPILimits` existing.

---

### Task 8: Credit-budget runway

**Files:**
- Modify: `AIBattery/Models/CodexCreditBudget.swift`
- Modify: `AIBattery/Services/CodexRateLimitFetcher.swift:270-…` (fresh-reading path) and `rolledOver()` call sites
- Modify: `AIBattery/Views/CreditBudgetSection.swift` footer
- Modify: `AIBattery/Utilities/Spacing.swift` (or wherever `RateLimitConstants` live per `spec/CONSTANTS.md` "Predictive Rate Limit") — `creditRunwayMinObservation: TimeInterval = 3600`
- Test: `Tests/AIBatteryCoreTests/Models/CodexCreditBudgetTests.swift`, `Tests/AIBatteryCoreTests/Services/CodexRateLimitFetcherTests.swift`

**Interfaces:**
- Produces: `struct CodexCreditBudget.PeriodAnchor: Codable, Equatable, Sendable { let at: Date; let used: Double; let resetsAt: Date? }`; `CodexCreditBudget.periodAnchor: PeriodAnchor?`; `func anchored(from cached: CodexCreditBudget?, now: Date) -> CodexCreditBudget`; `func estimatedTimeToExhaustion(now:) -> TimeInterval?`.

- [ ] **Step 1: Failing model tests**

Append to `CodexCreditBudgetTests` (use the suite's existing budget factory; shown here with explicit fields):

```swift
    private func budget(used: Double, limit: Double = 100, resetsAt: Date?) -> CodexCreditBudget {
        CodexCreditBudget(usedPercent: used / limit * 100, used: used, limit: limit, remaining: limit - used,
                          unit: "credit", resetsAt: resetsAt, reached: false, hasCredits: true, unlimited: false, planType: "business")
    }

    @Test func anchored_setsAnchorOnFirstReading_andCarriesItWithinPeriod() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let reset = t0.addingTimeInterval(30 * 86_400)
        let first = budget(used: 10, resetsAt: reset).anchored(from: nil, now: t0)
        #expect(first.periodAnchor == .init(at: t0, used: 10, resetsAt: reset))
        let later = budget(used: 20, resetsAt: reset).anchored(from: first, now: t0.addingTimeInterval(7200))
        #expect(later.periodAnchor?.at == t0)
        #expect(later.periodAnchor?.used == 10)
    }

    @Test func anchored_resetsWhenPeriodChanges() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let first = budget(used: 90, resetsAt: t0.addingTimeInterval(100)).anchored(from: nil, now: t0)
        let next = budget(used: 1, resetsAt: t0.addingTimeInterval(86_400)).anchored(from: first, now: t0.addingTimeInterval(200))
        #expect(next.periodAnchor?.used == 1)
    }

    @Test func runway_requiresObservationAndSpend() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let reset = t0.addingTimeInterval(30 * 86_400)
        let first = budget(used: 10, resetsAt: reset).anchored(from: nil, now: t0)
        let tooSoon = budget(used: 12, resetsAt: reset).anchored(from: first, now: t0.addingTimeInterval(600))
        #expect(tooSoon.estimatedTimeToExhaustion(now: t0.addingTimeInterval(600)) == nil)
        let noSpend = budget(used: 10, resetsAt: reset).anchored(from: first, now: t0.addingTimeInterval(7200))
        #expect(noSpend.estimatedTimeToExhaustion(now: t0.addingTimeInterval(7200)) == nil)
    }

    @Test func runway_projectsAtObservedPace_andSuppressesPastReset() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let reset = t0.addingTimeInterval(30 * 86_400)
        let first = budget(used: 10, resetsAt: reset).anchored(from: nil, now: t0)
        // 10 credits in 2 h → 90 remaining ≈ 18 h
        let now = t0.addingTimeInterval(7200)
        let b = budget(used: 20, resetsAt: reset).anchored(from: first, now: now)
        #expect(abs((b.estimatedTimeToExhaustion(now: now) ?? 0) - 18 * 3600) < 1)
        // Reset in 1 h → projection lands after reset → nil
        let soonReset = budget(used: 20, resetsAt: now.addingTimeInterval(3600)).anchored(from: first, now: now)
        #expect(soonReset.estimatedTimeToExhaustion(now: now) == nil)
    }

    @Test func rolledOver_clearsAnchor() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let b = budget(used: 10, resetsAt: t0).anchored(from: nil, now: t0)
        #expect(b.rolledOver().periodAnchor == nil)
    }
```

- [ ] **Step 2: Run to verify failure** — `swift test --filter CodexCreditBudget` → compile errors.

- [ ] **Step 3: Implement the model**

In `CodexCreditBudget`:

```swift
    /// First reading AI Battery saw in the current budget period: the baseline for the
    /// runway estimate. Carried across readings while `resetsAt` is unchanged.
    var periodAnchor: PeriodAnchor? = nil

    struct PeriodAnchor: Codable, Equatable, Sendable {
        let at: Date
        let used: Double
        let resetsAt: Date?
    }

    /// Carry the cached reading's anchor when it is the same period; otherwise start one.
    func anchored(from cached: CodexCreditBudget?, now: Date) -> CodexCreditBudget {
        var copy = self
        if let anchor = cached?.periodAnchor, anchor.resetsAt == resetsAt, anchor.used <= used {
            copy.periodAnchor = anchor
        } else {
            copy.periodAnchor = PeriodAnchor(at: now, used: used, resetsAt: resetsAt)
        }
        return copy
    }

    /// "~N to limit" for a capped budget at the pace observed since `periodAnchor`.
    /// nil until an hour of observation, with no spend, when nothing remains, or when
    /// the projection lands after the period resets (the reset gets there first).
    func estimatedTimeToExhaustion(now: Date) -> TimeInterval? {
        guard !isUncapped, limit > 0, remaining > 0, let anchor = periodAnchor else { return nil }
        let elapsed = now.timeIntervalSince(anchor.at)
        guard elapsed >= RateLimitConstants.creditRunwayMinObservation else { return nil }
        let spent = used - anchor.used
        guard spent > 0 else { return nil }
        let eta = remaining / (spent / elapsed)
        if let resetsAt, now.addingTimeInterval(eta) >= resetsAt { return nil }
        return eta
    }
```

`rolledOver()`: set `periodAnchor = nil` on the returned value. Add `static let creditRunwayMinObservation: TimeInterval = 3600` next to the other predictive-limit constants (the type `spec/CONSTANTS.md` "Predictive Rate Limit" names; if that section's constants live on `RateLimitUsage`, put it there and update the call above).

- [ ] **Step 4: Fetcher carry-forward (failing test first)**

Append to `CodexRateLimitFetcherTests` a test that feeds two fresh `wham/usage` Business payloads (same `reset_at`, `used` 10 then 20) through the suite's existing stubbed-session path and asserts `result2.rateLimits?.creditBudget?.periodAnchor?.used == 10`. Then in `CodexRateLimitFetcher.fetch`, where a fresh `RateLimitUsage` with `creditBudget != nil` is about to be cached/returned, replace the budget with `budget.anchored(from: cachedLimits?.creditBudget, now: Date())` (the cached value is the per-account entry the fetcher already holds for the session-log fallback). `PersistedCodexRateLimits` needs no change — `periodAnchor` rides inside `RateLimitUsage.creditBudget` (already Codable, new field optional).

- [ ] **Step 5: Footer**

In `CreditBudgetSection` footer, before the final `else` branch (`remainingText`), add:

```swift
                    } else if confirmed, let eta = budget.estimatedTimeToExhaustion(now: now) {
                        let runwayText = "~\(DurationFormatter.compact(eta)) to limit"
                        Text(runwayText)
                            .font(Typography.tinyLabel)
                            .foregroundStyle(ThemeColors.caution)
                            .copyable(runwayText)
                            .help("Estimated time until the credit cap at the pace observed this period")
```

(`confirmed` is the section's existing init parameter, same gate the window bars use.)

- [ ] **Step 6: Run tests + commit**

`swift test --filter "CodexCreditBudget|CodexRateLimitFetcher"` → PASS.
Docs: `spec/DATA_LAYER.md` `CodexCreditBudget` (+ anchor, runway), `CodexRateLimitFetcher` (anchor carry); `spec/CONSTANTS.md` "Predictive Rate Limit" (+ `creditRunwayMinObservation` 3600 s); `spec/UI_SPEC.md` §❷a footer. README Models + Services rows.

```bash
swiftformat AIBattery/ Tests/ && swiftlint --quiet
git add -A
git commit -m "feat: runway estimate for Codex credit budgets"
```

---

### Task 9: Dated Codex All-Time (ledger first-scan)

**Files:**
- Modify: `AIBattery/Services/TokenLedger.swift` (`LedgerData`, `merge`, new accessor)
- Modify: `AIBattery/Models/UsageSnapshot.swift` (`var ledgerSince: Date? = nil`)
- Modify: `AIBattery/Services/UsageAggregator.swift:460-499` (set it after the ledger merge, Codex only)
- Modify: `AIBattery/Views/InsightsRowsAndHover.swift:33-51` (tooltip), `AIBattery/Views/InsightsCharts.swift` (`sinceCaption`), `AIBattery/Views/ActivityChartView.swift` (render the caption under the chart, every mode)
- Test: `Tests/AIBatteryCoreTests/Services/TokenLedgerTests.swift`, `Tests/AIBatteryCoreTests/Views/InsightsAllTimeCaveatTests.swift` (exists; append)

**Interfaces:**
- Produces: `TokenLedger.firstScanDate(ledgerKey:) -> Date?`; `UsageSnapshot.ledgerSince: Date?`; `InsightsView.allTimeTooltip(for:since:) -> String`; `InsightsView.sinceCaption(provider:since:unattributed:now:) -> String?`. The key is whatever the aggregator passes (`TokenLedger.key(accountId:provider:attribution:)`, v3.3.0 plan §3 "Ledger") — for every existing user it is the plain account id, unchanged. Keep the name `InsightsView.allTimeTooltip(for:since:)` — that is right; the function lives in `InsightsRowsAndHover.swift` as an `extension InsightsView`. `sinceCaption` lives in `InsightsCharts.swift`, also an `extension InsightsView`, and returns the one caption line for **every** chart mode: `"since 12 Oct 2026"`, `"N turns from older Codex CLI versions not shown"`, both joined with `" · "`, or nil. Render it in `ActivityChartView.swift` right after the `switch mode { … }` that picks the chart (`:58-66`), regardless of mode, when non-nil.

- [ ] **Step 1: Failing tests**

`TokenLedgerTests`:

```swift
    @Test func merge_recordsFirstScanDateOncePerAccount() {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let ledger = TokenLedger(fileURL: url)
        #expect(ledger.firstScanDate(ledgerKey: "acc") == nil)
        _ = ledger.merge([makeToken(output: 1)], ledgerKey: "acc")
        let first = ledger.firstScanDate(ledgerKey: "acc")
        #expect(first != nil)
        _ = ledger.merge([makeToken(output: 2)], ledgerKey: "acc")
        #expect(ledger.firstScanDate(ledgerKey: "acc") == first)
        // survives reload
        #expect(TokenLedger(fileURL: url).firstScanDate(ledgerKey: "acc") == first)
    }
```

Append to `Tests/AIBatteryCoreTests/Views/InsightsAllTimeCaveatTests.swift` (it exists; add the
`since` cases here — the `unattributed` cases are added by the v3.3.0 plan's Codex-attribution
task):

```swift
    @Test func codex_withSince_appendsDate() {
        let since = Date(timeIntervalSince1970: 1_789_000_000)
        let text = InsightsView.allTimeTooltip(for: .codex, since: since)
        #expect(text.hasPrefix("Cumulative tokens from Codex session logs"))
        #expect(text.contains("since "))
    }

    @Test func claude_ignoresSince() {
        #expect(InsightsView.allTimeTooltip(for: .claude, since: Date()) == "Cumulative tokens across all sessions")
    }

    @Test func chartCaption_onlyForCodexWithinTwelveMonths() {
        let now = Date(timeIntervalSince1970: 1_789_000_000)
        #expect(InsightsView.sinceCaption(provider: .codex, since: now.addingTimeInterval(-30 * 86_400), unattributed: 0, now: now)?.hasPrefix("since ") == true)
        #expect(InsightsView.sinceCaption(provider: .codex, since: now.addingTimeInterval(-400 * 86_400), unattributed: 0, now: now) == nil)
        #expect(InsightsView.sinceCaption(provider: .claude, since: now, unattributed: 0, now: now) == nil)
        #expect(InsightsView.sinceCaption(provider: .codex, since: nil, unattributed: 0, now: now) == nil)
    }
```

- [ ] **Step 2: Run to verify failure** — `swift test --filter "TokenLedger|InsightsView — All Time caveat"` → compile errors.

- [ ] **Step 3: Implement**

`TokenLedger.LedgerData` gains `var firstScan: [String: Date] = [:]` with a custom `init(from:)` using `decodeIfPresent` (mirror the `ModelTokenRecord` pattern from Task 2). In `merge`, before the `if changed` block:

```swift
        if ledger.firstScan[ledgerKey] == nil {
            ledger.firstScan[ledgerKey] = Date()
            changed = true
        }
```

(The existing `if changed { ledger.accounts[ledgerKey] = accountData; isDirty = true; save() }` persists it.) Add:

```swift
    func firstScanDate(ledgerKey: String) -> Date? {
        lock.lock(); defer { lock.unlock() }
        return ledger.firstScan[ledgerKey]
    }
```

`pruneAccounts` and `migrate` must move/drop `firstScan` entries alongside `accounts` (update both; add one assertion to the suite's existing migrate test: the date follows the account).

`UsageSnapshot`: add `var ledgerSince: Date? = nil` after `firstSessionDate` (defaulted `var` so every init call site compiles). `UsageAggregator`: where the aggregator merges with `TokenLedger.shared` for the account, set `snapshot.ledgerSince = provider == .codex ? ledger.firstScanDate(ledgerKey: ledgerKey) : nil` (make the snapshot a `var` at that point, or pass the value into the init if construction happens after the merge).

`InsightsRowsAndHover.swift`:

```swift
    nonisolated static func allTimeTooltip(for provider: AIProvider, since: Date? = nil) -> String {
        switch provider {
        case .claude: return "Cumulative tokens across all sessions"
        case .codex:
            let base = "Cumulative tokens from Codex session logs since AI Battery first scanned them (kept across log rotation; Codex has no lifetime cache of its own)"
            guard let since else { return base }
            return base + " — since \(DateFormatters.mediumDate(since))"
        }
    }
```

(If `DateFormatters` has no medium-date helper, add `static func mediumDate(_ date: Date) -> String` using a cached `DateFormatter` with `dateStyle = .medium`, `timeStyle = .none`.) Call site: `tooltip: Self.allTimeTooltip(for: snapshot.provider, since: snapshot.ledgerSince)`.

`InsightsCharts.swift` (an `extension InsightsView`):

```swift
    nonisolated static func sinceCaption(provider: AIProvider, since: Date?, unattributed: Int = 0, now: Date) -> String? {
        let sincePart: String? = {
            guard provider == .codex, let since, since > now.addingTimeInterval(-365 * 86_400) else { return nil }
            return "since \(DateFormatters.mediumDate(since))"
        }()
        let unattributedPart = unattributed > 0
            ? "\(unattributed) turns from older Codex CLI versions not shown" : nil
        let parts = [sincePart, unattributedPart].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
```

Render under the chart in **every** mode, right after the `switch mode { … }` that picks the
chart (`ActivityChartView.swift:58-66`), when the caption is non-nil:
`Text(caption).font(Typography.monoTiny).foregroundStyle(ThemeColors.tertiaryLabel).help("The 12-month chart is rebuilt from the Codex rollouts still on disk; All Time is a ledger that also keeps what was scanned before rotation")`.

- [ ] **Step 4: Run tests + commit**

`swift test --filter "TokenLedger|InsightsView — All Time caveat|ActivityChart|UsageAggregator"` → PASS.
Docs: `spec/DATA_LAYER.md` `TokenLedger` (+ `firstScan`), `UsageSnapshot` (+ `ledgerSince`); `spec/UI_SPEC.md` Insights All-Time tooltip + 12M caption. README Services + Views rows.

```bash
swiftformat AIBattery/ Tests/ && swiftlint --quiet
git add -A
git commit -m "feat: date the Codex All-Time figure from the ledger's first scan"
```

---

### Task 10: Other-accounts strip — SUPERSEDED

Replaced by the multi-account overview (Phase 1 of the release plan). Not built.

---

### Task 11: Spec sync for this phase

**Files:** `spec/ARCHITECTURE.md` (project tree: `ReasoningVocabulary.swift`, `ModelWindowRows.swift` if built), `spec/DATA_LAYER.md`, `spec/UI_SPEC.md`, `spec/CONSTANTS.md`, `README.md` feature bullets, `CLAUDE.md` Key Design Decisions bullet (*reasoning tokens are a subset of output; per-record context window beats the table*).

- [ ] **Step 1:** Re-read the four spec files against the code for every item landed in this phase; fix drift.
- [ ] **Step 2:** `swiftformat AIBattery/ AIBatteryApp/ Tests/ && swiftlint` clean; `swift test` passes; `./scripts/build-app.sh && open .build/AIBattery.app` walkthrough per account (Context row, Insights tooltip, credits footer).
- [ ] **Step 3:** Commit with message `docs: sync specs for provider-relevant display`. Test counts, the changelog heading and the PR are handled by the release plan's wrap-up, not here.

---

## Self-review against the spec

- §1 context window → Task 1 (parse) + Task 3 (monitor). §2 reasoning → Tasks 1, 2, 3, 4. §3 effort → Tasks 1, 3, 4. §4 limit name → Task 5. §5 per-model windows → Task 0 gate + Task 6. §6 API-key menu bar → overview plan Task 1 (Task 7 here is a pointer). §7 runway → Task 8. §8 dated All-Time → Task 9. §9 strip → superseded (Task 10 is a pointer). §10 error handling → every new field is defaulted/optional with a legacy-decode test (Tasks 2, 5, 6, 9). §11 testing → each task has failing-test-first steps; counts in Task 11. R1 → Task 0; R2 → noted as not needed by the §7 method (observed pace), still cheap to glance at during Task 8; R3 → clamp in Task 1 plus the overflow test.
- Names used across tasks: `reasoningTokens` (entry, summary, status, ledger record as `reasoning`), `effortLabel`, `contextWindow`, `creatorAccountId`, `ReasoningVocabulary.label(forModel:)`, `FanOutResult.windows/apiLimits`, `perAccountAPILimits`, `CodexCreditBudget.periodAnchor/anchored(from:now:)/estimatedTimeToExhaustion(now:)`, `TokenLedger.firstScanDate(ledgerKey:)`, `UsageSnapshot.ledgerSince`, `InsightsView.allTimeTooltip(for:since:)`, `InsightsView.sinceCaption(provider:since:unattributed:now:)`, `OtherAccountsStrip.rows(accounts:activeId:windows:apiLimits:maskEmail:)` — consistent.
- Known soft spots an implementer must resolve on the spot (named in the steps): the exact helper names in `MultiAccountFanOutTests` / `MenuBarMultiAccountTextTests` / `AccountStoreTests` fixtures, where the predictive-limit constants live, and the mask-toggle key read by the chip.
