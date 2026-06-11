import Testing
import Foundation
@testable import AIBatteryCore

/// Behavioral tests for `OAuthManager.postToken`'s retry loop, via the injectable
/// transport seam. CLAUDE.md documents the contract ("token endpoint retries 5xx
/// up to 2 times with backoff") — these tests make it enforced. A zero-delay
/// `RetryPolicy` keeps the suite fast; the production default stays `.oauth`.
@Suite("OAuthManager.postToken")
struct OAuthPostTokenTests {
    /// Counts transport invocations and replays a scripted sequence of results.
    /// `@unchecked Sendable` + NSLock per the codebase's test-double convention.
    private final class TransportStub: @unchecked Sendable {
        enum Step {
            case status(Int, body: String = "")
            case throwError(Error)
        }

        private let lock = NSLock()
        private var steps: [Step]
        private var count = 0

        init(_ steps: [Step]) {
            self.steps = steps
        }

        var attemptCount: Int {
            lock.lock()
            defer { lock.unlock() }
            return count
        }

        func call(_ request: URLRequest) throws -> (Data, URLResponse) {
            lock.lock()
            let step = steps.isEmpty ? Step.status(500) : steps.removeFirst()
            count += 1
            lock.unlock()

            switch step {
            case .status(let code, let body):
                guard let url = request.url,
                      let response = HTTPURLResponse(url: url, statusCode: code, httpVersion: nil, headerFields: nil) else {
                    throw URLError(.badURL)
                }
                return (Data(body.utf8), response)
            case .throwError(let error):
                throw error
            }
        }
    }

    private static let noDelay = RetryPolicy(baseDelay: 0, maxDelay: 0)
    private static let validTokenBody = #"{"access_token":"at-1","refresh_token":"rt-1","expires_in":3600}"#

    private static func post(_ stub: TransportStub) async -> Result<OAuthManager.TokenResult, OAuthManager.AuthError> {
        await OAuthManager.postToken(
            body: ["grant_type": "refresh_token"],
            transport: { try stub.call($0) },
            retryPolicy: noDelay
        )
    }

    @Test func allAttempts500_returnsServerError_afterExactlyThreeAttempts() async {
        let stub = TransportStub([.status(500), .status(500), .status(500)])
        let result = await Self.post(stub)

        guard case .failure(.serverError(let code)) = result else {
            Issue.record("Expected .serverError, got \(result)")
            return
        }
        #expect(code == 500)
        // maxRetries == 2 → exactly 3 attempts, never more.
        #expect(stub.attemptCount == 3)
    }

    @Test func allAttemptsTimeout_returnsNetworkError_afterExactlyThreeAttempts() async {
        let stub = TransportStub([
            .throwError(URLError(.timedOut)),
            .throwError(URLError(.timedOut)),
            .throwError(URLError(.timedOut)),
        ])
        let result = await Self.post(stub)

        guard case .failure(.networkError) = result else {
            Issue.record("Expected .networkError, got \(result)")
            return
        }
        #expect(stub.attemptCount == 3)
    }

    @Test func transientFailureThenSuccess_recoversOnRetry() async {
        let stub = TransportStub([
            .status(503),
            .status(200, body: Self.validTokenBody),
        ])
        let result = await Self.post(stub)

        guard case .success(let tokens) = result else {
            Issue.record("Expected success after one retry, got \(result)")
            return
        }
        #expect(tokens.accessToken == "at-1")
        #expect(tokens.refreshToken == "rt-1")
        #expect(stub.attemptCount == 2)
    }

    @Test func authFailure401_failsImmediately_noRetry() async {
        // A dead credential is not transient — retrying spams the token endpoint.
        let stub = TransportStub([.status(401)])
        let result = await Self.post(stub)

        guard case .failure(.invalidCode) = result else {
            Issue.record("Expected .invalidCode, got \(result)")
            return
        }
        #expect(stub.attemptCount == 1)
    }

    @Test func expiredGrant_mapsToExpired_noRetry() async {
        let stub = TransportStub([
            .status(400, body: #"{"error":"invalid_grant","error_description":"refresh token revoked"}"#),
        ])
        let result = await Self.post(stub)

        guard case .failure(.expired) = result else {
            Issue.record("Expected .expired, got \(result)")
            return
        }
        #expect(stub.attemptCount == 1)
    }

    @Test func malformed200Body_retriesThenFails() async {
        // A 200 with an unparseable body is treated as transient (server hiccup).
        let stub = TransportStub([
            .status(200, body: "not json"),
            .status(200, body: "not json"),
            .status(200, body: "not json"),
        ])
        let result = await Self.post(stub)

        guard case .failure(.unknownError) = result else {
            Issue.record("Expected .unknownError, got \(result)")
            return
        }
        #expect(stub.attemptCount == 3)
    }
}
