import Testing
@testable import AIBatteryCore

@Suite("PopoverHeader back control")
struct PopoverHeaderBackTests {
    @Test func showsBack_onlyWithAnOverviewToReturnTo() {
        #expect(PopoverHeaderView.showsBack(eligibleAccountCount: 0) == false)
        #expect(PopoverHeaderView.showsBack(eligibleAccountCount: 1) == false)
        #expect(PopoverHeaderView.showsBack(eligibleAccountCount: 2))
        #expect(PopoverHeaderView.showsBack(eligibleAccountCount: 6))
    }
}
