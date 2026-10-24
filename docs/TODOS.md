# Deferred work

Open items that were consciously deferred, grouped by the review that deferred them. Each item names the file or type involved so it can be picked up cold. Shipped items are removed rather than struck through; the history is in `CHANGELOG.md`.

## Deferred from the third pre-release review (2026-10-10)

Verified against the source and judged not worth changing on the release branch.
Each says why, so a future session doesn't re-litigate it.

- [ ] **`CodexUsageParser` can infer "uncapped" from a partial payload.** A 200
  body carrying `plan_type` but no `rate_limit` at all (schema change, account
  mid-migration, truncated-but-valid JSON) parses to `uncapped: true,
  usedPercent: 0`, is accepted as `.success`, cached and persisted — flipping a
  Plus/Pro popover from 5h/Weekly bars to a single "Credits — no cap" bar at 0%.
  There is no "did this plan previously report windows?" sanity check. Needs a
  product call on whether an uncapped budget should ever be inferred without an
  explicit `spend_control`, so it is not a mechanical fix.
- [ ] **`used_percent` as a JSON string silently reads as 0%.** The window path
  accepts only `Int`/`Double`; a string-encoded value returns nil and `assemble`
  maps that to `utilization 0, status "allowed"`. The credit path two functions
  away already tolerates string-encoded numbers. Not observed from OpenAI — the
  fix is to reuse the credit path's `number(_:)` helper for `used_percent` and
  the reset fields.
- [ ] **CLI import derives the account id from `tokens.account_id`, the OAuth
  flow from the `chatgpt_account_id` id_token claim.** If those ever diverge
  (workspace-scoped logins are the obvious candidate) the same real account
  lands twice — burning a cap slot, duplicating Keychain items, and sending a
  header the endpoint may reject. `isPlausibleAccountId` now validates the
  shape, not the source. Prefer deriving from the imported `id_token` with the
  file's field as fallback.
- [ ] **`CodexCallbackServer` has no per-connection timeout.** `receive` has no
  deadline, so a local process that connects to 127.0.0.1:1455 and sends
  nothing holds an `NWConnection` until the 180 s session timeout. Loopback-only
  and time-bounded; arm a `queue.asyncAfter` cancel per connection. Related to
  the already-deferred request-line accumulation item above.
- [ ] **Session-log fallback inspects only the newest rollout.** With two ChatGPT
  accounts the one whose CLI session is newest gets the fallback and the other serves
  its cache. A per-account newest-file search (walk newest-first, head-read until a
  matching `creator_account_id`, bounded to ~20 files) would give both accounts a
  reading. Deferred from v3.3.0: outage × two accounts is an edge of an edge.
- [ ] **A persisted `7d` metric mode orders the Credits / API-Limits bar second
  on a Codex credit account.** `UsagePopoverView` renders `EmptyView()` for
  `.sevenDay` when the kind collapses while `MetricToggleView` keeps the stored
  selection highlighted. All sections still render (only the order shifts).
  Normalise `metricModeRaw` to `.fiveHour` when the active account's kind
  collapses.
- [ ] **No test coverage of the Codex OAuth completion flow.** Nothing exercises
  `completeCodexAuthFlow` (including the CSRF state-mismatch guard), the
  `registerCodexAccount` cap guard, or `registerCodexAPIKey`'s malformed-key and
  cap guards — only the pure helpers extracted from that file are tested. Needs
  a stubbable `AccountStore`/`storeTokens` seam, which is a refactor rather than
  a test addition.
- [ ] **Small cleanups:** `PopoverHeaderView.planLabel` is a forwarder with no
  production caller (only a test); `CodexAccessMode.chatgpt` is never
  constructed (nil means ChatGPT on persisted records); `CodexUsageParser`'s
  `parseUsageResponse`/`planType` are now test-only wrappers around the one-pass
  `parseUsage`; the 1-hour fallback token expiry (`3_600`) is duplicated between
  the Claude and Codex refresh paths and absent from `spec/CONSTANTS.md`.

