import Testing
import Foundation
@testable import AIBatteryCore

@Suite("CodexTokenClient")
struct CodexTokenClientTests {
    private let goodBody = Data("""
    {"id_token":"id.tok.en","access_token":"at.tok.en","refresh_token":"rt-1"}
    """.utf8)

    @Test func successParsesTokenSet() throws {
        let set = try CodexTokenClient.interpretTokenResponse(statusCode: 200, data: goodBody).get()
        #expect(set == CodexTokenSet(idToken: "id.tok.en", accessToken: "at.tok.en", refreshToken: "rt-1"))
    }

    @Test func missingRefreshTokenIsAllowed() throws {
        let body = Data(#"{"id_token":"i","access_token":"a"}"#.utf8)
        let set = try CodexTokenClient.interpretTokenResponse(statusCode: 200, data: body).get()
        #expect(set.refreshToken == nil)
    }

    @Test func authFailureIsNotTransient() {
        let result = CodexTokenClient.interpretTokenResponse(statusCode: 400, data: Data())
        guard case .failure(let error) = result else { Issue.record("expected failure"); return }
        #expect(!error.isTransient)
    }

    @Test func exchangeSendsFormEncodedBody() async throws {
        let captured = CapturedRequest()
        _ = await CodexTokenClient.exchangeCode("CODE1", verifier: "VERIF", transport: { request in
            await captured.set(request)
            return (Data("{\"id_token\":\"i\",\"access_token\":\"a\",\"refresh_token\":\"r\"}".utf8),
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let request = try #require(await captured.get())
        #expect(request.url == CodexOAuthConstants.tokenURL)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
        let bodyData = try #require(request.httpBody)
        let body = try #require(String(data: bodyData, encoding: .utf8))
        #expect(body.contains("grant_type=authorization_code"))
        #expect(body.contains("code=CODE1"))
        #expect(body.contains("code_verifier=VERIF"))
        #expect(body.contains("client_id=app_EMoamEEZ73f0CkXaXp7hrann"))
    }

    @Test func refreshSendsJSONBody() async throws {
        let captured = CapturedRequest()
        _ = await CodexTokenClient.refresh(refreshToken: "rt-9", transport: { request in
            await captured.set(request)
            return (Data("{\"id_token\":\"i\",\"access_token\":\"a\"}".utf8),
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let request = try #require(await captured.get())
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let bodyData = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: bodyData) as? [String: String])
        #expect(json["grant_type"] == "refresh_token")
        #expect(json["refresh_token"] == "rt-9")
        #expect(json["client_id"] == "app_EMoamEEZ73f0CkXaXp7hrann")
        #expect(json["scope"] == "openid profile email")
    }
}

/// Tiny actor to capture the request from the @Sendable transport closure.
actor CapturedRequest {
    private var request: URLRequest?
    func set(_ r: URLRequest) {
        request = r
    }

    func get() -> URLRequest? {
        request
    }
}
