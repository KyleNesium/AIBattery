import Foundation

/// One-shot, main-actor mailbox: the first `deliver` wins, and a value delivered
/// before anyone awaits is buffered rather than dropped. Lets the callback server
/// start listening (in `CodexAuthSession.begin()`) before the UI reaches
/// `awaitCallback()` without racing a fast localhost redirect.
@MainActor
final class OneShotMailbox<Value: Sendable> {
    private var buffered: Value?
    private var continuation: CheckedContinuation<Value, Never>?
    private var delivered = false

    /// - Returns: `false` when a value was already delivered (the call is ignored).
    @discardableResult
    func deliver(_ value: Value) -> Bool {
        guard !delivered else { return false }
        delivered = true
        if let continuation {
            self.continuation = nil
            continuation.resume(returning: value)
        } else {
            buffered = value
        }
        return true
    }

    /// Await the (single) value — returns immediately if it was already delivered.
    func value() async -> Value {
        if let buffered {
            self.buffered = nil
            return buffered
        }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }
}
