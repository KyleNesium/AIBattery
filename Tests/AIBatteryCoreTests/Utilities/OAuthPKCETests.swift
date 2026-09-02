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
}
