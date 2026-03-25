---
phase: 12
slug: responsiveness
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-20
---

# Phase 12 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Swift Testing (`@Test`, `#expect`) |
| **Config file** | `Package.swift` (test target: AIBatteryCoreTests) |
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
| 12-01-01 | 01 | 1 | RESP-01 | unit | `swift test --filter PanelToggle` | ❌ W0 | ⬜ pending |
| 12-01-02 | 01 | 1 | RESP-02 | unit | `swift test --filter MainThreadFreeze` | ❌ W0 | ⬜ pending |
| 12-01-03 | 01 | 1 | RESP-03 | unit | `swift test --filter ToggleSync` | ❌ W0 | ⬜ pending |
| 12-01-04 | 01 | 1 | RESP-04 | unit | `swift test --filter LazyLoad` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] Test stubs for RESP-01 through RESP-04 panel interaction scenarios
- [ ] Existing infrastructure covers framework — no new installs needed

*Existing Swift Testing framework and AIBatteryCoreTests target cover all phase requirements.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Sub-50ms panel open/close | RESP-01 | Requires wall-clock timing on real hardware | Click menu bar icon, observe < 50ms response |
| No main thread freeze during scroll | RESP-02 | Requires UI interaction testing | Open panel, scroll all sections, verify no hang |
| Toggle state consistency | RESP-03 | Requires rapid click sequence | Click menu bar icon 10x rapidly, verify state always correct |
| Lazy-load visual correctness | RESP-04 | Requires visual inspection | Open panel, verify no layout jump from deferred sections |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
