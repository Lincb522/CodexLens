import AppKit
import SwiftUI

enum MenuPopoverPage: String {
    case overview
    case tiboSignal
    case sessions
    case settings
    case tokenLogin
    case developer
}

enum ConsolePanel: String, CaseIterable, Identifiable {
    case appearance
    case live
    case account
    case data
    var id: String { rawValue }
}

private enum OverviewPanel: String, CaseIterable, Identifiable {
    case task
    case quota
    case account

    var id: String { rawValue }
}

private enum PulsePalette {
    // The native NSMenu remains the translucent canvas. Keep the colour system
    // deliberately narrow: one desaturated blue family, neutral glass surfaces
    // and semantic colour only for actual state. Avoid stacked cyan/teal tints,
    // heavy borders and milky overlays—the combination reads muddy on menu glass.
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

    static let canvas = Color.clear
    static let surface = adaptive(light: 1.0, dark: 0.15, alpha: 0.58)
    static let surfaceRaised = adaptive(light: 1.0, dark: 0.23, alpha: 0.74)
    static let surfaceHover = adaptive(light: 0.88, dark: 0.30, alpha: 0.24)
    // Light mode uses a cool blue graphite rather than neutral black. It keeps
    // the required contrast while feeling connected to the atmospheric hero
    // instead of looking printed on top of it.
    static let ink = adaptiveColor(
        light: NSColor(srgbRed: 0.08, green: 0.16, blue: 0.23, alpha: 1),
        dark: NSColor(calibratedWhite: 0.95, alpha: 1)
    )
    static let muted = adaptiveColor(
        light: NSColor(srgbRed: 0.31, green: 0.40, blue: 0.48, alpha: 1),
        dark: NSColor(calibratedWhite: 0.68, alpha: 1)
    )
    static let faint = adaptiveColor(
        light: NSColor(srgbRed: 0.45, green: 0.52, blue: 0.59, alpha: 1),
        dark: NSColor(calibratedWhite: 0.56, alpha: 1)
    )
    static let accent = adaptiveColor(
        light: NSColor(srgbRed: 0.10, green: 0.39, blue: 0.68, alpha: 1),
        dark: NSColor(srgbRed: 0.40, green: 0.66, blue: 0.92, alpha: 1)
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
    static let divider = adaptive(light: 0.16, dark: 0.88, alpha: 0.075)
    static let selectionInk = adaptive(light: 0.98, dark: 0.98)
    static let heroInk = adaptive(light: 0.99, dark: 0.98)
    static let heroMuted = adaptive(light: 0.99, dark: 0.98, alpha: 0.74)
    static let heroTile = adaptive(light: 1.0, dark: 1.0, alpha: 0.14)
    static let heroMetricSurface = adaptiveColor(
        light: NSColor(srgbRed: 0.05, green: 0.28, blue: 0.45, alpha: 0.16),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.12)
    )
    static let heroLowerInk = adaptive(light: 0.99, dark: 0.98)
    static let heroLowerMuted = adaptive(light: 0.99, dark: 0.98, alpha: 0.76)
    static let heroSheen = adaptive(
        light: 1.0,
        dark: 1.0,
        alpha: MenuHeroTopPalette.sheenAlpha
    )
    // A restrained adaptive tint sits above SwiftUI's thin material.
    // It keeps the drawer readable while allowing the hero gradient beneath
    // to remain faintly visible as real frosted glass.
    static let detailGlassTint = adaptiveColor(
        light: NSColor(srgbRed: 0.94, green: 0.975, blue: 1.00, alpha: 0.95),
        dark: NSColor(srgbRed: 0.035, green: 0.085, blue: 0.13, alpha: 0.94)
    )
    static let detailInk = adaptiveColor(
        light: NSColor(srgbRed: 0.07, green: 0.16, blue: 0.23, alpha: 1),
        dark: NSColor(calibratedWhite: 0.97, alpha: 1)
    )
    static let detailMuted = adaptiveColor(
        light: NSColor(srgbRed: 0.29, green: 0.40, blue: 0.49, alpha: 1),
        dark: NSColor(calibratedWhite: 0.76, alpha: 1)
    )
    static let detailDivider = adaptive(light: 0.12, dark: 0.90, alpha: 0.13)
    static let heroStart = adaptiveColor(
        light: MenuHeroTopPalette.lightBase,
        dark: MenuHeroTopPalette.darkBase
    )
    static let heroEnd = adaptiveColor(
        light: NSColor(srgbRed: 0.46, green: 0.67, blue: 0.80, alpha: 0.80),
        dark: NSColor(srgbRed: 0.11, green: 0.22, blue: 0.34, alpha: 0.74)
    )
}

private struct PulseIcon: View {
    let name: String
    var weight: Font.Weight = .semibold

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
    static let primaryPageHeight: CGFloat = 705
    private static let secondaryHeaderHeight: CGFloat = 58
    private static let footerHeight: CGFloat = 46
    private static let primaryPageContentHeight = primaryPageHeight - secondaryHeaderHeight - footerHeight
    private static let overviewPanelHeight: CGFloat = 142

    @EnvironmentObject private var viewModel: DashboardViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var systemColorScheme
    @State private var page: MenuPopoverPage
    @State private var sessionPage = 0
    @State private var consolePanel: ConsolePanel = .appearance
    @State private var credentialText: String
    @State private var credentialMode: AccountSwitchMode = .activateCodex
    @State private var overviewPanel: OverviewPanel = .quota
    private let initiallyExpandedLiveDetails: Bool

    // Eight 52pt rows use the fixed primary page height instead of leaving the
    // lower half of the ledger empty. Pagination remains explicit and the page
    // still contains no scrolling surface.
    private let sessionsPerPage = 8

    init(
        initialPage: MenuPopoverPage = .overview,
        initialConsolePanel: ConsolePanel = .appearance,
        initialCredentialText: String = "",
        initiallyExpandedLiveDetails: Bool = false
    ) {
        _page = State(initialValue: initialPage)
        _consolePanel = State(initialValue: initialConsolePanel)
        _credentialText = State(initialValue: initialCredentialText)
        self.initiallyExpandedLiveDetails = initiallyExpandedLiveDetails
    }

