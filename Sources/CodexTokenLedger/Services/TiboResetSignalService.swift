import CryptoKit
import Foundation

enum TiboResetSignalError: Error, AppLocalizedError {
    case invalidResponse
    case http(Int)
    case invalidPayload

    var localizationKey: String {
        switch self {
        case .invalidResponse: "error.tibo.invalidResponse"
        case .http: "error.tibo.http"
        case .invalidPayload: "error.tibo.invalidPayload"
        }
    }

    var localizationArguments: [CVarArg] {
        if case .http(let status) = self { return [status] }
        return []
    }
}

struct TiboResetSignalService: @unchecked Sendable {
    static let ruleVersion = "tibo-watch-rules-v1.2.0+token-pulse-2"
    static let endpoint = URL(string: "https://api.fxtwitter.com/2/profile/thsottiaux/statuses?count=100&with_replies=true")!
    static let forecastEndpoint = URL(string: "https://codex-reset.com/api/forecast")!
    static let feedEndpoint = URL(string: "https://codex-reset.com/api/feed")!

    private let session: URLSession
    private let now: @Sendable () -> Date

    init(session: URLSession = .shared, now: @escaping @Sendable () -> Date = { Date() }) {
        self.session = session
        self.now = now
    }

    func fetch() async throws -> TiboResetMonitorSnapshot {
        var snapshots: [TiboResetMonitorSnapshot] = []
        var lastError: Error?
        var forecastAvailable = false
        var socialEvidenceAvailable = false

        do {
            snapshots.append(try Self.decodeForecast(try await data(from: Self.forecastEndpoint), now: now()))
            forecastAvailable = true
        } catch {
            lastError = error
        }
        do {
            snapshots.append(try Self.decode(try await data(from: Self.endpoint), now: now()))
        } catch {
            lastError = error
        }
        do {
            snapshots.append(try Self.decodeFeed(try await data(from: Self.feedEndpoint), now: now()))
            socialEvidenceAvailable = true
        } catch {
            lastError = error
        }

        guard var combined = snapshots.first else {
            throw lastError ?? TiboResetSignalError.invalidResponse
        }
        for snapshot in snapshots.dropFirst() {
            combined = combined.mergingRemote(snapshot)
        }
        if !forecastAvailable
            || !socialEvidenceAvailable
            || snapshots.contains(where: { $0.sourceStatus != .healthy }) {
            combined.sourceStatus = .degraded
        }
        return combined
    }

    static func decodeFeed(_ data: Data, now: Date) throws -> TiboResetMonitorSnapshot {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let fetchedAt = isoDate(root["fetched_at"]),
              fetchedAt >= now.addingTimeInterval(-7 * 86_400),
              fetchedAt <= now.addingTimeInterval(300),
              let tweets = root["tweets"] as? [[String: Any]]
        else { throw TiboResetSignalError.invalidPayload }

        let cutoff = now.addingTimeInterval(-14 * 86_400)
        let evidence = tweets.compactMap { tweet -> TiboSocialEvidence? in
            guard let postID = tweet["id"] as? String,
                  !postID.isEmpty,
                  let sourceURL = tiboURL(tweet["url"]),
                  let postedAt = isoDate(tweet["at"]),
                  postedAt >= cutoff,
                  postedAt <= now.addingTimeInterval(300),
                  let rawText = tweet["text"] as? String
            else { return nil }

            let text = normalizedText(rawText)
            guard !text.isEmpty else { return nil }
            let explicit = tweet["explicit_reset_claim"] as? Bool ?? false
            let tease = (tweet["tease_classification"] as? [String: Any])?["teasing"] as? Bool ?? false
            let resetRelated = (tweet["tibo_lane"] as? String) == "reset_related"
            guard explicit || tease || resetRelated else { return nil }

            let signalKind: TiboSocialSignalKind
            if explicit {
                signalKind = .explicit
            } else if tease {
                signalKind = .tease
            } else {
                signalKind = .context
            }
            return TiboSocialEvidence(
                postID: postID,
                sourceURL: sourceURL,
                postedAt: postedAt,
                text: text,
                isReply: tweet["is_reply"] as? Bool ?? false,
                replyingTo: tweet["replying_to"] as? String,
                signalKind: signalKind
            )
        }
        .sorted { $0.postedAt > $1.postedAt }

        guard !evidence.isEmpty else { throw TiboResetSignalError.invalidPayload }
        let stale = root["stale"] as? Bool ?? true
        return TiboResetMonitorSnapshot(
            sourceStatus: stale ? .degraded : .healthy,
            checkedAt: now,
            lastSuccessAt: fetchedAt,
            latestSignal: nil,
            recentSignals: nil,
            lastErrorCode: stale ? "feed_stale" : nil,
            forecast: nil,
            socialEvidence: Array(evidence.prefix(16))
        )
    }

