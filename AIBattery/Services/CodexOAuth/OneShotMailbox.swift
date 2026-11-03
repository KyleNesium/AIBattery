import Foundation

/// One-shot, main-actor mailbox: the first `deliver` wins, and a value delivered
/// before anyone awaits is buffered rather than dropped. Lets the callback server
/// start listening (in `CodexAuthSession.begin()`) before the UI reaches
/// `awaitCallback()` without racing a fast localhost redirect.
@MainActor
final class OneShotMailbox<Value: Sendable> {
    private var buffered: Value?
    /// Every waiter, not just the latest. A second `value()` call used to overwrite the
    /// first continuation without resuming it, hanging that caller forever; there is one
    /// caller today, which is the only reason it never bit.
    private var continuations: [CheckedContinuation<Value, Never>] = []
    private var delivered = false

    /// - Returns: `false` when a value was already delivered (the call is ignored).
    @discardableResult
    func deliver(_ value: Value) -> Bool {
        guard !delivered else { return false }
        delivered = true
        if continuations.isEmpty {
            buffered = value
        } else {
            let waiting = continuations
            continuations = []
            for continuation in waiting {
                continuation.resume(returning: value)
            }
        }
        return true
    }

    /// Await the (single) value — returns immediately if it was already delivered.
    /// Several callers may await; they all receive the same value.
    func value() async -> Value {
        if let buffered {
            return buffered
        }
        return await withCheckedContinuation { continuation in
            if let buffered {
                continuation.resume(returning: buffered)
            } else {
                continuations.append(continuation)
            }
        }
    }
}
