# Deferred work

Open items, grouped by area and ordered by priority inside each group. Every item names
the file or type involved so it can be picked up cold, and says which approach was chosen
when the obvious fix is not the right one. Shipped items are removed rather than struck
through; the history is in `CHANGELOG.md`.

**⚠ pins current behaviour** marks an item whose existing test asserts today's (wrong)
output — the fix has to change that test deliberately, not route around it.

Triaged 2026-10-31 against source. Items the earlier reviews listed as deferred but which
have since shipped were removed; items judged not worth doing are in **Decided not to do**
at the end so they are not re-litigated.

## Correctness — windows and counting

- [ ] **Clock-skew rollover guard** (`RateLimitUsage.swift`, `elapsed >= 0`). A Mac whose
  clock is minutes behind the server after wake makes `elapsed` negative on a just-rolled
  7-day window, the near-full lagging reading is no longer suppressed, and on a cold start
  the spike filter has no previous value to hold — the popover paints "Limit reached" on a
  freshly reset window. The v2.4.2 bug class through a new door. **Approach:** do not delete
  the guard — replace the hard `elapsed >= 0` with a skew tolerance of a few minutes, so a
  just-rolled window under skew is suppressed while a genuinely unknown period is still left
  alone. Needs skew and cold-start tests. ⚠ pins current behaviour
  (`CodexCreditBudgetTests.rolloverFilter_ignoresResetsBeyondWindowLength` asserts negative
  elapsed preserves utilization).
- [ ] **`fiveHourWindowTokens` includes one pre-window 15-minute bucket**
  (`UsageSnapshot.swift`). `startBucket = 20 - (Int(elapsed / 900) + 1)`; the first in-window
  bucket is `ceil(remaining / 900)`. Up to 15 minutes of pre-window tokens inflate the figure
  under the bar. Fix with a boundary test — nothing in `Tests/` references it today.
- [ ] **`sevenDayWindowTokens` over-counts by up to a full calendar day**
  (`UsageSnapshot.swift`). `windowStartKey` is day-granular (`yyyy-MM-dd`) compared with `>=`.
  **Approach:** day-keyed totals cannot express a mid-day start — sum entries directly from
  the window start instead of from the day key.
- [ ] **A session ending on a `<synthetic>` entry reports 0% context, green.**
  `TokenHealthMonitor` takes `sessionEntries.last` for model and context; synthetic entries
  (Claude Code interrupt/error pseudo-messages) carry all-zero usage, so a session at 700K/1M
  drops to "0%, 1,000,000 remaining" the moment the user hits Esc and auto-mode can never
  escalate. ~0.4% of sessions end this way. Fix: pick the last entry passing `isTrackedModel`.
