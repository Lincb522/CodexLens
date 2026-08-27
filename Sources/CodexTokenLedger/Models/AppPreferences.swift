import Foundation

protocol AppLocalizedError: LocalizedError {
    var localizationKey: String { get }
    var localizationArguments: [CVarArg] { get }
}

extension AppLocalizedError {
    var localizationArguments: [CVarArg] { [] }

    var errorDescription: String? {
        LocalizationCatalog.text(
            localizationKey,
            language: .system,
            arguments: localizationArguments
        )
    }
}
import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case zhHans
    case zhHant
    case english
    case japanese
    case korean
    case spanish
    case french

    var id: String { rawValue }
    var autonym: String {
        switch self {
        case .system: "System"
        case .zhHans: "简体中文"
        case .zhHant: "繁體中文"
        case .english: "English"
        case .japanese: "日本語"
        case .korean: "한국어"
        case .spanish: "Español"
        case .french: "Français"
        }
    }

    var effective: AppLanguage {
        guard self == .system else { return self }
        let identifier = Locale.preferredLanguages.first?.lowercased() ?? "en"
        if identifier.hasPrefix("zh-hant") || identifier.hasPrefix("zh-tw") || identifier.hasPrefix("zh-hk") { return .zhHant }
        if identifier.hasPrefix("zh") { return .zhHans }
        if identifier.hasPrefix("ja") { return .japanese }
        if identifier.hasPrefix("ko") { return .korean }
        if identifier.hasPrefix("es") { return .spanish }
        if identifier.hasPrefix("fr") { return .french }
        return .english
    }

    var localeIdentifier: String {
        switch effective {
        case .zhHans: "zh-Hans"
        case .zhHant: "zh-Hant"
        case .japanese: "ja"
        case .korean: "ko"
        case .spanish: "es"
        case .french: "fr"
        default: "en"
        }
    }

    var localizationResourceName: String { localeIdentifier }
}

enum LiveRefreshRate: Double, CaseIterable, Identifiable {
    case one = 1
    case two = 2
    case five = 5
    case ten = 10
    var id: Double { rawValue }
}

enum DiscoveryRate: Double, CaseIterable, Identifiable {
    case five = 5
    case ten = 10
    case thirty = 30
    case sixty = 60
    var id: Double { rawValue }
}

enum AccountRefreshRate: Double, CaseIterable, Identifiable {
    case oneMinute = 60
    case fiveMinutes = 300
    case fifteenMinutes = 900
    case thirtyMinutes = 1800
    var id: Double { rawValue }
}

enum LiveTaskLimit: Int, CaseIterable, Identifiable {
    case four = 4
    case eight = 8
    case twelve = 12
    var id: Int { rawValue }
}

enum LocalizationCatalog {
    private final class BundleToken {}

