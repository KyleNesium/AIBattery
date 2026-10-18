import Foundation

/// The Anthropic token endpoint: the request/response shapes and `postToken`, which
/// performs the exchange and classifies the outcome.
///
/// Split out of `OAuthManager.swift` to keep it under the 800-line ceiling in CLAUDE.md.
/// `postToken` is `nonisolated static` so the network suspension happens entirely off
/// the main actor, and takes its transport and retry policy as parameters so tests can
/// pin the retry contract without touching the live endpoint.
extension OAuthManager {
    // MARK: - Token Endpoint

    struct TokenResult {
        let accessToken: String
        let refreshToken: String
        let expiresAt: Date
    }

    /// Maximum number of retries for transient server errors (5xx).
    /// `nonisolated` because `postToken` is `nonisolated static` and references this.
    nonisolated private static let maxRetries = 2

    /// The recognisable parts of an OAuth error body. Anthropic answers either the
    /// standard `{"error":"invalid_grant","error_description":"…"}` or its nested
    /// `{"error":{"type":"…","message":"…"}}` shape.
    private struct OAuthErrorBody {
        let type: String?
        let message: String?

        /// nil when the body is not a JSON object carrying `error` / `error_description`.
        init?(data: Data) {
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            let nested = json["error"] as? [String: Any]
            let type = json["error"] as? String ?? nested?["type"] as? String
            let message = json["error_description"] as? String ?? nested?["message"] as? String
            guard type != nil || message != nil else { return nil }
            self.type = type
            self.message = message
        }
    }

    /// Pure classification of one token-endpoint response. Mirrors
    /// `CodexTokenClient.interpretTokenResponse`: a non-transient failure makes the
    /// refresh path sign the account out and delete its Keychain item, so only a body
    /// that is recognisably an OAuth error (`error` / `error_description` present) is
    /// treated as the provider's final word. Everything else is transient:
    /// - 2xx whose body does not decode (captive portal, proxy HTML, truncated response)
    /// - 401 / 403 with no OAuth error body (WAF, CDN, proxy)
    /// - 429, 5xx, and any status outside {400, 401, 403}
    ///
    /// A 400 stays terminal regardless of body — the OAuth spec reserves it for a
    /// malformed or rejected grant, and the pre-existing `.unknownError` copy tells the
    /// user to check Console.app.
    nonisolated static func interpretTokenResponse(statusCode: Int, data: Data) -> Result<TokenResult, AuthError> {
        switch statusCode {
        case 200..<300:
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let access = json["access_token"] as? String,
                  let refresh = json["refresh_token"] as? String,
                  let expiresIn = json["expires_in"] as? Int else {
                return .failure(.serverError(statusCode))
            }
            return .success(TokenResult(
                accessToken: access,
                refreshToken: refresh,
                expiresAt: Date().addingTimeInterval(TimeInterval(expiresIn))
            ))
        case 401, 403:
            guard let body = OAuthErrorBody(data: data) else {
                return .failure(.serverError(statusCode))
            }
            if body.type == "invalid_grant" || body.message?.lowercased().contains("expired") == true {
                return .failure(.expired)
            }
            return .failure(.invalidCode)
        case 400:
            guard let body = OAuthErrorBody(data: data) else {
                return .failure(.unknownError("Server returned status \(statusCode). Check Console.app for details."))
            }
            if body.type == "invalid_grant" {
                return .failure(.expired)
            }
            if let message = body.message {
                return .failure(.unknownError("Auth failed: \(message)"))
            }
            return .failure(.unknownError("Server returned status \(statusCode). Check Console.app for details."))
        default:
            // 429 / 5xx / CDN 4xx / anything unexpected — say nothing about the credential.
            return .failure(.serverError(statusCode))
        }
    }

    /// HTTP POST to Anthropic's OAuth token endpoint. Pure: takes a body dict,
    /// returns a `Sendable Result<TokenResult, AuthError>`.
    ///
    /// `nonisolated static` so this can run off-MainActor; the network suspension
    /// already releases MainActor (see `getAccessToken(for:)` doc), but explicit
    /// nonisolation lets the compiler enforce that this function never depends
    /// on instance state — preventing the kind of accidental MainActor capture
    /// that would defeat the suspension contract.
    ///
    /// Used by both `exchangeCode` (authorization_code grant) and
    /// `refreshAccessToken` (refresh_token grant). The MainActor caller owns
    /// all side effects (token storage, account creation, auth state updates).
    ///
    /// `transport` and `retryPolicy` are injectable for tests so the retry loop's
    /// contract (attempt count, 5xx/429/timeout classification) can be pinned
    /// without URLProtocol stubs — those are global and racy under parallel
    /// Swift Testing suites. Production callers use the defaults.
    nonisolated static func postToken(
        body: [String: String],
        transport: @Sendable (URLRequest) async throws -> (Data, URLResponse) = { try await SecureNetworking.data(for: $0) },
        retryPolicy: RetryPolicy = .oauth
    ) async -> Result<TokenResult, AuthError> {
        guard let url = URL(string: tokenURL) else { return .failure(.unknownError("Invalid token URL")) }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            return .failure(.unknownError("Failed to serialize request body"))
        }
        request.httpBody = bodyData

        var lastError: AuthError = .networkError
        for attempt in 0...Self.maxRetries {
            // A cancelled refresh (sign-out mid-flight) must not keep hitting the endpoint
            // through the retry loop. `.networkError` is transient, so the caller never
            // treats a cancellation as a rejected credential.
            guard !Task.isCancelled else { return .failure(.networkError) }
            if attempt > 0 {
                // Exponential backoff with jitter via RetryPolicy.oauth (1s, 2s, 4s ±20%).
                let delay = retryPolicy.delay(forAttempt: attempt)
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }

            do {
                let (data, response) = try await transport(request)
                guard let http = response as? HTTPURLResponse else { return .failure(.networkError) }

                let result = Self.interpretTokenResponse(statusCode: http.statusCode, data: data)
                if case .failure(let error) = result, error.isTransient {
                    // 429 / 5xx / unparseable 2xx / non-OAuth 401-403 / any other status:
                    // nothing here is the provider's verdict on the credential — retry.
                    AppLogger.oauth.warning("Token endpoint returned \(http.statusCode), attempt \(attempt + 1)/\(Self.maxRetries + 1)")
                    // Honor Retry-After header on 429 if present (capped at 30s via RateLimitFetcher)
                    if http.statusCode == 429,
                       let delay = RateLimitFetcher.parseRetryAfter(
                           http.value(forHTTPHeaderField: "Retry-After")
                       ) {
                        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    }
                    lastError = error
                    continue
                }
                if case .failure = result {
                    // Terminal: the body is an OAuth error. It never contains a token.
                    let bodyStr = String(data: data.prefix(512), encoding: .utf8) ?? "(no body)"
                    AppLogger.oauth.error("Token endpoint returned \(http.statusCode): \(bodyStr)")
                }
                return result
            } catch {
                AppLogger.oauth.error("Token exchange network error: \(error)")
                lastError = .networkError
                continue
            }
        }

        return .failure(lastError)
    }
}
