import CryptoKit
import Foundation

/// OAuth PKCE (Proof Key for Public Clients) and state generation utilities.
enum OAuthPKCE {
    /// 32 CSPRNG bytes, or a trap.
    ///
    /// `SecRandomCopyBytes` leaves the buffer untouched on failure, so discarding its
    /// status would hand back 32 zero bytes — a fully predictable PKCE verifier and a
    /// fully predictable CSRF state, which is exactly what both values exist to prevent.
    /// There is no safe weaker fallback for a credential-grade secret, and the call does
    /// not fail on a working macOS, so failing loudly is correct.
    private static func randomBytes(count: Int = 32) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed (\(status)) — refusing to use predictable OAuth secrets")
        return bytes
    }

    /// Generates a random PKCE verifier and corresponding challenge for OAuth code exchange.
    ///
    /// The verifier is 32 random bytes (base64url-encoded), and the challenge is its SHA-256 hash
    /// (base64url-encoded). Both meet RFC 7636 requirements and are URL-safe (no +, /, or =).
    static func generatePKCE() -> (verifier: String, challenge: String) {
        // 32 random bytes → base64url → verifier
        let verifier = Data(randomBytes()).base64URLEncoded()

        // SHA-256(verifier) → base64url → challenge
        let digest = SHA256.hash(data: Data(verifier.utf8))
        let challenge = Data(digest).base64URLEncoded()

        return (verifier, challenge)
    }

    /// Generates a random OAuth state parameter for CSRF protection.
    ///
    /// Returns 32 random bytes (base64url-encoded), which are URL-safe (no +, /, or =).
    static func generateState() -> String {
        Data(randomBytes()).base64URLEncoded()
    }

    /// Constant-time equality for the OAuth state parameter. `==` on `String` short-circuits
    /// on the first differing byte; a CSRF token should not leak its prefix through timing,
    /// and the comparison is cheap enough that there is no reason to accept that.
    static func constantTimeEquals(_ lhs: String, _ rhs: String) -> Bool {
        let a = Array(lhs.utf8)
        let b = Array(rhs.utf8)
        guard a.count == b.count else { return false }
        var difference: UInt8 = 0
        for (x, y) in zip(a, b) {
            difference |= x ^ y
        }
        return difference == 0
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