- [ ] **The context-window tier bump halves the percentage exactly when context is most
  critical** — crossing the window doubles the denominator, so 199K/200K (red) becomes
  201K/500K (green). **Approach:** remove the bump rather than tune it. It dates from the
  200K era; the default is already 1M, so a stale table is no longer the likely cause of
  exceeding the window. Clamp at 100% red instead and add the Claude 5 keys to
  `TokenHealthConfig.contextWindows`. Codex never reaches this path (its entries carry the
  provider's own window). ⚠ pins current behaviour (the upward-adjust test).
- [ ] **`Data.firstNewlineIndex` has no lower-bound guard.** A `start < startIndex` gives a
  negative offset and an out-of-bounds `memchr`. Unreachable today; `guard start >= startIndex`
  costs nothing.

## Codex, auth and security

- [ ] **Callback hardening — one PR, one file cluster.** (a) Pass the expected state into
  `CodexCallbackServer.start` and deliver only on a match, so a local process cannot abort a
  sign-in by hitting `127.0.0.1:1455/auth/callback` first (denial of sign-in only; the forged
  code is never exchanged). (b) Per-connection timeout — `receive` has no deadline, so a
  connection that sends nothing holds an `NWConnection` to the 180 s session timeout.
  (c) Store and cancel the 180 s timeout task in `deliver`, so `cancelCodexAuthFlow` actually
  stops the clock. (d) `[weak session]` in the `server.start` closure. (e) `OneShotMailbox.value()`
  called twice overwrites the first continuation without resuming it — hangs that caller.
  (f) Claude's CSRF state compare is `==`, not `OAuthPKCE.constantTimeEquals` — inconsistent
  with the project's own standard. Write the Codex OAuth flow tests in this PR (below).
- [ ] **No test coverage of the Codex OAuth completion flow** — nothing exercises
  `completeCodexAuthFlow` (including the CSRF state-mismatch guard), the `registerCodexAccount`
  cap guard, or `registerCodexAPIKey`'s malformed-key and cap guards. **Approach:** combine with
  the inline test TODO about lifting the `URLProtocol` mock into a shared utility — the mock
  already exists in the concurrency tests. Lift it, give the manager an injectable store, and
  write these tests inside the callback-hardening PR, where the seam is needed anyway.
- [ ] **CLI import derives the account id from `tokens.account_id`, the OAuth flow from the
  `chatgpt_account_id` id_token claim.** If they diverge (workspace-scoped logins) the same
  real account lands twice — burning a cap slot, duplicating Keychain items, sending a header
  the endpoint may reject. Prefer deriving from the imported `id_token`, with the file field
  as fallback.
- [ ] **`CodexUsageParser` can infer "uncapped" from a partial payload.** A 200 body carrying
  `plan_type` with no `rate_limit` key parses to `uncapped: true, usedPercent: 0` and is cached
  — flipping a Plus/Pro popover to a single "Credits — no cap" bar at 0%. **Approach:** no
  product call needed. JSON distinguishes absent from explicit null: treat an *absent*
  `rate_limit` with no `spend_control` as a parse failure, so the cache keeps the last reading.
  `CodexCreditBudgetTests.noWindowsNoSpendControl_isUncappedCreditReading` uses an explicit
  null and stays green.
- [ ] **`used_percent` as a JSON string silently reads as 0%.** The window path accepts only
  `Int`/`Double`; a string value returns nil and `assemble` maps it to `utilization 0, status
  "allowed"`. Reuse the credit path's `number(_:)` helper for `used_percent` and the reset fields.
- [ ] **`AccountStore.update`'s duplicate-merge drops `codexAccessMode`** (it preserves
  `displayName`, `billingType`, `discoveredIdentity`). Unreachable today, but a future Codex id
  resolution would silently demote an `.apiKey` account to ChatGPT OAuth and send an `sk-…` key
  to the token endpoint. One field plus a test.
- [ ] **Identity resolution leaves id-keyed orphans.** Keychain, the account record, the ledger
  and the rate-limit cache are migrated when a `pending-<uuid>` resolves; the calibration keys
  (`aibattery_calibrated_*`), `setObservedModels`, the ledger bucket re-created by the same
  cycle's `merge`, and the notification latch keys are not. The resolved account starts
  uncalibrated until a poll lands in the 20–80% band. **Approach:** do not add three more
  one-off migrations — add one registry that every id-keyed store joins, driven from the single
  resolution point, so the next store is caught too.

## Performance

- [ ] **Reused read buffer** (`SessionLogReader`, `CodexSessionLogReader`). `FileHandle.read(upToCount:)`
  allocates a fresh `Data` per 64 KB chunk (~331 per 21 MB file) and the allocator retains it:
  measured ~479 MB launch footprint peak, Claude-only. Isolation test on one 21 MB file: shipping
  loop +26 MB retained, a reused buffer +5.2 MB and flat, identical wall time. The one measured
  memory win, independent of the tail parse — do it first.
- [ ] **Incremental tail parse for `SessionLogReader`.** A changed file is re-parsed from byte 0;
  the active session file (7–10 MB) is re-parsed on every debounced write (~95 ms). Keep a
  per-file byte offset + leftover buffer; full re-parse when the file shrinks, the offset is past
  EOF, or the head bytes changed. Risk: the append-only assumption vs. tool-call coalescing across
  lines — pin with the real-data timing tests before and after. Biggest CPU win, medium risk.
