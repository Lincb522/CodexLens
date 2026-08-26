import Foundation

struct BillingCalculator: Sendable {
    static func cost(
        for usage: TokenUsage,
        model: String,
        applyLongContextMultiplier: Bool = true
    ) -> CostBreakdown {
        guard usage.hasCompleteBreakdown,
              let rate = PricingCatalog.rate(for: model) else {
            return .unpriced
        }

        let million = Decimal(1_000_000)
        let longContext = applyLongContextMultiplier
            && (rate.longContextThreshold.map { usage.inputTokens > $0 } ?? false)
        let inputMultiplier = longContext ? rate.longContextInputMultiplier : 1
        let outputMultiplier = longContext ? rate.longContextOutputMultiplier : 1

        let input = Decimal(usage.uncachedInputTokens) / million
            * rate.inputPerMillion * inputMultiplier
        let cached = Decimal(usage.cachedInputTokens) / million
            * rate.cachedInputPerMillion * inputMultiplier
        let cacheWrite = Decimal(usage.cacheWriteInputTokens) / million
            * rate.cacheWritePerMillion * inputMultiplier
        let output = Decimal(usage.outputTokens) / million
            * rate.outputPerMillion * outputMultiplier

        return CostBreakdown(
            input: input,
            cachedInput: cached,
            cacheWrite: cacheWrite,
            output: output,
            total: input + cached + cacheWrite + output,
            isLongContext: longContext,
            isPriced: true
        )
    }

    /// Returns unavailable instead of a deceptively precise partial total when
    /// any record lacks a complete token breakdown or an official API rate.
    static func total(records: [UsageRecord]) -> CostBreakdown {
        guard !records.isEmpty else { return .unpriced }
        var input: Decimal = 0
        var cachedInput: Decimal = 0
        var cacheWrite: Decimal = 0
        var output: Decimal = 0
        var total: Decimal = 0
        var isLongContext = false

        for record in records {
            let value = cost(
                for: record.usage,
                model: record.model,
                applyLongContextMultiplier: !record.isCumulativeSessionSummary
            )
            guard value.isPriced else { return .unpriced }
            input += value.input
            cachedInput += value.cachedInput
            cacheWrite += value.cacheWrite
            output += value.output
            total += value.total
            isLongContext = isLongContext || value.isLongContext
        }
        return CostBreakdown(
            input: input,
            cachedInput: cachedInput,
            cacheWrite: cacheWrite,
            output: output,
            total: total,
            isLongContext: isLongContext,
            isPriced: true
        )
    }

    /// Prices a Codex turn one model call at a time. This preserves request
    /// boundaries for long-context multipliers and model changes during a turn.
    static func cost(calls: [CodexModelCallUsage]) -> CostBreakdown {
        guard !calls.isEmpty else { return .unpriced }
        var input: Decimal = 0
        var cachedInput: Decimal = 0
        var cacheWrite: Decimal = 0
        var output: Decimal = 0
        var total: Decimal = 0
        var isLongContext = false

        for call in calls {
            let value = cost(
                for: call.usage,
                model: call.model,
                applyLongContextMultiplier: true
            )
            // Never return a deceptively precise partial estimate.
            guard value.isPriced else { return .unpriced }
            input += value.input
            cachedInput += value.cachedInput
            cacheWrite += value.cacheWrite
            output += value.output
            total += value.total
            isLongContext = isLongContext || value.isLongContext
        }
        return CostBreakdown(
            input: input,
            cachedInput: cachedInput,
            cacheWrite: cacheWrite,
            output: output,
            total: total,
            isLongContext: isLongContext,
            isPriced: true
        )
    }

}
