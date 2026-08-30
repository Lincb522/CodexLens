import Foundation

enum TokenAccountingQuality: String, Codable, Hashable, Sendable {
    case complete
    case inconsistent
    case unclassified
}

struct TokenInputBreakdown: Codable, Hashable, Sendable {
    let totalTokens: Int64
    let uncachedTokens: Int64
    let cacheReadTokens: Int64
    let cacheWriteTokens: Int64

    private enum CodingKeys: String, CodingKey {
        case totalTokens = "total_tokens"
        case uncachedTokens = "uncached_tokens"
        case cacheReadTokens = "cache_read_tokens"
        case cacheWriteTokens = "cache_write_tokens"
    }
}

struct TokenOutputBreakdown: Codable, Hashable, Sendable {
    let totalTokens: Int64
    let nonReasoningTokens: Int64
    let reasoningTokens: Int64

    private enum CodingKeys: String, CodingKey {
        case totalTokens = "total_tokens"
        case nonReasoningTokens = "non_reasoning_tokens"
        case reasoningTokens = "reasoning_tokens"
    }
}

struct TokenBreakdown: Codable, Hashable, Sendable {
    static let schemaVersion = 2

    let schemaVersion: Int
    let quality: TokenAccountingQuality
    let totalTokens: Int64
    let input: TokenInputBreakdown
    let output: TokenOutputBreakdown
    let unclassifiedTokens: Int64

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case quality
        case totalTokens = "total_tokens"
        case input
        case output
        case unclassifiedTokens = "unclassified_tokens"
    }

    var isValid: Bool {
        guard schemaVersion == Self.schemaVersion,
              totalTokens >= 0,
              unclassifiedTokens >= 0,
              input.totalTokens >= 0,
              input.uncachedTokens >= 0,
              input.cacheReadTokens >= 0,
              input.cacheWriteTokens >= 0,
              output.totalTokens >= 0,
              output.nonReasoningTokens >= 0,
              output.reasoningTokens >= 0,
              let inputTotal = Self.nonNegativeSum(
                input.uncachedTokens,
                input.cacheReadTokens,
                input.cacheWriteTokens
              ),
              inputTotal == input.totalTokens,
              let outputTotal = Self.nonNegativeSum(
                output.nonReasoningTokens,
                output.reasoningTokens
              ),
              outputTotal == output.totalTokens,
              let classifiedTotal = Self.nonNegativeSum(
                input.totalTokens,
                output.totalTokens,
                unclassifiedTokens
              ),
              classifiedTotal == totalTokens
        else { return false }

        return quality != .complete || unclassifiedTokens == 0
    }

    static func subset(
        inputTotal: Int64,
        cacheRead: Int64,
        cacheWrite: Int64,
        outputTotal: Int64,
        reasoning: Int64,
        total: Int64
    ) -> TokenBreakdown {
        guard let cacheTotal = nonNegativeSum(cacheRead, cacheWrite),
              let expectedTotal = nonNegativeSum(inputTotal, outputTotal),
              cacheTotal <= inputTotal,
              reasoning >= 0,
              reasoning <= outputTotal,
              let resolvedTotal = resolvedTotal(total, expected: expectedTotal)
        else {
            return inconsistent(total: total, fallback: nonNegativeSum(inputTotal, outputTotal) ?? 0)
        }

        return complete(
            inputTotal: inputTotal,
            uncached: inputTotal - cacheTotal,
            cacheRead: cacheRead,
            cacheWrite: cacheWrite,
            outputTotal: outputTotal,
            nonReasoning: outputTotal - reasoning,
            reasoning: reasoning,
            total: resolvedTotal
        )
    }

    static func partialSubset(
        inputTotal: Int64,
        cacheRead: Int64,
        cacheWrite: Int64,
        outputTotal: Int64,
        reasoning: Int64,
        total: Int64
    ) -> TokenBreakdown {
        guard let cacheTotal = nonNegativeSum(cacheRead, cacheWrite),
              let expectedTotal = nonNegativeSum(inputTotal, outputTotal),
              cacheTotal <= inputTotal,
              reasoning >= 0,
              reasoning <= outputTotal,
              total >= 0
        else {
            return inconsistent(total: total, fallback: nonNegativeSum(inputTotal, outputTotal) ?? 0)
        }

        let resolvedTotal = total == 0 ? expectedTotal : total
        guard resolvedTotal >= expectedTotal else {
            return inconsistent(total: total, fallback: expectedTotal)
        }
        let unclassified = resolvedTotal - expectedTotal
        return TokenBreakdown(
            schemaVersion: schemaVersion,
            quality: unclassified == 0 ? .complete : .unclassified,
            totalTokens: resolvedTotal,
            input: TokenInputBreakdown(
                totalTokens: inputTotal,
                uncachedTokens: inputTotal - cacheTotal,
                cacheReadTokens: cacheRead,
                cacheWriteTokens: cacheWrite
            ),
            output: TokenOutputBreakdown(
                totalTokens: outputTotal,
                nonReasoningTokens: outputTotal - reasoning,
                reasoningTokens: reasoning
            ),
            unclassifiedTokens: unclassified
        )
    }

    static func independent(
        uncachedInput: Int64,
        cacheRead: Int64,
        cacheWrite: Int64,
        nonReasoningOutput: Int64,
        reasoning: Int64,
        total: Int64
    ) -> TokenBreakdown {
        guard let inputTotal = nonNegativeSum(uncachedInput, cacheRead, cacheWrite),
              let outputTotal = nonNegativeSum(nonReasoningOutput, reasoning),
              let expectedTotal = nonNegativeSum(inputTotal, outputTotal),
              let resolvedTotal = resolvedTotal(total, expected: expectedTotal)
        else {
            return inconsistent(total: total, fallback: 0)
        }

        return complete(
            inputTotal: inputTotal,
            uncached: uncachedInput,
            cacheRead: cacheRead,
            cacheWrite: cacheWrite,
            outputTotal: outputTotal,
            nonReasoning: nonReasoningOutput,
            reasoning: reasoning,
            total: resolvedTotal
        )
    }

    static func separateReasoning(
        inputTotal: Int64,
        cacheRead: Int64,
        cacheWrite: Int64,
        nonReasoningOutput: Int64,
        reasoning: Int64,
        total: Int64
    ) -> TokenBreakdown {
        guard let cacheTotal = nonNegativeSum(cacheRead, cacheWrite),
              cacheTotal <= inputTotal,
              let outputTotal = nonNegativeSum(nonReasoningOutput, reasoning),
              let expectedTotal = nonNegativeSum(inputTotal, outputTotal),
              let resolvedTotal = resolvedTotal(total, expected: expectedTotal)
        else {
            return inconsistent(total: total, fallback: 0)
        }

        return complete(
            inputTotal: inputTotal,
            uncached: inputTotal - cacheTotal,
            cacheRead: cacheRead,
            cacheWrite: cacheWrite,
            outputTotal: outputTotal,
            nonReasoning: nonReasoningOutput,
            reasoning: reasoning,
            total: resolvedTotal
        )
    }

    static func unclassified(total: Int64) -> TokenBreakdown {
        guard total > 0 else {
            return TokenBreakdown(
                schemaVersion: schemaVersion,
                quality: total < 0 ? .inconsistent : .complete,
                totalTokens: 0,
                input: .zero,
                output: .zero,
                unclassifiedTokens: 0
            )
        }
        return TokenBreakdown(
            schemaVersion: schemaVersion,
            quality: .unclassified,
            totalTokens: total,
            input: .zero,
            output: .zero,
            unclassifiedTokens: total
        )
    }

    func adding(_ other: TokenBreakdown) -> TokenBreakdown {
        guard isValid, other.isValid,
              let uncached = Self.nonNegativeSum(input.uncachedTokens, other.input.uncachedTokens),
              let cacheRead = Self.nonNegativeSum(input.cacheReadTokens, other.input.cacheReadTokens),
              let cacheWrite = Self.nonNegativeSum(input.cacheWriteTokens, other.input.cacheWriteTokens),
              let nonReasoning = Self.nonNegativeSum(output.nonReasoningTokens, other.output.nonReasoningTokens),
              let reasoning = Self.nonNegativeSum(output.reasoningTokens, other.output.reasoningTokens),
              let unclassified = Self.nonNegativeSum(unclassifiedTokens, other.unclassifiedTokens),
              let inputTotal = Self.nonNegativeSum(uncached, cacheRead, cacheWrite),
              let outputTotal = Self.nonNegativeSum(nonReasoning, reasoning),
              let total = Self.nonNegativeSum(inputTotal, outputTotal, unclassified)
        else {
            return Self.inconsistent(
                total: Self.nonNegativeSum(totalTokens, other.totalTokens) ?? 0,
                fallback: 0
            )
        }

        let quality: TokenAccountingQuality
        if self.quality == .inconsistent || other.quality == .inconsistent {
            quality = .inconsistent
        } else if unclassified > 0 {
            quality = .unclassified
        } else {
            quality = .complete
        }
        return TokenBreakdown(
            schemaVersion: Self.schemaVersion,
            quality: quality,
            totalTokens: total,
            input: TokenInputBreakdown(
                totalTokens: inputTotal,
                uncachedTokens: uncached,
                cacheReadTokens: cacheRead,
                cacheWriteTokens: cacheWrite
            ),
            output: TokenOutputBreakdown(
                totalTokens: outputTotal,
                nonReasoningTokens: nonReasoning,
                reasoningTokens: reasoning
            ),
            unclassifiedTokens: unclassified
        )
    }

    func subtracting(_ previous: TokenBreakdown) -> TokenBreakdown? {
        guard isValid,
              previous.isValid,
              quality != .inconsistent,
              previous.quality != .inconsistent,
              input.uncachedTokens >= previous.input.uncachedTokens,
              input.cacheReadTokens >= previous.input.cacheReadTokens,
              input.cacheWriteTokens >= previous.input.cacheWriteTokens,
              output.nonReasoningTokens >= previous.output.nonReasoningTokens,
              output.reasoningTokens >= previous.output.reasoningTokens,
              unclassifiedTokens >= previous.unclassifiedTokens
        else { return nil }

        let delta = TokenBreakdown(
            schemaVersion: Self.schemaVersion,
            quality: unclassifiedTokens == previous.unclassifiedTokens ? .complete : .unclassified,
            totalTokens: totalTokens - previous.totalTokens,
            input: TokenInputBreakdown(
                totalTokens: input.totalTokens - previous.input.totalTokens,
                uncachedTokens: input.uncachedTokens - previous.input.uncachedTokens,
                cacheReadTokens: input.cacheReadTokens - previous.input.cacheReadTokens,
                cacheWriteTokens: input.cacheWriteTokens - previous.input.cacheWriteTokens
            ),
            output: TokenOutputBreakdown(
                totalTokens: output.totalTokens - previous.output.totalTokens,
                nonReasoningTokens: output.nonReasoningTokens - previous.output.nonReasoningTokens,
                reasoningTokens: output.reasoningTokens - previous.output.reasoningTokens
            ),
            unclassifiedTokens: unclassifiedTokens - previous.unclassifiedTokens
        )
        return delta.isValid ? delta : nil
    }

    private static func complete(
        inputTotal: Int64,
        uncached: Int64,
        cacheRead: Int64,
        cacheWrite: Int64,
        outputTotal: Int64,
        nonReasoning: Int64,
        reasoning: Int64,
        total: Int64
    ) -> TokenBreakdown {
        TokenBreakdown(
            schemaVersion: schemaVersion,
            quality: .complete,
            totalTokens: total,
            input: TokenInputBreakdown(
                totalTokens: inputTotal,
                uncachedTokens: uncached,
                cacheReadTokens: cacheRead,
                cacheWriteTokens: cacheWrite
            ),
            output: TokenOutputBreakdown(
                totalTokens: outputTotal,
                nonReasoningTokens: nonReasoning,
                reasoningTokens: reasoning
            ),
            unclassifiedTokens: 0
        )
    }

    static func inconsistent(total: Int64, fallback: Int64) -> TokenBreakdown {
        let resolved = total > 0 ? total : max(0, fallback)
        return TokenBreakdown(
            schemaVersion: schemaVersion,
            quality: .inconsistent,
            totalTokens: resolved,
            input: .zero,
            output: .zero,
            unclassifiedTokens: resolved
        )
    }

    private static func resolvedTotal(_ total: Int64, expected: Int64) -> Int64? {
        guard total >= 0, expected >= 0 else { return nil }
        if total == 0 { return expected }
        return total == expected ? total : nil
    }

    private static func nonNegativeSum(_ values: Int64...) -> Int64? {
        var result: Int64 = 0
        for value in values {
            guard value >= 0, result <= Int64.max - value else { return nil }
            result += value
        }
        return result
    }
}

private extension TokenInputBreakdown {
    static let zero = TokenInputBreakdown(
        totalTokens: 0,
        uncachedTokens: 0,
        cacheReadTokens: 0,
        cacheWriteTokens: 0
    )
}

private extension TokenOutputBreakdown {
    static let zero = TokenOutputBreakdown(
        totalTokens: 0,
        nonReasoningTokens: 0,
        reasoningTokens: 0
    )
}