## Deferred from the fourth pre-release review (2026-10-10)

Found and verified against source in the fourth pass. The correctness bugs from that
pass were fixed on the release branch; everything below was triaged as not worth the
regression risk before tagging v3.0.0. Each says why.

### Views

- [ ] **The offline API-key notice is rendered as a red error.** `AuthView.swift`
  sets `errorMessage` for the `validation == .unknown` case, whose own comment says
  "not a failure" — it lands in the danger-coloured `exclamationmark.triangle` surface.
  Worse, `registerCodexAPIKey` has already succeeded by then, so `AccountStore.$accounts`
  fires and the overlay is torn down, probably before it is read. Needs a separate
  `noticeMessage` state in a caution style, surfaced on the popover footer rather than
  on a view that is about to disappear. CHANGELOG promises "added with a note".
- [ ] **Settings renders an empty row at 3 Claude + 3 Codex accounts.** Both
  `LinkActionButton`s in the add-account row are behind `canAddAccount(provider:)`, so at
  the cap the `HStack` is just two spacers — a bare gap above "Up to 3 accounts per
  provider." Wrap the row in a `canAddAccount(.claude) || canAddAccount(.codex)` guard.
- [ ] **A missing provider defaults to the Claude brand mark** in the menu bar
  (`MenuBarMultiAccountText`, `providers[id] ?? .claude`). Defensive only — the map is
  built from all accounts — but an unknown id should be skipped, not drawn as Claude.
- [ ] **"Full account email in popover" is Codex-only in practice.** Claude's discovered
  identity is a workspace name, which is deliberately never masked, so the toggle does
  nothing for a Claude-only user and reads as broken. Append "(Codex accounts)".

### Concurrency / lifecycle

- [ ] **`aggregateOffMain`'s serialization only holds for the first waiter.** N callers
  queued behind one in-flight task all resume together and each then creates its own
  detached task; the last assignment wins and the others become untracked, and the
  `nil` clear can drop a newer caller's task. The locks inside `UsageAggregator` /
  `TokenLedger` keep it safe — this is wasted work and last-writer-wins on the cached
  snapshot, not corruption — but the comment claims serialization it does not deliver.
  Loop until the slot is free and only clear when the task is identical.
- [ ] **`lastCorruptLineCount` is read on MainActor without the lock guarding its
  writes** (`CodexSessionLogReader`, `SessionLogReader`, read from
  `UsageViewModel.logCorruptionMetrics`). Written on the detached aggregation thread.
  It is an `Int`, so the consequence is a wrong number in a log line, but it is a real
  race and contradicts the type's stated `@unchecked Sendable` invariant. Return the
  count as part of the read result instead.
- [ ] **`FileWatcher`'s 60 s fallback timer is never stopped once the stats-cache watcher
  recovers.** Started when `fileSource == nil` at launch (common for a Codex-only user);
  `watchStatsCache` later sets `fileSource` but nothing invalidates the timer, so the app
  keeps a 60 s re-aggregate on top of working FSEvents forever.
- [ ] **`CodexAuthSession` leaks its 180 s timeout task on the success path**, and
  `begin()` captures the session strongly in the `server.start` closure (session → server
  → handlers → session). Both self-heal on every normal path — `deliver` stops the
  listener, and the timeout task holds `self` weakly — but `cancelCodexAuthFlow` does not
  actually stop the clock. Store and cancel the task in `deliver`; use `[weak session]`.
  Related: `OneShotMailbox.value()` called twice overwrites the first continuation
  without resuming it, hanging that caller. Latent (one caller today).

### Data

- [ ] **`fiveHourWindowTokens` includes one 15-minute bucket from before the window
  started.** `startBucket` is computed as `20 - (Int(elapsed / 900) + 1)`; the first
  in-window bucket is `ceil(remaining / 900)`. Up to 15 minutes of pre-window tokens
  inflate the "tokens in window" figure under the bar.
