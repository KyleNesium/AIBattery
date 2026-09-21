import Foundation

/// Placeholder — replaced by the real streaming reader in Plan 2 Task 3.
final class CodexSessionLogReader: @unchecked Sendable, UsageEntrySource {
    static let shared = CodexSessionLogReader()
    private(set) var lastCorruptLineCount = 0
    func readAllUsageEntries() -> [AssistantUsageEntry] {
        []
    }

    func invalidate() {}
}
