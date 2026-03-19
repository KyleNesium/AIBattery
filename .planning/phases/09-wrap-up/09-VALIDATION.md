---
phase: 9
slug: wrap-up
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-19
---

# Phase 9 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | grep + file reads (documentation phase) |
| **Config file** | N/A |
| **Quick run command** | `grep -c "Typography" spec/CONSTANTS.md` |
| **Full suite command** | `swift build` |
| **Estimated runtime** | ~5 seconds |

---

## Sampling Rate

- **After every task commit:** grep verification of spec content
- **After every plan wave:** `swift build` (no code changes expected, but confirm)
- **Before `/gsd:verify-work`:** Spec content verification via grep
- **Max feedback latency:** 5 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 09-01-01 | 01 | 1 | CQ-02 | grep | `grep "Typography" spec/CONSTANTS.md && grep "Typography" spec/UI_SPEC.md` | ✅ | ⬜ pending |
| 09-01-02 | 01 | 1 | PG-01 | grep | `grep -rn "repeatForever\|Timer\|DispatchSource" AIBattery/Views/ \| grep -v "\.planning"` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

*No new test files needed — documentation-only phase with grep verification.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Spec accuracy | CQ-02 | Human review of prose content | Read spec files, verify they match actual code |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 5s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
