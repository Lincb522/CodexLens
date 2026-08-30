import CoreFoundation
import Foundation

enum CodexTokenUsageParser {
    static func parse(_ dictionary: [String: Any]) -> TokenUsage? {
        if let rawBreakdown = dictionary["token_breakdown"] {
            guard let object = rawBreakdown as? [String: Any],
                  JSONSerialization.isValidJSONObject(object),
                  let data = try? JSONSerialization.data(withJSONObject: object),
                  let breakdown = try? JSONDecoder().decode(TokenBreakdown.self, from: data),
                  breakdown.isValid
            else { return nil }
            return TokenUsage(tokenBreakdown: breakdown)
        }

        let inputDetails = dictionary["input_tokens_details"] as? [String: Any] ?? [:]
        let outputDetails = dictionary["output_tokens_details"] as? [String: Any] ?? [:]

        let input = field([(dictionary, "input_tokens")])
        let output = field([(dictionary, "output_tokens")])
        let cacheRead = field([
            (dictionary, "cache_read_tokens"),
            (dictionary, "cached_input_tokens"),
            (inputDetails, "cached_tokens"),
            (dictionary, "cached_tokens"),
        ])
        let cacheWrite = field([
            (dictionary, "cache_creation_tokens"),
            (dictionary, "cache_write_input_tokens"),
            (inputDetails, "cache_write_tokens"),
        ])
        let reasoning = field([
            (dictionary, "reasoning_tokens"),
            (dictionary, "reasoning_output_tokens"),
            (outputDetails, "reasoning_tokens"),
        ])
        let total = field([(dictionary, "total_tokens")])

        let fields = [input, output, cacheRead, cacheWrite, reasoning, total]
        guard fields.allSatisfy({ !$0.isPresent || $0.value != nil }) else { return nil }

        return TokenUsage.codexEvent(
            inputTokens: input.value,
            cachedInputTokens: cacheRead.value,
            cacheWriteInputTokens: cacheWrite.value,
            outputTokens: output.value,
            reasoningOutputTokens: reasoning.value,
            reportedTotalTokens: total.value
        )
    }

    private struct Field {
        let isPresent: Bool
        let value: Int64?
    }

    private static func field(_ candidates: [([String: Any], String)]) -> Field {
        for (dictionary, key) in candidates where dictionary.keys.contains(key) {
            return Field(isPresent: true, value: integer(dictionary[key]))
        }
        return Field(isPresent: false, value: nil)
    }

    private static func integer(_ value: Any?) -> Int64? {
        if let number = value as? NSNumber {
            guard CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
            return Int64(number.stringValue)
        }
        if let text = value as? String {
            return Int64(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }
}