- [ ] **`sevenDayWindowTokens` over-counts by up to a full calendar day.**
  `windowStartKey` is day-granular (`yyyy-MM-dd`) and compared with `>=`, so the whole
  of the window's first day is summed even when the window starts mid-day.
- [ ] **The 1 MB oversized-line cap counts one line as ~5 corrupt and emits a bogus
  trailing fragment.** The branch fires per 64 KB chunk read, so a single oversized line
  is discarded and counted repeatedly, then the sub-1 MB remainder is passed to
  `process()` as if it were a line. Observed on the real tree: 36 lines exceed 1 MB, the
  largest 4.2 MB. No token data is lost and no message content escapes — the only effect
  is a ~5x over-reported corruption count in a log line. Use a
  `discardingOversizedLine` flag that swallows bytes to the next newline.
- [ ] **`Data.firstNewlineIndex` has no lower-bound guard.** A `start < startIndex` would
  give a negative offset and an out-of-bounds `memchr`. Unreachable today (every call site
  passes `startIndex + n`, `n >= 0`), but `guard start >= startIndex` costs nothing.
- [ ] **`estimatedTimeToLimit` has no window-length guard**, unlike
  `withClearedRolloverArtifacts`, so it would project nonsense from a monthly credit
  reset. Unreachable — every `isCreditBudget` reading routes to `CreditBudgetSection`,
  which never calls it. Worth a comment pinning that invariant.

### Persistence

- [ ] **`AccountStore.update`'s duplicate-merge preserves `displayName`, `billingType`
  and `discoveredIdentity` but drops `codexAccessMode`.** Unreachable today (the merge
  branch needs `newRecord.id != oldId`, which only the Claude pending→org path produces),
  but a future Codex id resolution would silently demote an `.apiKey` account to ChatGPT
  OAuth and send an `sk-…` key to the token endpoint.
- [ ] **`AccountRecordTests.discoveredIdentity_roundTripsAndDefaultsToNilForLegacyJSON`
  is mislabelled** — its "legacy" fixture includes `"provider":"claude"`, so it is not a
  v2.6.1 blob. The genuine v2 shape is covered by `AIProviderTests`; only the fixture is
  misleading. Drop the key from it.

### Security

Full pass found no credential leak: no token, key, PKCE verifier or state reaches a log,
UserDefaults or an error message; Keychain items are `WhenUnlockedThisDeviceOnly`,
one per account, deleted before the record on sign-out; no TLS override or ATS exception
exists anywhere; the callback listener binds `127.0.0.1` explicitly; provider error text
is laundered through a fixed allowlist. Remaining items:

- [ ] **`com.apple.security.cs.disable-library-validation` is still set** on the release
  bundle. It lets the process holding live tokens load dynamic libraries signed by any
  identity — relevant because `/Applications` is group-admin writable. `build-app.sh`
  already re-signs `Sparkle.framework` and its XPC services with the same identity as the
  outer bundle, which is the condition under which library validation passes, so the
  entitlement is probably removable. Not touched before a release: it needs a real
  Sparkle-still-loads test, ideally alongside notarization.
- [ ] **Any local process can abort a Codex sign-in** by hitting
  `127.0.0.1:1455/auth/callback` with any `code` and `state` first: the one-shot mailbox
  delivers and stops the listener *before* the CSRF state is compared (that happens in
  `OAuthManager+Codex`), so the real redirect lands on a dead port. Denial of sign-in
  only — the forged code is never exchanged and 32 CSPRNG bytes are unguessable. Fix by
  passing the expected state into `CodexCallbackServer.start` and only delivering on a
  match. Pairs naturally with the already-deferred listener `.ready` item.
