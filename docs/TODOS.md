# Deferred work

Open items, grouped by area and ordered by priority inside each group. Every item names
the file or type involved so it can be picked up cold, and says which approach was chosen
when the obvious fix is not the right one. Shipped items are removed rather than struck
through; the history is in `CHANGELOG.md`.

Triaged 2026-10-31 against source, and the queue was then worked top-down — everything
the triage marked "do" is in `CHANGELOG.md` for the next release. What is left is below:
one product decision, two blockers that need a certificate or a newer deployment target,
and the verdicts kept so they are not re-litigated.

## Open

- [ ] **Decide the Projects "beta" badge.** The badge says per-project attribution "is still
  being refined". Its concrete half shipped: rows now group by `ProjectIdentityResolver`
  (symlinks resolved, a git worktree folded into its parent repo) and the full path is the
  row's tooltip and VoiceOver hint. What remains is inherent rather than unfinished — local
  logs are machine-wide per provider, so a project's usage cannot be split per account. Either
  the badge comes off, or it stays with that sentence as its tooltip. **Kyle's call, not a
  code change.**

## Blocked

- [ ] **Verify library validation once the Developer ID certificate lands.**
  `build-app.sh` now strips `com.apple.security.cs.disable-library-validation` whenever
  `CODE_SIGN_IDENTITY` is a real identity (ad-hoc builds keep it — an ad-hoc signature has no
  Team ID, so validation could never pass and Sparkle would not load). The ad-hoc path is
  verified; the signed path cannot be tested without the certificate. When it arrives: build a
  signed bundle, confirm Sparkle still loads and an update still installs, then delete this
  item. `KEEP_LIBRARY_VALIDATION_EXEMPTION=1` is the escape hatch if it turns out to be needed.

- [ ] **Swift 6 language-mode flip** (all three targets are `.v5` + strict concurrency) —
  blocked by the macOS 13 deployment target: isolated `deinit` needs newer runtime
  availability. Revisit when the target moves. One warning is already visible in every build
  (`MenuBarIcon.markScale` referenced from a nonisolated context).

## Decided not to do

Kept so they are not re-litigated.

- **A retention horizon for the Claude reader**, mirroring `CodexSessionLogReader`. Measured on a
  real tree 2026-10-31 and the premise does not hold: Claude Code prunes its own session logs, so
  there is nothing for a horizon to skip. 2700 files / 755 MB, and the oldest is 46 days old
  (`find ~/.claude/projects -name '*.jsonl' -mtime +45` → 0; the cliff is at ~45 days, with only 3
  files past 40). A 13-month filter would skip zero files and save zero time, while adding a
  `.contentModificationDateKey` prefetch to every discovery pass. The two trees are opposites and
  the asymmetry in the code is correct: `~/.codex/sessions` is **not** pruned — 1734 files with 105
  already past 90 days and climbing — which is what the Codex horizon is guarding against, and why
  it stays. Revisit only if Claude Code stops pruning.
  The all-time-floor worry that blocked this is also the wrong way round. `stats-cache.json` on that
  machine stopped being written in February (`lastComputedDate` 2026-02-20, 9 daily entries) while
  the logs only reach back to September, so the JSONL `max()` and the `TokenLedger` high-water mark
  are *already* the only things carrying all-time — the ledger is doing exactly the job it exists
  for, with no pruning change needed. Note the consequence: on a machine like this, a lost
  `token-ledger.json` collapses All Time to the last ~7 weeks. That is the ledger's risk, not the
  reader's.

- **Session-log fallback inspects only the newest rollout.** With two ChatGPT accounts the one whose
  CLI session is newest gets the fallback and the other serves its cache. Outage × two accounts is
  an edge of an edge — won't-fix unless someone reports it.
- **Test-deadlock "proper fix" (pre-warm AppKit before any suite).** Swift Testing has no global
  setup hook, so it cannot be guaranteed. `--no-parallel` at 12 s is the answer, and `release.yml`
  now passes it too.
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
  `ChunkedFileReader`'s single reused buffer was the measured win.
- **June persist-write coalescing and per-body window-token reductions.** Unmeasured and tiny.
- **Aggregator CoW / array churn.** Full pass is 19 ms; the suspect operations measure under 1 ms each.
- **Blanket `fixedSize` and `Typography` sweeps.** Too broad to land safely; the specific clipping
  cases were fixed individually.
- **The unshipped "Phase 4" file splits.** Their targets were split other ways; every file is under
  the 800-line ceiling.
- **The monthly chart's empty state.** `monthlyData` always returns 12 zero-filled points, so the
  branch is effectively unreachable — but it is the guard against an empty `ForEach` with `AxisMarks`,
  which crashes Swift Charts. Kept, with copy that no longer promises a 30-day threshold.
