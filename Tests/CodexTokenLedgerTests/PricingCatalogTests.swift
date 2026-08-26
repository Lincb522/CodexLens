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
}
