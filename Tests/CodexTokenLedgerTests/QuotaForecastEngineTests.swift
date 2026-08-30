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

    private func sample(
        at date: Date,
        used: Double,
        reset: Date
    ) -> QuotaUsageSample {
        QuotaUsageSample(
            accountID: "account",
            windowID: "primary",
            observedAt: date,
            usedPercent: used,
            resetsAt: reset,
            windowMinutes: 300
        )
    }
}
