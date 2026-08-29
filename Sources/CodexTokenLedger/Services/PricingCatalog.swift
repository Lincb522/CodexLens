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
        api("gpt-5.6-sol", "GPT-5.6 Sol", 4, 0.4, 20, hasLongContextTier: true),
        api("gpt-5.6-terra", "GPT-5.6 Terra", 2, 0.2, 12, hasLongContextTier: true),
        api("gpt-5.6-luna", "GPT-5.6 Luna", 0.2, 0.02, 1.2, hasLongContextTier: true),
        api("gpt-5.5", "GPT-5.5", 5, 0.5, 30),
        api("daybreak-blue", "Daybreak Blue", 4, 0.4, 20),
        api("daybreak-red", "Daybreak Red", 12.5, 1.25, 75),
        api("gpt-5.4", "GPT-5.4", 2.5, 0.25, 15),
        api("gpt-5.4-mini", "GPT-5.4 Mini", 0.75, 0.075, 4.5),
        api("gpt-5.3-codex", "GPT-5.3 Codex", 1.75, 0.175, 14),
        api("gpt-5.2", "GPT-5.2", 1.75, 0.175, 14)
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
        if model.contains("5.3-codex") { return "gpt-5.3-codex" }
        if model.contains("5.2") { return "gpt-5.2" }
        return model
    }

    private static func api(
        _ key: String,
        _ name: String,
        _ input: Decimal,
        _ cached: Decimal,
        _ output: Decimal,
        hasLongContextTier: Bool = false
    ) -> TokenRate {
        TokenRate(
            modelKey: key,
            displayName: name,
            inputPerMillion: input,
            cachedInputPerMillion: cached,
            cacheWritePerMillion: input * Decimal(string: "1.25")!,
            outputPerMillion: output,
            longContextThreshold: hasLongContextTier ? 272_000 : nil,
            longContextInputMultiplier: 2,
            longContextOutputMultiplier: Decimal(string: "1.5")!,
            sourceNote: "OpenAI API and ChatGPT rate cards, verified 2026-08-29"
        )
    }
}
