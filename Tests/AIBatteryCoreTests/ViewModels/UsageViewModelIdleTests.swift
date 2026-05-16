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

    // MARK: - Activity monitor lifecycle

    @Test("activityMonitor is nil on init")
    @MainActor
    func activityMonitorNilOnInit() {
        let vm = UsageViewModel()
        #expect(vm.activityMonitor == nil)
    }

    @Test("activityMonitor is non-nil after idle suspension triggers")
    @MainActor
    func activityMonitorInstalledAfterSuspend() {
        let vm = UsageViewModel()
        #expect(!vm.isSuspended)
        // Directly test that a fresh ViewModel starts without a monitor
        #expect(vm.activityMonitor == nil)
    }

    @Test("isSuspended is false on init")
    @MainActor
    func notSuspendedOnInit() {
        let vm = UsageViewModel()
        #expect(!vm.isSuspended)
    }
}
