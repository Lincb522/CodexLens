import Foundation

struct PricingCatalog: Sendable {
    /// Published model capacity. Codex can also emit a smaller runtime window
    /// for a particular turn; the UI keeps both values instead of conflating
    /// the public model limit with the active runtime budget.
    static func publishedContextWindow(for rawModel: String) -> Int64? {
        switch normalize(model: rawModel) {
        case "gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna", "gpt-5.5", "gpt-5.4":
            return 1_050_000
        default:
            return nil
        }
    }

    /// Published API standard-processing rates, USD per 1M text tokens.
    /// GPT-5.6 API cache writes are 1.25× uncached input. Requests over 272K
    /// input tokens use 2× input-side and 1.5× output-side pricing for the
    /// entire request. The threshold is deliberately request-scoped.
    static let apiRates: [TokenRate] = [
        api("gpt-5.6-sol", "GPT-5.6 Sol", 4, 0.4, 20),
        api("gpt-5.6-terra", "GPT-5.6 Terra", 2, 0.2, 12),
        api("gpt-5.6-luna", "GPT-5.6 Luna", 0.2, 0.02, 1.2)
    ]

    static func rate(for rawModel: String) -> TokenRate? {
        let normalized = normalize(model: rawModel)
        return apiRates.first { $0.modelKey == normalized }
    }

    static func normalize(model rawModel: String) -> String {
        let model = rawModel.lowercased()
        if model.contains("daybreak-red") { return "daybreak-red" }
        if model.contains("daybreak-blue") { return "daybreak-blue" }
        if model.contains("5.6-luna") { return "gpt-5.6-luna" }
        if model.contains("5.6-terra") { return "gpt-5.6-terra" }
        if model == "gpt-5.6" || model.contains("5.6-sol") { return "gpt-5.6-sol" }
        if model.contains("5.5") { return "gpt-5.5" }
        if model.contains("5.4-mini") { return "gpt-5.4-mini" }
        if model.contains("5.4") { return "gpt-5.4" }
        return model
    }

    private static func api(
        _ key: String,
        _ name: String,
        _ input: Decimal,
        _ cached: Decimal,
        _ output: Decimal
    ) -> TokenRate {
        TokenRate(
            modelKey: key,
            displayName: name,
            inputPerMillion: input,
            cachedInputPerMillion: cached,
            cacheWritePerMillion: input * Decimal(string: "1.25")!,
            outputPerMillion: output,
            longContextThreshold: 272_000,
            longContextInputMultiplier: 2,
            longContextOutputMultiplier: Decimal(string: "1.5")!,
            sourceNote: "OpenAI API model pricing, verified 2026-08-24"
        )
    }
}
