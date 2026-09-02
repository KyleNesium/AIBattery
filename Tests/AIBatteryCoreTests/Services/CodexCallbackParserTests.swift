import Testing
@testable import AIBatteryCore

@Suite("CodexCallbackParser")
struct CodexCallbackParserTests {
    @Test func parsesCodeAndState() throws {
        let head = "GET /auth/callback?code=abc123&state=xyz789 HTTP/1.1"
        let parsed = try CodexCallbackParser.parse(requestHead: head).get()
        #expect(parsed.code == "abc123")
        #expect(parsed.state == "xyz789")
    }

    @Test func percentDecodesValues() throws {
        let head = "GET /auth/callback?state=s%2B1&code=c%2Fx HTTP/1.1"
        let parsed = try CodexCallbackParser.parse(requestHead: head).get()
        #expect(parsed.code == "c/x")
        #expect(parsed.state == "s+1")
    }

    @Test func surfacesProviderError() {
        let head = "GET /auth/callback?error=access_denied HTTP/1.1"
        let result = CodexCallbackParser.parse(requestHead: head)
        guard case .failure(.providerError("access_denied")) = result else {
            Issue.record("Expected .failure(.providerError(\"access_denied\")), got \(result)")
            return
        }
    }

    @Test func rejectsOtherPathsAndMissingParams() {
        let favicon = CodexCallbackParser.parse(requestHead: "GET /favicon.ico HTTP/1.1")
        guard case .failure(.notCallbackPath) = favicon else {
            Issue.record("Expected .failure(.notCallbackPath), got \(favicon)")
            return
        }
        let missingCode = CodexCallbackParser.parse(requestHead: "GET /auth/callback?state=s HTTP/1.1")
        guard case .failure(.missingCode) = missingCode else {
            Issue.record("Expected .failure(.missingCode), got \(missingCode)")
            return
        }
        let missingState = CodexCallbackParser.parse(requestHead: "GET /auth/callback?code=c HTTP/1.1")
        guard case .failure(.missingState) = missingState else {
            Issue.record("Expected .failure(.missingState), got \(missingState)")
            return
        }
    }
}