- [ ] **Footer timers run behind a closed popover.** `orderOut` never fires `onDisappear` (that is
  why `DeferredRenderState` exists) and `PopoverFooterView` sits outside the `deferredRender` gate,
  so `MarqueeText`'s scroll→pause→scroll chain cycles on the main queue during an incident and two
  10 s `TimelineView`s tick 24/7. **Approach:** pause on the panel-dismiss signal rather than moving
  the footer inside the gate — the gate defers heavy content and the footer should appear instantly.
- [ ] **The Claude reader still has no date bound** (the Codex side now skips date folders
  past `CodexSessionLogReader.retentionHorizonMonths`). Claude's all-time figures take a floor
  from *every* JSONL date, not just the stats-cache's, so dropping files older than ~13 months
  could visibly lower someone's all-time total — it needs the ledger high-water to be proven
  sufficient first. Original item, for reference:

- [ ] **Retained entries have no date bound.** The aggregator never looks past 12 months but both
  readers retain and re-scan everything (oldest retained Codex rollout is 7 months old; the Codex
  CLI never prunes). Skip files older than ~13 months at discovery. Safe because Codex all-time is
  a ledger high-water mark and the chart stops at 12 months; Codex rollouts carry the date in the
  filename, so no extra `stat` is needed for them.
- [ ] **`lastCorruptLineCount` is read on MainActor without the lock guarding its writes**
  (both readers, via `UsageViewModel.logCorruptionMetrics`). It is an `Int`, so the consequence is
  a wrong number in a log line, but it is a real race against the type's `@unchecked Sendable`
  invariant. Return the count as part of the read result.
- [ ] **`MarkCache` caches hits but not misses** — on a broken bundle every `ProviderBadge` body
  re-runs three `Bundle` lookups and up to three `fileExists` calls inside a SwiftUI `body`.
- [ ] **`aggregateOffMain`'s serialization only holds for the first waiter.** N callers queued
  behind one in-flight task resume together, each creates its own detached task, the last assignment
  wins and the `nil` clear can drop a newer caller's task. Safe (the locks inside `UsageAggregator`
  / `TokenLedger` hold) — wasted work, not corruption — but the comment claims serialization it does
  not deliver. Loop until the slot is free and clear only when the task is identical. Low priority.
- [ ] **`FileWatcher`'s 60 s fallback timer is never stopped** once `watchStatsCache` sets
  `fileSource`. Its tick now returns early unless a watcher actually failed, so the "re-aggregate
  forever" consequence is gone — what is left is a timer that never invalidates. One-line leak note.

## Insights, ledger and charts

- [ ] **"Throttled: N×" is global across every account and both providers** —
  `aibattery_throttleTimestamps` is a single unscoped array, so a Codex account's Insights panel
  reports throttles that only happened on a Claude account. The one cross-provider leak left in v3.
  **Approach:** store a dictionary keyed by account id under a new key and discard the legacy array
  (it is a 30-day trend, it self-heals). Note that the 3.2.0 changelog overclaims this as done: the
  state machine is per account, the timestamp store that Insights reads is not.
- [ ] **The 12M chart's current month is a projection rendered as actual** — from day 4 it plots
  `total × daysInMonth / dayOfMonth` with the same styling as the 11 real months, can tower over
  them and squash the shared Y axis, and the tooltip states it flatly. Fix: dash the final segment
  and suffix the tooltip with "(projected)". ⚠ pins current behaviour (a test asserts the projected
  value).
- [ ] **The trend "meaningful baseline" threshold is calibrated for message counts, not tokens** —
  1 000 tokens is 0.003% of a normal day here, so one stray hook session yields ">999% vs yesterday"
  instead of the suppression the threshold exists to provide. **Approach:** make it relative (a
  fraction of the trailing daily average) rather than a fixed 5M calibrated to one machine.
- [ ] **Project rows are keyed by full `cwd`, labelled by leaf, with no tooltip and no symlink
  resolution** — two different `api` directories are indistinguishable and a git worktree splits
  its parent project. **Approach:** no shelling out needed — a worktree's `.git` is a file whose one
  line points at the parent repo; group by that, and resolve symlinks. This also decides the
  Projects beta badge: ship this and remove the badge, or keep the badge as the open item.
- [ ] **Non-deterministic tie-breaks** in `hourCounts`, `weekdayTotals` and the session list (the
  month peak is deterministic now) — they visibly shuffle between polls. Sort by key on ties.
