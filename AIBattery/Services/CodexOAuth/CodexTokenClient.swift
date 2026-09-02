import Foundation

/// Token set returned by OpenAI's OAuth token endpoint, for both the
/// authorization-code exchange and the refresh-token grant.
struct CodexTokenSet: Equatable {
    let idToken: String
    let accessToken: String
    let refreshToken: String?
}

/// Exchanges an authorization code for tokens, and refreshes tokens, against
/// OpenAI's Codex OAuth token endpoint. Wire formats verified against the
/// open-source Codex CLI (codex-rs/login):
/// - Exchange: `application/x-www-form-urlencoded` POST, `authorization_code` grant.
/// - Refresh: `application/json` POST, `refresh_token` grant.
///
/// Reuses `OAuthManager.AuthError` rather than a parallel error enum — later
/// tasks that already know how to interpret that type (retry, sign-out on
/// non-transient failure) can treat Codex and Anthropic token results the
/// same way. The retry loop mirrors `OAuthManager.postToken`'s structure
/// (attempts loop, backoff on 5xx/transport error via `RetryPolicy.oauth`).
enum CodexTokenClient {
    /// Decodable shape of the token endpoint's JSON response body.
    private struct TokenResponse: Decodable {
        let idToken: String
        let accessToken: String
        let refreshToken: String?

        enum CodingKeys: String, CodingKey {
            case idToken = "id_token"
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
        }
    }

    /// Maps an HTTP status code + response body to a `CodexTokenSet` or an
    /// `OAuthManager.AuthError`. Pure — no I/O, no logging; never touches the
    /// token values it parses beyond returning them to the caller.
    nonisolated static func interpretTokenResponse(statusCode: Int, data: Data) -> Result<CodexTokenSet, OAuthManager.AuthError> {
        switch statusCode {
        case 200..<300:
            guard let response = try? JSONDecoder().decode(TokenResponse.self, from: data) else {
                return .failure(.unknownError("Token endpoint returned \(statusCode)"))
            }
            return .success(CodexTokenSet(
                idToken: response.idToken,
                accessToken: response.accessToken,
                refreshToken: response.refreshToken
            ))
        case 400:
            return .failure(.invalidCode)
        case 401, 403:
            return .failure(.expired)
        case 500..<600:
            return .failure(.serverError(statusCode))
        default:
            return .failure(.unknownError("Token endpoint returned \(statusCode)"))
        }
    }

    /// Exchange an authorization code for tokens (`authorization_code` grant,
    /// form-urlencoded body). `transport` is injectable for tests; production
    /// callers use the default `SecureNetworking` transport.
    static func exchangeCode(
        _ code: String,
        verifier: String,
        transport: @Sendable (URLRequest) async throws -> (Data, URLResponse) = { try await SecureNetworking.data(for: $0) }
    ) async -> Result<CodexTokenSet, OAuthManager.AuthError> {
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "redirect_uri", value: CodexOAuthConstants.redirectURI),
            URLQueryItem(name: "client_id", value: CodexOAuthConstants.clientId),
            URLQueryItem(name: "code_verifier", value: verifier),
        ]

        var request = URLRequest(url: CodexOAuthConstants.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        request.httpBody = Data((components.percentEncodedQuery ?? "").utf8)

        return await send(request, transport: transport)
    }

    /// Refresh an access token (`refresh_token` grant, JSON body). `transport`
    /// is injectable for tests; production callers use the default
    /// `SecureNetworking` transport.
    static func refresh(
        refreshToken: String,
        transport: @Sendable (URLRequest) async throws -> (Data, URLResponse) = { try await SecureNetworking.data(for: $0) }
    ) async -> Result<CodexTokenSet, OAuthManager.AuthError> {
        let body: [String: String] = [
            "client_id": CodexOAuthConstants.clientId,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "scope": "openid profile email",
        ]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            return .failure(.unknownError("Failed to serialize request body"))
        }

        var request = URLRequest(url: CodexOAuthConstants.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        request.httpBody = bodyData

        return await send(request, transport: transport)
    }

    /// Shared POST + retry loop for both grants. Mirrors `OAuthManager.postToken`
    /// (OAuthManager.swift:427-528): loop over attempts, exponential backoff via
    /// `RetryPolicy.oauth` on transient failures (5xx / transport error), return
    /// immediately on success or a non-transient failure. Logs status codes and
    /// error descriptions only — never token values.
    private static func send(
        _ request: URLRequest,
        transport: @Sendable (URLRequest) async throws -> (Data, URLResponse)
    ) async -> Result<CodexTokenSet, OAuthManager.AuthError> {
        let retryPolicy = RetryPolicy.oauth
        let maxRetries = retryPolicy.maxAttempts ?? 0
        var lastError: OAuthManager.AuthError = .networkError

        for attempt in 0...maxRetries {
            if attempt > 0 {
                // Exponential backoff with jitter via RetryPolicy.oauth (1s, 2s, 4s ±20%).
                let delay = retryPolicy.delay(forAttempt: attempt)
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }

            do {
                let (data, response) = try await transport(request)
                guard let http = response as? HTTPURLResponse else { return .failure(.networkError) }

                let result = interpretTokenResponse(statusCode: http.statusCode, data: data)
                if case .failure(let error) = result, error.isTransient {
                    AppLogger.oauth.warning("Codex token endpoint returned \(http.statusCode), attempt \(attempt + 1)/\(maxRetries + 1)")
                    lastError = error
                    continue
                }
                return result
            } catch {
                AppLogger.oauth.error("Codex token request network error: \(error)")
                lastError = .networkError
                continue
            }
        }

        return .failure(lastError)
    }
}
