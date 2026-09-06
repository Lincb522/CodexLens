import AppKit
import SwiftUI

enum MenuPopoverPage: String {
    case overview
    case usageHistory
    case tokenDetails
    case quotaDetails
    case activeTasks
    case tiboSignal
    case sessions
    case settings
    case tokenLogin
    case about
    case updates
    case legal
    case more
}

enum LegalDocument: String, CaseIterable, Identifiable {
    case userAgreement
    case privacy
    case openSource
    case disclaimer

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .userAgreement: "legal.userAgreement"
        case .privacy: "legal.privacy"
        case .openSource: "legal.openSource"
        case .disclaimer: "legal.disclaimer"
        }
    }

    var pageKeys: [String] {
        switch self {
        case .userAgreement: ["legal.userAgreement.page1", "legal.userAgreement.page2"]
        case .privacy: ["legal.privacy.page1", "legal.privacy.page2"]
        case .openSource: ["legal.openSource.page1", "legal.openSource.page2"]
        case .disclaimer: ["legal.disclaimer.page1", "legal.disclaimer.page2"]
        }
    }
}

enum ConsolePanel: String, CaseIterable, Identifiable {
    case appearance
    case live
    case account
    case data
    var id: String { rawValue }
}

private enum PulsePalette {
    // The native panel owns the backdrop; these fills only group content.
    private static func adaptiveColor(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark ? dark : light
        })
    }

    private static func adaptive(
        light: CGFloat,
        dark: CGFloat,
        alpha: CGFloat = 1
    ) -> Color {
        adaptiveColor(
            light: NSColor(calibratedWhite: light, alpha: alpha),
            dark: NSColor(calibratedWhite: dark, alpha: alpha)
        )
    }

    static let surface = adaptive(light: 1, dark: 0.86, alpha: 0.018)
    static let surfaceRaised = adaptive(light: 1, dark: 0.86, alpha: 0.045)
    static let surfaceHover = adaptive(light: 0.38, dark: 1, alpha: 0.09)
    static let ink = adaptiveColor(
        light: NSColor(srgbRed: 0.22, green: 0.25, blue: 0.30, alpha: 1),
        dark: NSColor(calibratedWhite: 0.90, alpha: 1)
    )
    static let muted = adaptiveColor(
        light: NSColor(srgbRed: 0.36, green: 0.39, blue: 0.43, alpha: 1),
        dark: NSColor(calibratedWhite: 0.76, alpha: 1)
    )
    static let faint = muted
    static let accent = adaptiveColor(
        light: NSColor(srgbRed: 0.20, green: 0.36, blue: 0.72, alpha: 1),
        dark: NSColor(srgbRed: 0.43, green: 0.59, blue: 0.96, alpha: 1)
    )

    static let lime = adaptiveColor(
        light: NSColor(srgbRed: 0.02, green: 0.45, blue: 0.34, alpha: 1),
        dark: NSColor(srgbRed: 0.42, green: 0.88, blue: 0.70, alpha: 1)
    )
    static let coral = adaptiveColor(
        light: NSColor(srgbRed: 0.70, green: 0.27, blue: 0.30, alpha: 1),
        dark: NSColor(srgbRed: 0.94, green: 0.51, blue: 0.49, alpha: 1)
    )
    static let warning = adaptiveColor(
        light: NSColor(srgbRed: 0.66, green: 0.41, blue: 0.05, alpha: 1),
        dark: NSColor(srgbRed: 0.93, green: 0.70, blue: 0.29, alpha: 1)
    )
    static let divider = adaptive(light: 0.2, dark: 0.95, alpha: 0.12)

    static let selectionInk = adaptiveColor(
        light: NSColor(calibratedWhite: 0.98, alpha: 1),
        dark: NSColor(srgbRed: 0.08, green: 0.16, blue: 0.23, alpha: 1)
    )
    static let detailMuted = muted

    static func heatmapGlassTint(intensity: Int) -> Color {
        let dark: NSColor
        switch intensity {
        case 1: dark = NSColor(srgbRed: 0.26, green: 0.36, blue: 0.54, alpha: 1)
        case 2: dark = NSColor(srgbRed: 0.27, green: 0.43, blue: 0.80, alpha: 1)
        case 3: dark = NSColor(srgbRed: 0.37, green: 0.55, blue: 1, alpha: 1)
        default: dark = NSColor(srgbRed: 0.49, green: 0.65, blue: 1, alpha: 1)
        }
        return adaptiveColor(
            light: intensity == 4
                ? NSColor(srgbRed: 0.40, green: 0.62, blue: 0.95, alpha: 1)
                : NSColor(srgbRed: 0.27, green: 0.49, blue: 0.84, alpha: 1),
            dark: dark
        )
    }
    static let heatmapEmpty = adaptiveColor(
        light: NSColor(srgbRed: 0.58, green: 0.66, blue: 0.75, alpha: 0.11),
        dark: NSColor(srgbRed: 0.58, green: 0.64, blue: 0.77, alpha: 0.16)
    )
    static let heatmapFuture = adaptiveColor(
        light: NSColor(calibratedWhite: 1, alpha: 0.12),
        dark: NSColor(calibratedWhite: 1, alpha: 0.035)
    )
}

private extension View {
    func glassOutline(radius: CGFloat = 9) -> some View {
        background(PulsePalette.surface, in: RoundedRectangle(cornerRadius: radius))
            .overlay { RoundedRectangle(cornerRadius: radius).stroke(PulsePalette.divider, lineWidth: 0.5) }
    }
}

struct PulseIcon: View {
    let name: String

    var body: some View {
        Image("PulseIcon-\(name)")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .accessibilityHidden(true)
    }
}

struct MenuBarLabelView: View {
    @EnvironmentObject private var viewModel: DashboardViewModel
    private let accountTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()
    private let liveTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 4) {
            PulseIcon(name: statusIconName)
                .frame(width: 13, height: 13)
                .rotationEffect(.degrees(viewModel.menuBarMetric == .contextUsed ? 90 : 0))
            if viewModel.menuBarMetric != .iconOnly {
                Text(viewModel.menuBarText)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .monospacedDigit()
            }
        }
        .task { viewModel.loadIfNeeded() }
        .onReceive(liveTimer) { _ in viewModel.scheduledLiveContextTick() }
        .onReceive(accountTimer) { _ in viewModel.accountTimerTick() }
    }

    private var statusIconName: String {
        switch viewModel.menuBarMetric {
        case .contextUsed: "arrow-right"
        case .requestAPICost, .credits, .usd: "credits"
        case .quotaRemaining: "quota"
        case .weeklyRemaining: "calendar"
        case .tokens: "ledger"
        case .iconOnly: "pulse"
        }
    }
}

struct MenuBarDashboardView: View {
    static let contentWidth: CGFloat = 340
    static let primaryPageHeight: CGFloat = 680
    private static let secondaryHeaderHeight: CGFloat = 62
    private static let footerHeight: CGFloat = 58
    private static let overviewPageContentHeight = primaryPageHeight - footerHeight
    private static let primaryPageContentHeight = primaryPageHeight - secondaryHeaderHeight - footerHeight

    @EnvironmentObject private var viewModel: DashboardViewModel
    @ObservedObject private var updateService: AppUpdateService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var systemColorScheme
    @State private var page: MenuPopoverPage
    @State private var activeTaskPage = 0
    @State private var sessionPage = 0
    @State private var consolePanel: ConsolePanel = .appearance
    @State private var credentialText: String
    @State private var credentialMode: AccountSwitchMode = .activateCodex
    @State private var legalDocument: LegalDocument
    @State private var legalPage = 0
    @State private var selectedUsageDayKey: String?
    @State private var usageHistoryShowsRecentHalf = true
    @State private var quotaWindowID: String?
    @State private var quotaGroupID: String?
    @State private var quotaShowsEstimateEvidence = false
    @State private var tiboShowsEvidence: Bool
    private let initialDetailScope: TokenDetailScope

    // Pagination keeps every list inside the native menu viewport.
    private let sessionsPerPage = 7
    private let activeTasksPerPage = 7

    init(
        updateService: AppUpdateService,
        initialPage: MenuPopoverPage = .overview,
        initialConsolePanel: ConsolePanel = .appearance,
        initialCredentialText: String = "",
        initialLegalDocument: LegalDocument = .userAgreement,
        initiallyExpandedLiveDetails: Bool = false,
        initialDetailScope: TokenDetailScope = .context,
        initiallyShowingTiboEvidence: Bool = false
    ) {
        _updateService = ObservedObject(wrappedValue: updateService)
        _page = State(initialValue: initiallyExpandedLiveDetails ? .tokenDetails : initialPage)
        _consolePanel = State(initialValue: initialConsolePanel)
        _credentialText = State(initialValue: initialCredentialText)
        _legalDocument = State(initialValue: initialLegalDocument)
        _selectedUsageDayKey = State(initialValue: nil)
        _tiboShowsEvidence = State(initialValue: initiallyShowingTiboEvidence)
        self.initialDetailScope = initialDetailScope
    }

    var body: some View {
        VStack(spacing: 0) {
            if page != .overview {
                header
            }

            Group {
                switch page {
                case .overview: overview
                case .tokenDetails: tokenDetails
                case .usageHistory: usageHistory
                case .quotaDetails: quotaDetails
                case .activeTasks: activeTasks
                case .tiboSignal: tiboSignalDetail
                case .sessions: sessions
                case .settings: settings
                case .tokenLogin: tokenLogin
                case .about: about
                case .updates: updates
                case .legal: legalViewer
                case .more: moreActions
                }
            }
            .id(page)
            .frame(maxWidth: .infinity)
            .frame(
                height: page == .overview
                    ? Self.overviewPageContentHeight
                    : Self.primaryPageContentHeight,
                alignment: .top
            )

            footer
        }
        .frame(width: Self.contentWidth)
        .background(Color.clear)
        .lineLimit(1)
        .allowsTightening(false)
        .fixedSize(horizontal: true, vertical: true)
        .preferredColorScheme(viewModel.appTheme.colorScheme)
        .environment(\.colorScheme, viewModel.appTheme.colorScheme ?? systemColorScheme)
        .environment(\.locale, Locale(identifier: viewModel.appLanguage.localeIdentifier))
        .onChange(of: viewModel.searchText) { _, _ in sessionPage = 0 }
        .onChange(of: viewModel.filteredSessions.count) { _, _ in
            sessionPage = min(sessionPage, max(0, sessionPageCount - 1))
        }
        .onChange(of: viewModel.activeTaskCount) { _, _ in
            activeTaskPage = min(activeTaskPage, max(0, activeTaskPageCount - 1))
        }
        .onChange(of: legalDocument) { _, _ in legalPage = 0 }
    }

    private var isLightAppearance: Bool {
        switch viewModel.appTheme {
        case .light: true
        case .dark: false
        case .system: systemColorScheme == .light
        }
    }

    private var strongSelection: Color {
        PulsePalette.accent
    }

    private var strongSelectionInk: Color {
        PulsePalette.selectionInk
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                if page == .tokenLogin {
                    consolePanel = .account
                    page = .settings
                } else if page == .updates || page == .legal {
                    page = .about
                } else if page != .overview {
                    page = .overview
                }
            } label: {
                ZStack {
                    PulseIcon(name: "chevron-down")
                        .rotationEffect(.degrees(90))
                        .frame(width: 13, height: 13)
                        .foregroundStyle(PulsePalette.ink)
                }
                .frame(width: 32, height: 32)
            }
            .buttonStyle(PulsePressStyle())
            .help(viewModel.t("action.back"))
            .accessibilityLabel(viewModel.t("action.back"))
            .accessibilityIdentifier("Page.Back")

            MarqueeLabel(text: pageTitle, font: .system(size: 19, weight: .semibold), color: PulsePalette.ink)
                .frame(height: 25)

