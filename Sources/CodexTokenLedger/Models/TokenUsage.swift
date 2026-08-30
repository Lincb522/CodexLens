import Foundation

struct TokenUsage: Codable, Hashable, Sendable {
    private let tokenBreakdown: TokenBreakdown

    var inputTokens: Int64 { tokenBreakdown.input.totalTokens }
    var cachedInputTokens: Int64 { tokenBreakdown.input.cacheReadTokens }
    var cacheWriteInputTokens: Int64 { tokenBreakdown.input.cacheWriteTokens }
    var outputTokens: Int64 { tokenBreakdown.output.totalTokens }
    var reasoningOutputTokens: Int64 { tokenBreakdown.output.reasoningTokens }
    var nonReasoningOutputTokens: Int64 { tokenBreakdown.output.nonReasoningTokens }
    var accountingQuality: TokenAccountingQuality { tokenBreakdown.quality }
    var accountingSchemaVersion: Int { tokenBreakdown.schemaVersion }
    var unclassifiedTokens: Int64 { tokenBreakdown.unclassifiedTokens }

    var reportedTotalTokens: Int64? {
        tokenBreakdown.quality == .complete ? nil : tokenBreakdown.totalTokens
    }

    var uncachedInputTokens: Int64 {
        tokenBreakdown.input.uncachedTokens
    }

    var totalTokens: Int64 {
        tokenBreakdown.totalTokens
    }

    var hasCompleteBreakdown: Bool {
        tokenBreakdown.quality == .complete
    }

    var isValidCodexCounter: Bool {
        tokenBreakdown.isValid
    }

    init(
        inputTokens: Int64 = 0,
        cachedInputTokens: Int64 = 0,
        cacheWriteInputTokens: Int64 = 0,
        outputTokens: Int64 = 0,
        reasoningOutputTokens: Int64 = 0,
        reportedTotalTokens: Int64? = nil
    ) {
        tokenBreakdown = .partialSubset(
            inputTotal: inputTokens,
            cacheRead: cachedInputTokens,
            cacheWrite: cacheWriteInputTokens,
            outputTotal: outputTokens,
            reasoning: reasoningOutputTokens,
            total: reportedTotalTokens ?? 0
        )
    }

    init(tokenBreakdown: TokenBreakdown) {
        self.tokenBreakdown = tokenBreakdown.isValid
            ? tokenBreakdown
            : .inconsistent(total: tokenBreakdown.totalTokens, fallback: 0)
    }

    static func codexEvent(
        inputTokens: Int64?,
        cachedInputTokens: Int64?,
        cacheWriteInputTokens: Int64?,
        outputTokens: Int64?,
        reasoningOutputTokens: Int64?,
        reportedTotalTokens: Int64?
    ) -> TokenUsage? {
        let hasAnyValue = inputTokens != nil
            || cachedInputTokens != nil
            || cacheWriteInputTokens != nil
            || outputTokens != nil
            || reasoningOutputTokens != nil
            || reportedTotalTokens != nil
        guard hasAnyValue else { return nil }

        let input = inputTokens ?? 0
        let cacheRead = cachedInputTokens ?? 0
        let cacheWrite = cacheWriteInputTokens ?? 0
        let output = outputTokens ?? 0
        let reasoning = reasoningOutputTokens ?? 0
        let total = reportedTotalTokens ?? 0

        if inputTokens == nil && outputTokens == nil {
            let cacheLowerBound = TokenUsage.safeSum(cacheRead, cacheWrite) ?? 0
            let lowerBound = TokenUsage.safeSum(max(cacheLowerBound, input), max(reasoning, output)) ?? 0
            return TokenUsage(tokenBreakdown: .unclassified(total: total == 0 ? lowerBound : total))
        }

        if input == 0, output == 0, total > 0 {
            return TokenUsage(tokenBreakdown: .unclassified(total: total))
        }

        let accounting: TokenBreakdown
        if inputTokens != nil, outputTokens != nil {
            accounting = .subset(
                inputTotal: input,
                cacheRead: cacheRead,
                cacheWrite: cacheWrite,
                outputTotal: output,
                reasoning: reasoning,
                total: total
            )
        } else {
            accounting = .partialSubset(
                inputTotal: input,
                cacheRead: cacheRead,
                cacheWrite: cacheWrite,
                outputTotal: output,
                reasoning: reasoning,
                total: total
            )
        }
        return TokenUsage(tokenBreakdown: accounting)
    }

    static func + (lhs: TokenUsage, rhs: TokenUsage) -> TokenUsage {
        TokenUsage(tokenBreakdown: lhs.tokenBreakdown.adding(rhs.tokenBreakdown))
    }

