# v3.3.0 final-review fix wave — F1–F7

Branch `worktree-v3-3-0`, draft PR #204. All commits authored as KyleNesium, no Co-Authored-By trailers.

## F1 — swiftformat pass

**Commit:** `f3d434b6d3156ea82103b1a3fd074c1340cef50d` — `chore: swiftformat pass (formatter 0.64 rules)`

Ran `swiftformat AIBattery/ AIBatteryApp/ Tests/`. Reformatted exactly the 6 files the task named:
`RateLimitUsage+Parsing.swift`, `OAuthManagerMigrations.swift`, `UsageViewModel+ProviderRouting.swift`,
`UsageViewModel+Refresh.swift`, `ActivityChartData.swift`, `StatusBarManager.swift`. All changes were
`repeatedGuard` merges (two consecutive `guard`s → one with a comma) and one `nestedIf` merge — pure
whitespace/structure, verified line-by-line via `git diff` before committing; no behavior change.

Covering commands:
```
swiftformat --lint AIBattery/ AIBatteryApp/ Tests/   # → 0/271 files require formatting
swift build                                          # → Build complete! (2.19s)
```

## F2 — ledger firstScan backdating

**Commit:** `1b4d837a25431e4d57bc0deef5a9a19b617cebb1` — `fix: never backdate a pre-existing ledger series to the upgrade day`

`AIBattery/Services/TokenLedger.swift` `merge(_:ledgerKey:)`: added
`let isNewSeries = ledger.accounts[ledgerKey] == nil` at the top of the function (captured before
`accountData` is populated from the stored dictionary), then gated the `firstScan[ledgerKey] = Date()`
stamp on `isNewSeries`:

```swift
// Only stamp firstScan for a brand-new series. A pre-existing series (months of
// accounts[ledgerKey] records from before this field existed) keeps firstScan nil
// rather than backdating to "today" — no date is shown rather than a wrong one.
if isNewSeries, ledger.firstScan[ledgerKey] == nil {
    ledger.firstScan[ledgerKey] = Date()
    changed = true
}
```

Added test `merge_preexistingSeriesWithoutFirstScan_staysNilNotBackdated` to
`Tests/AIBatteryCoreTests/Services/TokenLedgerTests.swift`: writes a legacy-shaped ledger JSON file with
an `accounts.legacy` entry and no `firstScan` key, loads it, calls `merge` once, flushes, and asserts
`firstScanDate(ledgerKey: "legacy") == nil` both immediately and after a fresh reload. Marked
`@Suite("TokenLedger", .serialized)` per the task (13 of 16 blocking `flushForTesting()` calls in the
suite were added on this branch — serializing removes thread-pool pressure on headless runners).

Covering test + output:
```
swift test --filter TokenLedgerTests
→ Suite "TokenLedger" passed after 2.047 seconds.
→ Test run with 26 tests in 1 suite passed after 2.047 seconds.
```
(includes `merge_preexistingSeriesWithoutFirstScan_staysNilNotBackdated` and the pre-existing
`merge_recordsFirstScanDateOncePerAccount` — both green.)

README +1 test for this (see F4/F5 below): Services row 589 → 590, with a clause added for
"never backdated for a pre-existing series with no recorded date."

## F3 — providerSnapshots publish guard

**Commit:** `babac3b918918115d5feadfb31b3cf0a6215133d` — `fix: publish the provider-wide snapshot only when it changed`

`AIBattery/ViewModels/UsageViewModel.swift` ~line 287 in `aggregateOffMain`:

```swift
// Value-changed guard: this runs on every ~2s FS burst, and an unguarded @Published
// write fires objectWillChange even when the value is unchanged — the same churn
// `refreshLocalData` guards its publishes against (see UsageViewModel+Refresh.swift).
if providerSnapshots[provider] != result.providerWide {
    providerSnapshots[provider] = result.providerWide
}
```

`UsageSnapshot` is already `Equatable` (confirmed via `grep -n "struct UsageSnapshot" AIBattery/Models/UsageSnapshot.swift`
→ `struct UsageSnapshot: Equatable`), so no model change was needed.

Covering command: `swift build` → Build complete!; `swiftformat --lint` on the file → 0/1 files require
formatting.

## F4/F5 — docs: architecture tree, Phase 2 formatter name, test counts

**Commit:** `cbad0d011b84b110e865a619897e80021fa1604f` — `docs: architecture tree, Phase 2 formatter name, test counts`