- [ ] **Claude's CSRF state comparison is not constant-time** (`==`), unlike the Codex
  path's `OAuthPKCE.constantTimeEquals`. No realistic attack — the value is pasted into a
  local text field and there is no remote timing oracle — reported only as an
  inconsistency with the project's own standard.
- [ ] **The Keychain accessibility migration skips Codex key names** (it builds
  `refreshToken_<id>`, never `refreshToken_codex_<id>`). Not exploitable: every Codex item
  is created through `KeychainHelper.add`, which always sets the correct attribute. It
  matters only if a future accessibility change reuses this one-shot migration, whose flag
  will already be set. Loop over `tokenStorageKey` instead.

### Docs

A full spec/code audit found **no wrong constant values and no version drift** — the
~70 CONSTANTS.md values spot-checked all match source, and 3.0.0 is consistent across
`Info.plist` and the CHANGELOG. The defects are omissions and stale
references. Most user-facing first:

## Deferred from the fifth pre-release review (2026-10-10)

A fifth pass swept dimensions the earlier four had not: performance/battery, the
Claude-side logic (which three passes had skipped in favour of the new Codex code),
accessibility, Insights/ledger/charts, and an adversarial regression review of that
session's own changes. The correctness, contrast and perf items that earned it were
fixed; the rest is below. Measurements are from the real trees on the dev machine
(1722 Claude JSONL / 380 MB, 863 Codex rollouts / 542 MB).

### Performance (all measured)

- [ ] **Both aggregators are invalidated on every FS event, whichever provider wrote.**
  `UsageViewModel+Lifecycle` calls `aggregator.invalidate()` and
  `codexAggregator.invalidate()` unconditionally, though `FileWatcher` already knows
  which reader changed (`PendingInvalidations`) — `onChange` is `() -> Void` and
  carries none of it. Costs a full ~19 ms re-aggregate over 7 654 entries producing a
  byte-identical snapshot, per burst, whenever the other provider's CLI writes. The
  redundant-aggregation fingerprint cache would have caught it, but `invalidate()`
  nils `cachedSnapshot` ahead of it. Fix: make `onChange` take `PendingInvalidations`.
- [ ] **~479 MB launch footprint peak** (measured `phys_footprint_peak` on the live
  app, Claude-only account; both providers would be ~900 MB). Cause is
  `FileHandle.read(upToCount:)` allocating a fresh `Data` per 64 KB chunk — ~331 per
  21 MB file — which the allocator retains. Peak `leftover` is only 2.16 MB, so the
  streaming discipline is sound. An isolation test on one 21 MB file: shipping loop
  +26 MB retained, a reused buffer +5.2 MB and flat. Wall time identical, so this is
  memory-only. Fix: one reused buffer per file instead of a `Data` per chunk.
- [ ] **The Codex reader copies every line in full before the 512-byte prefilter
  rejects it** (`CodexSessionLogReader`, `Data(leftover[..<newlineIndex])`). Largest
  measured line is 4.26 MB; ~560 MB of copying per cold scan, feeding the allocator
  churn above. The Claude reader already does this right — it slices and only
  materialises `Data` at the decode call. Fix: pass the slice.
- [ ] **`MarqueeText` and two `TimelineView`s keep running behind a closed popover.**
  The codebase documents that `orderOut` never fires `onDisappear` (that is why
  `DeferredRenderState` exists), but `PopoverFooterView` is rendered *outside* the
  `deferredRender` gate — so the ticker's scroll→pause→scroll chain cycles on the
  main queue indefinitely during an incident, and the 10 s `TimelineView` ticks run
  24/7 including while polling is idle-suspended. Individually trivial, but it stops
  the process ever going quiet, which is what the energy-impact metric penalises.
  Fix: move the footer inside the gate, or cancel on the panel-dismiss notification.
