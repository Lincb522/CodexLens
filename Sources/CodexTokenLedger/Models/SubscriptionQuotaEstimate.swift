import Foundation

struct SubscriptionQuotaEstimate: Hashable, Sendable {
    enum Tier: String, Hashable, Sendable {
        case plus
        case pro5x
        case pro20x
    }

    static let sourceURL = URL(
        string: "https://www.reddit.com/r/codex/comments/1v6ubah/realworld_codex_pro_20x_plan_test_with_gpt56_sol/"
    )
    static let averageWeeksPerMonth = 365.2425 / 12 / 7

    let tier: Tier
    let weeklyAPIEquivalentUSD: Double
    let weeklyAPILowerBoundUSD: Double
    let weeklyAPIUpperBoundUSD: Double

    var weeklyCredits: Double { weeklyAPIEquivalentUSD * 25 }
    var monthlyAPIEquivalentUSD: Double { weeklyAPIEquivalentUSD * Self.averageWeeksPerMonth }

    func remainingAPIEquivalentUSD(remainingPercent: Double) -> Double {
        weeklyAPIEquivalentUSD * min(100, max(0, remainingPercent)) / 100
    }

    static func forPlan(_ plan: String?) -> SubscriptionQuotaEstimate? {
        let normalized = plan?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""

        if normalized == "pro" || normalized.contains("20x") {
            return SubscriptionQuotaEstimate(
                tier: .pro20x,
                weeklyAPIEquivalentUSD: 2_144,
                weeklyAPILowerBoundUSD: 2_080,
                weeklyAPIUpperBoundUSD: 2_240
            )
        }
        if normalized == "prolite" || normalized.contains("5x") {
            return SubscriptionQuotaEstimate(
                tier: .pro5x,
                weeklyAPIEquivalentUSD: 537.5,
                weeklyAPILowerBoundUSD: 525,
                weeklyAPIUpperBoundUSD: 550
            )
        }
        if normalized == "plus" {
            return SubscriptionQuotaEstimate(
                tier: .plus,
                weeklyAPIEquivalentUSD: 105,
                weeklyAPILowerBoundUSD: 94,
                weeklyAPIUpperBoundUSD: 113
            )
        }
        return nil
    }
}
