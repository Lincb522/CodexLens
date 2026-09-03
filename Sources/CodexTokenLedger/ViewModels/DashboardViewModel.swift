import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

private enum AccountFetchOutcome: @unchecked Sendable {
    case success(CodexAccountUsageSnapshot)
    case failure(Error)
}

private enum LocalUsageFetchOutcome: @unchecked Sendable {
    case success(UsageSnapshot)
    case failure(Error)
}

private enum LiveContextFetchOutcome: @unchecked Sendable {
    case success([CodexLiveContextSnapshot])
    case failure(Error)
}

private enum ThreadMetadataFetchOutcome: @unchecked Sendable {
    case success([String: CodexThreadMetadata])
    case failure
}

private enum TiboSignalFetchOutcome: @unchecked Sendable {
    case success(TiboResetMonitorSnapshot)
    case failure(Error)
}

enum MenuBarMetric: String, CaseIterable, Identifiable {
    case contextUsed
    /// Keeps the historic raw value so existing preferences migrate without
    /// silently changing the selected menu metric.
    case requestAPICost = "requestCredits"
    case quotaRemaining
    case weeklyRemaining
    case tokens
    case credits
    case usd
    case iconOnly

    var id: String { rawValue }
}

enum AccountSwitchMode: String, CaseIterable, Identifiable {
    case monitorOnly
    case activateCodex

    var id: String { rawValue }
}

