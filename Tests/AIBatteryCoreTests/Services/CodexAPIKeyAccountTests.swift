import Foundation
import Testing
@testable import AIBatteryCore

/// Codex in API-key mode (`auth_mode: "apikey"`): pay-per-token, no ChatGPT windows.
@Suite("Codex API-key accounts")
struct CodexAPIKeyAccountTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let headers: [AnyHashable: Any] = [
        "x-ratelimit-limit-requests": "500", "x-ratelimit-remaining-requests": "499", "x-ratelimit-reset-requests": "120ms",
        "x-ratelimit-limit-tokens": "200000", "x-ratelimit-remaining-tokens": "199990", "x-ratelimit-reset-tokens": "3ms",
    ]

    @Test func probe200_yieldsStandardLimits() {
        guard case .success(let result) = CodexRateLimitFetcher.interpretAPIKeyProbe(statusCode: 200, headers: headers, now: now) else {
            Issue.record("expected success"); return
        }
        #expect(result.rateLimits == nil)
        #expect(result.standardLimits?.requestsLimit == 500)
        #expect(result.hasStandardRateLimitHeaders)
        #expect(!result.isCached)
    }

    @Test func probe429WithHeaders_stillYieldsLimits() {
        var exhausted = headers
        exhausted["x-ratelimit-remaining-requests"] = "0"
        guard case .success(let result) = CodexRateLimitFetcher.interpretAPIKeyProbe(statusCode: 429, headers: exhausted, now: now) else {
            Issue.record("expected success"); return
        }
        #expect(result.standardLimits?.isRequestsExhausted == true)
    }

    @Test func probe401_isAuthFailed_probe500OrNoHeaders_isUnavailable() {
        guard case .authFailed = CodexRateLimitFetcher.interpretAPIKeyProbe(statusCode: 401, headers: headers, now: now) else {
            Issue.record("401 must be authFailed"); return
        }
        guard case .unavailable = CodexRateLimitFetcher.interpretAPIKeyProbe(statusCode: 503, headers: headers, now: now) else {
            Issue.record("503 must be unavailable"); return
        }
        guard case .unavailable = CodexRateLimitFetcher.interpretAPIKeyProbe(statusCode: 200, headers: [:], now: now) else {
            Issue.record("200 without headers must be unavailable"); return
        }
    }

    @Test func probeRequest_shape() throws {
        let request = CodexRateLimitFetcher.apiKeyProbeRequest(apiKey: "sk-test-123", model: "gpt-5-nano", userAgent: "AIBattery/test")
        #expect(request.url?.absoluteString == "https://api.openai.com/v1/responses")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test-123")
        let body = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["model"] as? String == "gpt-5-nano")
        #expect(json["input"] as? String == ".")
        #expect(json["max_output_tokens"] as? Int == 16)
    }

    @Test func apiKeyAccountId_isStableAndNeverEmbedsTheKey() {
        let a = OAuthManager.apiKeyAccountId(for: "sk-proj-abcdef0123456789")
        let b = OAuthManager.apiKeyAccountId(for: "sk-proj-abcdef0123456789")
        let c = OAuthManager.apiKeyAccountId(for: "sk-proj-different")
        #expect(a == b)
        #expect(a != c)
        #expect(a.hasPrefix("openai-api-"))
        #expect(!a.contains("abcdef"))
        #expect(a.count <= 40)
    }

    @Test func accountRecord_accessMode_decodesNilForLegacyAndRoundTrips() throws {
        let legacy = Data(#"{"id":"acc","addedAt":800000000,"provider":"codex"}"#.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        #expect(try decoder.decode(AccountRecord.self, from: legacy).codexAccessMode == nil)

        let record = AccountRecord(id: "openai-api-x", addedAt: Date(), provider: .codex, codexAccessMode: .apiKey)
        let encoded = try JSONEncoder().encode(record)
        let round = try JSONDecoder().decode(AccountRecord.self, from: encoded)
        #expect(round.codexAccessMode == .apiKey)
        #expect(round.isAPIKeyAccount)
    }

    @Test func importer_parsesAPIKeyMode() {
        let apiKeyMode = Data(#"{"auth_mode":"apikey","OPENAI_API_KEY":"sk-x","tokens":null}"#.utf8)
        #expect(CodexAuthFileImporter.parseCredential(apiKeyMode) == .apiKey("sk-x"))
        let chatgpt = Data(#"{"auth_mode":"chatgpt","OPENAI_API_KEY":null,"tokens":{"id_token":"i","access_token":"a","refresh_token":"r","account_id":"acc"}}"#.utf8)
        #expect(CodexAuthFileImporter.parseCredential(chatgpt) == .chatGPT(CodexImportedAuth(accountId: "acc", idToken: "i", accessToken: "a", refreshToken: "r")))
        #expect(CodexAuthFileImporter.parseCredential(Data(#"{"auth_mode":"apikey","OPENAI_API_KEY":""}"#.utf8)) == nil)
    }
}