    var body: some View {
        VStack(spacing: 0) {
            if page != .overview {
                header
            }

            Group {
                switch page {
                case .overview: overview
                case .tiboSignal: tiboSignalDetail
                case .sessions: sessions
                case .settings: settings
                case .tokenLogin: tokenLogin
                case .developer: developer
                }
            }
            .id(page)
            .frame(maxWidth: .infinity)
            .transition(pageTransition)

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
        .animation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.9), value: page)
        .onChange(of: viewModel.searchText) { _, _ in sessionPage = 0 }
        .onChange(of: viewModel.filteredSessions.count) { _, _ in
            sessionPage = min(sessionPage, max(0, sessionPageCount - 1))
        }
        .onAppear { viewModel.menuPageChanged(isOverview: page == .overview) }
        .onChange(of: page) { _, newPage in
            viewModel.menuPageChanged(isOverview: newPage == .overview)
        }
    }

    private var pageTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
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
                } else if page != .overview {
                    page = .overview
                }
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(page == .overview ? strongSelection : PulsePalette.surfaceRaised)
                    PulseIcon(name: page == .overview ? "pulse" : "arrow-left")
                        .frame(width: page == .overview ? 17 : 14, height: page == .overview ? 17 : 14)
                        .foregroundStyle(page == .overview ? strongSelectionInk : PulsePalette.ink)
                }
                .frame(width: 36, height: 36)
            }
            .buttonStyle(PulsePressStyle())
            .help(page == .overview ? "Token Pulse" : viewModel.t("action.back"))

            VStack(alignment: .leading, spacing: 2) {
                Text(pageTitle)
                    .font(.system(size: 16, weight: .semibold, design: .default))
                    .foregroundStyle(PulsePalette.ink)
                    .fixedSize(horizontal: true, vertical: false)
                if page == .overview {
                    accountContext
                } else if !pageSubtitle.isEmpty {
                    Text(pageSubtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(PulsePalette.muted)
                }
            }

            Spacer(minLength: 8)

            if page == .overview {
                Button(action: viewModel.refresh) {
                    ZStack {
                        Circle().fill(PulsePalette.surfaceRaised)
                        AnimatedRefreshIcon(isSpinning: viewModel.isScanning)
                    }
                    .frame(width: 32, height: 32)
                }
                .buttonStyle(PulsePressStyle())
                .disabled(viewModel.isScanning)
                .help(viewModel.t("action.sync"))
            }
        }
        .frame(width: Self.contentWidth - 28, height: 58)
        .padding(.horizontal, 14)
    }

    @ViewBuilder
    private var accountContext: some View {
        if let account = viewModel.selectedAccount {
            Menu {
                ForEach(viewModel.accountSnapshots) { item in
                    Menu {
                        Button {
                            viewModel.switchAccount(to: item, mode: .monitorOnly)
                        } label: {
                            Text(viewModel.t("account.monitorOnly"))
                        }
                        Button {
                            viewModel.switchAccount(to: item, mode: .activateCodex)
                        } label: {
                            Text(viewModel.t("account.activateCodex"))
                        }
                    } label: {
                        Text(
                            "\(item.id == account.id ? "● " : "")\(viewModel.accountName(item))"
                                + (viewModel.accountIsCodexLogin(item) ? " · CODEX" : "")
                        )
                    }
                }
                Divider()
                Menu(viewModel.t("account.addMore")) { accountAddActions }
                if viewModel.hasPendingOAuth {
                    Button(viewModel.t("account.oauthCheck")) { viewModel.checkPendingOAuth() }
                }
            } label: {
                accountContextLabel(account)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(
                width: heroAccountLabelWidth(account),
                height: 15,
                alignment: .leading
            )
        } else {
            Menu {
                accountAddActions
            } label: {
                HStack(spacing: 5) {
                    PulseIcon(name: "account").frame(width: 12, height: 12)
                    Text(viewModel.isScanning ? viewModel.t("account.connecting") : viewModel.t("account.addCodex"))
                }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(PulsePalette.accent)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    private func accountContextLabel(_ account: CodexAccountUsageSnapshot) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(viewModel.selectedAccountIsActive ? PulsePalette.lime : PulsePalette.warning)
                .frame(width: 5, height: 5)
            Text(viewModel.accountName(account))
                .lineLimit(1)
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(PulsePalette.muted)
        .contentShape(Rectangle())
    }

    private var pageTitle: String {
        switch page {
        case .overview: viewModel.t("page.overview")
        case .tiboSignal: viewModel.t("page.tiboSignal")
        case .sessions: viewModel.t("page.ledger")
        case .settings: viewModel.t("page.console")
        case .tokenLogin: viewModel.t("page.tokenLogin")
        case .developer: viewModel.t("page.developer")
        }
    }

    private var pageSubtitle: String {
        switch page {
        case .overview: ""
        case .tiboSignal: viewModel.t("subtitle.tiboSignal")
        case .sessions: viewModel.t("subtitle.ledger")
        case .settings: viewModel.t("subtitle.console")
        case .tokenLogin: viewModel.t("subtitle.tokenLogin")
        case .developer: ""
        }
    }

    private var overview: some View {
        VStack(spacing: 0) {
            overviewHero

            VStack(spacing: 10) {
                if let account = viewModel.selectedAccount {
                    if let error = viewModel.accountErrorMessage {
                        inlineFailure(error, title: viewModel.t("account.stale"))
                    }
                    overviewUpdates(account)
                } else if viewModel.isScanning {
                    accountLoadingSurface
                } else {
                    inlineFailure(
                        viewModel.accountErrorMessage ?? viewModel.t("account.noReadable"),
                        title: viewModel.t("account.unavailable")
                    )
                }

                if viewModel.tiboMonitoringEnabled {
                    tiboGlobalSignalRow
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
        .frame(width: Self.contentWidth)
        .background {
            ZStack {
                LinearGradient(
                    stops: [
                        .init(color: PulsePalette.heroStart, location: 0),
                        .init(color: PulsePalette.heroEnd, location: 0.50),
                        .init(color: PulsePalette.heroEnd.opacity(0.42), location: 0.58),
                        .init(color: PulsePalette.heroEnd.opacity(0), location: 0.68),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                RadialGradient(
                    colors: [PulsePalette.heroSheen, .clear],
                    center: .topTrailing,
                    startRadius: 0,
                    endRadius: 240
                )
                .blur(radius: 24)
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: PulsePalette.ink, location: 0),
                            .init(color: PulsePalette.ink, location: 0.52),
                            .init(color: PulsePalette.ink.opacity(0), location: 0.68),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }
            .allowsHitTesting(false)
        }
    }

    private var overviewHero: some View {
        ZStack {
            VStack(spacing: 8) {
                overviewHeroHeader

                if viewModel.activeTaskCount > 1 {
                    liveTaskSwitcher
                }

                liveContextCard
            }
            .padding(.horizontal, 14)
            // Keep enough overlap for the atmospheric fade without leaving a
            // dead band between the hero metrics and the Updates controls.
            .padding(.bottom, 14)
        }
        // The token-details drawer is intentionally a fixed-size floating
        // surface. Keep the whole hero above the Updates sibling so no labels
        // or controls can bleed through the opaque drawer while it is open.
        .zIndex(10)
    }

    private var overviewHeroHeader: some View {
        HStack(spacing: 10) {
            Image("TokenPulseBrandMark")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: 36, height: 36)
                .foregroundStyle(PulsePalette.heroInk)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(viewModel.t("page.overview"))
                    .font(.system(size: 16, weight: .semibold, design: .default))
                    .foregroundStyle(PulsePalette.heroInk)
                heroAccountContext
            }

            Spacer(minLength: 8)

            Button(action: viewModel.refresh) {
                ZStack {
                    Circle().fill(PulsePalette.heroTile)
                    AnimatedRefreshIcon(
                        isSpinning: viewModel.isScanning,
                        idleColor: PulsePalette.heroInk,
                        spinningColor: PulsePalette.heroInk
                    )
                }
                .frame(width: 32, height: 32)
            }
            .buttonStyle(PulsePressStyle())
            .disabled(viewModel.isScanning)
            .help(viewModel.t("action.sync"))
        }
        .frame(height: 52)
    }

    @ViewBuilder
    private var heroAccountContext: some View {
        if let account = viewModel.selectedAccount {
            ZStack(alignment: .leading) {
                Menu {
                    ForEach(viewModel.accountSnapshots) { item in
                        Menu {
                            Button(viewModel.t("account.monitorOnly")) {
                                viewModel.switchAccount(to: item, mode: .monitorOnly)
                            }
                            Button(viewModel.t("account.activateCodex")) {
                                viewModel.switchAccount(to: item, mode: .activateCodex)
                            }
                        } label: {
                            Text("\(item.id == account.id ? "● " : "")\(viewModel.accountName(item))")
                        }
                    }
                    Divider()
                    Menu(viewModel.t("account.addMore")) { accountAddActions }
                } label: {
                    // The native borderless Menu owns the click target only.
                    // Its macOS Light appearance otherwise forces label text
                    // to black, regardless of SwiftUI's foreground style.
                    Color.clear
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Keep the visible label outside the native Menu so AppKit
                // cannot recolor it and so its width participates in layout.
                heroAccountLabel(account)
                    .allowsHitTesting(false)
            }
            .frame(width: heroAccountLabelWidth(account), height: 15, alignment: .leading)
            .accessibilityLabel(viewModel.accountName(account))
        } else {
            Button(viewModel.t("account.addCodex")) { page = .tokenLogin }
                .font(.system(size: 12, weight: .semibold, design: .default))
                .buttonStyle(.plain)
                .foregroundStyle(PulsePalette.heroMuted)
        }
    }

    private func heroAccountLabel(_ account: CodexAccountUsageSnapshot) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(viewModel.selectedAccountIsActive ? PulsePalette.heroInk : PulsePalette.warning)
                .frame(width: 5, height: 5)
            Text(viewModel.accountName(account))
                .foregroundColor(.white.opacity(0.82))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .font(.system(size: 12, weight: .semibold, design: .default))
    }

    private func heroAccountLabelWidth(_ account: CodexAccountUsageSnapshot) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let textWidth = ceil(
            (viewModel.accountName(account) as NSString)
                .size(withAttributes: [.font: font])
                .width
        )
        return textWidth + 10 // 5pt state dot + 5pt spacing
    }

    private func overviewUpdates(_ account: CodexAccountUsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Text(viewModel.t("overview.updates"))
                    .font(.system(size: 14, weight: .semibold, design: .default))
                    .foregroundStyle(PulsePalette.ink)

                Spacer(minLength: 6)

                Text(viewModel.syncStatusText)
                    .font(.system(size: 12, weight: .semibold, design: .default))
                    .foregroundStyle(PulsePalette.faint)
                    .lineLimit(1)
            }

            HStack(spacing: 3) {
                overviewPanelButton(.task, title: viewModel.t("overview.tab.task"))
                overviewPanelButton(.quota, title: viewModel.t("overview.tab.quota"))
                overviewPanelButton(.account, title: viewModel.t("overview.tab.account"))
            }
            .padding(3)
            .background(PulsePalette.surface, in: Capsule())

            // Keep all three panels in one fixed local layer. Switching tabs
            // only changes opacity; it never changes the dashboard's intrinsic
            // height or asks AppKit to rebuild the native NSMenu.
            ZStack(alignment: .top) {
                taskUpdateSurface
                    .opacity(overviewPanel == .task ? 1 : 0)
                    .allowsHitTesting(overviewPanel == .task)
                    .accessibilityHidden(overviewPanel != .task)

                quotaUpdateSurface(account, forecast: viewModel.selectedQuotaForecast)
                    .opacity(overviewPanel == .quota ? 1 : 0)
                    .allowsHitTesting(overviewPanel == .quota)
                    .accessibilityHidden(overviewPanel != .quota)

                accountUpdateSurface(account)
                    .opacity(overviewPanel == .account ? 1 : 0)
                    .allowsHitTesting(overviewPanel == .account)
                    .accessibilityHidden(overviewPanel != .account)
            }
            .frame(height: Self.overviewPanelHeight, alignment: .top)
            .clipped()
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: overviewPanel)
        }
    }

    private func overviewPanelButton(_ panel: OverviewPanel, title: String) -> some View {
        Button {
            overviewPanel = panel
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .default))
                .foregroundStyle(overviewPanel == panel ? PulsePalette.ink : PulsePalette.muted)
                .frame(maxWidth: .infinity)
                .frame(height: 27)
                .background(
                    overviewPanel == panel ? PulsePalette.surfaceRaised : Color.clear,
                    in: Capsule()
                )
                .contentShape(Capsule())
        }
        .buttonStyle(PulsePressStyle())
    }

    @ViewBuilder
    private var taskUpdateSurface: some View {
        if let context = viewModel.liveContext {
            VStack(spacing: 10) {
                HStack(spacing: 7) {
                    UpdateMetricTile(
                        title: viewModel.t("live.currentTurn"),
                        value: DisplayFormat.tokens(context.currentTurnUsage.totalTokens)
                    )
                    UpdateMetricTile(
                        title: viewModel.t("live.total"),
                        value: DisplayFormat.tokens(context.taskTotal.totalTokens)
                    )
                    UpdateMetricTile(
                        title: viewModel.t("live.apiEstimate"),
                        value: viewModel.liveRequestAPIUSD.map { DisplayFormat.usd($0.total) } ?? "—"
                    )
                }

                HStack(spacing: 7) {
                    PulseIcon(name: "tasks")
                        .frame(width: 13, height: 13)
                        .foregroundStyle(PulsePalette.accent)
                    MarqueeLabel(
                        text: "\(context.projectName) · \(PricingCatalog.normalize(model: context.model))",
                        font: .system(size: 12, weight: .semibold, design: .default),
                        color: PulsePalette.muted
                    )
                }
            }
            .padding(11)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(PulsePalette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else {
            accountLoadingSurface
        }
    }

    private func quotaUpdateSurface(_ account: CodexAccountUsageSnapshot, forecast: QuotaForecast?) -> some View {
        let windows = Array(account.allWindows.prefix(3))
        return VStack(spacing: 10) {
            if let primary = windows.first {
                VStack(spacing: 7) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(compactQuotaTitle(primary))
                            .font(.system(size: 13, weight: .semibold, design: .default))
                            .foregroundStyle(PulsePalette.ink)
                        Spacer()
                        Text("\(Int(primary.remainingPercent.rounded()))%")
                            .font(.system(size: 24, weight: .semibold, design: .default))
                            .foregroundStyle(quotaAccent(primary))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }

                    ContextUsageBar(
                        progress: primary.remainingPercent / 100,
                        color: quotaAccent(primary)
                    )
                    .frame(height: 7)

                    HStack(spacing: 6) {
                        PulseIcon(name: "timer").frame(width: 11, height: 11)
                        Text(compactQuotaReset(primary))
                        Spacer()
                        if let forecast {
                            Text(forecastHeadline(forecast))
                                .foregroundStyle(PulsePalette.ink)
                        }
                    }
                    .font(.system(size: 12, weight: .semibold, design: .default))
                    .foregroundStyle(PulsePalette.faint)
                }
            } else {
                Text(viewModel.t("quota.empty"))
                    .font(.system(size: 13, weight: .semibold, design: .default))
                    .foregroundStyle(PulsePalette.muted)
                    .frame(maxWidth: .infinity, minHeight: 62)
            }

            if windows.count > 1 {
                HStack(spacing: 7) {
                    ForEach(Array(windows.dropFirst())) { window in
                        UpdateMetricTile(
                            title: compactQuotaTitle(window),
                            value: "\(Int(window.remainingPercent.rounded()))%",
                            accent: quotaAccent(window)
                        )
                    }
                }
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(PulsePalette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func accountUpdateSurface(_ account: CodexAccountUsageSnapshot) -> some View {
        let today = account.accountTokenUsage?.latestDailyUsage.map { DisplayFormat.tokens($0.tokens) } ?? "—"
        let lifetime = account.accountTokenUsage?.summary.lifetimeTokens.map { DisplayFormat.tokens($0) } ?? "—"
        let todayLabel = viewModel.t("account.today", "").trimmingCharacters(in: .whitespacesAndNewlines)
        let lifetimeLabel = viewModel.t("account.lifetime", "").trimmingCharacters(in: .whitespacesAndNewlines)
        return HStack(spacing: 7) {
            UpdateMetricTile(title: todayLabel, value: today)
            UpdateMetricTile(title: lifetimeLabel, value: lifetime)
            UpdateMetricTile(title: viewModel.t("metric.credits"), value: creditText(account.credits))
        }
        .padding(11)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(PulsePalette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
        HStack(spacing: 2) {
            ForEach(Array(viewModel.activeLiveContexts.prefix(4).enumerated()), id: \.element.id) { index, context in
                let selected = context.id == viewModel.liveContext?.id
                Button {
                    viewModel.selectLiveContext(context.id)
                } label: {
                    VStack(spacing: 1) {
                        Text("\(viewModel.t("overview.tab.task")) \(index + 1)")
                            .font(.system(size: 12, weight: .semibold, design: .default))
                        Text(DisplayFormat.tokens(context.contextInputTokens))
                            .font(.system(size: 13, weight: .semibold, design: .default))
                            .monospacedDigit()
                    }
                    .foregroundStyle(selected ? PulsePalette.heroInk : PulsePalette.heroMuted)
                    .frame(maxWidth: .infinity)
                    .frame(height: 39)
                    .overlay(alignment: .bottom) {
                        Capsule()
                            .fill(selected ? PulsePalette.heroInk : Color.clear)
                            .frame(width: 18, height: 2)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PulsePressStyle())
                .help(context.displayTitle)
            }

            if viewModel.activeTaskCount > 4 {
                Menu {
                    ForEach(viewModel.activeLiveContexts.dropFirst(4)) { context in
                        Button(context.displayTitle) { viewModel.selectLiveContext(context.id) }
                    }
                } label: {
                    Text("+\(viewModel.activeTaskCount - 4)")
                        .font(.system(size: 12, weight: .semibold, design: .default))
                        .foregroundStyle(PulsePalette.heroInk)
                        .frame(width: 34, height: 39)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
    }

    private func cycleLiveTask(by offset: Int) {
        let contexts = viewModel.activeLiveContexts
        guard contexts.count > 1 else { return }
        let current = contexts.firstIndex { $0.id == viewModel.liveContext?.id } ?? 0
        let next = (current + offset + contexts.count) % contexts.count
        viewModel.selectLiveContext(contexts[next].id)
    }

    @ViewBuilder
    private var liveContextCard: some View {
        if let context = viewModel.liveContext {
            LiveContextCard(
                context: context,
                apiUSD: viewModel.liveRequestAPIUSD,
                showAPIEstimate: viewModel.showAPIEstimate,
                showRuntimeWindow: viewModel.showRuntimeWindow,
                initiallyExpanded: initiallyExpandedLiveDetails
            )
        } else {
            HStack(spacing: 12) {
                SignalSkeleton()
                    .frame(width: 76, height: 76)
                VStack(alignment: .leading, spacing: 5) {
                    Text(viewModel.t("live.capture"))
                        .font(.system(size: 14, weight: .semibold, design: .default))
                        .foregroundStyle(PulsePalette.ink)
                    Text(viewModel.liveContextErrorMessage ?? viewModel.t("live.waiting"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(PulsePalette.muted)
                        .lineLimit(1)
                    Button(viewModel.t("action.rediscover")) { viewModel.liveContextTick(forceDiscover: true) }
                        .buttonStyle(PulseTextButtonStyle())
                }
                Spacer()
            }
            .padding(16)
                .frame(minHeight: 116)
        }
    }

    private func accountSummarySurface(_ account: CodexAccountUsageSnapshot) -> some View {
        let today = account.accountTokenUsage?.latestDailyUsage.map { DisplayFormat.tokens($0.tokens) } ?? "—"
        let lifetime = account.accountTokenUsage?.summary.lifetimeTokens.map { DisplayFormat.tokens($0) } ?? "—"
        let todayLabel = viewModel.t("account.today", "").trimmingCharacters(in: .whitespacesAndNewlines)
        let lifetimeLabel = viewModel.t("account.lifetime", "").trimmingCharacters(in: .whitespacesAndNewlines)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                PulseIcon(name: "account")
                    .frame(width: 15, height: 15)
                    .foregroundStyle(PulsePalette.ink)
                Text(viewModel.t("account.total"))
                    .font(.system(size: 13, weight: .semibold, design: .default))
                    .foregroundStyle(PulsePalette.ink)
                Spacer()
            }

            HStack(spacing: 0) {
                FlatMetric(title: todayLabel, value: today, horizontalPadding: 4)
                PulsePalette.divider.frame(width: 1, height: 31)
                FlatMetric(title: lifetimeLabel, value: lifetime, horizontalPadding: 4)
                PulsePalette.divider.frame(width: 1, height: 31)
                FlatMetric(
                    title: viewModel.t("metric.credits"),
                    value: creditText(account.credits),
                    horizontalPadding: 4
                )
                PulsePalette.divider.frame(width: 1, height: 31)
                FlatMetric(
                    title: viewModel.t("ledger.localShort"),
                    value: viewModel.isScanning && viewModel.snapshot.records.isEmpty
                        ? viewModel.t("ledger.indexing")
                        : DisplayFormat.tokens(viewModel.localConversationTotalUsage.totalTokens),
                    horizontalPadding: 4,
                    action: { page = .sessions }
                )
                .help(viewModel.t("local.exactHelp"))
            }
        }
        .padding(11)
        .background(PulsePalette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(PulsePalette.divider.opacity(0.72), lineWidth: 1)
        }
        .help(viewModel.t("account.serverTotal"))
    }

    private func quotaSurface(_ account: CodexAccountUsageSnapshot, forecast: QuotaForecast?) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text(viewModel.t("quota.radar"))
                    .font(.system(size: 14, weight: .semibold, design: .default))
                    .foregroundStyle(PulsePalette.ink)
                Spacer()
                Text(viewModel.t("quota.windows", account.allWindows.count))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(PulsePalette.faint)
            }
            .frame(height: 22)

            if account.allWindows.isEmpty {
                Text(viewModel.t("quota.empty"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(PulsePalette.muted)
                    .frame(maxWidth: .infinity, minHeight: 54)
            } else {
                VStack(spacing: 6) {
                    ForEach(Array(Array(account.allWindows.prefix(5)).enumerated()), id: \.element.id) { index, window in
                        QuotaPulseRow(window: window, index: index)
                    }
                }
            }

            if let forecast {
                quotaForecastRow(forecast)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(PulsePalette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(PulsePalette.divider.opacity(0.72), lineWidth: 1)
        }
    }

    private func quotaForecastRow(_ forecast: QuotaForecast) -> some View {
        HStack(spacing: 8) {
            PulseIcon(name: "timer")
                .frame(width: 13, height: 13)
                .foregroundStyle(PulsePalette.ink)
            Text(forecastHeadline(forecast))
                .foregroundStyle(PulsePalette.ink)
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 0)
        }
        .font(.system(size: 12, weight: .semibold, design: .default))
        .lineLimit(1)
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background(PulsePalette.surfaceRaised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .help(forecastEvidence(forecast))
        .accessibilityElement(children: .combine)
    }

    private var tiboGlobalSignalRow: some View {
        Button { page = .tiboSignal } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(tiboCycleColor.opacity(0.14))
                    Circle().fill(tiboCycleColor).frame(width: 7, height: 7)
                }
                .frame(width: 26, height: 26)

                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.t("tibo.cycle.title"))
                        .font(.system(size: 13, weight: .semibold, design: .default))
                        .foregroundStyle(PulsePalette.ink)
                    MarqueeLabel(
                        text: viewModel.tiboCycleOverviewText,
                        font: .system(size: 12, weight: .semibold, design: .default),
                        color: tiboCycleColor
                    )
                    .frame(width: 112)
                }

                Spacer(minLength: 2)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(viewModel.tiboCycleNextLabel)
                        .font(.system(size: 12, weight: .medium, design: .default))
                        .foregroundStyle(PulsePalette.faint)
                    MarqueeLabel(
                        text: viewModel.tiboCycleNextText,
                        font: .system(size: 12, weight: .semibold, design: .default),
                        color: PulsePalette.ink
                    )
                    .frame(width: 118)
                }
                .frame(width: 118, alignment: .trailing)
            }
            .padding(.horizontal, 11)
            .frame(height: 52)
            .background(PulsePalette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(PulsePressStyle())
        .help(viewModel.t("tibo.globalHelp"))
        .accessibilityLabel(viewModel.t("tibo.cycle.title"))
        .accessibilityValue(viewModel.tiboCompactStatusText)
    }

    private var tiboCycleColor: Color {
        let cycle = viewModel.tiboResetCycle
        guard let signal = cycle.activeSignal ?? cycle.lastConfirmedSignal else {
            return viewModel.tiboSignalSnapshot.sourceStatus == .healthy
                ? PulsePalette.faint
                : PulsePalette.coral
        }
        switch signal.status {
        case .confirmed: return PulsePalette.accent
        case .expected: return PulsePalette.warning
        case .candidate: return PulsePalette.warning
        }
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
        let cycle = viewModel.tiboResetCycle
        return VStack(spacing: 10) {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle().fill(tiboCycleColor.opacity(0.14))
                        Circle().fill(tiboCycleColor).frame(width: 8, height: 8)
                    }
                    .frame(width: 28, height: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(viewModel.tiboCycleStateText)
                            .font(.system(size: 14, weight: .semibold, design: .default))
                            .foregroundStyle(PulsePalette.ink)
                        Text(viewModel.t("tibo.cycle.publicScope"))
                            .font(.system(size: 12, weight: .medium, design: .default))
                            .foregroundStyle(PulsePalette.muted)
                    }

                    Spacer(minLength: 4)

                    if viewModel.tiboCycleHasSource {
                        Button { viewModel.openTiboCycleSource() } label: {
                            HStack(spacing: 5) {
                                Text(viewModel.t("tibo.cycle.openPost"))
                                PulseIcon(name: "arrow-right").frame(width: 9, height: 9)
                            }
                        }
                        .buttonStyle(PulseTextButtonStyle())
                    }

                    Button { viewModel.tiboSignalTick(force: true) } label: {
                        AnimatedRefreshIcon(isSpinning: viewModel.isTiboSignalRefreshing)
                            .frame(width: 13, height: 13)
                            .frame(width: 26, height: 26)
                            .background(PulsePalette.surfaceRaised, in: Circle())
                    }
                    .buttonStyle(PulsePressStyle())
                    .disabled(viewModel.isTiboSignalRefreshing)
                    .help(viewModel.t("tibo.detail.refresh"))
                }
                .padding(.horizontal, 13)
                .frame(height: 58)

                PulsePalette.divider.frame(height: 1)

                tiboCycleTrack(cycle)
                    .padding(.horizontal, 16)
                    .padding(.top, 14)

                HStack(alignment: .top, spacing: 0) {
                    tiboCyclePoint(
                        title: viewModel.t("tibo.cycle.lastConfirmed"),
                        value: viewModel.tiboCycleLastConfirmedText,
                        color: cycle.lastConfirmedSignal == nil ? PulsePalette.faint : PulsePalette.accent,
                        source: cycle.lastConfirmedSignal
                    )
                    tiboCyclePoint(
                        title: viewModel.t("tibo.cycle.currentSignal"),
                        value: viewModel.tiboCycleCurrentSignalText,
                        color: cycle.activeSignal == nil ? PulsePalette.faint : PulsePalette.warning,
                        source: cycle.activeSignal
                    )
                    tiboCyclePoint(
                        title: viewModel.tiboCycleNextLabel,
                        value: viewModel.tiboCycleNextText,
                        color: cycle.displayedNextResetAt == nil ? PulsePalette.faint : tiboCycleColor
                    )
                }
                .padding(.horizontal, 9)
                .padding(.top, 8)
                .padding(.bottom, 15)
            }
            .background(PulsePalette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(PulsePalette.divider.opacity(0.72), lineWidth: 1)
            }

            if cycle.baselineIsProvisional {
                HStack(spacing: 8) {
                    PulseIcon(name: "timer")
                        .frame(width: 13, height: 13)
                        .foregroundStyle(PulsePalette.warning)
                    Text(viewModel.t("tibo.cycle.provisional"))
                        .font(.system(size: 12, weight: .semibold, design: .default))
                        .foregroundStyle(PulsePalette.muted)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(PulsePalette.surfaceRaised, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    private func tiboCycleTrack(_ cycle: TiboResetCycle) -> some View {
        HStack(spacing: 0) {
            tiboCycleDot(color: cycle.lastConfirmedSignal == nil ? PulsePalette.faint : PulsePalette.accent, filled: cycle.lastConfirmedSignal != nil)
            Rectangle().fill(PulsePalette.divider).frame(height: 2)
            tiboCycleDot(color: cycle.activeSignal == nil ? PulsePalette.faint : PulsePalette.warning, filled: cycle.activeSignal != nil)
            Rectangle().fill(PulsePalette.divider).frame(height: 2)
            tiboCycleDot(color: cycle.displayedNextResetAt == nil ? PulsePalette.faint : tiboCycleColor, filled: cycle.displayedNextResetAt != nil)
        }
        .frame(height: 14)
    }

    private func tiboCycleDot(color: Color, filled: Bool) -> some View {
        ZStack {
            Circle().fill(color.opacity(filled ? 0.18 : 0.08))
            Circle()
                .fill(filled ? color : Color.clear)
                .overlay(Circle().stroke(color.opacity(0.7), lineWidth: 1.5))
                .padding(4)
        }
        .frame(width: 14, height: 14)
    }

    private func tiboCyclePoint(
        title: String,
        value: String,
        color: Color,
        source: TiboResetSignal? = nil
    ) -> some View {
        Button {
            if let source { viewModel.openTiboSignal(source) }
        } label: {
            VStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 12, weight: .medium, design: .default))
                    .foregroundStyle(PulsePalette.faint)
                    .fixedSize()
                HStack(spacing: 4) {
                    Text(value)
                        .monospacedDigit()
                        .fixedSize()
                    if source != nil {
                        PulseIcon(name: "arrow-right").frame(width: 7, height: 7)
                    }
                }
                .font(.system(size: 12, weight: .semibold, design: .default))
                .foregroundStyle(color)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PulsePressStyle())
        .disabled(source == nil)
        .frame(maxWidth: .infinity)
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
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(PulsePalette.surfaceRaised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.horizontal, 12)

            Text(viewModel.t("sessions.notice"))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(PulsePalette.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)

            VStack(spacing: 7) {
                if visibleSessions.isEmpty {
                    Text(viewModel.t("sessions.empty"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(PulsePalette.muted)
                        .frame(maxWidth: .infinity, minHeight: 72)
                        .background(PulsePalette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    ForEach(visibleSessions) { session in
                        PulseSessionRow(
                            session: session,
                            title: viewModel.sessionTitle(session),
                            subtitle: viewModel.sessionSubtitle(session)
                        )
                    }
                }
            }
            .padding(.horizontal, 12)

            Spacer(minLength: 0)

            if sessionPageCount > 1 {
                sessionPager
            }
        }
        .padding(.bottom, 12)
        .frame(height: Self.primaryPageContentHeight, alignment: .top)
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
            .transition(pageTransition)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 9)
        .frame(height: Self.primaryPageContentHeight, alignment: .top)
        .animation(reduceMotion ? nil : .spring(response: 0.30, dampingFraction: 0.88), value: consolePanel)
    }

    private var consolePanelStrip: some View {
        HStack(spacing: 6) {
            consolePanelButton(.appearance, icon: "appearance")
            consolePanelButton(.live, icon: "pulse")
            consolePanelButton(.account, icon: "account")
            consolePanelButton(.data, icon: "data")
        }
        .padding(5)
        .background(PulsePalette.surface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(PulsePalette.divider.opacity(isLightAppearance ? 0.9 : 0.45), lineWidth: 1)
        }
        .help(viewModel.t("console.note"))
    }

    private func consolePanelButton(_ panel: ConsolePanel, icon: String) -> some View {
        Button { consolePanel = panel } label: {
            VStack(spacing: 3) {
                PulseIcon(name: icon).frame(width: 13, height: 13)
                Text(consolePanelTitle(panel))
                    .font(.system(size: 12, weight: .semibold, design: .default))
                    .lineLimit(1)
            }
            .foregroundStyle(consolePanel == panel ? strongSelectionInk : PulsePalette.muted)
            .frame(maxWidth: .infinity, minHeight: 36)
            .background(
                consolePanel == panel ? strongSelection : Color.clear,
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
        }
        .buttonStyle(PulsePressStyle())
    }

    private func consolePanelTitle(_ panel: ConsolePanel) -> String {
        switch panel {
        case .appearance: viewModel.t("console.theme")
        case .live: viewModel.t("console.live")
        case .account: viewModel.t("console.accounts")
        case .data: viewModel.t("console.data")
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
                Button { page = .developer } label: {
                    SettingsValueRow(title: viewModel.t("console.developer"), value: "Zijiu522", showsChevron: true)
                }.buttonStyle(PulsePressStyle())
                settingsDivider
                SettingsValueRow(title: viewModel.t("console.version"), value: appVersionDisplay)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var tokenLogin: some View {
        let inspection = viewModel.inspectCredentialText(credentialText)
        return VStack(spacing: 8) {
            HStack(spacing: 5) {
                formatBadge("TOKEN", color: PulsePalette.accent)
                formatBadge("JSON / JSONL", color: PulsePalette.muted)
                formatBadge("SUB2 · CPA · COCKPIT", color: PulsePalette.muted)
                Spacer(minLength: 0)
            }

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
                    Text(viewModel.t("account.tokenInputPlaceholder"))
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(PulsePalette.faint)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                }
                PrivateCredentialEditor(text: $credentialText)
                    .padding(7)
            }
            .frame(height: 148)

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
                HStack(spacing: 8) {
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
                Text(viewModel.t("account.tokenPrivacy"))
                    .font(.system(size: 12, weight: .semibold))
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
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    private func formatBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold, design: .default))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .frame(height: 20)
            .background(color.opacity(0.11), in: Capsule())
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
                        .font(.system(size: 12, weight: .semibold, design: .default))
                        .foregroundStyle(PulsePalette.ink)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, minHeight: 46)
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
        HStack(spacing: 8) {
            Text(title)
                .foregroundStyle(PulsePalette.ink)
            Spacer(minLength: 8)
            Menu(content: content) {
                Text(value)
                    .foregroundStyle(PulsePalette.accent)
                    .lineLimit(1)
                    .font(.system(size: 12, weight: .semibold, design: .default))
                    .padding(.horizontal, 8)
                    .frame(height: 25)
                    .background(PulsePalette.accent.opacity(0.10), in: Capsule())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 13)
        .frame(height: 42)
        .contentShape(Rectangle())
    }

    private var developer: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 34)

            ZStack {
                Circle()
                    .fill(PulsePalette.accent.opacity(isLightAppearance ? 0.08 : 0.13))
                    .frame(width: 204, height: 204)

                Circle()
                    .fill(PulsePalette.surfaceRaised)
                    .frame(width: 166, height: 166)

                Image("DeveloperAvatar")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 146, height: 146)
                    .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .stroke(PulsePalette.surfaceRaised, lineWidth: 3)
                    }
            }
            .frame(height: 210)

            VStack(spacing: 7) {
                Text("Zijiu522")
                    .font(.system(size: 28, weight: .semibold, design: .default))
                    .foregroundStyle(PulsePalette.ink)
                Text(viewModel.t("developer.role"))
                    .font(.system(size: 14, weight: .medium, design: .default))
                    .foregroundStyle(PulsePalette.muted)
                Text(viewModel.t("developer.tagline"))
                    .font(.system(size: 13, weight: .medium, design: .default))
                    .foregroundStyle(PulsePalette.ink)
            }

            Spacer(minLength: 34)

            HStack(spacing: 13) {
                Image("TokenPulseAppIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.t("developer.project"))
                        .font(.system(size: 12, weight: .medium, design: .default))
                        .foregroundStyle(PulsePalette.muted)
                    Text(viewModel.t("developer.product"))
                        .font(.system(size: 15, weight: .semibold, design: .default))
                        .foregroundStyle(PulsePalette.ink)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 15)
            .frame(height: 78)
            .background(PulsePalette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(PulsePalette.divider.opacity(0.72), lineWidth: 1)
            }

            HStack(spacing: 8) {
                Text(viewModel.t("console.version"))
                    .font(.system(size: 12, weight: .medium, design: .default))
                    .foregroundStyle(PulsePalette.muted)
                Spacer(minLength: 8)
                Text(appVersionDisplay)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(PulsePalette.ink)
                    .monospacedDigit()
            }
            .padding(.horizontal, 4)
            .frame(height: 44)

            Spacer(minLength: 14)
        }
        .frame(width: Self.contentWidth - 24, height: Self.primaryPageContentHeight)
        .padding(.horizontal, 12)
    }

    private var appVersionDisplay: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "2.1.0"
        let build = info?["CFBundleVersion"] as? String ?? "22"
        return "\(version) (\(build))"
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

    private var footer: some View {
        HStack(spacing: 18) {
            footerTab(.overview, icon: "pulse", title: viewModel.t("page.overview"))
            footerTab(.sessions, icon: "tasks", title: viewModel.t("page.ledger"))
            footerTab(.settings, icon: "console", title: viewModel.t("page.console"))

            Spacer(minLength: 12)

            Menu {
                Button(viewModel.t("page.tiboSignal")) { page = .tiboSignal }
                Button(viewModel.t("page.developer")) { page = .developer }
                Divider()
                Button(viewModel.t("action.exportCSV"), action: viewModel.exportCSV)
                Button(viewModel.t("action.exportJSON"), action: viewModel.exportJSON)
                Divider()
                Button(viewModel.t("action.quit")) { NSApp.terminate(nil) }
            } label: {
                ZStack(alignment: .topTrailing) {
                    PulseIcon(name: "more")
                        .frame(width: 15, height: 15)
                        .foregroundStyle(PulsePalette.selectionInk)
                        .frame(width: 34, height: 34)
                        .background(PulsePalette.ink, in: Circle())
                    Circle()
                        .fill(viewModel.isScanning ? PulsePalette.warning : PulsePalette.lime)
                        .frame(width: 6, height: 6)
                        .overlay(Circle().stroke(PulsePalette.ink, lineWidth: 2))
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .frame(height: 46)
        .padding(.horizontal, 18)
        .background(PulsePalette.surface.opacity(0.18))
    }

    private func footerTab(_ destination: MenuPopoverPage, icon: String, title: String) -> some View {
        let selected = page == destination
        return Button {
            page = destination
        } label: {
            PulseIcon(name: icon)
                .frame(width: 16, height: 16)
                .foregroundStyle(selected ? strongSelectionInk : PulsePalette.faint)
                .frame(width: 34, height: 34)
                .background(selected ? strongSelection : Color.clear, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(PulsePressStyle())
        .help(title)
        .accessibilityLabel(title)
    }

    private func inlineFailure(_ error: String, title: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            PulseIcon(name: "warning").frame(width: 16, height: 16)
                .foregroundStyle(PulsePalette.coral)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .default))
                    .foregroundStyle(PulsePalette.ink)
                Text(error)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(PulsePalette.muted)
                    .lineLimit(1)
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

private enum LiveHeroMetric: String {
    case context
    case task
}

private struct LiveContextCard: View {
    let context: CodexLiveContextSnapshot
    let apiUSD: CostBreakdown?
    let showAPIEstimate: Bool
    let showRuntimeWindow: Bool

    @EnvironmentObject private var viewModel: DashboardViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDetailsExpanded: Bool
    @State private var metric: LiveHeroMetric = .context

    init(
        context: CodexLiveContextSnapshot,
        apiUSD: CostBreakdown?,
        showAPIEstimate: Bool,
        showRuntimeWindow: Bool,
        initiallyExpanded: Bool = false
    ) {
        self.context = context
        self.apiUSD = apiUSD
        self.showAPIEstimate = showAPIEstimate
        self.showRuntimeWindow = showRuntimeWindow
        _isDetailsExpanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        VStack(spacing: 9) {
            HStack(spacing: 7) {
                LivePulseBadge(
                    isFresh: Date().timeIntervalSince(context.updatedAt) < 20,
                    onHero: true
                )
                MarqueeLabel(
                    text: context.displayTitle,
                    font: .system(size: 13, weight: .semibold, design: .default),
                    color: PulsePalette.heroInk
                )
                Button(action: toggleDetails) {
                    PulseIcon(name: "chevron-down")
                        .frame(width: 8, height: 8)
                        .rotationEffect(.degrees(isDetailsExpanded ? 180 : 0))
                        .animation(
                            reduceMotion ? nil : .easeInOut(duration: 0.14),
                            value: isDetailsExpanded
                        )
                        .foregroundStyle(PulsePalette.heroInk)
                        .frame(width: 26, height: 26)
                        .background(PulsePalette.heroTile, in: Circle())
                }
                .buttonStyle(PulsePressStyle())
                .help(viewModel.t("console.details"))
            }

            HStack(spacing: 2) {
                heroMetricButton(.context, title: viewModel.t("live.currentContext"))
                heroMetricButton(.task, title: viewModel.t("live.taskUsageTotal"))
            }
            .padding(3)
            .frame(width: 270)
            .background(PulsePalette.heroTile.opacity(0.54), in: Capsule())

            VStack(spacing: 0) {
                Text(heroValue)
                    .font(.system(size: 52, weight: .medium, design: .default))
                    .foregroundStyle(PulsePalette.heroInk)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(heroCaption)
                    .font(.system(size: 12, weight: .semibold, design: .default))
                    .foregroundStyle(PulsePalette.heroMuted)
            }

            Group {
                if metric == .context {
                    VStack(spacing: 5) {
                        HStack(spacing: 8) {
                            Text(heroCapacityText)
                            Spacer()
                            Text(heroPercentText)
                        }
                        .font(.system(size: 12, weight: .semibold, design: .default))
                        .foregroundStyle(PulsePalette.heroLowerInk)
                        .monospacedDigit()

                        ContextUsageBar(
                            progress: (context.contextUsedPercent ?? 0) / 100,
                            color: PulsePalette.heroLowerInk
                        )
                        .frame(height: 5)
                    }
                } else {
                    HStack {
                        Text(viewModel.t("live.usageNotContext"))
                        Spacer()
                        Text(modelLabel)
                    }
                    .font(.system(size: 12, weight: .semibold, design: .default))
                    .foregroundStyle(PulsePalette.heroLowerMuted)
                }
            }
            .frame(height: 28)

            HStack(spacing: 7) {
                HeroMetricTile(
                    direction: .input,
                    title: heroInputTitle,
                    value: DisplayFormat.tokens(heroUsage.inputTokens)
                )
                HeroMetricTile(
                    direction: .cached,
                    title: heroCacheTitle,
                    value: DisplayFormat.tokens(heroUsage.cachedInputTokens)
                )
                HeroMetricTile(
                    direction: .output,
                    title: heroOutputTitle,
                    value: DisplayFormat.tokens(heroUsage.outputTokens)
                )
            }

        }
        .padding(.top, 1)
        // The drawer is an overlay, not part of intrinsic layout. NSMenu keeps
        // exactly the same window size while it opens and closes, so AppKit no
        // longer rebuilds or flashes the entire menu window.
        .overlay(alignment: .top) {
            if isDetailsExpanded {
                expandedDetails
                    .padding(.horizontal, -2)
                    .offset(y: 38)
                    .transition(
                        reduceMotion
                            ? .identity
                            : .opacity.combined(with: .scale(scale: 0.985, anchor: .top))
                    )
                    .zIndex(20)
            }
        }
        .zIndex(isDetailsExpanded ? 20 : 0)
        .animation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.88), value: metric)
    }

    /// Never change the custom NSMenu item's intrinsic height from disclosure.
    /// The floating drawer is composited inside the existing hero bounds, so
    /// only that local layer redraws and the native menu window stays stable.
    private func toggleDetails() {
        let expanding = !isDetailsExpanded
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.14)) {
            isDetailsExpanded = expanding
        }
    }

    private func heroMetricButton(_ value: LiveHeroMetric, title: String) -> some View {
        Button {
            metric = value
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .default))
                .lineLimit(1)
                .foregroundStyle(metric == value ? PulsePalette.heroInk : PulsePalette.heroMuted)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(
                    metric == value ? PulsePalette.heroMetricSurface : Color.clear,
                    in: Capsule()
                )
                .contentShape(Capsule())
        }
        .buttonStyle(PulsePressStyle())
    }

    private var heroUsage: TokenUsage {
        // The live context number comes from the latest model request. Its
        // supporting input/cache/output breakdown must use that same request,
        // not the larger current-turn aggregate.
        metric == .context ? context.lastRequest : context.taskTotal
    }

    private var heroValue: String {
        switch metric {
        case .context: DisplayFormat.tokens(context.contextInputTokens)
        case .task: DisplayFormat.tokens(context.taskTotal.totalTokens)
        }
    }

    private var heroCaption: String {
        switch metric {
        case .context: viewModel.t("live.currentContextInput")
        case .task: viewModel.t("live.usageNotContext")
        }
    }

    private var heroInputTitle: String {
        metric == .context ? viewModel.t("live.contextInput") : viewModel.t("live.cumulativeInput")
    }

    private var heroCacheTitle: String {
        metric == .context ? viewModel.t("live.cacheWithinInput") : viewModel.t("live.cumulativeCache")
    }

    private var heroOutputTitle: String {
        metric == .context ? viewModel.t("live.requestOutput") : viewModel.t("live.cumulativeOutput")
    }

    private var heroCapacityText: String {
        guard let window = context.contextCapacityWindow else { return viewModel.t("live.single") }
        return viewModel.t("live.contextLimit", DisplayFormat.tokens(window))
    }

    private var heroPercentText: String {
        guard let percent = context.contextUsedPercent else { return "—" }
        let value = percent.formatted(.number.precision(.fractionLength(1))) + "%"
        return viewModel.t("live.usedValue", value)
    }

    private var expandedDetails: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(viewModel.t("live.tokenDetail"))
                        .font(.system(size: 14, weight: .semibold, design: .default))
                        .foregroundStyle(PulsePalette.detailInk)
                    Spacer(minLength: 6)
                    Text(modelLabel)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(PulsePalette.detailMuted)
                }

                HStack(spacing: 8) {
                    Text(context.projectName)
                    Spacer(minLength: 4)
                    if let detailWindowText {
                        Text(detailWindowText)
                    }
                }
                .font(.system(size: 12, weight: .medium, design: .default))
                .foregroundStyle(PulsePalette.detailMuted)
            }
            .padding(.bottom, 10)

            PulsePalette.detailDivider.frame(height: 1)

            TokenScopeDetailSection(
                title: viewModel.t("live.currentContext"),
                headline: "\(viewModel.t("live.contextInput")) \(tokenValue(context.contextInputTokens))",
                inputTitle: viewModel.t("live.input"),
                cachedTitle: viewModel.t("live.cached"),
                outputTitle: viewModel.t("live.output"),
                inputValue: exactTokenValue(context.lastRequest.inputTokens),
                cachedValue: exactTokenValue(context.lastRequest.cachedInputTokens),
                outputValue: exactTokenValue(context.lastRequest.outputTokens)
            )
            .padding(.vertical, 10)

            PulsePalette.detailDivider.frame(height: 1)

            TokenScopeDetailSection(
                title: viewModel.t("live.turn", context.currentTurnCalls.count),
                headline: viewModel.t("live.totalTokens", tokenValue(context.currentTurnUsage.totalTokens)),
                inputTitle: viewModel.t("live.input"),
                cachedTitle: viewModel.t("live.cached"),
                outputTitle: viewModel.t("live.output"),
                inputValue: exactTokenValue(context.currentTurnUsage.inputTokens),
                cachedValue: exactTokenValue(context.currentTurnUsage.cachedInputTokens),
                outputValue: exactTokenValue(context.currentTurnUsage.outputTokens)
            )
            .padding(.vertical, 10)

            PulsePalette.detailDivider.frame(height: 1)

            TokenScopeDetailSection(
                title: viewModel.t("live.total"),
                headline: viewModel.t("live.totalTokens", tokenValue(context.taskTotal.totalTokens)),
                inputTitle: viewModel.t("live.input"),
                cachedTitle: viewModel.t("live.cached"),
                outputTitle: viewModel.t("live.output"),
                inputValue: exactTokenValue(context.taskTotal.inputTokens),
                cachedValue: exactTokenValue(context.taskTotal.cachedInputTokens),
                outputValue: exactTokenValue(context.taskTotal.outputTokens)
            )
            .padding(.top, 10)

            MarqueeLabel(
                text: detailAccountingNote,
                font: .system(size: 12, weight: .medium, design: .default),
                color: PulsePalette.detailMuted
            )
            .frame(height: 15)
            .padding(.top, 8)

            if showAPIEstimate {
                PulsePalette.detailDivider
                    .frame(height: 1)
                    .padding(.vertical, 10)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(viewModel.t("live.estimate"))
                        .font(.system(size: 12, weight: .medium, design: .default))
                        .foregroundStyle(PulsePalette.detailMuted)
                    Spacer(minLength: 4)
                    Text(apiEstimateValue)
                        .font(.system(size: 14, weight: .semibold, design: .default))
                        .foregroundStyle(PulsePalette.detailInk)
                        .monospacedDigit()
                }
                .padding(.bottom, 8)

                if let rate = PricingCatalog.rate(for: context.model) {
                    PricingRateDetailRow(
                        title: standardTierTitle,
                        unitTitle: viewModel.t("live.perMillionTokens"),
                        inputTitle: viewModel.t("live.input"),
                        cachedTitle: viewModel.t("live.cached"),
                        outputTitle: viewModel.t("live.output"),
                        inputValue: "$\(compact(rate.inputPerMillion))",
                        cachedValue: "$\(compact(rate.cachedInputPerMillion))",
                        outputValue: "$\(compact(rate.outputPerMillion))"
                    )

                    if apiUSD?.isLongContext == true {
                        PricingRateDetailRow(
                            title: longTierTitle,
                            unitTitle: viewModel.t("live.perMillionTokens"),
                            inputTitle: viewModel.t("live.input"),
                            cachedTitle: viewModel.t("live.cached"),
                            outputTitle: viewModel.t("live.output"),
                            inputValue: "$\(compact(rate.inputPerMillion * rate.longContextInputMultiplier))",
                            cachedValue: "$\(compact(rate.cachedInputPerMillion * rate.longContextInputMultiplier))",
                            outputValue: "$\(compact(rate.outputPerMillion * rate.longContextOutputMultiplier))"
                        )
                        .padding(.top, 8)
                    }
                } else {
                    Text(viewModel.t("live.apiMissing"))
                        .font(.system(size: 12, weight: .medium, design: .default))
                        .foregroundStyle(PulsePalette.detailMuted)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PulsePalette.detailGlassTint, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(PulsePalette.detailDivider, lineWidth: 1)
        }
        .compositingGroup()
        .accessibilityElement(children: .contain)
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

    private var apiEstimateValue: String {
        guard let value = apiUSD?.total else { return viewModel.t("live.noRate") }
        return "≈ \(DisplayFormat.usd(value))"
    }

    private func tokenValue(_ value: Int64) -> String {
        viewModel.t("live.tokenValue", DisplayFormat.tokens(value))
    }

    private func exactTokenValue(_ value: Int64) -> String {
        viewModel.t("live.tokenValue", DisplayFormat.integer(value))
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

private struct TokenScopeDetailSection: View {
    let title: String
    let headline: String
    let inputTitle: String
    let cachedTitle: String
    let outputTitle: String
    let inputValue: String
    let cachedValue: String
    let outputValue: String

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .default))
                    .foregroundStyle(PulsePalette.detailInk)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(headline)
                    .font(.system(size: 12, weight: .medium, design: .default))
                    .foregroundStyle(PulsePalette.detailMuted)
                    .monospacedDigit()
                    .lineLimit(1)
            }

            VStack(spacing: 3) {
                DetailTokenMetric(
                    direction: .input,
                    title: inputTitle,
                    value: inputValue
                )
                DetailTokenMetric(
                    direction: .cached,
                    title: cachedTitle,
                    value: cachedValue
                )
                DetailTokenMetric(
                    direction: .output,
                    title: outputTitle,
                    value: outputValue
                )
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct DetailTokenMetric: View {
    let direction: HeroTokenDirection
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            PulseIcon(name: direction.iconName)
                .frame(width: 8, height: 8)
                .rotationEffect(direction.rotation)
            Text(title)
                .font(.system(size: 12, weight: .medium, design: .default))
                .foregroundStyle(PulsePalette.detailMuted)
                .lineLimit(1)
            Spacer(minLength: 12)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(PulsePalette.detailInk)
                .monospacedDigit()
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 15)
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
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(title)
                .foregroundStyle(PulsePalette.detailMuted)
            Text(value)
                .foregroundStyle(PulsePalette.detailInk)
                .monospacedDigit()
        }
        .font(.system(size: 12, weight: .semibold, design: .default))
        .lineLimit(1)
        .frame(maxWidth: .infinity)
    }
}

