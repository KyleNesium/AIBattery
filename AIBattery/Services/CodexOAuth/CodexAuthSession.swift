import Foundation

/// Holds the in-flight Codex OAuth state: PKCE verifier, CSRF state, and the
/// one-shot localhost callback server. One stored property on OAuthManager
/// instead of three; discarded when the flow completes or is cancelled.
@MainActor
final class CodexAuthSession {
    let verifier: String
    let state: String
    let server: CodexCallbackServer
    private var continuation: CheckedContinuation<Result<(code: String, state: String), CodexCallbackError>, Never>?

    private init(verifier: String, state: String, server: CodexCallbackServer) {
        self.verifier = verifier
        self.state = state
        self.server = server
    }

    /// Generate PKCE + state, bind the callback port, and produce the browser URL.
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
    func awaitCallback() async -> Result<(code: String, state: String), CodexCallbackError> {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(180))
                self?.deliver(.failure(.providerError("timeout")))
            }
        }
    }

    private func deliver(_ result: Result<(code: String, state: String), CodexCallbackError>) {
        guard let continuation else { return } // already delivered
        self.continuation = nil
        server.stop()
        continuation.resume(returning: result)
    }

    func cancel() {
        deliver(.failure(.providerError("cancelled")))
    }
}