            Spacer(minLength: 8)
        }
        .frame(width: Self.contentWidth - 32, height: Self.secondaryHeaderHeight)
        .padding(.horizontal, 16)
    }

    private var accountContext: some View {
        Button {
            consolePanel = .account
            page = .settings
        } label: {
            HStack(spacing: 6) {
                Text(viewModel.selectedAccount?.planDisplayName ?? viewModel.t("settings.tab.account"))
                    .font(.system(size: 12, weight: .medium))
                PulseIcon(name: "chevron-down").frame(width: 8, height: 8)
            }
            .foregroundStyle(PulsePalette.muted)
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(PulsePalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay { RoundedRectangle(cornerRadius: 6).stroke(PulsePalette.divider, lineWidth: 0.5) }
            .contentShape(Rectangle())
        }
        .buttonStyle(PulsePressStyle())
        .help(viewModel.selectedAccount.map { viewModel.accountName($0) } ?? viewModel.t("account.addCodex"))
        .accessibilityLabel(viewModel.t("console.accounts"))
        .accessibilityIdentifier("Overview.Accounts")
    }

    private var pageTitle: String {
        switch page {
        case .overview: viewModel.t("page.overview")
        case .tokenDetails: viewModel.t("live.tokenDetail")
        case .usageHistory: viewModel.t("usage.title")
        case .quotaDetails: viewModel.t("quota.accountScope")
        case .activeTasks: viewModel.t("page.activeTasks")
        case .tiboSignal: viewModel.t("page.tiboSignal")
        case .sessions: viewModel.t("page.ledger")
        case .settings: viewModel.t("page.console")
        case .tokenLogin: viewModel.t("page.tokenLogin")
        case .about: viewModel.t("page.about")
        case .updates: viewModel.t("page.updates")
        case .legal: viewModel.t(legalDocument.titleKey)
        case .more: viewModel.t("page.more")
        }
    }

    private var overview: some View {
        VStack(spacing: 12) {
            overviewHero
            if let account = viewModel.selectedAccount {
                if let error = viewModel.accountErrorMessage {
                    inlineFailure(error, title: viewModel.t("account.stale"))
                }
                accountUsageOverview(account)
            } else if viewModel.isScanning {
                accountLoadingSurface
            } else {
                inlineFailure(
                    viewModel.accountErrorMessage ?? viewModel.t("account.noReadable"),
                    title: viewModel.t("account.unavailable")
                )
            }
            VStack(spacing: 8) {
                if let account = viewModel.selectedAccount {
                    quotaOverviewRow(account)
                }
                if viewModel.tiboMonitoringEnabled {
                    tiboGlobalSignalRow
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 8)
        .frame(maxHeight: .infinity, alignment: .top)
        .frame(width: Self.contentWidth)
    }

    private var overviewHero: some View {
        VStack(spacing: 12) {
            overviewHeroHeader
            if viewModel.activeTaskCount > 0 { liveTaskSwitcher }
            liveContextCard
        }
    }

    private var overviewHeroHeader: some View {
        HStack(spacing: 12) {
            Text(viewModel.t("page.overview"))
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(PulsePalette.ink)
                .fixedSize()
            accountContext
            Spacer(minLength: 0)
            Button(action: viewModel.refresh) {
                AnimatedRefreshIcon(
                    isSpinning: viewModel.isScanning,
                    idleColor: PulsePalette.ink,
                    spinningColor: PulsePalette.warning
                )
                .frame(width: 30, height: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(PulsePressStyle())
            .disabled(viewModel.isScanning)
            .accessibilityLabel(viewModel.t("action.sync"))
            .help(viewModel.t("action.sync"))
        }
        .frame(height: 40)
    }

    private func accountUsageOverview(_ account: CodexAccountUsageSnapshot) -> some View {
        let heatmap = TokenUsageHeatmap.make(dailyBuckets: account.accountTokenUsage?.dailyBuckets ?? [])
        let visibleWeeks = Array(heatmap.weeks.suffix(OverviewUsageCalendar.weekCount))
        let compact = viewModel.accountErrorMessage != nil
        return VStack(alignment: .leading, spacing: 12) {
            PulsePalette.divider.frame(height: 1)
            Button {
                selectedUsageDayKey = nil
                usageHistoryShowsRecentHalf = true
                page = .usageHistory
            } label: {
                HStack(spacing: 8) {
                    MarqueeLabel(text: viewModel.t("usage.overviewTitle"), font: .system(size: 14, weight: .regular), color: PulsePalette.ink)
                        .frame(height: 20)
                    Spacer(minLength: 0)
                    Text(viewModel.t("usage.recentWeeks", OverviewUsageCalendar.weekCount))
                        .font(.system(size: 12))
                        .foregroundStyle(PulsePalette.muted)
                    PulseIcon(name: "chevron-down").frame(width: 8, height: 8)
                        .foregroundStyle(PulsePalette.muted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PulsePressStyle())
            .accessibilityIdentifier("Overview.UsageHistory")
            if !compact {
                OverviewUsageCalendar(
                    weeks: visibleWeeks,
                    locale: Locale(identifier: viewModel.appLanguage.localeIdentifier),
                    chartLabel: viewModel.t("usage.accountHistory"),
                    dayLabel: usageDayAccessibilityLabel
                ) { day in
                    selectedUsageDayKey = day.dateKey
                    usageHistoryShowsRecentHalf = true
                    page = .usageHistory
                }
            }
        }
        .frame(height: compact ? 46 : 182, alignment: .top)
    }

    @ViewBuilder
    private func quotaOverviewRow(_ account: CodexAccountUsageSnapshot) -> some View {
        if let window = account.preferredMenuWindow {
            Button { page = .quotaDetails } label: {
                HStack(spacing: 10) {
                    PulseIcon(name: "quota").frame(width: 19, height: 19)
                    MarqueeLabel(text: viewModel.t("quota.accountScope"), font: .system(size: 13), color: PulsePalette.ink)
                        .frame(height: 20)
                    VStack(alignment: .trailing, spacing: 5) {
                        Text("\(Int(window.remainingPercent.rounded()))%")
                            .font(.system(size: 16, weight: .regular)).monospacedDigit()
                        ContextUsageBar(progress: window.remainingPercent / 100, color: quotaAccent(window))
                            .frame(width: 104, height: 4)
                    }
                }
                .foregroundStyle(PulsePalette.ink)
                .padding(.horizontal, 12)
                .frame(height: 44)
                .glassOutline()
                .contentShape(Rectangle())
            }
            .buttonStyle(PulsePressStyle())
            .help(quotaCycleTitle(window))
            .accessibilityIdentifier("Overview.QuotaDetails")
        }
    }

    @ViewBuilder
    private var usageHistory: some View {
        if let account = viewModel.selectedAccount {
            let heatmap = TokenUsageHeatmap.make(
                dailyBuckets: account.accountTokenUsage?.dailyBuckets ?? []
            )
            let selectedDay = selectedUsageDay(in: heatmap)
            let months = usageMonthSummaries(heatmap)
            let visibleWeeks = usageHistoryShowsRecentHalf
                ? Array(heatmap.weeks.suffix(27))
                : Array(heatmap.weeks.prefix(26))
            let visibleMonths = usageHistoryShowsRecentHalf
                ? Array(heatmap.monthStarts.suffix(6))
                : Array(heatmap.monthStarts.prefix(6))

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(viewModel.t("usage.lastTwelveMonths"))
                                .font(.system(size: 12, weight: .semibold, design: .default))
                                .foregroundStyle(PulsePalette.muted)
                            Text("\(DisplayFormat.tokens(heatmap.totalTokens)) Token")
                                .font(.system(size: 22, weight: .semibold, design: .monospaced))
                                .foregroundStyle(PulsePalette.ink)
                                .monospacedDigit()
                        }

                        Spacer()

                        Text(viewModel.t("usage.activeDays", heatmap.activeDays))
                            .font(.system(size: 12, weight: .semibold, design: .default))
                            .foregroundStyle(PulsePalette.muted)
                    }

                    HStack(spacing: 8) {
                        Button {
                            usageHistoryShowsRecentHalf = false
                        } label: {
                            PulseIcon(name: "arrow-left")
                                .frame(width: 11, height: 11)
                                .frame(width: 28, height: 24)
                                .background(PulsePalette.surfaceRaised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(PulsePressStyle())
                        .disabled(!usageHistoryShowsRecentHalf)
                        .accessibilityLabel(usageMonthRangeLabel(Array(heatmap.monthStarts.prefix(6))))

                        Text(usageMonthRangeLabel(visibleMonths))
                            .font(.system(size: 13, weight: .semibold, design: .default))
                            .foregroundStyle(PulsePalette.ink)
                            .frame(maxWidth: .infinity)

                        Button {
                            usageHistoryShowsRecentHalf = true
                        } label: {
                            PulseIcon(name: "arrow-right")
                                .frame(width: 11, height: 11)
                                .frame(width: 28, height: 24)
                                .background(PulsePalette.surfaceRaised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(PulsePressStyle())
                        .disabled(usageHistoryShowsRecentHalf)
                        .accessibilityLabel(usageMonthRangeLabel(Array(heatmap.monthStarts.suffix(6))))
                    }

                    TokenUsageHeatmapGrid(
                        weeks: visibleWeeks,
                        cellSize: 8.7,
                        cellSpacing: 1.8,
                        selectedDayKey: selectedUsageDayKey,
                        onSelect: { selectedUsageDayKey = $0.dateKey },
                        chartLabel: viewModel.t("usage.accountHistory"),
                        dayLabel: usageDayAccessibilityLabel
                    )
                    .frame(width: 286, height: 72, alignment: .leading)

                    TokenUsageMonthLabels(
                        months: visibleMonths,
                        label: usageMonthLabel
                    )
                    .frame(width: 286, height: 14)
                }
                .padding(11)
                .background(PulsePalette.surface.opacity(0.72), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                usageSelectedDayRow(selectedDay)

                HStack(spacing: 0) {
                    usageMetric(
                        title: viewModel.t("usage.last30Days"),
                        value: "\(DisplayFormat.tokens(heatmap.last30DaysTokens)) Token"
                    )
                    PulsePalette.divider.frame(width: 1, height: 34)
                    usageMetric(
                        title: viewModel.t("usage.activeDaysShort"),
                        value: heatmap.activeDays.formatted()
                    )
                    PulsePalette.divider.frame(width: 1, height: 34)
                    usageMetric(
                        title: viewModel.t("usage.lifetime"),
                        value: account.accountTokenUsage?.summary.lifetimeTokens
                            .map { "\(DisplayFormat.tokens($0)) Token" } ?? "—"
                    )
                }
                .frame(height: 58)

                Text(viewModel.t("usage.monthly"))
                    .font(.system(size: 13, weight: .semibold, design: .default))
                    .foregroundStyle(PulsePalette.ink)

                ScrollView(.vertical) {
                    VStack(spacing: 4) {
                        ForEach(months) { month in
                            usageMonthRow(month, peak: months.map(\.tokens).max() ?? 0)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .accessibilityIdentifier("UsageHistory.Months")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(height: Self.primaryPageContentHeight, alignment: .top)
        } else {
            accountLoadingSurface
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(height: Self.primaryPageContentHeight, alignment: .top)
        }
    }

    private func usageSelectedDayRow(_ day: TokenUsageHeatmapDay?) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(day.map { usageDayLabel($0.date) } ?? viewModel.t("usage.selectDay"))
                    .font(.system(size: 13, weight: .semibold, design: .default))
                    .foregroundStyle(PulsePalette.ink)
                Text(viewModel.t("usage.dailyTotal"))
                    .font(.system(size: 12, weight: .medium, design: .default))
                    .foregroundStyle(PulsePalette.muted)
            }
            Spacer()
            Text(day.map { "\(DisplayFormat.integer($0.tokens)) Token" } ?? "—")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(PulsePalette.accent)
                .monospacedDigit()
        }
        .padding(.horizontal, 11)
        .frame(height: 48)
        .background(PulsePalette.surface.opacity(0.48), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func usageMetric(title: String, value: String) -> some View {
        VStack(alignment: .center, spacing: 3) {
            Text(title)
                .font(.system(size: 12, weight: .medium, design: .default))
                .foregroundStyle(PulsePalette.muted)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(PulsePalette.ink)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }

    private func usageMonthRow(_ month: TokenUsageMonthSummary, peak: Int64) -> some View {
        HStack(spacing: 10) {
            Text(usageMonthLabel(month.month))
                .font(.system(size: 12, weight: .semibold, design: .default))
                .foregroundStyle(PulsePalette.muted)
                .frame(width: 28, alignment: .leading)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(PulsePalette.divider)
                    if month.tokens > 0, peak > 0 {
                        Capsule()
                            .fill(PulsePalette.accent.opacity(0.78))
                            .frame(width: max(5, proxy.size.width * Double(month.tokens) / Double(peak)))
                    }
                }
            }
            .frame(height: 4)

            Text("\(DisplayFormat.tokens(month.tokens)) Token")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(PulsePalette.ink)
                .monospacedDigit()
                .frame(width: 104, alignment: .trailing)
        }
        .frame(height: 23)
    }

    private func selectedUsageDay(in heatmap: TokenUsageHeatmap) -> TokenUsageHeatmapDay? {
        if let selectedUsageDayKey,
           let selected = heatmap.days.first(where: { $0.dateKey == selectedUsageDayKey }) {
            return selected
        }
        return heatmap.days.last { !$0.isFuture && $0.tokens > 0 }
    }

    private func usageMonthSummaries(_ heatmap: TokenUsageHeatmap) -> [TokenUsageMonthSummary] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return heatmap.monthStarts.suffix(9).reversed().map { month in
            let components = calendar.dateComponents([.year, .month], from: month)
            let total = heatmap.days.lazy
                .filter {
                    let day = calendar.dateComponents([.year, .month], from: $0.date)
                    return !($0.isFuture) && day.year == components.year && day.month == components.month
                }
                .reduce(Int64(0)) { partial, day in
                    let (sum, overflow) = partial.addingReportingOverflow(day.tokens)
                    return overflow ? Int64.max : sum
                }
            return TokenUsageMonthSummary(month: month, tokens: total)
        }
    }

    private func usageMonthLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: viewModel.appLanguage.localeIdentifier)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.setLocalizedDateFormatFromTemplate("MMM")
        return formatter.string(from: date)
    }

    private func usageMonthRangeLabel(_ months: [Date]) -> String {
        guard let first = months.first, let last = months.last else { return "—" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: viewModel.appLanguage.localeIdentifier)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.setLocalizedDateFormatFromTemplate("yMMM")
        return "\(formatter.string(from: first)) – \(formatter.string(from: last))"
    }

    private func usageDayLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: viewModel.appLanguage.localeIdentifier)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return formatter.string(from: date)
    }

    private func usageDayAccessibilityLabel(_ day: TokenUsageHeatmapDay) -> String {
        "\(usageDayLabel(day.date)) · \(DisplayFormat.integer(day.tokens)) Token"
    }

    private func scopedQuotaTitle(_ group: CodexScopedQuotaGroup) -> String {
        let normalizedName = group.name.lowercased()
        if normalizedName.contains("codex-spark") {
            return viewModel.t("quota.codeCompletionScope")
        }
        return viewModel.t("quota.modelScope")
    }

    private func accountQuotaTimingText(_ window: CodexQuotaWindow, forecast: QuotaForecast?) -> String {
        let reset = compactQuotaReset(window)
        guard let forecast,
              forecast.state == .lastsUntilReset || forecast.state == .depletesBeforeReset
        else { return reset }
        return "\(reset) · \(forecastHeadline(forecast))"
    }

    private func quotaCycleTitle(_ window: CodexQuotaWindow) -> String {
        let minutes = window.windowMinutes ?? 0
        if minutes == 300 { return viewModel.t("quota.cycleFiveHours") }
        if minutes >= 6 * 24 * 60 { return viewModel.t("quota.cycleWeekly") }
        if minutes > 0, minutes.isMultiple(of: 24 * 60) {
            return viewModel.t("quota.cycleDays", minutes / (24 * 60))
        }
        if minutes > 0, minutes.isMultiple(of: 60) {
            return viewModel.t("quota.cycleHours", minutes / 60)
        }
        return window.title
    }

    private func compactQuotaTitle(_ window: CodexQuotaWindow) -> String {
        if window.id.localizedCaseInsensitiveContains("review") { return viewModel.t("quota.review") }
        let minutes = window.windowMinutes ?? 0
        if minutes >= 6 * 24 * 60 { return viewModel.t("quota.weekly") }
        if minutes == 300 { return viewModel.t("quota.fiveHours") }
        return window.title
    }

    private func compactQuotaReset(_ window: CodexQuotaWindow) -> String {
        guard let resetsAt = window.resetsAt else {
            return viewModel.t("quota.used", Int(window.clampedUsedPercent.rounded()))
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: viewModel.appLanguage.localeIdentifier)
        formatter.unitsStyle = .full
        return formatter.localizedString(for: resetsAt, relativeTo: Date())
    }

    private func quotaAccent(_ window: CodexQuotaWindow) -> Color {
        if window.remainingPercent <= 10 { return PulsePalette.coral }
        if window.remainingPercent <= 25 { return PulsePalette.warning }
        return PulsePalette.accent
    }

    private var liveTaskSwitcher: some View {
        Button {
            activeTaskPage = 0
            page = .activeTasks
        } label: {
            HStack(spacing: 8) {
                MarqueeLabel(text: viewModel.liveContext?.displayTitle ?? viewModel.t("page.activeTasks"),
                             font: .system(size: 13, weight: .regular), color: PulsePalette.ink)
                    .frame(height: 20)
                LivePulseBadge(isFresh: viewModel.liveContext.map { Date().timeIntervalSince($0.updatedAt) < 20 } ?? false)
                PulseIcon(name: "chevron-down").frame(width: 9, height: 9)
                    .foregroundStyle(PulsePalette.muted)
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .glassOutline(radius: 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(PulsePressStyle())
        .accessibilityLabel(viewModel.t("page.activeTasks"))
        .accessibilityIdentifier("Overview.ActiveTasks")
    }

    @ViewBuilder
    private var liveContextCard: some View {
        if let context = viewModel.liveContext {
            LiveContextCard(
                context: context,
                onOpenDetails: { page = .tokenDetails }
            )
        } else {
            HStack(spacing: 12) {
                SignalSkeleton()
                    .frame(width: 76, height: 76)
                VStack(alignment: .leading, spacing: 5) {
                    Text(viewModel.t("live.capture"))
                        .font(.system(size: 14, weight: .semibold, design: .default))
                        .foregroundStyle(PulsePalette.ink)
                    MarqueeLabel(text: viewModel.liveContextErrorMessage ?? viewModel.t("live.waiting"),
                                 font: .system(size: 13, weight: .medium), color: PulsePalette.muted)
                        .frame(height: 18)
                    Button(viewModel.t("action.rediscover")) { viewModel.liveContextTick(forceDiscover: true) }
                        .buttonStyle(PulseTextButtonStyle())
                }
                Spacer()
            }
            .padding(16)
            .frame(minHeight: 116)
        }
    }

    @ViewBuilder
    private var tokenDetails: some View {
        if let context = viewModel.liveContext {
            LiveTokenDetails(
                context: context, apiUSD: viewModel.liveRequestAPIUSD, taskAPIUSD: viewModel.liveTaskAPIUSD,
                showAPIEstimate: viewModel.showAPIEstimate, showRuntimeWindow: viewModel.showRuntimeWindow,
                initialDetailScope: initialDetailScope
            )
        } else {
            inlineFailure(viewModel.t("live.waiting"), title: viewModel.t("live.capture"))
                .padding(.horizontal, 20)
        }
    }

    @ViewBuilder
    private var quotaDetails: some View {
        if let account = viewModel.selectedAccount,
           !account.accountQuotaWindows.isEmpty {
            quotaDetailsContent(account: account)
        } else if viewModel.isScanning {
            accountLoadingSurface
                .padding(12)
                .frame(height: Self.primaryPageContentHeight, alignment: .top)
        } else {
            inlineFailure(
                viewModel.accountErrorMessage ?? viewModel.t("quota.empty"),
                title: viewModel.t("account.unavailable")
            )
            .padding(12)
            .frame(height: Self.primaryPageContentHeight, alignment: .top)
        }
    }

    private func quotaDetailsContent(account: CodexAccountUsageSnapshot) -> some View {
        let windows = Array(account.accountQuotaWindows.prefix(2))
        let selectedWindow = windows.first { $0.id == quotaWindowID } ?? account.preferredMenuWindow ?? windows[0]
        let groups = account.additionalQuotaGroups
        let selectedGroup = groups.first { $0.id == quotaGroupID } ?? groups.first
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                accountContext
                Spacer(minLength: 0)
                if windows.count > 1 {
                    Picker(viewModel.t("quota.accountScope"), selection: Binding(
                        get: { selectedWindow.id }, set: { quotaWindowID = $0 }
                    )) {
                        ForEach(windows) { window in Text(compactQuotaTitle(window)).tag(window.id) }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 160)
                }
            }
            .frame(height: 28)
            .padding(.bottom, 18)
            quotaDetailStatus(window: selectedWindow, forecast: selectedWindow.id == account.preferredMenuWindow?.id ? viewModel.selectedQuotaForecast : nil)
            if let credits = account.credits {
                quotaSectionDivider
                quotaCreditBalanceCard(credits)
            }
            if let window = account.weeklyWindow, let estimate = viewModel.selectedSubscriptionQuotaEstimate {
                quotaSectionDivider
                quotaAllowanceEstimateCard(estimate: estimate, window: window)
            }
            if let selectedGroup {
                quotaSectionDivider
                if groups.count > 1 {
                    Picker(viewModel.t("quota.modelScope"), selection: Binding(
                        get: { selectedGroup.id }, set: { quotaGroupID = $0 }
                    )) {
                        ForEach(groups) { group in Text(scopedQuotaTitle(group)).tag(group.id) }
                    }
                    .labelsHidden()
                }
                scopedQuotaDetail(selectedGroup)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .frame(height: Self.primaryPageContentHeight, alignment: .top)
    }

    private var quotaSectionDivider: some View {
        PulsePalette.divider.frame(height: 1).padding(.vertical, 8)
    }

    private func quotaCreditBalanceCard(_ credits: CodexCreditBalance) -> some View {
        HStack(spacing: 10) {
            PulseIcon(name: "credits").frame(width: 20, height: 20).foregroundStyle(PulsePalette.muted)
            Text(viewModel.t("ledger.credits")).font(.system(size: 14)).foregroundStyle(PulsePalette.ink)
            Spacer(minLength: 8)
            Text(creditText(credits)).font(.system(size: 23, weight: .regular))
                .foregroundStyle(PulsePalette.ink).monospacedDigit()
        }
        .frame(height: 40)
    }

    private func quotaAllowanceEstimateCard(
        estimate: SubscriptionQuotaEstimate,
        window: CodexQuotaWindow
    ) -> some View {
        let remainingUSD = estimate.remainingAPIEquivalentUSD(remainingPercent: window.remainingPercent)
        return VStack(alignment: .leading, spacing: 10) {
            Button { quotaShowsEstimateEvidence.toggle() } label: {
                HStack(spacing: 7) {
                    Text(viewModel.t("quota.apiEquivalentAllowance")).font(.system(size: 14))
                    PulseIcon(name: quotaShowsEstimateEvidence ? "arrow-left" : "info").frame(width: 13, height: 13)
                }
                .foregroundStyle(PulsePalette.ink)
                .frame(height: 22)
            }
            .buttonStyle(PulsePressStyle())
            if quotaShowsEstimateEvidence {
                VStack(alignment: .leading, spacing: 14) {
                    Text(accountPlanEstimateLabel(estimate.tier)).font(.system(size: 15, weight: .medium)).foregroundStyle(PulsePalette.ink)
                    MarqueeLabel(text: viewModel.t("quota.measuredRange", DisplayFormat.quotaUSD(estimate.weeklyAPILowerBoundUSD), DisplayFormat.quotaUSD(estimate.weeklyAPIUpperBoundUSD)),
                                 font: .system(size: 13), color: PulsePalette.muted).frame(height: 20)
                    if let sourceURL = SubscriptionQuotaEstimate.sourceURL {
                        Link(viewModel.t("quota.measurementSource"), destination: sourceURL)
                            .font(.system(size: 13)).foregroundStyle(PulsePalette.accent).buttonStyle(.plain)
                    }
                }
                .frame(height: 105, alignment: .top)
            } else {
                VStack(spacing: 0) {
                    quotaEstimateRow(title: viewModel.t("quota.currentAvailable"), value: DisplayFormat.quotaUSD(remainingUSD))
                    quotaEstimateRow(title: viewModel.t("quota.weeklyFull"), value: DisplayFormat.quotaUSD(estimate.weeklyAPIEquivalentUSD))
                    quotaEstimateRow(title: viewModel.t("quota.monthlyAverage"), value: DisplayFormat.quotaUSD(estimate.monthlyAPIEquivalentUSD))
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func quotaEstimateRow(title: String, value: String) -> some View {
        HStack(spacing: 10) {
            MarqueeLabel(text: title, font: .system(size: 13), color: PulsePalette.muted).frame(height: 20)
            Spacer(minLength: 0)
            Text(value).font(.system(size: 17)).foregroundStyle(PulsePalette.ink).monospacedDigit().fixedSize()
        }
        .frame(maxWidth: .infinity, minHeight: 35)
    }

    private func accountPlanEstimateLabel(_ tier: SubscriptionQuotaEstimate.Tier) -> String {
        switch tier {
        case .plus: "Plus"
        case .pro5x: "Pro 5x"
        case .pro20x: "Pro 20x"
        }
    }

    private func quotaDetailStatus(window: CodexQuotaWindow, forecast: QuotaForecast?) -> some View {
        let remaining = max(0, min(100, window.remainingPercent))
        return VStack(alignment: .leading, spacing: 7) {
            MarqueeLabel(text: viewModel.t("quota.remainingCycle", compactQuotaTitle(window)), font: .system(size: 13), color: PulsePalette.muted)
                .frame(height: 18)
            Text("\(Int(remaining.rounded()))%")
                .font(.system(size: 40, weight: .regular)).foregroundStyle(PulsePalette.ink).monospacedDigit()
            ContextUsageBar(progress: remaining / 100, color: quotaAccent(window)).frame(height: 6)
            MarqueeLabel(text: accountQuotaTimingText(window, forecast: forecast), font: .system(size: 12), color: PulsePalette.muted)
                .frame(height: 18)
        }
        .accessibilityElement(children: .combine)
    }

    private func scopedQuotaDetail(_ group: CodexScopedQuotaGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                PulseIcon(name: "developer").frame(width: 15, height: 15).foregroundStyle(PulsePalette.muted)
                MarqueeLabel(text: scopedQuotaTitle(group), font: .system(size: 14), color: PulsePalette.ink).frame(height: 22)
            }
            ForEach(Array(group.windows.prefix(2))) { window in
                VStack(spacing: 6) {
                    HStack {
                        MarqueeLabel(text: compactQuotaTitle(window), font: .system(size: 13), color: PulsePalette.muted).frame(height: 20)
                        Text("\(Int(window.remainingPercent.rounded()))%")
                            .font(.system(size: 14)).foregroundStyle(PulsePalette.muted).monospacedDigit()
                    }
                    ContextUsageBar(progress: window.remainingPercent / 100, color: quotaAccent(window)).frame(height: 5)
                }
                .padding(.vertical, 3)
            }
        }
    }

    private var tiboGlobalSignalRow: some View {
        Button { page = .tiboSignal } label: {
            HStack(spacing: 10) {
                PulseIcon(name: "forecast").frame(width: 19, height: 19)
                MarqueeLabel(text: viewModel.t("tibo.forecast.title"), font: .system(size: 13), color: PulsePalette.ink)
                    .frame(height: 20)
                VStack(alignment: .trailing, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(viewModel.tiboForecastProbabilityText).font(.system(size: 16, weight: .regular)).monospacedDigit()
                        MarqueeLabel(text: viewModel.tiboForecastProbabilityLevelText,
                                     font: .system(size: 12), color: PulsePalette.muted)
                            .frame(width: 64, height: 17)
                    }
                    ContextUsageBar(progress: viewModel.tiboForecastProgress, color: tiboCycleColor)
                        .frame(width: 104, height: 4)
                }
            }
            .foregroundStyle(PulsePalette.ink)
            .padding(.horizontal, 12)
            .frame(height: 44)
            .glassOutline()
            .contentShape(Rectangle())
        }
        .buttonStyle(PulsePressStyle())
        .help(viewModel.t("tibo.globalHelp"))
        .accessibilityLabel(viewModel.t("tibo.cycle.title"))
        .accessibilityValue(viewModel.tiboCompactStatusText)
    }

    private var tiboCycleColor: Color {
        viewModel.tiboForecast == nil ? PulsePalette.faint : PulsePalette.accent
    }

    private func forecastHeadline(_ forecast: QuotaForecast) -> String {
        switch forecast.state {
        case .collecting:
            return viewModel.t("account.forecastCollecting")
        case .noSustainedConsumption:
            return viewModel.t("account.forecastNoConsumption")
        case .lastsUntilReset:
            return viewModel.t("account.forecastStable")
        case .depletesBeforeReset:
            guard let duration = forecast.estimatedTimeToExhaustion else {
                return viewModel.t("account.forecastCollecting")
            }
            return viewModel.t(
                "account.forecastDepletes",
                DisplayFormat.duration(duration, localeIdentifier: viewModel.appLanguage.localeIdentifier)
            )
        }
    }

    private func forecastEvidence(_ forecast: QuotaForecast) -> String {
        let span = DisplayFormat.duration(
            forecast.observationSpan,
            localeIdentifier: viewModel.appLanguage.localeIdentifier
        )
        let confidence = viewModel.t("confidence.\(forecast.confidence.rawValue)")
        return viewModel.t("account.forecastSamples", forecast.sampleCount, span, confidence)
    }

    private var tiboSignalDetail: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker(viewModel.t("page.tiboSignal"), selection: $tiboShowsEvidence) {
                Text(viewModel.t("tibo.section.forecast")).tag(false)
                Text(viewModel.t("tibo.section.evidence")).tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityIdentifier("Tibo.Sections")

            if tiboShowsEvidence {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        Text(viewModel.tiboForecastJudgementTitle)
                            .font(.system(size: 13, weight: .semibold, design: .default))
                            .foregroundStyle(PulsePalette.ink)
                        Spacer(minLength: 6)
                        Text(viewModel.tiboForecastConfidenceText)
                            .font(.system(size: 12, weight: .semibold, design: .default))
                            .foregroundStyle(PulsePalette.muted)
                    }
                    .padding(.bottom, 8)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(viewModel.tiboSocialEvidenceTitle)
                                .font(.system(size: 12, weight: .semibold, design: .default))
                                .foregroundStyle(PulsePalette.muted)
                            Spacer(minLength: 4)
                            if viewModel.tiboLatestSocialEvidence != nil {
                                Button { viewModel.openLatestTiboSocialEvidence() } label: {
                                    HStack(spacing: 3) {
                                        Text(viewModel.t("tibo.cycle.openPost"))
                                        PulseIcon(name: "arrow-right").frame(width: 7, height: 7)
                                    }
                                }
                                .buttonStyle(PulseTextButtonStyle())
                            }
                        }

                        if let text = viewModel.tiboSocialEvidenceText {
                            Text("“\(text)”")
                                .font(.system(size: 13, weight: .regular, design: .default))
                                .foregroundStyle(PulsePalette.ink)
                                .lineSpacing(2)
                                .lineLimit(6)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            if let meta = viewModel.tiboSocialEvidenceMetaText {
                                MarqueeLabel(text: meta, font: .system(size: 12, weight: .medium), color: PulsePalette.muted)
                                    .frame(height: 16)
                            }
                            Text(viewModel.tiboSocialEvidenceAssessmentText)
                                .foregroundStyle(PulsePalette.accent)
                        }
                        .font(.system(size: 12, weight: .semibold, design: .default))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 8)

                    .padding(.bottom, 6)

                    forecastEvidenceRow(
                        title: viewModel.t("tibo.forecast.probabilityBand"),
                        value: viewModel.tiboForecastProbabilityBandText
                    )
                    PulsePalette.divider.frame(height: 1)
                    forecastEvidenceRow(
                        title: viewModel.t("tibo.forecast.publicSignal"),
                        value: viewModel.tiboForecastPublicSignalText
                    )
                    if let age = viewModel.tiboForecastLastResetAgeText {
                        PulsePalette.divider.frame(height: 1)
                        forecastEvidenceRow(title: viewModel.t("tibo.forecast.lastResetAge"), value: age)
                    }
                    if let cadence = viewModel.tiboForecastCadenceText {
                        PulsePalette.divider.frame(height: 1)
                        forecastEvidenceRow(title: viewModel.t("tibo.forecast.recentCadence"), value: cadence)
                    }
                    if let window = viewModel.tiboForecastCommonWindowText {
                        PulsePalette.divider.frame(height: 1)
                        forecastEvidenceRow(title: viewModel.t("tibo.forecast.commonWindow"), value: window)
                    }
                }
                .padding(13)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(PulsePalette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            } else {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(viewModel.t("tibo.forecast.horizon24h") + " · " + viewModel.t("tibo.forecast.resetProbability"))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(PulsePalette.muted)
                            Text(viewModel.tiboForecastProbabilityText)
                                .font(.system(size: 48, weight: .semibold))
                                .foregroundStyle(PulsePalette.accent)
                                .monospacedDigit()
                            Text(viewModel.tiboForecastProbabilityLevelText)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(PulsePalette.muted)
                        }
                        Spacer()
                        Button { viewModel.tiboSignalTick(force: true) } label: {
                            AnimatedRefreshIcon(isSpinning: viewModel.isTiboSignalRefreshing)
                                .frame(width: 32, height: 32)
                                .background(PulsePalette.surfaceRaised, in: Circle())
                        }
                        .buttonStyle(PulsePressStyle())
                        .disabled(viewModel.isTiboSignalRefreshing)
                        .accessibilityLabel(viewModel.t("tibo.detail.refresh"))
                    }
                    PulsePalette.divider.frame(height: 1)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(viewModel.tiboForecastReferenceLabel)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(PulsePalette.muted)
                        Text(viewModel.tiboForecastReferenceText)
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(PulsePalette.ink)
                            .monospacedDigit()
                        MarqueeLabel(text: viewModel.tiboForecastCountdownText,
                                     font: .system(size: 13, weight: .medium), color: PulsePalette.muted)
                            .frame(height: 18)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(PulsePalette.surface, in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 8) {
                        Text(viewModel.t("tibo.forecast.lastConfirmed"))
                            .font(.system(size: 13, weight: .semibold, design: .default))
                            .foregroundStyle(PulsePalette.ink)
                        Spacer(minLength: 4)
                        if viewModel.tiboCycleHasSource {
                            Button { viewModel.openTiboCycleSource() } label: {
                                HStack(spacing: 4) {
                                    Text(viewModel.t("tibo.cycle.openPost"))
                                    PulseIcon(name: "arrow-right").frame(width: 8, height: 8)
                                }
                            }
                            .buttonStyle(PulseTextButtonStyle())
                        }
                    }

                    Text(viewModel.tiboForecastLastConfirmedText)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(PulsePalette.accent)
                        .monospacedDigit()

                    if let reason = viewModel.tiboForecastResetReasonText {
                        Text(reason)
                            .font(.system(size: 13, weight: .regular, design: .default))
                            .foregroundStyle(PulsePalette.ink)
                            .lineSpacing(3)
                            .lineLimit(4)
                    }
                }
                .padding(13)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(PulsePalette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                Button { tiboShowsEvidence = true } label: {
                    HStack {
                        Text(viewModel.tiboForecastJudgementTitle)
                        Spacer()
                        PulseIcon(name: "arrow-right").frame(width: 12, height: 12)
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(PulsePalette.accent)
                    .padding(14)
                    .background(PulsePalette.surface, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(PulsePressStyle())
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 12)
    }

    private func forecastEvidenceRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(PulsePalette.muted)
            MarqueeLabel(text: value, font: .system(size: 14, weight: .medium), color: PulsePalette.ink)
                .frame(height: 18)
        }
        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func ledgerSurface(_ account: CodexAccountUsageSnapshot) -> some View {
        HStack(spacing: 0) {
            if let credits = account.credits {
                compactLedgerCell(
                    icon: "credits",
                    color: PulsePalette.ink,
                    title: viewModel.t("ledger.credits"),
                    value: creditText(credits),
                    action: nil
                )
                PulsePalette.divider.frame(width: 1).padding(.vertical, 9)
            }

            compactLedgerCell(
                icon: "ledger",
                color: PulsePalette.ink,
                title: viewModel.t("ledger.local"),
                value: viewModel.isScanning && viewModel.snapshot.records.isEmpty
                    ? viewModel.t("ledger.indexing")
                    : DisplayFormat.tokens(viewModel.localConversationTotalUsage.totalTokens),
                action: { page = .sessions }
            )
            .help(viewModel.t("local.exactHelp"))
        }
        .padding(.top, 3)
        .frame(height: 52)
        .overlay(alignment: .top) { PulsePalette.divider.frame(height: 1) }
    }

    private func compactLedgerCell(
        icon: String,
        color: Color,
        title: String,
        value: String,
        action: (() -> Void)?
    ) -> some View {
        Button {
            action?()
        } label: {
            HStack(spacing: 7) {
                PulseIcon(name: icon)
                    .frame(width: 13, height: 13)
                    .foregroundStyle(color)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold, design: .default))
                        .foregroundStyle(PulsePalette.muted)
                        .lineLimit(1)
                    Text(value)
                        .font(.system(size: 12, weight: .semibold, design: .default))
                        .foregroundStyle(PulsePalette.ink)
                        .monospacedDigit()
                        .lineLimit(1)
                }
                Spacer(minLength: 2)
                if action != nil {
                    PulseIcon(name: "arrow-right")
                        .frame(width: 8, height: 8)
                        .foregroundStyle(PulsePalette.faint)
                }
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(action == nil ? PulsePressStyle(enabled: false) : PulsePressStyle())
        .disabled(action == nil)
    }

    private var accountLoadingSurface: some View {
        HStack(spacing: 12) {
            SignalSkeleton().frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(viewModel.t("account.syncing"))
                    .font(.system(size: 13, weight: .semibold, design: .default))
                    .foregroundStyle(PulsePalette.ink)
                Text(viewModel.t("account.reading"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(PulsePalette.muted)
            }
            Spacer()
        }
        .padding(13)
        .background(PulsePalette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var sessions: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                PulseIcon(name: "search").frame(width: 13, height: 13)
                    .foregroundStyle(PulsePalette.faint)
                TextField(viewModel.t("sessions.search"), text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(PulsePalette.ink)
            }
            .padding(.horizontal, 16)
            .frame(height: 36)
            .background(PulsePalette.surfaceRaised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.horizontal, 16)

            MarqueeLabel(text: viewModel.t("sessions.notice"), font: .system(size: 12, weight: .medium), color: PulsePalette.muted)
                .frame(height: 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)

            VStack(spacing: 0) {
                if visibleSessions.isEmpty {
                    Text(viewModel.t("sessions.empty"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(PulsePalette.muted)
                        .frame(maxWidth: .infinity, minHeight: 72)
                } else {
                    ForEach(Array(visibleSessions.enumerated()), id: \.element.id) { index, session in
                        if index > 0 {
                            PulsePalette.divider.frame(height: 1).padding(.leading, 52)
                        }
                        PulseSessionRow(
                            session: session,
                            title: viewModel.sessionTitle(session),
                            subtitle: viewModel.sessionSubtitle(session)
                        )
                    }
                }
            }
            .background(PulsePalette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 16)

            Spacer(minLength: 0)

            if sessionPageCount > 1 {
                sessionPager
            }
        }
        .padding(.bottom, 12)
        .frame(height: Self.primaryPageContentHeight, alignment: .top)
    }

    private var activeTaskPageCount: Int {
        max(1, Int(ceil(Double(viewModel.activeTaskCount) / Double(activeTasksPerPage))))
    }

    private var visibleActiveTasks: [CodexLiveContextSnapshot] {
        let safePage = min(activeTaskPage, max(0, activeTaskPageCount - 1))
        let start = safePage * activeTasksPerPage
        guard start < viewModel.activeLiveContexts.count else { return [] }
        let end = min(start + activeTasksPerPage, viewModel.activeLiveContexts.count)
        return Array(viewModel.activeLiveContexts[start..<end])
    }

    private var activeTasks: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Text("\(viewModel.t("overview.tab.task")) \(viewModel.activeTaskCount)")
                Spacer(minLength: 8)
                Text(viewModel.t("live.contextInput"))
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(PulsePalette.muted)
            .padding(.horizontal, 4)
            .frame(height: 22)

            if visibleActiveTasks.isEmpty {
                Text(viewModel.t("activeTasks.empty"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(PulsePalette.muted)
                    .frame(maxWidth: .infinity, minHeight: 78)
                    .background(PulsePalette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(visibleActiveTasks.enumerated()), id: \.element.id) { offset, context in
                        let selected = context.id == viewModel.liveContext?.id
                        let taskNumber = activeTaskPage * activeTasksPerPage + offset + 1
                        if offset > 0 {
                            PulsePalette.divider.frame(height: 1).padding(.leading, 46)
                        }
                        Button {
                            viewModel.selectLiveContext(context.id)
                            page = .overview
                        } label: {
                            HStack(spacing: 9) {
                                Text("\(taskNumber)")
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(selected ? PulsePalette.accent : PulsePalette.muted)
                                    .frame(width: 25, height: 25)
                                    .background(
                                        selected ? PulsePalette.accent.opacity(0.12) : PulsePalette.surfaceRaised,
                                        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    )

                                VStack(alignment: .leading, spacing: 1) {
                                    MarqueeLabel(
                                        text: context.displayTitle,
                                        font: .system(size: 13, weight: .semibold, design: .default),
                                        color: PulsePalette.ink
                                    )
                                    MarqueeLabel(
                                        text: activeTaskSubtitle(context),
                                        font: .system(size: 12, weight: .medium, design: .default),
                                        color: PulsePalette.muted
                                    )
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)

                                Text(DisplayFormat.tokens(context.contextInputTokens))
                                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(selected ? PulsePalette.accent : PulsePalette.ink)
                                    .monospacedDigit()
                                    .frame(width: 62, alignment: .trailing)

                                PulseIcon(name: "arrow-right")
                                    .frame(width: 8, height: 8)
                                    .foregroundStyle(PulsePalette.faint)
                            }
                            .padding(.horizontal, 10)
                            .frame(height: 56)
                            .background(selected ? PulsePalette.accent.opacity(0.07) : Color.clear)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PulsePressStyle())
                        .accessibilityLabel("\(context.displayTitle), \(viewModel.t("metric.context")) \(DisplayFormat.tokens(context.contextInputTokens))")
                    }
                }
                .background(PulsePalette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            Spacer(minLength: 0)

            if activeTaskPageCount > 1 {
                HStack(spacing: 12) {
                    Button {
                        activeTaskPage = max(0, activeTaskPage - 1)
                    } label: {
                        PulseIcon(name: "arrow-left").frame(width: 12, height: 12)
                    }
                    .disabled(activeTaskPage == 0)

                    Text("\(activeTaskPage + 1) / \(activeTaskPageCount)")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(PulsePalette.muted)

                    Button {
                        activeTaskPage = min(activeTaskPageCount - 1, activeTaskPage + 1)
                    } label: {
                        PulseIcon(name: "arrow-right").frame(width: 12, height: 12)
                    }
                    .disabled(activeTaskPage >= activeTaskPageCount - 1)
                }
                .buttonStyle(PulseTextButtonStyle())
                .frame(height: 28)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .frame(height: Self.primaryPageContentHeight, alignment: .top)
    }

    private func activeTaskSubtitle(_ context: CodexLiveContextSnapshot) -> String {
        var parts: [String] = []
        if context.displayTitle != context.projectName {
            parts.append(context.projectName)
        }
        parts.append(context.model)
        if let reasoningEffort = context.reasoningEffort, !reasoningEffort.isEmpty {
            parts.append(reasoningEffort)
        }
        return parts.joined(separator: " · ")
    }

    private var moreActions: some View {
        VStack(spacing: 12) {
            VStack(spacing: 0) {
                moreActionButton(
                    title: viewModel.t("page.tiboSignal"),
                    icon: "forecast",
                    showsChevron: true
                ) { page = .tiboSignal }
                settingsDivider
                moreActionButton(
                    title: viewModel.t("page.about"),
                    icon: "info",
                    showsChevron: true
                ) { page = .about }
            }
            .background(PulsePalette.surface, in: RoundedRectangle(cornerRadius: 12))
            VStack(spacing: 0) {
                moreActionButton(title: viewModel.t("action.exportCSV"), icon: "export", action: viewModel.exportCSV)
                settingsDivider
                moreActionButton(title: viewModel.t("action.exportJSON"), icon: "export", action: viewModel.exportJSON)
            }
            .background(PulsePalette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            Spacer(minLength: 0)
            moreActionButton(title: viewModel.t("action.quit"), icon: "power", destructive: true) {
                NSApp.terminate(nil)
            }
            .background(PulsePalette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .frame(height: Self.primaryPageContentHeight, alignment: .top)
    }

    private func moreActionButton(
        title: String,
        icon: String,
        destructive: Bool = false,
        showsChevron: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 11) {
                PulseIcon(name: icon)
                    .frame(width: 15, height: 15)
                    .foregroundStyle(destructive ? PulsePalette.coral : PulsePalette.accent)
                    .frame(width: 30, height: 30)
                    .background(
                        (destructive ? PulsePalette.coral : PulsePalette.accent).opacity(0.10),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(destructive ? PulsePalette.coral : PulsePalette.ink)
                Spacer(minLength: 8)
                if showsChevron {
                    PulseIcon(name: "arrow-right")
                        .frame(width: 9, height: 9)
                        .foregroundStyle(PulsePalette.faint)
                }
            }
            .padding(.horizontal, 11)
            .frame(height: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(PulsePressStyle())
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 8) {
            consolePanelStrip
            Group {
                switch consolePanel {
                case .appearance: appearanceConsole
                case .live: liveConsole
                case .account: accountConsole
                case .data: dataConsole
                }
            }
            .id(consolePanel)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 9)
        .frame(height: Self.primaryPageContentHeight, alignment: .top)
    }

    private var consolePanelStrip: some View {
        Picker(viewModel.t("page.console"), selection: $consolePanel) {
            ForEach(ConsolePanel.allCases) { panel in
                Text(consolePanelTitle(panel)).tag(panel)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(height: 38)
        .accessibilityIdentifier("Settings.Sections")
    }

    private func consolePanelTitle(_ panel: ConsolePanel) -> String {
        switch panel {
        case .appearance: viewModel.t("settings.tab.appearance")
        case .live: viewModel.t("settings.tab.live")
        case .account: viewModel.t("settings.tab.account")
        case .data: viewModel.t("settings.tab.data")
        }
    }

    private var appearanceConsole: some View {
        VStack(spacing: 14) {
            PulseSettingsGroup(title: viewModel.t("console.appearance")) {
                themeSelectionRow
                settingsDivider
                settingsMenuRow(title: viewModel.t("console.language"), value: viewModel.languageTitle(viewModel.appLanguage)) {
                    ForEach(AppLanguage.allCases) { language in
                        Button(viewModel.languageTitle(language)) {
                            viewModel.appLanguage = language
                            viewModel.persistPreferences()
                        }
                    }
                }
            }

            PulseSettingsGroup(title: viewModel.t("console.menu")) {
                settingsMenuRow(title: viewModel.t("console.metric"), value: viewModel.menuMetricTitle(viewModel.menuBarMetric)) {
                    ForEach(MenuBarMetric.allCases) { metric in
                        Button(viewModel.menuMetricTitle(metric)) {
                            viewModel.menuBarMetric = metric
                            viewModel.persistPreferences()
                        }
                    }
                }
                settingsDivider
                SettingsToggleRow(title: viewModel.t("console.taskCount"), isOn: $viewModel.showConcurrentTaskCount) {
                    viewModel.persistPreferences()
                }
                settingsDivider
                SettingsActionToggleRow(
                    title: viewModel.t("console.launchAtLogin"),
                    isOn: viewModel.launchAtLoginEnabled,
                    changed: viewModel.setLaunchAtLogin
                )
                if viewModel.launchAtLoginRequiresApproval || viewModel.launchAtLoginErrorMessage != nil {
                    settingsDivider
                    HStack(spacing: 8) {
                        Text(
                            viewModel.launchAtLoginErrorMessage
                                ?? viewModel.t("console.launchAtLoginApproval")
                        )
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(PulsePalette.muted)
                        .lineLimit(1)
                        Spacer(minLength: 4)
                        if viewModel.launchAtLoginRequiresApproval {
                            Button(viewModel.t("console.openLoginItems"), action: viewModel.openLoginItemsSettings)
                                .buttonStyle(PulseTextButtonStyle())
                        }
                    }
                    .padding(.horizontal, 13)
                    .frame(height: 34)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var liveConsole: some View {
        VStack(spacing: 14) {
            PulseSettingsGroup(title: viewModel.t("console.live")) {
                settingsMenuRow(title: viewModel.t("console.liveRefresh"), value: viewModel.t("console.seconds", viewModel.liveRefreshRate.rawValue)) {
                    ForEach(LiveRefreshRate.allCases) { rate in
                        Button(viewModel.t("console.seconds", rate.rawValue)) {
                            viewModel.liveRefreshRate = rate; viewModel.persistPreferences()
                        }
                    }
                }
                settingsDivider
                settingsMenuRow(title: viewModel.t("console.discovery"), value: viewModel.t("console.seconds", viewModel.discoveryRate.rawValue)) {
                    ForEach(DiscoveryRate.allCases) { rate in
                        Button(viewModel.t("console.seconds", rate.rawValue)) {
                            viewModel.discoveryRate = rate; viewModel.persistPreferences()
                        }
                    }
                }
                settingsDivider
                settingsMenuRow(title: viewModel.t("console.taskLimit"), value: viewModel.t("console.tasks", viewModel.liveTaskLimit.rawValue)) {
                    ForEach(LiveTaskLimit.allCases) { limit in
                        Button(viewModel.t("console.tasks", limit.rawValue)) {
                            viewModel.liveTaskLimit = limit; viewModel.persistPreferences(); viewModel.liveContextTick(forceDiscover: true)
                        }
                    }
                }
            }

            PulseSettingsGroup(title: viewModel.t("console.details")) {
                SettingsToggleRow(title: viewModel.t("console.pricing"), isOn: $viewModel.showAPIEstimate) { viewModel.persistPreferences() }
                settingsDivider
                SettingsToggleRow(title: viewModel.t("console.runtime"), isOn: $viewModel.showRuntimeWindow) { viewModel.persistPreferences() }
                settingsDivider
                SettingsToggleRow(title: viewModel.t("console.tiboMonitoring"), isOn: $viewModel.tiboMonitoringEnabled) {
                    viewModel.tiboMonitoringChanged()
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var accountConsole: some View {
        VStack(spacing: 14) {
            PulseSettingsGroup(title: viewModel.t("console.accounts")) {
                if viewModel.accountSnapshots.isEmpty {
                    SettingsValueRow(
                        title: viewModel.t("console.quickSwitch"),
                        value: viewModel.t("console.notRead")
                    )
                } else {
                    ForEach(Array(viewModel.accountSnapshots.prefix(3).enumerated()), id: \.element.id) { index, account in
                        if index > 0 { settingsDivider }
                        CockpitAccountRow(
                            name: viewModel.accountName(account),
                            plan: account.planDisplayName,
                            isMonitored: account.id == viewModel.activeAccountID,
                            isCodexLogin: viewModel.accountIsCodexLogin(account),
                            isBusy: viewModel.isAccountSwitching,
                            monitorTitle: viewModel.t("account.monitorShort"),
                            activateTitle: viewModel.t("account.switchShort"),
                            onMonitor: { viewModel.switchAccount(to: account, mode: .monitorOnly) },
                            onActivate: { viewModel.switchAccount(to: account, mode: .activateCodex) }
                        )
                    }
                    if viewModel.accountSnapshots.count > 3 {
                        settingsDivider
                        settingsMenuRow(
                            title: viewModel.t("account.moreAccounts"),
                            value: "+\(viewModel.accountSnapshots.count - 3)"
                        ) {
                            ForEach(viewModel.accountSnapshots.dropFirst(3)) { account in
                                Menu(viewModel.accountName(account)) {
                                    Button(viewModel.t("account.monitorOnly")) {
                                        viewModel.switchAccount(to: account, mode: .monitorOnly)
                                    }
                                    Button(viewModel.t("account.activateCodex")) {
                                        viewModel.switchAccount(to: account, mode: .activateCodex)
                                    }
                                }
                            }
                        }
                    }
                }
                settingsDivider
                HStack(spacing: 8) {
                    Menu {
                        accountAddActions
                    } label: {
                        Text(viewModel.t("action.addAccount"))
                            .font(.system(size: 12, weight: .semibold, design: .default))
                            .foregroundStyle(PulsePalette.accent)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    Spacer()
                    Text(viewModel.t("console.saved", viewModel.accountSnapshots.count))
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(PulsePalette.muted)
                    if viewModel.accountSnapshots.count > 1 {
                        Button(viewModel.t("action.remove"), action: viewModel.forgetSelectedAccount)
                            .buttonStyle(PulseTextButtonStyle(color: PulsePalette.coral))
                    }
                }
                .padding(.horizontal, 13).frame(height: 36)
                if viewModel.hasPendingOAuth || viewModel.accountActionMessage != nil {
                    settingsDivider
                    HStack(spacing: 8) {
                        Circle()
                            .fill(viewModel.hasPendingOAuth ? PulsePalette.warning : PulsePalette.lime)
                            .frame(width: 6, height: 6)
                        Text(viewModel.accountActionMessage ?? viewModel.t("account.oauthPending"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(PulsePalette.muted)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        if viewModel.hasPendingOAuth {
                            Button(viewModel.t("account.oauthCheck")) { viewModel.checkPendingOAuth() }
                                .buttonStyle(PulseTextButtonStyle())
                        }
                    }
                    .padding(.horizontal, 13)
                    .frame(height: 34)
                }
            }

            PulseSettingsGroup(title: viewModel.t("console.accountSync")) {
                SettingsToggleRow(title: viewModel.t("account.restartAfterSwitch"), isOn: $viewModel.restartCodexAfterSwitch) { viewModel.persistPreferences() }
                settingsDivider
                SettingsToggleRow(title: viewModel.t("console.autoSync"), isOn: $viewModel.autoRefresh) { viewModel.persistPreferences() }
                settingsDivider
                settingsMenuRow(title: viewModel.t("console.accountSync"), value: viewModel.t("console.minutes", viewModel.accountRefreshRate.rawValue / 60)) {
                    ForEach(AccountRefreshRate.allCases) { rate in
                        Button(viewModel.t("console.minutes", rate.rawValue / 60)) {
                            viewModel.accountRefreshRate = rate; viewModel.persistPreferences()
                        }
                    }
                }
                settingsDivider
                SettingsToggleRow(title: viewModel.t("console.privacy"), isOn: $viewModel.privacyMode) { viewModel.persistPreferences() }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var dataConsole: some View {
        VStack(spacing: 14) {
            PulseSettingsGroup(title: viewModel.t("console.data")) {
                Button(action: viewModel.chooseCodexHome) {
                    SettingsValueRow(title: viewModel.t("console.home"), value: URL(fileURLWithPath: viewModel.codexHomePath).lastPathComponent, showsChevron: true)
                }.buttonStyle(PulsePressStyle())
                settingsDivider
                SettingsToggleRow(title: viewModel.t("console.archived"), isOn: $viewModel.includeArchived) { viewModel.refresh() }
                settingsDivider
                SettingsValueRow(title: viewModel.t("console.files"), value: "\(viewModel.snapshot.fileCount)")
                settingsDivider
                Button(viewModel.t("action.rebuild"), action: viewModel.rebuildIndex)
                    .buttonStyle(PulseTextButtonStyle()).padding(.horizontal, 13).frame(height: 38, alignment: .leading)
            }

            PulseSettingsGroup(title: viewModel.t("console.about")) {
                Button { page = .about } label: {
                    SettingsValueRow(title: viewModel.t("page.about"), value: appVersionDisplay, showsChevron: true)
                }.buttonStyle(PulsePressStyle())
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var tokenLogin: some View {
        let inspection = viewModel.inspectCredentialText(credentialText)
        return VStack(spacing: 8) {
            Text("Token / JSON")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(PulsePalette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(PulsePalette.surface)
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(
                                inspection.isValid ? PulsePalette.lime.opacity(0.48) : PulsePalette.divider,
                                lineWidth: 1
                            )
                    }
                if credentialText.isEmpty {
                    Text("Token / JSON")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(PulsePalette.faint)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                }
                PrivateCredentialEditor(text: $credentialText)
                    .padding(7)
            }
            .frame(height: 210)

            HStack(spacing: 8) {
                Circle()
                    .fill(credentialText.isEmpty ? PulsePalette.faint : (inspection.isValid ? PulsePalette.lime : PulsePalette.coral))
                    .frame(width: 6, height: 6)
                Text(inspection.message)
                    .font(.system(size: 12, weight: .semibold, design: .default))
                    .foregroundStyle(inspection.isValid ? PulsePalette.ink : PulsePalette.muted)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Button(viewModel.t("account.tokenPaste")) {
                    credentialText = NSPasteboard.general.string(forType: .string) ?? ""
                }
                .buttonStyle(PulseTextButtonStyle())
                if !credentialText.isEmpty {
                    Button(viewModel.t("action.clear")) { credentialText = "" }
                        .buttonStyle(PulseTextButtonStyle(color: PulsePalette.coral))
                }
            }
            .frame(height: 24)

            VStack(alignment: .leading, spacing: 6) {
                Text(viewModel.t("account.tokenModeTitle"))
                    .font(.system(size: 12, weight: .semibold, design: .default))
                    .foregroundStyle(PulsePalette.muted)
                VStack(spacing: 8) {
                    tokenModeButton(
                        .monitorOnly,
                        title: viewModel.t("account.tokenModeMonitor"),
                        subtitle: viewModel.t("account.monitorHelp"),
                        color: PulsePalette.muted
                    )
                    tokenModeButton(
                        .activateCodex,
                        title: viewModel.t("account.tokenModeActivate"),
                        subtitle: viewModel.t("account.activateHelp"),
                        color: PulsePalette.accent
                    )
                }
            }

            HStack(spacing: 8) {
                PulseIcon(name: "check")
                    .frame(width: 12, height: 12)
                MarqueeLabel(text: viewModel.t("account.tokenPrivacy"), font: .system(size: 12, weight: .medium), color: PulsePalette.muted)
                    .frame(height: 18)
                Spacer(minLength: 0)
            }
            .foregroundStyle(PulsePalette.muted)

            Button {
                if viewModel.importCredentialText(
                    credentialText,
                    activateCodex: credentialMode == .activateCodex
                ) {
                    credentialText = ""
                    consolePanel = .account
                    page = .settings
                }
            } label: {
                HStack(spacing: 8) {
                    PulseIcon(name: "account").frame(width: 15, height: 15)
                    Text(
                        credentialMode == .activateCodex
                            ? viewModel.t("account.tokenSubmit")
                            : viewModel.t("account.tokenSave")
                    )
                }
                .font(.system(size: 13, weight: .semibold, design: .default))
                .foregroundStyle(strongSelectionInk)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(PulsePalette.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(PulsePressStyle())
            .disabled(!inspection.isValid || viewModel.isAccountSwitching)
            .opacity(inspection.isValid ? 1 : 0.48)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    private func tokenModeButton(
        _ mode: AccountSwitchMode,
        title: String,
        subtitle: String,
        color: Color
    ) -> some View {
        let selected = credentialMode == mode
        return Button { credentialMode = mode } label: {
            HStack(spacing: 8) {
                ZStack {
                    Circle().fill(selected ? color : PulsePalette.surfaceRaised)
                    if selected {
                        PulseIcon(name: "check")
                            .frame(width: 9, height: 9)
                            .foregroundStyle(strongSelectionInk)
                    }
                }
                .frame(width: 19, height: 19)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold, design: .default))
                        .foregroundStyle(PulsePalette.ink)
                    MarqueeLabel(text: subtitle, font: .system(size: 12, weight: .regular), color: PulsePalette.muted)
                        .frame(height: 16)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, minHeight: 60)
            .background(
                selected ? color.opacity(0.12) : PulsePalette.surface,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(selected ? color.opacity(0.42) : PulsePalette.divider, lineWidth: 1)
            }
        }
        .buttonStyle(PulsePressStyle())
        .help(subtitle)
    }

    private var settingsDivider: some View {
        PulsePalette.divider.frame(height: 1).padding(.leading, 13)
    }

    private var themeSelectionRow: some View {
        HStack(spacing: 10) {
            Text(viewModel.t("console.theme"))
                .foregroundStyle(PulsePalette.ink)
            Spacer(minLength: 8)
            HStack(spacing: 3) {
                ForEach(AppTheme.allCases) { theme in
                    let selected = viewModel.appTheme == theme
                    Button {
                        viewModel.appTheme = theme
                        viewModel.persistPreferences()
                    } label: {
                        Text(viewModel.themeTitle(theme))
                            .font(.system(size: 12, weight: .semibold, design: .default))
                            .foregroundStyle(selected ? strongSelectionInk : PulsePalette.muted)
                            .padding(.horizontal, 9)
                            .frame(height: 27)
                            .background(
                                selected ? strongSelection : Color.clear,
                                in: Capsule()
                            )
                    }
                    .buttonStyle(PulsePressStyle())
                }
            }
            .padding(3)
            .fixedSize()
            .background(PulsePalette.surfaceRaised, in: Capsule())
            .overlay {
                Capsule().stroke(PulsePalette.divider, lineWidth: 1)
            }
        }
        .padding(.horizontal, 13)
        .frame(height: 42)
    }

    @ViewBuilder
    private var accountAddActions: some View {
        Button(viewModel.t("account.tokenLogin")) { page = .tokenLogin }
        Divider()
        Button(viewModel.t("account.oauth")) { viewModel.beginOAuthLogin() }
        Button(viewModel.t("account.importJSON")) { viewModel.importAuthJSON() }
        Button(viewModel.t("account.importHome")) { viewModel.chooseCodexHome() }
    }

    private func settingsMenuRow<Content: View>(title: String, value: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            MarqueeLabel(text: title, font: .system(size: 13, weight: .medium), color: PulsePalette.ink)
                .frame(height: 18)
            Menu(content: content) {
                Text(value)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(PulsePalette.accent)
            }
            .menuStyle(.borderlessButton)
            .frame(width: Self.contentWidth - 58, height: 20, alignment: .leading)
            .help(value)
            .accessibilityLabel(title)
        }
        .padding(.horizontal, 13)
        .frame(height: 60)
        .contentShape(Rectangle())
    }

    private var about: some View {
        VStack(spacing: 8) {
            VStack(spacing: 10) {
                Image("CodexLensAppIcon")
                    .resizable().scaledToFit()
                    .frame(width: 76, height: 76)
                    .accessibilityHidden(true)
                Text(viewModel.t("developer.product"))
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(PulsePalette.ink)
                HStack(spacing: 12) {
                    Text(viewModel.t("about.versionValue", appVersionNumber))
                    Text(viewModel.t("about.buildValue", appBuildNumber))
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(PulsePalette.muted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)

            VStack(spacing: 0) {
                aboutNavigationRow(title: viewModel.t("update.check"), value: updateStatusShortText, icon: "sync") { page = .updates }
                settingsDivider
                aboutNavigationRow(title: viewModel.t("about.website"), value: viewModel.t("about.websitePlaceholder"), icon: "external-link") { openURL(Self.websiteURL) }
                settingsDivider
                aboutNavigationRow(title: viewModel.t("about.source"), value: "GitHub", icon: "developer") { openURL(Self.sourceURL) }
            }
            .background(PulsePalette.surface, in: RoundedRectangle(cornerRadius: 12))

            VStack(spacing: 0) {
                ForEach(LegalDocument.allCases) { document in
                    if document != LegalDocument.allCases.first { settingsDivider }
                    aboutNavigationRow(title: viewModel.t(document.titleKey), value: "", icon: legalIcon(document)) {
                        legalDocument = document
                        legalPage = 0
                        page = .legal
                    }
                }
            }
            .background(PulsePalette.surface, in: RoundedRectangle(cornerRadius: 12))

            Spacer(minLength: 0)
            HStack(spacing: 8) {
                Image("DeveloperAvatar")
                    .resizable().scaledToFill()
                    .frame(width: 26, height: 26)
                    .clipShape(Circle())
                Text("Zijiu522")
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Text(viewModel.t("developer.role"))
                    .font(.system(size: 12))
            }
            .foregroundStyle(PulsePalette.muted)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .frame(height: Self.primaryPageContentHeight, alignment: .top)
    }

    private var updates: some View {
        VStack(spacing: 8) {
            VStack(spacing: 7) {
                ZStack {
                    Circle()
                        .fill(updateStatusColor.opacity(0.12))
                    PulseIcon(name: updateStatusIcon)
                        .frame(width: 20, height: 20)
                        .foregroundStyle(updateStatusColor)
                }
                .frame(width: 48, height: 48)

                Text(updateStatusTitle)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(PulsePalette.ink)
                Text(appVersionDisplay)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(PulsePalette.muted)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, minHeight: 102)

            Button(action: updateService.checkForUpdates) {
                HStack(spacing: 8) {
                    AnimatedRefreshIcon(
                        isSpinning: updateService.phase == .checking,
                        idleColor: strongSelectionInk,
                        spinningColor: strongSelectionInk
                    )
                    Text(viewModel.t("update.checkNow"))
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(strongSelectionInk)
                .frame(maxWidth: .infinity, minHeight: 42)
                .background(strongSelection, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            .buttonStyle(PulsePressStyle())
            .disabled(!updateService.canCheckForUpdates || updateService.phase == .checking)
            .opacity(updateService.canCheckForUpdates ? 1 : 0.55)

            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    Text(viewModel.t("update.releaseNotes"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(PulsePalette.ink)
                    Spacer(minLength: 8)
                    versionBadge(appVersionDisplay)
                }

                Rectangle()
                    .fill(PulsePalette.divider)
                    .frame(height: 1)

                VStack(alignment: .leading, spacing: 7) {
                    ForEach(currentReleaseNoteKeys, id: \.self) { key in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(PulsePalette.accent)
                                .frame(width: 4, height: 4)
                            MarqueeLabel(text: viewModel.t(key), font: .system(size: 13, weight: .medium), color: PulsePalette.ink)
                                .frame(height: 22)
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
            .padding(12)
            .background(PulsePalette.surface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))

            PulseSettingsGroup(title: viewModel.t("update.automatic")) {
                SettingsToggleRow(
                    title: viewModel.t("update.automaticChecks"),
                    isOn: Binding(
                        get: { updateService.automaticallyChecksForUpdates },
                        set: updateService.setAutomaticallyChecksForUpdates
                    )
                ) {}
                settingsDivider
                SettingsToggleRow(
                    title: viewModel.t("update.automaticDownloads"),
                    isOn: Binding(
                        get: { updateService.automaticallyDownloadsUpdates },
                        set: updateService.setAutomaticallyDownloadsUpdates
                    )
                ) {}
                    .disabled(!updateService.automaticallyChecksForUpdates)
            }

            HStack(spacing: 8) {
                Text(viewModel.t("update.lastChecked"))
                    .foregroundStyle(PulsePalette.muted)
                Spacer(minLength: 8)
                Text(lastUpdateCheckText)
                    .foregroundStyle(PulsePalette.ink)
            }
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 13)
            .frame(height: 42)
            .background(PulsePalette.surface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))

            Text(viewModel.t("update.installOnQuit"))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(PulsePalette.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .frame(height: Self.primaryPageContentHeight, alignment: .top)
    }

    private var legalViewer: some View {
        VStack(spacing: 10) {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)],
                spacing: 6
            ) {
                ForEach(LegalDocument.allCases) { document in
                    let selected = legalDocument == document
                    Button {
                        legalDocument = document
                    } label: {
                        Text(viewModel.t(document.titleKey))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(selected ? strongSelectionInk : PulsePalette.ink)
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .background(
                                selected ? strongSelection : PulsePalette.surface,
                                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                            )
                    }
                    .buttonStyle(PulsePressStyle())
                }
            }

            Text(viewModel.t(legalDocument.pageKeys[legalPage]))
                .font(.system(size: 12.5, weight: .regular))
                .foregroundStyle(PulsePalette.ink)
                .lineSpacing(4)
                .lineLimit(nil)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(15)
                .background(PulsePalette.surface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .stroke(PulsePalette.divider.opacity(0.72), lineWidth: 1)
                }

            HStack(spacing: 14) {
                Button {
                    legalPage = max(0, legalPage - 1)
                } label: {
                    PulseIcon(name: "arrow-left").frame(width: 12, height: 12)
                }
                .disabled(legalPage == 0)

                Text("\(legalPage + 1) / \(legalDocument.pageKeys.count)")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(PulsePalette.muted)

                Button {
                    legalPage = min(legalDocument.pageKeys.count - 1, legalPage + 1)
                } label: {
                    PulseIcon(name: "arrow-right").frame(width: 12, height: 12)
                }
                .disabled(legalPage >= legalDocument.pageKeys.count - 1)
            }
            .buttonStyle(PulseTextButtonStyle())
            .frame(height: 28)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .frame(height: Self.primaryPageContentHeight, alignment: .top)
    }

    private func versionBadge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .foregroundStyle(PulsePalette.muted)
            .padding(.horizontal, 7)
            .frame(height: 21)
            .background(PulsePalette.surfaceRaised, in: Capsule())
    }

    private func aboutNavigationRow(
        title: String,
        value: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                PulseIcon(name: icon)
                    .frame(width: 14, height: 14)
                    .foregroundStyle(PulsePalette.accent)
                    .frame(width: 28, height: 28)
                    .background(PulsePalette.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(PulsePalette.ink)
                Spacer(minLength: 8)
                Text(value)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(PulsePalette.muted)
                PulseIcon(name: "arrow-right")
                    .frame(width: 8, height: 8)
                    .foregroundStyle(PulsePalette.faint)
            }
            .padding(.horizontal, 11)
            .frame(height: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(PulsePressStyle())
    }

    private func legalIcon(_ document: LegalDocument) -> String {
        switch document {
        case .userAgreement: "document"
        case .privacy: "shield"
        case .openSource: "developer"
        case .disclaimer: "warning"
        }
    }

    private var updateStatusTitle: String {
        switch updateService.phase {
        case .idle: viewModel.t("update.ready")
        case .checking: viewModel.t("update.checking")
        case .current: viewModel.t("update.current")
        case let .available(version): viewModel.t("update.available", version)
        case .failed: viewModel.t("update.failed")
        }
    }

    private var updateStatusShortText: String {
        switch updateService.phase {
        case .idle: viewModel.t("update.readyShort")
        case .checking: viewModel.t("update.checkingShort")
        case .current: viewModel.t("update.currentShort")
        case .available: viewModel.t("update.availableShort")
        case .failed: viewModel.t("update.failedShort")
        }
    }

    private var updateStatusIcon: String {
        switch updateService.phase {
        case .failed: "warning"
        case .available: "export"
        case .current: "check"
        case .idle, .checking: "sync"
        }
    }

    private var updateStatusColor: Color {
        switch updateService.phase {
        case .failed: PulsePalette.coral
        case .available: PulsePalette.warning
        case .current: PulsePalette.lime
        case .idle, .checking: PulsePalette.accent
        }
    }

    private var lastUpdateCheckText: String {
        guard let date = updateService.lastUpdateCheckDate else {
            return viewModel.t("update.never")
        }
        return date.formatted(
            Date.FormatStyle(date: .abbreviated, time: .shortened)
                .locale(Locale(identifier: viewModel.appLanguage.localeIdentifier))
        )
    }

    private func openURL(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    private static let websiteURL = URL(string: "https://github.com/Lincb522/CodexLens#readme")!
    private static let sourceURL = URL(string: "https://github.com/Lincb522/CodexLens")!

    private var appVersionDisplay: String {
        "\(appVersionNumber) (\(appBuildNumber))"
    }

    private var currentReleaseNoteKeys: [String] {
        [
            "update.releaseNote.roundedIcons",
            "update.releaseNote.luminousHeatmap",
            "update.releaseNote.pageBounds",
            "update.releaseNote.astraPricing",
        ]
    }

    private var appVersionNumber: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.4.1"
    }

    private var appBuildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "41"
    }

    private var sessionPageCount: Int {
        max(1, Int(ceil(Double(viewModel.filteredSessions.count) / Double(sessionsPerPage))))
    }

    private var visibleSessions: [SessionSummary] {
        let safePage = min(sessionPage, max(0, sessionPageCount - 1))
        let start = safePage * sessionsPerPage
        guard start < viewModel.filteredSessions.count else { return [] }
        let end = min(start + sessionsPerPage, viewModel.filteredSessions.count)
        return Array(viewModel.filteredSessions[start..<end])
    }

    private var sessionPager: some View {
        HStack(spacing: 12) {
            Button {
                sessionPage = max(0, sessionPage - 1)
            } label: {
                PulseIcon(name: "arrow-left").frame(width: 12, height: 12)
            }
            .disabled(sessionPage == 0)

            Text("\(sessionPage + 1) / \(sessionPageCount)")
                .font(.system(size: 12, weight: .semibold, design: .default))
                .foregroundStyle(PulsePalette.muted)
                .monospacedDigit()

            Button {
                sessionPage = min(sessionPageCount - 1, sessionPage + 1)
            } label: {
                PulseIcon(name: "arrow-right").frame(width: 12, height: 12)
            }
            .disabled(sessionPage >= sessionPageCount - 1)
        }
        .buttonStyle(PulseTextButtonStyle())
        .frame(height: 28)
    }

    private var footerDestination: MenuPopoverPage {
        switch page {
        case .overview, .tokenDetails, .usageHistory, .quotaDetails, .activeTasks: .overview
        case .sessions: .sessions
        case .settings, .tokenLogin: .settings
        case .tiboSignal, .about, .updates, .legal, .more: .more
        }
    }

    private var footer: some View {
        HStack(spacing: 4) {
            footerTab(.overview, icon: "pulse", title: viewModel.t("nav.live"))
            footerTab(.sessions, icon: "history", title: viewModel.t("nav.history"))
            footerTab(.settings, icon: "console", title: viewModel.t("nav.settings"))
            footerTab(
                .more,
                icon: "more",
                title: viewModel.t("page.more"),
                showsStatus: true
            )
        }
        .padding(.horizontal, 5)
        .frame(height: 48)
        .glassOutline(radius: 10)
        .padding(.horizontal, 16)
        .frame(height: Self.footerHeight)
    }

    private func footerTab(
        _ destination: MenuPopoverPage,
        icon: String,
        title: String,
        showsStatus: Bool = false
    ) -> some View {
        let selected = footerDestination == destination
        return Button {
            page = destination
        } label: {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 4) {
                    PulseIcon(name: icon)
                        .frame(width: 24, height: 23)
                    Text(title)
                        .font(.system(size: 12, weight: .regular))
                }
                .foregroundStyle(selected ? PulsePalette.accent : PulsePalette.muted)
                .frame(maxWidth: .infinity, minHeight: 44)

                if showsStatus {
                    Circle()
                        .fill(viewModel.isScanning ? PulsePalette.warning : PulsePalette.lime)
                        .frame(width: 6, height: 6)
                        .padding(.top, 5)
                        .padding(.trailing, 9)
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(PulsePressStyle())
        .help(title)
        .accessibilityLabel(title)
        .accessibilityIdentifier(destination == .more ? "Footer.More" : "Footer.\(destination.rawValue)")
    }

    private func inlineFailure(_ error: String, title: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            PulseIcon(name: "warning").frame(width: 16, height: 16)
                .foregroundStyle(PulsePalette.coral)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .default))
                    .foregroundStyle(PulsePalette.ink)
                MarqueeLabel(text: error, font: .system(size: 12, weight: .medium), color: PulsePalette.muted)
                    .frame(height: 16)
            }
            Spacer()
            Button(viewModel.t("action.retry"), action: viewModel.refresh)
                .buttonStyle(PulseTextButtonStyle(color: PulsePalette.coral))
        }
        .padding(13)
        .background(PulsePalette.coral.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(PulsePalette.coral.opacity(0.22), lineWidth: 1)
        }
    }

    private func creditText(_ credits: CodexCreditBalance?) -> String {
        guard let credits else { return "—" }
        if credits.unlimited { return viewModel.t("ledger.unlimited") }
        guard let balance = credits.balance else { return credits.hasCredits ? viewModel.t("ledger.available") : "—" }
        return balance.formatted(.number.precision(.fractionLength(0...2)))
    }
}

private struct TokenUsageMonthSummary: Identifiable {
    var id: Date { month }
    let month: Date
    let tokens: Int64
}

private struct TokenUsageMonthLabels: View {
    let months: [Date]
    let label: (Date) -> String

    var body: some View {
        HStack(spacing: 0) {
            ForEach(months, id: \.self) { month in
                Text(label(month))
                    .font(.system(size: 12, weight: .medium, design: .default))
                    .foregroundStyle(PulsePalette.faint)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityHidden(true)
    }
}

struct OverviewUsageCalendar: View {
    let weeks: [[TokenUsageHeatmapDay]]
    let chartLabel: String
    let dayLabel: (TokenUsageHeatmapDay) -> String
    let onSelect: (TokenUsageHeatmapDay) -> Void
    static let weekCount = 16
    static let weekdayWidth: CGFloat = 28
    private let cellSize: CGFloat = 14.5
    private let gap: CGFloat = 2.25
    private let weekdays: [String]
    private let monthLabels: [Int: String]

    init(weeks: [[TokenUsageHeatmapDay]], locale: Locale, chartLabel: String,
         dayLabel: @escaping (TokenUsageHeatmapDay) -> String,
         onSelect: @escaping (TokenUsageHeatmapDay) -> Void) {
        self.weeks = weeks
        self.chartLabel = chartLabel
        self.dayLabel = dayLabel
        self.onSelect = onSelect
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        weekdays = formatter.shortWeekdaySymbols
        formatter.setLocalizedDateFormatFromTemplate("MMM")
        var labels: [Int: String] = [:]
        for (index, week) in weeks.enumerated() {
            guard let first = week.first else { continue }
            let monthStart = week.first { calendar.component(.day, from: $0.date) == 1 }
            if let monthStart {
                labels[index] = formatter.string(from: monthStart.date)
            } else if index == 0 && calendar.component(.day, from: first.date) < 20 {
                labels[index] = formatter.string(from: first.date)
            }
        }
        monthLabels = labels
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            VStack(spacing: gap) {
                ForEach(0..<7) { index in
                    Text(weekdays[index])
                        .font(.system(size: 12)).foregroundStyle(PulsePalette.muted)
                        .frame(width: Self.weekdayWidth, height: cellSize, alignment: .leading)
                }
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: gap) {
                    ForEach(weeks.indices, id: \.self) { index in
                        Color.clear.frame(width: cellSize, height: 16)
                            .overlay(alignment: index > weeks.count - 3 ? .trailing : .leading) {
                                if let label = monthLabels[index] {
                                    Text(label).font(.system(size: 12)).foregroundStyle(PulsePalette.muted).fixedSize()
                                }
                            }
                    }
                }
                .accessibilityHidden(true)
                TokenUsageHeatmapGrid(weeks: weeks, cellSize: cellSize, cellSpacing: gap,
                                      selectedDayKey: nil, onSelect: onSelect, chartLabel: chartLabel, dayLabel: dayLabel)
            }
        }
    }
}

private struct TokenUsageHeatmapGrid: View {
    let weeks: [[TokenUsageHeatmapDay]]
    let cellSize: CGFloat
    let cellSpacing: CGFloat
    let selectedDayKey: String?
    let onSelect: ((TokenUsageHeatmapDay) -> Void)?
    let chartLabel: String
    let dayLabel: (TokenUsageHeatmapDay) -> String

    var body: some View {
        HStack(spacing: cellSpacing) {
            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                VStack(spacing: cellSpacing) {
                    ForEach(week) { day in
                        TokenUsageHeatmapCell(
                            day: day,
                            size: cellSize,
                            selected: day.dateKey == selectedDayKey,
                            action: onSelect,
                            accessibilityLabel: dayLabel(day)
                        )
                    }
                }
            }
        }
        .accessibilityLabel(Text(chartLabel))
    }
}

struct TokenUsageHeatmapCell: View {
    let day: TokenUsageHeatmapDay
    let size: CGFloat
    let selected: Bool
    let action: ((TokenUsageHeatmapDay) -> Void)?
    let accessibilityLabel: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    var body: some View {
        Group {
            if let action, !day.isFuture {
                Button { action(day) } label: { cell }
                    .buttonStyle(.plain)
                    .accessibilityLabel(accessibilityLabel)
            } else {
                cell
                    .accessibilityHidden(true)
            }
        }
        .frame(width: size, height: size)
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered)
        .help(day.isFuture ? "" : accessibilityLabel)
    }

    private var cell: some View {
        let shape = RoundedRectangle(cornerRadius: min(1, size * 0.08), style: .continuous)
        let tint = PulsePalette.heatmapGlassTint(intensity: day.intensity)
        return shape
            .fill(day.isFuture ? PulsePalette.heatmapFuture : PulsePalette.heatmapEmpty.opacity(day.intensity == 0 ? 1 : 0.15))
            .overlay {
                shape.fill(LinearGradient(
                    colors: [tint.opacity(glassOpacity), tint.opacity(glassOpacity * 0.94)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                .blendMode(colorScheme == .dark ? .screen : .normal)
            }
            .overlay {
                shape.fill(LinearGradient(
                    stops: [.init(color: .white.opacity(glassOpacity * 0.22), location: 0),
                            .init(color: .white.opacity(glassOpacity * 0.07), location: 0.45),
                            .init(color: .clear, location: 1)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
            }
            .overlay {
                shape.strokeBorder(LinearGradient(
                    colors: [.white.opacity(glassOpacity * 0.30 + 0.03), .white.opacity(0.015)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ), lineWidth: 0.5)
            }
            .overlay {
                if selected || isHovered {
                    shape.strokeBorder(PulsePalette.ink.opacity(selected ? 0.65 : 0.28), lineWidth: 1)
                }
            }
            .contentShape(Rectangle())
    }

    private var glassOpacity: Double {
        guard !day.isFuture else { return 0 }
        switch day.intensity {
        case 1: return 0.34
        case 2: return 0.47
        case 3: return 0.62
        case 4: return colorScheme == .dark ? 0.84 : 0.68
        default: return 0
        }
    }
}

private struct LiveContextCard: View {
    let context: CodexLiveContextSnapshot
    let onOpenDetails: () -> Void
    @EnvironmentObject private var viewModel: DashboardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .bottom, spacing: 8) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(viewModel.t("detail.currentContext"))
                        .font(.system(size: 13)).foregroundStyle(PulsePalette.muted)
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(DisplayFormat.integer(context.contextInputTokens))
                            .font(.system(size: 30, weight: .regular))
                            .tracking(-0.5).monospacedDigit()
                        Text("Token").font(.system(size: 12)).foregroundStyle(PulsePalette.muted)
                    }
                    .foregroundStyle(PulsePalette.ink)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(context.contextUsedPercent.map { $0.formatted(.number.precision(.fractionLength(0))) + "%" } ?? "—")
                        .font(.system(size: 21, weight: .regular)).monospacedDigit()
                        .foregroundStyle(PulsePalette.ink)
                    Text(viewModel.t("detail.utilization"))
                        .font(.system(size: 12)).foregroundStyle(PulsePalette.muted)
                }
            }
            ContextCapacityRuler(capacity: context.contextCapacityWindow, progress: (context.contextUsedPercent ?? 0) / 100)
                .accessibilityLabel(context.contextCapacityWindow.map { viewModel.t("live.contextLimit", DisplayFormat.integer($0)) } ?? viewModel.t("live.single"))
            HStack(spacing: 20) {
                ContextTokenRow(direction: .cached, title: viewModel.t("live.cached"), value: context.lastRequest.cachedInputTokens)
                PulsePalette.divider.frame(width: 1, height: 34)
                ContextTokenRow(direction: .output, title: viewModel.t("live.requestOutput"), value: context.lastRequest.outputTokens)
            }
            Button(action: onOpenDetails) {
                HStack(spacing: 9) {
                    Text(viewModel.t("live.tokenDetail")).font(.system(size: 13, weight: .regular))
                    PulseIcon(name: "arrow-right").frame(width: 11, height: 11)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(PulsePalette.accent)
                .frame(height: 22)
                .contentShape(Rectangle())
            }
            .buttonStyle(PulsePressStyle())
            .accessibilityIdentifier("Overview.TokenDetails")
        }
        .frame(height: 190, alignment: .top)
    }
}

private struct ContextCapacityRuler: View {
    let capacity: Int64?
    let progress: Double

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .top) {
                ContextUsageBar(progress: progress, color: PulsePalette.accent).frame(height: 5)
                HStack(spacing: 0) {
                    ForEach(0..<17) { tick in
                        if tick > 0 { Spacer(minLength: 0) }
                        PulsePalette.muted.opacity(0.55).frame(width: 0.5, height: tick.isMultiple(of: 4) ? 7 : 3)
                    }
                }
                .padding(.top, 5)
            }
            .frame(height: 12)
            HStack {
                Text("0")
                Spacer(minLength: 0)
                Text(capacity.map { DisplayFormat.integer($0) + " Token" } ?? "—")
            }
            .font(.system(size: 12)).monospacedDigit().foregroundStyle(PulsePalette.muted)
        }
        .accessibilityElement(children: .ignore)
    }
}

private struct LiveTokenDetails: View {
    let context: CodexLiveContextSnapshot
    let apiUSD: CostBreakdown?
    let taskAPIUSD: CostBreakdown?
    let showAPIEstimate: Bool
    let showRuntimeWindow: Bool
    @EnvironmentObject private var viewModel: DashboardViewModel
    @State private var detailScope: TokenDetailScope
    @State private var showsRates = false

    init(context: CodexLiveContextSnapshot, apiUSD: CostBreakdown?, taskAPIUSD: CostBreakdown?,
         showAPIEstimate: Bool, showRuntimeWindow: Bool, initialDetailScope: TokenDetailScope) {
        self.context = context
        self.apiUSD = apiUSD
        self.taskAPIUSD = taskAPIUSD
        self.showAPIEstimate = showAPIEstimate
        self.showRuntimeWindow = showRuntimeWindow
        _detailScope = State(initialValue: initialDetailScope)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if showsRates {
                rateDetails
            } else {
                Picker(viewModel.t("live.tokenDetail"), selection: $detailScope) {
                    ForEach(TokenDetailScope.allCases) { scope in
                        Text(viewModel.t(scope.titleKey)).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityIdentifier("TokenDetails.Scope")
                TokenScopeDetailSection(
                    title: viewModel.t("detail.total"), headline: detailUsage.totalTokens,
                    inputTitle: viewModel.t("live.input"), cachedTitle: viewModel.t("live.cached"), outputTitle: viewModel.t("live.output"),
                    inputValue: detailUsage.inputTokens, cachedValue: detailUsage.cachedInputTokens, outputValue: detailUsage.outputTokens
                )
                if showAPIEstimate {
                    PulsePalette.divider.frame(height: 1)
                    apiCostRow(title: viewModel.t("live.turnAPIEstimate"), value: apiEstimateValue(apiUSD))
                    apiCostRow(title: viewModel.t("live.taskAPIEstimate"), value: apiEstimateValue(taskAPIUSD))
                }
                PulsePalette.divider.frame(height: 1)
                Button { showsRates = true } label: {
                    HStack(spacing: 8) {
                        MarqueeLabel(text: modelLabel, font: .system(size: 13), color: PulsePalette.muted)
                            .frame(height: 24)
                        PulseIcon(name: "chevron-down").frame(width: 9, height: 9)
                            .foregroundStyle(PulsePalette.muted)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .glassOutline(radius: 7)
                }
                .buttonStyle(PulsePressStyle())
                .accessibilityLabel(viewModel.t("detail.modelAndRates"))
                .accessibilityIdentifier("TokenDetails.Rates")
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private var detailUsage: TokenUsage { detailScope.usage(in: context) }

    private var rateDetails: some View {
        VStack(alignment: .leading, spacing: 22) {
            Button { showsRates = false } label: {
                Label(viewModel.t("detail.modelAndRates"), systemImage: "chevron.left")
                    .font(.system(size: 14, weight: .medium)).foregroundStyle(PulsePalette.accent)
            }
            .buttonStyle(PulseTextButtonStyle())
            MarqueeLabel(text: context.displayTitle, font: .system(size: 15, weight: .medium), color: PulsePalette.ink).frame(height: 22)
            MarqueeLabel(text: modelLabel, font: .system(size: 16), color: PulsePalette.ink).frame(height: 24)
            if let detailWindowText {
                MarqueeLabel(text: detailWindowText, font: .system(size: 13), color: PulsePalette.muted).frame(height: 20)
            }
            MarqueeLabel(text: detailAccountingNote, font: .system(size: 12), color: PulsePalette.muted).frame(height: 18)
            if showAPIEstimate {
                PulsePalette.divider.frame(height: 1)
                if let rate = PricingCatalog.rate(for: context.model) {
                    PricingRateDetailRow(
                        title: standardTierTitle, unitTitle: viewModel.t("live.perMillionTokens"),
                        inputTitle: viewModel.t("live.input"), cachedTitle: viewModel.t("live.cached"), outputTitle: viewModel.t("live.output"),
                        inputValue: "$\(compact(rate.inputPerMillion))", cachedValue: "$\(compact(rate.cachedInputPerMillion))", outputValue: "$\(compact(rate.outputPerMillion))"
                    )
                    if apiUSD?.isLongContext == true {
                        PricingRateDetailRow(
                            title: longTierTitle, unitTitle: viewModel.t("live.perMillionTokens"),
                            inputTitle: viewModel.t("live.input"), cachedTitle: viewModel.t("live.cached"), outputTitle: viewModel.t("live.output"),
                            inputValue: "$\(compact(rate.inputPerMillion * rate.longContextInputMultiplier))",
                            cachedValue: "$\(compact(rate.cachedInputPerMillion * rate.longContextInputMultiplier))",
                            outputValue: "$\(compact(rate.outputPerMillion * rate.longContextOutputMultiplier))"
                        )
                    }
                } else {
                    Text(viewModel.t("live.apiMissing"))
                        .font(.system(size: 12))
                        .foregroundStyle(PulsePalette.muted)
                }

            }
        }
    }

    private var detailWindowText: String? {
        if showRuntimeWindow, let runtime = context.modelContextWindow {
            return viewModel.t("live.runtime", DisplayFormat.tokens(runtime))
        }
        return context.contextCapacityWindow.map {
            viewModel.t("live.contextLimit", DisplayFormat.tokens($0))
        }
    }

    private var modelLabel: String {
        let model = PricingCatalog.normalize(model: context.model)
        guard let effort = context.reasoningEffort, !effort.isEmpty else { return model }
        return "\(model) · \(effort)"
    }

    private func apiEstimateValue(_ cost: CostBreakdown?) -> String {
        guard let value = cost?.total else { return viewModel.t("live.noRate") }
        return "≈ \(DisplayFormat.usd(value))"
    }

    private func apiCostRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            MarqueeLabel(text: title, font: .system(size: 13), color: PulsePalette.muted).frame(height: 22)
            Spacer(minLength: 0)
            Text(value).font(.system(size: 16)).foregroundStyle(PulsePalette.ink).monospacedDigit().fixedSize()
        }
        .frame(height: 27)
    }

    private var longContextCallCount: Int {
        context.currentTurnCalls.reduce(into: 0) { count, call in
            guard let threshold = PricingCatalog.rate(for: call.model)?.longContextThreshold,
                  call.usage.inputTokens > threshold
            else { return }
            count += 1
        }
    }

    private var standardTierTitle: String {
        tierTitle(viewModel.t("live.standardTier", "__RATE__"))
    }

    private var longTierTitle: String {
        tierTitle(viewModel.t("live.longTier", "__RATE__", longContextCallCount))
    }

    private func tierTitle(_ localized: String) -> String {
        localized
            .replacingOccurrences(of: "__RATE__", with: "")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var detailAccountingNote: String {
        let cacheNote = viewModel.t("live.inputIncludesCache")
        guard context.duplicateEventsIgnored > 0 else { return cacheNote }
        return cacheNote + " · " + viewModel.t("live.duplicatesIgnored", context.duplicateEventsIgnored)
    }

    private func compact(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }
}

private enum HeroTokenDirection {
    case input
    case cached
    case output

    var iconName: String {
        switch self {
        case .input, .output: "arrow-right"
        case .cached: "sync"
        }
    }

    var rotation: Angle {
        switch self {
        case .input: .degrees(90)
        case .cached: .zero
        case .output: .degrees(-90)
        }
    }
}

enum TokenDetailScope: String, CaseIterable, Identifiable {
    case context, turn, task
    var id: String { rawValue }
    var titleKey: String { "detail.scope." + rawValue }

    func usage(in context: CodexLiveContextSnapshot) -> TokenUsage {
        switch self {
        case .context: context.lastRequest
        case .turn: context.currentTurnUsage
        case .task: context.taskTotal
        }
    }
}

private struct TokenScopeDetailSection: View {
    let title: String
    let headline: Int64
    let inputTitle: String
    let cachedTitle: String
    let outputTitle: String
    let inputValue: Int64
    let cachedValue: Int64
    let outputValue: Int64

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 13)).foregroundStyle(PulsePalette.muted)
                ExactTokenNumber(value: headline, size: 32)
            }
            VStack(spacing: 8) {
                DetailTokenMetric(direction: .input, title: inputTitle, value: inputValue)
                DetailTokenMetric(direction: .cached, title: cachedTitle, value: cachedValue)
                DetailTokenMetric(direction: .output, title: outputTitle, value: outputValue)
            }
        }
    }
}

private struct ExactTokenNumber: View {
    let value: Int64
    let size: CGFloat

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                number.fixedSize()
                Text("Token").font(.system(size: 12)).foregroundStyle(PulsePalette.muted)
            }
            VStack(alignment: .leading, spacing: 2) {
                MarqueeLabel(text: DisplayFormat.integer(value), font: .system(size: size, weight: .regular), color: PulsePalette.ink)
                    .frame(height: size * 1.2)
                Text("Token").font(.system(size: 12)).foregroundStyle(PulsePalette.muted)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var number: some View {
        Text(DisplayFormat.integer(value))
            .font(.system(size: size, weight: .regular))
            .monospacedDigit().foregroundStyle(PulsePalette.ink)
    }
}

private struct DetailTokenMetric: View {
    let direction: HeroTokenDirection
    let title: String
    let value: Int64

    var body: some View {
        HStack(spacing: 14) {
            PulseIcon(name: direction.iconName).frame(width: 19, height: 19).rotationEffect(direction.rotation)
                .foregroundStyle(PulsePalette.muted)
            VStack(alignment: .leading, spacing: 5) {
                MarqueeLabel(text: title, font: .system(size: 13), color: PulsePalette.muted).frame(height: 18)
                ExactTokenNumber(value: value, size: 24)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .frame(height: 78)
        .glassOutline(radius: 8)
        .accessibilityElement(children: .combine)
    }
}

private struct PricingRateDetailRow: View {
    let title: String
    let unitTitle: String
    let inputTitle: String
    let cachedTitle: String
    let outputTitle: String
    let inputValue: String
    let cachedValue: String
    let outputValue: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(title)
                Spacer(minLength: 4)
                Text(unitTitle)
                    .fontDesign(.monospaced)
            }
            .font(.system(size: 12, weight: .semibold, design: .default))
            .foregroundStyle(PulsePalette.detailMuted)

            HStack(spacing: 0) {
                PricingRateMetric(title: inputTitle, value: inputValue)
                PricingRateMetric(title: cachedTitle, value: cachedValue)
                PricingRateMetric(title: outputTitle, value: outputValue)
            }
        }
    }
}

private struct PricingRateMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            MarqueeLabel(text: title, font: .system(size: 12), color: PulsePalette.muted).frame(height: 18)
            Text(value).font(.system(size: 17)).foregroundStyle(PulsePalette.ink).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ContextTokenRow: View {
    let direction: HeroTokenDirection
    let title: String
    let value: Int64

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                PulseIcon(name: direction.iconName).frame(width: 10, height: 10).rotationEffect(direction.rotation)
                MarqueeLabel(text: title, font: .system(size: 12), color: PulsePalette.muted).frame(height: 17)
            }
            .foregroundStyle(PulsePalette.muted)
            ExactTokenNumber(value: value, size: 18)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 60, alignment: .top)
        .accessibilityElement(children: .combine)
    }
}

struct MarqueeLabel: View {
    let text: String
    let font: Font
    let color: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var textWidth: CGFloat = 0
    @State private var cycleStartedAt = Date()

    var body: some View {
        // Use the native line height for clipping, including fallback glyphs.
        Text(text)
            .font(font)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .hidden()
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion || textWidth <= proxy.size.width)) { timeline in
                        Text(text)
                            .font(font)
                            .foregroundStyle(color)
                            .fixedSize()
                            .offset(x: marqueeOffset(at: timeline.date, containerWidth: proxy.size.width))
                            .background {
                                GeometryReader { textProxy in
                                    Color.clear.preference(key: MarqueeTextWidthKey.self, value: textProxy.size.width)
                                }
                            }
                    }
                }
            }
            .clipped()
            .onPreferenceChange(MarqueeTextWidthKey.self) { textWidth = $0 }
            .onChange(of: text) { _, _ in cycleStartedAt = Date() }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text)
            .help(text)
    }

    private func marqueeOffset(at date: Date, containerWidth: CGFloat) -> CGFloat {
        guard !reduceMotion else { return 0 }
        let overflow = max(0, textWidth - containerWidth)
        guard overflow > 0 else { return 0 }

        let pause = 1.2
        let travel = max(2.4, Double(overflow / 24))
        let cycle = pause + travel + pause + travel
        let elapsed = max(0, date.timeIntervalSince(cycleStartedAt))
        let time = elapsed.truncatingRemainder(dividingBy: cycle)
        let progress: Double

        if time < pause {
            progress = 0
        } else if time < pause + travel {
            progress = (time - pause) / travel
        } else if time < pause + travel + pause {
            progress = 1
        } else {
            progress = 1 - ((time - pause - travel - pause) / travel)
        }
        return -overflow * CGFloat(progress)
    }
}

private struct MarqueeTextWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct ContextUsageBar: View {
    let progress: Double
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(color)
                    .frame(width: max(progress > 0 ? 6 : 0, proxy.size.width * min(max(progress, 0), 1)))
                    .animation(
                        reduceMotion ? nil : .spring(response: 0.46, dampingFraction: 0.9),
                        value: progress
                    )
            }
        }
    }
}

private struct FlatMetric: View {
    let title: String
    let value: String
    var showsChevron = false
    var horizontalPadding: CGFloat = 8
    var action: (() -> Void)?

    init(
        title: String,
        value: String,
        showsChevron: Bool = false,
        horizontalPadding: CGFloat = 8,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.value = value
        self.showsChevron = showsChevron
        self.horizontalPadding = horizontalPadding
        self.action = action
    }

    var body: some View {
        Group {
            if let action {
                Button(action: action) { content }
                    .buttonStyle(PulsePressStyle())
            } else {
                content
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .default))
                .foregroundStyle(PulsePalette.muted)
            HStack(spacing: 5) {
                Text(value)
                    .font(.system(size: 14, weight: .semibold, design: .default))
                    .foregroundStyle(PulsePalette.ink)
                    .monospacedDigit()
                Spacer(minLength: 2)
                if showsChevron {
                    PulseIcon(name: "arrow-right")
                        .frame(width: 8, height: 8)
                        .foregroundStyle(PulsePalette.faint)
                }
            }
        }
        .padding(.horizontal, horizontalPadding)
        .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct ContextRing: View {
    let progress: Double
    @EnvironmentObject private var viewModel: DashboardViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.09), lineWidth: 8)

            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(
                    AngularGradient(
                        colors: [Color.primary.opacity(0.45), Color.primary, Color.primary.opacity(0.72)],
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(
                    reduceMotion ? nil : .spring(response: 0.52, dampingFraction: 0.86),
                    value: progress
                )

            VStack(spacing: 0) {
                Text((progress * 100).formatted(.number.precision(.fractionLength(1))) + "%")
                    .font(.system(size: 19, weight: .semibold, design: .default))
                    .foregroundStyle(PulsePalette.ink)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(viewModel.t("live.inputContextShort"))
                    .font(.system(size: 12, weight: .semibold, design: .default))
                    .foregroundStyle(PulsePalette.faint)
            }
        }
        .frame(width: 70, height: 70)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(viewModel.t("live.contextA11y"))
        .accessibilityValue("\(Int((progress * 100).rounded()))%")
    }
}

private struct LivePulseBadge: View {
    let isFresh: Bool
    @EnvironmentObject private var viewModel: DashboardViewModel

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(isFresh ? PulsePalette.accent : PulsePalette.warning).frame(width: 5, height: 5)
            Text(viewModel.t(isFresh ? "live.stateFresh" : "live.stateStale"))
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(isFresh ? PulsePalette.accent : PulsePalette.muted)
        .padding(.horizontal, 6)
        .frame(height: 20)
        .background(PulsePalette.surfaceRaised, in: RoundedRectangle(cornerRadius: 5))
    }
}

private struct TokenFlowBar: View {
    let usage: TokenUsage
    @EnvironmentObject private var viewModel: DashboardViewModel

    var body: some View {
        GeometryReader { proxy in
            let values = [
                max(usage.uncachedInputTokens, 0),
                max(usage.cachedInputTokens, 0),
                max(usage.outputTokens, 0),
            ]
            let total = max(values.reduce(0, +), 1)
            HStack(spacing: 2) {
                flowSegment(width: proxy.size.width * CGFloat(Double(values[0]) / Double(total)), color: PulsePalette.accent.opacity(0.34))
                flowSegment(width: proxy.size.width * CGFloat(Double(values[1]) / Double(total)), color: PulsePalette.accent)
                flowSegment(width: proxy.size.width * CGFloat(Double(values[2]) / Double(total)), color: PulsePalette.ink.opacity(0.30))
            }
        }
        .background(Color.primary.opacity(0.08), in: Capsule())
        .clipShape(Capsule())
        .accessibilityLabel(viewModel.t("live.flowA11y"))
        .accessibilityValue(viewModel.t("live.flowDetail"))
    }

    private func flowSegment(width: CGFloat, color: Color) -> some View {
        Capsule()
            .fill(color)
            .frame(width: max(width, 3))
    }
}

private struct TokenStat: View {
    let title: String
    let value: Int64
    var alignment: HorizontalAlignment = .leading
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(PulsePalette.muted)

            Text(DisplayFormat.tokens(value))
                .font(.system(size: 14, weight: .semibold, design: .default))
                .foregroundStyle(PulsePalette.ink)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: value)
        }
        .frame(maxWidth: .infinity, alignment: alignment == .trailing ? .trailing : .leading)
    }
}

private struct QuotaPulseRow: View {
    let window: CodexQuotaWindow
    let index: Int
    @EnvironmentObject private var viewModel: DashboardViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(localizedWindowTitle)
                        .font(.system(size: 13, weight: .semibold, design: .default))
                        .foregroundStyle(PulsePalette.ink)
                        .lineLimit(1)

                    HStack(spacing: 5) {
                        PulseIcon(name: "timer")
                            .frame(width: 10, height: 10)
                        Text(resetMomentText)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(PulsePalette.faint)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }

                Spacer()

                Text("\(Int(window.remainingPercent.rounded()))%")
                    .font(.system(size: 14, weight: .semibold, design: .default))
                    .foregroundStyle(accentColor)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(accentColor)
                        .frame(width: max(window.remainingPercent > 0 ? 5 : 0, proxy.size.width * window.remainingPercent / 100))
                        .animation(
                            reduceMotion ? nil : .spring(response: 0.46, dampingFraction: 0.9).delay(Double(index) * 0.035),
                            value: window.remainingPercent
                        )
                }
            }
            .frame(height: 5)
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 2)
        .background(
            hovering ? PulsePalette.surfaceRaised : .clear,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: hovering)
        .onHover { hovering = $0 }
        .help(resetText)
        .accessibilityElement(children: .combine)
    }

    private var accentColor: Color {
        if window.remainingPercent <= 10 { return PulsePalette.coral }
        if window.remainingPercent <= 25 { return PulsePalette.warning }
        return PulsePalette.accent
    }

    private var resetMomentText: String {
        guard let resetsAt = window.resetsAt else {
            return viewModel.t("quota.used", Int(window.clampedUsedPercent.rounded()))
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: viewModel.appLanguage.localeIdentifier)
        formatter.unitsStyle = .full
        return formatter.localizedString(for: resetsAt, relativeTo: Date())
    }

    private var resetText: String {
        guard let resetsAt = window.resetsAt else {
            return viewModel.t("quota.used", Int(window.clampedUsedPercent.rounded()))
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: viewModel.appLanguage.localeIdentifier)
        formatter.unitsStyle = .full
        return viewModel.t("quota.reset", Int(window.clampedUsedPercent.rounded()), formatter.localizedString(for: resetsAt, relativeTo: Date()))
    }

    private var localizedWindowTitle: String {
        if window.id.localizedCaseInsensitiveContains("review") { return viewModel.t("quota.review") }
        let minutes = window.windowMinutes ?? 0
        let isNamedAdditionalWindow = window.id != "primary" && window.id != "secondary"
        if minutes >= 6 * 24 * 60 {
            return isNamedAdditionalWindow
                ? viewModel.t("quota.namedWeekly", window.title)
                : viewModel.t("quota.weekly")
        }
        if isNamedAdditionalWindow { return window.title }
        if minutes == 300 { return viewModel.t("quota.fiveHours") }
        if minutes > 0, minutes.isMultiple(of: 24 * 60) {
            return viewModel.t("quota.days", minutes / (24 * 60))
        }
        if minutes > 0, minutes.isMultiple(of: 60) {
            return viewModel.t("quota.hours", minutes / 60)
        }
        return window.title
    }
}

private struct PulseSessionRow: View {
    let session: SessionSummary
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            MarqueeLabel(
                text: title,
                font: .system(size: 14, weight: .semibold),
                color: PulsePalette.ink
            )
            .frame(height: 18)
            HStack(spacing: 12) {
                MarqueeLabel(
                    text: subtitle,
                    font: .system(size: 12, weight: .regular),
                    color: PulsePalette.muted
                )
                .frame(height: 16)
                Text("\(DisplayFormat.tokens(session.usage.totalTokens)) Token")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(PulsePalette.accent)
                    .monospacedDigit()
                    .fixedSize()
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 58)
        .help(session.lastActivityAt.formatted(date: .complete, time: .shortened))
        .accessibilityElement(children: .combine)
    }
}

private struct PulseSettingsGroup<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .default))
                .foregroundStyle(PulsePalette.faint)
                .padding(.leading, 3)
            VStack(spacing: 0) { content }
                .font(.system(size: 13, weight: .semibold, design: .default))
                .foregroundStyle(PulsePalette.ink)
                .background(PulsePalette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

private struct CockpitAccountRow: View {
    let name: String
    let plan: String
    let isMonitored: Bool
    let isCodexLogin: Bool
    let isBusy: Bool
    let monitorTitle: String
    let activateTitle: String
    let onMonitor: () -> Void
    let onActivate: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onMonitor) {
                HStack(spacing: 9) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(isCodexLogin ? PulsePalette.accent.opacity(0.13) : PulsePalette.surfaceRaised)
                        PulseIcon(name: "account")
                            .frame(width: 15, height: 15)
                            .foregroundStyle(isCodexLogin ? PulsePalette.accent : PulsePalette.ink)
                    }
                    .frame(width: 27, height: 27)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(name)
                            .font(.system(size: 12, weight: .semibold, design: .default))
                            .foregroundStyle(PulsePalette.ink)
                            .lineLimit(1)
                        HStack(spacing: 5) {
                            Text(plan)
                            if isCodexLogin { Text("CODEX") }
                            else if isMonitored { Text("MON") }
                        }
                        .font(.system(size: 12, weight: .semibold, design: .default))
                        .foregroundStyle(isCodexLogin ? PulsePalette.accent : PulsePalette.faint)
                    }
                    Spacer(minLength: 2)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PulsePressStyle())
            .help(monitorTitle)

            Button(action: onActivate) {
                HStack(spacing: 4) {
                    PulseIcon(name: isCodexLogin ? "check" : "sync")
                        .frame(width: 10, height: 10)
                    Text(isCodexLogin ? "CODEX" : activateTitle)
                        .lineLimit(1)
                }
                .font(.system(size: 12, weight: .semibold, design: .default))
                .foregroundStyle(isCodexLogin ? PulsePalette.accent : PulsePalette.ink)
                .padding(.horizontal, 8)
                .frame(height: 26)
                .background(
                    isCodexLogin ? PulsePalette.accent.opacity(0.11) : PulsePalette.surfaceRaised,
                    in: Capsule()
                )
            }
            .buttonStyle(PulsePressStyle())
            .disabled(isBusy || isCodexLogin)
        }
        .padding(.horizontal, 10)
        .frame(height: 42)
        .background(hovering ? PulsePalette.surfaceHover.opacity(0.72) : Color.clear)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: hovering)
        .onHover { hovering = $0 }
    }
}

private struct SettingsValueRow: View {
    let title: String
    let value: String
    var showsChevron = false

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .foregroundStyle(PulsePalette.ink)
            Spacer()
            Text(value)
                .foregroundStyle(PulsePalette.muted)
                .lineLimit(1)
            if showsChevron {
                PulseIcon(name: "chevron-down").frame(width: 8, height: 8)
                    .foregroundStyle(PulsePalette.faint)
            }
        }
        .padding(.horizontal, 13)
        .frame(height: 46)
        .contentShape(Rectangle())
    }
}

