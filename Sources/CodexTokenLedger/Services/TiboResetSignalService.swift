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
    static let ruleVersion = "tibo-watch-rules-v1.1.0+token-pulse-1"
    static let endpoint = URL(string: "https://api.fxtwitter.com/2/profile/thsottiaux/statuses?count=100&with_replies=true")!

    private let session: URLSession
    private let now: @Sendable () -> Date

    init(session: URLSession = .shared, now: @escaping @Sendable () -> Date = { Date() }) {
        self.session = session
        self.now = now
    }

    func fetch() async throws -> TiboResetMonitorSnapshot {
        var request = URLRequest(url: Self.endpoint)
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("CodexTokenLedger/2.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TiboResetSignalError.invalidResponse
        }
        guard http.statusCode == 200 else { throw TiboResetSignalError.http(http.statusCode) }
        return try Self.decode(data, now: now())
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

            let result = TiboResetRuleEngine.evaluate(status.text)
            guard !result.matchedRuleIDs.isEmpty else { return nil }
            return TiboResetSignal(
                postID: id,
                sourceURL: sourceURL,
                postedAt: postedAt,
                status: result.status,
                resetKind: result.resetKind,
                matchedRuleIDs: result.matchedRuleIDs,
                ruleVersion: Self.ruleVersion,
                contentHash: SHA256.hash(data: Data(status.text.utf8)).map { String(format: "%02x", $0) }.joined()
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
    }

    private struct Rule {
        let id: String
        let expression: NSRegularExpression
    }

    static func evaluate(_ text: String) -> Result {
        guard !matches(suppression, text) else {
            return Result(status: .candidate, resetKind: "forced", matchedRuleIDs: [])
        }
        let matched = rules.filter { matches($0.expression, text) }.map(\.id)
        guard !matched.isEmpty else {
            return Result(status: .candidate, resetKind: "forced", matchedRuleIDs: [])
        }
        let completed = matches(completedExpression, text)
        let kind: String
        if matches(bankedExpression, text) { kind = "banked" }
        else if matches(compensationExpression, text) { kind = "compensation" }
        else { kind = "forced" }
        // This is intentionally the upstream rule-only behavior: a future
        // phrase is still only a candidate until a structured analysis has
        // produced an auditable time window. Never label keyword inference as
        // a confirmed prediction.
        return Result(
            status: completed ? .confirmed : .candidate,
            resetKind: kind,
            matchedRuleIDs: matched
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
        // Runtime evidence from 2026-08-24 uses “Reset has been propagated”.
        // This narrow extension is intentionally versioned separately from the
        // upstream frozen rule set.
        rule("reset-propagated-completed", #"\breset\b[^.!?]{0,100}\b(?:has|have)\s+been\s+propagat(?:ed|ing)\b"#),
    ]

    private static let suppression = regex(#"(?:should\s+really\s+stop\s+pressing|never\s+ending\s+cycle|poster[^.!?]{0,120}shows\s+how\s+resets|receive[^.!?]{0,120}ask\s+for\s+a\s+reset|might\s+also\s+have\s+reset\s+other\s+rate\s+limits)"#)
    private static let completedExpression = regex(#"(?:\b(?:i|we)\s+(?:have|'ve|did)\s+(?:now\s+)?reset(?:ted)?\b|\b(?:usage|rate|codex)\s+limits?\s+(?:have|has)\s+(?:now\s+)?been\s+reset\b|\breset\s+button\s+pressed\b|\bstill\s+did\s+reset\s+the\s+usage\b|\b(?:enjoy|have)\b[^.!?]{0,80}\b(?:a\s+)?(?:nice\s+)?reset\b[\s\S]{0,160}\b(?:landing|should\s+(?:land|show)|propagat(?:e|ing))\b|\breset\b[^.!?]{0,100}\b(?:has|have)\s+been\s+propagat(?:ed|ing)\b)"#)
    private static let bankedExpression = regex(#"\bbanked?\s+reset|reset\s+(?:into\s+)?(?:the\s+)?bank\b"#)
    private static let compensationExpression = regex(#"\bcompensat(?:e|ion|ory)\b"#)

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
