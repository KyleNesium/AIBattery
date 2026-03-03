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
}
