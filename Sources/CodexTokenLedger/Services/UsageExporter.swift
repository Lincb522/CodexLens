import Foundation

enum UsageExporter {
    static func csv(records: [UsageRecord]) -> Data {
        var rows = [
            "timestamp,session_id,project,model,reasoning_effort,input_tokens,cached_input_tokens,uncached_input_tokens,cache_write_input_tokens,output_tokens,reasoning_output_tokens,total_tokens,api_equivalent_usd_estimate,api_pricing_evidence"
        ]

        let iso = ISO8601DateFormatter()
        for record in records {
            let apiEstimate = BillingCalculator.cost(
                for: record.usage,
                model: record.model,
                applyLongContextMultiplier: !record.isCumulativeSessionSummary
            )
            rows.append([
                escape(iso.string(from: record.timestamp)),
                escape(record.sessionID),
                escape(record.projectPath ?? ""),
                escape(record.model),
                escape(record.reasoningEffort ?? ""),
                String(record.usage.inputTokens),
                String(record.usage.cachedInputTokens),
                String(record.usage.uncachedInputTokens),
                String(record.usage.cacheWriteInputTokens),
                String(record.usage.outputTokens),
                String(record.usage.reasoningOutputTokens),
                String(record.usage.totalTokens),
                apiEstimate.isPriced ? NSDecimalNumber(decimal: apiEstimate.total).stringValue : "",
                apiEstimate.isPriced ? "official_api_rate_estimate" : "unavailable"
            ].joined(separator: ","))
        }
        return (rows.joined(separator: "\n") + "\n").data(using: .utf8) ?? Data()
    }

    static func json(snapshot: UsageSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(snapshot)
    }

    private static func escape(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}
