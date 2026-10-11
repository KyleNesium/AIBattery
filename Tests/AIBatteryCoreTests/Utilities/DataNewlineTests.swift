import Foundation
import Testing
@testable import AIBatteryCore

@Suite("Data.firstNewlineIndex")
struct DataNewlineTests {
    @Test func findsNewlines_andHonoursStart() {
        let data = Data("ab\ncd\nef".utf8)
        #expect(data.firstNewlineIndex(from: 0) == 2)
        #expect(data.firstNewlineIndex(from: 3) == 5)
        #expect(data.firstNewlineIndex(from: 6) == nil)
        #expect(data.firstNewlineIndex(from: 99) == nil)
    }

    @Test func worksOnSlicesWithNonZeroStartIndex() {
        let data = Data("xxxx\nab\ncd".utf8)
        let slice = data[5...] // startIndex == 5
        #expect(slice.firstNewlineIndex(from: slice.startIndex) == 7)
        #expect(slice.firstNewlineIndex(from: 8) == nil)
        #expect(Data().firstNewlineIndex(from: 0) == nil)
    }
}
