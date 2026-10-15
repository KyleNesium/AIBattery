import CoreGraphics
import Testing
@testable import AIBatteryCore

@Suite("BurnSparkline geometry")
struct BurnSparklineTests {
    @Test func points_spanTheWidth_andNormaliseToThePeak() {
        let size = CGSize(width: 190, height: 14)
        let points = BurnSparkline.points(counts: [0, 50, 100, 25], in: size)
        #expect(points.count == 4)
        #expect(points.first?.x == 0)
        #expect(points.last?.x == 190)
        // The peak touches the top inset; zero sits on the baseline.
        #expect(points[2].y == CGFloat(Layout.sparklineLineWidth))
        #expect(points[0].y == 14)
        #expect(points[1].y > points[2].y && points[1].y < points[0].y)
    }

    @Test func points_flatSeries_sitsOnTheBaseline() {
        let points = BurnSparkline.points(counts: [0, 0, 0], in: CGSize(width: 100, height: 14))
        #expect(points.allSatisfy { $0.y == 14 })
    }

    @Test func points_needAtLeastTwoBuckets() {
        #expect(BurnSparkline.points(counts: [7], in: CGSize(width: 100, height: 14)).isEmpty)
        #expect(BurnSparkline.points(counts: [], in: CGSize(width: 100, height: 14)).isEmpty)
    }
}
