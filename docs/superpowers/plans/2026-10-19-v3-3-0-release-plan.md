# v3.3.0 Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship v3.3.0: the header update arrow, Phase 2 provider-relevant display, and Codex per-account attribution, on one integration branch, preceded by worktree and website housekeeping.

**Architecture:** Three independent pieces ride existing seams. The arrow is one new SwiftUI view inserted beside the two gears. Phase 2 is the already-written plan `2026-10-12-provider-relevance-plan.md`, re-based onto v3.2.0 by a docs commit (Task 4) and then executed from that file. Attribution first extracts the aggregator's loop body into an `AggregationPass` struct with zero behaviour change (Task 3), then runs two instances per entry under attribution so one pass yields the per-account snapshot *and* the provider-wide one — no second read, no second loop, no attribution-keyed cache. The ledger separates series by key suffix instead of migrating. Attribution is decided in one place, `UsageViewModel.aggregateOffMain`, which also publishes the provider-wide snapshot the overview cards read.

**Tech Stack:** Swift 6 / SwiftUI, SPM, Swift Testing (`import Testing`, `@testable import AIBatteryCore`), Sparkle 2, `swiftformat` + `swiftlint`.

**Spec:** `docs/superpowers/specs/2026-10-19-v3-3-0-release-design.md` (revision 3). Phase 2 behaviour: `docs/superpowers/specs/2026-10-12-provider-relevance-design.md`.

## Global Constraints

- macOS 13+, Swift 6 strict concurrency, zero new warnings; `swiftformat AIBattery/ AIBatteryApp/ Tests/` + `swiftlint` clean before every push.
- JSONL reads are token-count-only; `response_item` lines are never decoded; no message content is read, stored or logged. `~/.codex` and `~/.claude` are read-only. The only new read of a rollout is its first line, gated by `CodexSessionLogParser.isResponseItem` and `type == "session_meta"`, and only `creator_account_id` is taken from it.
- Cost framing unchanged: "API-equivalent cost" for subscriptions; real bill only when `snapshot.costIsBilled`.
- Headless-CI rules: suites touching AppKit colours are `@MainActor`; never construct `UsageViewModel()` in tests; never touch `SparkleUpdateService.shared`; no dynamic `NSColor` equality off-main.
- Every new persisted field is `decodeIfPresent` with a default; every new model field is `var … = default` trailing the existing ones so memberwise call sites keep compiling.
- Branch `worktree-v3-3-0` (worktree `.claude/worktrees/v3-3-0`), one draft PR for the whole release (stays draft until Kyle says done). Commit per task, `<type>: <description>`, **no Co-Authored-By trailers**.
- Each task that adds user-visible behaviour appends one line under `## [3.3.0] — Unreleased` in `CHANGELOG.md` (create the heading in Task 1).
- README "Test Coverage" table is updated **in the same commit as any test change**; `CLAUDE.md` counts in Task 11.
- Model-ID prefixes: Claude `claude-`, Codex `gpt-`. Vocabulary: Claude "Thinking" / "7-Day"; Codex "Reasoning" / "Weekly".
- Run all tests with `swift test`; one suite with `swift test --filter "<SuiteName>"`.

---

## File Structure

| Action | Path | Responsibility |
|---|---|---|
| Create | `AIBattery/Views/UpdateArrowButton.swift` | The arrow: glyph, breathe, glow, context menu, pure text helpers |
| Modify | `AIBattery/Views/PopoverHeaderView.swift` | Insert arrow; delete banner + badge logic |
| Modify | `AIBattery/Views/OverviewContentView.swift` (`OverviewFooterView`) | Insert arrow; `availableUpdate` replaces `showsUpdateBadge` |
| Modify | `AIBattery/Views/SettingsGearButton.swift` | Delete `showsUpdateBadge` + overlay |
| Modify | `AIBattery/Views/UsagePopoverView.swift` | Pass `availableUpdate` to the footer; delete `gearShowsUpdateBadge` |
| Modify | `AIBattery/ViewModels/UsageViewModel+Refresh.swift`, `AIBattery/Views/Settings/AboutSection.swift` | `withAnimation` around the two `availableUpdate` assignments |
| Modify | `AIBattery/Services/UsageAggregator.swift` | Task 3: `AggregationPass` extraction; Task 7: `attribution`, `AggregateResult`, cache fingerprint |
| Create | `AIBattery/Services/Attribution.swift` | `enum Attribution` + `partition` |
| Modify | `AIBattery/Models/SessionEntry.swift`, `AIBattery/Services/CodexSessionLogParser.swift` | `creatorAccountId` (via re-based Phase 2 Task 1) |
| Modify | `AIBattery/Models/UsageSnapshot.swift` | `unattributedTurnCount` + `==` |
| Modify | `AIBattery/Services/TokenLedger.swift` | `key(accountId:attribution:)`, `merge(_:ledgerKey:)`, prune suffix rule |
| Modify | `AIBattery/Services/AccountStore.swift` | `attribution(for:provider:accounts:)` |
| Modify | `AIBattery/ViewModels/UsageViewModel.swift`, `UsageViewModel+FanOut.swift` | Decide attribution, publish `providerSnapshots`, remove `didSet` mirror, `providerWide:` on the fan-out |
| Modify | `AIBattery/Services/CodexSessionRateLimitScanner.swift` | `creatorAccountId(ofNewestIn:)` + cache |
| Modify | `AIBattery/Services/CodexRateLimitFetcher.swift` | Fallback gating, max age on both paths |
| Modify | `AIBattery/Views/InsightsRowsAndHover.swift`, `AIBattery/Views/InsightsCharts.swift`, `AIBattery/Views/ActivityChartView.swift` | Tooltip `unattributed:`; caption line in every mode |
| Modify | `docs/superpowers/plans/2026-10-12-provider-relevance-plan.md` | Re-base (Task 4) |
| Modify | `spec/*.md`, `README.md`, `CLAUDE.md`, `CHANGELOG.md`, `TODOS.md`, `AIBattery/Info.plist` | Sync + version (Task 11) |
| Tests | `Tests/AIBatteryCoreTests/Views/UpdateArrowButtonTests.swift` (new), `Services/AttributionTests.swift` (new), extend `Services/UsageAggregatorTests.swift`, `Services/CodexSessionLogParserTests.swift`, `Services/TokenLedgerTests.swift`, `Services/AccountStoreProviderTests.swift`, `Services/CodexSessionRateLimitScannerTests.swift`, `Services/CodexRateLimitFetcherTests.swift`, `Models/UsageSnapshotTests.swift`, `Views/InsightsAllTimeCaveatTests.swift` | |

---

### Task 0: Housekeeping (on `main`, no app code)

**Files:** none in the app. Worktrees under `.claude/worktrees/`; the website repo `~/workspace/Github/KyleNesium/aibattery-web`.

- [ ] **Step 1: Bring the main checkout up to date**

```bash
cd ~/workspace/Github/KyleNesium/AIBattery
git status --short          # must be empty
git pull --ff-only origin main
git log --oneline -1        # expect e768fa6 or newer
```

- [ ] **Step 2: Audit every stale worktree over the whole tree**

```bash
cd ~/workspace/Github/KyleNesium/AIBattery
git worktree list
for b in worktree-agent-a75a12ee0f725883c worktree-agent-a7d1d0301fa81620d worktree-agent-a8399f016177de61a worktree-agent-a92e92e360af9de0d worktree-agent-ab144e4dcc00fd118 worktree-agent-ab8106f46382d4dce worktree-sparkle-2-10 fix/dmg-detach-already-unmounted "worktree-/Users/kyle/workspace/Github/KyleNesium"; do
  echo "== $b"; git diff --stat origin/main "$b" | tail -3
done
```

Expected: an empty diff, or only hunks whose content is already on `main` in another form (compare any non-empty one with `git diff origin/main <branch> -- <file>` and `git log -S'<a distinctive line>' origin/main`). **Any diff you cannot account for is reported to Kyle before removal.** Also confirm each worktree's `git -C <path> status --porcelain` is empty.

- [ ] **Step 3: Confirm no session is open on a path, then remove by path**

Ask Kyle which Claude sessions are open. The session that produced this plan was keyed to `review-fixes-2026-10`; that worktree waits until that session has ended. For every other cleared worktree:

```bash
git worktree remove .claude/worktrees/<name>
git branch -D <branch>
```

The mis-named entry is removed by its literal path: `git worktree remove ".claude/worktrees/Users/kyle/workspace/Github/KyleNesium"` then `git branch -D "worktree-/Users/kyle/workspace/Github/KyleNesium"`. Also `git branch -D worktree-review-fixes-2026-10` (orphaned, no worktree). Finish with `git worktree prune && git worktree list` — expect `main`, `v3-3-0`, and `review-fixes-2026-10` if still in use.

- [ ] **Step 4: Sync the website to 3.2.0**

```bash
cd ~/workspace/Github/KyleNesium/aibattery-web && git pull --ff-only
git switch -c chore/sync-3-2-0
npm ci
npm run sync:app
git diff --stat
```

Read `CHANGELOG.md` `## [3.2.0]` in the app repo; if the site's feature copy mentions the 7-Day bar or utilization parsing, update it to the fixed behaviour. Then `npm run build && npm test` (per that repo's README), commit `chore: sync app facts to 3.2.0`, push `-u`, open a PR, and merge it with a **merge commit** (squash bodies carrying `[skip ci]` skip the deploy). Verify `https://aibattery.dev` shows 3.2.0.

---

### Task 1: `UpdateArrowButton` view + pure helpers

**Files:**
- Create: `AIBattery/Views/UpdateArrowButton.swift`
- Test: `Tests/AIBatteryCoreTests/Views/UpdateArrowButtonTests.swift` (new)
- Modify: `CHANGELOG.md` (new `## [3.3.0] — Unreleased` heading above `## [3.2.0]`)

**Interfaces:**
- Produces: `struct UpdateArrowButton: View { init(update: VersionChecker.UpdateInfo) }`; `nonisolated static func helpText(version:) -> String`; `nonisolated static func accessibilityLabel(version:) -> String`; `static let releaseNotesTitle = "Release notes"`, `static let checkForUpdatesTitle = "Check for Updates"`; `nonisolated static func breatheAnimation(reduceMotion: Bool) -> Animation?`.
- Consumes: `VersionChecker.UpdateInfo { version: String; url: String }` (`VersionChecker.swift:9`), `AboutSection.installUpdate(_:)` (`AboutSection.swift:144`), `MotionConstants.breathe` (`Spacing.swift:211`), `ThemeColors.updateAvailable`, `ThemeColors.chevronGlowOpacity`, `ThemeColors.liveDotDimOpacity`, `Layout.glowRadius`, `Layout.accountChipHeight`, `Typography.headerGear`.

- [ ] **Step 1: Write the failing tests**

```swift
import SwiftUI
import Testing
@testable import AIBatteryCore

@Suite("UpdateArrowButton")
struct UpdateArrowButtonTests {
    @Test func helpText_namesTheVersionAndTheAction() {
        #expect(UpdateArrowButton.helpText(version: "3.3.0") == "v3.3.0 available — click to update")
    }

    @Test func accessibilityLabel_namesTheVersion() {
        #expect(UpdateArrowButton.accessibilityLabel(version: "3.3.0") == "Update available, version 3.3.0")
    }

    @Test func menuTitles_areStable() {
        #expect(UpdateArrowButton.releaseNotesTitle == "Release notes")
        #expect(UpdateArrowButton.checkForUpdatesTitle == "Check for Updates")
    }

    /// Reduce Motion stops the breathing; the arrow itself stays.
    @Test func breatheAnimation_isNilUnderReduceMotion() {
        #expect(UpdateArrowButton.breatheAnimation(reduceMotion: true) == nil)
        #expect(UpdateArrowButton.breatheAnimation(reduceMotion: false) != nil)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter "UpdateArrowButton"`
