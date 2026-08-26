import Foundation

enum TiboSignalStatus: String, Codable, Sendable {
    case candidate
    case expected
    case confirmed
}

enum TiboSignalSourceStatus: String, Codable, Sendable {
    case idle
    case healthy
    case degraded
    case offline
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
    /// A structured prediction is optional because rule-only monitoring does
    /// not invent a date from vague wording. These fields are populated only
    /// when a source adapter can supply an explicit, auditable window.
    var expectedStart: Date? = nil
    var expectedEnd: Date? = nil

    var id: String { postID }
}

/// The compact product model adapted from Tibo Watch's dashboard domain.
/// Account quota resets are deliberately absent: this describes only the
/// public Tibo reset cycle.
struct TiboResetCycle: Equatable, Sendable {
    let lastConfirmedSignal: TiboResetSignal?
    let lastObservedResetAt: Date?
    let baselineNextResetAt: Date?
    let baselineIsProvisional: Bool
    let activeCandidate: TiboResetSignal?
    let activePrediction: TiboResetSignal?
    let chain: [TiboResetSignal]

    var activeSignal: TiboResetSignal? { activePrediction ?? activeCandidate }
    var displayedNextResetAt: Date? { activePrediction?.expectedStart ?? baselineNextResetAt }
    var displayedNextResetEnd: Date? { activePrediction?.expectedEnd }
    var usesSignalPrediction: Bool { activePrediction != nil }
}

struct TiboResetMonitorSnapshot: Codable, Equatable, Sendable {
    var sourceStatus: TiboSignalSourceStatus
    var checkedAt: Date?
    var lastSuccessAt: Date?
    var latestSignal: TiboResetSignal?
    /// Recent public reset updates, newest first. Optional keeps caches written
    /// by older app versions decodable; `signals` falls back to latestSignal.
    var recentSignals: [TiboResetSignal]? = nil
    var lastErrorCode: String?

    var signals: [TiboResetSignal] {
        guard let recentSignals, !recentSignals.isEmpty else {
            return latestSignal.map { [$0] } ?? []
        }
        return recentSignals
    }

    /// Mirrors the upstream reset-cycle rules:
    /// - a confirmed non-banked reset anchors the seven-day baseline;
    /// - a reached structured prediction can establish a provisional anchor;
    /// - predictions posted at or before the newest confirmation are fulfilled;
    /// - a genuinely newer prediction temporarily overrides the baseline.
    func cycle(now: Date = Date()) -> TiboResetCycle {
        let primary = signals
            .filter { $0.resetKind != "banked" }
            .sorted { $0.postedAt > $1.postedAt }

        let lastConfirmed = primary
            .filter { $0.status == .confirmed && $0.postedAt <= now }
            .max { $0.postedAt < $1.postedAt }
        let confirmedAt = lastConfirmed?.postedAt

        let reachedPrediction = primary
            .filter { signal in
                guard signal.status == .expected,
                      let expectedStart = signal.expectedStart,
                      expectedStart <= now
                else { return false }
                if let confirmedAt, signal.postedAt <= confirmedAt { return false }
                return true
            }
            .max { ($0.expectedStart ?? .distantPast) < ($1.expectedStart ?? .distantPast) }

        let observedAt: Date?
        let provisional: Bool
        if let reached = reachedPrediction?.expectedStart,
           confirmedAt == nil || reached > confirmedAt! {
            observedAt = reached
            provisional = true
        } else {
            observedAt = confirmedAt
            provisional = false
        }

        let activePredictions = primary.filter { signal in
            guard signal.status == .expected else { return false }
            if let confirmedAt, signal.postedAt <= confirmedAt { return false }
            let boundary = signal.expectedEnd ?? signal.expectedStart
            return boundary.map { $0 > now } ?? true
        }
        let activePrediction = activePredictions.max { $0.postedAt < $1.postedAt }
        let activeCandidate = primary
            .filter { signal in
                guard signal.status == .candidate else { return false }
                if let confirmedAt { return signal.postedAt > confirmedAt }
                return true
            }
            .max { $0.postedAt < $1.postedAt }

        let baseline = observedAt?.addingTimeInterval(7 * 86_400)
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
            lastObservedResetAt: observedAt,
            baselineNextResetAt: baseline,
            baselineIsProvisional: provisional,
            activeCandidate: activeCandidate,
            activePrediction: activePrediction,
            chain: Array(chain.suffix(3))
        )
    }

    /// Preserve already-observed facts when the public endpoint's rolling
    /// result page no longer contains them. Records are metadata-only and
    /// bounded, so confirmed reset history survives refreshes without storing
    /// post bodies.
    func mergingRemote(_ remote: Self, maximumSignals: Int = 128) -> Self {
        var byID: [String: TiboResetSignal] = [:]
        for signal in signals { byID[signal.postID] = signal }
        for signal in remote.signals { byID[signal.postID] = signal }
        let merged = byID.values.sorted { $0.postedAt > $1.postedAt }
        let retained = Array(merged.prefix(maximumSignals))
        return Self(
            sourceStatus: remote.sourceStatus,
            checkedAt: remote.checkedAt,
            lastSuccessAt: remote.lastSuccessAt,
            latestSignal: retained.first,
            recentSignals: retained,
            lastErrorCode: remote.lastErrorCode
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

    /// Converts the source's UTC instant to the user's current Mac timezone.
    /// The explicit UTC offset prevents a compact timestamp from looking like
    /// the source timezone or an unconverted server value.
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
}
