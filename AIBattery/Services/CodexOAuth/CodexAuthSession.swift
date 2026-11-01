import Foundation

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
    /// The 180 s abandonment timer, so `deliver` can stop the clock. It used to run to
    /// completion on every path, including a cancelled flow.
    private var timeoutTask: Task<Void, Never>?

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
        // `[weak session]`: the strong form made session → server → handler → session.
        // The server only delivers while the session is alive, which is the whole point.
        try server.start(expectedState: state) { [weak session] result in
            Task { @MainActor in session?.deliver(result) }
        }
        return (session, CodexOAuthConstants.buildAuthorizeURL(codeChallenge: challenge, state: state))
    }

    /// Await the browser redirect. Times out after 180 s so an abandoned
    /// sign-in can't hold port 1455 forever.
    func awaitCallback() async -> CallbackResult {
        timeoutTask?.cancel()
        timeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(CodexAuthSession.abandonTimeout))
            guard !Task.isCancelled else { return }
            self?.deliver(.failure(.providerError("timeout")))
        }
        return await mailbox.value()
    }

    /// Seconds an abandoned sign-in may hold port 1455.
    static let abandonTimeout: TimeInterval = 180

    private func deliver(_ result: CallbackResult) {
        guard mailbox.deliver(result) else { return } // already delivered
        timeoutTask?.cancel()
        timeoutTask = nil
        server.stop()
    }

    func cancel() {
        deliver(.failure(.providerError("cancelled")))
    }
}