Expected: compile error — `UpdateArrowButton` not found.

- [ ] **Step 3: Implement the view**

Create `AIBattery/Views/UpdateArrowButton.swift`:

```swift
import SwiftUI

/// The one sign that a newer release exists: an arrow beside the gear that breathes in
/// the update colour. It appears only while `UsageViewModel.availableUpdate` is set and
/// replaces both the old header banner and the gear badge. Its visibility comes from
/// GitHub Releases while the click runs a Sparkle check against the appcast, so the two
/// can disagree for a few minutes after a release — the context menu keeps the release
/// page one click away for that case.
///
/// Respects Reduce Motion: the glow stays, the breathing stops (same rule as `LiveDot`).
struct UpdateArrowButton: View {
    let update: VersionChecker.UpdateInfo
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false

    static let releaseNotesTitle = "Release notes"
    static let checkForUpdatesTitle = "Check for Updates"

    nonisolated static func helpText(version: String) -> String {
        "v\(version) available — click to update"
    }

    nonisolated static func accessibilityLabel(version: String) -> String {
        "Update available, version \(version)"
    }

    /// `nil` means "don't animate" — the only honest value under Reduce Motion.
    nonisolated static func breatheAnimation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : MotionConstants.breathe
    }

    var body: some View {
        Button(action: { AboutSection.installUpdate(update) }) {
            Image(systemName: "arrow.up.circle")
                .font(Typography.headerGear)
                .foregroundStyle(ThemeColors.updateAvailable)
                .shadow(color: ThemeColors.updateAvailable.opacity(ThemeColors.chevronGlowOpacity), radius: Layout.glowRadius)
                .opacity(breathing ? ThemeColors.liveDotDimOpacity : 1)
                .frame(width: Layout.accountChipHeight, height: Layout.accountChipHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onAppear {
            guard let animation = Self.breatheAnimation(reduceMotion: reduceMotion) else { return }
            withAnimation(animation) { breathing = true }
        }
        .contextMenu {
            Button(Self.releaseNotesTitle) {
                if let url = URL(string: update.url) {
                    NSWorkspace.shared.open(url)
                }
            }
            Button(Self.checkForUpdatesTitle) {
                AboutSection.installUpdate(update)
            }
        }
        .help(Self.helpText(version: update.version))
        .accessibilityLabel(Self.accessibilityLabel(version: update.version))
        .accessibilityHint("Downloads and installs the update; right-click for release notes")
    }
}
```

`AboutSection.installUpdate` is inside `#if ENABLE_VERSION_CHECKER` (`AboutSection.swift:141`); so is `VersionChecker`. All three SPM targets define the flag (`Package.swift:24,35,46`) and `PopoverHeaderView.swift:12` already references `VersionChecker.UpdateInfo` unguarded, so this file is **not** wrapped (spec §1 "Compile flag note").

- [ ] **Step 4: Run tests**

Run: `swift test --filter "UpdateArrowButton"`
Expected: 4 PASS.

- [ ] **Step 5: Changelog heading, README row, commit**

Insert above `## [3.2.0] — 2026-10-18` in `CHANGELOG.md`:

```markdown
## [3.3.0] — Unreleased

### Added
- **An update arrow instead of a banner.** When a newer release exists, an arrow breathes beside the Settings gear in both the account view and the overview; click it to update, right-click for the release notes. The banner that pushed the whole popover down, and the badge on the gear, are gone.
```

README "Test Coverage": Views row `+4`, total `+4`, and mention "update arrow helpers". Then:

```bash
swiftformat AIBattery/ Tests/ && swiftlint --quiet
git add AIBattery/Views/UpdateArrowButton.swift Tests/AIBatteryCoreTests/Views/UpdateArrowButtonTests.swift CHANGELOG.md README.md
git commit -m "feat: update arrow button beside the gear (view + helpers)"
```

---

### Task 2: Wire the arrow in, remove the banner and the badge

**Files:**
- Modify: `AIBattery/Views/PopoverHeaderView.swift` (`:12-47` body, `:86-97` gear, `:99-152` banner)
- Modify: `AIBattery/Views/OverviewContentView.swift:47-60` (`OverviewFooterView`)
- Modify: `AIBattery/Views/SettingsGearButton.swift:7-47`
- Modify: `AIBattery/Views/UsagePopoverView.swift:225-233`, `:257`
- Modify: `AIBattery/ViewModels/UsageViewModel+Refresh.swift:468-471`, `AIBattery/Views/Settings/AboutSection.swift:157-160`
- Modify: `spec/UI_SPEC.md` (header row, overview footer, banner section removed), `spec/ARCHITECTURE.md` + `spec/CONSTANTS.md` (compile-flag claim)

**Interfaces:**
- Consumes: `UpdateArrowButton(update:)` from Task 1.
- Produces: `OverviewFooterView.availableUpdate: VersionChecker.UpdateInfo?` (replaces `showsUpdateBadge`); `SettingsGearButton` loses `showsUpdateBadge`.

- [ ] **Step 1: Confirm there is nothing to break in tests**

Run: `grep -rn "showsUpdateBadge\|updateBannerDismissed\|gearShowsUpdateBadge" Tests/`
Expected: no output (verified during review). The compile is the test.

- [ ] **Step 2: `SettingsGearButton` — delete the badge**

Replace the struct body so it reads:

```swift
struct SettingsGearButton: View {
    @Binding var showSettings: Bool
    /// Spelled-out label beside the gear. The detail header has a title row to give the
    /// icon context; the overview's footer does not, so there it says "Settings".
    var label: String?
    @State private var hovered = false

    var body: some View {
        Button(action: { withAnimation(MotionConstants.standard) { showSettings.toggle() } }) {
            HStack(spacing: Spacing.inner) {
                Image(systemName: "gearshape")
                    .font(Typography.headerGear)
                    .frame(
                        width: label == nil ? Layout.accountChipHeight : nil,
                        height: Layout.accountChipHeight
                    )
                if let label {
                    Text(label)
                        .font(Typography.caption)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(showSettings || hovered ? .primary : .secondary)
        .onHover { hovered = $0 }
        .help("Settings")
        .accessibilityLabel("Settings")
        .accessibilityHint(showSettings ? "Close settings" : "Open settings")
    }
}
```

- [ ] **Step 3: `PopoverHeaderView` — arrow in, banner out**

Delete `@State private var updateBannerDismissed` (and its `#if`), the `#if ENABLE_VERSION_CHECKER if let update = availableUpdate, !updateBannerDismissed { updateBanner(update) } #endif` block in `body`, `gearShowsUpdateBadge`, and the whole `updateBanner(_:)` function with its `#if`. Change the gear line in `body` to:

```swift
                Spacer(minLength: Spacing.inner)
                if let update = availableUpdate {
                    UpdateArrowButton(update: update)
                        .transition(MotionConstants.expandTransition)
                }
                gearButton
```

and `gearButton` to:

```swift
    private var gearButton: some View {
        SettingsGearButton(showSettings: $showSettings)
    }
```

Update the file's doc comment: "…only the update arrow stays here so an update is discoverable without opening Settings."

- [ ] **Step 4: `OverviewFooterView` — same arrow**

```swift
struct OverviewFooterView: View {
    let lastFreshFetch: Date?
    let isLoading: Bool
    var availableUpdate: VersionChecker.UpdateInfo? = nil
    @Binding var showSettings: Bool
    let onRefresh: () -> Void

    var body: some View {
        HStack(spacing: Spacing.medium) {
            if let update = availableUpdate {
                UpdateArrowButton(update: update)
                    .transition(MotionConstants.expandTransition)
            }
            SettingsGearButton(
                showSettings: $showSettings,
                label: "Settings"
            )
            // … rest unchanged …
```

- [ ] **Step 5: `UsagePopoverView` — pass the update, drop the badge property**

Delete the `gearShowsUpdateBadge` computed property (`:225-233`) and its doc comment. At `:257` replace `showsUpdateBadge: gearShowsUpdateBadge,` with `availableUpdate: viewModel.availableUpdate,`.

- [ ] **Step 6: Animate the appearance**

`UsageViewModel+Refresh.swift:469-470`:

```swift
        if availableUpdate == nil {
            let found = await VersionChecker.shared.checkForUpdate()
            withAnimation(MotionConstants.standard) { availableUpdate = found }
        }
```

`AboutSection.swift:160` (`viewModel.availableUpdate = result`) becomes `withAnimation(MotionConstants.standard) { viewModel.availableUpdate = result }`.

- [ ] **Step 7: Build, run the full suite, smoke-test**

```bash
swift build 2>&1 | grep -E "error|warning: unused" ; swift test 2>&1 | tail -3
./scripts/build-app.sh && open .build/AIBattery.app
```

(Keychain prompt on an ad-hoc rebuild → "Always Allow".) To see the arrow without a real release: Settings → About → the version line; temporarily set `aibattery` defaults? No — simplest: in the running build, open Settings → About → "Check for Updates" with the installed 3.2.0 and a published 3.2.0 shows "Up to date"; the arrow is exercised by the tests and by the next release. Verify instead that both header and footer render without the banner and the gear has no badge. Relaunch `/Applications/AIBattery.app` afterwards.

- [ ] **Step 8: Docs + commit**

`spec/UI_SPEC.md`: header row = `[back?] [chip] … [arrow?] [gear]`; overview footer = `[arrow?] [⚙ Settings] … [↻ elapsed] … [⊗ Quit]`; delete the "update banner" subsection; document the context menu and breathe. `spec/ARCHITECTURE.md:339,396` and `spec/CONSTANTS.md:645-652`: replace "remove the define for an App Store build" with "always defined by all three targets; view-side references are unguarded, so removing the define does not compile — kept for the service files' `#if` only".

```bash
swiftformat AIBattery/ Tests/ && swiftlint --quiet
git add -A AIBattery/Views AIBattery/ViewModels/UsageViewModel+Refresh.swift spec/
git commit -m "feat: show the update arrow in the header and overview; remove the banner and gear badge"
```

---

### Task 3: Extract `AggregationPass` from `UsageAggregator.aggregate` (zero behaviour change)

**Files:**
- Modify: `AIBattery/Services/UsageAggregator.swift:131-535`
- Test: existing `Tests/AIBatteryCoreTests/Services/UsageAggregatorTests.swift` (43), `UsageAggregatorIntegrationTests.swift`, `UsageAggregatorRealDataTests.swift` (opt-in) — **no test changes**

**Interfaces:**
- Produces (private to the file, used by Task 7): `private struct AggregationPass { init(provider:now:cachedDates:); mutating func add(_ entry: AssistantUsageEntry); func finish(entries:statsCache:…) -> (snapshot: UsageSnapshot, observedModels: [String]) }`.
- `aggregate(...)`'s signature and every output are unchanged.

- [ ] **Step 1: Record the baseline**

```bash
swift test --filter "UsageAggregator" 2>&1 | tail -2
AIBATTERY_REAL_CLAUDE_LOGS=1 AIBATTERY_REAL_CODEX_LOGS=1 swift test --filter "UsageAggregatorRealData" 2>&1 | grep -iE "ms|pass|fail" | tail -5
```

Note the timing lines; they go in the commit message.

- [ ] **Step 2: Move the per-pass state and the loop body into a struct**

