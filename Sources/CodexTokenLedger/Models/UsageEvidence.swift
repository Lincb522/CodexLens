import Foundation

/// Describes where a number came from. Exact counters and estimates are never
/// presented as the same class of data.
enum UsageEvidence: String, Codable, Hashable, Sendable {
    case codexEventExact
    case codexServerOfficial
    case derivedFromExactCounters
    case officialRateEstimate
    case unavailable
}

extension UsageRecord {
    /// Both detailed and cumulative records originate in Codex `token_count`
    /// events. The cumulative fast path changes granularity, not accuracy.
    var evidence: UsageEvidence {
        isCumulativeSessionSummary ? .codexEventExact : .codexEventExact
    }
}

extension UsageSnapshot {
    var evidence: UsageEvidence {
        records.isEmpty ? .unavailable : .derivedFromExactCounters
    }

    var exactConversationTotal: TokenUsage {
        totalUsage
    }
}