    private func data(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("CodexTokenLedger/2.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TiboResetSignalError.invalidResponse
        }
        guard http.statusCode == 200 else { throw TiboResetSignalError.http(http.statusCode) }
        return data
    }

    static func decode(_ data: Data, now: Date) throws -> TiboResetMonitorSnapshot {
        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            throw TiboResetSignalError.invalidPayload
        }
        guard payload.code == 200, let results = payload.results else {
            throw TiboResetSignalError.invalidPayload
        }

        let cutoff = now.addingTimeInterval(-14 * 86_400)
        let signals = results.compactMap { status -> TiboResetSignal? in
            guard status.type == "status",
                  let id = status.id,
                  let url = status.url,
                  let sourceURL = URL(string: url),
                  ["x.com", "twitter.com"].contains(sourceURL.host?.lowercased() ?? ""),
                  status.author?.screenName.lowercased() == "thsottiaux",
                  !status.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !status.text.lowercased().hasPrefix("rt @"),
                  let postedAt = fxDateFormatter.date(from: status.createdAt),
                  postedAt >= cutoff,
                  postedAt <= now.addingTimeInterval(300)
            else { return nil }

            let result = TiboResetRuleEngine.evaluate(status.text, postedAt: postedAt)
            guard !result.matchedRuleIDs.isEmpty else { return nil }
            return TiboResetSignal(
                postID: id,
                sourceURL: sourceURL,
                postedAt: postedAt,
                status: result.status,
                resetKind: result.resetKind,
                matchedRuleIDs: result.matchedRuleIDs,
                ruleVersion: Self.ruleVersion,
                contentHash: digest(status.text),
                expectedStart: result.expectedStart,
                expectedEnd: result.expectedEnd
            )
        }
        .sorted { $0.postedAt > $1.postedAt }