    private static let requiredKeys: Set<String> = [
        "activeTasks.empty",
        "account.activateCodex",
        "account.activateHelp",
        "account.addCodex",
        "account.addHelp",
        "account.addMore",
        "account.addTitle",
        "account.codexActivated",
        "account.codexActivatedRestarting",
        "account.connecting",
        "account.current",
        "account.dailyOn",
        "account.dataSource",
        "account.forecast",
        "account.forecastCollecting",
        "account.forecastDepletes",
        "account.forecastNoConsumption",
        "account.forecastReset",
        "account.forecastSamples",
        "account.forecastStable",
        "account.import",
        "account.importFailed",
        "account.importHome",
        "account.importHomeHelp",
        "account.importJSON",
        "account.importJSONHelp",
        "account.imported",
        "account.importedCount",
        "account.lifetime",
        "account.monitorHelp",
        "account.monitorOnly",
        "account.monitorShort",
        "account.monitoring",
        "account.moreAccounts",
        "account.noReadable",
        "account.oauth",
        "account.oauthCheck",
        "account.oauthFailed",
        "account.oauthPending",
        "account.oauthReady",
        "account.oauthWaiting",
        "account.official",
        "account.reading",
        "account.restartAfterSwitch",
        "account.serverTotal",
        "account.stale",
        "account.switchFailed",
        "account.switchMode",
        "account.switchShort",
        "account.syncing",
        "account.today",
        "account.token",
        "account.tokenEmpty",
        "account.tokenInputPlaceholder",
        "account.tokenLogin",
        "account.tokenLoginHelp",
        "account.tokenModeActivate",
        "account.tokenModeMonitor",
        "account.tokenModeTitle",
        "account.tokenParsed",
        "account.tokenPaste",
        "account.tokenPrivacy",
        "account.tokenSave",
        "account.tokenSubmit",
        "account.total",
        "account.unavailable",
        "account.windowPrimary",
        "account.windowWeekly",
        "about.buildValue",
        "about.source",
        "about.versionValue",
        "about.website",
        "about.websitePlaceholder",
        "action.addAccount",
        "action.back",
        "action.cancel",
        "action.choose",
        "action.clear",
        "action.exportCSV",
        "action.exportJSON",
        "action.quit",
        "action.rebuild",
        "action.rediscover",
        "action.remove",
        "action.retry",
        "action.sync",
        "confidence.high",
        "confidence.low",
        "confidence.medium",
        "console.about",
        "console.accountSync",
        "console.accounts",
        "console.appearance",
        "console.archived",
        "console.autoSync",
        "console.data",
        "console.details",
        "console.developer",
        "console.discovery",
        "console.files",
        "console.home",
        "console.language",
        "console.launchAtLogin",
        "console.launchAtLoginApproval",
        "console.launchAtLoginFailed",
        "console.launchAtLoginMoveToApplications",
        "console.live",
        "console.liveRefresh",
        "console.menu",
        "console.metric",
        "console.minutes",
        "console.notRead",
        "console.note",
        "console.openLoginItems",
        "console.pricing",
        "console.privacy",
        "console.quickSwitch",
        "console.runtime",
        "console.saved",
        "console.seconds",
        "console.taskCount",
        "console.taskLimit",
        "console.tasks",
        "console.theme",
        "console.tiboMonitoring",
        "console.version",
        "control.toggle",
        "developer.product",
        "developer.project",
        "developer.role",
        "developer.tagline",
        "evidence.apiEstimate",
        "evidence.codexExact",
        "evidence.derivedExact",
        "evidence.officialShort",
        "evidence.quotaForecast",
        "evidence.serverOfficial",
        "evidence.unavailable",
        "error.account.codexNotFound",
        "error.account.invalidResponse",
        "error.account.launchFailed",
        "error.account.rpcEnded",
        "error.account.rpcError",
        "error.credentials.authMissing",
        "error.credentials.fileTooLarge",
        "error.credentials.invalidJSON",
        "error.credentials.mismatch",
        "error.credentials.unsupported",
        "error.import.invalidJSON",
        "error.import.invalidToken",
        "error.import.noSupportedAccounts",
        "error.import.payloadTooLarge",
        "error.import.tooManyAccounts",
        "error.tibo.http",
        "error.tibo.invalidPayload",
        "error.tibo.invalidResponse",
        "error.live.noSessions",
        "error.scanner.homeNotFound",
        "error.scanner.noSessions",
        "error.thread.sqlite",
        "export.done",
        "export.failed",
        "footer.console",
        "footer.noAccount",
        "footer.syncFailed",
        "footer.syncing",
        "footer.updated",
        "footer.updatedDuration",
        "ledger.available",
        "ledger.credits",
        "ledger.indexing",
        "ledger.local",
        "ledger.localShort",
        "ledger.unlimited",
        "legal.disclaimer",
        "legal.disclaimer.page1",
        "legal.disclaimer.page2",
        "legal.openSource",
        "legal.openSource.page1",
        "legal.openSource.page2",
        "legal.privacy",
        "legal.privacy.page1",
        "legal.privacy.page2",
        "legal.userAgreement",
        "legal.userAgreement.page1",
        "legal.userAgreement.page2",
        "live.apiMissing",
        "live.apiEstimate",
        "live.cached",
        "live.capture",
        "live.contextA11y",
        "live.currentTurn",
        "live.estimate",
        "live.estimateValue",
        "live.exact",
        "live.flowA11y",
        "live.flowDetail",
        "live.input",
        "live.inputContextShort",
        "live.longRate",
        "live.noEvents",
        "live.noRate",
        "live.output",
        "live.remaining",
        "live.runtime",
        "live.single",
        "live.standardRate",
        "live.tasks",
        "live.total",
        "live.turn",
        "live.waiting",
        "local.exactHelp",
        "local.scope",
        "metric.context",
        "metric.credits",
        "metric.iconOnly",
        "metric.quota",
        "metric.requestCredits",
        "metric.weekly",
        "overview.tab.account",
        "overview.tab.quota",
        "overview.tab.task",
        "overview.updates",
        "page.about",
        "page.console",
        "page.developer",
        "page.activeTasks",
        "page.ledger",
        "page.more",
        "page.overview",
        "page.tiboSignal",
        "page.tokenLogin",
        "page.updates",
        "quota.empty",
        "quota.fiveHours",
        "quota.days",
        "quota.hours",
        "quota.namedWeekly",
        "quota.radar",
        "quota.reset",
        "quota.review",
        "quota.used",
        "quota.weekly",
        "quota.windows",
        "sessions.empty",
        "sessions.notice",
        "sessions.search",
        "status.loading",
        "status.off",
        "status.on",
        "status.switch",
        "task.source.desktopCatalog",
        "task.source.explicitName",
        "task.source.firstUserMessage",
        "task.source.preview",
        "task.source.projectDirectory",
        "task.source.stateTitle",
        "subtitle.console",
        "subtitle.ledger",
        "subtitle.tiboSignal",
        "subtitle.tokenLogin",
        "subtitle.updates",
        "theme.dark",
        "theme.light",
        "theme.system",
        "tibo.badge",
        "tibo.cycle.awaitingFirst",
        "tibo.cycle.currentSignal",
        "tibo.cycle.expected",
        "tibo.cycle.lastConfirmed",
        "tibo.cycle.noBaseline",
        "tibo.cycle.noNewSignal",
        "tibo.cycle.notObserved",
        "tibo.cycle.openPost",
        "tibo.cycle.overviewCandidate",
        "tibo.cycle.overviewConfirmed",
        "tibo.cycle.overviewPrediction",
        "tibo.cycle.pending",
        "tibo.cycle.predictedTime",
        "tibo.cycle.predictionActive",
        "tibo.cycle.provisional",
        "tibo.cycle.publicScope",
        "tibo.cycle.signalActive",
        "tibo.cycle.title",
        "tibo.cycle.waiting",
        "tibo.cycle.waitingSignal",
        "tibo.cycle.weeklyBaseline",
        "tibo.cycle.windowPending",
        "tibo.detail.accountRelation",
        "tibo.detail.announcementType",
        "tibo.detail.evidence",
        "tibo.detail.localTime",
        "tibo.detail.manualGlobalReset",
        "tibo.detail.matchedRule",
        "tibo.detail.meaning",
        "tibo.detail.notAccountReset",
        "tibo.detail.openSource",
        "tibo.detail.postID",
        "tibo.detail.refresh",
        "tibo.detail.rule",
        "tibo.detail.scope",
        "tibo.detail.scopeAll",
        "tibo.detail.source",
        "tibo.detail.sourceStatus",
        "tibo.detail.sourceTime",
        "tibo.detail.technical",
        "tibo.feed.empty",
        "tibo.feed.title",
        "tibo.globalAnnouncement",
        "tibo.globalHelp",
        "tibo.help.cached",
        "tibo.help.none",
        "tibo.help.signal",
        "tibo.short.candidate",
        "tibo.short.checking",
        "tibo.short.confirmed",
        "tibo.short.expected",
        "tibo.short.none",
        "tibo.short.unavailable",
        "tibo.signalTitle",
        "tibo.source.degraded",
        "tibo.source.healthy",
        "tibo.source.idle",
        "tibo.source.offline",
        "tibo.status.candidate",
        "tibo.status.checking",
        "tibo.status.confirmed",
        "tibo.status.expected",
        "tibo.status.none",
        "tibo.status.unavailable",
        "update.automatic",
        "update.automaticChecks",
        "update.automaticDownloads",
        "update.available",
        "update.availableShort",
        "update.check",
        "update.checking",
        "update.checkingShort",
        "update.checkNow",
        "update.current",
        "update.currentShort",
        "update.failed",
        "update.failedShort",
        "update.installOnQuit",
        "update.lastChecked",
        "update.never",
        "update.releaseNote.fixedHeight",
        "update.releaseNote.history",
        "update.releaseNote.localized",
        "update.releaseNotes",
        "update.ready",
        "update.readyShort"
    ]

