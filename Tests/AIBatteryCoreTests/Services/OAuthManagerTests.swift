import Testing
@testable import AIBatteryCore

@Suite("OAuthManager.AuthError")
struct OAuthManagerAuthErrorTests {

    // MARK: - userMessage

    @Test func userMessage_noVerifier() {
        let error = OAuthManager.AuthError.noVerifier
        #expect(error.userMessage.contains("Auth flow not started"))
    }

    @Test func userMessage_invalidCode() {
        let error = OAuthManager.AuthError.invalidCode
        #expect(error.userMessage.contains("Invalid authorization code"))
    }

    @Test func userMessage_expired() {
        let error = OAuthManager.AuthError.expired
        #expect(error.userMessage.contains("expired"))
    }

    @Test func userMessage_networkError() {
        let error = OAuthManager.AuthError.networkError
        #expect(error.userMessage.contains("Network error"))
    }

    @Test func userMessage_serverError_includesStatusCode() {
        let error = OAuthManager.AuthError.serverError(503)
        #expect(error.userMessage.contains("503"))
    }

    @Test func userMessage_maxAccountsReached() {
        let error = OAuthManager.AuthError.maxAccountsReached
        #expect(error.userMessage.contains("Maximum"))
        #expect(error.userMessage.contains("\(AccountStore.maxAccounts)"))
    }

    @Test func userMessage_unknownError_returnsMessage() {
        let msg = "Something went wrong"
        let error = OAuthManager.AuthError.unknownError(msg)
        #expect(error.userMessage == msg)
    }

    // MARK: - isTransient

    @Test func isTransient_networkError() {
        #expect(OAuthManager.AuthError.networkError.isTransient == true)
    }

    @Test func isTransient_serverError() {
        #expect(OAuthManager.AuthError.serverError(500).isTransient == true)
        #expect(OAuthManager.AuthError.serverError(503).isTransient == true)
    }

    @Test func isTransient_nonTransientErrors() {
        #expect(OAuthManager.AuthError.noVerifier.isTransient == false)
        #expect(OAuthManager.AuthError.invalidCode.isTransient == false)
        #expect(OAuthManager.AuthError.expired.isTransient == false)
        #expect(OAuthManager.AuthError.maxAccountsReached.isTransient == false)
        #expect(OAuthManager.AuthError.unknownError("test").isTransient == false)
    }
}
