import Testing
import Foundation
@testable import AIBatteryCore

@Suite("IdleSuspendPolicy")
struct IdleSuspendPolicyTests {
    @Test("shouldSuspend false just under threshold")
    func justUnderThreshold() {
        #expect(!IdleSuspendPolicy.shouldSuspend(secondsIdle: 299, threshold: 300))
    }

    @Test("shouldSuspend true exactly at threshold")
    func exactlyAtThreshold() {
        #expect(IdleSuspendPolicy.shouldSuspend(secondsIdle: 300, threshold: 300))
    }

    @Test("shouldSuspend true well over threshold")
    func wellOverThreshold() {
        #expect(IdleSuspendPolicy.shouldSuspend(secondsIdle: 600, threshold: 300))
    }

    @Test("shouldSuspend false for active user")
    func activeUser() {
        #expect(!IdleSuspendPolicy.shouldSuspend(secondsIdle: 0, threshold: 300))
    }

    @Test("shouldSuspend false for negative idle time")
    func negativeGuard() {
        #expect(!IdleSuspendPolicy.shouldSuspend(secondsIdle: -1, threshold: 300))
    }

    @Test("idleSeconds returns non-negative value")
    func idleSecondsSmoke() {
        let seconds = IdleSuspendPolicy.idleSeconds()
        #expect(seconds >= 0)
    }
}