        return TiboResetMonitorSnapshot(
            sourceStatus: .healthy,
            checkedAt: now,
            lastSuccessAt: now,
            latestSignal: signals.first,
            recentSignals: Array(signals.prefix(64)),
            lastErrorCode: nil
        )
    }

    static func decodeForecast(_ data: Data, now: Date) throws -> TiboResetMonitorSnapshot {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let updatedAt = isoDate(root["updated_at"]),
              updatedAt >= now.addingTimeInterval(-7 * 86_400),
              updatedAt <= now.addingTimeInterval(300)
        else { throw TiboResetSignalError.invalidPayload }

        let forecast = forecastSnapshot(root, updatedAt: updatedAt)

        var signals: [TiboResetSignal] = []
        if let lastResetAt = isoDate(root["last_reset_at"]),
           lastResetAt <= now.addingTimeInterval(300),
           let evidence = root["evidence"] as? [[String: Any]],
           let source = evidence.first(where: { ($0["code"] as? String) == "last_reset" }),
           let url = tiboURL(source["href"]),
           let postID = postID(from: url) {
            signals.append(
                TiboResetSignal(
                    postID: postID,
                    sourceURL: url,
                    postedAt: lastResetAt,
                    status: .confirmed,
                    resetKind: "forced",
                    matchedRuleIDs: ["forecast-verified-last-reset"],
                    ruleVersion: ruleVersion,
                    contentHash: digest("\(postID)|\(lastResetAt.timeIntervalSince1970)|confirmed")
                )
            )
        }

        if let teased = root["teased_window"] as? [String: Any],
           let url = tiboURL(teased["url"]),
           let postID = (teased["tweet_id"] as? String) ?? postID(from: url),
           let postedAt = isoDate(teased["at"]),
           postedAt <= now.addingTimeInterval(300),
           let window = teased["window"] as? [String: Any],
           let start = isoDate(window["start_at"]),
           let end = isoDate(window["end_at"]),
           start < end,
           end > now,
           end.timeIntervalSince(start) <= 7 * 86_400 {
            signals.append(
                TiboResetSignal(
                    postID: postID,
                    sourceURL: url,
                    postedAt: postedAt,
                    status: .forecast,
                    resetKind: "forced",
                    matchedRuleIDs: ["forecast-bounded-tease"],
                    ruleVersion: ruleVersion,
                    contentHash: digest((teased["summary"] as? String) ?? postID),
                    expectedStart: start,
                    expectedEnd: end
                )
            )
        }

        if let official = root["official_signal"] as? [String: Any],
           let url = tiboURL(official["url"] ?? official["source_url"]),
           let postID = (official["tweet_id"] as? String) ?? postID(from: url),
           let postedAt = isoDate(official["at"] ?? official["source_posted_at"]),
           postedAt <= now.addingTimeInterval(300) {
            let window = official["window"] as? [String: Any]
            let start = isoDate(window?["start_at"] ?? official["expected_start"])
            let end = isoDate(window?["end_at"] ?? official["expected_end"])
            let statusText = (official["status"] as? String)?.lowercased()
            let status: TiboSignalStatus = statusText == "confirmed" ? .confirmed : .expected
            signals.append(
                TiboResetSignal(
                    postID: postID,
                    sourceURL: url,
                    postedAt: postedAt,
                    status: status,
                    resetKind: "forced",
                    matchedRuleIDs: ["forecast-official-signal"],
                    ruleVersion: ruleVersion,
                    contentHash: digest((official["summary"] as? String) ?? postID),
                    expectedStart: start,
                    expectedEnd: end
                )
            )
        }

        guard !signals.isEmpty || forecast != nil else { throw TiboResetSignalError.invalidPayload }
        let ordered = Dictionary(grouping: signals, by: \TiboResetSignal.postID)
            .compactMap { _, values in values.max { statusRank($0.status) < statusRank($1.status) } }
            .sorted { $0.postedAt > $1.postedAt }
        let fresh = now.timeIntervalSince(updatedAt) <= 6 * 3_600
        return TiboResetMonitorSnapshot(
            sourceStatus: fresh ? .healthy : .degraded,
            checkedAt: now,
            lastSuccessAt: updatedAt,
            latestSignal: ordered.first,
            recentSignals: ordered,
            lastErrorCode: fresh ? nil : "forecast_stale",
            forecast: forecast
        )
    }

    private static func forecastSnapshot(
        _ root: [String: Any],
        updatedAt: Date
    ) -> TiboForecastSnapshot? {
        guard let probabilities = root["probabilities"] as? [String: Any] else { return nil }
        let rounded24h = integer(probabilities["rounded_24h"])
            ?? number(probabilities["raw_24h"]).map { Int(($0 * 100).rounded()) }
        guard let rounded24h, (0...100).contains(rounded24h) else { return nil }

        let rounded48h = integer(probabilities["rounded_48h"])
            ?? number(probabilities["raw_48h"]).map { Int(($0 * 100).rounded()) }
        let confidence = (root["confidence"] as? String)
            .flatMap(TiboForecastConfidence.init(rawValue:)) ?? .unknown
        let lastResetAt = isoDate(root["last_reset_at"])

        let cadence: TiboForecastCadence?
        if let value = root["cadence"] as? [String: Any],
           let median = number(value["recent_median_days"]),
           let sample = integer(value["recent_sample"]),
           let weightedMean = number(value["weighted_mean_days"]) {
            cadence = TiboForecastCadence(
                recentMedianDays: median,
                recentSample: sample,
                weightedMeanDays: weightedMean
            )
        } else {
            cadence = nil
        }

        let commonTimeWindow: TiboForecastTimeWindow?
        if let value = root["time_window"] as? [String: Any],
           let startHour = integer(value["start_hour"]),
           let endHour = integer(value["end_hour"]),
           let label = value["label"] as? String,
           let timeZone = value["timezone"] as? String,
           !label.isEmpty,
           !timeZone.isEmpty {
            commonTimeWindow = TiboForecastTimeWindow(
                startHour: startHour,
                endHour: endHour,
                label: label,
                timeZoneIdentifier: timeZone
            )
        } else {
            commonTimeWindow = nil
        }

        let latestSummary = (root["latest_alert"] as? [String: Any])?["summary"] as? String
        let resetReason: TiboResetReason? = latestSummary?
            .lowercased()
            .contains("25m active users") == true ? .milestone25M : nil

        return TiboForecastSnapshot(
            updatedAt: updatedAt,
            probability24hPercent: rounded24h,
            probability48hPercent: rounded48h.flatMap { (0...100).contains($0) ? $0 : nil },
            confidence: confidence,
            lastResetAt: lastResetAt,
            cadence: cadence,
            commonTimeWindow: commonTimeWindow,
            latestResetReason: resetReason
        )
    }

    private static func tiboURL(_ value: Any?) -> URL? {
        guard let raw = value as? String, let url = URL(string: raw),
              ["x.com", "twitter.com"].contains(url.host?.lowercased() ?? ""),
              url.path.lowercased().hasPrefix("/thsottiaux/status/")
        else { return nil }
        return url
    }

    private static func postID(from url: URL) -> String? {
        let value = url.pathComponents.last ?? ""
        return value.allSatisfy(\.isNumber) && !value.isEmpty ? value : nil
    }

    private static func isoDate(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }

    private static func number(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }

    private static func integer(_ value: Any?) -> Int? {
        (value as? NSNumber)?.intValue
    }

    private static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func normalizedText(_ value: String) -> String {
        value
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func statusRank(_ status: TiboSignalStatus) -> Int {
        switch status {
        case .candidate: 0
        case .forecast: 1
        case .expected: 2
        case .confirmed: 3
        }
    }

    private struct Payload: Decodable {
        let code: Int?
        let results: [Status]?
    }

    private struct Status: Decodable {
        let type: String
        let id: String?
        let url: String?
        let text: String
        let createdAt: String
        let author: Author?

        enum CodingKeys: String, CodingKey {
            case type, id, url, text, author
            case createdAt = "created_at"
        }
    }

    private struct Author: Decodable {
        let screenName: String

        enum CodingKeys: String, CodingKey {
            case screenName = "screen_name"
        }
    }

    private static let fxDateFormatter: DateFormatter = {
        let value = DateFormatter()
        value.locale = Locale(identifier: "en_US_POSIX")
        value.timeZone = TimeZone(secondsFromGMT: 0)
        value.dateFormat = "EEE MMM dd HH:mm:ss Z yyyy"
        return value
    }()
}

