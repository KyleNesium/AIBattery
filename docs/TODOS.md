# Deferred work

Open items, grouped by area and ordered by priority inside each group. Every item names
the file or type involved so it can be picked up cold, and says which approach was chosen
when the obvious fix is not the right one. Shipped items are removed rather than struck
through; the history is in `CHANGELOG.md`.

## 3.6.0 — in progress on `release/3.6.0`

Everything found during the 3.5.0 cycle ships here (Kyle, 2026-11-20: fix what a release
cycle finds in that release). Tick an item when its commit lands on the branch.

- [ ] **Menu bar icon before the Keychain prompt.** `OAuthManager.init` read the token item
  synchronously (`loadAllTokens`) before `StatusBarManager.setup`, so after every update the
  icon did not appear until the prompt was answered. Approach: every account starts in
  `unreadableAccounts` (signed in, last reading shown), one read of the vault runs on a GCD
  thread (not the cooperative pool: it can block for minutes on the prompt), and the view
  model refreshes when it finishes.
- [ ] **A 400 without an OAuth error body is transient.** `OAuthManager.interpretTokenResponse`
  treated every 400 as final; a proxy or captive-portal 400 signed the account out. Same
  rule as 401/403: only a body with `error` / `error_description` is the provider's word.
  Codex (`CodexTokenClient.interpretTokenResponse`) gets the same rule; it treated any
  400/401/403 as final.
- [ ] **A rejected sign-in keeps the account.** `signOut` ran on a rejected refresh token and
  removed the account record, so the account vanished (2026-11-18), its "session expired"
  message never showed while other accounts were signed in, and the launch prune then
  dropped its history. Now the record stays as a sign-in card, the active account moves to
  a signed-in one, and signing in again merges into the record (`AccountStore.update`). At
  the per-provider cap, a new sign-in replaces a signed-out record instead of failing.
- [ ] **Log the Codex token endpoint's final answer**, with its OAuth error code, like the
  Claude side (`CodexTokenClient.send`).
- [ ] **Land the five unlanded reader tests** from `wip/codex-discovery-tests` (4 discovery
  cache tests) and `wip/reader-incremental-cache-tests` (`codexReader_deletedFilePurgesItsEntries`),
  then delete both branches.
- [ ] **Universal binary (Apple Silicon + Intel).** `build-app.sh` builds arm64 only. Build
  `--arch arm64 --arch x86_64`, check both slices in `verify-release.sh`, launch the Intel
  slice under Rosetta in CI.
- [ ] **License: GPL-3.0 with an attribution term, commercial licence on request.** Was MIT.
  Versions up to 3.5.0 stay MIT. The app shows the notice GPL requires (Settings).
- [ ] **Release docs.** `spec/ARCHITECTURE.md` release steps: push the tag as
  `refs/tags/vX.Y.Z` (a branch of the same name made `--tags` ambiguous in 3.4.0), and the
  release date is GitHub's UTC publish day (the website takes `releasedAt` from it).
- [ ] **GitHub Actions versions** checked against their latest releases (Dependabot's first
  monthly run has not happened yet).
- [ ] **Website FAQ** (aibattery-web): the Keychain password after an update, and a missing
  menu bar icon on macOS 27. Draft PR, merged with the release-day sync.

## Blocked

- [ ] **Verify library validation once the Developer ID certificate lands.**
  `build-app.sh` now strips `com.apple.security.cs.disable-library-validation` whenever
  `CODE_SIGN_IDENTITY` is a real identity (ad-hoc builds keep it — an ad-hoc signature has no
  Team ID, so validation could never pass and Sparkle would not load). The ad-hoc path is
  verified; the signed path cannot be tested without the certificate. When it arrives: build a
  signed bundle, confirm Sparkle still loads and an update still installs, then delete this
  item. `KEEP_LIBRARY_VALIDATION_EXEMPTION=1` is the escape hatch if it turns out to be needed.

## Decided not to do

Kept so they are not re-litigated.

- **Removing the Projects "beta" badge.** Kyle's call, made 2026-10-31: it **stays**. The
  grouping half is finished (`ProjectIdentityResolver` — symlinks resolved, a git worktree
  folded into its parent repo), so the old "still being refined" copy was describing work
  that had already shipped and is gone. The badge now marks two limits that are structural
  rather than unfinished, and the tooltip says both: local logs are machine-wide per provider,
  so a project's usage cannot be split per account; and the CLIs prune their own session logs,
  so only sessions still on disk are counted. Do not re-open this as "the badge is stale".

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
