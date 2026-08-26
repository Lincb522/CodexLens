import Foundation

/// Token counters emitted by Codex. `outputTokens` already includes reasoning
/// output, so reasoning is displayed separately but never charged twice.
struct TokenUsage: Codable, Hashable, Sendable {
    var inputTokens: Int64 = 0
    var cachedInputTokens: Int64 = 0
    var cacheWriteInputTokens: Int64 = 0
    var outputTokens: Int64 = 0
    var reasoningOutputTokens: Int64 = 0
    /// Some older or remote Codex events expose only an authoritative total.
    /// Keep it instead of fabricating an input/output split.
    var reportedTotalTokens: Int64? = nil

    var uncachedInputTokens: Int64 {
        max(0, inputTokens - cachedInputTokens - cacheWriteInputTokens)
    }

    /// Matches Codex's recorded total: input + output.
    var totalTokens: Int64 {
        reportedTotalTokens ?? (inputTokens + outputTokens)
    }

    var hasCompleteBreakdown: Bool {
        reportedTotalTokens == nil || reportedTotalTokens == inputTokens + outputTokens
    }

    /// Structural invariants of Codex accounting events. Invalid counters are
    /// rejected at ingestion instead of being silently clamped into a value
    /// that looks precise.
    var isValidCodexCounter: Bool {
        inputTokens >= 0
            && cachedInputTokens >= 0
            && cacheWriteInputTokens >= 0
            && outputTokens >= 0
            && reasoningOutputTokens >= 0
            && cachedInputTokens + cacheWriteInputTokens <= inputTokens
            && reasoningOutputTokens <= outputTokens
            && (reportedTotalTokens.map { $0 >= inputTokens + outputTokens } ?? true)
    }

    static func + (lhs: TokenUsage, rhs: TokenUsage) -> TokenUsage {
        let needsAuthoritativeTotal = !lhs.hasCompleteBreakdown || !rhs.hasCompleteBreakdown
        return TokenUsage(
            inputTokens: lhs.inputTokens + rhs.inputTokens,
            cachedInputTokens: lhs.cachedInputTokens + rhs.cachedInputTokens,
            cacheWriteInputTokens: lhs.cacheWriteInputTokens + rhs.cacheWriteInputTokens,
            outputTokens: lhs.outputTokens + rhs.outputTokens,
            reasoningOutputTokens: lhs.reasoningOutputTokens + rhs.reasoningOutputTokens,
            reportedTotalTokens: needsAuthoritativeTotal ? lhs.totalTokens + rhs.totalTokens : nil
        )
    }

    static func += (lhs: inout TokenUsage, rhs: TokenUsage) {
        lhs = lhs + rhs
    }

    /// Returns the non-negative cumulative delta. Codex emits a cumulative
    /// counter alongside each model-call counter; deriving the call from two
    /// cumulative samples makes repeated token_count events harmless.
    func subtracting(_ previous: TokenUsage) -> TokenUsage? {
        let delta = TokenUsage(
            inputTokens: inputTokens - previous.inputTokens,
            cachedInputTokens: cachedInputTokens - previous.cachedInputTokens,
            cacheWriteInputTokens: cacheWriteInputTokens - previous.cacheWriteInputTokens,
            outputTokens: outputTokens - previous.outputTokens,
            reasoningOutputTokens: reasoningOutputTokens - previous.reasoningOutputTokens,
            reportedTotalTokens: (!hasCompleteBreakdown || !previous.hasCompleteBreakdown)
                ? totalTokens - previous.totalTokens
                : nil
        )
        guard delta.isValidCodexCounter else { return nil }
        return delta
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
