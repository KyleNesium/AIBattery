import CryptoKit
import Foundation
import Testing
@testable import AIBatteryCore

@Suite("OAuthPKCE")
struct OAuthPKCETests {
    @Test func challengeIsSHA256OfVerifier() {
        let (verifier, challenge) = OAuthPKCE.generatePKCE()
        let expected = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded()
        #expect(challenge == expected)
        #expect(verifier.count >= 43) // RFC 7636 minimum
        #expect(!verifier.contains("+") && !verifier.contains("/") && !verifier.contains("="))
    }

    @Test func stateIsUniqueAndURLSafe() {
        let a = OAuthPKCE.generateState()
        let b = OAuthPKCE.generateState()
        #expect(a != b)
        #expect(!a.contains("+") && !a.contains("/") && !a.contains("="))
    }

    /// `SecRandomCopyBytes` leaves its buffer untouched on failure, so a discarded status
    /// would yield 32 zero bytes — a predictable verifier and a predictable CSRF state.
    /// The all-zero value is what that bug looks like.
    @Test func secretsAreNeverTheAllZeroFallback() {
        let allZero = Data(repeating: 0, count: 32).base64URLEncoded()
        #expect(OAuthPKCE.generateState() != allZero)
        #expect(OAuthPKCE.generatePKCE().verifier != allZero)
    }

    @Test func constantTimeEqualsMatchesValueEquality() {
        let state = OAuthPKCE.generateState()
        #expect(OAuthPKCE.constantTimeEquals(state, state))
        #expect(!OAuthPKCE.constantTimeEquals(state, OAuthPKCE.generateState()))
        #expect(!OAuthPKCE.constantTimeEquals(state, String(state.dropLast())))
        #expect(!OAuthPKCE.constantTimeEquals("", state))
        #expect(OAuthPKCE.constantTimeEquals("", ""))
        // Differs only in the last byte — the case a short-circuiting == leaks the timing of.
        #expect(!OAuthPKCE.constantTimeEquals("abcd", "abce"))
    }
}