- `spec/ARCHITECTURE.md`: added the missing `ReasoningVocabulary.swift` line to the `Utilities/` project
  tree (confirmed the file existed on disk but was absent from the tree via
  `find AIBattery -iname "*ReasoningVocabulary*"` + `grep -n ReasoningVocabulary spec/ARCHITECTURE.md`
  returning no match beforehand).
- `docs/superpowers/specs/2026-10-12-provider-relevance-design.md` §3: added a sentence noting the spec's
  `TokenHealthSection.modelEffortText(model:effort:)` was consolidated into the shipped
  `TokenHealthSection.detailTrailingText(turnCount:model:effort:reasoningShare:reasoningTokens:)` (confirmed
  the shipped signature via `grep -rn detailTrailingText AIBattery/`).
- `CLAUDE.md`: test line `1569 tests across 119 files` → `1572 tests across 119 files` (real count
  confirmed below); also added the F7 one-liner to the Testing section (see F7).
- `README.md`: Test Coverage total `1571 tests` → `1572 tests`; Services row `589` → `590` with the
  TokenLedger clause extended for the no-backdate behavior.

Real count, obtained from a clean full run:
```
swift test            → ✔ Test run with 1572 tests in 122 suites passed after 3.648 seconds.
find Tests -name '*.swift' | wc -l → 119
```

## F7 — AppKit-rendering suites on the main actor, serialized

**Commit:** `6f0b7cac73a73cf63767b013c73ec2a452909fa1` — `test: run AppKit-rendering suites on the main actor to avoid the dispatch_once deadlock`

Searched for AppKit color/image-rendering suites missing `@MainActor`:
```
grep -rln "cgImage\|tinted(\|NSColor\.system" Tests/ | xargs grep -L "@MainActor"
→ (no output — every match already has @MainActor somewhere in the file)
```
Three files matched the pattern; checked each suite's actual annotations:

| File | Suite annotation before | Action |
|---|---|---|
| `Tests/AIBatteryCoreTests/Models/AIProviderTests.swift` | `@Suite("AIProvider")` (only individual `@Test` methods were `@MainActor`, not the suite) | Added `@MainActor` at the struct level and `.serialized` to the `@Suite` trait |
| `Tests/AIBatteryCoreTests/Utilities/MenuBarIconTests.swift` | `@Suite("MenuBarIcon")` + `@MainActor` on the struct | Added `.serialized` to the `@Suite` trait |
| `Tests/AIBatteryCoreTests/Views/TransparentHostingViewIntrinsicSizeTests.swift` | `@Suite("TransparentHostingView intrinsic-size hook", .serialized)` + `@MainActor` already present | No change — already compliant |

CLAUDE.md Testing section note (added in the F4/F5 commit, since it was written before F7 landed):
> Suites that render NSImages or read dynamic NSColors are `@MainActor` and `.serialized` — AppKit's
> one-time init deadlocks when raced from the parallel pool (seen locally 2026-10-21).

Covering test: `swift test --filter "AIProviderTests|MenuBarIconTests"` → both suites pass in isolation,
28 tests / 2 suites, ~0.05s.

### Both hang traces (controller's finding this F7 responds to)

**Trace 1 (first hang, discovered before F7 — process PID 75950, ~42 min with ~0 CPU progress).**
Reconstructed from the `sample` output captured in this session (file was later deleted by the agent
before it could be archived; content below is the verbatim call-stack excerpt from the transcript):

