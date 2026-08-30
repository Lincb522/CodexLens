import XCTest
@testable import CodexTokenLedger

final class TokenAccountingTests: XCTestCase {
    func testSubsetAccountingDoesNotDoubleCountCacheOrReasoning() {
        let breakdown = TokenBreakdown.subset(
            inputTotal: 100,
            cacheRead: 40,
            cacheWrite: 10,
            outputTotal: 30,
            reasoning: 12,
            total: 130
        )

        XCTAssertTrue(breakdown.isValid)
        XCTAssertEqual(breakdown.quality, .complete)
        XCTAssertEqual(breakdown.input.uncachedTokens, 50)
        XCTAssertEqual(breakdown.output.nonReasoningTokens, 18)
        XCTAssertEqual(breakdown.totalTokens, 130)
    }

    func testPartialSubsetPreservesAuthoritativeRemainder() {
        let breakdown = TokenBreakdown.partialSubset(
            inputTotal: 10,
            cacheRead: 4,
            cacheWrite: 0,
            outputTotal: 0,
            reasoning: 0,
            total: 15
        )

        XCTAssertTrue(breakdown.isValid)
        XCTAssertEqual(breakdown.quality, .unclassified)
        XCTAssertEqual(breakdown.input.totalTokens, 10)
        XCTAssertEqual(breakdown.unclassifiedTokens, 5)
    }

    func testIndependentAccountingKeepsCacheBucketsOutsideInput() {
        let breakdown = TokenBreakdown.independent(
            uncachedInput: 30,
            cacheRead: 7,
            cacheWrite: 13,
            nonReasoningOutput: 5,
            reasoning: 0,
            total: 55
        )

        XCTAssertTrue(breakdown.isValid)
        XCTAssertEqual(breakdown.input.totalTokens, 50)
        XCTAssertEqual(breakdown.totalTokens, 55)
    }

    func testSeparateReasoningAccountingAddsReasoningToOutput() {
        let breakdown = TokenBreakdown.separateReasoning(
            inputTotal: 20,
            cacheRead: 5,
            cacheWrite: 0,
            nonReasoningOutput: 7,
            reasoning: 3,
            total: 30
        )

        XCTAssertTrue(breakdown.isValid)
        XCTAssertEqual(breakdown.output.totalTokens, 10)
        XCTAssertEqual(breakdown.totalTokens, 30)
    }

    func testContradictoryParentTotalBecomesInconsistentAndUnclassified() {
        let breakdown = TokenBreakdown.subset(
            inputTotal: 10,
            cacheRead: 4,
            cacheWrite: 0,
            outputTotal: 3,
            reasoning: 1,
            total: 20
        )

        XCTAssertTrue(breakdown.isValid)
        XCTAssertEqual(breakdown.quality, .inconsistent)
        XCTAssertEqual(breakdown.totalTokens, 20)
        XCTAssertEqual(breakdown.unclassifiedTokens, 20)
        XCTAssertEqual(breakdown.input.totalTokens, 0)
        XCTAssertEqual(breakdown.output.totalTokens, 0)
    }

    func testUnclassifiedAccountingDoesNotInventBuckets() {
        let breakdown = TokenBreakdown.unclassified(total: 42)

        XCTAssertTrue(breakdown.isValid)
        XCTAssertEqual(breakdown.quality, .unclassified)
        XCTAssertEqual(breakdown.unclassifiedTokens, 42)
        XCTAssertEqual(breakdown.input.totalTokens, 0)
        XCTAssertEqual(breakdown.output.totalTokens, 0)
    }

    func testCodexParserAcceptsCPAFieldNamesAndNestedDetails() throws {
        let direct = try XCTUnwrap(CodexTokenUsageParser.parse([
            "input_tokens": 100,
            "output_tokens": 30,
            "cache_read_tokens": 40,
            "cache_creation_tokens": 10,
            "reasoning_tokens": 12,
            "total_tokens": 130,
        ]))
        let nested = try XCTUnwrap(CodexTokenUsageParser.parse([
            "input_tokens": 100,
            "output_tokens": 30,
            "input_tokens_details": ["cached_tokens": 40, "cache_write_tokens": 10],
            "output_tokens_details": ["reasoning_tokens": 12],
            "total_tokens": 130,
        ]))

        for usage in [direct, nested] {
            XCTAssertEqual(usage.accountingQuality, .complete)
            XCTAssertEqual(usage.inputTokens, 100)
            XCTAssertEqual(usage.uncachedInputTokens, 50)
            XCTAssertEqual(usage.cachedInputTokens, 40)
            XCTAssertEqual(usage.cacheWriteInputTokens, 10)
            XCTAssertEqual(usage.outputTokens, 30)
            XCTAssertEqual(usage.nonReasoningOutputTokens, 18)
            XCTAssertEqual(usage.reasoningOutputTokens, 12)
            XCTAssertEqual(usage.totalTokens, 130)
        }
    }

    func testExplicitCanonicalZeroIsNotOverriddenByLegacyAlias() throws {
        let usage = try XCTUnwrap(CodexTokenUsageParser.parse([
            "input_tokens": 100,
            "output_tokens": 20,
            "cache_read_tokens": 0,
            "cached_input_tokens": 30,
            "total_tokens": 120,
        ]))

        XCTAssertEqual(usage.cachedInputTokens, 0)
        XCTAssertEqual(usage.uncachedInputTokens, 100)
    }