struct CredentialInputInspection {
    let isValid: Bool
    let accountCount: Int
    let formatSummary: String
    let message: String
}

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var snapshot: UsageSnapshot = .empty
    @Published var isScanning = false
    @Published var errorMessage: String?
    @Published var exportMessage: String?
    @Published var searchText = ""
    @Published var codexHomePath: String
    @Published var includeArchived: Bool
    @Published var autoRefresh: Bool
    @Published var menuBarMetric: MenuBarMetric
    @Published var lastScanDuration: TimeInterval?
    @Published var accountSnapshots: [CodexAccountUsageSnapshot]
    @Published var accountHomePaths: [String]
    @Published var activeAccountID: String?
    @Published private(set) var codexLoginAccountID: String?
    @Published var selectedAccountID: String?
    @Published var accountErrorMessage: String?
    @Published var accountActionMessage: String?
    @Published private(set) var pendingOAuthHomePath: String?
    @Published var liveContext: CodexLiveContextSnapshot?
    @Published var liveContexts: [CodexLiveContextSnapshot]
    @Published var selectedLiveContextID: String?
    @Published var liveContextErrorMessage: String?
    @Published var isLiveContextRefreshing: Bool
    @Published var threadMetadataByID: [String: CodexThreadMetadata]
    @Published var appTheme: AppTheme
    @Published var appLanguage: AppLanguage
    @Published var liveRefreshRate: LiveRefreshRate
    @Published var discoveryRate: DiscoveryRate
    @Published var accountRefreshRate: AccountRefreshRate
    @Published var liveTaskLimit: LiveTaskLimit
    @Published var showAPIEstimate: Bool
    @Published var showRuntimeWindow: Bool
    @Published var showConcurrentTaskCount: Bool
    @Published var privacyMode: Bool
    @Published var restartCodexAfterSwitch: Bool
    @Published var tiboMonitoringEnabled: Bool
    @Published private(set) var launchAtLoginEnabled: Bool
    @Published private(set) var launchAtLoginRequiresApproval: Bool
    @Published private(set) var launchAtLoginErrorMessage: String?
    @Published private(set) var tiboSignalSnapshot: TiboResetMonitorSnapshot
    @Published private(set) var tiboSignalErrorMessage: String?
    @Published private(set) var isTiboSignalRefreshing: Bool
    @Published private(set) var menuLayoutRevision: Int
    @Published private(set) var isAccountSwitching: Bool
    @Published private(set) var quotaHistorySamples: [QuotaUsageSample]
    @Published private(set) var clockNow: Date

    private var hasLoaded = false
    private var refreshQueued = false
    private let defaults: UserDefaults
    private var lastLiveDiscoveryAt = Date.distantPast
    private var lastLivePollAt = Date.distantPast
    private var lastAccountRefreshAt = Date.distantPast
    private var lastTiboRefreshAt = Date.distantPast
    private var accountCredentialHomes: [String: String]
    private let liveContextMonitor = CodexLiveContextMonitor()
    private let tiboResetSignalService = TiboResetSignalService()
    private let launchAtLoginController: LaunchAtLoginControlling

    init(
        defaults: UserDefaults = .standard,
        initialQuotaHistorySamples: [QuotaUsageSample]? = nil,
        initialTiboSignalSnapshot: TiboResetMonitorSnapshot? = nil,
        launchAtLoginController: LaunchAtLoginControlling = LaunchAtLoginService()
    ) {
        self.defaults = defaults
        self.launchAtLoginController = launchAtLoginController
        let cachedAccounts = CodexAccountUsageStore.load()
        let defaultHome = ProcessInfo.processInfo.environment["CODEX_HOME"]
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex").path
        let initialHome = defaults.string(forKey: "codexHomePath") ?? defaultHome
        codexHomePath = initialHome
        includeArchived = defaults.object(forKey: "includeArchived") as? Bool ?? true
        autoRefresh = defaults.object(forKey: "autoRefresh") as? Bool ?? true
        if defaults.bool(forKey: "liveContextMetricMigrationV5_1") {
            menuBarMetric = MenuBarMetric(rawValue: defaults.string(forKey: "menuBarMetric") ?? "contextUsed")
                ?? .contextUsed
        } else {
            menuBarMetric = .contextUsed
            defaults.set(true, forKey: "liveContextMetricMigrationV5_1")
            defaults.set(MenuBarMetric.contextUsed.rawValue, forKey: "menuBarMetric")
        }
        lastScanDuration = nil
        accountSnapshots = cachedAccounts
        accountHomePaths = Self.uniquePaths(
            (defaults.stringArray(forKey: "accountHomePaths") ?? [])
                + cachedAccounts.map(\.codexHome)
                + [initialHome]
        )
        activeAccountID = nil
        codexLoginAccountID = (try? CodexCredentialStore.authData(in: Self.runtimeCodexHomeURL))
            .flatMap(CodexCredentialStore.stableAccountID(from:))
        selectedAccountID = defaults.string(forKey: "selectedAccountID") ?? cachedAccounts.first?.id
        accountErrorMessage = nil
        accountActionMessage = nil
        pendingOAuthHomePath = defaults.string(forKey: "pendingOAuthHomePath")
        var storedCredentialHomes = defaults.dictionary(forKey: "accountCredentialHomes") as? [String: String] ?? [:]
        for account in cachedAccounts where storedCredentialHomes[account.id] == nil {
            storedCredentialHomes[account.id] = account.codexHome
        }
        accountCredentialHomes = storedCredentialHomes
        liveContext = nil
        liveContexts = []
        selectedLiveContextID = defaults.string(forKey: "selectedLiveContextID")
        liveContextErrorMessage = nil
        isLiveContextRefreshing = false
        threadMetadataByID = [:]
        appTheme = AppTheme(rawValue: defaults.string(forKey: "appTheme") ?? "system") ?? .system
        appLanguage = AppLanguage(rawValue: defaults.string(forKey: "appLanguage") ?? "system") ?? .system
        liveRefreshRate = LiveRefreshRate(rawValue: defaults.double(forKey: "liveRefreshRate")) ?? .two
        discoveryRate = DiscoveryRate(rawValue: defaults.double(forKey: "discoveryRate")) ?? .ten
        accountRefreshRate = AccountRefreshRate(rawValue: defaults.double(forKey: "accountRefreshRate")) ?? .fiveMinutes
        liveTaskLimit = LiveTaskLimit(rawValue: defaults.integer(forKey: "liveTaskLimit")) ?? .eight
        showAPIEstimate = defaults.object(forKey: "showAPIEstimate") as? Bool ?? true
        showRuntimeWindow = defaults.object(forKey: "showRuntimeWindow") as? Bool ?? true
        showConcurrentTaskCount = defaults.object(forKey: "showConcurrentTaskCount") as? Bool ?? true
        privacyMode = defaults.object(forKey: "privacyMode") as? Bool ?? false
        restartCodexAfterSwitch = defaults.object(forKey: "restartCodexAfterSwitch") as? Bool ?? true
        tiboMonitoringEnabled = defaults.object(forKey: "tiboMonitoringEnabled") as? Bool ?? true
        let launchAtLoginStatus = launchAtLoginController.status
        launchAtLoginEnabled = launchAtLoginStatus == .enabled || launchAtLoginStatus == .requiresApproval
        launchAtLoginRequiresApproval = launchAtLoginStatus == .requiresApproval
        launchAtLoginErrorMessage = nil
        tiboSignalSnapshot = initialTiboSignalSnapshot ?? TiboResetSignalStore.load()
        tiboSignalErrorMessage = nil
        isTiboSignalRefreshing = false
        menuLayoutRevision = 0
        isAccountSwitching = false
        quotaHistorySamples = initialQuotaHistorySamples ?? QuotaUsageHistoryStore.load()
        clockNow = Date()
    }

    var selectedAccount: CodexAccountUsageSnapshot? {
        if let selectedAccountID,
           let selected = accountSnapshots.first(where: { $0.id == selectedAccountID }) {
            return selected
        }
        return accountSnapshots.first
    }

    var selectedAccountIsActive: Bool {
        guard let selectedAccount else { return false }
        return selectedAccount.id == activeAccountID
    }

    var selectedAccountIsCodexLogin: Bool {
        selectedAccount?.id == codexLoginAccountID
    }

    var codexLoginAccount: CodexAccountUsageSnapshot? {
        guard let codexLoginAccountID else { return nil }
        return accountSnapshots.first { $0.id == codexLoginAccountID }
    }

    func accountIsCodexLogin(_ account: CodexAccountUsageSnapshot) -> Bool {
        account.id == codexLoginAccountID
    }

    var hasPendingOAuth: Bool { pendingOAuthHomePath != nil }

    func credentialHomePath(for account: CodexAccountUsageSnapshot) -> String {
        accountCredentialHomes[account.id] ?? account.codexHome
    }

    var activeLiveContexts: [CodexLiveContextSnapshot] {
        liveContexts.filter(\.isTaskActive)
    }

    var activeTaskCount: Int { activeLiveContexts.count }

    var combinedActiveContextInputTokens: Int64 {
        activeLiveContexts.reduce(0) { $0 + $1.contextInputTokens }
    }

    /// All local Codex accounting records. The menu-bar app has no hidden
    /// date filter; exports and account-independent totals therefore use the
    /// same complete local scope shown to the user.
    var filteredRecords: [UsageRecord] { snapshot.records }

    /// Exact total for every locally indexed conversation in this Codex Home.
    /// Unlike date-filtered charts, this never assigns a cumulative session
    /// counter to an arbitrary date range.
    var localConversationTotalUsage: TokenUsage {
        snapshot.exactConversationTotal
    }

    var selectedQuotaForecast: QuotaForecast? {
        guard let account = selectedAccount, let window = account.preferredMenuWindow else { return nil }
        return QuotaForecastEngine().forecast(
            accountID: account.id,
            window: window,
            samples: quotaHistorySamples,
            observedAt: account.updatedAt
        )
    }

    var selectedSubscriptionQuotaEstimate: SubscriptionQuotaEstimate? {
        SubscriptionQuotaEstimate.forPlan(selectedAccount?.plan)
    }

    func accountDailyValue(_ account: CodexAccountUsageSnapshot) -> String {
        account.accountTokenUsage?.latestDailyUsage
            .map { DisplayFormat.tokens($0.tokens) } ?? "—"
    }

    func accountDailyTitle(_ account: CodexAccountUsageSnapshot) -> String {
        guard let bucket = account.accountTokenUsage?.latestDailyUsage,
              let date = Self.serverDayFormatter.date(from: String(bucket.startDate.prefix(10)))
        else {
            return t("account.today", "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let today = Self.serverDayFormatter.string(from: Date())
        if String(bucket.startDate.prefix(10)) == today {
            return t("account.today", "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: appLanguage.localeIdentifier)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.setLocalizedDateFormatFromTemplate("Md")
        return t("account.dailyUsageOn", formatter.string(from: date))
    }

    var apiEquivalentCost: CostBreakdown? {
        let value = BillingCalculator.total(records: filteredRecords)
        return value.isPriced ? value : nil
    }

    var menuBarText: String {
        if isScanning && selectedAccount == nil { return "…" }
        switch menuBarMetric {
        case .contextUsed:
            guard let context = liveContext else { return "—" }
            let taskSuffix = showConcurrentTaskCount && activeTaskCount > 1 ? " ×\(activeTaskCount)" : ""
            return "\(DisplayFormat.tokens(context.contextInputTokens))\(taskSuffix)"
        case .requestAPICost:
            guard let total = liveRequestAPIUSD?.total else { return "—" }
            return "≈\(DisplayFormat.usd(total))"
        case .quotaRemaining:
            return selectedAccount?.preferredMenuWindow.map { "\(Int($0.remainingPercent.rounded()))%" } ?? "—"
        case .weeklyRemaining:
            return selectedAccount?.weeklyWindow.map { "\(Int($0.remainingPercent.rounded()))%" } ?? "—"
        case .tokens: return DisplayFormat.tokens(localConversationTotalUsage.totalTokens)
        case .credits:
            if selectedAccount?.credits?.unlimited == true { return "∞" }
            if let balance = selectedAccount?.credits?.balance {
                return balance.formatted(.number.precision(.fractionLength(0...2)))
            }
            return "—"
        case .usd:
            guard let total = apiEquivalentCost?.total else { return "—" }
            return "≈\(DisplayFormat.usd(total))"
        case .iconOnly: return ""
        }
    }

    var syncStatusText: String {
        if isScanning {
            return t("footer.syncing")
        }
        if accountErrorMessage != nil, selectedAccount == nil { return t("footer.syncFailed") }
        guard let selectedAccount else { return t("footer.noAccount") }
        let time = selectedAccount.updatedAt.formatted(date: .omitted, time: .shortened)
        if let lastScanDuration {
            return t("footer.updatedDuration", time, Self.durationFormatter.string(from: lastScanDuration) ?? "<1s")
        }
        return t("footer.updated", time)
    }

    func t(_ key: String, _ arguments: CVarArg...) -> String {
        LocalizationCatalog.text(key, language: appLanguage, arguments: arguments)
    }

    private func localizedErrorText(_ error: Error) -> String {
        guard let localized = error as? any AppLocalizedError else {
            return error.localizedDescription
        }
        return LocalizationCatalog.text(
            localized.localizationKey,
            language: appLanguage,
            arguments: localized.localizationArguments
        )
    }

    func accountName(_ account: CodexAccountUsageSnapshot) -> String {
        let email = account.email?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard privacyMode else {
            if let email, !email.isEmpty { return email }
            return t("account.current")
        }
        if let email, email.contains("@") {
            let suffix = email.split(separator: "@").last.map(String.init) ?? "account"
            return "••••@\(suffix)"
        }
        return "Codex ••••"
    }

    func themeTitle(_ theme: AppTheme) -> String { t("theme.\(theme.rawValue)") }

    func languageTitle(_ language: AppLanguage) -> String {
        language == .system ? t("theme.system") : language.autonym
    }

    func menuMetricTitle(_ metric: MenuBarMetric) -> String {
        switch metric {
        case .contextUsed: t("metric.context")
        case .requestAPICost: t("metric.requestCredits")
        case .quotaRemaining: t("metric.quota")
        case .weeklyRemaining: t("metric.weekly")
        case .tokens: "Token"
        case .credits: t("metric.credits")
        case .usd: "API USD"
        case .iconOnly: t("metric.iconOnly")
        }
    }

    var liveRequestAPIUSD: CostBreakdown? {
        liveTurnCost()
    }

    var liveTaskAPIUSD: CostBreakdown? {
        // The cumulative counter has no per-request boundaries. Do not invent
        // long-context multipliers for the task total.
        liveCost(for: liveContext?.taskTotal, applyLongContextMultiplier: false)
    }

    var filteredSessions: [SessionSummary] {
        guard !searchText.isEmpty else { return snapshot.sessions }
        let needle = searchText.localizedLowercase
        return snapshot.sessions.filter {
            sessionTitle($0).localizedLowercase.contains(needle)
                || $0.projectName.localizedLowercase.contains(needle)
                || $0.latestModel.localizedLowercase.contains(needle)
                || $0.id.localizedLowercase.contains(needle)
        }
    }

    func sessionTitle(_ session: SessionSummary) -> String {
        threadMetadataByID[session.id]?.title ?? session.projectName
    }

    func sessionSubtitle(_ session: SessionSummary) -> String {
        "\(session.projectName) · \(PricingCatalog.normalize(model: session.latestModel))"
    }

    func loadIfNeeded() {
        guard !hasLoaded else { return }
        hasLoaded = true
        liveContextTick(forceDiscover: true)
        tiboSignalTick(force: true)
        refresh()
    }

    func scheduledLiveContextTick() {
        let now = Date()
        clockNow = now
        guard now.timeIntervalSince(lastLivePollAt) >= liveRefreshRate.rawValue else { return }
        lastLivePollAt = now
        liveContextTick()
    }

    func liveContextTick(forceDiscover: Bool = false) {
        guard !isLiveContextRefreshing else { return }
        let home = URL(
            fileURLWithPath: (codexHomePath as NSString).expandingTildeInPath,
            isDirectory: true
        )
        let discover = forceDiscover
            || liveContexts.isEmpty
            || Date().timeIntervalSince(lastLiveDiscoveryAt) >= discoveryRate.rawValue
        let preferredPaths = liveContexts.map(\.sourcePath)
        let knownMetadata = threadMetadataByID
        let maximumResults = liveTaskLimit.rawValue
        let monitor = liveContextMonitor
        isLiveContextRefreshing = true

        Task {
            let outcome = await Task.detached(priority: .utility) { () -> LiveContextFetchOutcome in
                do {
                    let values = try await monitor.readContexts(
                        codexHome: home,
                        preferredSourcePaths: preferredPaths,
                        maximumResults: maximumResults,
                        discover: discover
                    )
                    let resolved = values.map { context -> CodexLiveContextSnapshot in
                        if let metadata = knownMetadata[context.id] {
                            return context.applying(metadata)
                        }
                        return context.applying(
                            try? CodexThreadMetadataReader().read(threadID: context.id, codexHome: home)
                        )
                    }
                    return .success(resolved.sorted { $0.updatedAt > $1.updatedAt })
                } catch {
                    return .failure(error)
                }
            }.value

            if discover { lastLiveDiscoveryAt = Date() }
            switch outcome {
            case .success(let values):
                liveContexts = values
                let preferredID = selectedLiveContextID ?? liveContext?.id
                let selected = preferredID.flatMap { id in values.first { $0.id == id } } ?? values.first
                liveContext = selected
                selectedLiveContextID = selected?.id
                defaults.set(selected?.id, forKey: "selectedLiveContextID")
                liveContextErrorMessage = values.isEmpty ? t("live.noEvents") : nil
            case .failure(let error):
                liveContextErrorMessage = localizedErrorText(error)
            }
            isLiveContextRefreshing = false
        }
    }

    func selectLiveContext(_ id: String) {
        guard let context = liveContexts.first(where: { $0.id == id }) else { return }
        selectedLiveContextID = id
        liveContext = context
        defaults.set(id, forKey: "selectedLiveContextID")
    }

    func refresh() {
        guard !isScanning else {
            refreshQueued = true
            return
        }
        persistPreferences()
        isScanning = true
        errorMessage = nil
        accountErrorMessage = nil
        let home = URL(fileURLWithPath: (codexHomePath as NSString).expandingTildeInPath, isDirectory: true)
        let archived = includeArchived
        let cacheURL = UsageCacheStore.defaultURL
        let startedAt = Date()
        lastAccountRefreshAt = startedAt
        tiboSignalTick(force: true)

        Task {
            let accountTask = Task.detached(priority: .userInitiated) { () -> AccountFetchOutcome in
                do {
                    return .success(try CodexAccountService().fetch(codexHome: home))
                } catch {
                    return .failure(error)
                }
            }
            let usageTask = Task.detached(priority: .utility) { () -> LocalUsageFetchOutcome in
                do {
                    let cache = UsageCacheStore.load(from: cacheURL)
                    let result = try CodexSessionScanner().scanWithCache(
                        codexHome: home,
                        includeArchived: archived,
                        cache: cache
                    )
                    try? UsageCacheStore.save(result.cache, to: cacheURL)
                    return .success(result.snapshot)
                } catch {
                    return .failure(error)
                }
            }
            let metadataTask = Task.detached(priority: .utility) { () -> ThreadMetadataFetchOutcome in
                do {
                    return .success(try CodexThreadMetadataReader().readAll(codexHome: home))
                } catch {
                    return .failure
                }
            }

            let accountOutcome = await accountTask.value
            let usageOutcome = await usageTask.value

            switch accountOutcome {
            case .success(let account):
                accountSnapshots = CodexAccountUsageStore.upserting(account, into: accountSnapshots)
                quotaHistorySamples = QuotaUsageHistoryStore.appending(
                    snapshot: account,
                    to: quotaHistorySamples
                )
                try? QuotaUsageHistoryStore.save(quotaHistorySamples)
                registerAccountHome(account.codexHome)
                if accountCredentialHomes[account.id] == nil {
                    accountCredentialHomes[account.id] = home.standardizedFileURL.path
                }
                activeAccountID = account.id
                if home.standardizedFileURL == Self.runtimeCodexHomeURL {
                    codexLoginAccountID = account.id
                }
                selectedAccountID = account.id
                defaults.set(account.id, forKey: "selectedAccountID")
                defaults.set(accountCredentialHomes, forKey: "accountCredentialHomes")
                try? CodexAccountUsageStore.save(accountSnapshots)
            case .failure(let error):
                accountErrorMessage = localizedErrorText(error)
            }

            switch usageOutcome {
            case .success(let result):
                snapshot = result
            case .failure(let error):
                errorMessage = localizedErrorText(error)
            }
            if case .success(let metadata) = await metadataTask.value {
                threadMetadataByID = metadata
                liveContexts = liveContexts.map { $0.applying(metadata[$0.id]) }
                if let selectedLiveContextID {
                    liveContext = liveContexts.first { $0.id == selectedLiveContextID }
                } else {
                    liveContext = liveContexts.first
                }
            }
            lastScanDuration = Date().timeIntervalSince(startedAt)
            isScanning = false
            if refreshQueued {
                refreshQueued = false
                refresh()
            }
        }
    }

    func autoRefreshTick() {
        guard autoRefresh else { return }
        guard Date().timeIntervalSince(lastAccountRefreshAt) >= accountRefreshRate.rawValue else { return }
        refresh()
    }

    func accountTimerTick() {
        checkPendingOAuth(announceWhenWaiting: false)
        autoRefreshTick()
        tiboSignalTick()
    }

    func tiboSignalTick(force: Bool = false) {
        guard tiboMonitoringEnabled, !isTiboSignalRefreshing else { return }
        let now = Date()
        guard force || now.timeIntervalSince(lastTiboRefreshAt) >= 5 * 60 else { return }
        lastTiboRefreshAt = now
        isTiboSignalRefreshing = true
        let service = tiboResetSignalService

        Task {
            let outcome = await Task.detached(priority: .utility) { () -> TiboSignalFetchOutcome in
                do { return .success(try await service.fetch()) }
                catch { return .failure(error) }
            }.value

            switch outcome {
            case .success(let value):
                // The public endpoint is a rolling page. Merge it with the
                // local metadata-only fact log so older confirmations remain
                // available as cycle anchors after they leave the response.
                let merged = tiboSignalSnapshot.mergingRemote(value)
                tiboSignalSnapshot = merged
                tiboSignalErrorMessage = nil
                try? TiboResetSignalStore.save(merged)
            case .failure(let error):
                let offline = (error as? URLError).map {
                    [.notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost]
                        .contains($0.code)
                } ?? false
                let failed = tiboSignalSnapshot.recordingFailure(
                    at: Date(),
                    code: Self.tiboErrorCode(error),
                    offline: offline
                )
                tiboSignalSnapshot = failed
                tiboSignalErrorMessage = localizedErrorText(error)
                try? TiboResetSignalStore.save(failed)
            }
            isTiboSignalRefreshing = false
        }
    }

    func tiboMonitoringChanged() {
        persistPreferences()
        if tiboMonitoringEnabled { tiboSignalTick(force: true) }
    }

    func openTiboCycleSource() {
        let cycle = tiboResetCycle
        guard let url = (cycle.activeSignal ?? cycle.lastConfirmedSignal)?.sourceURL else { return }
        NSWorkspace.shared.open(url)
    }

    func openLatestTiboSocialEvidence() {
        guard let url = tiboLatestSocialEvidence?.sourceURL else { return }
        NSWorkspace.shared.open(url)
    }

    var tiboCompactStatusText: String {
        if isTiboSignalRefreshing, tiboSignalSnapshot.latestSignal == nil {
            return t("tibo.badge", t("tibo.status.checking"))
        }
        guard let signal = tiboSignalSnapshot.latestSignal else {
            let status = tiboSignalSnapshot.sourceStatus == .healthy
                ? t("tibo.status.none")
                : t("tibo.status.unavailable")
            return t("tibo.badge", status)
        }
        return t("tibo.badge", t("tibo.status.\(signal.status.rawValue)"))
    }

    var tiboResetCycle: TiboResetCycle {
        tiboSignalSnapshot.cycle(now: clockNow)
    }

    var tiboForecast: TiboForecastSnapshot? {
        tiboSignalSnapshot.forecast
    }

    var tiboForecastProbabilityText: String {
        tiboForecast.map { "\($0.probability24hPercent)%" } ?? "—"
    }

    var tiboForecastProbabilityLevelText: String {
        guard let percent = tiboForecast?.probability24hPercent else {
            return t("tibo.forecast.level.unavailable")
        }
        if percent >= 70 { return t("tibo.forecast.level.high") }
        if percent >= 40 { return t("tibo.forecast.level.medium") }
        return t("tibo.forecast.level.low")
    }

    var tiboForecastJudgementTitle: String {
        t("tibo.forecast.judgementTitle", tiboForecastProbabilityLevelText)
    }

    var tiboForecastProbabilityBandText: String {
        guard let percent = tiboForecast?.probability24hPercent else {
            return t("tibo.forecast.probabilityBand.unavailable")
        }
        let key: String
        if percent >= 70 {
            key = "tibo.forecast.probabilityBand.high"
        } else if percent >= 40 {
            key = "tibo.forecast.probabilityBand.medium"
        } else {
            key = "tibo.forecast.probabilityBand.low"
        }
        return t(key, percent)
    }

    var tiboForecastPublicSignalText: String {
        let socialKind = tiboLatestSocialEvidence?.signalKind
        if tiboResetCycle.activePrediction != nil
            || socialKind == .explicit
            || socialKind == .tease {
            return t("tibo.forecast.publicSignal.active")
        }
        return t("tibo.forecast.publicSignal.none")
    }

    var tiboLatestSocialEvidence: TiboSocialEvidence? {
        tiboSignalSnapshot.socialEvidence?.max { $0.postedAt < $1.postedAt }
    }

    var tiboSocialEvidenceTitle: String {
        guard let evidence = tiboLatestSocialEvidence else {
            return t("tibo.forecast.latestPost")
        }
        return evidence.isReply
            ? t("tibo.forecast.latestReply")
            : t("tibo.forecast.latestPost")
    }

    var tiboSocialEvidenceText: String? {
        tiboLatestSocialEvidence?.text
    }

    var tiboSocialEvidenceMetaText: String? {
        guard let evidence = tiboLatestSocialEvidence else { return nil }
        let timestamp = TiboResetSignalFormatter.compactLocalTimestamp(
            evidence.postedAt,
            localeIdentifier: appLanguage.localeIdentifier
        )
        guard evidence.isReply,
              let replyingTo = evidence.replyingTo,
              !replyingTo.isEmpty
        else { return timestamp }
        return t("tibo.forecast.replyMeta", timestamp, replyingTo)
    }

    var tiboSocialEvidenceAssessmentText: String {
        guard let kind = tiboLatestSocialEvidence?.signalKind else {
            return tiboForecastPublicSignalText
        }
        return t("tibo.forecast.socialAssessment.\(kind.rawValue)")
    }

    var tiboForecastLastResetAgeText: String? {
        let date = tiboForecast?.lastResetAt ?? tiboResetCycle.lastConfirmedSignal?.postedAt
        guard let date else { return nil }
        let days = max(0, clockNow.timeIntervalSince(date) / 86_400)
        return t("tibo.forecast.lastResetAgeValue", localizedDecimal(days))
    }

    var tiboForecastProgress: Double {
        Double(tiboForecast?.probability24hPercent ?? 0) / 100
    }

    var tiboForecastReferenceAt: Date? {
        tiboResetCycle.activePrediction?.expectedStart ?? tiboForecast?.sevenDayReferenceAt
    }

    var tiboForecastReferenceLabel: String {
        tiboResetCycle.activePrediction == nil
            ? t("tibo.forecast.sevenDayReference")
            : t("tibo.forecast.signalWindow")
    }

    var tiboForecastReferenceText: String {
        let cycle = tiboResetCycle
        if cycle.activePrediction != nil {
            return TiboResetSignalFormatter.compactLocalWindow(
                start: cycle.activePrediction?.expectedStart,
                end: cycle.activePrediction?.expectedEnd,
                localeIdentifier: appLanguage.localeIdentifier
            ) ?? t("tibo.cycle.windowPending")
        }
        guard let date = tiboForecast?.sevenDayReferenceAt else { return "—" }
        return tiboCycleTimeText(date)
    }

    var tiboForecastCountdownText: String {
        let cycle = tiboResetCycle
        let target = cycle.activePrediction?.expectedEnd
            ?? cycle.activePrediction?.expectedStart
            ?? tiboForecast?.sevenDayReferenceAt
        guard let target else { return t("tibo.forecast.countdownUnavailable") }
        guard let countdown = TiboResetSignalFormatter.countdown(to: target, now: clockNow) else {
            return t("tibo.forecast.referenceReached")
        }
        let basis = cycle.activePrediction == nil
            ? t("tibo.forecast.sevenDayBasis")
            : t("tibo.forecast.announcedBasis")
        return t("tibo.forecast.countdown", countdown, basis)
    }

    var tiboForecastLastConfirmedText: String {
        let date = tiboForecast?.lastResetAt ?? tiboResetCycle.lastConfirmedSignal?.postedAt
        guard let date else { return t("tibo.cycle.notObserved") }
        return TiboResetSignalFormatter.localTimestamp(
            date,
            localeIdentifier: appLanguage.localeIdentifier
        )
    }

    var tiboForecastCadenceText: String? {
        guard let cadence = tiboForecast?.cadence else { return nil }
        return t(
            "tibo.forecast.cadenceValue",
            cadence.recentSample,
            localizedDecimal(cadence.recentMedianDays),
            localizedDecimal(cadence.weightedMeanDays)
        )
    }

    var tiboForecastCommonWindowText: String? {
        guard let window = tiboForecast?.commonTimeWindow else { return nil }
        return t("tibo.forecast.commonWindowValue", window.label, window.timeZoneIdentifier)
    }

    var tiboForecastConfidenceText: String {
        guard let confidence = tiboForecast?.confidence else {
            return t("tibo.forecast.confidence.unknown")
        }
        return t("tibo.forecast.confidence.\(confidence.rawValue)")
    }

    var tiboForecastResetReasonText: String? {
        guard let reason = tiboForecast?.latestResetReason else { return nil }
        return t("tibo.forecast.reason.\(reason.rawValue)")
    }

    private func localizedDecimal(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: appLanguage.localeIdentifier)
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.1f", value)
    }

    var tiboCycleHasSource: Bool {
        let cycle = tiboResetCycle
        return cycle.activeSignal != nil || cycle.lastConfirmedSignal != nil
    }

    func tiboCycleTimeText(_ date: Date) -> String {
        TiboResetSignalFormatter.compactLocalTimestamp(
            date,
            localeIdentifier: appLanguage.localeIdentifier
        )
    }

    func menuLayoutChanged() {
        menuLayoutRevision &+= 1
    }

    func menuPageChanged() {
        menuLayoutRevision &+= 1
    }

    func chooseCodexHome() {
        let panel = NSOpenPanel()
        panel.title = t("account.importHome")
        panel.message = t("account.importHomeHelp")
        panel.prompt = t("action.addAccount")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: (codexHomePath as NSString).expandingTildeInPath)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        registerAccountHome(url.path)
        switchToAccountHome(url.path, expectedAccountID: nil)
    }

    func switchAccount(to account: CodexAccountUsageSnapshot, mode: AccountSwitchMode = .monitorOnly) {
        selectedAccountID = account.id
        accountActionMessage = nil
        switch mode {
        case .monitorOnly:
            switchToAccountHome(credentialHomePath(for: account), expectedAccountID: account.id)
            accountActionMessage = t("account.monitoring", accountName(account))
        case .activateCodex:
            activateCodexAccount(account)
        }
    }

    func forgetSelectedAccount() {
        guard let account = selectedAccount else { return }
        let credentialHome = credentialHomePath(for: account)
        accountSnapshots.removeAll { $0.id == account.id }
        quotaHistorySamples = QuotaUsageHistoryStore.removing(
            accountID: account.id,
            from: quotaHistorySamples
        )
        try? QuotaUsageHistoryStore.save(quotaHistorySamples)
        accountCredentialHomes.removeValue(forKey: account.id)
        accountHomePaths.removeAll {
            let candidate = Self.standardizedPath($0)
            return candidate == Self.standardizedPath(account.codexHome)
                || candidate == Self.standardizedPath(credentialHome)
        }
        try? CodexAccountUsageStore.save(accountSnapshots)
        let next = accountSnapshots.first
        selectedAccountID = next?.id
        activeAccountID = nil
        let fallback = next.map(credentialHomePath(for:)) ?? Self.runtimeCodexHomeURL.path
        registerAccountHome(fallback)
        switchToAccountHome(fallback, expectedAccountID: next?.id)
    }

    func exportCSV() {
        export(data: UsageExporter.csv(records: filteredRecords), extension: "csv")
    }

    func exportJSON() {
        do {
            export(data: try UsageExporter.json(snapshot: snapshot), extension: "json")
        } catch {
            exportMessage = t("export.failed", error.localizedDescription)
        }
    }

    func persistPreferences() {
        defaults.set(codexHomePath, forKey: "codexHomePath")
        defaults.set(includeArchived, forKey: "includeArchived")
        defaults.set(autoRefresh, forKey: "autoRefresh")
        defaults.set(menuBarMetric.rawValue, forKey: "menuBarMetric")
        defaults.set(selectedAccountID, forKey: "selectedAccountID")
        defaults.set(selectedLiveContextID, forKey: "selectedLiveContextID")
        defaults.set(accountHomePaths, forKey: "accountHomePaths")
        defaults.set(accountCredentialHomes, forKey: "accountCredentialHomes")
        defaults.set(pendingOAuthHomePath, forKey: "pendingOAuthHomePath")
        defaults.set(appTheme.rawValue, forKey: "appTheme")
        defaults.set(appLanguage.rawValue, forKey: "appLanguage")
        defaults.set(liveRefreshRate.rawValue, forKey: "liveRefreshRate")
        defaults.set(discoveryRate.rawValue, forKey: "discoveryRate")
        defaults.set(accountRefreshRate.rawValue, forKey: "accountRefreshRate")
        defaults.set(liveTaskLimit.rawValue, forKey: "liveTaskLimit")
        defaults.set(showAPIEstimate, forKey: "showAPIEstimate")
        defaults.set(showRuntimeWindow, forKey: "showRuntimeWindow")
        defaults.set(showConcurrentTaskCount, forKey: "showConcurrentTaskCount")
        defaults.set(privacyMode, forKey: "privacyMode")
        defaults.set(restartCodexAfterSwitch, forKey: "restartCodexAfterSwitch")
        defaults.set(tiboMonitoringEnabled, forKey: "tiboMonitoringEnabled")
    }

    func refreshLaunchAtLoginState() {
        let status = launchAtLoginController.status
        launchAtLoginEnabled = status == .enabled || status == .requiresApproval
        launchAtLoginRequiresApproval = status == .requiresApproval
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        if enabled, launchAtLoginController.registrationIssue == .readOnlyVolume {
            launchAtLoginErrorMessage = t("console.launchAtLoginMoveToApplications")
            refreshLaunchAtLoginState()
            return
        }

        do {
            if enabled {
                try launchAtLoginController.register()
            } else {
                try launchAtLoginController.unregister()
            }
            launchAtLoginErrorMessage = nil
        } catch {
            launchAtLoginErrorMessage = t("console.launchAtLoginFailed", error.localizedDescription)
        }
        refreshLaunchAtLoginState()
    }

    func openLoginItemsSettings() {
        launchAtLoginController.openSystemSettings()
    }

    func rebuildIndex() {
        try? FileManager.default.removeItem(at: UsageCacheStore.defaultURL)
        snapshot = .empty
        hasLoaded = true
        refresh()
    }

    private func export(data: Data, extension fileExtension: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "codex-usage-\(Self.fileDateFormatter.string(from: Date())).\(fileExtension)"
        panel.allowedContentTypes = fileExtension == "csv" ? [.commaSeparatedText] : [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url, options: .atomic)
            exportMessage = t("export.done", url.lastPathComponent)
        } catch {
            exportMessage = t("export.failed", error.localizedDescription)
        }
    }

    private func liveCost(
        for usage: TokenUsage?,
        applyLongContextMultiplier: Bool
    ) -> CostBreakdown? {
        guard let usage, let model = liveContext?.model else { return nil }
        let value = BillingCalculator.cost(
            for: usage,
            model: model,
            applyLongContextMultiplier: applyLongContextMultiplier
        )
        return value.isPriced ? value : nil
    }

    private func liveTurnCost() -> CostBreakdown? {
        guard let context = liveContext, !context.currentTurnCalls.isEmpty else { return nil }
        let value = BillingCalculator.cost(
            calls: context.currentTurnCalls
        )
        return value.isPriced ? value : nil
    }

    private static func tiboErrorCode(_ error: Error) -> String {
        if let value = error as? URLError { return "url.\(value.code.rawValue)" }
        if let value = error as? TiboResetSignalError {
            switch value {
            case .invalidResponse: return "invalid-response"
            case .http(let status): return "http.\(status)"
            case .invalidPayload: return "invalid-payload"
            }
        }
        return String(describing: type(of: error))
    }

    private func switchToAccountHome(_ path: String, expectedAccountID: String?) {
        let normalized = Self.standardizedPath(path)
        codexHomePath = normalized
        activeAccountID = nil
        if let expectedAccountID { selectedAccountID = expectedAccountID }
        snapshot = .empty
        threadMetadataByID = [:]
        liveContexts = []
        liveContext = nil
        selectedLiveContextID = nil
        liveContextErrorMessage = nil
        lastLiveDiscoveryAt = .distantPast
        persistPreferences()
        liveContextTick(forceDiscover: true)
        refresh()
    }

    private func registerAccountHome(_ path: String) {
        accountHomePaths = Self.uniquePaths(accountHomePaths + [path])
        defaults.set(accountHomePaths, forKey: "accountHomePaths")
    }

    func importAuthJSON() {
        let panel = NSOpenPanel()
        panel.title = t("account.importJSON")
        panel.message = t("account.importJSONHelp")
        panel.prompt = t("account.import")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.json, .plainText]
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }

        do {
            var imported: [ImportedCodexCredential] = []
            var seen = Set<String>()
            for source in panel.urls {
                let data = try Data(contentsOf: source, options: [.mappedIfSafe])
                for credential in try CodexCredentialImportAdapter.decode(data) where seen.insert(credential.accountID).inserted {
                    imported.append(credential)
                }
            }
            try installImportedCredentials(imported)
        } catch {
            accountErrorMessage = t("account.importFailed", localizedErrorText(error))
        }
    }

    func inspectCredentialText(_ text: String) -> CredentialInputInspection {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return CredentialInputInspection(
                isValid: false,
                accountCount: 0,
                formatSummary: "",
                message: t("account.tokenEmpty")
            )
        }
        do {
            let credentials = try CodexCredentialImportAdapter.decode(text: text)
            let formats = Set(credentials.map(\.format.rawValue)).sorted().joined(separator: " + ")
            return CredentialInputInspection(
                isValid: true,
                accountCount: credentials.count,
                formatSummary: formats,
                message: t("account.tokenParsed", credentials.count, formats)
            )
        } catch {
            return CredentialInputInspection(
                isValid: false,
                accountCount: 0,
                formatSummary: "",
                message: localizedErrorText(error)
            )
        }
    }

    /// Imports pasted token/JSON text and optionally commits the first parsed
    /// account to Codex's live auth.json using the same atomic switch path as
    /// the Cockpit-style account picker.
    @discardableResult
    func importCredentialText(_ text: String, activateCodex: Bool) -> Bool {
        do {
            let credentials = try CodexCredentialImportAdapter.decode(text: text)
            try installImportedCredentials(credentials)
            guard activateCodex, let first = credentials.first else { return true }
            guard let account = accountSnapshots.first(where: { $0.id == first.accountID }) else {
                throw CodexCredentialImportError.noSupportedAccounts
            }
            return activateCodexAccount(account)
        } catch {
            accountErrorMessage = t("account.importFailed", localizedErrorText(error))
            return false
        }
    }

    func checkPendingOAuth(announceWhenWaiting: Bool = true) {
        guard let pendingOAuthHomePath else { return }
        let home = URL(fileURLWithPath: pendingOAuthHomePath, isDirectory: true)
        guard CodexCredentialStore.hasUsableAuth(in: home) else {
            if announceWhenWaiting { accountActionMessage = t("account.oauthWaiting") }
            return
        }
        self.pendingOAuthHomePath = nil
        defaults.removeObject(forKey: "pendingOAuthHomePath")
        registerAccountHome(home.path)
        if let data = try? CodexCredentialStore.authData(in: home),
           let accountID = CodexCredentialStore.stableAccountID(from: data) {
            accountCredentialHomes[accountID] = home.path
        }
        accountActionMessage = t("account.oauthReady")
        switchToAccountHome(home.path, expectedAccountID: nil)
    }

    func beginOAuthLogin() {
        do {
            let profile = try makeAccountProfile(prefix: "oauth")

            let executable = try Self.resolveCodexExecutable()
            let command = profile.deletingLastPathComponent().appendingPathComponent("Codex OAuth Login.command")
            let script = """
            #!/bin/zsh
            clear
            echo 'Codex Lens · Codex OAuth'
            echo 'Complete authorization in the browser, then return to Codex Lens.'
            export CODEX_HOME=\(Self.shellQuote(profile.path))
            \(Self.shellQuote(executable.path)) login
            echo
            echo 'OAuth flow finished. You can close this window.'
            """
            try script.write(to: command, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: command.path)
            NSWorkspace.shared.open(command)
            pendingOAuthHomePath = profile.path
            accountActionMessage = t("account.oauthPending")
            persistPreferences()
        } catch {
            accountErrorMessage = t("account.oauthFailed", localizedErrorText(error))
        }
    }

    @discardableResult
    private func activateCodexAccount(_ account: CodexAccountUsageSnapshot) -> Bool {
        guard !isAccountSwitching else { return false }
        isAccountSwitching = true
        defer { isAccountSwitching = false }
        do {
            let sourceHome = URL(fileURLWithPath: credentialHomePath(for: account), isDirectory: true)
            let targetData = try CodexCredentialStore.authData(in: sourceHome)
            if let credentialID = CodexCredentialStore.stableAccountID(from: targetData),
               credentialID != account.id {
                throw CodexCredentialStoreError.credentialMismatch
            }

            let runningCodexApps = NSWorkspace.shared.runningApplications.filter {
                $0.bundleIdentifier == Self.codexDesktopBundleIdentifier
            }
            let relaunchURL = runningCodexApps.first?.bundleURL
                ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.codexDesktopBundleIdentifier)
            if restartCodexAfterSwitch {
                runningCodexApps.forEach { _ = $0.terminate() }
            }

            let runtimeHome = Self.runtimeCodexHomeURL
            let currentData = try? CodexCredentialStore.authData(in: runtimeHome)
            let committedData = try CodexCredentialStore.mergedAuth(target: targetData, preserving: currentData)
            if currentData != committedData {
                if let currentData {
                    try preserveRuntimeCredential(currentData, excluding: account.id)
                    try createSafetyBackup(currentData)
                }
                try CodexCredentialStore.install(committedData, in: runtimeHome)
            }
            accountCredentialHomes[account.id] = sourceHome.standardizedFileURL.path
            codexLoginAccountID = account.id
            accountActionMessage = restartCodexAfterSwitch && !runningCodexApps.isEmpty
                ? t("account.codexActivatedRestarting", accountName(account))
                : t("account.codexActivated", accountName(account))
            persistPreferences()
            switchToAccountHome(runtimeHome.path, expectedAccountID: account.id)
            if restartCodexAfterSwitch, !runningCodexApps.isEmpty, let relaunchURL {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                    NSWorkspace.shared.openApplication(
                        at: relaunchURL,
                        configuration: NSWorkspace.OpenConfiguration()
                    )
                }
            }
            return true
        } catch {
            accountErrorMessage = t("account.switchFailed", localizedErrorText(error))
            return false
        }
    }

    private func installImportedCredentials(_ credentials: [ImportedCodexCredential]) throws {
        guard !credentials.isEmpty else { throw CodexCredentialImportError.noSupportedAccounts }
        var installed: [(ImportedCodexCredential, URL)] = []
        for credential in credentials {
            let existingPath = accountCredentialHomes[credential.accountID].map {
                URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL
            }
            let profile: URL
            if let existingPath,
               existingPath.path.hasPrefix(Self.accountProfilesRoot.standardizedFileURL.path + "/") {
                profile = existingPath
            } else {
                profile = try makeAccountProfile(prefix: credential.format.rawValue.lowercased())
            }
            try CodexCredentialStore.install(credential.authData, in: profile)
            accountCredentialHomes[credential.accountID] = profile.path
            registerAccountHome(profile.path)
            let placeholder = CodexAccountUsageSnapshot(
                id: credential.accountID,
                email: credential.email ?? credential.suggestedName,
                plan: credential.plan,
                codexHome: profile.path,
                primaryWindow: nil,
                secondaryWindow: nil,
                additionalWindows: [],
                credits: nil,
                updatedAt: Date()
            )
            accountSnapshots = CodexAccountUsageStore.upserting(placeholder, into: accountSnapshots)
            installed.append((credential, profile))
        }

        try? CodexAccountUsageStore.save(accountSnapshots)
        defaults.set(accountCredentialHomes, forKey: "accountCredentialHomes")
        let formats = Set(credentials.map(\.format.rawValue)).sorted().joined(separator: " + ")
        accountActionMessage = t("account.importedCount", credentials.count, formats)
        if let first = installed.first {
            selectedAccountID = first.0.accountID
            switchToAccountHome(first.1.path, expectedAccountID: first.0.accountID)
        }
        refreshImportedProfiles(Array(installed.dropFirst()))
    }

    private func refreshImportedProfiles(_ installed: [(ImportedCodexCredential, URL)]) {
        guard !installed.isEmpty else { return }
        Task {
            for (credential, home) in installed {
                let outcome = await Task.detached(priority: .utility) { () -> AccountFetchOutcome in
                    do { return .success(try CodexAccountService().fetch(codexHome: home)) }
                    catch { return .failure(error) }
                }.value
                if case .success(let snapshot) = outcome {
                    accountSnapshots = CodexAccountUsageStore.upserting(snapshot, into: accountSnapshots)
                    accountCredentialHomes[snapshot.id] = home.path
                    if snapshot.id != credential.accountID {
                        accountSnapshots.removeAll { $0.id == credential.accountID }
                        accountCredentialHomes.removeValue(forKey: credential.accountID)
                    }
                }
            }
            try? CodexAccountUsageStore.save(accountSnapshots)
            defaults.set(accountCredentialHomes, forKey: "accountCredentialHomes")
        }
    }

    private func preserveRuntimeCredential(_ data: Data, excluding targetAccountID: String) throws {
        guard let currentAccountID = CodexCredentialStore.stableAccountID(from: data),
              currentAccountID != targetAccountID
        else { return }
        let profile = Self.accountProfilesRoot
            .appendingPathComponent("saved-\(currentAccountID)", isDirectory: true)
            .appendingPathComponent(".codex", isDirectory: true)
        try CodexCredentialStore.install(data, in: profile)
        accountCredentialHomes[currentAccountID] = profile.path
        registerAccountHome(profile.path)
    }

    private func createSafetyBackup(_ data: Data) throws {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let backup = Self.credentialBackupsRoot
            .appendingPathComponent("\(formatter.string(from: Date()))-\(UUID().uuidString.prefix(6))", isDirectory: true)
            .appendingPathComponent(".codex", isDirectory: true)
        try CodexCredentialStore.install(data, in: backup)

        let manager = FileManager.default
        let directories = (try? manager.contentsOfDirectory(
            at: Self.credentialBackupsRoot,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        let sorted = directories.sorted {
            let left = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let right = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return left > right
        }
        for expired in sorted.dropFirst(5) { try? manager.removeItem(at: expired) }
    }

    private func makeAccountProfile(prefix: String) throws -> URL {
        let profile = Self.accountProfilesRoot
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: profile.path)
        return profile
    }

    private static func resolveCodexExecutable() throws -> URL {
        var candidates = [
            ProcessInfo.processInfo.environment["CODEX_EXECUTABLE"],
            "/usr/local/bin/codex",
            "/opt/homebrew/bin/codex",
        ].compactMap { $0 }
        let searchPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        candidates += searchPath.split(separator: ":").map { "\($0)/codex" }
        if let result = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return URL(fileURLWithPath: result)
        }
        throw CodexAccountServiceError.codexNotFound
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func standardizedPath(_ path: String) -> String {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
            .standardizedFileURL.path
    }

    private static func uniquePaths(_ paths: [String]) -> [String] {
        var seen = Set<String>()
        return paths.map(standardizedPath).filter { seen.insert($0).inserted }
    }

    private static var runtimeCodexHomeURL: URL {
        if let configured = ProcessInfo.processInfo.environment["CODEX_HOME"], !configured.isEmpty {
            return URL(fileURLWithPath: (configured as NSString).expandingTildeInPath, isDirectory: true)
                .standardizedFileURL
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
            .standardizedFileURL
    }

    private static var applicationSupportRoot: URL {
        (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser)
            .appendingPathComponent("CodexTokenLedger", isDirectory: true)
    }

    private static var accountProfilesRoot: URL {
        applicationSupportRoot.appendingPathComponent("Accounts", isDirectory: true)
    }

    private static var credentialBackupsRoot: URL {
        applicationSupportRoot.appendingPathComponent("CredentialBackups", isDirectory: true)
    }

    private static let codexDesktopBundleIdentifier = "com.openai.codex"

    private static func compactDecimal(_ value: Decimal) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }

    private static let fileDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

    private static let serverDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 1
        return formatter
    }()
}
