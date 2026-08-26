import CryptoKit
import Foundation

enum CodexAccountServiceError: AppLocalizedError {
    case codexNotFound
    case launchFailed(String)
    case rpcEnded
    case rpcError(String)
    case invalidResponse(String)

    var localizationKey: String {
        switch self {
        case .codexNotFound: "error.account.codexNotFound"
        case .launchFailed: "error.account.launchFailed"
        case .rpcEnded: "error.account.rpcEnded"
        case .rpcError: "error.account.rpcError"
        case .invalidResponse: "error.account.invalidResponse"
        }
    }

    var localizationArguments: [CVarArg] {
        switch self {
        case .launchFailed(let message), .rpcError(let message): [message]
        case .invalidResponse(let field): [field]
        default: []
        }
    }
}

struct CodexAccountService: Sendable {
    private let timeout: TimeInterval

    init(timeout: TimeInterval = 30) {
        self.timeout = timeout
    }

    func fetch(codexHome: URL) throws -> CodexAccountUsageSnapshot {
        let executable = try resolveCodexExecutable()
        let process = Process()
        let input = Pipe()
        let output = Pipe()

        process.executableURL = executable
        process.arguments = ["-s", "read-only", "-a", "never", "app-server"]
        var environment = ProcessInfo.processInfo.environment
        environment["CODEX_HOME"] = codexHome.path
        environment["PATH"] = effectivePath(environment["PATH"])
        process.environment = environment
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw CodexAccountServiceError.launchFailed(error.localizedDescription)
        }

        let timeoutWork = DispatchWorkItem {
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: timeoutWork)

        let connection = JSONLineRPCConnection(
            input: input.fileHandleForWriting,
            output: output.fileHandleForReading
        )
        defer {
            timeoutWork.cancel()
            try? input.fileHandleForWriting.close()
            if process.isRunning { process.terminate() }
            process.waitUntilExit()
        }