    static func += (lhs: inout TokenUsage, rhs: TokenUsage) {
        lhs = lhs + rhs
    }

    func subtracting(_ previous: TokenUsage) -> TokenUsage? {
        if let exact = tokenBreakdown.subtracting(previous.tokenBreakdown) {
            return TokenUsage(tokenBreakdown: exact)
        }
        guard (accountingQuality == .inconsistent || previous.accountingQuality == .inconsistent),
              totalTokens >= previous.totalTokens
        else { return nil }
        return TokenUsage(
            tokenBreakdown: .unclassified(total: totalTokens - previous.totalTokens)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case inputTokens
        case cachedInputTokens
        case cacheWriteInputTokens
        case outputTokens
        case reasoningOutputTokens
        case reportedTotalTokens
        case tokenBreakdown = "token_breakdown"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let decoded = try container.decodeIfPresent(TokenBreakdown.self, forKey: .tokenBreakdown),
           decoded.isValid {
            self.init(tokenBreakdown: decoded)
            return
        }
        self.init(
            inputTokens: try container.decodeIfPresent(Int64.self, forKey: .inputTokens) ?? 0,
            cachedInputTokens: try container.decodeIfPresent(Int64.self, forKey: .cachedInputTokens) ?? 0,
            cacheWriteInputTokens: try container.decodeIfPresent(Int64.self, forKey: .cacheWriteInputTokens) ?? 0,
            outputTokens: try container.decodeIfPresent(Int64.self, forKey: .outputTokens) ?? 0,
            reasoningOutputTokens: try container.decodeIfPresent(Int64.self, forKey: .reasoningOutputTokens) ?? 0,
            reportedTotalTokens: try container.decodeIfPresent(Int64.self, forKey: .reportedTotalTokens)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(inputTokens, forKey: .inputTokens)
        try container.encode(cachedInputTokens, forKey: .cachedInputTokens)
        try container.encode(cacheWriteInputTokens, forKey: .cacheWriteInputTokens)
        try container.encode(outputTokens, forKey: .outputTokens)
        try container.encode(reasoningOutputTokens, forKey: .reasoningOutputTokens)
        try container.encodeIfPresent(reportedTotalTokens, forKey: .reportedTotalTokens)
        try container.encode(tokenBreakdown, forKey: .tokenBreakdown)
    }

    private static func safeSum(_ values: Int64...) -> Int64? {
        var total: Int64 = 0
        for value in values {
            guard value >= 0, total <= Int64.max - value else { return nil }
            total += value
        }
        return total
    }
}

struct UsageRecord: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let timestamp: Date
    let sessionID: String
    let sourcePath: String
    let projectPath: String?
    let model: String
    let reasoningEffort: String?
    let usage: TokenUsage

    /// Fast modern scans store Codex's exact cumulative session counters as one
    /// record. The record is exact for Token totals, but it does not retain
    /// per-request boundaries needed to infer long-context API surcharges.
    var isCumulativeSessionSummary: Bool { id.hasSuffix("|cumulative") }

    var projectName: String {
        guard let projectPath, !projectPath.isEmpty else { return "Codex" }
        return URL(fileURLWithPath: projectPath).lastPathComponent
    }
}

struct SessionSummary: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let startedAt: Date
    let lastActivityAt: Date
    let projectPath: String?
    let latestModel: String
    let eventCount: Int
    let usage: TokenUsage

    var projectName: String {
        guard let projectPath, !projectPath.isEmpty else { return "Codex" }
        return URL(fileURLWithPath: projectPath).lastPathComponent
    }
}

struct ScanIssue: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let file: String
    let line: Int
    let message: String
}

struct UsageSnapshot: Codable, Sendable {
    let scannedAt: Date
    let codexHome: String
    let fileCount: Int
    let records: [UsageRecord]
    let sessions: [SessionSummary]
    let issues: [ScanIssue]

    static let empty = UsageSnapshot(
        scannedAt: .distantPast,
        codexHome: "",
        fileCount: 0,
        records: [],
        sessions: [],
        issues: []
    )

    var totalUsage: TokenUsage {
        records.reduce(into: TokenUsage()) { $0 += $1.usage }
    }
}

struct DailyUsage: Identifiable, Hashable, Sendable {
    var id: Date { date }
    let date: Date
    let usage: TokenUsage
}

struct ModelUsage: Identifiable, Hashable, Sendable {
    var id: String { model }
    let model: String
    let usage: TokenUsage
    let eventCount: Int
}
