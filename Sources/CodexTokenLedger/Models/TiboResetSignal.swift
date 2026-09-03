import Foundation

enum TiboSignalStatus: String, Codable, Sendable {
    case candidate
    case forecast
    case expected
    case confirmed
}

enum TiboSignalSourceStatus: String, Codable, Sendable {
    case idle
    case healthy
    case degraded
    case offline
}

enum TiboForecastConfidence: String, Codable, Sendable {
    case low
    case medium
    case high
    case unknown
}

enum TiboResetReason: String, Codable, Sendable {
    case milestone25M
}

enum TiboSocialSignalKind: String, Codable, Sendable {
    case explicit
    case tease
    case context
}

struct TiboSocialEvidence: Codable, Equatable, Identifiable, Sendable {
    let postID: String
    let sourceURL: URL
    let postedAt: Date
    let text: String
    let isReply: Bool
    let replyingTo: String?
    let signalKind: TiboSocialSignalKind

    var id: String { postID }
}

struct TiboForecastCadence: Codable, Equatable, Sendable {
    let recentMedianDays: Double
    let recentSample: Int
    let weightedMeanDays: Double
}

struct TiboForecastTimeWindow: Codable, Equatable, Sendable {
    let startHour: Int
    let endHour: Int
    let label: String
    let timeZoneIdentifier: String
}

/// Structured fields returned by the public reset forecast endpoint. The app
/// displays these values directly and does not derive a probability from local
/// account usage or fabricate a confidence score.
struct TiboForecastSnapshot: Codable, Equatable, Sendable {
    let updatedAt: Date
    let probability24hPercent: Int
    let probability48hPercent: Int?
    let confidence: TiboForecastConfidence
    let lastResetAt: Date?
    let cadence: TiboForecastCadence?
    let commonTimeWindow: TiboForecastTimeWindow?
    let latestResetReason: TiboResetReason?

    var sevenDayReferenceAt: Date? {
        lastResetAt?.addingTimeInterval(7 * 86_400)
    }
}

struct TiboResetSignal: Codable, Equatable, Identifiable, Sendable {
    let postID: String
    let sourceURL: URL
    let postedAt: Date
    let status: TiboSignalStatus
    let resetKind: String
    let matchedRuleIDs: [String]
    let ruleVersion: String
    let contentHash: String
    var expectedStart: Date? = nil
    var expectedEnd: Date? = nil

    var id: String { postID }
}

struct TiboResetCycle: Equatable, Sendable {
    let lastConfirmedSignal: TiboResetSignal?
    let lastObservedResetAt: Date?
    let activeCandidate: TiboResetSignal?
    let activePrediction: TiboResetSignal?
    let chain: [TiboResetSignal]

    var activeSignal: TiboResetSignal? { activePrediction ?? activeCandidate }
    var displayedNextResetAt: Date? { activePrediction?.expectedStart }
    var displayedNextResetEnd: Date? { activePrediction?.expectedEnd }
    var usesSignalPrediction: Bool { activePrediction != nil }
}

struct TiboResetMonitorSnapshot: Codable, Equatable, Sendable {
    var sourceStatus: TiboSignalSourceStatus
    var checkedAt: Date?
    var lastSuccessAt: Date?
    var latestSignal: TiboResetSignal?
    var recentSignals: [TiboResetSignal]? = nil
    var lastErrorCode: String?
    var forecast: TiboForecastSnapshot? = nil
    var socialEvidence: [TiboSocialEvidence]? = nil

    var signals: [TiboResetSignal] {
        guard let recentSignals, !recentSignals.isEmpty else {
            return latestSignal.map { [$0] } ?? []
        }
        return recentSignals
    }

    func cycle(now: Date = Date()) -> TiboResetCycle {
        let primary = signals
            .filter { $0.resetKind != "banked" }
            .sorted { $0.postedAt > $1.postedAt }

        let lastConfirmed = primary
            .filter { $0.status == .confirmed && $0.postedAt <= now }
            .max { $0.postedAt < $1.postedAt }
        let confirmedAt = lastConfirmed?.postedAt

        let activePredictions = primary.filter { signal in
            guard signal.status == .expected || signal.status == .forecast else { return false }
            if let confirmedAt, signal.postedAt <= confirmedAt { return false }
            let boundary = signal.expectedEnd ?? signal.expectedStart
            if let boundary { return boundary > now }
            return signal.postedAt > now.addingTimeInterval(-7 * 86_400)
        }
        let activePrediction = activePredictions.max { lhs, rhs in
            if lhs.status != rhs.status {
                return lhs.status == .forecast && rhs.status == .expected
            }
            return lhs.postedAt < rhs.postedAt
        }
        let activeCandidate = primary
            .filter { signal in
                guard signal.status == .candidate else { return false }
                if let confirmedAt { return signal.postedAt > confirmedAt }
                return true
            }
            .max { $0.postedAt < $1.postedAt }

        let activeBoundary = activePrediction?.postedAt ?? activeCandidate?.postedAt
        let chain: [TiboResetSignal]
        if activeBoundary != nil {
            chain = primary
                .filter { signal in
                    if let confirmedAt { return signal.postedAt > confirmedAt }
                    return signal.postedAt >= now.addingTimeInterval(-7 * 86_400)
                }
                .sorted { $0.postedAt < $1.postedAt }
        } else if let lastConfirmed {
            let start = lastConfirmed.postedAt.addingTimeInterval(-7 * 86_400)
            chain = primary
                .filter { $0.postedAt >= start && $0.postedAt <= lastConfirmed.postedAt }
                .sorted { $0.postedAt < $1.postedAt }
        } else {
            chain = []
        }

        return TiboResetCycle(
            lastConfirmedSignal: lastConfirmed,
            lastObservedResetAt: confirmedAt,
            activeCandidate: activeCandidate,
            activePrediction: activePrediction,
            chain: Array(chain.suffix(3))
        )
    }