- [ ] **A corrupt `token-ledger.json` is swallowed silently and then overwritten**, destroying all
  pre-rotation high-water history for every account. Atomic writes make it unlikely; it still
  deserves a `.corrupt-<timestamp>` rename and a warning log.
- [ ] **Dead code:** `dailyAverage` and `trendDirection` are computed every cycle, reach no view,
  and are index-based so they would be wrong on sparse history. Delete. Likewise the unreachable
  "Need 30+ days of data" empty state (the chart always returns 12 zero-filled points) — delete
  the dead branch rather than trying to reach it.

## Views and settings

- [ ] **A persisted `7d` metric mode orders the Credits / API-Limits bar second on a Codex credit
  account.** `UsagePopoverView` renders `EmptyView()` for `.sevenDay` when the kind collapses while
  `MetricToggleView` keeps the stored selection highlighted. Normalise `metricModeRaw` to
  `.fiveHour` when the active account's kind collapses.
- [ ] **Settings renders an empty row at 3 Claude + 3 Codex accounts** — both `LinkActionButton`s
  are behind `canAddAccount(provider:)`, so at the cap the `HStack` is two spacers. Wrap the row in
  `canAddAccount(.claude) || canAddAccount(.codex)`.
- [ ] **A missing provider is drawn as the Claude brand mark** in `MenuBarMultiAccountText`
  (`providers[id] ?? .claude`). Defensive only; skip the id instead of defaulting.
- [ ] **The offline API-key notice is rendered as a red error.** `AuthView` sets `errorMessage` for
  `validation == .unknown`, whose own comment says "not a failure", and `registerCodexAPIKey` has
  already succeeded — so the overlay is torn down before it is read. **Approach:** show nothing on
  the inconclusive case. The account is added and the next poll surfaces the real state through the
  existing error surfaces; no new notice state or footer plumbing.
- [ ] **"Full account email in popover" is Codex-only in practice** — Claude's discovered identity
  is a workspace name, deliberately never masked. **Approach:** hide the toggle when no Codex
  account exists, rather than appending "(Codex accounts)".
- [ ] **"Credits are unlimited" can become invisible** — the badge was correctly removed from the
  budget header, but `CreditBalanceRow` renders only when a balance exists, so `unlimited: true,
  balance: null` shows it nowhere.
- [ ] **`useMulti` is still gated on `perAccount.count`** while the worst/throttled/countdown scans
  moved to `order` — an empty `order` with ≥2 stale `perAccount` entries renders an empty menu-bar
  string.
- [ ] **The `@ScaledMetric` popover width is dead code** — the parent pins the frame to 275 pt, so
  the documented "width scales with system text size" never happens. **Approach:** decide now —
  delete the scaled metric and own the fixed width, since the panel frame is fixed anyway.
- [ ] **Small cleanups:** `PopoverHeaderView.planLabel` is a forwarder with no production caller;
  `CodexUsageParser.parseUsageResponse`/`planType` are test-only wrappers around the one-pass
  `parseUsage`; the 1-hour fallback token expiry (`3_600`) is duplicated between the Claude and
  Codex refresh paths and absent from `spec/CONSTANTS.md`;
  `AccountRecordTests.discoveredIdentity_roundTripsAndDefaultsToNilForLegacyJSON` is mislabelled —
  its "legacy" fixture includes `"provider":"claude"`, so drop that key.

## Accessibility

- [ ] **The menu-bar status item never says what the number means, or that you are throttled.**
  Provider glyphs are spoken as names now; the metric name, the raw `"42% | 23%"` separator, the
  literal `—`, and the exhausted state in the multi-account branch are still unhandled. Build the
  spoken string from the `Display` struct — pure and testable. Relatedly, a colour-blind user with
  2+ accounts has no non-colour throttle cue (the countdown prefix exists only in the
  single-account branch).
- [ ] **All four bar fills are under 3:1 against their track in light mode** (green 1.47, orange
  1.48, red 2.39; dark mode is fine). Raise the light `trackFill` alpha to ~0.30 and accept the
  test fallout.
