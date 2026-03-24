import Testing
import Foundation
@testable import AIBatteryCore

@Suite("UsageViewModel Idle")
struct UsageViewModelIdleTests {

    @Test("idle threshold is 5 minutes")
    func idleThresholdIsFiveMinutes() {
        #expect(IdleSuspendPolicy.defaultThreshold == 300)
    }

    @Test("shouldSuspend false below threshold")
    func idleCheckBelowThreshold() {
        #expect(!IdleSuspendPolicy.shouldSuspend(secondsIdle: 299))
    }

    @Test("shouldSuspend true at threshold")
    func idleCheckAtThreshold() {
        #expect(IdleSuspendPolicy.shouldSuspend(secondsIdle: 300))
    }
}