    static func text(_ key: String, language: AppLanguage, arguments: [CVarArg] = []) -> String {
        let localizedBundle = bundle(for: language.effective)
        let fallbackBundle = bundle(for: .english)
        let fallback = fallbackBundle.localizedString(forKey: key, value: key, table: "Localizable")
        let format = localizedBundle.localizedString(forKey: key, value: fallback, table: "Localizable")
        guard !arguments.isEmpty else { return format }
        return String(format: format, locale: Locale(identifier: language.localeIdentifier), arguments: arguments)
    }

    static func missingKeys(for language: AppLanguage) -> [String] {
        let values = localizedStrings(for: language.effective)
        return requiredKeys.subtracting(values.keys).sorted()
    }

    private static func bundle(for language: AppLanguage) -> Bundle {
        let root = Bundle(for: BundleToken.self)
        guard let path = root.path(forResource: language.localizationResourceName, ofType: "lproj"),
              let localized = Bundle(path: path)
        else { return root }
        return localized
    }

    private static func localizedStrings(for language: AppLanguage) -> [String: String] {
        let localized = bundle(for: language)
        guard let url = localized.url(forResource: "Localizable", withExtension: "strings"),
              let dictionary = NSDictionary(contentsOf: url) as? [String: String]
        else { return [:] }
        return dictionary
    }
}
