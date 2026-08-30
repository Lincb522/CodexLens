import XCTest
@testable import CodexTokenLedger

final class SubscriptionQuotaEstimateTests: XCTestCase {
    func testPro20xUsesLatestControlledCommunityMeasurement() throws {
        let estimate = try XCTUnwrap(SubscriptionQuotaEstimate.forPlan("pro"))

        XCTAssertEqual(estimate.tier, .pro20x)
        XCTAssertEqual(estimate.weeklyCredits, 53_600, accuracy: 0.001)
        XCTAssertEqual(estimate.weeklyAPIEquivalentUSD, 2_144, accuracy: 0.001)
        XCTAssertEqual(estimate.weeklyAPILowerBoundUSD, 2_080, accuracy: 0.001)
        XCTAssertEqual(estimate.weeklyAPIUpperBoundUSD, 2_240, accuracy: 0.001)
        XCTAssertEqual(estimate.monthlyAPIEquivalentUSD, 9_322.38, accuracy: 0.01)
        XCTAssertEqual(
            estimate.remainingAPIEquivalentUSD(remainingPercent: 38),
            814.72,
            accuracy: 0.001
        )
    }

    func testPlanTierSelectsReferenceEstimateWithoutTaskUsage() throws {
        let plus = try XCTUnwrap(SubscriptionQuotaEstimate.forPlan("plus"))
        let pro5x = try XCTUnwrap(SubscriptionQuotaEstimate.forPlan("prolite"))

        XCTAssertEqual(plus.weeklyAPIEquivalentUSD, 105, accuracy: 0.001)
        XCTAssertEqual(pro5x.weeklyAPIEquivalentUSD, 537.5, accuracy: 0.001)
        XCTAssertNil(SubscriptionQuotaEstimate.forPlan("unknown"))
    }

    func testServerPlanNamesIdentifyCurrentPlanTier() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let pro = CodexAccountUsageSnapshot(
            id: "pro",
            email: nil,
            plan: "pro",
            codexHome: "/tmp/.codex",
            primaryWindow: nil,
            secondaryWindow: nil,
            additionalWindows: [],
            credits: nil,
            updatedAt: now
        )
        let pro5x = CodexAccountUsageSnapshot(
            id: "prolite",
            email: nil,
            plan: "prolite",
            codexHome: "/tmp/.codex-prolite",
            primaryWindow: nil,
            secondaryWindow: nil,
            additionalWindows: [],
            credits: nil,
            updatedAt: now
        )

        XCTAssertEqual(pro.planDisplayName, "Pro 20x")
        XCTAssertEqual(pro5x.planDisplayName, "Pro 5x")
    }

    func testQuotaUSDUsesFullGroupedValues() {
        XCTAssertEqual(DisplayFormat.quotaUSD(1_672.32), "US$1,672")
        XCTAssertEqual(DisplayFormat.quotaUSD(2_144), "US$2,144")
        XCTAssertEqual(DisplayFormat.quotaUSD(9_322.38), "US$9,322")
    }
}