private struct HeroMetricTile: View {
    let direction: HeroTokenDirection
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 4) {
                PulseIcon(name: direction.iconName)
                    .frame(width: 9, height: 9)
                    .rotationEffect(direction.rotation)
                Text(title)
            }
            .font(.system(size: 12, weight: .semibold, design: .default))
            .foregroundStyle(PulsePalette.heroLowerMuted)
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .default))
                .foregroundStyle(PulsePalette.heroLowerInk)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity)
        .frame(height: 49)
        .background(PulsePalette.heroMetricSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct UpdateMetricTile: View {
    let title: String
    let value: String
    var accent: Color = PulsePalette.ink

    var body: some View {
        VStack(alignment: .center, spacing: 3) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .default))
                .foregroundStyle(PulsePalette.faint)
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .default))
                .foregroundStyle(accent)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, minHeight: 46, alignment: .center)
    }
}

private struct MarqueeLabel: View {
    let text: String
    let font: Font
    let color: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var textWidth: CGFloat = 0
    @State private var cycleStartedAt = Date()

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion || textWidth <= proxy.size.width)) { timeline in
                Text(text)
                    .font(font)
                    .foregroundStyle(color)
                    .fixedSize(horizontal: true, vertical: false)
                    .offset(x: marqueeOffset(at: timeline.date, containerWidth: proxy.size.width))
                    .background {
                        GeometryReader { textProxy in
                            Color.clear.preference(key: MarqueeTextWidthKey.self, value: textProxy.size.width)
                        }
                    }
            }
        }
        .frame(height: 18)
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
    var onHero = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion || !isFresh)) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate
            let pulse = reduceMotion ? 1 : 0.72 + (sin(phase * 5) + 1) * 0.14
            HStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(isFresh ? PulsePalette.lime.opacity(0.20) : PulsePalette.warning.opacity(0.20))
                        .frame(width: 10, height: 10)
                        .scaleEffect(isFresh ? pulse : 1)
                    Circle()
                        .fill(isFresh ? PulsePalette.lime : PulsePalette.warning)
                        .frame(width: 4, height: 4)
                }
                Text(isFresh ? "LIVE" : "STALE")
            }
            .font(.system(size: 12, weight: .semibold, design: .default))
            .foregroundStyle(onHero ? PulsePalette.heroInk : (isFresh ? PulsePalette.accent : PulsePalette.warning))
            .padding(.horizontal, 6)
            .frame(height: 18)
            .background(
                onHero ? PulsePalette.heroTile : Color.primary.opacity(0.07),
                in: Capsule()
            )
        }
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(PulsePalette.surfaceRaised)
                PulseIcon(name: "tasks").frame(width: 15, height: 15)
                    .foregroundStyle(PulsePalette.ink)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 3) {
                MarqueeLabel(
                    text: title,
                    font: .system(size: 13, weight: .semibold, design: .default),
                    color: PulsePalette.ink
                )
                .frame(width: 150)
                MarqueeLabel(
                    text: subtitle,
                    font: .system(size: 12, weight: .medium, design: .monospaced),
                    color: PulsePalette.faint
                )
                .frame(width: 150)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text(DisplayFormat.tokens(session.usage.totalTokens))
                    .font(.system(size: 13, weight: .semibold, design: .default))
                    .foregroundStyle(PulsePalette.accent)
                    .monospacedDigit()
                Text(session.lastActivityAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(PulsePalette.faint)
            }
        }
        .padding(.horizontal, 11)
        .frame(height: 52)
        .background(
            hovering ? PulsePalette.surfaceHover : PulsePalette.surface,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .offset(y: hovering && !reduceMotion ? -1 : 0)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: hovering)
        .onHover { hovering = $0 }
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
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .default))
                .foregroundStyle(PulsePalette.faint)
                .padding(.leading, 3)
            VStack(spacing: 0) { content }
                .font(.system(size: 13, weight: .semibold, design: .default))
                .foregroundStyle(PulsePalette.ink)
                .background(PulsePalette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(PulsePalette.divider.opacity(0.72), lineWidth: 1)
                }
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
        .frame(height: 38)
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
        }
        .padding(.horizontal, 13)
        .frame(height: 38)
        .contentShape(Rectangle())
        .onChange(of: isOn) { _, _ in changed() }
    }
}

private struct PulseToggle: View {
    @Binding var isOn: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var viewModel: DashboardViewModel

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? PulsePalette.accent : PulsePalette.surfaceHover)
                    .frame(width: 34, height: 20)
                Circle()
                    .fill(isOn ? PulsePalette.surface : PulsePalette.muted)
                    .frame(width: 14, height: 14)
                    .padding(3)
            }
        }
        .buttonStyle(PulsePressStyle())
        .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.86), value: isOn)
        .accessibilityLabel(viewModel.t("control.toggle"))
        .accessibilityValue(viewModel.t(isOn ? "status.on" : "status.off"))
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
            PulseIcon(name: "sync").frame(width: 15, height: 15)
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
            .scaleEffect(enabled && configuration.isPressed && !reduceMotion ? 0.955 : 1)
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
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.10), value: configuration.isPressed)
    }
}
