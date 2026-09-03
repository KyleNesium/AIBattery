import Foundation

/// Fetches Codex/ChatGPT rate limit usage from OpenAI's dedicated usage endpoint.
///
/// Mirrors `RateLimitFetcher`'s per-account caching, auth-failure counting, and
/// persistence patterns for the Codex provider (see that file first — this one
/// intentionally keeps the same shape).
///
/// Primary: `GET /backend-api/wham/usage` (structured JSON, Bearer token auth).
/// Fallback: the newest Codex CLI session log's last `rate_limits` snapshot,
/// via `CodexSessionRateLimitScanner` — always surfaced as cached data since
/// it's as old as the user's last Codex turn.
///
/// Caches results per account ID to support multi-account.
@MainActor
final class CodexRateLimitFetcher {
    static let shared = CodexRateLimitFetcher()

    nonisolated static let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!

    /// Per-account cache of API results. Never expires — stale data is better than empty bars.
    /// Fresh fetches replace cached data on success.
    var cachedResults: [String: APIFetchResult] = [:]

    /// UserDefaults key prefix for persisted rate limits.
    static let persistKeyPrefix = "aibattery_codexRateLimits_"

    /// Per-account count of consecutive 401/403 responses from the usage endpoint.
    /// Reset on any successful result. At or above `authErrorThreshold`, surface
    /// `authError = true` on returned APIFetchResults so the UI can prompt the
    /// user to reconnect instead of silently showing cached data.
    private var consecutiveAuthFailures: [String: Int] = [:]
    static let authErrorThreshold = 3

    /// User-Agent string built from bundle version at startup — same construction
    /// as `RateLimitFetcher.userAgent`.
    let userAgent: String = {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        return "AIBattery/\(version) (macOS)"
    }()

    init() {
        restorePersistedRateLimits()
    }

    /// Outcome of the `/backend-api/wham/usage` request. Distinguishes an auth failure
    /// (the token is dead) from the endpoint merely being unavailable (fall back to
    /// the session-log scanner).
    enum UsageOutcome {
        case success(APIFetchResult)
        case authFailed
        case unavailable
    }

    /// Pure interpretation of the wham/usage response. The HTTP call happens in the
    /// async wrapper (`fetch`); this function takes the raw inputs and decides what
    /// kind of `APIFetchResult` (if any) to surface.
    ///
    /// - 401/403 → `.authFailed`
    /// - 2xx or 429 with a parseable body → `.success` (429 additionally runs
    ///   `markedThrottled()` — the quota-throttle signal lives in the body, not headers)
    /// - everything else (true server error, or a 2xx/429 body that doesn't parse) → `.unavailable`
    nonisolated static func interpretUsageResponse(statusCode: Int, data: Data) -> UsageOutcome {
        if statusCode == 401 || statusCode == 403 {
            return .authFailed
        }
        guard (200..<300).contains(statusCode) || statusCode == 429 else {
            return .unavailable
        }

        guard let rateLimits = CodexUsageParser.parseUsageResponse(data) else {
            return .unavailable
        }

        let normalized = statusCode == 429 ? rateLimits.markedThrottled() : rateLimits

        return .success(APIFetchResult(
            rateLimits: normalized,
            rateLimitSource: .codexUsageEndpoint,
            profile: nil
        ))
    }

    /// Fetches Codex rate limits for a specific account.
    ///
    /// Actor isolation note: mirrors `RateLimitFetcher.fetch` — this method is
    /// `@MainActor`-isolated but the `await SecureNetworking.data(for:)` call
    /// releases MainActor during the network suspension, so the 30s timeout
    /// does not freeze the UI.
    func fetch(accessToken: String, accountId: String) async -> APIFetchResult {
        var request = URLRequest(url: Self.usageURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30

        do {
            let (data, response) = try await SecureNetworking.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return sessionLogFallback(accountId: accountId)
            }

            AppLogger.network.info("codex usage endpoint: status=\(http.statusCode), bodySize=\(data.count)")

            switch Self.interpretUsageResponse(statusCode: http.statusCode, data: data) {
            case .success(let result):
                consecutiveAuthFailures[accountId] = 0
                cachedResults[accountId] = result
                persistRateLimits(result, accountId: accountId)
                return result
            case .authFailed:
                return registerAuthFailure(accountId: accountId)
            case .unavailable:
                // Diagnostic: log a body preview on unexpected error statuses (2xx + 429
                // + 401/403 are all "expected" paths handled above).
                if !(200..<300).contains(http.statusCode), http.statusCode != 429 {
                    if let bodyStr = String(data: data.prefix(256), encoding: .utf8) {
                        AppLogger.network.warning("codex usage endpoint error \(http.statusCode): \(bodyStr)")
                    }
                }
                return sessionLogFallback(accountId: accountId)
            }
        } catch {
            AppLogger.network.warning("codex usage endpoint failed: \(error.localizedDescription)")
            return sessionLogFallback(accountId: accountId)
        }
    }