- [ ] **The colourblind palette is manual-only** and ignores
  `NSWorkspace.accessibilityDisplayShouldDifferentiateWithoutColor`. OR it into the manual toggle.
- [ ] **Smaller:** "Check for Updates" gives VoiceOver no feedback (copy the auto-mode announcement
  pattern); tooltip-only data (plan type, reset time, provenance) never reaches VoiceOver because
  `.help()` does not populate it; fixed-height error containers truncate long errors with no
  tooltip and no text selection, so the user cannot recover the message to report it; `MarqueeText`
  clips at a fixed 14 pt against a font that scales; `TrendDirection.accessibilityLabel` is dead
  code while the view hard-codes the arrow glyphs; the footer status dot is double-labelled; one
  raw `.font(.system(size:` literal remains; "reached"/"depleted"/"exhausted" are three verbs for
  one state.

## Tests and CI

- [ ] **`release.yml` runs `swift test` in parallel.** CI passes `--no-parallel` because of the
  AppKit `dispatch_once` deadlock (~1 in 2 local runs before the flag); the release workflow does
  not, so a tag push can hang on the same race. One line, real downside if left.
- [ ] **The pricing drive-through test covers Opus 4.x only.** Sonnet and Haiku minors past 4.5 are
  not driven through `pricing(for:)`, so a generation-wide key could still shadow a future minor.
- [ ] **Claude 3 Haiku has no pricing row** and bills at the Haiku family rate ($1/$5). Its launch
  rate was $0.25/$1.25 per million — confirm against an archived copy of the pricing page before
  adding the row.

## Blocked

- [ ] **`com.apple.security.cs.disable-library-validation` on the release bundle** — blocked on the
  Developer ID certificate. Release builds sign ad-hoc when the secret is empty, and an ad-hoc
  signature has no Team ID, so library validation cannot pass and Sparkle would fail to load:
  removing it now breaks every shipped build. **Approach:** have `build-app.sh` strip the
  entitlement only when a real signing identity is set, then test once the cert lands. Verify the
  ad-hoc claim with one local build first.
- [ ] **Swift 6 language-mode flip** (all three targets are `.v5` + strict concurrency) — blocked by
  the macOS 13 deployment target: isolated `deinit` needs newer runtime availability. Revisit when
  the target moves.

## Decided not to do

Kept so they are not re-litigated.

- **Session-log fallback inspects only the newest rollout.** With two ChatGPT accounts the one whose
  CLI session is newest gets the fallback and the other serves its cache. Outage × two accounts is
  an edge of an edge — won't-fix unless someone reports it.
- **Test-deadlock "proper fix" (pre-warm AppKit before any suite).** Swift Testing has no global
  setup hook, so it cannot be guaranteed. `--no-parallel` at 12 s is the answer; the open half is
  the release workflow above.
- **Legacy unified-header unit question** (fraction vs. percentage). The 2026-10-18 header-capture
  run logged 19 responses and none carried a unified header key — the header parser is unreachable
  in practice. A note on the parser, not an investigation.
- **`estimatedTimeToLimit` window-length guard.** Unreachable: every `isCreditBudget` reading routes
  to `CreditBudgetSection`, which never calls it.
- **Keychain accessibility migration skipping Codex key names.** Every Codex item is created through
  `KeychainHelper.add`, which always sets the correct attribute, and the one-shot flag is already set
  everywhere.
- **`CodexAccessMode.chatgpt` is never constructed** (nil means ChatGPT on persisted records). Leave it.
- **`busiestDayOfWeek` averages over active days only.** Definitional, not a bug.
- **Hand memory back after scans / intern cached strings.** 85 MB resident for a menu bar app is fine;
  the reused read buffer above is the measured win.
- **June persist-write coalescing and per-body window-token reductions.** Unmeasured and tiny.
- **Aggregator CoW / array churn.** Full pass is 19 ms; the suspect operations measure under 1 ms each.
- **Blanket `fixedSize` and `Typography` sweeps.** Too broad to land safely; the specific clipping
  cases are listed under Accessibility.
- **The unshipped "Phase 4" file splits.** Their targets were split other ways; every file is under
  the 800-line ceiling.