private struct SettingsToggleRow: View {
    let title: String
    @Binding var isOn: Bool
    let changed: () -> Void

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            PulseToggle(isOn: $isOn)
                .accessibilityLabel(title)
        }
        .padding(.horizontal, 13)
        .frame(height: 46)
        .contentShape(Rectangle())
        .onChange(of: isOn) { _, _ in changed() }
    }
}

private struct SettingsActionToggleRow: View {
    let title: String
    let isOn: Bool
    let changed: (Bool) -> Void

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            PulseToggle(
                isOn: Binding(
                    get: { isOn },
                    set: changed
                )
            )
            .accessibilityLabel(title)
        }
        .padding(.horizontal, 13)
        .frame(height: 46)
        .contentShape(Rectangle())
    }
}

private struct PulseToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) { EmptyView() }
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
            .tint(PulsePalette.accent)
    }
}

private struct AnimatedRefreshIcon: View {
    let isSpinning: Bool
    var idleColor: Color = PulsePalette.ink
    var spinningColor: Color = PulsePalette.warning
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !isSpinning || reduceMotion)) { timeline in
            let degrees = isSpinning
                ? timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1) * 360
                : 0
            PulseIcon(name: "sync").frame(width: 20, height: 20)
                .foregroundStyle(isSpinning ? spinningColor : idleColor)
                .rotationEffect(.degrees(degrees))
        }
    }
}

private struct SignalSkeleton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate
            let opacity = reduceMotion ? 0.45 : 0.28 + (sin(phase * 3) + 1) * 0.14
            ZStack {
                Circle().stroke(PulsePalette.accent.opacity(opacity), lineWidth: 7)
                Circle().fill(PulsePalette.accent.opacity(0.12)).padding(13)
                PulseIcon(name: "pulse").frame(width: 18, height: 18)
                    .foregroundStyle(PulsePalette.accent)
            }
        }
    }
}

private struct PulsePressStyle: ButtonStyle {
    var enabled = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(enabled && configuration.isPressed ? 0.82 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.10), value: configuration.isPressed)
    }
}

private struct PulseTextButtonStyle: ButtonStyle {
    var color: Color = PulsePalette.accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold, design: .default))
            .foregroundStyle(color)
            .opacity(configuration.isPressed ? 0.64 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.10), value: configuration.isPressed)
    }
}