    /// Record a 401/403 from the usage endpoint and return the cached fallback.
    /// Surfaces `authError` on the result once the per-account count of consecutive
    /// auth failures reaches `authErrorThreshold`.
    private func registerAuthFailure(accountId: String) -> APIFetchResult {
        let count = (consecutiveAuthFailures[accountId] ?? 0) + 1
        consecutiveAuthFailures[accountId] = count
        let surfaceAuthError = count >= Self.authErrorThreshold
        if surfaceAuthError {
            AppLogger.network.error("codex usage endpoint auth failed \(count) consecutive times for account \(accountId, privacy: .public) — surfacing authError to UI")
        }
        return cachedOrEmpty(accountId: accountId, authError: surfaceAuthError)
    }

    /// Try the Codex CLI session-log scanner when the endpoint is unreachable or
    /// returns a transport error. Caches the fallback result in memory (so the menu
    /// bar reflects it immediately) but never persists it — a session-log snapshot
    /// must not overwrite real endpoint data on disk.
    private func sessionLogFallback(accountId: String) -> APIFetchResult {
        guard let (rateLimits, asOf) = CodexSessionRateLimitScanner.latestRateLimits() else {
            return cachedOrEmpty(accountId: accountId)
        }
        AppLogger.network.info("codex usage endpoint unavailable — using session log fallback")
        let result = APIFetchResult(
            rateLimits: rateLimits,
            rateLimitSource: .codexSessionLog,
            profile: nil,
            fetchedAt: asOf,
            isCached: true
        )
        cachedResults[accountId] = result
        return result
    }

    /// Return cached result marked as stale, or an empty result.
    /// Always returns cached data when available — stale rate limits are better
    /// than empty bars.
    func cachedOrEmpty(accountId: String, authError: Bool = false) -> APIFetchResult {
        if let cached = cachedResults[accountId] {
            return APIFetchResult(
                rateLimits: cached.rateLimits?.withClearedExpiredWindows(),
                rateLimitSource: cached.rateLimitSource,
                profile: nil,
                fetchedAt: cached.fetchedAt,
                isCached: true,
                authError: authError
            )
        }
        return APIFetchResult(rateLimits: nil, profile: nil, authError: authError)
    }

    /// Remove an account's cached + persisted rate limits. Called from sign-out paths.
    func clearCache(accountId: String, defaults: UserDefaults = .standard) {
        cachedResults.removeValue(forKey: accountId)
        defaults.removeObject(forKey: Self.persistKeyPrefix + accountId)
    }
}

// MARK: - Persistence

//
// UserDefaults-backed cache of the most recent rate-limit snapshot per account,
// restored on launch so the menu bar fills in immediately instead of showing
// empty bars while the first poll runs. Mirrors `RateLimitFetcher+Persistence.swift`.

extension CodexRateLimitFetcher {
    /// Wrapper for persisting rate limits + fetch timestamp.
    private struct PersistedCodexRateLimits: Codable {
        let rateLimits: RateLimitUsage?
        let rateLimitSource: RateLimitSource?
        let fetchedAt: Date
    }

    /// Save rate limits to UserDefaults for instant display on next launch.
    /// `defaults` is injectable for tests.
    func persistRateLimits(_ result: APIFetchResult, accountId: String, defaults: UserDefaults = .standard) {
        guard result.rateLimits != nil else { return }
        let key = Self.persistKeyPrefix + accountId
        let persisted = PersistedCodexRateLimits(
            rateLimits: result.rateLimits,
            rateLimitSource: result.rateLimitSource,
            fetchedAt: result.fetchedAt
        )
        if let data = try? JSONEncoder().encode(persisted) {
            defaults.set(data, forKey: key)
        }
    }

    /// Restore persisted rate limits into the in-memory cache on launch.
    /// Self-heals: a blob that fails to decode is removed so it cannot wedge
    /// every subsequent launch; other accounts' entries still restore.
    func restorePersistedRateLimits(defaults: UserDefaults = .standard) {
        let prefix = Self.persistKeyPrefix
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            let accountId = String(key.dropFirst(prefix.count))
            guard let data = defaults.data(forKey: key),
                  let persisted = try? JSONDecoder().decode(PersistedCodexRateLimits.self, from: data) else {
                defaults.removeObject(forKey: key)
                continue
            }
            // Discard cache entries with future fetchedAt (system clock went backward)
            let fetchedAt = persisted.fetchedAt <= Date() ? persisted.fetchedAt : Date()
            let normalizedRateLimits = persisted.rateLimits?.withClearedExpiredWindows()
            cachedResults[accountId] = APIFetchResult(
                rateLimits: normalizedRateLimits,
                rateLimitSource: persisted.rateLimitSource,
                profile: nil,
                fetchedAt: fetchedAt,
                isCached: true
            )
        }
    }
}
