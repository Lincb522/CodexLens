import XCTest
@testable import CodexTokenLedger

final class TokenDisplayTests: XCTestCase {
    func testFullCountsPreserveEveryDigitAndCompactCountsUseUnits() {
        let locale = Locale(identifier: "en_US")
        for value: Int64 in [0, 999, 1_000, 24_800, 1_200_000, 2_700_000_000, .max, .min] {
            XCTAssertEqual(DisplayFormat.tokens(value, abbreviated: false, locale: locale),
                           value.formatted(.number.grouping(.automatic).locale(locale)))
        }
        for (value, expected): (Int64, String) in [(0, "0"), (999, "999"), (1_000, "1.0K"),
                                                   (24_800, "24.8K"), (1_200_000, "1.20M"),
                                                   (2_700_000_000, "2.70B"), (1_000_000_000_000, "1.00T")] {
            XCTAssertEqual(DisplayFormat.tokens(value, abbreviated: true, locale: locale), expected)
        }
        XCTAssertEqual(DisplayFormat.tokens(24_800, abbreviated: true, locale: Locale(identifier: "fr")), "24,8K")
    }

    @MainActor
    func testPreferenceChangesFormattingAndPersistsBothStates() throws {
        let suite = "CodexTokenLedger.TokenDisplay.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let viewModel = DashboardViewModel(defaults: defaults)
        viewModel.appLanguage = .english
        XCTAssertFalse(viewModel.abbreviateTokenCounts)
        XCTAssertEqual(viewModel.tokenText(24_800), "24,800")
        viewModel.abbreviateTokenCounts = true
        XCTAssertEqual(viewModel.tokenText(24_800), "24.8K")
        viewModel.persistPreferences()
        XCTAssertTrue(DashboardViewModel(defaults: defaults).abbreviateTokenCounts)
        viewModel.abbreviateTokenCounts = false
        viewModel.persistPreferences()
        XCTAssertFalse(DashboardViewModel(defaults: defaults).abbreviateTokenCounts)
    }

    func testTooltipUsesTheSameDisplayChoiceWithoutChangingDate() throws {
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-27T23:30:00Z"))
        XCTAssertEqual(DisplayFormat.dailyTokenUsage(date: date, tokens: 660_000_001, language: .zhHans, abbreviated: true),
                       "2026年8月27日 使用了 660.00M Token")
        for language in AppLanguage.allCases where language != .system {
            XCTAssertFalse(LocalizationCatalog.text("console.abbreviateTokens", language: language).contains("console."))
        }
    }
}
