import AppKit
import SwiftUI
import XCTest
@testable import CodexTokenLedger

final class MenuBarVisualSmokeTests: XCTestCase {
    @MainActor
    func testRasterIconFamilyLoadsAndRendersWithTemplateTint() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Design/IconSystem/icon-system.json"))
        let spec = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let names = try XCTUnwrap(spec["icons"] as? [String])
        XCTAssertEqual(names.count, 31)
        XCTAssertEqual(Set(names).count, names.count)
        for name in names {
            let asset = try XCTUnwrap(NSImage(named: "PulseIcon-\(name)"), name)
            XCTAssertTrue(asset.isTemplate, name)
            for size in [CGFloat(16), 24, 48] {
                for dark in [false, true] {
                    let view = PulseIcon(name: name)
                        .frame(width: size, height: size)
                        .foregroundStyle(dark ? Color.white : .black)
                        .padding(4)
                        .background(dark ? Color.black : .white)
                    let host = NSHostingView(rootView: view)
                    host.frame = NSRect(x: 0, y: 0, width: size + 8, height: size + 8)
                    host.layoutSubtreeIfNeeded()
                    let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    var coverage = 0.0
                    for y in 0..<bitmap.pixelsHigh {
                        for x in 0..<bitmap.pixelsWide {
                            let color = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                            let ink = dark ? color.redComponent : 1 - color.redComponent
                            coverage += ink
                            if x < 4 || y < 4 || x >= bitmap.pixelsWide - 4 || y >= bitmap.pixelsHigh - 4 {
                                XCTAssertLessThan(ink, 0.02, "\(name): transparent outer margin")
                            }
                        }
                    }
                    XCTAssertGreaterThan(coverage, Double(size * size) * 0.05, "\(name): template is visible at \(size) pt")
                    XCTAssertLessThan(coverage, Double(bitmap.pixelsWide * bitmap.pixelsHigh) * 0.65, "\(name): no opaque image tile")
                }
            }
        }
    }

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

    func testSettingsSegmentsFitAllSupportedLanguages() {
        for language in AppLanguage.allCases where language != .system {
            let width = ["appearance", "live", "account", "data"].reduce(CGFloat(0)) { width, key in
                let title = LocalizationCatalog.text("settings.tab." + key, language: language)
                return width + (title as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 13)]).width + 20
            }
            XCTAssertLessThanOrEqual(width, 308, "\(language): setting segments overflow")
        }
    }

    @MainActor
    func testMarqueePreservesNativeGlyphsAcrossTitleSizesAndScripts() throws {
        func ink(in content: some View, width: CGFloat) throws -> (coverage: Double, height: Int) {
            let host = NSHostingView(rootView: content
                .frame(width: width, height: 40, alignment: .leading)
                .clipped()
                .background(Color.black))
            host.frame = NSRect(x: 0, y: 0, width: width, height: 40)
            host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            var coverage = 0.0
            var rows: [Int] = []
            for y in 0..<bitmap.pixelsHigh {
                var rowCoverage = 0.0
                for x in 0..<bitmap.pixelsWide {
                    rowCoverage += try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB)).redComponent
                }
                coverage += rowCoverage
                if rowCoverage > 0.1 { rows.append(y) }
            }
            return (coverage, (try XCTUnwrap(rows.last)) - (try XCTUnwrap(rows.first)) + 1)
        }
        for title in ["Token 使用记录", "账户额度", "Réglages gyqp", "利用履歴", "사용 기록", "123,456,789 Token"] {
            for size in [CGFloat(12), 16, 19, 26] {
                for width in [CGFloat(120), 300] {
                    let font = Font.system(size: size, weight: .semibold)
                    let actual = try ink(in: MarqueeLabel(text: title, font: font, color: .white), width: width)
                    let expected = try ink(in: Text(title).font(font).foregroundStyle(.white).fixedSize(), width: width)
                    XCTAssertEqual(actual.coverage, expected.coverage, accuracy: expected.coverage * 0.02,
                                   "\(title), \(size) pt at \(width) pt must retain the native glyphs")
                    XCTAssertGreaterThanOrEqual(actual.height, expected.height - 1, "Do not clip accents or descenders")
                }
            }
        }
    }

    @MainActor
    func testHeatmapCellsKeepTheBackdropVisibleAtEveryIntensity() throws {
        func sample(_ intensity: Int, background: CGFloat, scheme: ColorScheme, position: CGPoint = CGPoint(x: 24, y: 24)) throws -> NSColor {
            let day = TokenUsageHeatmapDay(date: Date(), dateKey: "2026-09-06", tokens: 100,
                                           intensity: intensity, isFuture: false)
            let content = TokenUsageHeatmapCell(day: day, size: 32, selected: false, action: nil, accessibilityLabel: "Preview")
                .padding(8)
                .background(Color(nsColor: NSColor(calibratedWhite: background, alpha: 1)))
                .environment(\.colorScheme, scheme)
            let host = NSHostingView(rootView: content)
            host.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            host.frame = NSRect(x: 0, y: 0, width: 48, height: 48)
            host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let x = Int(CGFloat(bitmap.pixelsWide) * position.x / 48)
            let y = Int(CGFloat(bitmap.pixelsHigh) * position.y / 48)
            return try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
        }
        for scheme in [ColorScheme.light, .dark] {
            var previousBrightness: CGFloat?
            for intensity in 0...4 {
                let darkBackdrop = try sample(intensity, background: 0.2, scheme: scheme)
                let lightBackdrop = try sample(intensity, background: 0.8, scheme: scheme)
                let transmittedChange = abs(lightBackdrop.redComponent - darkBackdrop.redComponent)
                    + abs(lightBackdrop.greenComponent - darkBackdrop.greenComponent)
                    + abs(lightBackdrop.blueComponent - darkBackdrop.blueComponent)
                XCTAssertGreaterThan(transmittedChange / 3, 0.15, "\(scheme) level \(intensity) became opaque")
                let brightness = (darkBackdrop.redComponent + darkBackdrop.greenComponent + darkBackdrop.blueComponent) / 3
                if let previousBrightness {
                    XCTAssertGreaterThan(brightness, previousBrightness + 0.01, "\(scheme) usage levels must remain distinguishable")
                }
                previousBrightness = brightness
            }
            let center = try sample(4, background: 0.2, scheme: scheme)
            if scheme == .dark {
                XCTAssertGreaterThan(center.redComponent, 0.50, "Peak usage should have a pale blue face, not a dark saturated fill")
                XCTAssertGreaterThan(center.blueComponent, 0.80)
            }
            let face = try sample(4, background: 0.2, scheme: scheme, position: CGPoint(x: 16, y: 32))
            XCTAssertEqual(center.redComponent, face.redComponent, accuracy: 0.01, "The face must be planar, without a radial hotspot")
            XCTAssertEqual(center.blueComponent, face.blueComponent, accuracy: 0.01)
            let emptyEdge = try sample(0, background: 0.2, scheme: scheme, position: CGPoint(x: 40.5, y: 24))
            let usedEdge = try sample(4, background: 0.2, scheme: scheme, position: CGPoint(x: 40.5, y: 24))
            XCTAssertEqual(usedEdge.blueComponent, emptyEdge.blueComponent, accuracy: 0.005, "The tile must not cast a glow into the gap")
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
        // More than one ledger page verifies that the list and pager
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
            model: "gpt-6-astra",
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
                    model: "gpt-6-astra",
                    usage: TokenUsage(inputTokens: 810_000, cachedInputTokens: 760_000, outputTokens: 4_000),
                    cumulativeTaskUsage: TokenUsage(inputTokens: 52_848_000, outputTokens: 557_192)
                ),
                CodexModelCallUsage(
                    id: "preview-call-2",
                    timestamp: now,
                    model: "gpt-6-astra",
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
        var moreFooterPixels: [String: [CGFloat]] = [:]
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
            initiallyExpandedLiveDetails: Bool = false,
            detailScope: TokenDetailScope = .context,
            tiboEvidence: Bool = false,
            canvasWidth: CGFloat = 340,
            showOldestMonth: Bool = false,
            usageRange: OverviewUsageRange = .monthToDate,
            editingUsageRange: Bool = false
        ) throws -> CGSize {
            return try autoreleasepool {
                viewModel.appTheme = theme
                let view = MenuBarDashboardView(
                    updateService: updateService,
                    initialPage: page,
                    initialConsolePanel: consolePanel,
                    initialCredentialText: credentialText,
                    initialLegalDocument: legalDocument,
                    initiallyExpandedLiveDetails: initiallyExpandedLiveDetails,
                    initialDetailScope: detailScope,
                    initiallyShowingTiboEvidence: tiboEvidence,
                    initialOverviewUsageRange: usageRange,
                    initiallyEditingUsageRange: editingUsageRange
                )
                .environmentObject(viewModel)
                // Static test images cannot capture the desktop behind a real
                // glass panel. Supply only a neutral inspection backdrop that
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
                host.frame = NSRect(x: 0, y: 0, width: canvasWidth, height: 1_200)
                host.layoutSubtreeIfNeeded()
                let fittedSize = host.fittingSize
                XCTAssertEqual(fittedSize.width, 340, accuracy: 0.5)
                XCTAssertEqual(fittedSize.height, 680, accuracy: 0.5)
                XCTAssertGreaterThan(fittedSize.height, minimumHeight)
                XCTAssertLessThan(fittedSize.height, maximumHeight)
                host.frame = NSRect(origin: .zero, size: fittedSize)
                host.appearance = NSAppearance(named: theme == .dark ? .darkAqua : .aqua)
                let window = NSWindow(contentRect: host.bounds, styleMask: .borderless, backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.contentView = host
                window.appearance = host.appearance
                defer { window.contentView = nil; window.close() }
                host.layoutSubtreeIfNeeded()
                // Native controls commit their layer state on the next run-loop pass.
                RunLoop.main.run(until: Date().addingTimeInterval(0.05))
                host.layoutSubtreeIfNeeded()
                if page == .usageHistory, viewModel.selectedAccount != nil {
                    @MainActor
                    func scrollViews(in view: NSView) -> [NSScrollView] {
                        if let scroll = view as? NSScrollView { return [scroll] }
                        return view.subviews.flatMap { scrollViews(in: $0) }
                    }
                    let scrolls = scrollViews(in: host)
                    XCTAssertEqual(scrolls.count, 1, "Only the monthly list should scroll")
                    let scroll = try XCTUnwrap(scrolls.first)
                    let document = try XCTUnwrap(scroll.documentView)
                    let frame = host.convert(scroll.bounds, from: scroll)
                    let top = host.isFlipped ? frame.minY : host.bounds.height - frame.maxY
                    XCTAssertGreaterThan(top, 300, "The heatmap and summaries must stay above the scroll area")
                    XCTAssertGreaterThan(frame.height, 100)
                    XCTAssertLessThanOrEqual(top + frame.height, 610.5, "Keep 12 pt clear above the footer at y = 622")
                    XCTAssertGreaterThanOrEqual(frame.minX, 16)
                    XCTAssertLessThanOrEqual(frame.maxX, 324)
                    XCTAssertEqual(document.bounds.height, 9 * 23 + 8 * 4, accuracy: 0.5, "All month rows must remain available")
                    XCTAssertGreaterThan(document.bounds.height, scroll.contentView.bounds.height)
                    let initialOrigin = scroll.contentView.bounds.origin
                    let oldestOrigin = NSPoint(
                        x: initialOrigin.x,
                        y: document.isFlipped ? document.bounds.maxY - scroll.contentView.bounds.height : document.bounds.minY
                    )
                    scroll.contentView.scroll(to: oldestOrigin)
                    scroll.reflectScrolledClipView(scroll.contentView)
                    host.layoutSubtreeIfNeeded()
                    XCTAssertEqual(scroll.contentView.bounds.origin.y, oldestOrigin.y, accuracy: 0.5)
                    XCTAssertEqual(host.convert(scroll.bounds, from: scroll), frame, "Scrolling must not move the viewport or footer")
                    let footerPoint = NSPoint(x: 170, y: host.isFlipped ? 651 : host.bounds.height - 651)
                    let footerHit = try XCTUnwrap(host.hitTest(footerPoint))
                    XCTAssertFalse(footerHit === scroll || footerHit.isDescendant(of: scroll), "The month list must not intercept footer clicks")
                    if !showOldestMonth {
                        scroll.contentView.scroll(to: initialOrigin)
                        scroll.reflectScrolledClipView(scroll.contentView)
                    }
                }
                host.displayIfNeeded()
                CATransaction.flush()
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                bitmap.size = host.bounds.size
                host.cacheDisplay(in: host.bounds, to: bitmap)
                if [.more, .about, .updates].contains(page) {
                    var footerPixels: [CGFloat] = []
                    let startY = Int(CGFloat(bitmap.pixelsHigh) * 622 / 680)
                    for y in startY..<bitmap.pixelsHigh {
                        for x in 0..<bitmap.pixelsWide {
                            let color = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                            footerPixels += [color.redComponent, color.greenComponent, color.blueComponent]
                        }
                    }
                    let key = theme.rawValue + viewModel.appLanguage.rawValue
                    if page == .more { moreFooterPixels[key] = footerPixels }
                    if let reference = moreFooterPixels[key] {
                        XCTAssertEqual(reference.count, footerPixels.count)
                        let difference = zip(reference, footerPixels).reduce(CGFloat(0)) { $0 + abs($1.0 - $1.1) }
                        XCTAssertLessThan(difference / CGFloat(reference.count), 0.0005,
                                          "\(page): page content must not paint over the fixed footer")
                    }
                }
                let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                try FileManager.default.createDirectory(
                    at: output.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try png.write(to: output, options: .atomic)
                XCTAssertGreaterThan(png.count, 8_000)
                return fittedSize
            }
        }

        let renders: [(AppTheme, URL)] = [
            (.dark, requestedDarkOutput ?? projectRoot.appendingPathComponent("build/ui-redesign/preview-dark.png")),
            (.light, projectRoot.appendingPathComponent("build/ui-redesign/preview-light.png")),
        ]
        var darkOverviewHeight: CGFloat?
        var lightOverviewHeight: CGFloat?
        for (theme, output) in renders {
            let size = try render(page: .overview, theme: theme, output: output, minimumHeight: 560, maximumHeight: 850)
            if theme == .dark { darkOverviewHeight = size.height }
            if theme == .light { lightOverviewHeight = size.height }
            try render(page: .overview, theme: theme,
                       output: projectRoot.appendingPathComponent("build/daily-heatmap/home-editor-\(theme.rawValue).png"),
                       minimumHeight: 560, maximumHeight: 850, editingUsageRange: true)
            try render(page: .overview, theme: theme,
                       output: projectRoot.appendingPathComponent("build/daily-heatmap/home-thirty-\(theme.rawValue).png"),
                       minimumHeight: 560, maximumHeight: 850, usageRange: .last30Days)
        }
        let activeTasksLightSize = try render(
            page: .activeTasks,
            theme: .light,
            output: projectRoot.appendingPathComponent("build/ui-redesign/active-tasks-light.png"),
            minimumHeight: 650,
            maximumHeight: 750
        )
        XCTAssertEqual(activeTasksLightSize.height, try XCTUnwrap(lightOverviewHeight), accuracy: 0.5)
        let activeTasksDarkSize = try render(
            page: .activeTasks,
            theme: .dark,
            output: projectRoot.appendingPathComponent("build/ui-redesign/active-tasks-dark.png"),
            minimumHeight: 650,
            maximumHeight: 750
        )
        XCTAssertEqual(activeTasksDarkSize.height, try XCTUnwrap(darkOverviewHeight), accuracy: 0.5)
        let quotaDetailsLightSize = try render(
            page: .quotaDetails,
            theme: .light,
            output: projectRoot.appendingPathComponent("build/ui-redesign/quota-details-light.png"),
            minimumHeight: 650,
            maximumHeight: 750
        )
        XCTAssertEqual(quotaDetailsLightSize.height, try XCTUnwrap(lightOverviewHeight), accuracy: 0.5)
        let quotaDetailsDarkSize = try render(
            page: .quotaDetails,
            theme: .dark,
            output: projectRoot.appendingPathComponent("build/ui-redesign/quota-details-dark.png"),
            minimumHeight: 650,
            maximumHeight: 750
        )
        XCTAssertEqual(quotaDetailsDarkSize.height, try XCTUnwrap(darkOverviewHeight), accuracy: 0.5)
        let usageHistoryLightSize = try render(
            page: .usageHistory,
            theme: .light,
            output: projectRoot.appendingPathComponent("build/ui-redesign/usage-history-light.png"),
            minimumHeight: 650,
            maximumHeight: 750
        )
        XCTAssertEqual(usageHistoryLightSize.height, try XCTUnwrap(lightOverviewHeight), accuracy: 0.5)
        let usageHistoryDarkSize = try render(
            page: .usageHistory,
            theme: .dark,
            output: projectRoot.appendingPathComponent("build/ui-redesign/usage-history-dark.png"),
            minimumHeight: 650,
            maximumHeight: 750
        )
        XCTAssertEqual(usageHistoryDarkSize.height, try XCTUnwrap(darkOverviewHeight), accuracy: 0.5)
        for theme in [AppTheme.light, .dark] {
            try render(page: .usageHistory, theme: theme,
                       output: projectRoot.appendingPathComponent("build/ui-redesign/usage-history-oldest-\(theme.rawValue).png"),
                       minimumHeight: 650, showOldestMonth: true)
        }
        let moreLightSize = try render(
            page: .more,
            theme: .light,
            output: projectRoot.appendingPathComponent("build/ui-redesign/more-light.png"),
            minimumHeight: 650,
            maximumHeight: 750
        )
        XCTAssertEqual(moreLightSize.height, try XCTUnwrap(lightOverviewHeight), accuracy: 0.5)
        let moreDarkSize = try render(
            page: .more,
            theme: .dark,
            output: projectRoot.appendingPathComponent("build/ui-redesign/more-dark.png"),
            minimumHeight: 650,
            maximumHeight: 750
        )
        XCTAssertEqual(moreDarkSize.height, try XCTUnwrap(darkOverviewHeight), accuracy: 0.5)
        let lightSessionsSize = try render(
            page: .sessions,
            theme: .light,
            output: projectRoot.appendingPathComponent("build/ui-redesign/sessions-light.png"),
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
            output: projectRoot.appendingPathComponent("build/ui-redesign/sessions-dark.png"),
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
            output: projectRoot.appendingPathComponent("build/ui-redesign/details-dark.png"),
            minimumHeight: 650,
            maximumHeight: 1_000,
            initiallyExpandedLiveDetails: true
        )
        XCTAssertEqual(
            expandedOverviewSize.height,
            try XCTUnwrap(darkOverviewHeight),
            accuracy: 0.5,
            "The detail page must keep the fixed window geometry"
        )
        let expandedLightOverviewSize = try render(
            page: .overview,
            theme: .light,
            output: projectRoot.appendingPathComponent("build/ui-redesign/details-light.png"),
            minimumHeight: 650,
            maximumHeight: 1_000,
            initiallyExpandedLiveDetails: true
        )
        XCTAssertEqual(
            expandedLightOverviewSize.height,
            try XCTUnwrap(lightOverviewHeight),
            accuracy: 0.5,
            "Light details must keep the fixed window geometry"
        )
        let tiboLightSize = try render(
            page: .tiboSignal,
            theme: .light,
            output: projectRoot.appendingPathComponent("build/ui-redesign/tibo-signal-light.png"),
            minimumHeight: 650,
            maximumHeight: 750
        )
        XCTAssertEqual(tiboLightSize.height, try XCTUnwrap(lightOverviewHeight), accuracy: 0.5)
        let tiboDarkSize = try render(
            page: .tiboSignal,
            theme: .dark,
            output: projectRoot.appendingPathComponent("build/ui-redesign/tibo-signal-dark.png"),
            minimumHeight: 650,
            maximumHeight: 750
        )
        XCTAssertEqual(tiboDarkSize.height, try XCTUnwrap(darkOverviewHeight), accuracy: 0.5)
        let darkConsoleSize = try render(page: .settings, theme: .dark, output: projectRoot.appendingPathComponent("build/ui-redesign/console-dark.png"), minimumHeight: 650, maximumHeight: 750)
        XCTAssertEqual(darkConsoleSize.height, try XCTUnwrap(darkOverviewHeight), accuracy: 0.5)
        let lightConsoleSize = try render(page: .settings, theme: .light, output: projectRoot.appendingPathComponent("build/ui-redesign/console-light.png"), minimumHeight: 650, maximumHeight: 750)
        XCTAssertEqual(lightConsoleSize.height, try XCTUnwrap(lightOverviewHeight), accuracy: 0.5)
        let liveConsoleSize = try render(page: .settings, theme: .light, output: projectRoot.appendingPathComponent("build/ui-redesign/live-settings-light.png"), minimumHeight: 650, maximumHeight: 750, consolePanel: .live)
        XCTAssertEqual(liveConsoleSize.height, try XCTUnwrap(lightOverviewHeight), accuracy: 0.5)
        viewModel.accountActionMessage = viewModel.t("account.codexActivated", "designer@example.com")
        let darkAccountsSize = try render(page: .settings, theme: .dark, output: projectRoot.appendingPathComponent("build/ui-redesign/accounts-dark.png"), minimumHeight: 650, maximumHeight: 750, consolePanel: .account)
        XCTAssertEqual(darkAccountsSize.height, try XCTUnwrap(darkOverviewHeight), accuracy: 0.5)
        let lightAccountsSize = try render(page: .settings, theme: .light, output: projectRoot.appendingPathComponent("build/ui-redesign/accounts-light.png"), minimumHeight: 650, maximumHeight: 750, consolePanel: .account)
        XCTAssertEqual(lightAccountsSize.height, try XCTUnwrap(lightOverviewHeight), accuracy: 0.5)
        let dataConsoleSize = try render(page: .settings, theme: .light, output: projectRoot.appendingPathComponent("build/ui-redesign/data-settings-light.png"), minimumHeight: 650, maximumHeight: 750, consolePanel: .data)
        XCTAssertEqual(dataConsoleSize.height, try XCTUnwrap(lightOverviewHeight), accuracy: 0.5)
        let tokenFixture = #"{"provider":"openai","credentials":{"accessToken":"preview-access-token","accountId":"preview-account"}}"#
        let tokenDarkSize = try render(page: .tokenLogin, theme: .dark, output: projectRoot.appendingPathComponent("build/ui-redesign/token-login-dark.png"), minimumHeight: 650, maximumHeight: 750, credentialText: tokenFixture)
        XCTAssertEqual(tokenDarkSize.height, try XCTUnwrap(darkOverviewHeight), accuracy: 0.5)
        let tokenLightSize = try render(page: .tokenLogin, theme: .light, output: projectRoot.appendingPathComponent("build/ui-redesign/token-login-light.png"), minimumHeight: 650, maximumHeight: 750, credentialText: tokenFixture)
        XCTAssertEqual(tokenLightSize.height, try XCTUnwrap(lightOverviewHeight), accuracy: 0.5)
        let lightDeveloperSize = try render(page: .about, theme: .light, output: projectRoot.appendingPathComponent("build/ui-redesign/about-light.png"), minimumHeight: 650, maximumHeight: 750)
        XCTAssertEqual(lightDeveloperSize.height, try XCTUnwrap(lightOverviewHeight), accuracy: 0.5)
        let darkDeveloperSize = try render(page: .about, theme: .dark, output: projectRoot.appendingPathComponent("build/ui-redesign/about-dark.png"), minimumHeight: 650, maximumHeight: 750)
        XCTAssertEqual(darkDeveloperSize.height, try XCTUnwrap(darkOverviewHeight), accuracy: 0.5)
        let lightUpdateSize = try render(page: .updates, theme: .light, output: projectRoot.appendingPathComponent("build/ui-redesign/updates-light.png"), minimumHeight: 650, maximumHeight: 750)
        XCTAssertEqual(lightUpdateSize.height, try XCTUnwrap(lightOverviewHeight), accuracy: 0.5)
        let darkUpdateSize = try render(page: .updates, theme: .dark, output: projectRoot.appendingPathComponent("build/ui-redesign/updates-dark.png"), minimumHeight: 650, maximumHeight: 750)
        XCTAssertEqual(darkUpdateSize.height, try XCTUnwrap(darkOverviewHeight), accuracy: 0.5)
        let lightLegalSize = try render(page: .legal, theme: .light, output: projectRoot.appendingPathComponent("build/ui-redesign/legal-light.png"), minimumHeight: 650, maximumHeight: 750, legalDocument: .privacy)
        XCTAssertEqual(lightLegalSize.height, try XCTUnwrap(lightOverviewHeight), accuracy: 0.5)
        let darkLegalSize = try render(page: .legal, theme: .dark, output: projectRoot.appendingPathComponent("build/ui-redesign/legal-dark.png"), minimumHeight: 650, maximumHeight: 750, legalDocument: .openSource)
        XCTAssertEqual(darkLegalSize.height, try XCTUnwrap(darkOverviewHeight), accuracy: 0.5)

        let referenceContext = try XCTUnwrap(viewModel.liveContext)
        XCTAssertEqual(TokenDetailScope.context.usage(in: referenceContext), referenceContext.lastRequest)
        XCTAssertEqual(TokenDetailScope.turn.usage(in: referenceContext), referenceContext.currentTurnUsage)
        XCTAssertEqual(TokenDetailScope.task.usage(in: referenceContext), referenceContext.taskTotal)
        XCTAssertNotEqual(referenceContext.lastRequest, referenceContext.taskTotal)

        for scope in TokenDetailScope.allCases {
            try render(page: .overview, theme: .light,
                       output: projectRoot.appendingPathComponent("build/ui-redesign/detail-\(scope.rawValue).png"),
                       minimumHeight: 650, initiallyExpandedLiveDetails: true, detailScope: scope)
        }
        for theme in [AppTheme.light, .dark] {
            try render(page: .tiboSignal, theme: theme,
                       output: projectRoot.appendingPathComponent("build/ui-redesign/tibo-evidence-\(theme.rawValue).png"),
                       minimumHeight: 650, tiboEvidence: true)
        }
        for language in AppLanguage.allCases where language != .system {
            viewModel.appLanguage = language
            try render(page: .more, theme: .light,
                       output: projectRoot.appendingPathComponent("build/ui-redesign/\(language.rawValue)-more.png"),
                       minimumHeight: 650, canvasWidth: 420)
            for destination in [MenuPopoverPage.overview, .tokenDetails, .usageHistory, .quotaDetails, .settings, .about, .updates, .tokenLogin, .tiboSignal] {
                try render(page: destination, theme: .light,
                           output: projectRoot.appendingPathComponent("build/ui-redesign/\(language.rawValue)-\(destination.rawValue).png"),
                           minimumHeight: 650, canvasWidth: 420)
            }
        }
        viewModel.appLanguage = .zhHans
        for compact in [false, true] {
            viewModel.abbreviateTokenCounts = compact
            for theme in [AppTheme.light, .dark] {
                for destination in [MenuPopoverPage.overview, .tokenDetails, .usageHistory, .sessions, .activeTasks, .settings] {
                    try render(page: destination, theme: theme,
                               output: projectRoot.appendingPathComponent("build/token-display/\(destination.rawValue)-\(compact)-\(theme.rawValue).png"),
                               minimumHeight: 650, canvasWidth: compact ? 420 : 340)
                }
            }
        }
        viewModel.abbreviateTokenCounts = false
        viewModel.accountErrorMessage = "Preview: account sync failed. Retry the connection."
        try render(page: .overview, theme: .light,
                   output: projectRoot.appendingPathComponent("build/ui-redesign/sync-error.png"), minimumHeight: 650)
        try render(page: .usageHistory, theme: .light,
                   output: projectRoot.appendingPathComponent("build/ui-redesign/usage-history-sync-error.png"), minimumHeight: 650)
        viewModel.accountErrorMessage = nil
        let savedAccounts = viewModel.accountSnapshots
        let savedContexts = viewModel.liveContexts
        viewModel.accountSnapshots = []
        viewModel.liveContexts = []
        viewModel.liveContext = nil
        viewModel.isScanning = true
        try render(page: .overview, theme: .light,
                   output: projectRoot.appendingPathComponent("build/ui-redesign/loading.png"), minimumHeight: 650)
        try render(page: .usageHistory, theme: .light,
                   output: projectRoot.appendingPathComponent("build/ui-redesign/usage-history-loading.png"), minimumHeight: 650)
        viewModel.isScanning = false
        try render(page: .overview, theme: .dark,
                   output: projectRoot.appendingPathComponent("build/ui-redesign/empty.png"), minimumHeight: 650)
        try render(page: .usageHistory, theme: .dark,
                   output: projectRoot.appendingPathComponent("build/ui-redesign/usage-history-empty.png"), minimumHeight: 650)
        viewModel.accountSnapshots = savedAccounts
        viewModel.liveContexts = savedContexts
        viewModel.liveContext = referenceContext

        viewModel.liveContext = CodexLiveContextSnapshot(
            id: referenceContext.id, sourcePath: referenceContext.sourcePath, projectPath: referenceContext.projectPath,
            threadTitle: referenceContext.threadTitle, titleSource: referenceContext.titleSource, turnID: referenceContext.turnID,
            model: referenceContext.model, reasoningEffort: referenceContext.reasoningEffort, updatedAt: now,
            lastRequest: TokenUsage(inputTokens: 1_050_000, cachedInputTokens: 1_048_576, outputTokens: 100_000),
            currentTurnUsage: referenceContext.currentTurnUsage, currentTurnCalls: referenceContext.currentTurnCalls,
            taskTotal: TokenUsage(inputTokens: 124_456_789_012, cachedInputTokens: 122_456_789_012, outputTokens: 9_876_543_210),
            modelContextWindow: referenceContext.modelContextWindow, duplicateEventsIgnored: 0, isTaskActive: true
        )
        for theme in [AppTheme.light, .dark] {
            try render(page: .overview, theme: theme,
                       output: projectRoot.appendingPathComponent("build/ui-redesign/large-context-\(theme.rawValue).png"), minimumHeight: 650)
            try render(page: .tokenDetails, theme: theme,
                       output: projectRoot.appendingPathComponent("build/ui-redesign/large-task-\(theme.rawValue).png"), minimumHeight: 650, detailScope: .task)
        }
        viewModel.liveContext = referenceContext

        viewModel.liveContexts = Array(viewModel.liveContexts.prefix(1))
        let singleTaskSize = try render(
            page: .overview,
            theme: .dark,
            output: projectRoot.appendingPathComponent("build/ui-redesign/single-task-dark.png"),
            minimumHeight: 650,
            maximumHeight: 750
        )
        XCTAssertEqual(singleTaskSize.height, try XCTUnwrap(darkOverviewHeight), accuracy: 0.5)

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

        XCTAssertTrue(source.contains("private let sessionsPerPage = 7"))
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
            "update.releaseNote.windowCorners",
        ]

        for language in AppLanguage.allCases where language != .system {
            for key in keys {
                let value = LocalizationCatalog.text(key, language: language)
                let width = (value as NSString).size(withAttributes: [.font: font]).width
                XCTAssertLessThanOrEqual(width, 280, "\(language) \(key): \(value)")
            }
        }
    }

    @MainActor
    func testNativeGlassOwnsWholeWindowAndPreservesSafeScreenBounds() throws {
        let panel = FrostedDashboardPanel(content: AnyView(Text("Preview")))
        defer { panel.close() }
        XCTAssertFalse(panel.isOpaque)
        XCTAssertEqual(panel.backgroundColor, .clear)
        XCTAssertEqual(panel.backdrop.blendingMode, .behindWindow)
        XCTAssertEqual(panel.backdrop.material, .menu)
        XCTAssertEqual(panel.backdrop.state, .active)
        XCTAssertTrue(panel.contentView === panel.backdrop)
        XCTAssertTrue(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertFalse(panel.hostingView.isOpaque)
        XCTAssertTrue(panel.hostingView.allowsVibrancy)
        panel.contentView?.layoutSubtreeIfNeeded()
        XCTAssertEqual(panel.backdrop.bounds.size, panel.contentLayoutRect.size)
        XCTAssertEqual(panel.hostingView.frame.size, NSSize(width: 340, height: 680))
        let scroll = try XCTUnwrap(panel.backdrop.subviews.first(where: { $0 is NSScrollView }) as? NSScrollView)
        XCTAssertFalse(scroll.drawsBackground)
        XCTAssertFalse(scroll.contentView.drawsBackground)
        XCTAssertEqual(scroll.frame, panel.backdrop.bounds)
        XCTAssertEqual(panel.backdrop.subviews, [scroll])
        var dismissed = false
        panel.onDismiss = { dismissed = true }
        panel.cancelOperation(nil)
        XCTAssertTrue(dismissed)
        for screen in [NSRect(x: 0, y: 60, width: 1440, height: 815), NSRect(x: -1280, y: 0, width: 1280, height: 695)] {
            for x in [screen.minX, screen.midX, screen.maxX] {
                let frame = FrostedDashboardPanel.frame(anchoredTo: NSRect(x: x, y: screen.maxY, width: 30, height: 25), visibleFrame: screen)
                XCTAssertEqual(frame.width, 340)
                XCTAssertLessThanOrEqual(frame.height, 680)
                XCTAssertTrue(screen.contains(frame))
            }
        }
    }

    @MainActor
    func testNativeGlassMaskKeepsRoundCornersWhenWindowResizes() throws {
        let panel = FrostedDashboardPanel(content: AnyView(Text("Preview")))
        defer { panel.close() }
        let mask = try XCTUnwrap(panel.backdrop.maskImage, "The native material and window shadow need their own mask")
        let radius = try XCTUnwrap(panel.backdrop.layer).cornerRadius
        XCTAssertEqual(radius, 14)
        XCTAssertEqual(mask.size, NSSize(width: radius * 2 + 1, height: radius * 2 + 1))
        XCTAssertEqual(mask.capInsets.top, radius)
        XCTAssertEqual(mask.capInsets.left, radius)
        XCTAssertEqual(mask.capInsets.bottom, radius)
        XCTAssertEqual(mask.capInsets.right, radius)
        XCTAssertEqual(mask.resizingMode, .stretch)
        XCTAssertTrue(try XCTUnwrap(panel.backdrop.layer).masksToBounds, "The material mask does not clip child views")
        XCTAssertTrue(panel.contentView === panel.backdrop, "The material must own the window shadow")
        XCTAssertTrue(panel.hasShadow)

        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("build/window-corners")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for size in [NSSize(width: 340, height: 680), NSSize(width: 340, height: 480), NSSize(width: 420, height: 680)] {
            panel.setContentSize(size)
            panel.contentView?.layoutSubtreeIfNeeded()
            XCTAssertTrue(panel.backdrop.maskImage === mask)
            XCTAssertEqual(panel.backdrop.bounds.size, size)
            for scale in [1, 2] {
                let bitmap = try XCTUnwrap(NSBitmapImageRep(
                    bitmapDataPlanes: nil, pixelsWide: Int(size.width) * scale, pixelsHigh: Int(size.height) * scale,
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
                ))
                bitmap.size = size
                let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = context
                mask.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .copy, fraction: 1)
                NSGraphicsContext.restoreGraphicsState()

                func alpha(x: CGFloat, y: CGFloat) throws -> CGFloat {
                    try XCTUnwrap(bitmap.colorAt(x: Int(x * CGFloat(scale)), y: Int(y * CGFloat(scale)))).alphaComponent
                }
                for right in [false, true] {
                    for bottom in [false, true] {
                        func point(_ inset: CGFloat) -> NSPoint {
                            NSPoint(x: right ? size.width - inset : inset, y: bottom ? size.height - inset : inset)
                        }
                        for inset in [CGFloat(0.5), 2.5] {
                            let outside = point(inset)
                            XCTAssertLessThan(try alpha(x: outside.x, y: outside.y), 0.02, "No square material at the outer corner")
                        }
                        let inside = point(7.5)
                        XCTAssertGreaterThan(try alpha(x: inside.x, y: inside.y), 0.98, "Do not cut a transparent square from the corner")
                    }
                }
                XCTAssertGreaterThan(try alpha(x: size.width / 2, y: 0.5), 0.98)
                XCTAssertGreaterThan(try alpha(x: 0.5, y: size.height / 2), 0.98)
                let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                try png.write(to: root.appendingPathComponent("mask-\(Int(size.width))x\(Int(size.height))-\(scale)x.png"))
            }
        }
    }

    @MainActor
    func testNativeMenuMaterialKeepsClearContentAcrossAppearances() throws {
        let panel = FrostedDashboardPanel(content: AnyView(Text("Preview")))
        defer { panel.close() }
        for name in [NSAppearance.Name.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua] {
            let appearance = try XCTUnwrap(NSAppearance(named: name))
            panel.appearance = appearance
            panel.contentView?.appearance = appearance
            panel.contentView?.layoutSubtreeIfNeeded()
            XCTAssertEqual(panel.backdrop.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]),
                           appearance.bestMatch(from: [.aqua, .darkAqua]))
            XCTAssertEqual(panel.backdrop.material, .menu)
            XCTAssertEqual(panel.backdrop.blendingMode, .behindWindow)
            XCTAssertEqual(panel.backgroundColor, .clear)
            XCTAssertEqual(panel.alphaValue, 1)
            XCTAssertFalse(panel.hostingView.isOpaque)
            XCTAssertTrue(panel.hostingView.allowsVibrancy)
            XCTAssertEqual(panel.hostingView.layer?.backgroundColor?.alpha, 0)
            XCTAssertEqual(panel.backdrop.subviews.count, 1)
        }
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
        XCTAssertTrue(contents.contains("static let primaryPageHeight: CGFloat = 680"))
        XCTAssertTrue(contents.contains(".padding(.horizontal, 16)"))
        XCTAssertTrue(contents.contains(".background(Color.clear)"))
        XCTAssertFalse(contents.contains("PulsePalette.focusSurface"))
        XCTAssertTrue(contents.contains("idleColor: PulsePalette.ink"))
        XCTAssertTrue(contents.contains("spinningColor: PulsePalette.warning"))
        XCTAssertTrue(contents.contains(".toggleStyle(.switch)"))
        XCTAssertTrue(contents.contains("ContextTokenRow("))
        XCTAssertTrue(contents.contains("direction: .input"))
        XCTAssertTrue(contents.contains("direction: .cached"))
        XCTAssertTrue(contents.contains("direction: .output"))
        XCTAssertTrue(contents.contains("private enum HeroTokenDirection"))
        XCTAssertTrue(contents.contains("PulseIcon(name: direction.iconName)"))
        XCTAssertTrue(contents.contains("viewModel.tokenText(context.contextInputTokens)"))
        XCTAssertTrue(contents.contains("Text(viewModel.t(\"live.tokenDetail\"))"))
        XCTAssertTrue(contents.contains("viewModel.t(\"detail.currentContext\")"))
        XCTAssertTrue(contents.contains("viewModel.t(\"live.inputIncludesCache\")"))
        XCTAssertTrue(contents.contains("TokenScopeDetailSection("))
        XCTAssertTrue(contents.contains("DetailTokenMetric("))
        XCTAssertTrue(contents.contains("viewModel.tokenText(value)"))
        XCTAssertTrue(contents.contains("private struct TokenAmount"))
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
        XCTAssertTrue(contents.contains("MarqueeLabel("))
        XCTAssertTrue(contents.contains(".lineLimit(1)"))
        XCTAssertTrue(contents.contains(".allowsTightening(false)"))
        XCTAssertFalse(contents.contains(".lineLimit(2)"))
        XCTAssertFalse(contents.contains(".minimumScaleFactor"))
        let metricStart = try XCTUnwrap(contents.range(of: "private func usageMetric(title:"))
        let metricEnd = try XCTUnwrap(contents.range(of: "private func usageMonthRow("))
        let metricRange = metricStart.lowerBound..<metricEnd.lowerBound
        XCTAssertTrue(contents[metricRange].contains("LabeledContent"))
        XCTAssertTrue(contents[metricRange].contains(".fixedSize(horizontal: false, vertical: true)"))
        // Full Token counts may wrap within their summary rows, not resize the other pages.
        let otherViews = contents.replacingCharacters(in: metricRange, with: "")
        XCTAssertFalse(otherViews.contains(".fixedSize(horizontal: false"))
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

    func testPageChangesDoNotRecreateOrResizeTheGlassWindow() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let dashboard = try String(contentsOf: root.appendingPathComponent("Sources/CodexTokenLedger/Views/MenuBarDashboardView.swift"), encoding: .utf8)
        let controller = try String(contentsOf: root.appendingPathComponent("Sources/CodexTokenLedger/NativeMenuBarController.swift"), encoding: .utf8)
        XCTAssertTrue(dashboard.contains(".background(Color.clear)"))
        XCTAssertTrue(dashboard.contains("case .tokenDetails: tokenDetails"))
        XCTAssertTrue(dashboard.contains("onOpenDetails: { page = .tokenDetails }"))
        XCTAssertFalse(dashboard.contains("isDetailsExpanded"))
        XCTAssertFalse(controller.contains("menu.update()"))
        XCTAssertFalse(controller.contains("menuLayoutRevision"))
        XCTAssertFalse(controller.contains("asyncAfter"))
        XCTAssertTrue(controller.contains("NSEvent.addLocalMonitorForEvents"))
        XCTAssertTrue(controller.contains("NSEvent.addGlobalMonitorForEvents"))
        XCTAssertTrue(controller.contains("NSEvent.removeMonitor"))
        XCTAssertTrue(controller.contains("button.title = text"))
        XCTAssertTrue(controller.contains("case .contextUsed: specification = (\"arrow-right\", -90)"))
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
