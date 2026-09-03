import AppKit
import SwiftUI
import XCTest
@testable import CodexTokenLedger

final class MenuBarVisualSmokeTests: XCTestCase {
    func testOfficialQuotaLabelsFitFixedPanelAcrossLocalizations() {
        let availableWidth = 340.0 - 40.0
        let font = NSFont.systemFont(ofSize: 13, weight: .semibold)

        for language in AppLanguage.allCases where language != .system {
            for key in [
                "quota.accountScope",
                "quota.cycleFiveHours",
                "quota.cycleWeekly",
                "quota.codeCompletionScope",
            ] {
                let label = LocalizationCatalog.text(key, language: language)
                let width = (label as NSString).size(withAttributes: [.font: font]).width
                XCTAssertLessThanOrEqual(width, availableWidth, "\(language.rawValue): \(label)")
            }
        }
    }

    @MainActor
    func testRenderOverviewForVisualInspection() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "CodexTokenLedger.VisualSmoke.\(UUID().uuidString)"))
        let now = Date()
        let previewAccountID = "preview-account"
        let previewReset = now.addingTimeInterval(7_200)
        let quotaSamples = [
            QuotaUsageSample(accountID: previewAccountID, windowID: "primary", observedAt: now.addingTimeInterval(-3_600), usedPercent: 43, resetsAt: now.addingTimeInterval(172_800), windowMinutes: 10_080),
            QuotaUsageSample(accountID: previewAccountID, windowID: "primary", observedAt: now.addingTimeInterval(-1_800), usedPercent: 48, resetsAt: now.addingTimeInterval(172_800), windowMinutes: 10_080),
        ]
        let tiboSignal = TiboResetSignal(
            postID: "2091688655828246890",
            sourceURL: URL(string: "https://x.com/thsottiaux/status/2091688655828246890")!,
            postedAt: now.addingTimeInterval(-(3 * 86_400 + 6 * 3_600)),
            status: .confirmed,
            resetKind: "forced",
            matchedRuleIDs: ["reset-propagated-completed"],
            ruleVersion: TiboResetSignalService.ruleVersion,
            contentHash: String(repeating: "a", count: 64)
        )
        let tiboSnapshot = TiboResetMonitorSnapshot(
            sourceStatus: .healthy,
            checkedAt: now,
            lastSuccessAt: now,
            latestSignal: tiboSignal,
            recentSignals: [tiboSignal],
            lastErrorCode: nil,
            forecast: TiboForecastSnapshot(
                updatedAt: now,
                probability24hPercent: 25,
                probability48hPercent: 45,
                confidence: .low,
                lastResetAt: tiboSignal.postedAt,
                cadence: TiboForecastCadence(
                    recentMedianDays: 2.1,
                    recentSample: 5,
                    weightedMeanDays: 5.1
                ),
                commonTimeWindow: TiboForecastTimeWindow(
                    startHour: 23,
                    endHour: 2,
                    label: "11 PM - 2 AM",
                    timeZoneIdentifier: "UTC"
                ),
                latestResetReason: .milestone25M
            ),
            socialEvidence: [
                TiboSocialEvidence(
                    postID: "2095370639892955269",
                    sourceURL: URL(string: "https://x.com/thsottiaux/status/2095370639892955269")!,
                    postedAt: now.addingTimeInterval(-7 * 3_600),
                    text: "Which Codex reset?",
                    isReply: true,
                    replyingTo: "melvindvivas",
                    signalKind: .context
                )
            ]
        )
        let viewModel = DashboardViewModel(
            defaults: defaults,
            initialQuotaHistorySamples: quotaSamples,
            initialTiboSignalSnapshot: tiboSnapshot
        )
        var records: [UsageRecord] = []
        // More than one eight-row ledger page verifies that the list and pager
        // reach the footer without a scroll view or an empty lower half.
        for offset in 0..<10 {
            let timestamp = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -offset, to: now))
            let input = Int64(2_400_000 + offset * 260_000)
            let cached = Int64(1_900_000 + offset * 210_000)
            let output = Int64(86_000 + offset * 9_000)
            let reasoning = Int64(24_000 + offset * 2_000)
            let record = UsageRecord(
                id: "preview-\(offset)",
                timestamp: timestamp,
                sessionID: "session-\(offset)",
                sourcePath: "/tmp/session-\(offset).jsonl",
                projectPath: offset.isMultiple(of: 2) ? "/Projects/Studio" : "/Projects/Console",
                model: offset.isMultiple(of: 3) ? "gpt-5.6-terra" : "gpt-5.6-sol",
                reasoningEffort: "high",
                usage: TokenUsage(
                    inputTokens: input,
                    cachedInputTokens: cached,
                    outputTokens: output,
                    reasoningOutputTokens: reasoning
                )
            )
            records.append(record)
        }
        let sessions = records.map { record in
            SessionSummary(
                id: record.sessionID,
                startedAt: record.timestamp,
                lastActivityAt: record.timestamp,
                projectPath: record.projectPath,
                latestModel: record.model,
                eventCount: 1,
                usage: record.usage
            )
        }.sorted { $0.lastActivityAt > $1.lastActivityAt }
        viewModel.snapshot = UsageSnapshot(
            scannedAt: now,
            codexHome: "/Users/demo/.codex",
            fileCount: records.count,
            records: records,
            sessions: sessions,
            issues: []
        )
        viewModel.lastScanDuration = 0.7
        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        dayFormatter.dateFormat = "yyyy-MM-dd"
        let previewDailyBuckets = (0..<150).compactMap { offset -> CodexAccountDailyTokenUsage? in
            guard !offset.isMultiple(of: 4),
                  let date = Calendar.current.date(byAdding: .day, value: -offset, to: now)
            else { return nil }
            let wave = Int64((offset % 17) + 1)
            return CodexAccountDailyTokenUsage(
                startDate: dayFormatter.string(from: date),
                tokens: 28_000_000 + wave * 13_400_000
            )
        }
        let account = CodexAccountUsageSnapshot(
            id: previewAccountID,
            email: "designer@example.com",
            plan: "pro",
            codexHome: "/Users/demo/.codex",
            primaryWindow: CodexQuotaWindow(
                id: "primary",
                title: "Weekly quota",
                usedPercent: 48,
                windowMinutes: 10_080,
                resetsAt: now.addingTimeInterval(172_800),
                limitID: "codex"
            ),
            secondaryWindow: nil,
            additionalWindows: [
                CodexQuotaWindow(
                    id: "codex_bengalfox-primary",
                    title: "GPT-5.3-Codex-Spark",
                    usedPercent: 0,
                    windowMinutes: 300,
                    resetsAt: previewReset,
                    limitID: "codex_bengalfox",
                    limitName: "GPT-5.3-Codex-Spark"
                ),
                CodexQuotaWindow(
                    id: "codex_bengalfox-secondary",
                    title: "GPT-5.3-Codex-Spark",
                    usedPercent: 0,
                    windowMinutes: 10_080,
                    resetsAt: now.addingTimeInterval(345_600),
                    limitID: "codex_bengalfox",
                    limitName: "GPT-5.3-Codex-Spark"
                )
            ],
            credits: CodexCreditBalance(hasCredits: true, unlimited: false, balance: 824.35),
            accountTokenUsage: CodexAccountTokenUsage(
                summary: CodexAccountTokenUsageSummary(
                    lifetimeTokens: 24_963_164_410,
                    peakDailyTokens: 1_000_438_359,
                    longestRunningTurnSeconds: 540,
                    currentStreakDays: 2,
                    longestStreakDays: 12
                ),
                dailyBuckets: previewDailyBuckets
            ),
            updatedAt: now
        )
        let secondAccount = CodexAccountUsageSnapshot(
            id: "preview-account-two",
            email: "studio@example.com",
            plan: "team",
            codexHome: "/Users/demo/.codex-studio",
            primaryWindow: CodexQuotaWindow(id: "primary", title: "5 小时额度", usedPercent: 12, windowMinutes: 300, resetsAt: previewReset),
            secondaryWindow: nil,
            additionalWindows: [],
            credits: nil,
            updatedAt: now.addingTimeInterval(-60)
        )
        let thirdAccount = CodexAccountUsageSnapshot(
            id: "preview-account-three",
            email: "lab@example.com",
            plan: "plus",
            codexHome: "/Users/demo/.codex-lab",
            primaryWindow: CodexQuotaWindow(id: "primary", title: "5 小时额度", usedPercent: 54, windowMinutes: 300, resetsAt: previewReset),
            secondaryWindow: nil,
            additionalWindows: [],
            credits: nil,
            updatedAt: now.addingTimeInterval(-120)
        )
        viewModel.accountSnapshots = [account, secondAccount, thirdAccount]
        viewModel.activeAccountID = account.id
        viewModel.selectedAccountID = account.id
        viewModel.liveContext = CodexLiveContextSnapshot(
            id: "preview-live-thread",
            sourcePath: "/Users/demo/.codex/sessions/live.jsonl",
            projectPath: "/Projects/CodexTokenLedger",
            threadTitle: "重构实时 Token 计费与上下文追踪",
            titleSource: .desktopCatalog,
            turnID: "preview-turn",
            model: "gpt-5.6-sol",
            reasoningEffort: "xhigh",
            updatedAt: now,
            lastRequest: TokenUsage(
                inputTokens: 213_505,
                cachedInputTokens: 212_864,
                outputTokens: 242,
                reasoningOutputTokens: 104
            ),
            currentTurnUsage: TokenUsage(
                inputTokens: 1_842_301,
                cachedInputTokens: 1_729_440,
                outputTokens: 8_612,
                reasoningOutputTokens: 4_208
            ),
            currentTurnCalls: [
                CodexModelCallUsage(
                    id: "preview-call-1",
                    timestamp: now.addingTimeInterval(-4),
                    model: "gpt-5.6-sol",
                    usage: TokenUsage(inputTokens: 810_000, cachedInputTokens: 760_000, outputTokens: 4_000),
                    cumulativeTaskUsage: TokenUsage(inputTokens: 52_848_000, outputTokens: 557_192)
                ),
                CodexModelCallUsage(
                    id: "preview-call-2",
                    timestamp: now,
                    model: "gpt-5.6-sol",
                    usage: TokenUsage(inputTokens: 1_032_301, cachedInputTokens: 969_440, outputTokens: 4_612),
                    cumulativeTaskUsage: TokenUsage(inputTokens: 53_880_000, outputTokens: 561_804)
                ),
            ],
            taskTotal: TokenUsage(
                inputTokens: 53_880_000,
                cachedInputTokens: 51_100_000,
                outputTokens: 561_804,
                reasoningOutputTokens: 280_000
            ),
            modelContextWindow: 258_400,
            duplicateEventsIgnored: 1,
            isTaskActive: true
        )
        viewModel.liveContexts = [
            try XCTUnwrap(viewModel.liveContext),
            CodexLiveContextSnapshot(
                id: "preview-live-thread-two",
                sourcePath: "/Users/demo/.codex/sessions/live-two.jsonl",
                projectPath: "/Projects/AnimatedDashboard",
                threadTitle: "打磨多账号切换与动效",
                titleSource: .desktopCatalog,
                turnID: "preview-turn-two",
                model: "gpt-5.6-terra",
                reasoningEffort: "high",
                updatedAt: now.addingTimeInterval(-2),
                lastRequest: TokenUsage(
                    inputTokens: 164_200,
                    cachedInputTokens: 151_040,
                    outputTokens: 188
                ),
                currentTurnUsage: TokenUsage(
                    inputTokens: 922_400,
                    cachedInputTokens: 858_100,
                    outputTokens: 4_210
                ),
                currentTurnCalls: [],
                taskTotal: TokenUsage(inputTokens: 12_880_000, outputTokens: 92_000),
                modelContextWindow: 258_400,
                duplicateEventsIgnored: 0,
                isTaskActive: true
            ),
        ]
        for taskNumber in 3...6 {
            viewModel.liveContexts.append(
                CodexLiveContextSnapshot(
                    id: "preview-live-thread-\(taskNumber)",
                    sourcePath: "/Users/demo/.codex/sessions/live-\(taskNumber).jsonl",
                    projectPath: "/Projects/Workspace\(taskNumber)",
                    threadTitle: "任务 \(taskNumber) · 校准实时上下文与项目识别",
                    titleSource: .desktopCatalog,
                    turnID: "preview-turn-\(taskNumber)",
                    model: taskNumber.isMultiple(of: 2) ? "gpt-5.6-sol" : "gpt-5.6-terra",
                    reasoningEffort: taskNumber.isMultiple(of: 2) ? "xhigh" : "high",
                    updatedAt: now.addingTimeInterval(Double(-taskNumber)),
                    lastRequest: TokenUsage(
                        inputTokens: Int64(118_000 + taskNumber * 9_400),
                        cachedInputTokens: Int64(102_000 + taskNumber * 8_100),
                        outputTokens: Int64(180 + taskNumber * 24)
                    ),
                    currentTurnUsage: TokenUsage(
                        inputTokens: Int64(640_000 + taskNumber * 72_000),
                        cachedInputTokens: Int64(580_000 + taskNumber * 66_000),
                        outputTokens: Int64(2_800 + taskNumber * 310)
                    ),
                    currentTurnCalls: [],
                    taskTotal: TokenUsage(
                        inputTokens: Int64(8_400_000 + taskNumber * 1_100_000),
                        outputTokens: Int64(64_000 + taskNumber * 7_600)
                    ),
                    modelContextWindow: 258_400,
                    duplicateEventsIgnored: 0,
                    isTaskActive: true
                )
            )
        }
        viewModel.selectedLiveContextID = viewModel.liveContext?.id

        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let requestedDarkOutput = ProcessInfo.processInfo.environment["CODEX_LEDGER_PREVIEW_PATH"].map(URL.init(fileURLWithPath:))
        let updateService = AppUpdateService()
        @discardableResult
        func render(
            page: MenuPopoverPage,
            theme: AppTheme,
            output: URL,
            minimumHeight: CGFloat,
            maximumHeight: CGFloat = 900,
            consolePanel: ConsolePanel = .appearance,
            credentialText: String = "",
            legalDocument: LegalDocument = .userAgreement,
            initiallyExpandedLiveDetails: Bool = false
        ) throws -> CGSize {
            viewModel.appTheme = theme
            let view = MenuBarDashboardView(
                updateService: updateService,
                initialPage: page,
                initialConsolePanel: consolePanel,
                initialCredentialText: credentialText,
                initialLegalDocument: legalDocument,
                initiallyExpandedLiveDetails: initiallyExpandedLiveDetails
            )
                .environmentObject(viewModel)
                // Static test images cannot capture the desktop behind a real
                // NSMenu. Supply only a neutral inspection backdrop that
                // matches the requested appearance; production remains clear
                // and AppKit-owned.
                .background(
                    Color(
                        nsColor: theme == .dark
                            ? NSColor(calibratedWhite: 0.10, alpha: 1)
                            : NSColor(calibratedWhite: 0.96, alpha: 1)
                    )
                )
            let host = NSHostingView(rootView: view)
            host.frame = NSRect(x: 0, y: 0, width: 340, height: 1_200)
            host.layoutSubtreeIfNeeded()
            let fittedSize = host.fittingSize
            XCTAssertGreaterThanOrEqual(fittedSize.width, 340)
            XCTAssertGreaterThan(fittedSize.height, minimumHeight)
            XCTAssertLessThan(fittedSize.height, maximumHeight)
            host.frame = NSRect(origin: .zero, size: fittedSize)
            host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            bitmap.size = host.bounds.size
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try FileManager.default.createDirectory(
                at: output.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try png.write(to: output, options: .atomic)
            XCTAssertGreaterThan(png.count, 8_000)
            return fittedSize
        }

        let renders: [(AppTheme, URL)] = [
            (.dark, requestedDarkOutput ?? projectRoot.appendingPathComponent("build/CodexTokenLedger-v2.3-preview-dark.png")),
            (.light, projectRoot.appendingPathComponent("build/CodexTokenLedger-v2.3-preview-light.png")),
        ]
        var darkOverviewHeight: CGFloat?
        var lightOverviewHeight: CGFloat?
        for (theme, output) in renders {
            let size = try render(page: .overview, theme: theme, output: output, minimumHeight: 560, maximumHeight: 850)
            if theme == .dark { darkOverviewHeight = size.height }
            if theme == .light { lightOverviewHeight = size.height }
        }
        let activeTasksLightSize = try render(
            page: .activeTasks,
            theme: .light,
            output: projectRoot.appendingPathComponent("build/CodexTokenLedger-v2.3-active-tasks-light.png"),
            minimumHeight: 650,
            maximumHeight: 750
        )
        XCTAssertEqual(activeTasksLightSize.height, try XCTUnwrap(lightOverviewHeight), accuracy: 0.5)
        let activeTasksDarkSize = try render(
            page: .activeTasks,
            theme: .dark,
            output: projectRoot.appendingPathComponent("build/CodexTokenLedger-v2.3-active-tasks-dark.png"),
            minimumHeight: 650,
            maximumHeight: 750
        )
        XCTAssertEqual(activeTasksDarkSize.height, try XCTUnwrap(darkOverviewHeight), accuracy: 0.5)
        let quotaDetailsLightSize = try render(
            page: .quotaDetails,
            theme: .light,
            output: projectRoot.appendingPathComponent("build/CodexTokenLedger-v2.3-quota-details-light.png"),
            minimumHeight: 650,
            maximumHeight: 750
        )
        XCTAssertEqual(quotaDetailsLightSize.height, try XCTUnwrap(lightOverviewHeight), accuracy: 0.5)
        let quotaDetailsDarkSize = try render(
            page: .quotaDetails,
            theme: .dark,
            output: projectRoot.appendingPathComponent("build/CodexTokenLedger-v2.3-quota-details-dark.png"),
            minimumHeight: 650,
            maximumHeight: 750
        )
        XCTAssertEqual(quotaDetailsDarkSize.height, try XCTUnwrap(darkOverviewHeight), accuracy: 0.5)
        let usageHistoryLightSize = try render(
            page: .usageHistory,
            theme: .light,
            output: projectRoot.appendingPathComponent("build/CodexTokenLedger-v2.3-usage-history-light.png"),
            minimumHeight: 650,
            maximumHeight: 750
        )
        XCTAssertEqual(usageHistoryLightSize.height, try XCTUnwrap(lightOverviewHeight), accuracy: 0.5)
        let usageHistoryDarkSize = try render(
            page: .usageHistory,
            theme: .dark,
            output: projectRoot.appendingPathComponent("build/CodexTokenLedger-v2.3-usage-history-dark.png"),
            minimumHeight: 650,
            maximumHeight: 750
        )
        XCTAssertEqual(usageHistoryDarkSize.height, try XCTUnwrap(darkOverviewHeight), accuracy: 0.5)
        let moreLightSize = try render(
            page: .more,
            theme: .light,
            output: projectRoot.appendingPathComponent("build/CodexTokenLedger-v2.3-more-light.png"),
            minimumHeight: 650,
            maximumHeight: 750
        )
        XCTAssertEqual(moreLightSize.height, try XCTUnwrap(lightOverviewHeight), accuracy: 0.5)
        let moreDarkSize = try render(
            page: .more,
            theme: .dark,
            output: projectRoot.appendingPathComponent("build/CodexTokenLedger-v2.3-more-dark.png"),
            minimumHeight: 650,
            maximumHeight: 750
        )
        XCTAssertEqual(moreDarkSize.height, try XCTUnwrap(darkOverviewHeight), accuracy: 0.5)
        let lightSessionsSize = try render(
            page: .sessions,
            theme: .light,
            output: projectRoot.appendingPathComponent("build/CodexTokenLedger-v2.3-sessions-light.png"),
            minimumHeight: 650,
            maximumHeight: 750
        )
        XCTAssertEqual(
            lightSessionsSize.height,
            try XCTUnwrap(lightOverviewHeight),
            accuracy: 0.5,
            "Primary navigation pages must keep the overview window height"
        )
        let darkSessionsSize = try render(
            page: .sessions,
            theme: .dark,
            output: projectRoot.appendingPathComponent("build/CodexTokenLedger-v2.3-sessions-dark.png"),
            minimumHeight: 650,
            maximumHeight: 750
        )
        XCTAssertEqual(
            darkSessionsSize.height,
            try XCTUnwrap(darkOverviewHeight),
            accuracy: 0.5,
            "Dark primary navigation pages must keep the overview window height"
        )
        let expandedOverviewSize = try render(
            page: .overview,
            theme: .dark,
            output: projectRoot.appendingPathComponent("build/CodexTokenLedger-v2.3-details-dark.png"),
            minimumHeight: 650,
            maximumHeight: 1_000,
            initiallyExpandedLiveDetails: true
        )
        XCTAssertEqual(
            expandedOverviewSize.height,
            try XCTUnwrap(darkOverviewHeight),
            accuracy: 0.5,
            "The detail drawer must never resize the native NSMenu window"
        )
        let expandedLightOverviewSize = try render(
            page: .overview,
            theme: .light,
            output: projectRoot.appendingPathComponent("build/CodexTokenLedger-v2.3-details-light.png"),
            minimumHeight: 650,
            maximumHeight: 1_000,
            initiallyExpandedLiveDetails: true
        )
        XCTAssertEqual(
            expandedLightOverviewSize.height,
            try XCTUnwrap(lightOverviewHeight),
            accuracy: 0.5,
            "The Light detail drawer must never resize the native NSMenu window"
        )
        let tiboLightSize = try render(
            page: .tiboSignal,
            theme: .light,
            output: projectRoot.appendingPathComponent("build/CodexTokenLedger-v2.3-tibo-signal-light.png"),
            minimumHeight: 650,
            maximumHeight: 750
        )
        XCTAssertEqual(tiboLightSize.height, try XCTUnwrap(lightOverviewHeight), accuracy: 0.5)
        let tiboDarkSize = try render(
            page: .tiboSignal,
            theme: .dark,
            output: projectRoot.appendingPathComponent("build/CodexTokenLedger-v2.3-tibo-signal-dark.png"),
            minimumHeight: 650,
            maximumHeight: 750
        )
        XCTAssertEqual(tiboDarkSize.height, try XCTUnwrap(darkOverviewHeight), accuracy: 0.5)
        let darkConsoleSize = try render(page: .settings, theme: .dark, output: projectRoot.appendingPathComponent("build/CodexTokenLedger-v2.3-console-dark.png"), minimumHeight: 650, maximumHeight: 750)
        XCTAssertEqual(darkConsoleSize.height, try XCTUnwrap(darkOverviewHeight), accuracy: 0.5)
        let lightConsoleSize = try render(page: .settings, theme: .light, output: projectRoot.appendingPathComponent("build/CodexTokenLedger-v2.3-console-light.png"), minimumHeight: 650, maximumHeight: 750)
        XCTAssertEqual(lightConsoleSize.height, try XCTUnwrap(lightOverviewHeight), accuracy: 0.5)
        let liveConsoleSize = try render(page: .settings, theme: .light, output: projectRoot.appendingPathComponent("build/CodexTokenLedger-v2.3-live-settings-light.png"), minimumHeight: 650, maximumHeight: 750, consolePanel: .live)
        XCTAssertEqual(liveConsoleSize.height, try XCTUnwrap(lightOverviewHeight), accuracy: 0.5)
        viewModel.accountActionMessage = viewModel.t("account.codexActivated", "designer@example.com")
        let darkAccountsSize = try render(page: .settings, theme: .dark, output: projectRoot.appendingPathComponent("build/CodexTokenLedger-v2.3-accounts-dark.png"), minimumHeight: 650, maximumHeight: 750, consolePanel: .account)
        XCTAssertEqual(darkAccountsSize.height, try XCTUnwrap(darkOverviewHeight), accuracy: 0.5)
        let lightAccountsSize = try render(page: .settings, theme: .light, output: projectRoot.appendingPathComponent("build/CodexTokenLedger-v2.3-accounts-light.png"), minimumHeight: 650, maximumHeight: 750, consolePanel: .account)
        XCTAssertEqual(lightAccountsSize.height, try XCTUnwrap(lightOverviewHeight), accuracy: 0.5)
        let dataConsoleSize = try render(page: .settings, theme: .light, output: projectRoot.appendingPathComponent("build/CodexTokenLedger-v2.3-data-settings-light.png"), minimumHeight: 650, maximumHeight: 750, consolePanel: .data)
        XCTAssertEqual(dataConsoleSize.height, try XCTUnwrap(lightOverviewHeight), accuracy: 0.5)
        let tokenFixture = #"{"provider":"openai","credentials":{"accessToken":"preview-access-token","accountId":"preview-account"}}"#
        let tokenDarkSize = try render(page: .tokenLogin, theme: .dark, output: projectRoot.appendingPathComponent("build/CodexTokenLedger-v2.3-token-login-dark.png"), minimumHeight: 650, maximumHeight: 750, credentialText: tokenFixture)
        XCTAssertEqual(tokenDarkSize.height, try XCTUnwrap(darkOverviewHeight), accuracy: 0.5)
        let tokenLightSize = try render(page: .tokenLogin, theme: .light, output: projectRoot.appendingPathComponent("build/CodexTokenLedger-v2.3-token-login-light.png"), minimumHeight: 650, maximumHeight: 750, credentialText: tokenFixture)
        XCTAssertEqual(tokenLightSize.height, try XCTUnwrap(lightOverviewHeight), accuracy: 0.5)
        let lightDeveloperSize = try render(page: .about, theme: .light, output: projectRoot.appendingPathComponent("build/CodexTokenLedger-v2.3-about-light.png"), minimumHeight: 650, maximumHeight: 750)
        XCTAssertEqual(lightDeveloperSize.height, try XCTUnwrap(lightOverviewHeight), accuracy: 0.5)
        let darkDeveloperSize = try render(page: .about, theme: .dark, output: projectRoot.appendingPathComponent("build/CodexTokenLedger-v2.3-about-dark.png"), minimumHeight: 650, maximumHeight: 750)
        XCTAssertEqual(darkDeveloperSize.height, try XCTUnwrap(darkOverviewHeight), accuracy: 0.5)
        let lightUpdateSize = try render(page: .updates, theme: .light, output: projectRoot.appendingPathComponent("build/CodexTokenLedger-v2.3-updates-light.png"), minimumHeight: 650, maximumHeight: 750)
        XCTAssertEqual(lightUpdateSize.height, try XCTUnwrap(lightOverviewHeight), accuracy: 0.5)
        let darkUpdateSize = try render(page: .updates, theme: .dark, output: projectRoot.appendingPathComponent("build/CodexTokenLedger-v2.3-updates-dark.png"), minimumHeight: 650, maximumHeight: 750)
        XCTAssertEqual(darkUpdateSize.height, try XCTUnwrap(darkOverviewHeight), accuracy: 0.5)
        let lightLegalSize = try render(page: .legal, theme: .light, output: projectRoot.appendingPathComponent("build/CodexTokenLedger-v2.3-legal-light.png"), minimumHeight: 650, maximumHeight: 750, legalDocument: .privacy)
        XCTAssertEqual(lightLegalSize.height, try XCTUnwrap(lightOverviewHeight), accuracy: 0.5)
        let darkLegalSize = try render(page: .legal, theme: .dark, output: projectRoot.appendingPathComponent("build/CodexTokenLedger-v2.3-legal-dark.png"), minimumHeight: 650, maximumHeight: 750, legalDocument: .openSource)
        XCTAssertEqual(darkLegalSize.height, try XCTUnwrap(darkOverviewHeight), accuracy: 0.5)

        viewModel.liveContexts = Array(viewModel.liveContexts.prefix(1))
        let singleTaskSize = try render(
            page: .overview,
            theme: .dark,
            output: projectRoot.appendingPathComponent("build/CodexTokenLedger-v2.3-single-task-dark.png"),
            minimumHeight: 650,
            maximumHeight: 750
        )
        XCTAssertEqual(singleTaskSize.height, try XCTUnwrap(darkOverviewHeight), accuracy: 0.5)

    }

    func testMenuPopoverContainsNoScrollContainer() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = projectRoot.appendingPathComponent(
            "Sources/CodexTokenLedger/Views/MenuBarDashboardView.swift"
        )
        let contents = try String(contentsOf: source, encoding: .utf8)
        XCTAssertFalse(contents.contains("ScrollView"))
        XCTAssertFalse(contents.contains("scrollIndicators"))
    }

    func testEveryPageUsesTheFixedPageHeight() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = projectRoot.appendingPathComponent(
            "Sources/CodexTokenLedger/Views/MenuBarDashboardView.swift"
        )
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("private let sessionsPerPage = 8"))
        XCTAssertTrue(source.contains("private static let overviewPageContentHeight = primaryPageHeight - footerHeight"))
        XCTAssertTrue(source.contains("? Self.overviewPageContentHeight"))
        XCTAssertTrue(source.contains(": Self.primaryPageContentHeight"))
        XCTAssertTrue(source.contains("Spacer(minLength: 0)"))
        XCTAssertTrue(
            source.contains(
                ".frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)"
            )
        )
    }

    func testAboutPageProvidesVersionUpdateLinksAndLegalDocuments() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = projectRoot.appendingPathComponent(
            "Sources/CodexTokenLedger/Views/MenuBarDashboardView.swift"
        )
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let start = try XCTUnwrap(source.range(of: "private var about: some View"))
        let end = try XCTUnwrap(
            source.range(
                of: "private var sessionPageCount",
                range: start.upperBound..<source.endIndex
            )
        )
        let about = source[start.lowerBound..<end.lowerBound]

        XCTAssertTrue(about.contains("developer.product"))
        XCTAssertTrue(about.contains("about.versionValue"))
        XCTAssertTrue(about.contains("about.buildValue"))
        XCTAssertTrue(about.contains("page = .updates"))
        XCTAssertTrue(about.contains("Self.websiteURL"))
        XCTAssertTrue(about.contains("Self.sourceURL"))
        XCTAssertTrue(about.contains("ForEach(LegalDocument.allCases)"))
        XCTAssertTrue(about.contains("private var legalViewer"))
        XCTAssertTrue(about.contains("appVersionDisplay"))
        XCTAssertFalse(source.contains("\"1.9.0 (20)\""))
    }

    func testUpdatePipelineUsesSparkleAndPublishesAnAppcast() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let project = try String(
            contentsOf: projectRoot.appendingPathComponent("project.yml"),
            encoding: .utf8
        )
        let service = try String(
            contentsOf: projectRoot.appendingPathComponent(
                "Sources/CodexTokenLedger/Services/AppUpdateService.swift"
            ),
            encoding: .utf8
        )
        let infoData = try Data(
            contentsOf: projectRoot.appendingPathComponent("Config/Info.plist")
        )
        let info = try XCTUnwrap(
            try PropertyListSerialization.propertyList(from: infoData, format: nil) as? [String: Any]
        )
        let workflow = try String(
            contentsOf: projectRoot.appendingPathComponent(".github/workflows/release.yml"),
            encoding: .utf8
        )

        XCTAssertTrue(project.contains("exactVersion: 2.9.6"))
        XCTAssertEqual(
            info["SUFeedURL"] as? String,
            "https://github.com/Lincb522/CodexLens/releases/latest/download/appcast.xml"
        )
        XCTAssertNotNil(info["SUPublicEDKey"] as? String)
        XCTAssertEqual(info["SUVerifyUpdateBeforeExtraction"] as? Bool, true)
        XCTAssertTrue(service.contains("SPUStandardUpdaterController"))
        XCTAssertTrue(service.contains("checkForUpdates"))
        XCTAssertTrue(workflow.contains("SPARKLE_PRIVATE_KEY"))
        XCTAssertTrue(workflow.contains("--ed-key-file -"))
        XCTAssertTrue(workflow.contains("--embed-release-notes"))
        XCTAssertTrue(workflow.contains("release-notes/${TAG#v}.md"))
        XCTAssertTrue(workflow.contains("--notes-file \"$NOTES\""))
        XCTAssertTrue(workflow.contains("inputs.notarize"))
        XCTAssertTrue(workflow.contains("尚未通过 Apple 公证"))
        XCTAssertTrue(workflow.contains("dist/appcast.xml"))
    }

    func testUpdatePageShowsTheCurrentVersionNotes() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: projectRoot.appendingPathComponent(
                "Sources/CodexTokenLedger/Views/MenuBarDashboardView.swift"
            ),
            encoding: .utf8
        )
        let start = try XCTUnwrap(source.range(of: "private var updates: some View"))
        let end = try XCTUnwrap(
            source.range(
                of: "private var legalViewer",
                range: start.upperBound..<source.endIndex
            )
        )
        let updates = source[start.lowerBound..<end.lowerBound]

        XCTAssertTrue(updates.contains("update.releaseNotes"))
        XCTAssertTrue(updates.contains("currentReleaseNoteKeys"))
        XCTAssertTrue(updates.contains("versionBadge(appVersionDisplay)"))
    }

    func testLocalizedVersionNotesFitTheUpdateCard() {
        let font = NSFont.systemFont(ofSize: 12, weight: .medium)
        let keys = [
            "update.releaseNote.glass",
            "update.releaseNote.layout",
            "update.releaseNote.quotaSummary",
        ]

        for language in AppLanguage.allCases where language != .system {
            for key in keys {
                let value = LocalizationCatalog.text(key, language: language)
                let width = (value as NSString).size(withAttributes: [.font: font]).width
                XCTAssertLessThanOrEqual(width, 280, "\(language) \(key): \(value)")
            }
        }
    }

    func testWholePopoverUsesCodexBarStyleNativeMenuGlass() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let dashboardSource = projectRoot.appendingPathComponent(
            "Sources/CodexTokenLedger/Views/MenuBarDashboardView.swift"
        )
        let controllerSource = projectRoot.appendingPathComponent(
            "Sources/CodexTokenLedger/NativeMenuBarController.swift"
        )
        let appSource = projectRoot.appendingPathComponent(
            "Sources/CodexTokenLedger/CodexTokenLedgerApp.swift"
        )
        let dashboard = try String(contentsOf: dashboardSource, encoding: .utf8)
        let controller = try String(contentsOf: controllerSource, encoding: .utf8)
        let app = try String(contentsOf: appSource, encoding: .utf8)

        XCTAssertTrue(controller.contains("NSStatusBar.system"))
        XCTAssertTrue(controller.contains("private let menu = NativeDashboardMenu()"))
        XCTAssertTrue(controller.contains("dashboardItem.view = hostingView"))
        XCTAssertTrue(controller.contains("override var allowsVibrancy: Bool { true }"))
        XCTAssertTrue(controller.contains("override var isOpaque: Bool { false }"))
        XCTAssertTrue(controller.contains("hostingView.layer?.backgroundColor = NSColor.clear.cgColor"))
        XCTAssertTrue(controller.contains("AppKit owns the complete menu window and its"))
        XCTAssertTrue(controller.contains("system backdrop blur; SwiftUI only supplies transparent menu content"))
        XCTAssertFalse(controller.contains("menuTopBridge"))
        XCTAssertFalse(controller.contains("MenuTopBridgeView"))
        XCTAssertFalse(controller.contains("NativeMenuTopBridgeGeometry"))
        XCTAssertFalse(controller.contains("MenuHeroTopPalette"))
        XCTAssertFalse(app.contains("MenuBarExtra"))
        XCTAssertFalse(app.contains("menuBarExtraStyle"))
        XCTAssertFalse(dashboard.contains("FrostedPopoverBackground"))
        XCTAssertFalse(dashboard.contains("NSVisualEffectView"))
        XCTAssertFalse(dashboard.contains("atmosphericBackground"))
        XCTAssertTrue(dashboard.contains(".background(Color.clear)"))
        XCTAssertFalse(dashboard.contains("Color.white"))
        XCTAssertFalse(dashboard.contains("Color.black"))
        XCTAssertTrue(dashboard.contains("static let selectionInk = adaptive"))
        XCTAssertFalse(dashboard.contains("heroSelectionInk"))
        XCTAssertTrue(dashboard.contains("Light mode uses a cool blue graphite rather than neutral black"))
        XCTAssertTrue(dashboard.contains("heroAccountLabel(account)"))
        XCTAssertTrue(dashboard.contains("heroAccountLabelWidth(account)"))
        XCTAssertTrue(dashboard.contains("Keep the visible label outside the native Menu"))
        XCTAssertTrue(dashboard.contains(".foregroundColor(.white.opacity(0.82))"))
        XCTAssertFalse(dashboard.contains("Color(\"Pulse"))
    }

    func testNativeMenuDoesNotPaintASeparateTopBand() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let controllerSource = projectRoot.appendingPathComponent(
            "Sources/CodexTokenLedger/NativeMenuBarController.swift"
        )
        let controller = try String(contentsOf: controllerSource, encoding: .utf8)

        XCTAssertTrue(controller.contains("hostingView.layer?.backgroundColor = NSColor.clear.cgColor"))
        XCTAssertTrue(controller.contains("NSMenu owns the glass window"))
        XCTAssertFalse(controller.contains("CAGradientLayer"))
        XCTAssertFalse(controller.contains("addSubview(menuTopBridge"))
    }

    func testMenuPopoverUsesReadableTypeRamp() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = projectRoot.appendingPathComponent(
            "Sources/CodexTokenLedger/Views/MenuBarDashboardView.swift"
        )
        let contents = try String(contentsOf: source, encoding: .utf8)
        let expression = try NSRegularExpression(
            pattern: #"\.system\(size:\s*([0-9]+(?:\.[0-9]+)?)"#
        )
        let matches = expression.matches(
            in: contents,
            range: NSRange(contents.startIndex..<contents.endIndex, in: contents)
        )
        let sizes = matches.compactMap { match -> Double? in
            guard let range = Range(match.range(at: 1), in: contents) else { return nil }
            return Double(contents[range])
        }

        XCTAssertFalse(sizes.isEmpty)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(sizes.min()), 12)
        XCTAssertTrue(contents.contains("static let contentWidth: CGFloat = 340"))
        XCTAssertTrue(contents.contains("static let primaryPageHeight: CGFloat = 740"))
        XCTAssertTrue(contents.contains(".padding(.horizontal, 16)"))
        XCTAssertTrue(contents.contains(".background(Color.clear)"))
        XCTAssertTrue(contents.contains("PulsePalette.focusSurface"))
        XCTAssertTrue(contents.contains("idleColor: PulsePalette.ink"))
        XCTAssertTrue(contents.contains("spinningColor: PulsePalette.warning"))
        XCTAssertTrue(contents.contains("static let heroLowerInk = adaptive(light: 0.99, dark: 0.98)"))
        XCTAssertTrue(contents.contains("HeroMetricTile("))
        XCTAssertTrue(contents.contains("direction: .input"))
        XCTAssertTrue(contents.contains("direction: .cached"))
        XCTAssertTrue(contents.contains("direction: .output"))
        XCTAssertTrue(contents.contains("private enum HeroTokenDirection"))
        XCTAssertTrue(contents.contains("PulseIcon(name: direction.iconName)"))
        XCTAssertTrue(contents.contains("DisplayFormat.tokens(context.contextInputTokens)"))
        XCTAssertTrue(contents.contains("viewModel.t(\"live.currentContext\")"))
        XCTAssertTrue(contents.contains("viewModel.t(\"live.taskUsageTotal\")"))
        XCTAssertTrue(contents.contains("Text(viewModel.t(\"live.tokenDetail\"))"))
        XCTAssertTrue(contents.contains("viewModel.t(\"live.currentContextInput\")"))
        XCTAssertTrue(contents.contains("viewModel.t(\"live.currentTurn\")"))
        XCTAssertTrue(contents.contains("viewModel.t(\"live.inputIncludesCache\")"))
        XCTAssertTrue(contents.contains("TokenScopeDetailSection("))
        XCTAssertTrue(contents.contains("DetailTokenMetric("))
        XCTAssertTrue(contents.contains("private func exactTokenValue"))
        XCTAssertTrue(contents.contains("DisplayFormat.integer(value)"))
        XCTAssertTrue(contents.contains("viewModel.t(\"live.tokenValue\""))
        XCTAssertTrue(contents.contains("viewModel.t(\"live.perMillionTokens\")"))
        XCTAssertTrue(contents.contains("account.accountQuotaWindows.prefix(2)"))
        XCTAssertTrue(contents.contains("window.remainingPercent"))
        XCTAssertTrue(contents.contains("quotaAllowanceEstimateCard"))
        XCTAssertTrue(contents.contains("selectedSubscriptionQuotaEstimate"))
        XCTAssertTrue(contents.contains("estimate.remainingAPIEquivalentUSD"))
        XCTAssertTrue(contents.contains("SubscriptionQuotaEstimate.sourceURL"))
        XCTAssertFalse(contents.contains("selectedQuotaValueEstimate"))
        XCTAssertFalse(contents.contains("quotaBudgetDetailCard"))
        XCTAssertFalse(contents.contains("DUP"))
        XCTAssertFalse(contents.contains("LONG ×2/×1.5"))
        XCTAssertTrue(contents.contains("accountUsageOverview(account)"))
        XCTAssertTrue(contents.contains("TokenUsageHeatmapGrid("))
        XCTAssertTrue(contents.contains("quotaOverviewRow(account)"))
        XCTAssertTrue(contents.contains("private var liveTaskSwitcher"))
        XCTAssertTrue(contents.contains("private var selectedLiveTaskIndex"))
        XCTAssertTrue(contents.contains("private func selectAdjacentLiveTask"))
        XCTAssertTrue(contents.contains("MarqueeLabel("))
        XCTAssertTrue(contents.contains(".lineLimit(1)"))
        XCTAssertTrue(contents.contains(".allowsTightening(false)"))
        XCTAssertFalse(contents.contains(".lineLimit(2)"))
        XCTAssertFalse(contents.contains(".minimumScaleFactor"))
        XCTAssertFalse(contents.contains(".fixedSize(horizontal: false"))
        XCTAssertFalse(contents.contains("design: .rounded"))
        XCTAssertFalse(contents.contains(".shadow("))
        XCTAssertFalse(contents.contains("flashOpacity"))
    }

    func testTiboGlobalAnnouncementIsIndependentFromAccountQuota() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = projectRoot.appendingPathComponent(
            "Sources/CodexTokenLedger/Views/MenuBarDashboardView.swift"
        )
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let forecastStart = try XCTUnwrap(source.range(of: "private var quotaDetails"))
        let signalStart = try XCTUnwrap(
            source.range(of: "private var tiboGlobalSignalRow", range: forecastStart.upperBound..<source.endIndex)
        )
        let forecastBody = source[forecastStart.lowerBound..<signalStart.lowerBound]

        XCTAssertFalse(forecastBody.localizedCaseInsensitiveContains("tibo"))
        XCTAssertTrue(source.contains("Button { page = .tiboSignal }"))
        XCTAssertTrue(source.contains("private var tiboSignalDetail"))
        XCTAssertTrue(source.contains("tibo.forecast.horizon24h"))
        XCTAssertTrue(source.contains("tibo.forecast.resetProbability"))
        XCTAssertTrue(source.contains("tiboForecastProbabilityText"))
        XCTAssertTrue(source.contains("tiboForecastReferenceText"))
        XCTAssertTrue(source.contains("tiboForecastCountdownText"))
        XCTAssertTrue(source.contains("tiboForecastJudgementTitle"))
        XCTAssertTrue(source.contains("tiboForecastProbabilityBandText"))
        XCTAssertTrue(source.contains("tiboForecastPublicSignalText"))
        XCTAssertTrue(source.contains("tiboForecastLastResetAgeText"))
        XCTAssertTrue(source.contains("tiboSocialEvidenceText"))
        XCTAssertTrue(source.contains("tiboSocialEvidenceAssessmentText"))
        XCTAssertTrue(source.contains("openLatestTiboSocialEvidence"))
        XCTAssertTrue(source.contains("forecastEvidenceRow("))

        let detailStart = try XCTUnwrap(source.range(of: "private var tiboSignalDetail"))
        let detailEnd = try XCTUnwrap(
            source.range(of: "private func ledgerSurface", range: detailStart.upperBound..<source.endIndex)
        )
        let detailBody = source[detailStart.lowerBound..<detailEnd.lowerBound]
        XCTAssertFalse(detailBody.contains("tibo.detail.technical"))
        XCTAssertFalse(detailBody.contains("tibo.detail.rule"))
        XCTAssertFalse(detailBody.contains("tibo.detail.matchedRule"))
        XCTAssertFalse(detailBody.contains("tibo.detail.postID"))
        XCTAssertFalse(detailBody.contains("tibo.detail.source"))
        XCTAssertFalse(detailBody.contains("tibo.feed.title"))
        XCTAssertFalse(detailBody.contains("tiboSignalSnapshot.signals.enumerated()"))

        let overviewStart = try XCTUnwrap(source.range(of: "private var overview"))
        let overviewEnd = try XCTUnwrap(
            source.range(of: "private var liveTaskSwitcher", range: overviewStart.upperBound..<source.endIndex)
        )
        let overviewBody = source[overviewStart.lowerBound..<overviewEnd.lowerBound]
        XCTAssertNotNil(overviewBody.range(of: "liveContextCard"))
        XCTAssertNotNil(overviewBody.range(of: "accountUsageOverview(account)"))
        XCTAssertNotNil(overviewBody.range(of: "tiboGlobalSignalRow"))
        XCTAssertTrue(source.contains("Button { page = .tiboSignal } label:"))
    }

    func testOverflowAndMoreUseInMenuPages() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = projectRoot.appendingPathComponent(
            "Sources/CodexTokenLedger/Views/MenuBarDashboardView.swift"
        )
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        let switcherStart = try XCTUnwrap(source.range(of: "private var liveTaskSwitcher"))
        let switcherEnd = try XCTUnwrap(
            source.range(of: "private var liveContextCard", range: switcherStart.upperBound..<source.endIndex)
        )
        let switcher = source[switcherStart.lowerBound..<switcherEnd.lowerBound]
        XCTAssertTrue(switcher.contains("page = .activeTasks"))
        XCTAssertFalse(switcher.contains("Menu {"))

        let footerStart = try XCTUnwrap(source.range(of: "private var footer"))
        let footerEnd = try XCTUnwrap(
            source.range(of: "private func footerTab", range: footerStart.upperBound..<source.endIndex)
        )
        let footer = source[footerStart.lowerBound..<footerEnd.lowerBound]
        XCTAssertTrue(footer.contains("footerTab(\n                .more"))
        XCTAssertFalse(footer.contains("Menu {"))
    }

    func testConsolePageRemeasuresNativeMenuAndCoversItsRoot() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let dashboardURL = projectRoot.appendingPathComponent(
            "Sources/CodexTokenLedger/Views/MenuBarDashboardView.swift"
        )
        let controllerURL = projectRoot.appendingPathComponent(
            "Sources/CodexTokenLedger/NativeMenuBarController.swift"
        )
        let dashboard = try String(contentsOf: dashboardURL, encoding: .utf8)
        let controller = try String(contentsOf: controllerURL, encoding: .utf8)

        XCTAssertTrue(dashboard.contains(".background(Color.clear)"))
        XCTAssertTrue(dashboard.contains(".onChange(of: page)"))
        XCTAssertFalse(dashboard.contains(".onChange(of: consolePanel)"))
        XCTAssertTrue(dashboard.contains("static let primaryPageHeight: CGFloat = 740"))
        XCTAssertTrue(dashboard.contains(".frame(height: Self.primaryPageContentHeight, alignment: .top)"))
        XCTAssertTrue(dashboard.contains("@State private var isDetailsExpanded: Bool"))
        XCTAssertTrue(dashboard.contains("Button(action: toggleDetails)"))
        XCTAssertTrue(dashboard.contains(".overlay(alignment: .top)"))
        XCTAssertTrue(dashboard.contains("PulsePalette.detailGlassTint"))
        XCTAssertTrue(dashboard.contains(".background(.thinMaterial"))
        XCTAssertTrue(dashboard.contains(".compositingGroup()"))
        XCTAssertTrue(dashboard.contains("if isDetailsExpanded"))
        XCTAssertTrue(dashboard.contains("value: isDetailsExpanded"))
        XCTAssertFalse(dashboard.contains("@State private var isDetailsMounted"))
        XCTAssertFalse(dashboard.contains("@State private var chevronExpanded"))
        XCTAssertFalse(dashboard.contains("layoutTransaction.disablesAnimations = true"))
        XCTAssertFalse(dashboard.contains("withTransaction(layoutTransaction)"))
        XCTAssertFalse(dashboard.contains(".onChange(of: overviewPanel)"))
        XCTAssertFalse(dashboard.contains(".id(overviewPanel)"))
        XCTAssertTrue(dashboard.contains("private var usageHistory: some View"))
        XCTAssertTrue(dashboard.contains("TokenUsageHeatmapGrid("))
        XCTAssertTrue(dashboard.contains(".easeOut(duration: 0.12)"))
        let toggleStart = try XCTUnwrap(dashboard.range(of: "private func toggleDetails()"))
        let toggleEnd = try XCTUnwrap(
            dashboard.range(of: "private var heroCapacityText", range: toggleStart.upperBound..<dashboard.endIndex)
        )
        let toggleBody = dashboard[toggleStart.lowerBound..<toggleEnd.lowerBound]
        XCTAssertTrue(toggleBody.contains("withAnimation"))
        XCTAssertFalse(toggleBody.contains("menuLayoutChanged"))
        XCTAssertFalse(toggleBody.contains("DispatchQueue"))
        XCTAssertTrue(controller.contains("viewModel.$menuLayoutRevision"))
        XCTAssertTrue(controller.contains("resizeDashboardIfNeeded(force: true)"))
        XCTAssertTrue(controller.contains("hostingView.sizingOptions = [.intrinsicContentSize]"))
        XCTAssertTrue(controller.contains("settledLayoutWorkItem?.cancel()"))
        XCTAssertTrue(controller.contains("deadline: .now() + 0.62"))
        XCTAssertTrue(controller.contains("let intrinsicHeight = hostingView.intrinsicContentSize.height"))
        XCTAssertTrue(controller.contains("self.resizeDashboardIfNeeded()"))
        XCTAssertTrue(controller.contains("button.font = .monospacedSystemFont(ofSize: 12.5, weight: .medium)"))
        XCTAssertTrue(controller.contains("case .contextUsed: specification = (\"arrow-right\", -90)"))
        XCTAssertTrue(controller.contains("button.title = text"))
        XCTAssertFalse(controller.contains("button.title = text.isEmpty ? \"\" : \"  "))
        XCTAssertFalse(dashboard.contains("completionCriteria: .removed"))
    }

    @MainActor
    func testNativeMenuThemeSwitchUpdatesApplicationAppearanceImmediately() throws {
        let suite = "CodexTokenLedger.NativeTheme.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            UserDefaults.standard.removePersistentDomain(forName: suite)
            NSApp.appearance = nil
        }

        let viewModel = DashboardViewModel(defaults: defaults)
        viewModel.appTheme = .dark
        let controller = NativeMenuBarController(
            viewModel: viewModel,
            updateService: AppUpdateService()
        )
        defer { controller.stop() }

        XCTAssertEqual(
            NSApp.appearance?.bestMatch(from: [.darkAqua, .aqua]),
            .darkAqua
        )

        viewModel.appTheme = .light
        XCTAssertEqual(
            NSApp.appearance?.bestMatch(from: [.darkAqua, .aqua]),
            .aqua
        )

        viewModel.appTheme = .system
        XCTAssertNil(NSApp.appearance)
    }
}