Inside `final class UsageAggregator`, below `ProjectAccum`, add:

```swift
    /// One accumulation over a sorted entry stream, plus the assembly of its snapshot.
    ///
    /// Extracted from `aggregate` so that a second instance can run beside the first
    /// (per-account attribution, Task 7): the entries are read once and walked once; each
    /// instance only pays for its own accumulators.
    ///
    ///     entries ──► pass.add(entry) ×N ──► pass.finish(entries:…) ──► UsageSnapshot
    ///
    private struct AggregationPass {
        let provider: AIProvider
        let now: Date
        let calendar: Calendar
        let today: Date
        let todayDate: String
        let fiveHoursAgo: Date
        let twentyFourHoursAgo: Date
        let sevenDayRateLimitCutoff: Date
        let sevenDaysAgo: Date
        let twelveMonthsAgo: Date
        let cachedDates: Set<String>

        var todayEntries: [AssistantUsageEntry] = []
        var trailing24hEntries: [AssistantUsageEntry] = []
        var fiveHourTokens = 0
        var sevenDayTokens = 0
        var fiveHourTokenBuckets: [Int: Int] = [:]
        var dailyTokenTotals: [String: Int] = [:]
        var entriesByDate: [String: (messages: Int, sessions: Set<String>)] = [:]
        var uncachedModelTokensMap: TokenMap = [:]
        var allJsonlModelTokensMap: TokenMap = [:]
        var jsonlTodayToolCalls = 0
        var projectMap: [String: ProjectAccum] = [:]
        var lastSeenByModel: [String: Date] = [:]
        var todayTokenMap: TokenMap = [:]
        var weekTokenMap: TokenMap = [:]
        var monthTokenMap: TokenMap = [:]
        private var lastDayStart: Date = .distantPast
        private var lastDayEnd: Date = .distantPast
        private var lastDateKey = ""

        init(provider: AIProvider, now: Date, cachedDates: Set<String>) {
            self.provider = provider
            self.now = now
            self.cachedDates = cachedDates
            let calendar = Calendar.current
            self.calendar = calendar
            today = calendar.startOfDay(for: now)
            todayDate = UsageAggregator.dateFormatter.string(from: now)
            fiveHoursAgo = now.addingTimeInterval(-UsageAggregator.fiveHourWindow)
            twentyFourHoursAgo = now.addingTimeInterval(-UsageAggregator.twentyFourHourWindow)
            sevenDayRateLimitCutoff = now.addingTimeInterval(-UsageAggregator.sevenDayWindow)
            sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: today) ?? today
            twelveMonthsAgo = calendar.date(byAdding: .month, value: -12, to: today) ?? today
        }

        mutating func add(_ entry: AssistantUsageEntry) {
            // ← the body of `for entry in allEntries { … }` from aggregate, verbatim,
            //   with `Self.accumulate` → `UsageAggregator.accumulate`,
            //   `Self.isTrackedModel` → `UsageAggregator.isTrackedModel`,
            //   `Self.fiveHourBucketCount` etc. → `UsageAggregator.…`.
        }

        /// Everything after the loop: observed models, project/model summaries, ledger
        /// merge, health, activity merge, hour counts, and the snapshot itself.
        func finish(
            entries: [AssistantUsageEntry],
            statsCache: StatsCache?,
            rateLimits: RateLimitUsage?,
            rateLimitSource: RateLimitSource?,
            standardLimits: StandardRateLimits?,
            rateLimitsFresh: Bool,
            idleSessionMinutes: Int,
            ledger: TokenLedger,
            accountId: String?
        ) -> (snapshot: UsageSnapshot, observedModels: [String]) {
            // ← lines from `let observedModels = …` through `let snapshot = UsageSnapshot(…)`,
            //   verbatim, with `allEntries` → `entries`, `Self.` → `UsageAggregator.`.
            return (snapshot, observedModels)
        }
    }
```

Move the code exactly as the two arrows say (the `// ←` comments are instructions for you, not code to leave behind). `StatsCache` is whatever `statsCacheReader?.read()` returns — use that type name. `TokenMap` and `ProjectAccum` are already file-private to the class; mark `TokenMap` `fileprivate typealias` if the nested struct cannot see it. `dateFormatter`, `fiveHourWindow`, `sevenDayWindow`, `twentyFourHourWindow`, `fiveHourBucketCount`, `bucketDuration` are `private static` on the class — the nested struct can reach them as `UsageAggregator.x`.

- [ ] **Step 3: Rewrite `aggregate` to use it**

After the cache check and `let allEntries = sessionLogReader.readAllUsageEntries()`:

```swift
        let cachedDates = Set(statsCache?.dailyModelTokens.map(\.date) ?? [])
        var pass = AggregationPass(provider: provider, now: now, cachedDates: cachedDates)
        for entry in allEntries {
            pass.add(entry)
        }
        let (snapshot, observedModels) = pass.finish(
            entries: allEntries, statsCache: statsCache, rateLimits: rateLimits,
            rateLimitSource: rateLimitSource, standardLimits: standardLimits,
            rateLimitsFresh: rateLimitsFresh, idleSessionMinutes: idleSessionMinutes,
            ledger: ledger, accountId: accountId
        )

        let effects = SideEffects(
            activeUserModel: allEntries.last?.model,
            observedModels: observedModels,
            accountId: accountId,
            provider: provider
        )
        // … cache store unchanged …
        return (snapshot, effects)
```

- [ ] **Step 4: Verify zero behaviour change**

```bash
swift build 2>&1 | grep -E "error|warning" ; swift test 2>&1 | tail -3
AIBATTERY_REAL_CLAUDE_LOGS=1 AIBATTERY_REAL_CODEX_LOGS=1 swift test --filter "UsageAggregatorRealData" 2>&1 | grep -iE "ms|pass|fail" | tail -5
```

Expected: every test green, **no test file touched**, timing within noise of Step 1. If `UsageAggregator.swift` now exceeds 800 lines, move `AggregationPass` to `AIBattery/Services/UsageAggregator+Pass.swift` as `extension UsageAggregator { struct AggregationPass … }` with `fileprivate` → `internal` on the helpers it needs; keep it in one file otherwise.

- [ ] **Step 5: Commit**

```bash
swiftformat AIBattery/ && swiftlint --quiet
git add AIBattery/Services/
git commit -m "refactor: extract AggregationPass from UsageAggregator.aggregate (no behaviour change)

Baseline vs after (opt-in real-data timing): <paste the two lines>"
```

---

### Task 4: Re-base the Phase 2 plan, then execute it

**Files:**
- Modify: `docs/superpowers/plans/2026-10-12-provider-relevance-plan.md`
- Modify: `docs/superpowers/specs/2026-10-19-v3-3-0-release-design.md` §2 (one wrong name, see Step 1.g)

**Interfaces:**
- Produces (after execution): everything in that plan's "Interfaces" blocks, plus `AssistantUsageEntry.creatorAccountId: String?` from the re-based Task 1, `TokenLedger.merge(_:ledgerKey:)`-compatible `ModelTokenRecord.reasoning`, `firstScan` keyed by ledger key, `InsightsView.allTimeTooltip(for:since:)`, `InsightsView.sinceCaption(provider:since:unattributed:now:)`.

- [ ] **Step 1: Edit the plan file (docs only)**

Make these edits with the Edit tool; each is a find-and-replace on the plan:

a. Header `**Spec:**` paragraph: replace "Executed as Phase 2 of `2026-10-12-v3-1-0-release-plan.md` — the umbrella plan owns the branch…" with "Executed as Task 4 of `2026-10-19-v3-3-0-release-plan.md`, which owns the branch (`worktree-v3-3-0`), the changelog heading (`## [3.3.0] — Unreleased`), the counts and the PR."

b. Global Constraints: `worktree-v3-1-0` → `worktree-v3-3-0`; `## [3.1.0] — Unreleased` → `## [3.3.0] — Unreleased`; add the line "New model fields are `var … = default` trailing the existing ones (every task)."

c. File Structure table: `AIBattery/Models/RateLimitUsage.swift:41-70, 431-640` → `AIBattery/Models/RateLimitUsage.swift` (`modelWindows` field) **and** `AIBattery/Models/RateLimitUsage+Parsing.swift` (parse); drop the `OtherAccountsStrip.swift` and `UsagePopoverView.swift:128-156` rows (superseded); `Views/InsightsAllTimeTooltipTests.swift` → `Views/InsightsAllTimeCaveatTests.swift` (exists; append). Add a note under the table: "Line numbers in this plan predate v3.2.0; locate every anchor by symbol."

d. **Task 0, Steps 1–2** replaced by:

```markdown
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
```

e. Task 1 "Interfaces → Produces on `AssistantUsageEntry`": append `, var creatorAccountId: String? = nil` and this sentence: "Codex fills it from `session_meta.payload.creator_account_id` (non-empty string; every `session_meta` line is applied, so a later one wins for later entries); Claude leaves it nil." Add to Task 1 Step 1 a fixture and test:

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

and in Task 1 Step 3's parser implementation: a `private(set) var creatorAccountId: String?` next to `cwd`; in `applySessionMeta`: `if let account = payload["creator_account_id"] as? String, !account.isEmpty { creatorAccountId = account }`; in `makeEntry`'s `AssistantUsageEntry(…)` add `creatorAccountId: creatorAccountId` after the three Phase 2 fields. `SessionLogReader.makeUsageEntry` passes nothing (defaults to nil).

f. Task 2 and Task 9 ledger text: wherever they say `merge(…, accountId: "acc")` / `firstScanDate(accountId:)` / `firstScan[accountId]`, write `ledgerKey:` instead and add the sentence "The key is whatever the aggregator passes (`TokenLedger.key(accountId:attribution:)`, v3.3.0 plan Task 6) — for every existing user it is the account id." (Task 6 of this plan lands before Task 9 runs only if you execute Phase 2 after Task 6; **execution order inside Phase 2 is unchanged, and Task 6 here must land before Phase 2 Task 2** — see Step 2 below.)

g. Task 9: `ActivityChartView.sinceCaption(provider:since:now:)` → `InsightsView.sinceCaption(provider:since:unattributed:now:)` defined in `AIBattery/Views/InsightsCharts.swift` (an `extension InsightsView`); it returns the one caption line for **every** chart mode: `"since 12 Oct 2026"`, `"N turns from older Codex CLI versions not shown"`, both joined with `" · "`, or nil. Render it in `ActivityChartView.swift` right after the `switch mode { … }` that picks the chart (`:58-66`), regardless of mode, when non-nil. Test file: append to `Tests/AIBatteryCoreTests/Views/InsightsAllTimeCaveatTests.swift` instead of creating a new one; the `since` cases of the test block stay, the `unattributed` cases are added by Task 10 of this plan. Keep `InsightsView.allTimeTooltip(for:since:)` — that name is right (the function lives in `InsightsRowsAndHover.swift` as an `extension InsightsView`). Fix the v3.3.0 spec §2 bullet that calls it `InsightsRowsAndHover.allTimeTooltip` to say `InsightsView.allTimeTooltip` (defined in `InsightsRowsAndHover.swift`).

h. "Self-review against the spec" and "Names used across tasks": update the names changed above.

- [ ] **Step 2: Commit the re-base**

```bash
git add docs/superpowers/plans/2026-10-12-provider-relevance-plan.md docs/superpowers/specs/2026-10-19-v3-3-0-release-design.md
git commit -m "docs: re-base the Phase 2 plan onto v3.2.0 (Task 0 capture method, creatorAccountId, ledger keys, caption home)"
```

