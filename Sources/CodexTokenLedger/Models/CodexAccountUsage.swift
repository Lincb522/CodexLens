import Foundation

struct CodexQuotaWindow: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let title: String
    let usedPercent: Double
    let windowMinutes: Int?
    let resetsAt: Date?
    let limitID: String?
    let limitName: String?

    init(
        id: String,
        title: String,
        usedPercent: Double,
        windowMinutes: Int?,
        resetsAt: Date?,
        limitID: String? = nil,
        limitName: String? = nil
    ) {
        self.id = id
        self.title = title
        self.usedPercent = usedPercent
        self.windowMinutes = windowMinutes
        self.resetsAt = resetsAt
        self.limitID = limitID
        self.limitName = limitName
    }

    var clampedUsedPercent: Double { min(100, max(0, usedPercent)) }
    var remainingPercent: Double { max(0, 100 - clampedUsedPercent) }
}

struct CodexScopedQuotaGroup: Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let windows: [CodexQuotaWindow]
}

struct CodexCreditBalance: Codable, Hashable, Sendable {
    let hasCredits: Bool
    let unlimited: Bool
    let balance: Double?
}

struct CodexAccountTokenUsageSummary: Codable, Hashable, Sendable {
    let lifetimeTokens: Int64?
    let peakDailyTokens: Int64?
    let longestRunningTurnSeconds: Int64?
    let currentStreakDays: Int64?
    let longestStreakDays: Int64?
}

struct CodexAccountDailyTokenUsage: Codable, Hashable, Identifiable, Sendable {
    var id: String { startDate }
    let startDate: String
    let tokens: Int64
}

struct CodexAccountTokenUsage: Codable, Hashable, Sendable {
    let summary: CodexAccountTokenUsageSummary
    let dailyBuckets: [CodexAccountDailyTokenUsage]

    var latestDailyUsage: CodexAccountDailyTokenUsage? {
        dailyBuckets.max { String($0.startDate.prefix(10)) < String($1.startDate.prefix(10)) }
    }
}

struct CodexAccountUsageSnapshot: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let email: String?
    let plan: String?
    let codexHome: String
    let primaryWindow: CodexQuotaWindow?
    let secondaryWindow: CodexQuotaWindow?
    let additionalWindows: [CodexQuotaWindow]
    let credits: CodexCreditBalance?
    let accountTokenUsage: CodexAccountTokenUsage?
    let updatedAt: Date

    init(
        id: String,
        email: String?,
        plan: String?,
        codexHome: String,
        primaryWindow: CodexQuotaWindow?,
        secondaryWindow: CodexQuotaWindow?,
        additionalWindows: [CodexQuotaWindow],
        credits: CodexCreditBalance?,
        accountTokenUsage: CodexAccountTokenUsage? = nil,
        updatedAt: Date
    ) {
        self.id = id
        self.email = email
        self.plan = plan
        self.codexHome = codexHome
        self.primaryWindow = primaryWindow
        self.secondaryWindow = secondaryWindow
        self.additionalWindows = additionalWindows
        self.credits = credits
        self.accountTokenUsage = accountTokenUsage
        self.updatedAt = updatedAt
    }

    var displayName: String {
        let normalized = email?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return normalized.isEmpty ? "Codex" : normalized
    }

    var planDisplayName: String {
        let normalized = plan?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return normalized.isEmpty ? "Codex" : normalized.uppercased()
    }

    var allWindows: [CodexQuotaWindow] {
        accountQuotaWindows + additionalWindows
    }

    var accountQuotaWindows: [CodexQuotaWindow] {
        [primaryWindow, secondaryWindow].compactMap { $0 }
    }

    var additionalQuotaGroups: [CodexScopedQuotaGroup] {
        var order: [String] = []
        var names: [String: String] = [:]
        var grouped: [String: [CodexQuotaWindow]] = [:]

        for window in additionalWindows {
            let groupID = window.limitID ?? window.id
            if grouped[groupID] == nil { order.append(groupID) }
            grouped[groupID, default: []].append(window)
            names[groupID] = window.limitName ?? window.title
        }

        return order.compactMap { id in
            guard let windows = grouped[id], let name = names[id] else { return nil }
            return CodexScopedQuotaGroup(id: id, name: name, windows: windows)
        }
    }

    var preferredMenuWindow: CodexQuotaWindow? {
        primaryWindow ?? secondaryWindow
    }

    var weeklyWindow: CodexQuotaWindow? {
        accountQuotaWindows.first { ($0.windowMinutes ?? 0) >= 6 * 24 * 60 }
            ?? secondaryWindow
    }
}

struct CodexAccountUsageCache: Codable, Sendable {
    let version: Int
    var accounts: [CodexAccountUsageSnapshot]
}