enum TiboResetRuleEngine {
    struct Result: Equatable {
        let status: TiboSignalStatus
        let resetKind: String
        let matchedRuleIDs: [String]
        let expectedStart: Date?
        let expectedEnd: Date?
    }

    private struct Rule {
        let id: String
        let expression: NSRegularExpression
    }

    static func evaluate(_ text: String, postedAt: Date? = nil) -> Result {
        guard !matches(suppression, text) else {
            return Result(
                status: .candidate,
                resetKind: "forced",
                matchedRuleIDs: [],
                expectedStart: nil,
                expectedEnd: nil
            )
        }
        let matched = rules.filter { matches($0.expression, text) }.map(\.id)
        guard !matched.isEmpty else {
            return Result(
                status: .candidate,
                resetKind: "forced",
                matchedRuleIDs: [],
                expectedStart: nil,
                expectedEnd: nil
            )
        }
        let completed = matches(completedExpression, text)
        let kind: String
        if matches(bankedExpression, text) { kind = "banked" }
        else if matches(compensationExpression, text) { kind = "compensation" }
        else { kind = "forced" }
        let window = postedAt.flatMap { predictionWindow(for: text, postedAt: $0) }
        let isTease = matches(teaseExpression, text)
        return Result(
            status: completed ? .confirmed : (window == nil ? .candidate : (isTease ? .forecast : .expected)),
            resetKind: kind,
            matchedRuleIDs: matched,
            expectedStart: completed ? nil : window?.start,
            expectedEnd: completed ? nil : window?.end
        )
    }

