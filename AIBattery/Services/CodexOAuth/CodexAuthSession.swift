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

/// Holds the in-flight Codex OAuth state: PKCE verifier, CSRF state, and the
/// one-shot localhost callback server. One stored property on OAuthManager
/// instead of three; discarded when the flow completes or is cancelled.
@MainActor
final class CodexAuthSession {
    typealias CallbackResult = Result<(code: String, state: String), CodexCallbackError>

    let verifier: String
    let state: String
    let server: CodexCallbackServer
    private let mailbox = OneShotMailbox<CallbackResult>()

    private init(verifier: String, state: String, server: CodexCallbackServer) {
        self.verifier = verifier
        self.state = state
        self.server = server
    }

    /// Generate PKCE + state, bind the callback port, and produce the browser URL.
    /// The server is live from this point; a redirect arriving before
    /// `awaitCallback()` is buffered by the mailbox.
    static func begin() throws -> (session: CodexAuthSession, browserURL: URL) {
        let (verifier, challenge) = OAuthPKCE.generatePKCE()
        let state = OAuthPKCE.generateState()
        let server = CodexCallbackServer()
        let session = CodexAuthSession(verifier: verifier, state: state, server: server)
        try server.start { result in
            Task { @MainActor in session.deliver(result) }
        }
        return (session, CodexOAuthConstants.buildAuthorizeURL(codeChallenge: challenge, state: state))
    }

    /// Await the browser redirect. Times out after 180 s so an abandoned
    /// sign-in can't hold port 1455 forever.
    func awaitCallback() async -> CallbackResult {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(180))
            self?.deliver(.failure(.providerError("timeout")))
        }
        return await mailbox.value()
    }

    private func deliver(_ result: CallbackResult) {
        guard mailbox.deliver(result) else { return } // already delivered
        server.stop()
    }

    func cancel() {
        deliver(.failure(.providerError("cancelled")))
    }
}
