---
phase: 7
slug: visual-polish
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-19
---

# Phase 7 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Swift Testing (@Test, #expect) |
| **Config file** | Package.swift (AIBatteryCoreTests target) |
| **Quick run command** | `swift build` |
| **Full suite command** | `swift test` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `swift build` (compile check)
- **After every plan wave:** Run `swift build` (animations are visual — compile is the automated gate)
- **Before `/gsd:verify-work`:** Full build must be green + visual inspection
- **Max feedback latency:** 15 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 07-01-01 | 01 | 1 | UI-06 | compile+grep | `swift build && grep -r "StyledDivider" AIBattery/Views/` | ❌ W0 | ⬜ pending |
| 07-01-02 | 01 | 1 | UI-07 | compile+grep | `swift build && grep -r "MotionConstants" AIBattery/` | ❌ W0 | ⬜ pending |
| 07-01-03 | 01 | 2 | UI-06 | grep | `grep -rn "Divider()" AIBattery/Views/ \| grep -v StyledDivider` | ✅ | ⬜ pending |
| 07-01-04 | 01 | 2 | UI-07 | grep | `grep -rn "contentTransition" AIBattery/Views/` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `AIBattery/Views/StyledDivider.swift` — created by Plan 01 Task 1
- [ ] `MotionConstants` enum — created by Plan 01 Task 1

*No pre-existing test stubs needed — visual phase validated by compile + grep + manual inspection.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Divider visual consistency | UI-06 | Opacity/spacing are visual | Launch app, verify all dividers look identical |
| Expand/collapse smoothness | UI-07 | Animation timing is perceptual | Launch app, expand/collapse each section, verify no jumps |
| Metric value transitions | UI-07 | Digit rolling is visual | Launch app, wait for poll cycle, verify numbers transition smoothly |
| Animation performance | UI-07 | Perceived latency is subjective | Launch app, rapidly toggle sections, verify no lag |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 15s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
