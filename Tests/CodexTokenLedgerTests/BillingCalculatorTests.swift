import XCTest
@testable import CodexTokenLedger

final class BillingCalculatorTests: XCTestCase {
    func testAuthoritativeTotalWithoutBreakdownIsCountedButNeverPriced() {
        let usage = TokenUsage(
            inputTokens: 0,
            outputTokens: 0,
            reportedTotalTokens: 9_657
        )

        XCTAssertTrue(usage.isValidCodexCounter)
        XCTAssertFalse(usage.hasCompleteBreakdown)
        XCTAssertEqual(usage.totalTokens, 9_657)
        XCTAssertFalse(BillingCalculator.cost(for: usage, model: "gpt-5.6-sol").isPriced)
    }

    func testAPILongContextMultiplierIsAppliedPerRequest() {
        let usage = TokenUsage(inputTokens: 300_000, outputTokens: 1_000)

        let result = BillingCalculator.cost(for: usage, model: "gpt-5.6-sol")

        XCTAssertTrue(result.isLongContext)
        XCTAssertEqual(result.input, Decimal(string: "2.4")!)
        XCTAssertEqual(result.output, Decimal(string: "0.03")!)
        XCTAssertEqual(result.total, Decimal(string: "2.43")!)
    }

    func testCumulativeSessionDoesNotInventPerRequestLongContextSurcharge() {
        let record = UsageRecord(
            id: "session-1|cumulative",
            timestamp: Date(timeIntervalSince1970: 0),
            sessionID: "session-1",
            sourcePath: "/tmp/session.jsonl",
            projectPath: nil,
            model: "gpt-5.6-sol",
            reasoningEffort: nil,
            usage: TokenUsage(inputTokens: 300_000, outputTokens: 1_000)
        )

        let total = BillingCalculator.total(records: [record])

        XCTAssertTrue(total.isPriced)
        XCTAssertEqual(total.total, Decimal(string: "1.22")!)
    }

    func testCacheWriteUsesPublished125PercentAPIRate() {
        let usage = TokenUsage(
            inputTokens: 1_000,
            cachedInputTokens: 400,
            cacheWriteInputTokens: 100,
            outputTokens: 0
        )

        let result = BillingCalculator.cost(for: usage, model: "gpt-5.6-sol")

        XCTAssertEqual(result.input, Decimal(string: "0.002")!)
        XCTAssertEqual(result.cachedInput, Decimal(string: "0.00016")!)
        XCTAssertEqual(result.cacheWrite, Decimal(string: "0.0005")!)
        XCTAssertEqual(result.total, Decimal(string: "0.00266")!)
    }

    func testUnknownModelRemainsUnpricedWithoutLosingTokens() {
        let usage = TokenUsage(inputTokens: 42, outputTokens: 8)
        let result = BillingCalculator.cost(for: usage, model: "future-model")

        XCTAssertFalse(result.isPriced)
        XCTAssertEqual(result.total, 0)
        XCTAssertEqual(usage.totalTokens, 50)
    }

    func testAggregateCostNeverHidesAnUnpricedRecord() {
        let known = UsageRecord(
            id: "known",
            timestamp: .distantPast,
            sessionID: "one",
            sourcePath: "/tmp/one.jsonl",
            projectPath: nil,
            model: "gpt-5.6-sol",
            reasoningEffort: nil,
            usage: TokenUsage(inputTokens: 1_000, outputTokens: 100)
        )
        let unknown = UsageRecord(
            id: "unknown",
            timestamp: .distantPast,
            sessionID: "two",
            sourcePath: "/tmp/two.jsonl",
            projectPath: nil,
            model: "unpublished-model",
            reasoningEffort: nil,
            usage: TokenUsage(inputTokens: 2_000, outputTokens: 200)
        )

        XCTAssertFalse(BillingCalculator.total(records: [known, unknown]).isPriced)
    }

    func testTurnPricingPreservesPerCallLongContextBoundaries() {
        let calls = [
            CodexModelCallUsage(
                id: "call-1",
                timestamp: .distantPast,
                model: "gpt-5.6-sol",
                usage: TokenUsage(inputTokens: 150_000, outputTokens: 500),
                cumulativeTaskUsage: TokenUsage(inputTokens: 150_000, outputTokens: 500)
            ),
            CodexModelCallUsage(
                id: "call-2",
                timestamp: .distantPast,
                model: "gpt-5.6-sol",
                usage: TokenUsage(inputTokens: 150_000, outputTokens: 500),
                cumulativeTaskUsage: TokenUsage(inputTokens: 300_000, outputTokens: 1_000)
            ),
        ]

        let perCall = BillingCalculator.cost(calls: calls)
        let incorrectlyMerged = BillingCalculator.cost(
            for: TokenUsage(inputTokens: 300_000, outputTokens: 1_000),
            model: "gpt-5.6-sol",
            applyLongContextMultiplier: true
        )

        XCTAssertTrue(perCall.isPriced)
        XCTAssertFalse(perCall.isLongContext)
        XCTAssertEqual(perCall.total, Decimal(string: "1.22")!)
        XCTAssertEqual(incorrectlyMerged.total, Decimal(string: "2.43")!)
    }
}
