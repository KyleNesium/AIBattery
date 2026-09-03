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
        let listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: port)!)
        self.listener = listener
        // Capture queue directly to avoid weak self escape to .global()
        let queue = self.queue
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

    private static func respond(_ connection: NWConnection, status: String, body: String, then: @escaping @Sendable () -> Void) {
        let payload = "HTTP/1.1 \(status)\r\nContent-Type: text/html\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        connection.send(content: Data(payload.utf8), completion: .contentProcessed { _ in
            connection.cancel()
            then()
        })
    }
}
