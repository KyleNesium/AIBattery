import Foundation

/// Minimal JWT payload reader. NO signature verification — we only read claims
/// from tokens we just received over TLS from the issuer; the tokens are the
/// credential, the claims are informational (account id, expiry).
enum JWTDecoder {
    static func payload(_ jwt: String) -> [String: Any]? {
        let segments = jwt.split(separator: ".")
        guard segments.count == 3 else { return nil }
        var base64 = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 {
            base64.append("=")
        }
        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }

    /// ChatGPT account id from the id_token's OpenAI auth claim.
    static func chatGPTAccountId(idToken: String) -> String? {
        let auth = payload(idToken)?["https://api.openai.com/auth"] as? [String: Any]
        return auth?["chatgpt_account_id"] as? String
    }

    /// Email address from an OpenAI id_token: the standard `email` claim, or the
    /// address nested under the OpenAI profile claim. Nil when absent or blank.
    static func email(idToken: String) -> String? {
        guard let payload = payload(idToken) else { return nil }
        let direct = payload["email"] as? String
        let profile = (payload["https://api.openai.com/profile"] as? [String: Any])?["email"] as? String
        guard let raw = direct ?? profile else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// `exp` claim as a Date (nil when absent/malformed).
    static func expiry(_ jwt: String) -> Date? {
        guard let exp = payload(jwt)?["exp"] as? TimeInterval else { return nil }
        return Date(timeIntervalSince1970: exp)
    }
}
