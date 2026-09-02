import Foundation
import Testing
@testable import AIBatteryCore

@Suite("JWTDecoder")
struct JWTDecoderTests {
    /// Build an unsigned test JWT: header.payload.fakesig with base64url segments.
    private func jwt(payload: [String: Any]) -> String {
        let header = Data(#"{"alg":"none"}"#.utf8).base64URLEncoded()
        let body = (try! JSONSerialization.data(withJSONObject: payload)).base64URLEncoded()
        return "\(header).\(body).sig"
    }

    @Test func extractsChatGPTAccountId() {
        let token = jwt(payload: [
            "https://api.openai.com/auth": ["chatgpt_account_id": "acc-uuid-42"],
            "exp": 1_900_000_000,
        ])
        #expect(JWTDecoder.chatGPTAccountId(idToken: token) == "acc-uuid-42")
        #expect(JWTDecoder.expiry(token) == Date(timeIntervalSince1970: 1_900_000_000))
    }

    @Test func malformedTokensReturnNil() {
        #expect(JWTDecoder.payload("not-a-jwt") == nil)
        #expect(JWTDecoder.chatGPTAccountId(idToken: "a.!!!.c") == nil)
        #expect(JWTDecoder.expiry("") == nil)
    }
}