- [ ] **Step 3: Execute Task 6 of this plan (ledger keys) BEFORE Phase 2 Task 2**, because Phase 2 Tasks 2 and 9 write ledger records and tests through `merge(_:ledgerKey:)`. Order: Phase 2 Task 0 → Task 1 → **this plan's Task 5 and Task 6** → Phase 2 Tasks 2, 3, 4, 5, (6 if Task 0 said present), 8, 9 → Phase 2 Task 11 (its spec sync) → this plan's Tasks 7–11.

- [ ] **Step 4: Execute the re-based Phase 2 plan** with superpowers:subagent-driven-development, one task per subagent, each reading both specs and the re-based plan. Each Phase 2 task commits on `worktree-v3-3-0`.

---

### Task 5: `Attribution` + `partition`

**Files:**
- Create: `AIBattery/Services/Attribution.swift`
- Test: `Tests/AIBatteryCoreTests/Services/AttributionTests.swift` (new)

**Interfaces:**
- Consumes: `AssistantUsageEntry.creatorAccountId` (Task 4 / Phase 2 Task 1).
- Produces: `enum Attribution: Hashable, Sendable { case all; case account(String) }`; `func partition(_ entries: [AssistantUsageEntry]) -> (kept: [AssistantUsageEntry], unattributed: Int)`; `var isAttributed: Bool`.

- [ ] **Step 1: Failing tests**

```swift
import Foundation
import Testing
@testable import AIBatteryCore

@Suite("Attribution")
struct AttributionTests {
    private func entry(_ account: String?, ts: TimeInterval) -> AssistantUsageEntry {
        AssistantUsageEntry(
            timestamp: Date(timeIntervalSince1970: ts), model: "gpt-6-astra", messageId: UUID().uuidString,
            inputTokens: 1, outputTokens: 1, cacheReadTokens: 0, cacheWriteTokens: 0,
            sessionId: "s", cwd: "/p", gitBranch: nil, toolCallCount: 0, creatorAccountId: account
        )
    }

    @Test func all_returnsInputUntouched() {
        let entries = [entry("a", ts: 1), entry(nil, ts: 2), entry("b", ts: 3)]
        let (kept, unattributed) = Attribution.all.partition(entries)
        #expect(kept.map(\.messageId) == entries.map(\.messageId))
        #expect(unattributed == 0)
        #expect(!Attribution.all.isAttributed)
    }

    @Test func account_keepsOwn_countsNil_dropsForeignUncounted_preservesOrder() {
        let entries = [entry("a", ts: 1), entry(nil, ts: 2), entry("b", ts: 3), entry("a", ts: 4), entry(nil, ts: 5)]
        let (kept, unattributed) = Attribution.account("a").partition(entries)
        #expect(kept.map(\.timestamp.timeIntervalSince1970) == [1, 4])
        #expect(unattributed == 2)
        #expect(Attribution.account("a").isAttributed)
    }

    @Test func account_onEmptyInput() {
        let (kept, unattributed) = Attribution.account("a").partition([])
        #expect(kept.isEmpty && unattributed == 0)
    }
}
```

- [ ] **Step 2: Run** — `swift test --filter "Attribution"` → compile error.

- [ ] **Step 3: Implement**

```swift
import Foundation

/// Which Codex account's turns an aggregation counts.
///
/// `.all` is every entry on disk — the only mode for Claude, for API-key accounts and
/// for setups with at most one ChatGPT-backed Codex account. `.account(id)` keeps the
/// entries whose rollout `session_meta` was stamped with that ChatGPT account id
/// (current Codex CLI versions write it; older rollouts carry no stamp).
///
///     entries ─┬─ stamped id      → kept
///              ├─ no stamp (old)  → dropped, counted as unattributed
///              └─ other account   → dropped, uncounted
enum Attribution: Hashable, Sendable {
    case all
    case account(String)

    var isAttributed: Bool {
        if case .account = self { return true }
        return false
    }

    /// Under `.all` the input is returned untouched (no copy). The kept array keeps the
    /// reader's ascending timestamp order, which every consumer relies on.
    func partition(_ entries: [AssistantUsageEntry]) -> (kept: [AssistantUsageEntry], unattributed: Int) {
        guard case let .account(id) = self else { return (entries, 0) }
        var kept: [AssistantUsageEntry] = []
        kept.reserveCapacity(entries.count)
        var unattributed = 0
        for entry in entries {
            switch entry.creatorAccountId {
            case let .some(stamp) where stamp == id: kept.append(entry)
            case .none: unattributed += 1
            default: break
            }
        }
        return (kept, unattributed)
    }
}
```

- [ ] **Step 4: Run** — `swift test --filter "Attribution"` → 3 PASS. README Services row `+3`.

- [ ] **Step 5: Commit**

```bash
swiftformat AIBattery/ Tests/ && swiftlint --quiet
git add AIBattery/Services/Attribution.swift Tests/AIBatteryCoreTests/Services/AttributionTests.swift README.md
git commit -m "feat: Attribution enum with entry partition for per-account Codex data"
```

---

### Task 6: Ledger keys by attribution

**Files:**
- Modify: `AIBattery/Services/TokenLedger.swift:42-100` (`merge`), `:142-152` (`pruneAccounts`), new `key(…)`
- Modify: `AIBattery/Services/UsageAggregator.swift` (the one `ledger.merge(rawModelTokens, accountId: accountId)` call → `ledgerKey:`; attribution is still `.all` here until Task 7)
- Test: `Tests/AIBatteryCoreTests/Services/TokenLedgerTests.swift` (existing `accountId:` calls → `ledgerKey:`; new tests)

**Interfaces:**
- Produces: `nonisolated static func key(accountId: String, attribution: Attribution) -> String`; `static let providerWideCodexKey = "codex#all"`; `static let attributedSuffix = "#attributed"`; `func merge(_ tokens: [ModelTokenSummary], ledgerKey: String) -> [ModelTokenSummary]`; `nonisolated static func baseAccountId(ofKey key: String) -> String`.
- Consumes: `Attribution` (Task 5).

- [ ] **Step 1: Failing tests** (append to `TokenLedgerTests`)

```swift
    @Test func key_plainForUnattributed_namespacedForAttributed() {
        #expect(TokenLedger.key(accountId: "acc", attribution: .all) == "acc")
        #expect(TokenLedger.key(accountId: "acc", attribution: .account("acc")) == "acc#attributed")
        #expect(TokenLedger.key(accountId: "acc", attribution: .account("other")) == "acc#attributed")
        #expect(TokenLedger.baseAccountId(ofKey: "acc#attributed") == "acc")
        #expect(TokenLedger.baseAccountId(ofKey: "codex#all") == "codex")
        #expect(TokenLedger.baseAccountId(ofKey: "acc") == "acc")
    }

    @Test func merge_keepsSeparateSeriesPerKey() {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let ledger = TokenLedger(fileURL: url)
        _ = ledger.merge([makeToken(id: "gpt-6-astra", output: 100)], ledgerKey: "acc")
        _ = ledger.merge([makeToken(id: "gpt-6-astra", output: 10)], ledgerKey: "acc#attributed")
        _ = ledger.merge([makeToken(id: "gpt-6-astra", output: 70)], ledgerKey: TokenLedger.providerWideCodexKey)
        #expect(ledger.merge([makeToken(id: "gpt-6-astra")], ledgerKey: "acc").first?.outputTokens == 100)
        #expect(ledger.merge([makeToken(id: "gpt-6-astra")], ledgerKey: "acc#attributed").first?.outputTokens == 10)
        #expect(ledger.merge([makeToken(id: "gpt-6-astra")], ledgerKey: "codex#all").first?.outputTokens == 70)
        ledger.flushForTesting()
        let reloaded = TokenLedger(fileURL: url)
        #expect(reloaded.merge([makeToken(id: "gpt-6-astra")], ledgerKey: "acc#attributed").first?.outputTokens == 10)
    }

    @Test func prune_keepsNamespacedKeysOfLiveAccounts_andProviderWideWhileAnyCodexLives() {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let ledger = TokenLedger(fileURL: url)
        for key in ["live", "live#attributed", "dead", "dead#attributed", "codex#all"] {
            _ = ledger.merge([makeToken(id: "gpt-6-astra", output: 1)], ledgerKey: key)
        }
        ledger.pruneAccounts(keeping: ["live"], hasLiveCodexAccount: true)
        ledger.flushForTesting()
        let keys = Set(TokenLedger(fileURL: url).ledgerKeysForTesting())
        #expect(keys == ["live", "live#attributed", "codex#all"])
        ledger.pruneAccounts(keeping: ["live"], hasLiveCodexAccount: false)
        ledger.flushForTesting()
        #expect(Set(TokenLedger(fileURL: url).ledgerKeysForTesting()) == ["live", "live#attributed"])
    }
```

Update every existing `merge(…, accountId:` in the suite to `ledgerKey:` (same strings). Note the existing `pruneAccounts(keeping:)` callers in tests get the new `hasLiveCodexAccount:` argument (default `true` keeps `codex#all`).

- [ ] **Step 2: Run** — `swift test --filter "TokenLedger"` → compile errors.

- [ ] **Step 3: Implement**

In `TokenLedger`:

```swift
    // MARK: - Keys

    /// Suffix of the per-account series kept while attribution is active.
    static let attributedSuffix = "#attributed"
    /// The provider-wide Codex series kept while attribution is active. The plain
    /// account-id key stays what every single-account user has today.
    static let providerWideCodexKey = "codex#all"

    /// Which series an aggregation writes to.
    ///
    ///     .all                 → "<accountId>"            (unchanged for every existing user)
    ///     .account(_)          → "<accountId>#attributed" (fresh series on first attributed scan)
    ///     provider-wide pass   → providerWideCodexKey      (Task 7 passes it explicitly)
    nonisolated static func key(accountId: String, attribution: Attribution) -> String {
        attribution.isAttributed ? accountId + attributedSuffix : accountId
    }

    /// `"acc#attributed"` → `"acc"`, `"codex#all"` → `"codex"`, `"acc"` → `"acc"`.
    nonisolated static func baseAccountId(ofKey key: String) -> String {
        guard let hash = key.firstIndex(of: "#") else { return key }
        return String(key[..<hash])
    }
```

Rename `merge(_ tokens:accountId:)` → `merge(_ tokens:ledgerKey:)` (body: `accountId` → `ledgerKey`). `pruneAccounts`:

```swift
    func pruneAccounts(keeping liveAccountIds: Set<String>, hasLiveCodexAccount: Bool = true) {
        guard !liveAccountIds.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        let before = ledger.accounts.count
        ledger.accounts = ledger.accounts.filter { key, _ in
            if key == Self.providerWideCodexKey { return hasLiveCodexAccount }
            return liveAccountIds.contains(Self.baseAccountId(ofKey: key))
        }
        if ledger.accounts.count != before {
            isDirty = true
            save()
        }
    }

    func ledgerKeysForTesting() -> [String] {
        lock.lock(); defer { lock.unlock() }
        return Array(ledger.accounts.keys)
    }
```

Find the production `pruneAccounts(keeping:)` caller (`grep -rn "pruneAccounts(keeping" AIBattery`) and pass `hasLiveCodexAccount: accounts.contains { $0.provider == .codex }`. `UsageAggregator`: `ledger.merge(rawModelTokens, ledgerKey: accountId)` (Task 7 replaces this with the real key). When Phase 2 Task 9's `firstScan` exists, it is keyed by the same `ledgerKey` and pruned by the same rule.

- [ ] **Step 4: Run** — `swift test --filter "TokenLedger|UsageAggregator"` → PASS. README Services row `+3`.