    func mergingRemote(_ remote: Self, maximumSignals: Int = 128) -> Self {
        var byID: [String: TiboResetSignal] = [:]
        for signal in signals { byID[signal.postID] = signal }
        for signal in remote.signals {
            if let existing = byID[signal.postID], statusRank(existing.status) > statusRank(signal.status) {
                continue
            }
            byID[signal.postID] = signal
        }
        let merged = byID.values.sorted { $0.postedAt > $1.postedAt }
        let retained = Array(merged.prefix(maximumSignals))
        var socialByID: [String: TiboSocialEvidence] = [:]
        for evidence in socialEvidence ?? [] { socialByID[evidence.postID] = evidence }
        for evidence in remote.socialEvidence ?? [] { socialByID[evidence.postID] = evidence }
        let mergedSocial = socialByID.values
            .sorted { $0.postedAt > $1.postedAt }
            .prefix(16)
        return Self(
            sourceStatus: remote.sourceStatus,
            checkedAt: remote.checkedAt,
            lastSuccessAt: remote.lastSuccessAt,
            latestSignal: retained.first,
            recentSignals: retained,
            lastErrorCode: remote.lastErrorCode,
            forecast: freshestForecast(local: forecast, remote: remote.forecast),
            socialEvidence: Array(mergedSocial)
        )
    }

    static let empty = TiboResetMonitorSnapshot(
        sourceStatus: .idle,
        checkedAt: nil,
        lastSuccessAt: nil,
        latestSignal: nil,
        recentSignals: nil,
        lastErrorCode: nil
    )

    func recordingFailure(at date: Date, code: String, offline: Bool) -> Self {
        var copy = self
        copy.sourceStatus = offline ? .offline : .degraded
        copy.checkedAt = date
        copy.lastErrorCode = code
        return copy
    }

    private func statusRank(_ status: TiboSignalStatus) -> Int {
        switch status {
        case .candidate: 0
        case .forecast: 1
        case .expected: 2
        case .confirmed: 3
        }
    }

    private func freshestForecast(
        local: TiboForecastSnapshot?,
        remote: TiboForecastSnapshot?
    ) -> TiboForecastSnapshot? {
        switch (local, remote) {
        case (.none, .none): nil
        case (.some(let value), .none), (.none, .some(let value)): value
        case (.some(let local), .some(let remote)):
            remote.updatedAt >= local.updatedAt ? remote : local
        }
    }
}

enum TiboResetSignalFormatter {
    static func compactLocalTimestamp(
        _ date: Date,
        localeIdentifier: String,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: localeIdentifier)
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("MdHHmm")
        return formatter.string(from: date)
    }

    static func compactLocalWindow(
        start: Date?,
        end: Date?,
        localeIdentifier: String,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String? {
        guard let start else { return nil }
        guard let end, end > start else {
            return compactLocalTimestamp(
                start,
                localeIdentifier: localeIdentifier,
                timeZone: timeZone
            )
        }

        let calendar = Calendar(identifier: .gregorian)
        let sameDay = calendar.dateComponents(
            in: timeZone,
            from: start
        ).day == calendar.dateComponents(in: timeZone, from: end).day
            && calendar.dateComponents(in: timeZone, from: start).month
                == calendar.dateComponents(in: timeZone, from: end).month
            && calendar.dateComponents(in: timeZone, from: start).year
                == calendar.dateComponents(in: timeZone, from: end).year

        if sameDay {
            let endFormatter = DateFormatter()
            endFormatter.locale = Locale(identifier: localeIdentifier)
            endFormatter.timeZone = timeZone
            endFormatter.setLocalizedDateFormatFromTemplate("HHmm")
            return "\(compactLocalTimestamp(start, localeIdentifier: localeIdentifier, timeZone: timeZone))–\(endFormatter.string(from: end))"
        }
        return "\(compactLocalTimestamp(start, localeIdentifier: localeIdentifier, timeZone: timeZone))–\(compactLocalTimestamp(end, localeIdentifier: localeIdentifier, timeZone: timeZone))"
    }

    static func localTimestamp(
        _ date: Date,
        localeIdentifier: String,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: localeIdentifier)
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("MdHHmm")

        let seconds = timeZone.secondsFromGMT(for: date)
        let totalMinutes = abs(seconds) / 60
        let sign = seconds >= 0 ? "+" : "−"
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        let offset = minutes == 0
            ? "UTC\(sign)\(hours)"
            : String(format: "UTC%@%d:%02d", sign, hours, minutes)
        return "\(formatter.string(from: date)) \(offset)"
    }

    static func utcTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm 'UTC'"
        return formatter.string(from: date)
    }

    static func countdown(to target: Date, now: Date) -> String? {
        let remaining = Int(target.timeIntervalSince(now).rounded(.down))
        guard remaining > 0 else { return nil }
        let hours = remaining / 3_600
        let minutes = (remaining % 3_600) / 60
        return String(format: "%d:%02d", hours, minutes)
    }
}
