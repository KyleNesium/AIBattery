import Foundation

/// The recognisable parts of an OAuth token endpoint's error body, for both the Claude and
/// the Codex token clients.
///
/// Only a body like this is the provider's verdict on a credential. A 400, 401 or 403
/// without one came from a proxy, a captive portal or a CDN and says nothing about the
/// refresh token, so both clients treat it as transient: a final answer signs the account
/// out. Shapes accepted: the standard `{"error":"invalid_grant","error_description":"…"}`,
/// and the nested `{"error":{"type":"…","message":"…","code":"…"}}` that Anthropic and
/// OpenAI also send.
struct OAuthErrorBody {
    let type: String?
    let message: String?
    /// OpenAI's specific reason inside the nested shape, e.g. `refresh_token_reused`.
    let code: String?

    /// nil when the body is not a JSON object carrying `error` / `error_description`.
    init?(data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let nested = json["error"] as? [String: Any]
        let type = json["error"] as? String ?? nested?["type"] as? String
        let message = json["error_description"] as? String ?? nested?["message"] as? String
        guard type != nil || message != nil else { return nil }
        self.type = type
        self.message = message
        code = nested?["code"] as? String
    }

    /// What a log line may show publicly: the error code, never the message, which can
    /// echo request details. Capped so a hostile body cannot flood the log.
    static func logCode(_ data: Data) -> String {
        guard let body = OAuthErrorBody(data: data) else { return "no OAuth error body" }
        return String((body.code ?? body.type ?? "no error code").prefix(40))
    }
}
