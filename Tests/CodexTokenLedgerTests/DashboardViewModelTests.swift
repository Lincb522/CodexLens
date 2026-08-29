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
    func testLaunchAtLoginUsesSystemServiceState() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "CodexTokenLedger.LaunchAtLogin.\(UUID().uuidString)"))
        let controller = LaunchAtLoginControllerStub(status: .disabled)
        let viewModel = DashboardViewModel(
            defaults: defaults,
            launchAtLoginController: controller
        )

        XCTAssertFalse(viewModel.launchAtLoginEnabled)

        viewModel.setLaunchAtLogin(true)
        XCTAssertEqual(controller.registerCount, 1)
        XCTAssertTrue(viewModel.launchAtLoginEnabled)
        XCTAssertFalse(viewModel.launchAtLoginRequiresApproval)

        controller.status = .requiresApproval
        viewModel.refreshLaunchAtLoginState()
        XCTAssertTrue(viewModel.launchAtLoginEnabled)
        XCTAssertTrue(viewModel.launchAtLoginRequiresApproval)

        viewModel.setLaunchAtLogin(false)
        XCTAssertEqual(controller.unregisterCount, 1)
        XCTAssertFalse(viewModel.launchAtLoginEnabled)
    }

    @MainActor
    func testLaunchAtLoginExplainsReadOnlyDiskImage() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "CodexTokenLedger.LaunchAtLoginReadOnly.\(UUID().uuidString)"))
        let controller = LaunchAtLoginControllerStub(
            status: .disabled,
            registrationIssue: .readOnlyVolume
        )
        let viewModel = DashboardViewModel(
            defaults: defaults,
            launchAtLoginController: controller
        )
        viewModel.appLanguage = .zhHans

        viewModel.setLaunchAtLogin(true)

        XCTAssertEqual(controller.registerCount, 0)
        XCTAssertEqual(viewModel.launchAtLoginErrorMessage, "拖到“应用程序”后再开启")
        XCTAssertFalse(viewModel.launchAtLoginEnabled)
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

    @MainActor
    func testAccountDailyUsageUsesNewestServerBucketAndItsActualDate() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "CodexTokenLedger.DailyUsage.\(UUID().uuidString)"))
        let viewModel = DashboardViewModel(defaults: defaults)
        viewModel.appLanguage = .zhHans
        let account = CodexAccountUsageSnapshot(
            id: "account",
            email: nil,
            plan: nil,
            codexHome: "/tmp/codex",
            primaryWindow: nil,
            secondaryWindow: nil,
            additionalWindows: [],
            credits: nil,
            accountTokenUsage: CodexAccountTokenUsage(
                summary: CodexAccountTokenUsageSummary(
                    lifetimeTokens: 3_000,
                    peakDailyTokens: nil,
                    longestRunningTurnSeconds: nil,
                    currentStreakDays: nil,
                    longestStreakDays: nil
                ),
                dailyBuckets: [
                    CodexAccountDailyTokenUsage(startDate: "2020-01-02", tokens: 2_000),
                    CodexAccountDailyTokenUsage(startDate: "2020-01-01", tokens: 1_000),
                ]
            ),
            updatedAt: Date()
        )

        XCTAssertEqual(viewModel.accountDailyValue(account), "2.0K")
        XCTAssertTrue(viewModel.accountDailyTitle(account).contains("1/2"))
        XCTAssertFalse(viewModel.accountDailyTitle(account).contains("今日"))
    }

    @MainActor
    func testConversationTotalAPIEstimateUsesCumulativeCounterAtStandardRate() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "CodexTokenLedger.LiveCost.\(UUID().uuidString)"))
        let viewModel = DashboardViewModel(defaults: defaults)
        let base = context(id: "cost", input: 300_000, updatedAt: Date())
        viewModel.liveContext = CodexLiveContextSnapshot(
            id: base.id,
            sourcePath: base.sourcePath,
            projectPath: base.projectPath,
            threadTitle: base.threadTitle,
            titleSource: base.titleSource,
            turnID: base.turnID,
            model: base.model,
            reasoningEffort: base.reasoningEffort,
            updatedAt: base.updatedAt,
            lastRequest: base.lastRequest,
            currentTurnUsage: base.currentTurnUsage,
            currentTurnCalls: base.currentTurnCalls,
            taskTotal: TokenUsage(inputTokens: 1_000_000),
            modelContextWindow: base.modelContextWindow,
            duplicateEventsIgnored: base.duplicateEventsIgnored,
            isTaskActive: true
        )

        XCTAssertEqual(viewModel.liveTaskAPIUSD?.total, Decimal(4))
        XCTAssertEqual(viewModel.liveTaskAPIUSD?.isLongContext, false)
    }

    @MainActor
    func testWeeklyQuotaValueUsesSelectedAccountLedgerInsteadOfLiveTask() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "CodexTokenLedger.QuotaValue.\(UUID().uuidString)"))
        let now = Date()
        let reset = now.addingTimeInterval(3 * 24 * 60 * 60)
        let samples = [
            QuotaUsageSample(
                accountID: "account",
                windowID: "weekly",
                observedAt: now.addingTimeInterval(-3_600),
                usedPercent: 10,
                resetsAt: reset,
                windowMinutes: 10_080,
                lifetimeTokens: 1_000_000
            )
        ]
        let viewModel = DashboardViewModel(defaults: defaults, initialQuotaHistorySamples: samples)
        let account = CodexAccountUsageSnapshot(
            id: "account",
            email: "pro@example.com",
            plan: "pro",
            codexHome: "/tmp/account",
            primaryWindow: CodexQuotaWindow(
                id: "primary",
                title: "5-hour quota",
                usedPercent: 5,
                windowMinutes: 300,
                resetsAt: now.addingTimeInterval(3_600)
            ),
            secondaryWindow: CodexQuotaWindow(
                id: "weekly",
                title: "Weekly quota",
                usedPercent: 20,
                windowMinutes: 10_080,
                resetsAt: reset
            ),
            additionalWindows: [],
            credits: nil,
            accountTokenUsage: CodexAccountTokenUsage(
                summary: CodexAccountTokenUsageSummary(
                    lifetimeTokens: 2_000_000,
                    peakDailyTokens: nil,
                    longestRunningTurnSeconds: nil,
                    currentStreakDays: nil,
                    longestStreakDays: nil
                ),
                dailyBuckets: []
            ),
            updatedAt: now
        )
        viewModel.accountSnapshots = [account]
        viewModel.selectedAccountID = account.id
        viewModel.activeAccountID = account.id
        viewModel.snapshot = UsageSnapshot(
            scannedAt: now,
            codexHome: account.codexHome,
            fileCount: 1,
            records: [
                UsageRecord(
                    id: "luna-ledger",
                    timestamp: now,
                    sessionID: "ledger",
                    sourcePath: "/tmp/ledger.jsonl",
                    projectPath: "/Projects/Ledger",
                    model: "gpt-5.6-luna",
                    reasoningEffort: "medium",
                    usage: TokenUsage(inputTokens: 1_000_000)
                )
            ],
            sessions: [],
            issues: []
        )
        viewModel.liveContext = context(id: "unrelated-sol-task", input: 1_000_000, updatedAt: now)

        let estimate = try XCTUnwrap(viewModel.selectedQuotaValueEstimate)
        XCTAssertEqual(estimate.weeklyTokens, 10_000_000)
        XCTAssertEqual(estimate.remainingWeeklyTokens, 8_000_000)
        XCTAssertEqual(estimate.monthlyTokens, 43_481_250)
        XCTAssertEqual(estimate.weeklyAPIEquivalentUSD, Decimal(4))
        XCTAssertEqual(estimate.remainingAPIEquivalentUSD, Decimal(string: "3.2"))
        XCTAssertEqual(estimate.monthlyAPIEquivalentUSD, Decimal(string: "17.3925"))
        XCTAssertEqual(estimate.pricedSampleTokens, 1_000_000)
        XCTAssertEqual(estimate.localTokenCoverage, 1)
        XCTAssertEqual(estimate.pricedModelCount, 1)
    }

    @MainActor
    func testCodeReviewWindowIsNotUsedAsAccountWeeklyCapacity() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "CodexTokenLedger.ReviewCapacity.\(UUID().uuidString)"))
        let now = Date()
        let reset = now.addingTimeInterval(3 * 24 * 60 * 60)
        let viewModel = DashboardViewModel(
            defaults: defaults,
            initialQuotaHistorySamples: [
                QuotaUsageSample(
                    accountID: "account",
                    windowID: "code-review",
                    observedAt: now.addingTimeInterval(-3_600),
                    usedPercent: 10,
                    resetsAt: reset,
                    windowMinutes: 10_080,
                    lifetimeTokens: 1_000_000
                )
            ]
        )
        viewModel.accountSnapshots = [
            CodexAccountUsageSnapshot(
                id: "account",
                email: nil,
                plan: "pro",
                codexHome: "/tmp/account",
                primaryWindow: nil,
                secondaryWindow: nil,
                additionalWindows: [
                    CodexQuotaWindow(
                        id: "code-review",
                        title: "Code review",
                        usedPercent: 20,
                        windowMinutes: 10_080,
                        resetsAt: reset
                    )
                ],
                credits: nil,
                accountTokenUsage: CodexAccountTokenUsage(
                    summary: CodexAccountTokenUsageSummary(
                        lifetimeTokens: 2_000_000,
                        peakDailyTokens: nil,
                        longestRunningTurnSeconds: nil,
                        currentStreakDays: nil,
                        longestStreakDays: nil
                    ),
                    dailyBuckets: []
                ),
                updatedAt: now
            )
        ]
        viewModel.selectedAccountID = "account"

        XCTAssertNil(viewModel.selectedQuotaCapacityEstimate)
        XCTAssertNil(viewModel.selectedQuotaValueEstimate)
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

private final class LaunchAtLoginControllerStub: LaunchAtLoginControlling {
    var status: LaunchAtLoginStatus
    var registrationIssue: LaunchAtLoginRegistrationIssue?
    private(set) var registerCount = 0
    private(set) var unregisterCount = 0

    init(
        status: LaunchAtLoginStatus,
        registrationIssue: LaunchAtLoginRegistrationIssue? = nil
    ) {
        self.status = status
        self.registrationIssue = registrationIssue
    }

    func register() throws {
        registerCount += 1
        status = .enabled
    }

    func unregister() throws {
        unregisterCount += 1
        status = .disabled
    }

    func openSystemSettings() {}
}
