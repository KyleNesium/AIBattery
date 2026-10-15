import Testing
@testable import AIBatteryCore

@Suite("PopoverMode")
struct PopoverModeTests {
    @Test func initial_overviewOnlyWithTwoOrMore() {
        #expect(PopoverMode.initial(eligibleAccountCount: 0) == .detail)
        #expect(PopoverMode.initial(eligibleAccountCount: 1) == .detail)
        #expect(PopoverMode.initial(eligibleAccountCount: 2) == .overview)
        #expect(PopoverMode.initial(eligibleAccountCount: 6) == .overview)
    }

    @Test func onShow_firstOpenDecides_laterOpensRemember() {
        // First open after launch: the account count decides.
        #expect(PopoverMode.onShow(remembered: nil, eligibleAccountCount: 2) == .overview)
        #expect(PopoverMode.onShow(remembered: nil, eligibleAccountCount: 1) == .detail)
        // Later opens: drill in, click away, come back → still in the account.
        #expect(PopoverMode.onShow(remembered: .detail, eligibleAccountCount: 2) == .detail)
        #expect(PopoverMode.onShow(remembered: .overview, eligibleAccountCount: 2) == .overview)
        // …unless the remembered face is no longer valid.
        #expect(PopoverMode.onShow(remembered: .overview, eligibleAccountCount: 1) == .detail)
    }

    @Test func next_dropsToDetailWhenOneAccountRemains_keepsDetailOtherwise() {
        #expect(PopoverMode.next(current: .overview, eligibleAccountCount: 1) == .detail)
        #expect(PopoverMode.next(current: .overview, eligibleAccountCount: 0) == .detail)
        #expect(PopoverMode.next(current: .overview, eligibleAccountCount: 2) == .overview)
        // Gaining an account must not yank the user out of the detail view they chose.
        #expect(PopoverMode.next(current: .detail, eligibleAccountCount: 3) == .detail)
        #expect(PopoverMode.next(current: .detail, eligibleAccountCount: 1) == .detail)
    }

    @Test func escape_goesBackFromDetailWithoutSettings_elseCloses() {
        #expect(PopoverEscapeRouting.consume(mode: .detail, showSettings: false, showsBack: true) == .backToOverview)
        #expect(PopoverEscapeRouting.consume(mode: .detail, showSettings: true, showsBack: true) == .close)
        #expect(PopoverEscapeRouting.consume(mode: .detail, showSettings: false, showsBack: false) == .close)
        #expect(PopoverEscapeRouting.consume(mode: .overview, showSettings: false, showsBack: true) == .close)
        #expect(PopoverEscapeRouting.consume(mode: .overview, showSettings: true, showsBack: false) == .close)
    }
}
