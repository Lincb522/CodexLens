import Foundation

struct TokenRate: Codable, Hashable, Sendable {
    let modelKey: String
    let displayName: String
    let inputPerMillion: Decimal
    let cachedInputPerMillion: Decimal
    let cacheWritePerMillion: Decimal
    let outputPerMillion: Decimal
    let longContextThreshold: Int64?
    let longContextInputMultiplier: Decimal
    let longContextOutputMultiplier: Decimal
    let sourceNote: String
}

struct CostBreakdown: Hashable, Sendable {
    let input: Decimal
    let cachedInput: Decimal
    let cacheWrite: Decimal
    let output: Decimal
    let total: Decimal
    let isLongContext: Bool
    let isPriced: Bool

    static let unpriced = CostBreakdown(
        input: 0,
        cachedInput: 0,
        cacheWrite: 0,
        output: 0,
        total: 0,
        isLongContext: false,
        isPriced: false
    )
}