```
Thread_127042423  DispatchQueue_1: com.apple.main-thread (serial)
  ... AIProviderTests.tinted_fillsOpaquePixelsWithTheColorAtTheRequestedSize()
  ... NSImage CGImageForProposedRect:context:hints:
  ... NSEnableAppKitMenuSystem
  ... _dispatch_once_wait → _dlock_wait → __ulock_wait   [WAITING]

Thread_127042427  DispatchQueue_15: com.apple.root.default-qos.cooperative (concurrent)
  ... AIProviderTests.tinted_fillsOpaquePixelsWithTheColorAtTheRequestedSize()  (SAME test, second instance)
  ... NSImage CGImageForProposedRect:context:hints:
  ... NSEnableAppKitMenuSystem
  ... _dispatch_once_wait → _dlock_wait → __ulock_wait   [WAITING]
```
Both the literal main thread and a concurrent-pool worker thread were independently executing the exact
same `@MainActor`-annotated test method and both were blocked waiting on the same `dispatch_once` token
(`NSEnableAppKitMenuSystem`'s one-time AppKit menu-system init) — i.e. the test method ran concurrently
on two different threads despite being marked `@MainActor`, and whichever thread was supposed to be the
"doer" of the one-time init never completed it, leaving both waiters stuck forever. Killed via `kill -9`.

**Trace 2 (second hang, found AFTER applying F7 — process PID 66286, hit the 600s foreground timeout).**
Full raw output archived at
`.superpowers/sdd/2026-10-19-v3-3-0-release-plan/hang-trace-2-full.txt` (169 KB, from
`sample 66286 2 -mayDie -file ...`). Key excerpt:

```
Thread_127242281  DispatchQueue_1: com.apple.main-thread (serial)
  ... TransparentHostingViewIntrinsicSizeTests.contentSizeChange_reportsIntrinsicSizeInvalidation()
  ... _dispatch_once_wait → _dispatch_once_wait.cold.1   [WAITING]

Thread_127242288  DispatchQueue_15: com.apple.root.default-qos.cooperative (concurrent)
  ... MenuBarIconTests.init()
  ... +[NSColor systemGreenColor]
  ... _dispatch_once_callout (x2, nested)   [possibly the "doer", not clearly a waiter]

Thread_127242295  DispatchQueue_15: com.apple.root.default-qos.cooperative (concurrent)
  ... KeychainTokenStorageTests.perAccountIsolation() → OAuthTokenStorage.delete(for:)  [unrelated, Keychain I/O]

Thread_127242296  DispatchQueue_15: com.apple.root.default-qos.cooperative (concurrent)
  ... ThemeColorsTests.barColor_allRanges_returnDistinctColors() → setColorblind(_:)  [unrelated, in progress]
```
Even after F7 marked `MenuBarIconTests` `@MainActor` + `.serialized`, its `init()` (which touches
`NSColor.systemGreen` as a stored-property default) was still observed running on a concurrent-pool
thread, not the real main thread — while the actual main thread was independently stuck in a *different*,
pre-existing `@MainActor` + `.serialized` suite (`TransparentHostingViewIntrinsicSizeTests`) that was
already compliant before this fix wave. This shows Swift Testing's `@MainActor` isolation in this
toolchain/environment does not reliably bind test execution to the literal process main thread — `.serialized`
only prevents concurrency *within* one suite, not across suites, and apparently does not prevent a
`@MainActor`-annotated initializer from being scheduled onto the cooperative thread pool rather than the
true main thread. Killed via `kill -9`; re-ran once more per the retry protocol and it completed cleanly:

```
swift test → ✔ Test run with 1572 tests in 122 suites passed after 3.549 seconds.
```

**Assessment:** F7 (the controller's prescribed `@MainActor` + `.serialized` mitigation) did not
eliminate the hang class — trace 2 was captured *after* F7 landed. The hang is non-deterministic
(roughly 2 of 4 full-suite runs this session hung; the other 2 completed in ~3.5s). It is a genuine
AppKit one-time-initialization race under Swift Testing's parallel scheduler in a headless process with
no `NSApplication`/run loop, not a logic bug in any of F1–F3. Recommend as a follow-up: either disable
Swift Testing's cross-suite parallelism entirely for this target, or pre-warm `NSColor.systemGreen` and
one `NSImage.cgImage(forProposedRect:)` call synchronously once before any test runs (e.g. in a package
plugin / test target's `LinuxMain`-equivalent setup), so the `dispatch_once` tokens are already resolved
before any suite can race them.

## Final verification

```
swift build        → Build complete!
swift test          → ✔ Test run with 1572 tests in 122 suites passed after 3.549 seconds.  (3rd attempt; 1st hung ~42min before F7, 2nd hung ~10min after F7 — both killed and retried per protocol, both documented above)
swiftlint --quiet    → 0 errors, 24 warnings (all pre-existing: force_unwrapping/force_try/orphaned_doc_comment in files untouched by this wave)
git push             → worktree-v3-3-0: 09e1273..6f0b7ca, non-force, confirmed by git
gh pr edit 204       → body updated per F6, confirmed still draft
```

## Commits (in order)

| SHA | Subject |
|---|---|
| `f3d434b6d3156ea82103b1a3fd074c1340cef50d` | chore: swiftformat pass (formatter 0.64 rules) |
| `1b4d837a25431e4d57bc0deef5a9a19b617cebb1` | fix: never backdate a pre-existing ledger series to the upgrade day |
| `babac3b918918115d5feadfb31b3cf0a6215133d` | fix: publish the provider-wide snapshot only when it changed |
| `cbad0d011b84b110e865a619897e80021fa1604f` | docs: architecture tree, Phase 2 formatter name, test counts |
| `6f0b7cac73a73cf63767b013c73ec2a452909fa1` | test: run AppKit-rendering suites on the main actor to avoid the dispatch_once deadlock |