- [ ] **Step 5: Commit**

```bash
swiftformat AIBattery/ Tests/ && swiftlint --quiet
git add AIBattery/Services/TokenLedger.swift AIBattery/Services/UsageAggregator.swift Tests/AIBatteryCoreTests/Services/TokenLedgerTests.swift README.md
git commit -m "feat: ledger series keyed by attribution (plain, #attributed, codex#all)"
```

---

### Task 7: One pass, two snapshots

**Files:**
- Modify: `AIBattery/Services/UsageAggregator.swift` (`aggregate`, cache fingerprint)
- Modify: `AIBattery/Models/UsageSnapshot.swift` (`var unattributedTurnCount: Int = 0` after `costIsBilled`; `==` at `:6-47`)
- Test: `Tests/AIBatteryCoreTests/Services/UsageAggregatorTests.swift`, `Tests/AIBatteryCoreTests/Models/UsageSnapshotTests.swift`

**Interfaces:**
- Produces: `struct UsageAggregator.AggregateResult { var detail: UsageSnapshot; var providerWide: UsageSnapshot; let effects: SideEffects }`; `func aggregate(rateLimits:rateLimitSource:standardLimits:accountId:rateLimitsFresh:attribution:now:) -> AggregateResult`; `UsageSnapshot.unattributedTurnCount`.
- Consumes: `AggregationPass` (Task 3), `Attribution.partition` (Task 5), `TokenLedger.key` / `providerWideCodexKey` (Task 6).

- [ ] **Step 1: Failing tests**

