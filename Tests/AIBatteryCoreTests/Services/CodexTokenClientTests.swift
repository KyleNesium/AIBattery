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

    /// A 429 (or any other unexpected status) from the token endpoint says nothing about
    /// the refresh token — it must be retried next cycle, never sign the account out.
    @Test func rateLimitedAndUnexpectedStatusesAreTransient() {
        for status in [408, 425, 429, 499] {
            let result = CodexTokenClient.interpretTokenResponse(statusCode: status, data: Data())
            guard case .failure(let error) = result else { Issue.record("expected failure for \(status)"); return }
            #expect(error.isTransient, "status \(status) must be transient")
        }
    }

    /// Codex sign-in errors speak for OpenAI, never Anthropic, and a user cancel is silent.
    @Test func codexErrorsUseOpenAIVoice() {
        guard case .failure(let rejected) = CodexTokenClient.interpretTokenResponse(statusCode: 400, data: Data()) else {
            Issue.record("expected failure"); return
        }
        #expect(rejected.userMessage.contains("OpenAI"))
        #expect(!rejected.userMessage.contains("Anthropic"))
        #expect(!rejected.userMessage.contains("authorization code"))

        guard case .failure(let transient) = CodexTokenClient.interpretTokenResponse(statusCode: 502, data: Data()) else {
            Issue.record("expected failure"); return
        }
        #expect(transient.userMessage.contains("OpenAI"))
        #expect(!transient.userMessage.contains("Anthropic"))

        let cancelled = OAuthManager.AuthError.codexCallbackFailure(.providerError("cancelled"))
        #expect(cancelled.isCancellation)
        #expect(cancelled.userMessage.isEmpty)
        let timeout = OAuthManager.AuthError.codexCallbackFailure(.providerError("timeout"))
        #expect(!timeout.isCancellation)
        #expect(timeout.userMessage.contains("timed out"))
        #expect(!timeout.userMessage.contains("providerError"))
        let denied = OAuthManager.AuthError.codexCallbackFailure(.providerError("access_denied"))
        #expect(denied.userMessage.contains("access_denied"))
        #expect(OAuthManager.AuthError.codexCallbackFailure(.missingState).userMessage.contains("redirect"))
    }

    /// The refresh grant is not guaranteed to echo `id_token`; only the code exchange
    /// needs it (to derive the account id). A 200 without it is still a good token set.
    @Test func refreshResponseWithoutIdTokenIsAccepted() throws {
        let body = Data(#"{"access_token":"a2","refresh_token":"r2"}"#.utf8)
        let set = try CodexTokenClient.interpretTokenResponse(statusCode: 200, data: body).get()
        #expect(set.idToken == nil)
        #expect(set.accessToken == "a2")
        #expect(set.refreshToken == "r2")
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

    @Test func exchangeEscapesPlusInCode() async throws {
        let captured = CapturedRequest()
        _ = await CodexTokenClient.exchangeCode("ab+cd", verifier: "VERIF", transport: { request in
            await captured.set(request)
            return (Data("{\"id_token\":\"i\",\"access_token\":\"a\",\"refresh_token\":\"r\"}".utf8),
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let request = try #require(await captured.get())
        let bodyData = try #require(request.httpBody)
        let body = try #require(String(data: bodyData, encoding: .utf8))
        #expect(body.contains("code=ab%2Bcd"))
        #expect(!body.contains("code=ab+cd"))
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
