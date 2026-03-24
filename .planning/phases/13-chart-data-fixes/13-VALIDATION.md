---
phase: 13
slug: chart-data-fixes
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-24
---

# Phase 13 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Swift Testing (`@Test`, `#expect`) |
| **Config file** | `Package.swift` — AIBatteryCoreTests target |
| **Quick run command** | `swift test --filter AIBatteryCoreTests` |
| **Full suite command** | `swift test` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `swift test --filter AIBatteryCoreTests`
- **After every plan wave:** Run `swift test`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 13-01-01 | 01 | 1 | DATA-01 | unit | `swift test --filter isEmpty` | ❌ W0 | ⬜ pending |
| 13-01-02 | 01 | 1 | CHART-02 | unit | `swift test --filter formatHourLabelFull` | ❌ W0 | ⬜ pending |
| 13-01-03 | 01 | 1 | CHART-01 | unit | `swift test --filter quarterlyMonthLabels` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `Tests/AIBatteryCoreTests/Views/InsightsViewFormatterTests.swift` — tests for `formatHourLabelFull`, quarterly month filter
- [ ] `Tests/AIBatteryCoreTests/Views/ActivityChartIsEmptyTests.swift` — tests for `isEmpty` logic (extracted to static helper)

*Existing test infrastructure covers framework — only new test files needed.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| 12M labels don't overlap at 275pt | CHART-01 | Visual rendering at specific width | Build app, open 12M chart, verify no label clipping |
| 24H labels show HH:00 format evenly | CHART-02 | Visual spacing verification | Build app, open 24H chart, verify 4 labels with equal gaps |
| 24H chart shows data after relaunch | DATA-01 | Requires app restart cycle | Kill app, relaunch, open 24H chart before JSONL scan completes |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
