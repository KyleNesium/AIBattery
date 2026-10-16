import Foundation
import Testing
@testable import AIBatteryCore

@Suite("SecureNetworking")
struct SecureNetworkingTests {
    @Test func session_usesEphemeralConfiguration() {
        let config = SecureNetworking.session.configuration
        // Ephemeral sessions have no persistent disk cache
        #expect(config.urlCache == nil || config.urlCache?.diskCapacity == 0)
    }

    @Test func session_isSingleton() {
        let a = SecureNetworking.session
        let b = SecureNetworking.session
        #expect(a === b)
    }

    @Test func maxResponseSize_is2MB() {
        #expect(SecureNetworking.maxResponseSize == 2_000_000)
    }

    @Test func session_doesNotAcceptCookies() {
        let config = SecureNetworking.session.configuration
        #expect(config.httpCookieAcceptPolicy == .never)
        #expect(config.httpShouldSetCookies == false)
    }

    @Test func session_hasResourceTimeout() {
        let config = SecureNetworking.session.configuration
        #expect(config.timeoutIntervalForResource == 30)
    }

    /// Following a 3xx would re-issue the request, Authorization header and all, to
    /// whatever host the Location named. The delegate must hand URLSession nil.
    @Test func redirectDelegate_refusesRedirect() async throws {
        let delegate = SecureNetworking.NoRedirectDelegate()
        let response = try #require(HTTPURLResponse(
            url: #require(URL(string: "https://example.com/a")),
            statusCode: 302,
            httpVersion: nil,
            headerFields: ["Location": "https://evil.example/b"]
        ))
        let newRequest = try URLRequest(url: #require(URL(string: "https://evil.example/b")))

        let delivered: URLRequest? = await withCheckedContinuation { continuation in
            delegate.urlSession(
                SecureNetworking.session,
                task: SecureNetworking.session.dataTask(with: URL(string: "https://example.com/a")!),
                willPerformHTTPRedirection: response,
                newRequest: newRequest
            ) { request in
                continuation.resume(returning: request)
            }
        }

        #expect(delivered == nil)
    }

    /// The session must carry the delegate, or the refusal above never runs.
    @Test func session_installsRedirectDelegate() {
        #expect(SecureNetworking.session.delegate is SecureNetworking.NoRedirectDelegate)
    }
}
