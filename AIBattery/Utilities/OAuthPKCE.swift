import CryptoKit
import Foundation

/// OAuth PKCE (Proof Key for Public Clients) and state generation utilities.
enum OAuthPKCE {
    /// Generates a random PKCE verifier and corresponding challenge for OAuth code exchange.
    ///
    /// The verifier is 32 random bytes (base64url-encoded), and the challenge is its SHA-256 hash
    /// (base64url-encoded). Both meet RFC 7636 requirements and are URL-safe (no +, /, or =).
    static func generatePKCE() -> (verifier: String, challenge: String) {
        // 32 random bytes → base64url → verifier
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let verifier = Data(bytes).base64URLEncoded()

        // SHA-256(verifier) → base64url → challenge
        let digest = SHA256.hash(data: Data(verifier.utf8))
        let challenge = Data(digest).base64URLEncoded()

        return (verifier, challenge)
    }

    /// Generates a random OAuth state parameter for CSRF protection.
    ///
    /// Returns 32 random bytes (base64url-encoded), which are URL-safe (no +, /, or =).
    static func generateState() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncoded()
    }
}

// MARK: - Data Extension for Base64URL Encoding

extension Data {
    /// Encodes data as a base64url string per RFC 4648 Section 5.
    ///
    /// Removes padding (=) and replaces + with - and / with _ to produce URL-safe strings
    /// suitable for OAuth PKCE and state parameters.
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