`UsageSnapshotTests` (use the suite's `makeSnapshot` and copy-with-var):

```swift
    @Test func equality_includesUnattributedTurnCount() {
        var a = makeSnapshot()
        var b = makeSnapshot()
        a.unattributedTurnCount = 0
        b.unattributedTurnCount = 3
        #expect(a != b)
        b.unattributedTurnCount = 0
        #expect(a == b)
    }
```

`UsageAggregatorTests` (uses the suite's `StubEntrySource` and `makeEntry`; extend `makeEntry` with `account: String? = nil` passed as `creatorAccountId:`):

```swift
    private func codexAggregator(_ entries: [AssistantUsageEntry]) -> (UsageAggregator, URL) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ledger-\(UUID().uuidString).json")
        let agg = UsageAggregator(statsCacheReader: nil, sessionLogReader: StubEntrySource(entries), ledger: TokenLedger(fileURL: url), provider: .codex)
        return (agg, url)
    }

    @Test func attribution_all_isByteIdenticalToUnattributedAggregate() {
        let now = Date()
        let entries = [makeEntry(model: "gpt-6-astra", timestamp: now.addingTimeInterval(-60), account: "a"),
                       makeEntry(model: "gpt-6-astra", timestamp: now.addingTimeInterval(-30), account: nil)]
        let (agg, url) = codexAggregator(entries)
        defer { try? FileManager.default.removeItem(at: url) }
        let plain = agg.aggregate(rateLimits: nil, accountId: "a", now: now)
        let all = agg.aggregate(rateLimits: nil, accountId: "a", attribution: .all, now: now)
        #expect(plain.detail == all.detail)
        #expect(all.detail == all.providerWide)
        #expect(all.detail.unattributedTurnCount == 0)
    }

    @Test func attribution_account_filtersEveryAccumulator_andKeepsProviderWide() {
        let now = Date()
        let mine = makeEntry(model: "gpt-6-astra", sessionId: "mine", timestamp: now.addingTimeInterval(-120), output: 10, account: "a")
        let old = makeEntry(model: "gpt-6-astra", sessionId: "old", timestamp: now.addingTimeInterval(-90), output: 20, account: nil)
        let theirs = makeEntry(model: "gpt-6-astra", sessionId: "theirs", timestamp: now.addingTimeInterval(-60), output: 40, account: "b")
        let (agg, url) = codexAggregator([mine, old, theirs])
        defer { try? FileManager.default.removeItem(at: url) }
        let result = agg.aggregate(rateLimits: nil, accountId: "a", attribution: .account("a"), now: now)

        // detail: only "mine"
        #expect(result.detail.unattributedTurnCount == 1)
        #expect(result.detail.todayModelTokens.first?.outputTokens == 10)
        #expect(result.detail.weekModelTokens.first?.outputTokens == 10)
        #expect(result.detail.monthModelTokens.first?.outputTokens == 10)
        #expect(result.detail.modelTokens.first?.outputTokens == 10)
        #expect(result.detail.projectTokens.first?.outputTokens == 10)
        #expect(result.detail.firstSessionDate == mine.timestamp)
        #expect(result.detail.tokenHealth?.id == "mine")
        #expect(result.detail.topSessionHealths.map(\.id) == ["mine"])
        #expect(result.detail.dailyTokenTotals.values.reduce(0, +) == mine.inputTokens + 10)
        #expect(result.effects.activeUserModel == "gpt-6-astra")

        // provider-wide: everything, no count
        #expect(result.providerWide.unattributedTurnCount == 0)
        #expect(result.providerWide.todayModelTokens.first?.outputTokens == 70)
        #expect(result.providerWide.topSessionHealths.count == 3)
    }

    @Test func attribution_account_usesNamespacedLedgerKeys() {
        let now = Date()
        let (agg, url) = codexAggregator([makeEntry(model: "gpt-6-astra", timestamp: now, output: 5, account: "a")])
        defer { try? FileManager.default.removeItem(at: url) }
        _ = agg.aggregate(rateLimits: nil, accountId: "a", attribution: .account("a"), now: now)
        let ledger = TokenLedger(fileURL: url)
        // flush happened inside merge; reload sees both series
        let keys = Set(ledger.ledgerKeysForTesting())
        #expect(keys.contains("a#attributed") && keys.contains(TokenLedger.providerWideCodexKey) && !keys.contains("a"))
    }

    @Test func cache_missesWhenAttributionChanges_hitsWhenSame() {
        let now = Date()
        let (agg, url) = codexAggregator([makeEntry(model: "gpt-6-astra", timestamp: now, account: "a")])
        defer { try? FileManager.default.removeItem(at: url) }
        let first = agg.aggregate(rateLimits: nil, accountId: "a", attribution: .account("a"), now: now)
        let again = agg.aggregate(rateLimits: nil, accountId: "a", attribution: .account("a"), now: now)
        #expect(first.detail.lastUpdated == again.detail.lastUpdated) // served from cache
        let other = agg.aggregate(rateLimits: nil, accountId: "a", attribution: .all, now: now.addingTimeInterval(1))
        #expect(other.detail.unattributedTurnCount == 0)
    }
```

(The ledger `save()` is async; the key test reads after `merge` returned — call `TokenLedger(fileURL:)`'s `flushForTesting()` on the aggregator's ledger if the reload races: keep a reference to the ledger you passed in and call `ledger.flushForTesting()` before reloading.)

- [ ] **Step 2: Run** — `swift test --filter "UsageAggregator|UsageSnapshot"` → compile errors.

- [ ] **Step 3: Implement**

`UsageSnapshot.swift`: after `var costIsBilled: Bool = false` add

```swift
    /// Turns hidden from this snapshot because their rollout carries no account stamp
    /// (older Codex CLI versions) while per-account attribution is active. 0 otherwise.
    var unattributedTurnCount: Int = 0
```

and `&& lhs.unattributedTurnCount == rhs.unattributedTurnCount` in `==`.

`UsageAggregator.swift`:

```swift
    struct AggregateResult {
        /// What the active account's popover shows (attributed when attribution is active).
        var detail: UsageSnapshot
        /// What the overview cards show for the provider: every entry on disk. Equal to
        /// `detail` when attribution is `.all`.
        var providerWide: UsageSnapshot
        let effects: SideEffects
    }
```

Add `private var lastAttribution: Attribution = .all` and `private var cachedResult: AggregateResult?` (replacing `cachedSnapshot` + `cachedEffects`). `aggregate` gains `attribution: Attribution = .all` after `rateLimitsFresh`, adds `attribution == lastAttribution` to the fingerprint, returns `AggregateResult`. After the read:

```swift
        let (kept, unattributed) = attribution.partition(allEntries)
        let cachedDates = Set(statsCache?.dailyModelTokens.map(\.date) ?? [])
        var all = AggregationPass(provider: provider, now: now, cachedDates: cachedDates)
        var mine: AggregationPass? = attribution.isAttributed ? AggregationPass(provider: provider, now: now, cachedDates: cachedDates) : nil

        if mine != nil {
            // One walk, two accumulators: the kept array is a subsequence of allEntries in
            // the same order, so advance through it alongside.
            var keptIndex = kept.startIndex
            for entry in allEntries {
                all.add(entry)
                if keptIndex < kept.endIndex, kept[keptIndex].messageId == entry.messageId {
                    mine!.add(entry)
                    keptIndex += 1
                }
            }
        } else {
            for entry in allEntries { all.add(entry) }
        }

        let providerKey: String? = accountId.map { id in
            attribution.isAttributed ? TokenLedger.providerWideCodexKey : TokenLedger.key(accountId: id, attribution: .all)
        }
        let (providerWide, observedAll) = all.finish(entries: allEntries, …, ledgerKey: providerKey)
        var detail = providerWide
        var observed = observedAll
        var activeModel = allEntries.last?.model
        if let mine {
            let detailKey = accountId.map { TokenLedger.key(accountId: $0, attribution: attribution) }
            let (d, o) = mine.finish(entries: kept, …, ledgerKey: detailKey)
            detail = d
            detail.unattributedTurnCount = unattributed
            observed = o
            activeModel = kept.last?.model
        }
        let effects = SideEffects(activeUserModel: activeModel, observedModels: observed, accountId: accountId, provider: provider)
        let result = AggregateResult(detail: detail, providerWide: providerWide, effects: effects)
        // cache store: cachedResult = result; lastAttribution = attribution; … (rest unchanged)
        return result
```

`AggregationPass.finish` takes `ledgerKey: String?` instead of `accountId:` and calls `ledger.merge(rawModelTokens, ledgerKey: key)` when non-nil. Message ids are unique per entry (the readers dedupe on them), which is what the two-cursor walk relies on; add that sentence as a comment.

Update the one production caller (`UsageViewModel.aggregateOffMain`, `UsageViewModel.swift:270-279`) minimally for now so it compiles: `var result = await task.value; result.detail.costIsBilled = …; … return result.detail` — Task 8 does the real wiring.

- [ ] **Step 4: Run** — `swift test` → all PASS (the existing aggregator tests use `.aggregate(...)`'s tuple destructuring `let (snapshot, effects) = …` in places — change those to `.detail` / `.effects`). README Services `+4`, Models `+1`.

- [ ] **Step 5: Commit**

```bash
swiftformat AIBattery/ Tests/ && swiftlint --quiet
git add AIBattery/Services/UsageAggregator.swift AIBattery/Models/UsageSnapshot.swift AIBattery/ViewModels/UsageViewModel.swift Tests/ README.md
git commit -m "feat: aggregate once into a per-account detail snapshot and a provider-wide one"
```

---

### Task 8: Decide attribution in `aggregateOffMain`; publish the provider-wide snapshot

**Files:**
- Modify: `AIBattery/Services/AccountStore.swift` (next to `billsLocalCodexCosts`, `:215`)
- Modify: `AIBattery/ViewModels/UsageViewModel.swift:7-16` (remove the mirror), `:255-300` (`aggregateOffMain`)
- Modify: `AIBattery/ViewModels/UsageViewModel+FanOut.swift:70-91` (`providerWide: true`)
- Test: `Tests/AIBatteryCoreTests/Services/AccountStoreProviderTests.swift`

**Interfaces:**
- Produces: `nonisolated static func AccountStore.attribution(for accountId: String?, provider: AIProvider, accounts: [AccountRecord]) -> Attribution`; `aggregateOffMain(…, providerWide: Bool = false)`.
- Consumes: `AggregateResult` (Task 7).

- [ ] **Step 1: Failing tests** (append to `AccountStoreProviderTests`)

```swift
    /// Attribution exists only for a ChatGPT-backed Codex account when at least two such
    /// accounts exist — the only case where "whose turns are these?" has more than one
    /// answer. API keys, Claude and single-account setups always see everything.
    @Test func attribution_onlyForChatGPTCodexWithTwoOrMore() {
        let a = AccountRecord(id: "codex-a", billingType: "plus", addedAt: Date(), provider: .codex)
        let b = AccountRecord(id: "codex-b", billingType: "pro", addedAt: Date(), provider: .codex)
        let key = AccountRecord(id: "openai-api-k", billingType: "api", addedAt: Date(), provider: .codex, codexAccessMode: .apiKey)
        let claude = AccountRecord(id: "org-1", billingType: "pro", addedAt: Date(), provider: .claude)

        #expect(AccountStore.attribution(for: "codex-a", provider: .codex, accounts: [a, b]) == .account("codex-a"))
        #expect(AccountStore.attribution(for: "codex-b", provider: .codex, accounts: [a, b, key]) == .account("codex-b"))
        #expect(AccountStore.attribution(for: "codex-a", provider: .codex, accounts: [a]) == .all)
        #expect(AccountStore.attribution(for: "codex-a", provider: .codex, accounts: [a, key]) == .all)
        #expect(AccountStore.attribution(for: "openai-api-k", provider: .codex, accounts: [a, b, key]) == .all)
        #expect(AccountStore.attribution(for: "org-1", provider: .claude, accounts: [a, b, claude]) == .all)
        #expect(AccountStore.attribution(for: nil, provider: .codex, accounts: [a, b]) == .all)
        #expect(AccountStore.attribution(for: "missing", provider: .codex, accounts: [a, b]) == .all)
    }
```

- [ ] **Step 2: Run** — `swift test --filter "AccountStore provider caps"` → compile error.

- [ ] **Step 3: Implement**

`AccountStore.swift`, after `billsLocalCodexCosts`:

```swift
    /// Which turns the active account's local Codex data should count. Per-account
    /// attribution is only meaningful (and only possible) when two or more ChatGPT-backed
    /// Codex accounts exist and the active one is one of them.
    nonisolated static func attribution(for accountId: String?, provider: AIProvider, accounts: [AccountRecord]) -> Attribution {
        guard provider == .codex, let accountId,
              let active = accounts.first(where: { $0.id == accountId }),
              active.provider == .codex, !active.isAPIKeyAccount else { return .all }
        let chatGPTCount = accounts.filter { $0.provider == .codex && !$0.isAPIKeyAccount }.count
        return chatGPTCount >= 2 ? .account(accountId) : .all
    }
```

`UsageViewModel.swift`: replace the `snapshot` property with a plain `@Published var snapshot: UsageSnapshot?` (delete the `didSet` mirror and its comment). `aggregateOffMain`:

```swift
    func aggregateOffMain(
        rateLimits: RateLimitUsage?,
        rateLimitSource: RateLimitSource? = nil,
        standardLimits: StandardRateLimits? = nil,
        accountId: String? = nil,
        provider: AIProvider = .claude,
        rateLimitsFresh: Bool = true,
        applySideEffects: Bool = true,
        providerWide: Bool = false
    ) async -> UsageSnapshot {
        if let inflight = inflightAggregation {
            _ = await inflight.value
        }
        let accounts = OAuthManager.shared.accountStore.accounts
        // Decided here, once, for all seven callers: the detail view gets per-account data
        // only when two or more ChatGPT Codex accounts exist; the overview's background
        // pass for another provider always asks for everything.
        let attribution: Attribution = providerWide ? .all : AccountStore.attribution(for: accountId, provider: provider, accounts: accounts)

        let agg = aggregator(for: provider)
        let task = Task.detached {
            agg.aggregate(rateLimits: rateLimits, rateLimitSource: rateLimitSource, standardLimits: standardLimits, accountId: accountId, rateLimitsFresh: rateLimitsFresh, attribution: attribution)
        }
        inflightAggregation = task
        var result = await task.value
        let billed = accountId.map { AccountStore.billsLocalCodexCosts(accounts: accounts, activeId: $0) } ?? false
        result.detail.costIsBilled = billed
        result.providerWide.costIsBilled = billed

        // The overview's cards read this map; it must never carry an attributed snapshot
        // (two Codex cards would otherwise show one account's turns). A nil snapshot on an
        // account switch must not erase a provider's last known aggregate either — only
        // real results land here.
        providerSnapshots[provider] = result.providerWide

        if applySideEffects, result.effects.provider == .claude {
            RateLimitFetcher.shared.activeUserModel = result.effects.activeUserModel
            if let id = result.effects.accountId {
                RateLimitFetcher.shared.setObservedModels(result.effects.observedModels, accountId: id)
            }
        }
        inflightAggregation = nil
        return result.detail
    }
```

Keep the type alias `inflightAggregation: Task<UsageAggregator.AggregateResult, Never>?` consistent (find its declaration with `grep -n inflightAggregation AIBattery/ViewModels/UsageViewModel.swift`).

`UsageViewModel+FanOut.swift:79`: add `providerWide: true` to that `aggregateOffMain(...)` call and update the comment: "Provider-wide by construction: cards show the provider's total, never one account's share." Remove the now-redundant `if providerSnapshots[provider] != snapshot { providerSnapshots[provider] = snapshot }` (`:88-90`) — `aggregateOffMain` publishes.

- [ ] **Step 4: Run + smoke**

`swift test` → PASS (any VM test that asserted the `didSet` mirror — `grep -rn "providerSnapshots" Tests/` — now asserts the publish from `aggregateOffMain`; adjust). `./scripts/build-app.sh && open .build/AIBattery.app`: with your one Claude + one Codex account the overview cards still show tokens-today and the live dot; detail views unchanged. Relaunch the installed app afterwards. README Services `+1`.

- [ ] **Step 5: Commit**

```bash
swiftformat AIBattery/ Tests/ && swiftlint --quiet
git add AIBattery/Services/AccountStore.swift AIBattery/ViewModels/ Tests/ README.md
git commit -m "feat: decide Codex attribution in aggregateOffMain and publish the provider-wide snapshot from there"
```

---

### Task 9: Session-log fallback — head read, per-account gating, maximum age

**Files:**
- Modify: `AIBattery/Services/CodexSessionRateLimitScanner.swift` (new `creatorAccountId(ofNewestIn:)` + cache; `sessionMetaMaxLineBytes`)
- Modify: `AIBattery/Services/CodexRateLimitFetcher.swift:346-407` (`shouldUseSessionLogFallback`, `sessionLogFallback`, `cachedOrEmpty`; `codexFallbackMaxAge`)
- Test: `Tests/AIBatteryCoreTests/Services/CodexSessionRateLimitScannerTests.swift`, `Tests/AIBatteryCoreTests/Services/CodexRateLimitFetcherTests.swift`
- Modify: `spec/CONSTANTS.md` ("Timing" + "JSONL Processing"), `TODOS.md` (close the max-age item; add the per-account newest-file item)

**Interfaces:**
- Produces: `nonisolated static func creatorAccountId(ofNewestIn root: URL = CodexPaths.sessions, now: Date = .now) -> String?`; `nonisolated static func creatorAccountId(fromFirstLineOf file: URL) -> String?`; `static let sessionMetaMaxLineBytes = 1_048_576`; `CodexRateLimitFetcher.codexFallbackMaxAge: TimeInterval = 7 * 86_400`; `shouldUseSessionLogFallback(cached:fallbackAsOf:codexAccountCount:rolloutAccountId:accountId:now:)`.

- [ ] **Step 1: Failing scanner tests**

```swift
    private func writeRollout(_ lines: [String]) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("scanner-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("rollout-2026-10-19T10-00-00-x.jsonl")
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: url)
        return url
    }

    @Test func creatorAccountId_readsOnlyTheFirstLine_evenWhenLarge() throws {
        let padding = String(repeating: "x", count: 23_000)
        let meta = #"{"type":"session_meta","payload":{"id":"s","base_instructions":{"text":"\#(padding)"},"creator_account_id":"acct-1"}}"#
        let url = try writeRollout([meta, tokenCountLine(primaryPercent: 1), #"{"type":"session_meta","payload":{"creator_account_id":"acct-2"}}"#])
        #expect(CodexSessionRateLimitScanner.creatorAccountId(fromFirstLineOf: url) == "acct-1")
    }

    @Test func creatorAccountId_nilWhenFirstLineIsResponseItem_orNotSessionMeta_orMissing() throws {
        let responseFirst = try writeRollout([#"{"type":"response_item","payload":{"text":"\"creator_account_id\":\"leak\""}}"#, #"{"type":"session_meta","payload":{"creator_account_id":"acct-1"}}"#])
        #expect(CodexSessionRateLimitScanner.creatorAccountId(fromFirstLineOf: responseFirst) == nil)
        let turnFirst = try writeRollout([#"{"type":"turn_context","payload":{"creator_account_id":"acct-1"}}"#])
        #expect(CodexSessionRateLimitScanner.creatorAccountId(fromFirstLineOf: turnFirst) == nil)
        let noKey = try writeRollout([#"{"type":"session_meta","payload":{"id":"s"}}"#])
        #expect(CodexSessionRateLimitScanner.creatorAccountId(fromFirstLineOf: noKey) == nil)
        let empty = try writeRollout([""])
        #expect(CodexSessionRateLimitScanner.creatorAccountId(fromFirstLineOf: empty) == nil)
    }

    @Test func creatorAccountId_nilWhenFirstLineExceedsCap() throws {
        let huge = #"{"type":"session_meta","payload":{"creator_account_id":"acct-1","pad":""# + String(repeating: "y", count: CodexSessionRateLimitScanner.sessionMetaMaxLineBytes + 10) + #""}}"#
        let url = try writeRollout([huge])
        #expect(CodexSessionRateLimitScanner.creatorAccountId(fromFirstLineOf: url) == nil)
    }

    @Test func creatorAccountId_ofNewest_followsTheNewestFileCache() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("scanner-root-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let first = root.appendingPathComponent("a.jsonl")
        try Data(#"{"type":"session_meta","payload":{"creator_account_id":"acct-1"}}"#.utf8).write(to: first)
        CodexSessionRateLimitScanner.invalidateFileCache()
        #expect(CodexSessionRateLimitScanner.creatorAccountId(ofNewestIn: root) == "acct-1")
        let second = root.appendingPathComponent("b.jsonl")
        try Data(#"{"type":"session_meta","payload":{"creator_account_id":"acct-2"}}"#.utf8).write(to: second)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: second.path)
        CodexSessionRateLimitScanner.invalidateFileCache()
        #expect(CodexSessionRateLimitScanner.creatorAccountId(ofNewestIn: root) == "acct-2")
    }
```

- [ ] **Step 2: Failing fetcher tests** (append; keep the two existing fallback tests but update their calls to the new signature with `rolloutAccountId: nil, accountId: "acc", now: t0`)

```swift
    @Test func sessionLogFallback_withTwoAccounts_onlyForTheAccountStampedOnTheNewestRollout() {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(CodexRateLimitFetcher.shouldUseSessionLogFallback(cached: nil, fallbackAsOf: t0, codexAccountCount: 2, rolloutAccountId: "a", accountId: "a", now: t0))
        #expect(!CodexRateLimitFetcher.shouldUseSessionLogFallback(cached: nil, fallbackAsOf: t0, codexAccountCount: 2, rolloutAccountId: "a", accountId: "b", now: t0))
        #expect(!CodexRateLimitFetcher.shouldUseSessionLogFallback(cached: nil, fallbackAsOf: t0, codexAccountCount: 2, rolloutAccountId: nil, accountId: "a", now: t0))
        // One account: the stamp is irrelevant.
        #expect(CodexRateLimitFetcher.shouldUseSessionLogFallback(cached: nil, fallbackAsOf: t0, codexAccountCount: 1, rolloutAccountId: "zzz", accountId: "a", now: t0))
    }

    @Test func sessionLogFallback_refusesReadingsOlderThanMaxAge() {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let limit = CodexRateLimitFetcher.codexFallbackMaxAge
        #expect(CodexRateLimitFetcher.shouldUseSessionLogFallback(cached: nil, fallbackAsOf: t0.addingTimeInterval(-limit), codexAccountCount: 1, rolloutAccountId: nil, accountId: "a", now: t0))
        #expect(!CodexRateLimitFetcher.shouldUseSessionLogFallback(cached: nil, fallbackAsOf: t0.addingTimeInterval(-limit - 1), codexAccountCount: 1, rolloutAccountId: nil, accountId: "a", now: t0))
    }

    @Test func cachedOrEmpty_dropsStaleSessionLogReadings_keepsStaleEndpointReadings() throws {
        let fetcher = CodexRateLimitFetcher(defaults: makeDefaults()) // use the suite's existing fetcher factory
        let t0 = Date()
        let old = t0.addingTimeInterval(-CodexRateLimitFetcher.codexFallbackMaxAge - 1)
        let limits = endpointResult(fetchedAt: old).rateLimits
        fetcher.cachedResults["log"] = APIFetchResult(rateLimits: limits, rateLimitSource: .codexSessionLog, profile: nil, fetchedAt: old, isCached: true)
        fetcher.cachedResults["api"] = APIFetchResult(rateLimits: limits, rateLimitSource: .codexUsageEndpoint, profile: nil, fetchedAt: old, isCached: true)
        #expect(fetcher.cachedOrEmpty(accountId: "log", now: t0).rateLimits == nil)
        #expect(fetcher.cachedOrEmpty(accountId: "api", now: t0).rateLimits != nil)
    }
```

(Use the suite's real factory names: read the top of `CodexRateLimitFetcherTests.swift` for how it builds a fetcher and an `endpointResult`; `cachedResults` may need `internal` + a `ForTesting` setter — follow the file's existing pattern, e.g. `registerAuthFailureForTesting`. The `RateLimitSource` case name for the endpoint is whatever `sessionLogFallback`'s siblings use — `grep -n "rateLimitSource: \." AIBattery/Services/CodexRateLimitFetcher.swift`.)

- [ ] **Step 3: Run** — `swift test --filter "CodexSessionRateLimitScanner|CodexRateLimitFetcher"` → compile errors.

- [ ] **Step 4: Implement the scanner**

```swift
    /// Cap on the first line of a rollout. `session_meta` carries `base_instructions`
    /// (observed up to 23 KB); the reader discards lines over 1 MB, so do we.
    static let sessionMetaMaxLineBytes = 1_048_576

    nonisolated(unsafe) private static var creatorIdCache: (file: URL, id: String?)?

    /// The ChatGPT account stamped on the newest rollout, or nil. Memoized per newest
    /// file (the file changes only when the CLI starts a session; its first line never
    /// changes after that), so an outage costs one head read per session, not per poll.
    nonisolated static func creatorAccountId(ofNewestIn root: URL = CodexPaths.sessions, now: Date = .now) -> String? {
        guard let file = cachedNewestSessionFile(in: root, now: now) else { return nil }
        newestFileCacheLock.lock()
        defer { newestFileCacheLock.unlock() }
        if let cache = creatorIdCache, cache.file == file { return cache.id }
        let id = creatorAccountId(fromFirstLineOf: file)
        creatorIdCache = (file, id)
        return id
    }

    /// Reads the file's first line only. Same content boundary as everywhere else: a
    /// `response_item` is rejected from its head bytes and never decoded; only a line
    /// whose `type` is `session_meta` yields a value, and only `creator_account_id` is read.
    nonisolated static func creatorAccountId(fromFirstLineOf file: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: sessionMetaMaxLineBytes + 1), !head.isEmpty else { return nil }
        let lineEnd = head.firstNewlineIndex(from: head.startIndex)
        guard let lineEnd else {
            // No newline inside the cap: either the line is over the cap or the file is
            // a single unterminated line (still being written). Refuse both.
            return nil
        }
        let line = head[head.startIndex..<lineEnd]
        guard !CodexSessionLogParser.isResponseItem(line),
              let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              object["type"] as? String == "session_meta",
              let payload = object["payload"] as? [String: Any],
              let id = payload["creator_account_id"] as? String, !id.isEmpty else { return nil }
        return id
    }
```

`invalidateFileCache()` also sets `creatorIdCache = nil`. (`Data.firstNewlineIndex(from:)` exists — `AIBattery/Utilities/Data+Newline.swift` or wherever `grep -rn "func firstNewlineIndex" AIBattery` says.)

- [ ] **Step 5: Implement the fetcher**

```swift
    /// A rollout reading older than this is not a usable stand-in for the endpoint, on
    /// either path (fresh scan or the in-memory cache of a previous scan).
    nonisolated static let codexFallbackMaxAge: TimeInterval = 7 * 86_400

    nonisolated static func shouldUseSessionLogFallback(
        cached: APIFetchResult?, fallbackAsOf: Date, codexAccountCount: Int = 1,
        rolloutAccountId: String?, accountId: String, now: Date
    ) -> Bool {
        if codexAccountCount >= 2 {
            guard let rolloutAccountId, rolloutAccountId == accountId else { return false }
        }
        guard now.timeIntervalSince(fallbackAsOf) <= codexFallbackMaxAge else { return false }
        guard let cached else { return true }
        return fallbackAsOf > cached.fetchedAt
    }
```

`sessionLogFallback`:

```swift
    private func sessionLogFallback(accountId: String) async -> APIFetchResult {
        let codexAccountCount = OAuthManager.shared.accountStore.accounts.filter { $0.provider == .codex && !$0.isAPIKeyAccount }.count
        // With 2+ ChatGPT accounts only the account stamped on the newest rollout may use
        // it. Decide that from the (memoized) first line BEFORE the tail scan, so the other
        // accounts pay nothing per poll — the whole-tree walk + 256 KB tail read per account
        // per poll is exactly what this guard existed to prevent.
        var rolloutAccountId: String?
        if codexAccountCount >= 2 {
            rolloutAccountId = await Task.detached(priority: .utility) { CodexSessionRateLimitScanner.creatorAccountId(ofNewestIn: CodexPaths.sessions) }.value
            guard rolloutAccountId == accountId else { return cachedOrEmpty(accountId: accountId) }
        }
        let scanned = await Task.detached(priority: .utility) { CodexSessionRateLimitScanner.latestRateLimits() }.value
        guard let (rateLimits, asOf) = scanned,
              Self.shouldUseSessionLogFallback(cached: cachedResults[accountId], fallbackAsOf: asOf, codexAccountCount: codexAccountCount,
                                               rolloutAccountId: rolloutAccountId, accountId: accountId, now: Date()) else {
            return cachedOrEmpty(accountId: accountId)
        }
        // … unchanged from here …
```

`cachedOrEmpty(accountId:authError:now: Date = Date())`: at the top of the `if let cached` branch:

```swift
            // A cached rollout reading ages out; a cached endpoint reading does not (stale
            // beats empty for real data; a week-old CLI snapshot is not real data).
            let tooOld = cached.rateLimitSource == .codexSessionLog && now.timeIntervalSince(cached.fetchedAt) > Self.codexFallbackMaxAge
            return APIFetchResult(
                rateLimits: tooOld ? nil : cached.rateLimits?.withClearedExpiredWindows(),
                // … rest unchanged …
```

- [ ] **Step 6: Run** — `swift test --filter "CodexSessionRateLimitScanner|CodexRateLimitFetcher"` → PASS; `swift test` → PASS. README Services `+7`.

- [ ] **Step 7: Docs + commit**

`spec/CONSTANTS.md` "Timing": `codexFallbackMaxAge = 7 × 86 400 s`; "JSONL Processing": `sessionMetaMaxLineBytes = 1 MB (first-line head read for creator_account_id; response_item rejected from head bytes; keys-only)`. `TODOS.md`: strike the "session-log fallback has no maximum age" item (`- [x] ~~…~~ Fixed in v3.3.0: …`); add under the Codex list:

```markdown
- [ ] **Session-log fallback inspects only the newest rollout.** With two ChatGPT accounts the one
  whose CLI session is newest gets the fallback and the other serves its cache. A per-account
  newest-file search (walk newest-first, head-read until a matching `creator_account_id`,
  bounded to ~20 files) would give both accounts a reading. Deferred from v3.3.0: outage ×
  two accounts is an edge of an edge.
```

```bash
swiftformat AIBattery/ Tests/ && swiftlint --quiet
git add AIBattery/Services/CodexSessionRateLimitScanner.swift AIBattery/Services/CodexRateLimitFetcher.swift Tests/ spec/CONSTANTS.md TODOS.md README.md
git commit -m "feat: gate the Codex session-log fallback by the rollout's account stamp and a maximum age"
```

---

### Task 10: Hidden-turn count in the Insights caption and tooltip

**Files:**
- Modify: `AIBattery/Views/InsightsRowsAndHover.swift:33-51` (`allTimeTooltip(for:since:unattributed:)`), `AIBattery/Views/InsightsCharts.swift` (`sinceCaption(provider:since:unattributed:now:)`), `AIBattery/Views/ActivityChartView.swift` (caption call site)
- Test: `Tests/AIBatteryCoreTests/Views/InsightsAllTimeCaveatTests.swift`

**Interfaces:**
- Consumes: `UsageSnapshot.unattributedTurnCount` (Task 7); `InsightsView.allTimeTooltip(for:since:)` and `InsightsView.sinceCaption(provider:since:unattributed:now:)` as left by Phase 2 Task 9 (the `unattributed:` parameter exists there with default 0 if Task 9 followed the re-base; if Task 9 was cut, add both parameters here with the same names).
- Produces: the final signatures above.

- [ ] **Step 1: Failing tests** (append)

```swift
    @Test func codex_tooltipAppendsHiddenTurnCount() {
        let text = InsightsView.allTimeTooltip(for: .codex, since: nil, unattributed: 902)
        #expect(text.hasSuffix(" · 902 turns from older Codex CLI versions are not attributable"))
        #expect(!InsightsView.allTimeTooltip(for: .codex, since: nil, unattributed: 0).contains("not attributable"))
        #expect(!InsightsView.allTimeTooltip(for: .claude, since: nil, unattributed: 5).contains("not attributable"))
    }

    @Test func caption_combinesSinceAndHiddenCount_inEveryMode() {
        let now = Date(timeIntervalSince1970: 1_789_000_000)
        let since = now.addingTimeInterval(-30 * 86_400)
        let both = InsightsView.sinceCaption(provider: .codex, since: since, unattributed: 3, now: now)
        #expect(both?.hasPrefix("since ") == true)
        #expect(both?.hasSuffix(" · 3 turns from older Codex CLI versions not shown") == true)
        #expect(InsightsView.sinceCaption(provider: .codex, since: nil, unattributed: 1, now: now) == "1 turn from older Codex CLI versions not shown")
        #expect(InsightsView.sinceCaption(provider: .codex, since: nil, unattributed: 0, now: now) == nil)
        #expect(InsightsView.sinceCaption(provider: .claude, since: since, unattributed: 9, now: now) == nil)
    }
```

- [ ] **Step 2: Run** — `swift test --filter "All Time caveat"` → compile error / failure.

- [ ] **Step 3: Implement**

`InsightsRowsAndHover.swift`:

```swift
    nonisolated static func allTimeTooltip(for provider: AIProvider, since: Date? = nil, unattributed: Int = 0) -> String {
        switch provider {
        case .claude: return "Cumulative tokens across all sessions"
        case .codex:
            var text = "Cumulative tokens from Codex session logs since AI Battery first scanned them (kept across log rotation; Codex has no lifetime cache of its own)"
            if let since { text += " — since \(DateFormatters.mediumDate(since))" }
            if unattributed > 0 { text += " · \(unattributed) turns from older Codex CLI versions are not attributable" }
            return text
        }
    }
```

Call site: `tooltip: Self.allTimeTooltip(for: snapshot.provider, since: snapshot.ledgerSince, unattributed: snapshot.unattributedTurnCount)` (drop `since:` if Phase 2 Task 9 was cut).

`InsightsCharts.swift`:

```swift
    /// One caption under the chart, in every mode: where the Codex data starts and how
    /// many turns per-account attribution had to hide. nil when neither applies.
    nonisolated static func sinceCaption(provider: AIProvider, since: Date?, unattributed: Int, now: Date) -> String? {
        guard provider == .codex else { return nil }
        var parts: [String] = []
        if let since, since > now.addingTimeInterval(-365 * 86_400) {
            parts.append("since \(DateFormatters.mediumDate(since))")
        }
        if unattributed > 0 {
            parts.append("\(unattributed) turn\(unattributed == 1 ? "" : "s") from older Codex CLI versions not shown")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
```

`ActivityChartView.swift`, right after the mode `switch` that renders the chart:

```swift
            if let snapshot,
               let caption = Self.sinceCaption(provider: snapshot.provider, since: snapshot.ledgerSince, unattributed: snapshot.unattributedTurnCount, now: Date()) {
                Text(caption)
                    .font(Typography.monoTiny)
                    .foregroundStyle(ThemeColors.tertiaryLabel)
                    .lineLimit(2)
                    .help("Codex has no lifetime cache: the charts are rebuilt from the rollouts on disk, and turns from Codex CLI versions that did not stamp the account are hidden while two or more ChatGPT accounts are signed in")
            }
```

- [ ] **Step 4: Run** — `swift test` → PASS. README Views `+2`. Append to CHANGELOG `### Added`:

```markdown
- **Each Codex account sees its own sessions.** With two or more ChatGPT-backed Codex accounts, Insights, Projects and Context show the active account's turns only (current Codex CLI versions stamp every rollout with the account). Turns from older CLI versions carry no stamp and are hidden rather than guessed — the Insights caption says how many. Overview cards keep showing the provider's total. Verified with fixtures; if you run two accounts, please report what you see.
```

- [ ] **Step 5: Commit**

```bash
swiftformat AIBattery/ Tests/ && swiftlint --quiet
git add AIBattery/Views/ Tests/AIBatteryCoreTests/Views/InsightsAllTimeCaveatTests.swift CHANGELOG.md README.md
git commit -m "feat: say how many unattributable Codex turns are hidden (caption + tooltip)"
```

---

### Task 11: Wrap-up — spec sync, version, PR

**Files:** `spec/ARCHITECTURE.md`, `spec/DATA_LAYER.md`, `spec/UI_SPEC.md`, `spec/CONSTANTS.md`, `CLAUDE.md`, `README.md`, `CHANGELOG.md`, `TODOS.md`, `AIBattery/Info.plist`.

- [ ] **Step 1: Spec sync (per spec §9)**

- `ARCHITECTURE.md`: project tree gains `Views/UpdateArrowButton.swift`, `Services/Attribution.swift` (and `UsageAggregator+Pass.swift` if split); the dispatch-seam list gains "`Attribution` — decided in `UsageViewModel.aggregateOffMain`, applied in `UsageAggregator.aggregate` (one pass, `AggregateResult.detail` / `.providerWide`)"; data-flow section: `providerSnapshots` is published by `aggregateOffMain`, never mirrored from `snapshot`.
- `DATA_LAYER.md`: `AssistantUsageEntry.creatorAccountId`; `Attribution` + `partition`; `AggregationPass` / `AggregateResult`; `UsageSnapshot.unattributedTurnCount`; `TokenLedger.key` rule (plain / `#attributed` / `codex#all`) and the prune rule; scanner first-line read + memo; fallback gating table incl. max age on both paths.
- `UI_SPEC.md`: already updated by Task 2; add the Insights caption line and tooltip text.
- `CONSTANTS.md`: already updated by Tasks 2 and 9; verify.
- `CLAUDE.md`: in "Key Design Decisions", the Codex-local-data bullet gains: "With ≥ 2 ChatGPT-backed Codex accounts the active account's detail view is **attributed** (`creator_account_id` from `session_meta`; unstamped turns hidden and counted); one aggregation pass yields both the attributed and the provider-wide snapshot; ledger series are keyed `<id>`, `<id>#attributed`, `codex#all`." The multi-account-overview bullet: "Cards show **provider-wide** totals (`providerSnapshots`, published by `aggregateOffMain`), never an attributed snapshot." Update the test count line.
- `TODOS.md`: strike "Per-account attribution of Codex local data" (`- [x] ~~…~~ Shipped in v3.3.0`).
- `README.md`: feature bullets for the arrow and attribution; "Test Coverage" totals reconciled with `swift test` output (`swift test 2>&1 | grep -E "Test run with [0-9]+ tests"`); test-file count via `find Tests -name '*.swift' | wc -l`.

- [ ] **Step 2: Version**

`AIBattery/Info.plist`: `CFBundleShortVersionString` `3.2.0` → `3.3.0`; bump `CFBundleVersion` by one. CHANGELOG heading stays `Unreleased` until Kyle tags (release flow: tag `v3.3.0` on `main` after merge; CI builds and publishes).

- [ ] **Step 3: Full verification**

```bash
swiftformat AIBattery/ AIBatteryApp/ Tests/ && swiftlint
swift test 2>&1 | tail -3
./scripts/build-app.sh && open .build/AIBattery.app
```

Walk every surface per account (Context row, Insights tooltip and caption, credits footer, header, overview footer). Relaunch `/Applications/AIBattery.app`. Commit `docs: sync specs, README and CLAUDE.md for v3.3.0; bump version`.

- [ ] **Step 4: Draft PR**

```bash
git push -u origin worktree-v3-3-0
gh pr create --draft --title "v3.3.0: update arrow, provider-relevant display, Codex per-account attribution" --body-file - <<'EOF'
## Summary
- Header update arrow replaces the banner + gear badge (click installs via Sparkle; right-click → release notes / check).
- Phase 2 provider-relevant display: Codex per-record context window, reasoning/thinking share, effort label, limit name, credit runway, dated All-Time (+ per-model weekly windows if the live payload carried them — see the spec's recorded key set).
- Codex per-account attribution with ≥ 2 ChatGPT accounts: one aggregation pass → attributed detail + provider-wide cards; namespaced ledger series; fallback gated by the newest rollout's account stamp and a 7-day maximum age.

Specs: `docs/superpowers/specs/2026-10-19-v3-3-0-release-design.md`, `docs/superpowers/specs/2026-10-12-provider-relevance-design.md`.

## Test plan
- [ ] `swift test` green locally (count in README)
- [ ] `./scripts/build-app.sh` bundle launches; header/footer arrow absent with no update; no banner, no badge
- [ ] One Claude + one Codex account: every view identical to 3.2.0 apart from Phase 2 additions
- [ ] Attribution: fixture-verified only (one Codex account on the dev machine) — two-account users asked to report
- [ ] Mark ready-for-review once Kyle's manual check passes → CI runs once
EOF
```

Stays draft until Kyle says done.

---

## Self-review against the spec

- §0 housekeeping → Task 0 (whole-tree diff, no-live-session rule, remove by path, website sync). §1 arrow → Tasks 1–2 (breathe, glow, context menu, `withAnimation` at both set sites, footer `availableUpdate`, badge/banner removal, compile-flag doc correction, pure-helper tests). §2 Phase 2 re-base → Task 4 (Task 0 method, `creatorAccountId` in Task 1 with the double-`session_meta` test, ledger keys, caption home + every-mode rule, existing caveat test file, tooltip name corrected to `InsightsView.allTimeTooltip`). §3 attribution: data model → Task 4e; partition → Task 5; one pass two snapshots, `unattributedTurnCount`, `==`, fingerprint → Task 7; decision in `aggregateOffMain`, publish, mirror removed, fan-out `providerWide` → Task 8; ledger keys + prune → Task 6; scanner first-line read + memo, fallback gating, max age on both paths, documented asymmetry in TODOS → Task 9; caption + tooltip → Task 10; verification wording → Task 10 changelog. §4 error handling → covered by the nil paths in Tasks 5, 9. §5 tests → each task. §6 R1 → Phase 2 Task 0; R4 → unchanged heuristic (Task 8 keeps `billsLocalCodexCosts`). §9 sync → Tasks 2, 9, 11.
- Names used across tasks: `Attribution.all/.account(_)/.isAttributed/.partition(_:)`, `TokenLedger.key(accountId:attribution:)`, `TokenLedger.providerWideCodexKey`, `TokenLedger.attributedSuffix`, `TokenLedger.baseAccountId(ofKey:)`, `merge(_:ledgerKey:)`, `pruneAccounts(keeping:hasLiveCodexAccount:)`, `ledgerKeysForTesting()`, `UsageAggregator.AggregateResult.detail/.providerWide/.effects`, `aggregate(…, attribution:now:)`, `AggregationPass.add(_:)/finish(entries:…ledgerKey:)`, `UsageSnapshot.unattributedTurnCount`, `AccountStore.attribution(for:provider:accounts:)`, `aggregateOffMain(…, providerWide:)`, `CodexSessionRateLimitScanner.creatorAccountId(ofNewestIn:now:)/creatorAccountId(fromFirstLineOf:)/sessionMetaMaxLineBytes`, `CodexRateLimitFetcher.codexFallbackMaxAge`, `shouldUseSessionLogFallback(cached:fallbackAsOf:codexAccountCount:rolloutAccountId:accountId:now:)`, `cachedOrEmpty(accountId:authError:now:)`, `InsightsView.allTimeTooltip(for:since:unattributed:)`, `InsightsView.sinceCaption(provider:since:unattributed:now:)`, `UpdateArrowButton.helpText/accessibilityLabel/breatheAnimation/releaseNotesTitle/checkForUpdatesTitle` — consistent.
- Soft spots an implementer resolves on the spot (named in the steps): `StatsCache` type name in `AggregationPass.finish`; whether `AggregationPass` needs its own file (800-line rule); the fetcher test suite's factory names; the `RateLimitSource` endpoint case name; the `inflightAggregation` type alias; the `pruneAccounts` production caller; `Data.firstNewlineIndex`'s file.
