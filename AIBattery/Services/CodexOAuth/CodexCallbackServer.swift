import Foundation
import Network

enum CodexCallbackError: Error, Equatable {
    case notCallbackPath
    case missingCode
    case missingState
    case providerError(String)
}

/// Pure parser for the OAuth redirect's HTTP request line. Split from the
/// server so the extraction contract is unit-testable without sockets.
enum CodexCallbackParser {
    static func parse(requestHead: String) -> Result<(code: String, state: String), CodexCallbackError> {
        // "GET /auth/callback?code=…&state=… HTTP/1.1"
        let parts = requestHead.split(separator: " ")
        guard parts.count >= 2,
              let comps = URLComponents(string: String(parts[1])),
              comps.path == "/auth/callback" else {
            return .failure(.notCallbackPath)
        }
        let items = comps.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value
        }
        if let error = value("error") {
            return .failure(.providerError(error))
        }
        guard let code = value("code"), !code.isEmpty else { return .failure(.missingCode) }
        guard let state = value("state"), !state.isEmpty else { return .failure(.missingState) }
        return .success((code: code, state: state))
    }
}

/// One-shot localhost HTTP listener for the OpenAI OAuth redirect
/// (`http://localhost:1455/auth/callback`). Started when the Codex sign-in
/// button opens the browser; stops itself after the first callback hit or
/// on `stop()` (cancel / popover closed). Non-callback paths (favicon…)
/// get a 404 and the listener keeps waiting.
///
/// Thread safety: all mutable state (listener, hasDelivered) is queue-confined.
/// Every connection handler and send completion runs on the private queue,
/// making plain property access inherently serialized.
final class CodexCallbackServer: @unchecked Sendable {
    private let port: UInt16
    private var listener: NWListener?
    private var hasDelivered = false // queue-confined: every access happens on `queue`
    private let queue = DispatchQueue(label: "codex-oauth-callback")

    init(port: UInt16 = CodexOAuthConstants.callbackPort) {
        self.port = port
    }

    func start(onRequest: @escaping @Sendable (Result<(code: String, state: String), CodexCallbackError>) -> Void) throws {
        let parameters = NWParameters.tcp
        // Loopback-only bind: the redirect URI is `http://localhost:1455/...`, and this
        // app is unsandboxed, so a wildcard (all-interfaces) bind — NWListener's default —
        // would make the OAuth callback reachable from the LAN for the full ≤180s window
        // the listener is up. Setting `requiredLocalEndpoint` restricts the bind to
        // 127.0.0.1 while keeping the exact configured port.
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!
        )
        let listener = try NWListener(using: parameters)
        self.listener = listener
        // Capture queue directly to avoid weak self escape to .global()
        let queue = self.queue

        // NWListener's initializer only throws for malformed parameters — a genuine bind
        // failure (e.g. EADDRINUSE, port already held by the Codex CLI or a previous
        // flow) surfaces ASYNCHRONOUSLY via this handler as `.failed`, after
        // `listener.start(queue:)` below. Without it, `startCodexAuthFlow()`'s "port
        // busy" catch branch was unreachable dead code, and `awaitCallback()` would sit
        // through the full 180s timeout while the real callback hit routed to whichever
        // process already held the port. Delivers through the same one-shot path a bad
        // callback uses so `awaitCallback()` resolves immediately instead.
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .failed(let error):
                AppLogger.oauth.error("Codex callback listener failed: \(error.debugDescription, privacy: .public)")
                self.deliverFailureOnce(.providerError("listener failed: \(error.debugDescription)"), onRequest: onRequest)
            case .cancelled:
                // The normal path (a delivered callback calling `stopOnQueue()`) also
                // lands here — `deliverFailureOnce`'s one-shot guard makes that a no-op.
                // Only a bind failure that surfaces as `.cancelled` instead of `.failed`
                // reaches `onRequest` from this branch.
                self.deliverFailureOnce(.providerError("listener cancelled"), onRequest: onRequest)
            default:
                break
            }
        }

        listener.newConnectionHandler = { [weak self] connection in
            connection.start(queue: queue)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { data, _, _, _ in
                guard let data, let head = String(data: data, encoding: .utf8)?
                    .components(separatedBy: "\r\n").first else {
                    connection.cancel()
                    return
                }
                let result = CodexCallbackParser.parse(requestHead: head)
                if case .failure(.notCallbackPath) = result {
                    Self.respond(connection, status: "404 Not Found", body: "Not found") {}
                    return // keep listening — this was favicon or noise; flag untouched
                }
                // For callback-path results, enforce one-shot delivery (runs on queue, so check-and-set is serialized)
                guard let self else { return }
                guard !self.hasDelivered else {
                    connection.cancel() // duplicate callback hit: close silently, no onRequest
                    return
                }
                self.hasDelivered = true
                let message = (try? result.get()) != nil
                    ? "You're signed in — return to AI Battery."
                    : "Sign-in failed — return to AI Battery and try again."
                Self.respond(connection, status: "200 OK",
                             body: "<html><body style=\"font-family:-apple-system\"><h3>\(message)</h3></body></html>") { [weak self] in
                    self?.stopOnQueue() // send completion runs on queue; call directly, not via public stop()
                    onRequest(result)
                }
            }
        }
        listener.start(queue: queue)
    }

    func stop() {
        queue.async { [weak self] in
            self?.stopOnQueue()
        }
    }

    private func stopOnQueue() {
        listener?.cancel()
        listener = nil
    }

    /// One-shot delivery for the listener-failure path (bind failure / cancellation
    /// before any callback was ever received). Mirrors the connection handler's
    /// check-and-set ordering: `hasDelivered` is set before anything else so a
    /// same-tick duplicate (e.g. a callback landing right as the bind fails) can't
    /// slip through. Runs on `queue` — `stateUpdateHandler` callbacks dispatch there
    /// once `listener.start(queue:)` is called — so this check-and-set is serialized
    /// with the connection handler's own.
    private func deliverFailureOnce(
        _ error: CodexCallbackError,
        onRequest: @escaping @Sendable (Result<(code: String, state: String), CodexCallbackError>) -> Void
    ) {
        guard !hasDelivered else { return }
        hasDelivered = true
        stopOnQueue()
        onRequest(.failure(error))
    }

    private static func respond(_ connection: NWConnection, status: String, body: String, then: @escaping @Sendable () -> Void) {
        let payload = "HTTP/1.1 \(status)\r\nContent-Type: text/html\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        connection.send(content: Data(payload.utf8), completion: .contentProcessed { _ in
            connection.cancel()
            then()
        })
    }
}
