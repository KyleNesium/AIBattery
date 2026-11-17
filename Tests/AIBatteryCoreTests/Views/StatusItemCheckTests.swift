import Foundation
import Testing
@testable import AIBatteryCore

/// The launch check only writes a log line, so what matters is that it names the right
/// reason. These pin the decision on plain values; no status item is created.
@Suite("StatusItemCheck")
struct StatusItemCheckTests {
    private let healthy = StatusItemCheck.Observation(
        isVisible: true,
        hasWindow: true,
        buttonWidth: 54,
        windowSize: CGSize(width: 54, height: 24),
        hasScreen: true,
        occlusionVisible: true
    )

    @Test func anItemOnScreenHasNoProblem() {
        #expect(StatusItemCheck.problem(with: healthy) == nil)
    }

    /// Each way the item can be missing gets its own reason, checked in order, so the log
    /// line says which one it was.
    @Test func eachWayOfBeingHiddenIsNamed() {
        var hidden = healthy
        hidden.isVisible = false
        #expect(StatusItemCheck.problem(with: hidden) == "isVisible is false")

        var windowless = healthy
        windowless.hasWindow = false
        #expect(StatusItemCheck.problem(with: windowless) == "the button has no window")

        // A zero-height window at the origin, as reported for an item macOS 27 never hosted.
        var flat = healthy
        flat.windowSize = CGSize(width: 54, height: 0)
        #expect(StatusItemCheck.problem(with: flat) == "it has no size")

        var offScreen = healthy
        offScreen.hasScreen = false
        #expect(StatusItemCheck.problem(with: offScreen) == "its window is on no screen")
    }

    /// Measured on macOS 26.5: every on-screen menu bar item window belongs to Control
    /// Center, so an app's own status window reads occlusionVisible = false whether or not
    /// its item is shown. Treating that as hidden would log an error on every launch.
    @Test func occlusionAloneIsNotAProblem() {
        var shownByTheSystem = healthy
        shownByTheSystem.occlusionVisible = false
        #expect(StatusItemCheck.problem(with: shownByTheSystem) == nil)
    }

    @Test func theSummaryCarriesEveryReading() {
        #expect(healthy.summary == "isVisible=true window=true button=54 frame=54x24 screen=true occlusionVisible=true")
    }
}