        _ = try connection.request(
            id: 1,
            method: "initialize",
            params: ["clientInfo": ["name": "CodexTokenLedger", "version": "1.9.0"]]
        )
        try connection.notify(method: "initialized")
        let account = try connection.request(id: 2, method: "account/read", params: [:])
        let limits = try connection.request(id: 3, method: "account/rateLimits/read")
        let accountUsage = try? connection.request(id: 4, method: "account/usage/read")
        return try Self.parse(
            accountResult: account,
            rateLimitsResult: limits,
            accountUsageResult: accountUsage,
            codexHome: codexHome
        )
    }

    static func parse(
        accountResult: [String: Any],
        rateLimitsResult: [String: Any],
        accountUsageResult: [String: Any]? = nil,
        codexHome: URL,
        now: Date = Date()
    ) throws -> CodexAccountUsageSnapshot {
        let account = accountResult["account"] as? [String: Any]
        let email = normalized(account?["email"])
        let planFromAccount = normalized(account?["planType"] ?? account?["plan_type"])

        guard let rootLimits = rateLimitsResult["rateLimits"] as? [String: Any]
            ?? rateLimitsResult["rate_limits"] as? [String: Any]
        else {
            throw CodexAccountServiceError.invalidResponse("rateLimits")
        }

        let plan = planFromAccount ?? normalized(rootLimits["planType"] ?? rootLimits["plan_type"])
        let primary = quotaWindow(
            from: rootLimits["primary"],
            id: "primary",
            fallbackTitle: "Primary"
        )
        let secondary = quotaWindow(
            from: rootLimits["secondary"],
            id: "secondary",
            fallbackTitle: "Weekly"
        )
        let credits = creditBalance(from: rootLimits["credits"])
        let accountTokenUsage = accountTokenUsage(from: accountUsageResult)

        let byLimit = rateLimitsResult["rateLimitsByLimitId"] as? [String: Any]
            ?? rateLimitsResult["rate_limits_by_limit_id"] as? [String: Any]
            ?? [:]
        var additional: [CodexQuotaWindow] = []
        for key in byLimit.keys.sorted() where key != "codex" {
            guard let item = byLimit[key] as? [String: Any] else { continue }
            let name = normalized(item["limitName"] ?? item["limit_name"])
                ?? readableLimitName(key)
            if let window = quotaWindow(
                from: item["primary"],
                id: "\(key)-primary",
                fallbackTitle: name,
                preferFallbackTitle: true
            ) {
                additional.append(window)
            }
            if let window = quotaWindow(
                from: item["secondary"],
                id: "\(key)-secondary",
                fallbackTitle: name,
                preferFallbackTitle: true
            ) {
                additional.append(window)
            }
        }

        let authData = try? CodexCredentialStore.authData(in: codexHome)
        let stableID: String
        if let credentialID = authData.flatMap(CodexCredentialStore.stableAccountID(from:)) {
            stableID = credentialID
        } else {
            let identitySource = email?.lowercased() ?? codexHome.standardizedFileURL.path
            let digest = SHA256.hash(data: Data(identitySource.utf8))
            stableID = digest.prefix(12).map { String(format: "%02x", $0) }.joined()
        }

        return CodexAccountUsageSnapshot(
            id: stableID,
            email: email,
            plan: plan,
            codexHome: codexHome.standardizedFileURL.path,
            primaryWindow: primary,
            secondaryWindow: secondary,
            additionalWindows: additional,
            credits: credits,
            accountTokenUsage: accountTokenUsage,
            updatedAt: now
        )
    }

    private func resolveCodexExecutable() throws -> URL {
        var candidates: [String] = []
        if let configured = ProcessInfo.processInfo.environment["CODEX_EXECUTABLE"] {
            candidates.append(configured)
        }
        candidates += ["/usr/local/bin/codex", "/opt/homebrew/bin/codex"]
        let path = effectivePath(ProcessInfo.processInfo.environment["PATH"])
        candidates += path.split(separator: ":").map { "\($0)/codex" }
        for candidate in candidates {
            let expanded = (candidate as NSString).expandingTildeInPath
            if FileManager.default.isExecutableFile(atPath: expanded) {
                return URL(fileURLWithPath: expanded)
            }
        }
        throw CodexAccountServiceError.codexNotFound
    }

    private func effectivePath(_ current: String?) -> String {
        let defaults = "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        guard let current, !current.isEmpty else { return defaults }
        return current + ":" + defaults
    }

    private static func quotaWindow(
        from value: Any?,
        id: String,
        fallbackTitle: String,
        preferFallbackTitle: Bool = false
    ) -> CodexQuotaWindow? {
        guard let dictionary = value as? [String: Any],
              let used = flexibleDouble(dictionary["usedPercent"] ?? dictionary["used_percent"])
        else { return nil }
        let minutes = flexibleInt(dictionary["windowDurationMins"] ?? dictionary["window_duration_mins"])
        let reset = flexibleDouble(dictionary["resetsAt"] ?? dictionary["resets_at"])
            .map { Date(timeIntervalSince1970: $0) }
        return CodexQuotaWindow(
            id: id,
            title: preferFallbackTitle ? fallbackTitle : windowTitle(minutes: minutes, fallback: fallbackTitle),
            usedPercent: used,
            windowMinutes: minutes,
            resetsAt: reset
        )
    }

    private static func creditBalance(from value: Any?) -> CodexCreditBalance? {
        guard let dictionary = value as? [String: Any] else { return nil }
        return CodexCreditBalance(
            hasCredits: dictionary["hasCredits"] as? Bool
                ?? dictionary["has_credits"] as? Bool
                ?? false,
            unlimited: dictionary["unlimited"] as? Bool ?? false,
            balance: flexibleDouble(dictionary["balance"])
        )
    }

    private static func accountTokenUsage(from value: [String: Any]?) -> CodexAccountTokenUsage? {
        guard let value, let summary = value["summary"] as? [String: Any] else { return nil }
        let parsedSummary = CodexAccountTokenUsageSummary(
            lifetimeTokens: flexibleInt64(summary["lifetimeTokens"] ?? summary["lifetime_tokens"]),
            peakDailyTokens: flexibleInt64(summary["peakDailyTokens"] ?? summary["peak_daily_tokens"]),
            longestRunningTurnSeconds: flexibleInt64(
                summary["longestRunningTurnSec"] ?? summary["longest_running_turn_sec"]
            ),
            currentStreakDays: flexibleInt64(summary["currentStreakDays"] ?? summary["current_streak_days"]),
            longestStreakDays: flexibleInt64(summary["longestStreakDays"] ?? summary["longest_streak_days"])
        )
        let rawBuckets = value["dailyUsageBuckets"] as? [[String: Any]]
            ?? value["daily_usage_buckets"] as? [[String: Any]]
            ?? []
        let buckets = rawBuckets.compactMap { item -> CodexAccountDailyTokenUsage? in
            guard let date = normalized(item["startDate"] ?? item["start_date"]),
                  let tokens = flexibleInt64(item["tokens"])
            else { return nil }
            return CodexAccountDailyTokenUsage(startDate: date, tokens: tokens)
        }.sorted { $0.startDate < $1.startDate }
        return CodexAccountTokenUsage(summary: parsedSummary, dailyBuckets: buckets)
    }

    private static func windowTitle(minutes: Int?, fallback: String) -> String {
        guard let minutes, minutes > 0 else { return fallback }
        if minutes == 300 { return "5-hour quota" }
        if minutes >= 6 * 24 * 60 { return "Weekly quota" }
        if minutes.isMultiple(of: 24 * 60) { return "\(minutes / (24 * 60))-day quota" }
        if minutes.isMultiple(of: 60) { return "\(minutes / 60)-hour quota" }
        return fallback
    }

    private static func readableLimitName(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    private static func normalized(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func flexibleDouble(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return nil
    }

    private static func flexibleInt(_ value: Any?) -> Int? {
        flexibleDouble(value).map(Int.init)
    }

    private static func flexibleInt64(_ value: Any?) -> Int64? {
        if let value = value as? Int64 { return value }
        if let value = value as? Int { return Int64(value) }
        if let value = value as? NSNumber { return value.int64Value }
        if let value = value as? String { return Int64(value.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return nil
    }

}

private final class JSONLineRPCConnection {
    private let input: FileHandle
    private let output: FileHandle
    private var buffer = Data()

    init(input: FileHandle, output: FileHandle) {
        self.input = input
        self.output = output
    }

    func request(id: Int, method: String, params: [String: Any]? = nil) throws -> [String: Any] {
        var object: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": method]
        if let params { object["params"] = params }
        try send(object)
        while true {
            let message = try nextMessage()
            guard Self.integer(message["id"]) == id else { continue }
            if let error = message["error"] as? [String: Any] {
                let text = error["message"] as? String ?? "Unknown RPC error"
                throw CodexAccountServiceError.rpcError(text)
            }
            guard let result = message["result"] as? [String: Any] else {
                throw CodexAccountServiceError.invalidResponse(method)
            }
            return result
        }
    }

    func notify(method: String) throws {
        try send(["jsonrpc": "2.0", "method": method])
    }

    private func send(_ object: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)
        try input.write(contentsOf: data)
    }

    private func nextMessage() throws -> [String: Any] {
        while true {
            if let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer[..<newline]
                buffer.removeSubrange(...newline)
                if line.isEmpty { continue }
                if let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] {
                    return object
                }
                continue
            }
            let chunk = output.availableData
            guard !chunk.isEmpty else { throw CodexAccountServiceError.rpcEnded }
            buffer.append(chunk)
        }
    }

    private static func integer(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }
}
