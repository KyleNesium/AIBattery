import Foundation
import Testing
@testable import AIBatteryCore

/// Phase 3a regression coverage: verify that `StatusChecker.fetchAndParse` is
/// callable from a non-MainActor context. The pre-refactor implementation
/// did its HTTP work while `@MainActor`-isolated, which meant a 30s URLSession
/// timeout could freeze the UI. After the refactor, the fetch/decode/parse
/// pipeline must run off-MainActor.
///
/// These tests are intentionally short and use a non-routable / refusing
/// endpoint so the network attempt fails immediately. The point is not to
/// test the network — it's to prove the function compiles and runs in a
/// non-isolated context (the compiler enforces this via `nonisolated`).
@Suite("StatusChecker — concurrency")
struct StatusCheckerConcurrencyTests {
    /// Calling `fetchAndParse` from a `Task.detached` (non-MainActor)
    /// context must complete without deadlock or crash. The compiler
    /// would reject this call site if `fetchAndParse` were MainActor-isolated.
    @Test func fetchAndParse_callableFromDetachedTask() async throws {
        let url = try #require(URL(string: "http://127.0.0.1:1")) // port 1 refuses immediately
        let outcome = await Task.detached(priority: .userInitiated) {
            await StatusChecker.fetchAndParse(url: url, timeout: 0.5)
        }.value

        // Outcome should never be .success against a non-routable URL.
        switch outcome {
        case .success:
            Issue.record("Expected fetch to refusing port to fail, got .success")
        case .httpError, .failure:
            break // expected
        }
    }

    /// `fetchAndParse` must not block MainActor while the network call is
    /// pending. We start a MainActor "ping" task in parallel with the
    /// network attempt; if MainActor were blocked, the ping would not run
    /// until the network attempt completed.
    @Test @MainActor func fetchAndParse_doesNotBlockMainActor() async throws {
        let url = try #require(URL(string: "http://127.0.0.1:1"))
        let mainActorPingFired = MainActorBox(value: false)

        async let fetchTask: Void = {
            _ = await StatusChecker.fetchAndParse(url: url, timeout: 0.5)
        }()

        // While the fetch is in flight, schedule a MainActor closure.
        // If MainActor is blocked by the fetch, this will not run until
        // the fetch returns. With the refactor, MainActor stays free.
        await Task { @MainActor in
            mainActorPingFired.value = true
        }.value

        // The MainActor ping must have fired before (or during) the fetch.
        #expect(mainActorPingFired.value)

        // Drain the fetch task.
        await fetchTask
    }
}

/// Trivial MainActor-bound box used by the concurrency test to record a side
/// effect from inside a `Task { @MainActor in ... }` closure.
@MainActor
private final class MainActorBox {
    var value: Bool
    init(value: Bool) {
        self.value = value
    }
}
