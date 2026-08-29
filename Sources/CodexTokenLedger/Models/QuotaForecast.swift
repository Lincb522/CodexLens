import Foundation

struct QuotaUsageSample: Codable, Hashable, Identifiable, Sendable {
    let accountID: String
    let windowID: String
    let observedAt: Date
    let usedPercent: Double
    let resetsAt: Date?
    let windowMinutes: Int?
    /// Exact account lifetime counter returned by `account/usage/read` at the
    /// same observation instant. Older stored samples decode as nil.
    let lifetimeTokens: Int64?

    init(
        accountID: String,
        windowID: String,
        observedAt: Date,
        usedPercent: Double,
        resetsAt: Date?,
        windowMinutes: Int?,
        lifetimeTokens: Int64? = nil
    ) {
        self.accountID = accountID
        self.windowID = windowID
        self.observedAt = observedAt
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.windowMinutes = windowMinutes
        self.lifetimeTokens = lifetimeTokens
    }

    var id: String {
        "\(accountID)|\(windowID)|\(observedAt.timeIntervalSince1970)"
    }
}

enum QuotaForecastConfidence: String, Codable, Hashable, Sendable {
    case low
    case medium
    case high
}

enum QuotaForecastState: String, Codable, Hashable, Sendable {
    case collecting
    case noSustainedConsumption
    case lastsUntilReset
    case depletesBeforeReset
}

struct QuotaForecast: Hashable, Sendable {
    let state: QuotaForecastState
    let estimatedTimeToExhaustion: TimeInterval?
    let timeToReset: TimeInterval?
    let sampleCount: Int
    let observationSpan: TimeInterval
    let confidence: QuotaForecastConfidence
    let usedPercentPerHour: Double?
}

struct QuotaCapacityEstimate: Hashable, Sendable {
    enum Evidence: Hashable, Sendable {
        case pairedAccountCounters
        case currentCycleLocalLedger
    }

    let estimatedTotalTokens: Int64
    let estimatedRemainingTokens: Int64
    let tokensPerPercent: Double
    let samplePairCount: Int
    let observationSpan: TimeInterval
    let confidence: QuotaForecastConfidence
    let evidence: Evidence
    let observedTokens: Int64?
}

struct LocalQuotaCycleUsage: Hashable, Sendable {
    let resetsAt: Date
    let observedAt: Date
    let totalTokens: Int64
    let sessionCount: Int
    let sessionTotals: [String: Int64]
    let cycleSessionIDs: Set<String>

    init(
        resetsAt: Date,
        observedAt: Date,
        totalTokens: Int64,
        sessionCount: Int,
        sessionTotals: [String: Int64] = [:],
        cycleSessionIDs: Set<String> = []
    ) {
        self.resetsAt = resetsAt
        self.observedAt = observedAt
        self.totalTokens = totalTokens
        self.sessionCount = sessionCount
        self.sessionTotals = sessionTotals
        self.cycleSessionIDs = cycleSessionIDs
    }
}

struct QuotaValueEstimate: Hashable, Sendable {
    let weeklyTokens: Int64
    let monthlyTokens: Int64
    let remainingWeeklyTokens: Int64
    let weeklyAPIEquivalentUSD: Decimal?
    let monthlyAPIEquivalentUSD: Decimal?
    let remainingAPIEquivalentUSD: Decimal?
    let pricedSampleTokens: Int64
    let localTokenCoverage: Double
    let pricedModelCount: Int
}
