import XCTest
@testable import CodexTokenLedger

final class PricingCatalogTests: XCTestCase {
    func testCurrentAliasesNormalizeToSol() {
        XCTAssertEqual(PricingCatalog.normalize(model: "gpt-5.6"), "gpt-5.6-sol")
        XCTAssertEqual(PricingCatalog.normalize(model: "gpt-5.6-sol"), "gpt-5.6-sol")
    }

    func testSpecificVariantsWinBeforeGenericFamily() {
        XCTAssertEqual(PricingCatalog.normalize(model: "gpt-5.6-terra"), "gpt-5.6-terra")
        XCTAssertEqual(PricingCatalog.normalize(model: "gpt-5.6-luna"), "gpt-5.6-luna")
        XCTAssertEqual(PricingCatalog.normalize(model: "gpt-5.4-mini"), "gpt-5.4-mini")
    }

    func testGPT56FamilyUsesPublished105MContextCapacity() {
        XCTAssertEqual(PricingCatalog.publishedContextWindow(for: "gpt-5.6"), 1_050_000)
        XCTAssertEqual(PricingCatalog.publishedContextWindow(for: "gpt-5.6-terra"), 1_050_000)
        XCTAssertEqual(PricingCatalog.publishedContextWindow(for: "gpt-5.6-luna"), 1_050_000)
    }

    func testGPT56APIRatesCarryRequestScopedLongContextTier() throws {
        for model in ["gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna"] {
            let rate = try XCTUnwrap(PricingCatalog.rate(for: model))
            XCTAssertEqual(rate.longContextThreshold, 272_000)
            XCTAssertEqual(rate.longContextInputMultiplier, 2)
            XCTAssertEqual(rate.longContextOutputMultiplier, Decimal(string: "1.5"))
        }
    }

    func testPublishedRateCardModelsArePriced() throws {
        let expected: [String: (Decimal, Decimal, Decimal)] = [
            "gpt-5.5": (5, Decimal(string: "0.5")!, 30),
            "daybreak-blue": (4, Decimal(string: "0.4")!, 20),
            "daybreak-red": (Decimal(string: "12.5")!, Decimal(string: "1.25")!, 75),
            "gpt-5.4": (Decimal(string: "2.5")!, Decimal(string: "0.25")!, 15),
            "gpt-5.4-mini": (Decimal(string: "0.75")!, Decimal(string: "0.075")!, Decimal(string: "4.5")!),
            "gpt-5.3-codex": (Decimal(string: "1.75")!, Decimal(string: "0.175")!, 14),
            "gpt-5.2": (Decimal(string: "1.75")!, Decimal(string: "0.175")!, 14),
        ]
        for (model, values) in expected {
            let rate = try XCTUnwrap(PricingCatalog.rate(for: model))
            XCTAssertEqual(rate.inputPerMillion, values.0, model)
            XCTAssertEqual(rate.cachedInputPerMillion, values.1, model)
            XCTAssertEqual(rate.outputPerMillion, values.2, model)
        }
    }

    func testLongContextSurchargeIsNotAppliedToModelsWithoutPublishedTier() throws {
        let rate = try XCTUnwrap(PricingCatalog.rate(for: "gpt-5.5"))
        XCTAssertNil(rate.longContextThreshold)
        let cost = BillingCalculator.cost(
            for: TokenUsage(inputTokens: 300_000, outputTokens: 1_000),
            model: "gpt-5.5"
        )
        XCTAssertFalse(cost.isLongContext)
        XCTAssertEqual(cost.total, Decimal(string: "1.53")!)
    }
}
