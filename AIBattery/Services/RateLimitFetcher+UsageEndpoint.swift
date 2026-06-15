import Foundation

// MARK: - Dedicated /api/oauth/usage endpoint (primary path)

//
// Returns structured JSON with five-hour / seven-day utilization — no
// model probe needed. Same endpoint CodexBar and other tools use.
// The pure interpreter (`interpretUsageEndpoint`) is `nonisolated static`
// so its status-code / payload / 429-normalization contract can be
// tested without mocking URLSession.

extension RateLimitFetcher {
    /// Outcome of the primary `/api/oauth/usage` path. Distinguishes an auth failure
    /// (the token is dead — probing the Messages API with it would just produce a
    /// second 401) from the endpoint merely being unavailable (fall back to the probe).
    enum UsageEndpointOutcome {
        case success(APIFetchResult)
        case authFailed
        case unavailable
    }

    /// Pure interpretation of the OAuth `/api/oauth/usage` response. The HTTP call
    /// happens in the async wrapper; this function takes the raw inputs and decides
    /// what kind of `APIFetchResult` (if any) to surface.
    ///
    /// Returns:
    /// - `.authFailed` for 401/403 — `fetch()` counts it toward
    ///   `consecutiveAuthFailures` and skips the Messages probe
    /// - `.unavailable` for any other non-2xx-non-429 status (true server error),
    ///   or 2xx/429 with a body that doesn't parse to a `RateLimitUsage`
    nonisolated static func interpretUsageEndpoint(
        statusCode: Int,
        data: Data,
        headers: [AnyHashable: Any],
        cachedProfile: APIProfile?
    ) -> UsageEndpointOutcome {
        if statusCode == 401 || statusCode == 403 { return .authFailed }
        // 429 carries the quota-throttle signal in its body — accept alongside 2xx so the
        // `markedThrottled` normalization below can fire. Mirrors the sibling
        // `interpretClaudeCodeClientData` contract.
        guard (200..<300).contains(statusCode) || statusCode == 429 else { return .unavailable }

        let rateLimits = RateLimitUsage.parse(clientData: data)
        let profile = APIProfile.parse(headers: headers)
            ?? APIProfile.parse(clientData: data)
            ?? cachedProfile

        guard let rateLimits else { return .unavailable }

        let normalizedRateLimits = (statusCode == 429 && Self.quotaThrottleLikely(rateLimits))
            ? rateLimits.markedThrottled()
            : rateLimits

        return .success(APIFetchResult(
            rateLimits: normalizedRateLimits,
            rateLimitSource: .oauthUsageEndpoint,
            profile: profile,
            hasStandardRateLimitHeaders: false
        ))
    }

    /// Fetches usage data from Anthropic's dedicated OAuth usage endpoint.
    /// Thin async wrapper: makes the HTTP call, runs diagnostic logging, then
    /// delegates interpretation to `interpretUsageEndpoint`. Transport-level
    /// failures (no response, thrown error) surface as `.unavailable`.
    func fetchUsageEndpoint(accessToken: String, accountId: String) async -> UsageEndpointOutcome {
        var request = URLRequest(url: usageURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30

        do {
            let (data, response) = try await SecureNetworking.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .unavailable }

            AppLogger.network.info("usage endpoint: status=\(http.statusCode), bodySize=\(data.count)")

            // Diagnostic: log body preview on unexpected error statuses before the
            // interpreter discards them (2xx + 429 + 401/403 are all "expected" paths).
            if !(200..<300).contains(http.statusCode), http.statusCode != 429,
               http.statusCode != 401, http.statusCode != 403 {
                if let bodyStr = String(data: data.prefix(256), encoding: .utf8) {
                    AppLogger.network.warning("usage endpoint error \(http.statusCode): \(bodyStr)")
                }
            }

            let outcome = Self.interpretUsageEndpoint(
                statusCode: http.statusCode,
                data: data,
                headers: http.allHeaderFields,
                cachedProfile: cachedResults[accountId]?.profile
            )

            // Diagnostic: 2xx/429 returned a body that didn't parse to rate limits.
            if case .unavailable = outcome, (200..<300).contains(http.statusCode) || http.statusCode == 429 {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let keys = json.keys.sorted().joined(separator: ", ")
                    AppLogger.network.warning("usage endpoint: no rate limits parsed. Keys: [\(keys, privacy: .public)]")
                }
            }

            return outcome
        } catch {
            AppLogger.network.warning("usage endpoint failed: \(error.localizedDescription)")
            return .unavailable
        }
    }
}
