import Testing
import Foundation
@testable import AIBatteryCore

@Suite("MenuBarSparkline")
struct MenuBarSparklineTests {

    @Test func hashConsistency() {
        let data: [String: Int] = ["0": 5, "1": 10, "12": 3]
        let hash1 = MenuBarSparkline.dataHash(data)
        let hash2 = MenuBarSparkline.dataHash(data)
        #expect(hash1 == hash2)
    }

    @Test func differentData_differentHash() {
        let data1: [String: Int] = ["0": 5, "1": 10]
        let data2: [String: Int] = ["0": 5, "1": 11]
        #expect(MenuBarSparkline.dataHash(data1) != MenuBarSparkline.dataHash(data2))
    }

    @Test func missingHours_defaultToZero() {
        // Only hour "5" has data — other 23 hours should be zero
        let sparse: [String: Int] = ["5": 42]
        let full: [String: Int] = {
            var d: [String: Int] = [:]
            for h in 0..<24 { d[String(h)] = h == 5 ? 42 : 0 }
            return d
        }()
        #expect(MenuBarSparkline.dataHash(sparse) == MenuBarSparkline.dataHash(full))
    }

    @Test func allZeros_equalToEmpty() {
        let empty: [String: Int] = [:]
        let zeros: [String: Int] = Dictionary(uniqueKeysWithValues: (0..<24).map { (String($0), 0) })
        #expect(MenuBarSparkline.dataHash(empty) == MenuBarSparkline.dataHash(zeros))
    }

    @Test func fullData_producesStableHash() {
        let data: [String: Int] = Dictionary(uniqueKeysWithValues: (0..<24).map { (String($0), $0 * 10) })
        let hash = MenuBarSparkline.dataHash(data)
        // Just verify it's deterministic (not zero, not crashing)
        #expect(hash != 0)
        #expect(MenuBarSparkline.dataHash(data) == hash)
    }
}
