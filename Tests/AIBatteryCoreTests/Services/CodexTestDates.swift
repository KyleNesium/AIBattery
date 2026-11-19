import Foundation

/// Date folders for tests that write Codex rollouts under `YYYY/MM/DD`.
///
/// `CodexSessionLogReader` skips date folders older than `retentionHorizonMonths`,
/// measured from the real clock. A hard-coded folder such as `2026/09` therefore drops
/// out of discovery about 13 months after it was written, and every test that put a
/// rollout there starts finding nothing at once. The current month never ages out.
///
/// Tests that exercise the horizon itself pin their own `now` and keep literal dates.
enum CodexTestDates {
    /// `YYYY/MM` for the month the test run started in.
    static let thisMonth: String = {
        let parts = Calendar(identifier: .gregorian).dateComponents([.year, .month], from: Date())
        return String(format: "%04d/%02d", parts.year ?? 0, parts.month ?? 0)
    }()
}
