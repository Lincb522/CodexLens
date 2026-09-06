import Foundation
import XCTest
@testable import CodexTokenLedger

final class OverviewUsageRangeTests: XCTestCase {
    func testMonthToDateUsesInclusiveUTCDaysWithoutFilteringCompleteHistory() throws {
        let heatmap = TokenUsageHeatmap.make(dailyBuckets: [
            .init(startDate: "2026-08-31", tokens: 900),
            .init(startDate: "2026-09-01", tokens: 100),
            .init(startDate: "2026-09-06", tokens: 300),
            .init(startDate: "2026-09-06", tokens: 200),
            .init(startDate: "2026-09-07", tokens: 800),
        ], referenceDate: try date("2026-09-06T23:30:00Z"))
        let days = OverviewUsageRange.monthToDate.days(in: heatmap)
        XCTAssertEqual(days.map(\.dateKey), (1...6).map { "2026-09-0\($0)" })
        XCTAssertEqual(days.map(\.tokens), [100, 0, 0, 0, 0, 300])
        XCTAssertEqual(days.map(\.intensity), [1, 0, 0, 0, 0, 2])
        XCTAssertEqual(heatmap.days.count, 371)
        XCTAssertEqual(heatmap.totalTokens, 1_300)
        XCTAssertFalse(days.contains(where: \.isFuture))
    }

    func testPresetsCrossMonthsAndYearsAndFollowMonthRollover() throws {
        for (stamp, first, count) in [
            ("2024-02-29T23:59:59Z", "2024-02-01", 29),
            ("2024-03-01T00:00:00Z", "2024-03-01", 1),
            ("2026-09-30T23:59:59Z", "2026-09-01", 30),
            ("2026-01-01T00:00:00Z", "2026-01-01", 1),
            ("2026-09-01T01:00:00+08:00", "2026-08-01", 31),
        ] {
            let heatmap = TokenUsageHeatmap.make(dailyBuckets: [], referenceDate: try date(stamp))
            let days = OverviewUsageRange.monthToDate.days(in: heatmap)
            XCTAssertEqual(days.first?.dateKey, first)
            XCTAssertEqual(days.count, count)
            XCTAssertEqual(days.last?.date, heatmap.today)
            XCTAssertEqual(OverviewUsageRange.last7Days.days(in: heatmap).count, 7)
            XCTAssertEqual(OverviewUsageRange.last30Days.days(in: heatmap).count, 30)
        }
    }

    func testCustomDatesAreInclusiveNormalizedClampedAndKeepIntensity() throws {
        let heatmap = TokenUsageHeatmap.make(dailyBuckets: [], referenceDate: try date("2026-09-06T12:00:00Z"))
        let selection = OverviewUsageRange.custom(start: try date("2026-09-02T16:00:00Z"), end: try date("2026-08-30T05:00:00Z"))
        XCTAssertEqual(selection.days(in: heatmap).map(\.dateKey), ["2026-08-30", "2026-08-31", "2026-09-01", "2026-09-02"])
        let outside = OverviewUsageRange.custom(start: .distantPast, end: .distantFuture)
        XCTAssertEqual(outside.resolved(in: heatmap), heatmap.rangeStart...heatmap.today)
        XCTAssertEqual(outside.days(in: heatmap), heatmap.days.filter { !$0.isFuture })
        let future = OverviewUsageRange.custom(start: try date("2027-01-01T00:00:00Z"), end: .distantFuture)
        XCTAssertEqual(future.days(in: heatmap).map(\.dateKey), ["2026-09-06"])
        let past = OverviewUsageRange.custom(start: .distantPast, end: try date("2020-01-01T00:00:00Z"))
        XCTAssertEqual(past.days(in: heatmap).map(\.date), [heatmap.rangeStart])
    }

    func testDayOpensTheHistoryHalfContainingItIncludingBoundary() throws {
        let heatmap = TokenUsageHeatmap.make(dailyBuckets: [], referenceDate: try date("2026-09-06T12:00:00Z"))
        for (index, day) in heatmap.days.enumerated() {
            XCTAssertEqual(heatmap.showsRecentHalf(for: day), index >= 26 * 7)
        }
    }

    private func date(_ value: String) throws -> Date {
        try XCTUnwrap(ISO8601DateFormatter().date(from: value))
    }
}
