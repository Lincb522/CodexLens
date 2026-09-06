import Foundation
import XCTest
@testable import CodexTokenLedger

final class TokenUsageHeatmapTests: XCTestCase {
    func testBuildsFixedFiftyThreeWeekGridFromServerDailyBuckets() throws {
        let now = try XCTUnwrap(isoDate("2026-09-03"))
        let heatmap = TokenUsageHeatmap.make(
            dailyBuckets: [
                CodexAccountDailyTokenUsage(startDate: "2026-09-03", tokens: 400),
                CodexAccountDailyTokenUsage(startDate: "2026-08-20", tokens: 100),
                CodexAccountDailyTokenUsage(startDate: "2025-01-01", tokens: 9_999),
            ],
            referenceDate: now
        )

        XCTAssertEqual(heatmap.weeks.count, 53)
        XCTAssertTrue(heatmap.weeks.allSatisfy { $0.count == 7 })
        XCTAssertEqual(heatmap.days.count, 371)
        XCTAssertEqual(heatmap.monthStarts.count, 12)
        XCTAssertEqual(heatmap.totalTokens, 500)
        XCTAssertEqual(heatmap.last30DaysTokens, 500)
        XCTAssertEqual(heatmap.activeDays, 2)
        XCTAssertEqual(heatmap.peakTokens, 400)
        XCTAssertEqual(heatmap.days.first { $0.dateKey == "2026-09-03" }?.intensity, 4)
        XCTAssertTrue(heatmap.days.contains { $0.isFuture })
    }

    func testDuplicateServerDaysUseLatestDailyTotalWithoutDoubleCounting() throws {
        let now = try XCTUnwrap(isoDate("2026-09-03"))
        let heatmap = TokenUsageHeatmap.make(
            dailyBuckets: [
                CodexAccountDailyTokenUsage(startDate: "2026-09-03T00:00:00Z", tokens: 100),
                CodexAccountDailyTokenUsage(startDate: "2026-09-03", tokens: 300),
                CodexAccountDailyTokenUsage(startDate: "invalid", tokens: 1_000),
                CodexAccountDailyTokenUsage(startDate: "2026-09-02", tokens: -10),
            ],
            referenceDate: now
        )

        XCTAssertEqual(heatmap.totalTokens, 300)
        XCTAssertEqual(heatmap.activeDays, 1)
        XCTAssertEqual(heatmap.days.first { $0.dateKey == "2026-09-03" }?.tokens, 300)
        XCTAssertEqual(heatmap.days.first { $0.dateKey == "2026-09-02" }?.intensity, 0)
    }

    func testLargeDailyTotalsKeepDistinctRelativeDisplayLevels() throws {
        let now = try XCTUnwrap(isoDate("2026-09-03"))
        let amounts: [Int64] = [40_000_000, 100_000_000, 200_000_000, 400_000_000]
        let days = ["2026-08-31", "2026-09-01", "2026-09-02", "2026-09-03"]
        for scale in [Int64(1), 10] {
            let heatmap = TokenUsageHeatmap.make(
                dailyBuckets: zip(days, amounts).map { CodexAccountDailyTokenUsage(startDate: $0, tokens: $1 * scale) },
                referenceDate: now
            )
            XCTAssertEqual(days.compactMap { key in heatmap.days.first { $0.dateKey == key }?.intensity }, [1, 2, 3, 4])
            XCTAssertEqual(heatmap.totalTokens, 740_000_000 * scale)
            XCTAssertEqual(heatmap.last30DaysTokens, 740_000_000 * scale)
            XCTAssertEqual(heatmap.activeDays, 4)
        }
    }

    private func isoDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }
}