- [ ] **Retained entries have no date bound.** The aggregator never looks past 12
  months but both readers retain and re-scan everything; the oldest retained Codex
  rollout is 7 months old and the Codex CLI never prunes. Skipping files older than
  ~13 months at discovery would cut the cold scan, the per-cycle stat sweep and the
  footprint spike proportionally.
- [ ] **`MarkCache` caches hits but not misses** — on a broken bundle every
  `ProviderBadge` body re-runs three `Bundle` lookups and up to three
  `fileExists` calls, i.e. filesystem work inside a SwiftUI `body`.

Backlog verdicts from the same pass, so they are not re-litigated: **tail-parse** is
real but lower priority than the above (re-parse is already incremental per file; the
largest active file costs ~38 ms, less than the overhead that used to sit in front of
it); **aggregator CoW/array churn** is not worth fixing (full pass 19 ms; the suspect
operations measure under 1 ms each); **per-call date formatters** are already fixed —
every formatter in the tree is a `static let`.

### Insights / ledger / charts

- [ ] **A session ending on a `<synthetic>` entry reports 0% context, green.**
  `TokenHealthMonitor` takes `sessionEntries.last` for both the model and the context
  estimate, and synthetic entries (Claude Code's interrupt/error pseudo-messages)
  carry all-zero usage — verified: max per-turn total for `<synthetic>` is 0. A
  session at 700K/1M drops to "0%, 1,000,000 remaining" the moment the user hits Esc,
  and auto-mode can never escalate on it. ~0.4% of sessions end this way. Fix: pick
  the last entry that passes `isTrackedModel`.
- [ ] **The context-window tier bump halves the percentage exactly when context is
  most critical** — crossing the window doubles the denominator, so 199K/200K (99.5%,
  red) becomes 201K/500K (40%, green) and the warning vanishes as the session gets
  worse. Related: the comment claims the percentage is against 80% of the raw window,
  but `usableContextRatio` is 1.0. Also `TokenHealthConfig.contextWindows` has no
  Claude 5 entries, so they all take the 1M default — correct for 1M-context accounts,
  5x too generous for anyone not on it.
- [ ] **"X in 12m" and "Peak: <Month>" are computed over all history, not 12 months** —
  both reduce over the unbounded `dailyTokenTotals`, so a long-retention user sees a
  12-month total that does not match the 12 points on the chart, and a peak month that
  is not on it (and has no year, so it is ambiguous with an on-chart month).
- [ ] **The 12M chart's current month is a projection rendered as actual** — from day
  4 it plots `total × daysInMonth / dayOfMonth` with the same styling as the 11 real
  months, and the tooltip states it flatly ("Oct — 930M tokens") for tokens not yet
  spent. It can also tower over every real month and squash the shared Y axis, and it
  disagrees with the unprojected stat beside it. Fix: dash the final segment and
  suffix the tooltip with "(projected)".
- [ ] **"Throttled: N×" is global across every account and both providers** —
  `aibattery_throttleTimestamps` is a single unscoped array, so a Codex account's
  Insights panel reports throttles that only ever happened on a Claude account.
  Exactly the cross-provider leak the rest of v3.0.0 avoids. Key it per account.
- [ ] **The trend "meaningful baseline" threshold is calibrated for message counts,
  not tokens.** 1 000 tokens is 0.003% of a normal day here (~30M), so a single stray
  hook session clears it and the user sees ">999% vs yesterday" instead of the
  suppression the threshold exists to provide. Raise to ~5M.
- [ ] **Smaller:** the "Need 30+ days of data" empty state is unreachable (the chart
  always returns 12 zero-filled points); project rows are keyed by full `cwd` but
  labelled by leaf with no tooltip and no symlink resolution, so two different `api`
  directories are indistinguishable and a git worktree splits its parent project;
  several top-N/peak selections (`hourCounts`, `monthTotals`, `weekdayTotals`, the
  session list) tie-break non-deterministically and visibly shuffle between polls;
  `busiestDayOfWeek` averages over active days only, so one outlier day wins; a
  corrupt `token-ledger.json` is swallowed silently and then overwritten, destroying
  all pre-rotation high-water history for every account (atomic writes make this
  unlikely, but it deserves a `.corrupt-<timestamp>` rename and a warning log);
  `dailyAverage` and `trendDirection` are computed every cycle, reach no view, and are
  index-based so they would be wrong on sparse history if ever surfaced.

### Claude-side

- [ ] **The v3 `elapsed >= 0` guard disables rollover-artifact suppression under clock
  skew.** Its stated motivation (monthly credit budgets) is already handled by the
  `isCreditBudget` short-circuit added in the same commit, and Codex windowed readings
  carry real window lengths — so the guard only bites Claude, where window length is
  assumed. A Mac whose clock is a couple of minutes behind the server after wake makes
  `elapsed` negative on a just-rolled 7-day window, the near-full lagging reading is
  no longer suppressed, and on a cold start the spike filter has no previous value to
  hold — so the popover paints "Limit reached" on a freshly reset window. This is the
  v2.4.2 bug class returning through a new door. No test covers negative `elapsed`
  either way. **Deliberately not changed here**: the rollover/spike logic is the most
  delicate code in the app and has its own regression history; it wants its own PR
  with tests for the skew case.
- [ ] **Identity resolution renames the account mid-cycle, but the rest of the cycle
  keeps writing under the dead `pending-<uuid>`.** Keychain, the account record, the
  ledger and the rate-limit cache are all migrated; the calibration keys
  (`aibattery_calibrated_*`), `setObservedModels`, the ledger bucket re-created by the
  same cycle's `merge`, and the notification latch keys are not. The orphans are never
  pruned, and the resolved account starts uncalibrated until a poll lands in the
  20–80% band. Pre-existing, but v3 added two more id-keyed stores on top of it.
- [ ] **`PlanTier.decodeCounts` is a test-only counter that is never trimmed**, unlike
  the `decodedAccounts` cache beside it — it retains every distinct accounts JSON blob
  as a dictionary key for the process lifetime. Tiny, but unbounded by construction.

### Accessibility

Fixed this round: the light-mode 50–80% bar contrast, dark-mode `tertiaryLabel`,
Reduce Motion on the marquee, the `CreditBalanceRow` overflow, the metric picker not
being an accessibility container, and the slider announcing "infinity". Remaining:

- [ ] **All four bar fills are under 3:1 against their track in light mode** (green
  1.47, gold now improved, orange 1.48, red 2.39). Dark mode is fine. Raising the
  light `trackFill` alpha to ~0.30, or outlining the fill, lifts them past 3:1 without
  touching the palette. Deferred because it has test fallout.
- [ ] **The colourblind palette is manual-only** and ignores
  `NSWorkspace.accessibilityDisplayShouldDifferentiateWithoutColor`, so a user who has
  already set it system-wide gets the standard palette until they find the checkbox.
- [ ] **The menu-bar status item never says what the number means, or that you are
  throttled.** VoiceOver reads "AI Battery, 63%" with no metric name, reads the raw
  `"42% | 23%"` separator string for multiple accounts, speaks `—` literally, and
  never announces the exhausted state in the multi-account branch. Build the spoken
  string from the `Display` struct — a pure, testable change. Relatedly, a colour-blind
  user with 2+ accounts has no non-colour throttle cue, because the countdown prefix
  exists only in the single-account branch.
- [ ] **The `@ScaledMetric` popover width is dead code** — the parent pins the frame to
  a hard 275pt, so the documented "width scales with system text size" never happens,
  and at a scaled size the content is clipped by the panel edge rather than reflowed.
  Pick one: drop the parent frame, or delete the ScaledMetric and own 275 honestly.
- [ ] **Smaller:** "Check for Updates" gives VoiceOver no feedback (the result row
  auto-dismisses in 2.5 s with no announcement — copy the pattern already used for
  auto mode); tooltip-only data (plan type, reset time, provenance) never reaches
  VoiceOver since `.help()` does not populate it; fixed-height error/empty containers
  truncate long errors with no tooltip and no text selection, so a user cannot recover
  the message to report it; `MarqueeText` clips at a fixed 14 pt against a font that
  scales; `fixedSize` is applied to only 7 of ~20 wrapping texts; `Typography` mixes
  fixed-pt and text-style tokens within single rows, which shear under scaling;
  `TrendDirection.accessibilityLabel` is dead code while the view hard-codes the raw
  arrow glyphs; the footer status dot is double-labelled; one raw `.font(.system(size:`
  literal remains; and "reached"/"depleted"/"exhausted" are three verbs for one state.

### From the regression review of this round's own changes

- [ ] **`useMulti` is still gated on `perAccount.count`** while the worst/throttled/
  countdown scans moved to `order`. An empty `order` with ≥2 stale `perAccount`
  entries renders an empty menu-bar string. Narrow, but gratuitously inconsistent.
- [ ] **"Credits are unlimited" can become invisible** — the badge was correctly
  removed from the budget header, but `CreditBalanceRow` renders only when a balance
  exists, so `unlimited: true, balance: null` shows it nowhere. Cosmetic: `isUncapped`
  still yields "no cap" in that case.
- [ ] **The pricing ordering test compares table keys only**, so it cannot catch a key
  shadowing a *display name that has no row of its own* — the generation-wide `opus 4`
  / `sonnet 4` / `haiku 4` keys would swallow a future 4.x minor before the family
  fallback is reached, and `opus 4` carries the retired $15/$75. Add a second
  assertion driving real model ids through `pricing(for:)`.
- [ ] **Claude 3 Haiku has no row** and now bills at the Haiku family rate ($1/$5)
  rather than its own retired rate. Anthropic no longer publishes pricing for fully
  retired models, so the correct figures could not be sourced — left as the family
  approximation rather than guessed. Sonnet 3/3.7 *were* resolvable ($3/$15 across
  every published Sonnet from 3 to 4.6) and now have a row.

## Performance (deferred from the v3.3.0 release, 2026-10-22)

Measured on the running 3.3.0 build: 11 MB bundle, 0 % idle CPU with ~5 % blips when a session log is written, 85 MB resident of which 32 MB is live heap (≈ 35 k cached entries + strings); the rest is freed-but-dirty allocator pages from scan peaks. Logs: 607 MB / 2 412 Claude files, 924 MB / 1 252 Codex files.

- [ ] **Incremental tail parse for `SessionLogReader`.** A changed file is re-parsed from byte 0; the active session file (7–10 MB) is re-parsed on every debounced write (~95 ms). Keep a per-file byte offset + leftover buffer; full re-parse when the file shrinks, the offset is past EOF, or the head bytes changed. Risk: append-only assumption vs. tool-call coalescing across lines — pin with the real-data timing tests before/after. Biggest CPU win; medium risk.

- [ ] **Hand memory back after scans.** Sort in place instead of copying, drop raw per-file arrays earlier, `malloc_zone_pressure_relief` after a cold scan. Expected 85 → ~50 MB resident. Low risk, mostly cosmetic.

- [ ] **Compact cached entries.** Intern repeated strings (session id, cwd, model, branch); hash message ids in the global dedupe set (keep full ids per file). ~5–7 MB. Smallest payoff, most invasive — only if memory becomes a complaint.

- [ ] **Test runner deadlock (infra).** Parallel `swift test` hung ~1 in 2 local runs (AppKit `dispatch_once` raced from the pool; traces: `git show 8f3d600:docs/reviews/2026-10-21-test-deadlock-sample.txt`). CI now runs `--no-parallel` (12 s). Proper fix: pre-warm AppKit on the main thread before any suite, then drop the flag.