    func testCodexParserPreservesTotalOnlyLegacyUsage() throws {
        let usage = try XCTUnwrap(CodexTokenUsageParser.parse([
            "input_tokens": 0,
            "output_tokens": 0,
            "total_tokens": 9_657,
        ]))

        XCTAssertEqual(usage.accountingQuality, .unclassified)
        XCTAssertEqual(usage.totalTokens, 9_657)
        XCTAssertEqual(usage.unclassifiedTokens, 9_657)
        XCTAssertFalse(usage.hasCompleteBreakdown)
    }

    func testCodexParserKeepsContradictoryTotalButDoesNotPriceIt() throws {
        let usage = try XCTUnwrap(CodexTokenUsageParser.parse([
            "input_tokens": 100,
            "output_tokens": 20,
            "reasoning_output_tokens": 5,
            "total_tokens": 125,
        ]))

        XCTAssertEqual(usage.accountingQuality, .inconsistent)
        XCTAssertEqual(usage.totalTokens, 125)
        XCTAssertEqual(usage.unclassifiedTokens, 125)
        XCTAssertFalse(BillingCalculator.cost(for: usage, model: "gpt-5.6-sol").isPriced)
    }

    func testNegativeAndOverflowingCountersNeverCreateInvalidBreakdown() {
        let negative = TokenBreakdown.subset(
            inputTotal: -1,
            cacheRead: 0,
            cacheWrite: 0,
            outputTotal: 2,
            reasoning: 0,
            total: 9
        )
        let overflow = TokenBreakdown.subset(
            inputTotal: .max,
            cacheRead: 0,
            cacheWrite: 0,
            outputTotal: 1,
            reasoning: 0,
            total: 42
        )

        XCTAssertTrue(negative.isValid)
        XCTAssertEqual(negative.quality, .inconsistent)
        XCTAssertEqual(negative.totalTokens, 9)
        XCTAssertTrue(overflow.isValid)
        XCTAssertEqual(overflow.quality, .inconsistent)
        XCTAssertEqual(overflow.totalTokens, 42)
    }

    func testCumulativeDeltaUsesMutuallyExclusiveBuckets() throws {
        let previous = TokenUsage(
            inputTokens: 100,
            cachedInputTokens: 40,
            cacheWriteInputTokens: 10,
            outputTokens: 30,
            reasoningOutputTokens: 12
        )
        let current = TokenUsage(
            inputTokens: 250,
            cachedInputTokens: 100,
            cacheWriteInputTokens: 20,
            outputTokens: 70,
            reasoningOutputTokens: 22
        )

        let delta = try XCTUnwrap(current.subtracting(previous))
        XCTAssertEqual(delta.inputTokens, 150)
        XCTAssertEqual(delta.uncachedInputTokens, 80)
        XCTAssertEqual(delta.cachedInputTokens, 60)
        XCTAssertEqual(delta.cacheWriteInputTokens, 10)
        XCTAssertEqual(delta.outputTokens, 40)
        XCTAssertEqual(delta.nonReasoningOutputTokens, 30)
        XCTAssertEqual(delta.reasoningOutputTokens, 10)
        XCTAssertEqual(delta.totalTokens, 190)
    }

    func testInconsistentCumulativePointFallsBackToAuthoritativeTotalDelta() throws {
        let previous = try XCTUnwrap(CodexTokenUsageParser.parse([
            "input_tokens": 100,
            "output_tokens": 20,
            "total_tokens": 120,
        ]))
        let current = try XCTUnwrap(CodexTokenUsageParser.parse([
            "input_tokens": 200,
            "output_tokens": 40,
            "total_tokens": 250,
        ]))

        let delta = try XCTUnwrap(current.subtracting(previous))
        XCTAssertEqual(current.accountingQuality, .inconsistent)
        XCTAssertEqual(delta.accountingQuality, .unclassified)
        XCTAssertEqual(delta.totalTokens, 130)
        XCTAssertEqual(delta.unclassifiedTokens, 130)
        XCTAssertFalse(BillingCalculator.cost(for: delta, model: "gpt-5.6-sol").isPriced)
    }

    func testV2BreakdownRoundTripsAndLegacyFlatCacheStillDecodes() throws {
        let usage = TokenUsage(
            inputTokens: 100,
            cachedInputTokens: 40,
            cacheWriteInputTokens: 10,
            outputTokens: 30,
            reasoningOutputTokens: 12
        )
        let encoded = try JSONEncoder().encode(usage)
        let roundTrip = try JSONDecoder().decode(TokenUsage.self, from: encoded)
        let legacy = try JSONDecoder().decode(
            TokenUsage.self,
            from: Data(#"{"inputTokens":100,"cachedInputTokens":40,"outputTokens":30}"#.utf8)
        )

        XCTAssertEqual(roundTrip, usage)
        XCTAssertEqual(roundTrip.accountingSchemaVersion, 2)
        XCTAssertEqual(legacy.totalTokens, 130)
        XCTAssertEqual(legacy.uncachedInputTokens, 60)
    }
}
