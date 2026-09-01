import Foundation

// MARK: - Claude Code client-data fallback endpoint

//
// When the Messages API stops returning unified headers, fall back to
// `/api/oauth/claude_cli/client_data` and parse either headers or a
// structured JSON body. The pure interpreter
// (`interpretClaudeCodeClientData`) is `nonisolated static` so its
// contract is testable without mocking URLSession.
//
// `containsStandardRateLimitHeaders` lives here too — it's referenced
// from the Messages-API path in the main file via internal visibility,
// but it logically belongs with the rate-limit-header parsing this file
// already covers.

extension RateLimitFetcher {
    /// Pure interpretation of the `/api/oauth/claude_cli/client_data` response.
    /// Header rate limits take precedence over body; profile and standard-limit
    /// headers can also be surfaced even when no rate-limit data is present.
    /// Side-effect-free; the `saveWorkingModel` bookkeeping lives in the async
    /// wrapper because it depends on `self` state.
    nonisolated static func interpretClaudeCodeClientData(
        statusCode: Int,
        data: Data,
        headers: [AnyHashable: Any],
        cachedProfile: APIProfile?,
        callerStandardLimits: StandardRateLimits?
    ) -> APIFetchResult? {
        if statusCode == 401 || statusCode == 403 {
            return nil
        }
        guard (200..<300).contains(statusCode) || statusCode == 429 else { return nil }

        let headerRL = RateLimitUsage.parse(headers: headers)
        let bodyRL = RateLimitUsage.parse(clientData: data)
        let rateLimits = headerRL ?? bodyRL

        let profile = APIProfile.parse(headers: headers)
            ?? APIProfile.parse(clientData: data)
            ?? cachedProfile
        let hasStandardRateLimitHeaders = Self.containsStandardRateLimitHeaders(headers)

        guard rateLimits != nil || profile != nil || hasStandardRateLimitHeaders else { return nil }

        let normalizedRateLimits = rateLimits.map {
            (statusCode == 429 && Self.quotaThrottleLikely($0)) ? $0.markedThrottled() : $0
        }

        return APIFetchResult(
            rateLimits: normalizedRateLimits,
            rateLimitSource: normalizedRateLimits == nil ? nil : .claudeCodeClientData,
            standardLimits: callerStandardLimits,
            profile: profile,
            hasStandardRateLimitHeaders: hasStandardRateLimitHeaders
        )
    }

    /// Claude Code now uses a separate OAuth-backed endpoint for client metadata
    /// and usage state. When the Messages API stops returning unified headers,
    /// fall back to that endpoint and parse either headers or a structured JSON body.
    func fetchClaudeCodeClientData(
        accessToken: String,
        cached: APIFetchResult?,
        accountId: String,
        model: String,
        callerStandardLimits: StandardRateLimits? = nil
    ) async -> APIFetchResult? {
        var request = URLRequest(url: clientDataURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await SecureNetworking.data(for: request)
            guard let http = response as? HTTPURLResponse else { return nil }

            AppLogger.network.info("client_data response: status=\(http.statusCode), bodySize=\(data.count)")
            if let bodyPreview = String(data: data.prefix(512), encoding: .utf8) {
                AppLogger.network.debug("client_data body preview: \(bodyPreview)")
            }

            let result = Self.interpretClaudeCodeClientData(
                statusCode: http.statusCode,
                data: data,
                headers: http.allHeaderFields,
                cachedProfile: cached?.profile,
                callerStandardLimits: callerStandardLimits
            )

            // Diagnostic: 2xx/429 returned a body where rate limits couldn't be
            // parsed from either headers or body. Logged here (not in the
            // interpreter) because it requires the raw payload.
            if result?.rateLimits == nil,
               (200..<300).contains(http.statusCode) || http.statusCode == 429 {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let keys = json.keys.sorted().joined(separator: ", ")
                    AppLogger.network.warning("client_data: no rate limits parsed. Top-level keys: [\(keys, privacy: .public)]")
                } else if let bodyStr = String(data: data.prefix(256), encoding: .utf8) {
                    AppLogger.network.warning("client_data: not a JSON object. Body: \(bodyStr, privacy: .public)")
                } else {
                    AppLogger.network.warning("client_data: response is not a JSON object")
                }
            }

            // Side effect: only when usable rate-limit data landed.
            if result?.rateLimits != nil {
                saveWorkingModel(model, accountId: accountId)
            }

            return result
        } catch {
            return nil
        }
    }

    /// True iff the response carries standard (non-unified) anthropic-ratelimit-* headers.
    /// Used by both client_data and the Messages-API path in the main file.
    nonisolated static func containsStandardRateLimitHeaders(_ headers: [AnyHashable: Any]) -> Bool {
        headers.keys
            .compactMap { $0 as? String }
            .map { $0.lowercased() }
            .contains { key in
                key.hasPrefix("anthropic-ratelimit-") && !key.hasPrefix("anthropic-ratelimit-unified-")
            }
    }
}
