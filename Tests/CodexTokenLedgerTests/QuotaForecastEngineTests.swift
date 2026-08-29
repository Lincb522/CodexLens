import XCTest
@testable import CodexTokenLedger

final class QuotaForecastEngineTests: XCTestCase {
    func testForecastUsesObservedQuotaSlopeAndStopsAtReset() throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let reset = now.addingTimeInterval(2 * 3_600)
        let window = CodexQuotaWindow(
            id: "primary",
            title: "Primary",
            usedPercent: 40,
            windowMinutes: 300,
            resetsAt: reset
        )
        let samples = [
            sample(at: now.addingTimeInterval(-3_600), used: 20, reset: reset),
            sample(at: now.addingTimeInterval(-1_800), used: 30, reset: reset),
        ]

        let forecast = QuotaForecastEngine().forecast(
            accountID: "account",
            window: window,
            samples: samples,
            now: now
        )

        XCTAssertEqual(forecast.state, .lastsUntilReset)
        XCTAssertEqual(try XCTUnwrap(forecast.usedPercentPerHour), 20, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(forecast.estimatedTimeToExhaustion), 3 * 3_600, accuracy: 1)
        XCTAssertEqual(forecast.sampleCount, 3)
    }

    func testForecastReportsDepletionBeforeReset() throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let reset = now.addingTimeInterval(4 * 3_600)
        let window = CodexQuotaWindow(
            id: "primary",
            title: "Primary",
            usedPercent: 80,
            windowMinutes: 300,
            resetsAt: reset
        )
        let samples = [
            sample(at: now.addingTimeInterval(-3_600), used: 40, reset: reset),
            sample(at: now.addingTimeInterval(-1_800), used: 60, reset: reset),
        ]

        let forecast = QuotaForecastEngine().forecast(
            accountID: "account",
            window: window,
            samples: samples,
            now: now
        )

        XCTAssertEqual(forecast.state, .depletesBeforeReset)
        XCTAssertEqual(try XCTUnwrap(forecast.estimatedTimeToExhaustion), 1_800, accuracy: 1)
    }

    func testForecastDoesNotInventPaceFromOneSample() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let window = CodexQuotaWindow(
            id: "primary",
            title: "Primary",
            usedPercent: 50,
            windowMinutes: 300,
            resetsAt: now.addingTimeInterval(3_600)
        )

        let forecast = QuotaForecastEngine().forecast(
            accountID: "account",
            window: window,
            samples: [],
            now: now
        )

        XCTAssertEqual(forecast.state, .collecting)
        XCTAssertNil(forecast.estimatedTimeToExhaustion)
        XCTAssertNil(forecast.usedPercentPerHour)
    }

    func testForecastRejectsSamplesFromAnotherResetCycle() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let currentReset = now.addingTimeInterval(3_600)
        let oldReset = now.addingTimeInterval(-3_600)
        let window = CodexQuotaWindow(
            id: "primary",
            title: "Primary",
            usedPercent: 10,
            windowMinutes: 300,
            resetsAt: currentReset
        )
        let samples = [sample(at: now.addingTimeInterval(-600), used: 95, reset: oldReset)]

        let forecast = QuotaForecastEngine().forecast(
            accountID: "account",
            window: window,
            samples: samples,
            now: now
        )

        XCTAssertEqual(forecast.state, .collecting)
        XCTAssertEqual(forecast.sampleCount, 1)
    }

    func testForecastDoesNotTurnStaleSnapshotIntoANewObservation() {
        let observedAt = Date(timeIntervalSince1970: 2_000_000_000)
        let reset = observedAt.addingTimeInterval(4 * 3_600)
        let window = CodexQuotaWindow(
            id: "primary",
            title: "Primary",
            usedPercent: 20,
            windowMinutes: 300,
            resetsAt: reset
        )
        let forecast = QuotaForecastEngine().forecast(
            accountID: "account",
            window: window,
            samples: [sample(at: observedAt, used: 20, reset: reset)],
            observedAt: observedAt,
            now: observedAt.addingTimeInterval(3_600)
        )

        XCTAssertEqual(forecast.state, .collecting)
        XCTAssertEqual(forecast.sampleCount, 1)
    }

    func testCapacityEstimateUsesPairedOfficialQuotaAndTokenDeltas() throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let reset = now.addingTimeInterval(3_600)
        let window = CodexQuotaWindow(
            id: "primary",
            title: "Primary",
            usedPercent: 40,
            windowMinutes: 300,
            resetsAt: reset
        )
        let samples = [
            sample(at: now.addingTimeInterval(-3_600), used: 20, reset: reset, lifetime: 1_000_000),
            sample(at: now.addingTimeInterval(-1_800), used: 30, reset: reset, lifetime: 1_500_000),
        ]

        let estimate = try XCTUnwrap(QuotaForecastEngine().capacityEstimate(
            accountID: "account",
            window: window,
            lifetimeTokens: 2_000_000,
            samples: samples,
            observedAt: now,
            now: now
        ))

        XCTAssertEqual(estimate.estimatedTotalTokens, 5_000_000)
        XCTAssertEqual(estimate.estimatedRemainingTokens, 3_000_000)
        XCTAssertEqual(estimate.tokensPerPercent, 50_000, accuracy: 0.001)
        XCTAssertEqual(estimate.samplePairCount, 3)
        XCTAssertEqual(estimate.evidence, .pairedAccountCounters)
    }

    func testCapacityEstimateWaitsForAtLeastOnePercentOfMovement() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let reset = now.addingTimeInterval(3_600)
        let window = CodexQuotaWindow(
            id: "primary",
            title: "Primary",
            usedPercent: 20.5,
            windowMinutes: 300,
            resetsAt: reset
        )
        let estimate = QuotaForecastEngine().capacityEstimate(
            accountID: "account",
            window: window,
            lifetimeTokens: 1_100_000,
            samples: [sample(
                at: now.addingTimeInterval(-600),
                used: 20,
                reset: reset,
                lifetime: 1_000_000
            )],
            observedAt: now,
            now: now
        )

        XCTAssertNil(estimate)
    }

    func testCurrentCycleCapacityUsesExactCycleTokenObservation() throws {
        let observedAt = Date(timeIntervalSince1970: 2_000_000_000)
        let reset = observedAt.addingTimeInterval(2 * 24 * 3_600)
        let window = CodexQuotaWindow(
            id: "weekly",
            title: "Weekly",
            usedPercent: 40,
            windowMinutes: 10_080,
            resetsAt: reset
        )
        let usage = LocalQuotaCycleUsage(
            resetsAt: reset,
            observedAt: observedAt,
            totalTokens: 1_000_000,
            sessionCount: 1
        )

        let estimate = try XCTUnwrap(QuotaForecastEngine().currentCycleCapacityEstimate(
            window: window,
            usage: usage,
            observedAt: observedAt
        ))

        XCTAssertEqual(estimate.estimatedTotalTokens, 2_500_000)
        XCTAssertEqual(estimate.estimatedRemainingTokens, 1_500_000)
        XCTAssertEqual(estimate.observedTokens, 1_000_000)
        XCTAssertEqual(estimate.evidence, .currentCycleLocalLedger)
    }

    func testCurrentCycleCapacityDoesNotInventAValueAtZeroPercent() {
        let observedAt = Date(timeIntervalSince1970: 2_000_000_000)
        let window = CodexQuotaWindow(
            id: "weekly",
            title: "Weekly",
            usedPercent: 0,
            windowMinutes: 10_080,
            resetsAt: observedAt.addingTimeInterval(2 * 24 * 3_600)
        )

        XCTAssertNil(QuotaForecastEngine().currentCycleCapacityEstimate(
            window: window,
            usage: LocalQuotaCycleUsage(
                resetsAt: try XCTUnwrap(window.resetsAt),
                observedAt: observedAt,
                totalTokens: 1_000,
                sessionCount: 1
            ),
            observedAt: observedAt
        ))
    }

    private func sample(
        at date: Date,
        used: Double,
        reset: Date,
        lifetime: Int64? = nil
    ) -> QuotaUsageSample {
        QuotaUsageSample(
            accountID: "account",
            windowID: "primary",
            observedAt: date,
            usedPercent: used,
            resetsAt: reset,
            windowMinutes: 300,
            lifetimeTokens: lifetime
        )
    }
}
