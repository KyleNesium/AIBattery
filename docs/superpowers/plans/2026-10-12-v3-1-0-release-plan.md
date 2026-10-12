# v3.1.0 Release Plan (umbrella)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. This document sequences two task plans on ONE branch and owns everything release-level (branch, changelog heading, version, counts, PR). Steps use checkbox (`- [ ]`) syntax.

**Goal:** Ship v3.1.0 as one PR: the Settings-height fix already on main (#196), the multi-account overview, the provider-relevant display items, and the Sparkle 2.10.0 bump + README/spec alignment (absorbed from #199).

**Architecture:** Two phases on the single branch `worktree-v3-1-0` (worktree `.claude/worktrees/v3-1-0`). Phase 1 is the multi-account overview plan (it also delivers provider-relevance item 6). Phase 2 is the provider-relevance plan minus its superseded/duplicated tasks. One wrap-up task finishes counts, changelog and the PR description. Nothing is tagged until Kyle says ship.

**Tech Stack:** Swift 6 / SwiftUI, SPM, Swift Testing.

**Specs:**
- `docs/superpowers/specs/2026-10-12-multi-account-overview-design.md`
- `docs/superpowers/specs/2026-10-12-provider-relevance-design.md`

**Task plans:**
- Phase 1: `docs/superpowers/plans/2026-10-12-multi-account-overview-plan.md` (Tasks 1–7, 9; Task 8 is a pointer)
- Phase 2: `docs/superpowers/plans/2026-10-12-provider-relevance-plan.md` (Tasks 0–6, 8, 9, 11; Tasks 7 and 10 are pointers)

## Global Constraints

- **One branch, one PR, draft until Kyle says done.** PR title `feat: v3.1.0 — multi-account overview, provider-relevant display, Settings height fix`. Never `gh pr ready`; CI runs via `gh workflow run ci.yml --ref worktree-v3-1-0` when a phase completes (not per task).
- Version is already `3.1.0` in `project.yml` and `AIBattery/Info.plist`; `CHANGELOG.md` has `## [3.1.0] — Unreleased`. Tasks append their own `### Added` line; the wrap-up sets the date.
- All constraints of both task plans apply (Swift 6 strict concurrency, lint clean, headless-CI rules, no `.move(edge:)`, no synthetic keystrokes, identity never copied into `displayName`, cost framing, privacy).
- Commit per task, `<type>: <description>`, **no Co-Authored-By trailers**. README "Test Coverage" updated with every test change; `CLAUDE.md` counts at wrap-up.
- Superseded PRs #197, #198, #199, #200 are closed with a pointer to this PR; their remote branches are deleted (the `sparkle-2-10` worktree belongs to another session and is left in place).

---

## Execution order

| # | Phase / task | Why here |
|---|---|---|
| 1 | Overview Task 1 — `AccountReading`, `FanOutGate`, API-key accounts in fan-out + menu bar | Foundation for every card and for provider item 6 |
| 2 | Overview Task 2 — both providers' status feeds | Card status dots |
| 3 | Overview Task 3 — `PopoverMode` + view branch | Mode switch, placeholder overview |
| 4 | Overview Task 4 — `AccountCard` model | Pure, fully tested |
| 5 | Overview Task 5 — card + overview UI | First visible feature; take `screenshots/overview.png` |
| 6 | Overview Task 6 — back chevron + Escape routing | Completes the flow |
| 7 | Overview Task 7 — Settings copy + poll-cost hint | |
| 8 | Overview Task 9 — spec sync for Phase 1 | Then dispatch CI once |
| 9 | Provider Task 0 — capture live `/api/oauth/usage` keys (R1) | Gates provider Task 6 |
| 10 | Provider Task 1 — entry fields (context window, reasoning, effort) | |
| 11 | Provider Task 2 — reasoning through aggregator / summaries / ledger | |
| 12 | Provider Task 3 — context health status fields | |
| 13 | Provider Task 4 — Context row + Insights copy | |
| 14 | Provider Task 5 — limit name on the credits bar | |
| 15 | Provider Task 6 — Claude per-model weekly windows (only if #9 said present) | |
| 16 | Provider Task 8 — credit runway | Uses `CodexCreditBudget` + fetcher; after item 5 |
| 17 | Provider Task 9 — dated Codex All-Time | |
| 18 | Provider Task 11 — spec sync for Phase 2 | Then dispatch CI once |
| 19 | Wrap-up (below) | |

Phase 2 can be cut short if time is tight: items 1–3 (steps 10–13) are the ones worth shipping with the overview; 5, 6, 8, 9 can slide to 3.1.1 — record any slide in the changelog PR body, not silently.

---

### Wrap-up: counts, changelog, PR body

**Files:** `README.md` (Test Coverage), `CLAUDE.md` (counts), `CHANGELOG.md` (date, final `### Added` list, remove the placeholder line), PR body.

- [ ] **Step 1: Counts**

```bash
grep -rho "@Test" Tests | wc -l
find Tests -name "*.swift" | wc -l
for d in Models Services Views ViewModels Utilities; do echo "$d $(grep -rho '@Test' Tests/AIBatteryCoreTests/$d | wc -l)"; done
```

Update `README.md` (`**N tests** across M test files.` + per-area rows) and `CLAUDE.md:43`.

- [ ] **Step 2: Changelog**

Replace `## [3.1.0] — Unreleased` with `## [3.1.0] — <YYYY-MM-DD>` and delete the italic placeholder line under `### Added`. Every landed task must already have its line; verify against `git log --oneline main..HEAD`.

- [ ] **Step 3: Full verification**

```bash
swiftformat AIBattery/ AIBatteryApp/ Tests/ && swiftlint
swift test 2>&1 | tail -3
./scripts/build-app.sh && open .build/AIBattery.app
```

Walk the overview with all accounts, each account's detail (Context row, Insights tooltips, credits footer), Settings from both modes, and the menu bar with the toggle on. Then `gh workflow run ci.yml --ref worktree-v3-1-0` and wait for green.

- [ ] **Step 4: Commit and update the PR body**

```bash
git add -A
git commit -m "docs: v3.1.0 counts and changelog"
git push
gh pr edit <number> --body-file docs/superpowers/plans/2026-10-12-v3-1-0-release-plan.md
```

The PR **stays draft**. Hand the link to Kyle.

### Release (only on Kyle's "ship")

```bash
gh pr ready <number> && gh pr merge <number> --squash --delete-branch
git checkout main && git pull --ff-only
git tag v3.1.0 && git push origin v3.1.0
gh run list --workflow=release.yml
```

Then remove the worktree (`git worktree remove .claude/worktrees/v3-1-0`), delete the local branch, verify the GitHub release, appcast and Homebrew tap per `scripts/verify-release.sh`.

---

## Self-review

- Every task of both plans appears exactly once in the execution order or is marked as a pointer (overview 8; provider 7, 10). Wrap-ups of the two plans are spec-sync only; version, changelog date, counts and PR live here only.
- The version bump and changelog heading are already on the branch (cherry-picked from the held 3.0.1 bump and rewritten), so no task re-bumps.
- Draft-until-done is stated in the constraints, in both task plans' constraints, and in the wrap-up.
