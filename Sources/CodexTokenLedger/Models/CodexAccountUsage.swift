import Foundation

struct CodexQuotaWindow: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let title: String
    let usedPercent: Double
    let windowMinutes: Int?
    let resetsAt: Date?

    var clampedUsedPercent: Double { min(100, max(0, usedPercent)) }
    var remainingPercent: Double { max(0, 100 - clampedUsedPercent) }
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

    var latestDailyUsage: CodexAccountDailyTokenUsage? { dailyBuckets.last }
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
        [primaryWindow, secondaryWindow].compactMap { $0 } + additionalWindows
    }

    var preferredMenuWindow: CodexQuotaWindow? {
        primaryWindow ?? additionalWindows.first
    }

    var weeklyWindow: CodexQuotaWindow? {
        allWindows.first { ($0.windowMinutes ?? 0) >= 6 * 24 * 60 }
            ?? secondaryWindow
    }
}

struct CodexAccountUsageCache: Codable, Sendable {
    let version: Int
    var accounts: [CodexAccountUsageSnapshot]
}