    private static let rules: [Rule] = [
        rule("reset-dispatched-and-landing", #"\b(?:enjoy|have)\b[^.!?]{0,80}\b(?:a\s+)?(?:nice\s+)?reset\b[\s\S]{0,160}\b(?:landing|should\s+(?:land|show)|propagat(?:e|ing))\b"#),
        rule("first-person-future-reset", #"(?:\b(?:i|we)\b[^.!?]{0,120}\b(?:will|['’]ll)\b[^.!?]{0,140}\breset\b|\breset\b[^.!?]{0,100}\b(?:will\s+be\s+coming|coming\s+this|shortly\s+after|on\s+monday)\b)"#),
        rule("continuing-or-targeted-reset-intent", #"(?:\bresets?\s+will\s+continue\b|\bin\s+need\s+of\s+a\s+reset\b)"#),
        rule("explicit-limit-reset", #"(?:\b(?:usage|rate)\s+limits?\b[^.!?]{0,160}\b(?:reset(?:s|ting)?|reseting)\b|\b(?:reset(?:s|ting)?|reseting)\b[^.!?]{0,160}\b(?:usage|rate)\s+limits?\b)"#),
        rule("usage-reset-announcement", #"(?:\b(?:codex|chatgpt\s+work|paid\s+users?|all\s+codex\s+users?)\b[^.!?]{0,160}\b(?:usage\s+)?reset\b|\b(?:usage\s+)?reset\b[^.!?]{0,160}\b(?:codex|chatgpt\s+work|paid\s+users?|all\s+codex\s+users?)\b)"#),
        rule("reset-the-limits", #"\b(?:reset(?:s|ting)?|reseting)\s+(?:the\s+)?limits?\b"#),
        rule("completed-reset-the-usage", #"\b(?:did|have|has)\s+reset(?:ted)?\s+(?:the\s+)?usage\b"#),
        rule("reset-button", #"\breset\s+button\s+pressed\b"#),
        rule("banked-reset", #"\b(?:banked\s+reset|reset\s+bank|reset\s+into\s+(?:the|your)\s+bank)\b"#),
        rule("future-manual-resets", #"\b(?:will|get(?:ting)?)\b[^.!?]{0,100}\bmore\s+manual\s+resets?\b"#),
        rule("vague-limit-reset-intent", #"\b(?:feeling\s+like|thinking\s+about|might)\b[^.!?]{0,80}\blimit\s+reset\b"#),
        rule("soon-not-today", #"\bresets?\b[^.!?]{0,120}\bsoon\b[^.!?]{0,80}\bnot\s+today\b|\bsoon\b[^.!?]{0,80}\bnot\s+today\b"#),
        rule("reset-propagated-completed", #"\breset\b[^.!?]{0,100}\b(?:has|have)\s+been\s+propagat(?:ed|ing)\b"#),
    ]

    private static let suppression = regex(#"(?:should\s+really\s+stop\s+pressing|never\s+ending\s+cycle|poster[^.!?]{0,120}shows\s+how\s+resets|receive[^.!?]{0,120}ask\s+for\s+a\s+reset|might\s+also\s+have\s+reset\s+other\s+rate\s+limits)"#)
    private static let completedExpression = regex(#"(?:\b(?:i|we)\s+(?:have|'ve|did)\s+(?:now\s+)?reset(?:ted)?\b|\b(?:usage|rate|codex)\s+limits?\s+(?:have|has)\s+(?:now\s+)?been\s+reset\b|\breset\s+button\s+pressed\b|\bstill\s+did\s+reset\s+the\s+usage\b|\b(?:enjoy|have)\b[^.!?]{0,80}\b(?:a\s+)?(?:nice\s+)?reset\b[\s\S]{0,160}\b(?:landing|should\s+(?:land|show)|propagat(?:e|ing))\b|\breset\b[^.!?]{0,100}\b(?:has|have)\s+been\s+propagat(?:ed|ing)\b)"#)
    private static let bankedExpression = regex(#"\bbanked?\s+reset|reset\s+(?:into\s+)?(?:the\s+)?bank\b"#)
    private static let compensationExpression = regex(#"\bcompensat(?:e|ion|ory)\b"#)
    private static let teaseExpression = regex(#"\bsoon\b[^.!?]{0,80}\bnot\s+today\b|\bfeeling\s+like\b"#)

    private static func predictionWindow(for text: String, postedAt: Date) -> (start: Date, end: Date)? {
        let lower = text.lowercased()
        if lower.range(of: #"next\s+30\s+minutes"#, options: .regularExpression) != nil {
            return (postedAt, postedAt.addingTimeInterval(30 * 60))
        }
        if lower.range(of: #"next\s+(?:few|couple\s+of)\s+hours"#, options: .regularExpression) != nil {
            return (postedAt, postedAt.addingTimeInterval(4 * 3_600))
        }
        if lower.range(of: #"next\s+hour"#, options: .regularExpression) != nil {
            return (postedAt, postedAt.addingTimeInterval(3_600))
        }

        var calendar = Calendar(identifier: .gregorian)
        guard let sourceTimeZone = TimeZone(identifier: "America/Los_Angeles") else { return nil }
        calendar.timeZone = sourceTimeZone
        if lower.contains("not today") || lower.contains("tomorrow") {
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: postedAt) else { return nil }
            let start = calendar.startOfDay(for: nextDay)
            guard let end = calendar.date(byAdding: .day, value: 1, to: start)?.addingTimeInterval(-0.001) else {
                return nil
            }
            return (start, end)
        }
        if lower.contains("later in the day") || lower.contains("later today") || lower.contains("tonight") {
            let start = postedAt
            guard let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: postedAt))?
                .addingTimeInterval(-0.001)
            else { return nil }
            return start < end ? (start, end) : nil
        }
        if lower.range(of: #"in\s+(?:a\s+bit|a\s+few\s+minutes)|shortly"#, options: .regularExpression) != nil {
            return (postedAt, postedAt.addingTimeInterval(3 * 3_600))
        }
        if let match = lower.firstMatch(of: /in\s+(\d{1,2})\s+(minute|minutes|hour|hours)/),
           let amount = Int(match.1), amount > 0 {
            let seconds = match.2.hasPrefix("hour") ? amount * 3_600 : amount * 60
            return (postedAt, postedAt.addingTimeInterval(TimeInterval(seconds)))
        }
        let weekdays = [
            "sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4,
            "thursday": 5, "friday": 6, "saturday": 7,
        ]
        if let weekday = weekdays.first(where: { lower.contains("on \($0.key)") })?.value,
           let day = nextDate(weekday: weekday, after: postedAt, calendar: calendar) {
            let start = calendar.startOfDay(for: day)
            guard let end = calendar.date(byAdding: .day, value: 1, to: start)?.addingTimeInterval(-0.001) else {
                return nil
            }
            return (start, end)
        }
        return nil
    }

    private static func nextDate(weekday: Int, after date: Date, calendar: Calendar) -> Date? {
        let current = calendar.component(.weekday, from: date)
        let days = (weekday - current + 7) % 7
        return calendar.date(byAdding: .day, value: days == 0 ? 7 : days, to: date)
    }

    private static func rule(_ id: String, _ pattern: String) -> Rule {
        Rule(id: id, expression: regex(pattern))
    }

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // Every expression is a build-time constant and covered by tests.
        try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    private static func matches(_ expression: NSRegularExpression, _ text: String) -> Bool {
        expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }
}
