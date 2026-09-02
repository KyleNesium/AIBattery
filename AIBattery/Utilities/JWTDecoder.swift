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

    /// `exp` claim as a Date (nil when absent/malformed).
    static func expiry(_ jwt: String) -> Date? {
        guard let exp = payload(jwt)?["exp"] as? TimeInterval else { return nil }
        return Date(timeIntervalSince1970: exp)
    }
}
