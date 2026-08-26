import XCTest
@testable import CodexTokenLedger

final class DashboardViewModelTests: XCTestCase {
    @MainActor
    func testMenuBarShowsSelectedContextInputAndActiveTaskCount() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "CodexTokenLedger.ViewModel.\(UUID().uuidString)"))
        let viewModel = DashboardViewModel(defaults: defaults)
        let first = context(id: "one", input: 600, updatedAt: Date())
        let second = context(id: "two", input: 1_200, updatedAt: Date().addingTimeInterval(-1))
        viewModel.liveContexts = [first, second]
        viewModel.liveContext = first
        viewModel.selectedLiveContextID = first.id
        viewModel.menuBarMetric = .contextUsed

        XCTAssertEqual(viewModel.activeTaskCount, 2)
        XCTAssertEqual(viewModel.combinedActiveContextInputTokens, 1_800)
        XCTAssertEqual(viewModel.menuBarText, "600 ×2")

        viewModel.selectLiveContext(second.id)
        XCTAssertEqual(viewModel.menuBarText, "1.2K ×2")
    }

    @MainActor
    func testAccountHomeRegistryIsDeduplicatedAndPersistent() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "CodexTokenLedger.AccountHomes.\(UUID().uuidString)"))
        defaults.set("/tmp/codex-account-a", forKey: "codexHomePath")
        defaults.set(
            ["/tmp/codex-account-a", "/tmp/codex-account-a/", "/tmp/codex-account-b"],
            forKey: "accountHomePaths"
        )

        let viewModel = DashboardViewModel(defaults: defaults)
        XCTAssertEqual(Set(viewModel.accountHomePaths).count, viewModel.accountHomePaths.count)
        XCTAssertTrue(viewModel.accountHomePaths.contains("/tmp/codex-account-a"))
        XCTAssertTrue(viewModel.accountHomePaths.contains("/tmp/codex-account-b"))
    }

    @MainActor
    func testThemeLanguageAndConsolePreferencesPersist() throws {
        let suite = "CodexTokenLedger.Preferences.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let viewModel = DashboardViewModel(defaults: defaults)
        viewModel.appLanguage = .japanese
        viewModel.appTheme = .light
        viewModel.liveRefreshRate = .five
        viewModel.discoveryRate = .thirty
        viewModel.accountRefreshRate = .fifteenMinutes
        viewModel.liveTaskLimit = .twelve
        viewModel.privacyMode = true
        viewModel.persistPreferences()

        let restored = DashboardViewModel(defaults: defaults)
        XCTAssertEqual(restored.appLanguage, .japanese)
        XCTAssertEqual(restored.appTheme, .light)
        XCTAssertEqual(restored.liveRefreshRate, .five)
        XCTAssertEqual(restored.discoveryRate, .thirty)
        XCTAssertEqual(restored.accountRefreshRate, .fifteenMinutes)
        XCTAssertEqual(restored.liveTaskLimit, .twelve)
        XCTAssertTrue(restored.privacyMode)
        XCTAssertEqual(restored.t("page.console"), "コントロールセンター")
    }

    @MainActor
    func testCredentialProfileMappingIsSeparateFromMonitoringSnapshotHome() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "CodexTokenLedger.CredentialHomes.\(UUID().uuidString)"))
        defaults.set(["account-a": "/tmp/private-profile/.codex"], forKey: "accountCredentialHomes")
        let viewModel = DashboardViewModel(defaults: defaults)
        let account = CodexAccountUsageSnapshot(
            id: "account-a",
            email: "a@example.com",
            plan: "pro",
            codexHome: "/tmp/runtime-monitor-home",
            primaryWindow: nil,
            secondaryWindow: nil,
            additionalWindows: [],
            credits: nil,
            updatedAt: Date()
        )

        XCTAssertEqual(viewModel.credentialHomePath(for: account), "/tmp/private-profile/.codex")
    }

    @MainActor
    func testAccountActionsAreLocalizedAcrossAllExplicitLanguages() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "CodexTokenLedger.AccountLocalization.\(UUID().uuidString)"))
        let viewModel = DashboardViewModel(defaults: defaults)
        for language in AppLanguage.allCases where language != .system {
            viewModel.appLanguage = language
            XCTAssertNotEqual(viewModel.t("account.monitorOnly"), "account.monitorOnly")
            XCTAssertNotEqual(viewModel.t("account.activateCodex"), "account.activateCodex")
            XCTAssertNotEqual(viewModel.t("account.importJSON"), "account.importJSON")
            XCTAssertNotEqual(viewModel.t("account.oauth"), "account.oauth")
            XCTAssertNotEqual(viewModel.t("account.tokenLogin"), "account.tokenLogin")
            XCTAssertNotEqual(viewModel.t("account.tokenSubmit"), "account.tokenSubmit")
            XCTAssertTrue(
                LocalizationCatalog.missingKeys(for: language).isEmpty,
                "\(language.rawValue) is missing: \(LocalizationCatalog.missingKeys(for: language))"
            )
        }
    }

    private func context(id: String, input: Int64, updatedAt: Date) -> CodexLiveContextSnapshot {
        CodexLiveContextSnapshot(
            id: id,
            sourcePath: "/tmp/\(id).jsonl",
            projectPath: "/Projects/\(id)",
            threadTitle: "Task \(id)",
            titleSource: .desktopCatalog,
            turnID: "turn-\(id)",
            model: "gpt-5.6-sol",
            reasoningEffort: "high",
            updatedAt: updatedAt,
            lastRequest: TokenUsage(inputTokens: input, cachedInputTokens: input / 2, outputTokens: 50),
            currentTurnUsage: TokenUsage(inputTokens: input, cachedInputTokens: input / 2, outputTokens: 50),
            currentTurnCalls: [],
            taskTotal: TokenUsage(inputTokens: input, outputTokens: 50),
            modelContextWindow: 258_400,
            duplicateEventsIgnored: 0,
            isTaskActive: true
        )
    }
}
