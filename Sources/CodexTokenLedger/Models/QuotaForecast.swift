import Foundation

struct QuotaUsageSample: Codable, Hashable, Identifiable, Sendable {
    let accountID: String
    let windowID: String
    let observedAt: Date
    let usedPercent: Double
    let resetsAt: Date?
    let windowMinutes: Int?

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
