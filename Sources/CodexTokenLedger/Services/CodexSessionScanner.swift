import Darwin
import Foundation

enum CodexSessionScannerError: AppLocalizedError {
    case codexHomeNotFound(String)
    case noSessionDirectory(String)

    var localizationKey: String {
        switch self {
        case .codexHomeNotFound: "error.scanner.homeNotFound"
        case .noSessionDirectory: "error.scanner.noSessions"
        }
    }

    var localizationArguments: [CVarArg] {
        switch self {
        case .codexHomeNotFound(let path), .noSessionDirectory(let path): [path]
        }
    }
}

struct CodexSessionScanner: Sendable {
    private let maximumReportedIssues = 100
    private let cacheVersion = 3
    private let quickTailWindow = 256 * 1_024

    func scan(codexHome: URL, includeArchived: Bool) throws -> UsageSnapshot {
        try scanWithCache(codexHome: codexHome, includeArchived: includeArchived, cache: nil).snapshot
    }

    func scanWithCache(
        codexHome: URL,
        includeArchived: Bool,
        cache: CodexScanCache?
    ) throws -> CodexScanResult {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: codexHome.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw CodexSessionScannerError.codexHomeNotFound(codexHome.path)
        }

        let sessionsURL = codexHome.appendingPathComponent("sessions", isDirectory: true)
        guard fileManager.fileExists(atPath: sessionsURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw CodexSessionScannerError.noSessionDirectory(codexHome.path)
        }

        var roots = [sessionsURL]
        if includeArchived {
            let archivedURL = codexHome.appendingPathComponent("archived_sessions", isDirectory: true)
            if fileManager.fileExists(atPath: archivedURL.path, isDirectory: &isDirectory), isDirectory.boolValue {
                roots.append(archivedURL)
            }
        }

        let files = roots.flatMap(jsonlFiles(in:)).sorted { $0.path < $1.path }
        var allRecords: [UsageRecord] = []
        var sessionMetadata: [String: ParsedSessionMetadata] = [:]
        var allIssues: [ScanIssue] = []
        var fingerprints = Set<String>()
        var updatedCacheFiles: [String: CachedFileAnalysis] = [:]
        let reusableCache = cache?.version == cacheVersion
            && cache?.codexHome == codexHome.path
            && cache?.includeArchived == includeArchived
            ? cache?.files ?? [:]
            : [:]

        for file in files {
            let values = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let fileSize = Int64(values?.fileSize ?? 0)
            let modificationDate = values?.contentModificationDate ?? .distantPast
            let parsed: ParsedFile

            if let cached = reusableCache[file.path],
               cached.fileSize == fileSize,
               cached.modificationDate == modificationDate {
                parsed = ParsedFile(records: cached.records, metadata: cached.metadata, issues: cached.issues)
            } else {
                parsed = parse(file: file)
            }

            updatedCacheFiles[file.path] = CachedFileAnalysis(
                fileSize: fileSize,
                modificationDate: modificationDate,
                records: parsed.records,
                metadata: parsed.metadata,
                issues: parsed.issues
            )
            if let metadata = parsed.metadata {
                sessionMetadata[metadata.id] = metadata
            }
            for record in parsed.records where fingerprints.insert(record.id).inserted {
                allRecords.append(record)
            }
            if allIssues.count < maximumReportedIssues {
                allIssues.append(contentsOf: parsed.issues.prefix(maximumReportedIssues - allIssues.count))
            }
        }

        allRecords.sort { $0.timestamp < $1.timestamp }
        let grouped = Dictionary(grouping: allRecords, by: \UsageRecord.sessionID)
        let summaries = grouped.compactMap { sessionID, records -> SessionSummary? in
            guard let first = records.first, let last = records.last else { return nil }
            let metadata = sessionMetadata[sessionID]
            return SessionSummary(
                id: sessionID,
                startedAt: metadata?.startedAt ?? first.timestamp,
                lastActivityAt: last.timestamp,
                projectPath: metadata?.projectPath ?? last.projectPath,
                latestModel: last.model,
                eventCount: records.count,
                usage: records.reduce(into: TokenUsage()) { $0 += $1.usage }
            )
        }.sorted { $0.lastActivityAt > $1.lastActivityAt }

        let snapshot = UsageSnapshot(
            scannedAt: Date(), codexHome: codexHome.path, fileCount: files.count,
            records: allRecords, sessions: summaries, issues: allIssues
        )
        let updatedCache = CodexScanCache(
            version: cacheVersion,
            codexHome: codexHome.path,
            includeArchived: includeArchived,
            files: updatedCacheFiles
        )
        return CodexScanResult(snapshot: snapshot, cache: updatedCache)
    }

    private func jsonlFiles(in root: URL) -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        return enumerator.compactMap { element in
            guard let url = element as? URL, url.pathExtension.lowercased() == "jsonl" else { return nil }
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile == true, values?.isSymbolicLink != true else { return nil }
            return url
        }
    }

    private func parse(file: URL) -> ParsedFile {
        guard let data = try? Data(contentsOf: file, options: [.mappedIfSafe]) else {
            return ParsedFile(
                records: [],
                metadata: nil,
                issues: [issue(file: file, line: 0, message: "file_unreadable")]
            )
        }

        // Modern Codex token_count events include total_token_usage. Reading the
        // first metadata line and the last accounting/context lines gives an
        // exact session total without walking multi-GB embedded image/tool data.
        // Files without a cumulative counter fall back to the detailed parser.
        if let summary = parseCumulativeSummary(file: file, data: data) {
            return summary
        }

        return parseDetailed(file: file, data: data)
    }

    private func parseCumulativeSummary(file: URL, data: Data) -> ParsedFile? {
        guard !data.isEmpty else { return nil }

        let fallbackDate = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            ?? .distantPast
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let headUpperBound = min(data.endIndex, data.startIndex + min(data.count, 1_024 * 1_024))
        let headRange = data.startIndex..<headUpperBound
        let sessionObject = jsonObject(
            from: firstLine(containing: eventNeedles("session_meta"), in: data, range: headRange)
        )

        var sessionID = file.deletingPathExtension().lastPathComponent
        var projectPath: String?
        var startedAt = fallbackDate
        if let sessionObject,
           sessionObject["type"] as? String == "session_meta",
           let payload = sessionObject["payload"] as? [String: Any] {
            sessionID = string(payload["id"]) ?? string(payload["session_id"]) ?? sessionID
            projectPath = string(payload["cwd"])
            startedAt = parseDate(payload["timestamp"], parser: parser)
                ?? parseDate(sessionObject["timestamp"], parser: parser)
                ?? startedAt
        }

        let tokenObject = lastEventObject(kind: "token_count", in: data)
        guard
            let tokenObject,
            let payload = tokenObject["payload"] as? [String: Any],
            let info = payload["info"] as? [String: Any],
            let cumulative = info["total_token_usage"] as? [String: Any],
            let usage = parseUsage(cumulative),
            usage.totalTokens > 0
        else { return nil }

        var currentModel = "unknown"
        var reasoningEffort: String?
        if let contextObject = lastEventObject(kind: "turn_context", in: data),
           let contextPayload = contextObject["payload"] as? [String: Any] {
            currentModel = string(contextPayload["model"]) ?? currentModel
            reasoningEffort = string(contextPayload["effort"])
            projectPath = string(contextPayload["cwd"]) ?? projectPath
        }

        let timestamp = parseDate(tokenObject["timestamp"], parser: parser) ?? fallbackDate
        let record = UsageRecord(
            id: "\(sessionID)|cumulative",
            timestamp: timestamp,
            sessionID: sessionID,
            sourcePath: file.path,
            projectPath: projectPath,
            model: currentModel,
            reasoningEffort: reasoningEffort,
            usage: usage
        )
        return ParsedFile(
            records: [record],
            metadata: ParsedSessionMetadata(id: sessionID, startedAt: startedAt, projectPath: projectPath),
            issues: []
        )
    }

    private func lastEventObject(kind: String, in data: Data) -> [String: Any]? {
        let windows = [quickTailWindow, 1_024 * 1_024, 2 * 1_024 * 1_024]
        for window in windows {
            let lowerBound = max(data.startIndex, data.endIndex - min(data.count, window))
            let range = lowerBound..<data.endIndex
            if let line = lastLine(containing: eventNeedles(kind), in: data, range: range),
               let object = jsonObject(from: line),
               (object["type"] as? String == kind
                    || ((object["type"] as? String) == "event_msg"
                        && (object["payload"] as? [String: Any])?["type"] as? String == kind)) {
                return object
            }
        }
        return nil
    }

    private func eventNeedles(_ kind: String) -> [Data] {
        [Data("\"type\":\"\(kind)\"".utf8), Data("\"type\": \"\(kind)\"".utf8)]
    }

    private func firstLine(containing needles: [Data], in data: Data, range: Range<Data.Index>) -> Data? {
        let matches = needles.compactMap { data.range(of: $0, in: range) }
        guard let match = matches.min(by: { $0.lowerBound < $1.lowerBound }) else { return nil }
        return completeLine(around: match, in: data, lowerLimit: range.lowerBound, upperLimit: range.upperBound)
    }

    private func lastLine(containing needles: [Data], in data: Data, range: Range<Data.Index>) -> Data? {
        let matches = needles.compactMap { data.range(of: $0, options: .backwards, in: range) }
        guard let match = matches.max(by: { $0.lowerBound < $1.lowerBound }) else { return nil }
        return completeLine(around: match, in: data, lowerLimit: range.lowerBound, upperLimit: range.upperBound)
    }

    private func completeLine(
        around match: Range<Data.Index>,
        in data: Data,
        lowerLimit: Data.Index,
        upperLimit: Data.Index
    ) -> Data? {
        let newline = Data([0x0A])
        let start = data.range(of: newline, options: .backwards, in: lowerLimit..<match.lowerBound)?.upperBound
            ?? lowerLimit
        let endSearchUpperBound = min(data.endIndex, max(upperLimit, match.upperBound))
        let end = data.range(of: newline, in: match.upperBound..<endSearchUpperBound)?.lowerBound
            ?? endSearchUpperBound
        guard end > start, end - start <= 1_024 * 1_024 else { return nil }
        return data.subdata(in: start..<end)
    }

    private func jsonObject(from data: Data?) -> [String: Any]? {
        guard let data,
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any]
        else { return nil }
        return dictionary
    }

    private func parseDetailed(file: URL, data: Data) -> ParsedFile {

        let fallbackDate = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
        var sessionID = file.deletingPathExtension().lastPathComponent
        var projectPath: String?
        var startedAt = fallbackDate
        var currentModel = "unknown"
        var reasoningEffort: String?
        var records: [UsageRecord] = []
        var issues: [ScanIssue] = []
        var lineNumber = 0
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        // Some rollout lines contain very large embedded images or tool output.
        // Walk the memory-mapped file with libc's memchr and materialize only
        // the three small event kinds this app needs. This keeps a multi-GB
        // history from becoming a multi-GB heap allocation.
        data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return }
            var offset = 0

            while offset < rawBuffer.count {
                let remaining = rawBuffer.count - offset
                let found = memchr(base.advanced(by: offset), Int32(0x0A), remaining)
                let endOffset: Int
                if let found {
                    let newline = found.assumingMemoryBound(to: UInt8.self)
                    endOffset = base.distance(to: newline)
                } else {
                    endOffset = rawBuffer.count
                }

                lineNumber += 1
                let lineLength = endOffset - offset
                if lineLength > 0 {
                    let prefixLength = min(lineLength, 2_048)
                    let prefixBuffer = UnsafeBufferPointer(start: base.advanced(by: offset), count: prefixLength)
                    let prefix = String(decoding: prefixBuffer, as: UTF8.self)
                    let relevant = prefix.contains("\"type\":\"session_meta\"")
                        || prefix.contains("\"type\":\"turn_context\"")
                        || prefix.contains("\"type\":\"token_count\"")
                        || prefix.contains("\"type\": \"session_meta\"")
                        || prefix.contains("\"type\": \"turn_context\"")
                        || prefix.contains("\"type\": \"token_count\"")

                    if relevant {
                        // Relevant Codex accounting events are normally a few
                        // KB. If a metadata event embeds an oversized field,
                        // recover its early scalar fields without copying it.
                        if lineLength <= 1_048_576 {
                            let line = Data(bytes: base.advanced(by: offset), count: lineLength)
                            consume(
                                line: line,
                                file: file,
                                lineNumber: lineNumber,
                                fallbackDate: fallbackDate,
                                parser: parser,
                                sessionID: &sessionID,
                                projectPath: &projectPath,
                                startedAt: &startedAt,
                                currentModel: &currentModel,
                                reasoningEffort: &reasoningEffort,
                                records: &records,
                                issues: &issues
                            )
                        } else {
                            recoverOversizedMetadata(
                                prefix: prefix,
                                parser: parser,
                                sessionID: &sessionID,
                                projectPath: &projectPath,
                                startedAt: &startedAt,
                                currentModel: &currentModel,
                                reasoningEffort: &reasoningEffort
                            )
                        }
                    }
                }

                offset = endOffset < rawBuffer.count ? endOffset + 1 : rawBuffer.count
            }
        }

        return ParsedFile(
            records: records,
            metadata: ParsedSessionMetadata(id: sessionID, startedAt: startedAt, projectPath: projectPath),
            issues: issues
        )
    }

    private func consume(
        line: Data,
        file: URL,
        lineNumber: Int,
        fallbackDate: Date,
        parser: ISO8601DateFormatter,
        sessionID: inout String,
        projectPath: inout String?,
        startedAt: inout Date,
        currentModel: inout String,
        reasoningEffort: inout String?,
        records: inout [UsageRecord],
        issues: inout [ScanIssue]
    ) {
        guard
            let object = try? JSONSerialization.jsonObject(with: line),
            let dictionary = object as? [String: Any]
        else {
            if issues.count < 10 {
                issues.append(issue(file: file, line: lineNumber, message: "invalid_jsonl_skipped"))
            }
            return
        }

        let type = dictionary["type"] as? String
        let payload = dictionary["payload"] as? [String: Any] ?? [:]
        let timestamp = parseDate(dictionary["timestamp"], parser: parser) ?? fallbackDate

        switch type {
        case "session_meta":
            sessionID = string(payload["id"]) ?? string(payload["session_id"]) ?? sessionID
            projectPath = string(payload["cwd"]) ?? projectPath
            startedAt = parseDate(payload["timestamp"], parser: parser) ?? timestamp

        case "turn_context":
            currentModel = string(payload["model"]) ?? currentModel
            reasoningEffort = string(payload["effort"]) ?? reasoningEffort
            projectPath = string(payload["cwd"]) ?? projectPath

        case "event_msg" where string(payload["type"]) == "token_count":
            guard
                let info = payload["info"] as? [String: Any],
                let last = info["last_token_usage"] as? [String: Any],
                let usage = parseUsage(last),
                usage.totalTokens > 0
            else { return }

            let id = [
                sessionID,
                ISO8601DateFormatter.string(from: timestamp, timeZone: .gmt, formatOptions: [.withInternetDateTime, .withFractionalSeconds]),
                currentModel,
                String(usage.inputTokens),
                String(usage.cachedInputTokens),
                String(usage.outputTokens)
            ].joined(separator: "|")

            records.append(
                UsageRecord(
                    id: id,
                    timestamp: timestamp,
                    sessionID: sessionID,
                    sourcePath: file.path,
                    projectPath: projectPath,
                    model: currentModel,
                    reasoningEffort: reasoningEffort,
                    usage: usage
                )
            )

        default:
            return
        }
    }

    private func recoverOversizedMetadata(
        prefix: String,
        parser: ISO8601DateFormatter,
        sessionID: inout String,
        projectPath: inout String?,
        startedAt: inout Date,
        currentModel: inout String,
        reasoningEffort: inout String?
    ) {
        if prefix.contains("session_meta") {
            sessionID = jsonStringField("id", in: prefix) ?? sessionID
            projectPath = jsonStringField("cwd", in: prefix) ?? projectPath
            if let timestamp = jsonStringField("timestamp", in: prefix), let date = parser.date(from: timestamp) {
                startedAt = date
            }
        } else if prefix.contains("turn_context") {
            currentModel = jsonStringField("model", in: prefix) ?? currentModel
            projectPath = jsonStringField("cwd", in: prefix) ?? projectPath
            reasoningEffort = jsonStringField("effort", in: prefix) ?? reasoningEffort
        }
    }

    private func jsonStringField(_ key: String, in text: String) -> String? {
        let escapedKey = NSRegularExpression.escapedPattern(for: key)
        guard let expression = try? NSRegularExpression(pattern: "\"\(escapedKey)\"\\s*:\\s*\"([^\"]*)\"") else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard
            let match = expression.firstMatch(in: text, range: range),
            let capture = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[capture])
    }

    private func parseUsage(_ dictionary: [String: Any]) -> TokenUsage? {
        guard let input = integer(dictionary["input_tokens"]), let output = integer(dictionary["output_tokens"]) else {
            return nil
        }
        let usage = TokenUsage(
            inputTokens: input,
            cachedInputTokens: integer(dictionary["cached_input_tokens"]) ?? 0,
            cacheWriteInputTokens: integer(dictionary["cache_write_input_tokens"]) ?? 0,
            outputTokens: output,
            reasoningOutputTokens: integer(dictionary["reasoning_output_tokens"]) ?? 0,
            reportedTotalTokens: integer(dictionary["total_tokens"])
        )
        return usage.isValidCodexCounter ? usage : nil
    }

    private func parseDate(_ value: Any?, parser: ISO8601DateFormatter) -> Date? {
        guard let text = string(value) else { return nil }
        return parser.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }

    private func integer(_ value: Any?) -> Int64? {
        if let number = value as? NSNumber { return number.int64Value }
        if let text = value as? String { return Int64(text) }
        return nil
    }

    private func string(_ value: Any?) -> String? {
        value as? String
    }

    private func issue(file: URL, line: Int, message: String) -> ScanIssue {
        ScanIssue(id: "\(file.path):\(line):\(message)", file: file.path, line: line, message: message)
    }
}

struct CodexScanResult: Sendable {
    let snapshot: UsageSnapshot
    let cache: CodexScanCache
}

struct CodexScanCache: Codable, Sendable {
    let version: Int
    let codexHome: String
    let includeArchived: Bool
    let files: [String: CachedFileAnalysis]
}

struct CachedFileAnalysis: Codable, Sendable {
    let fileSize: Int64
    let modificationDate: Date
    let records: [UsageRecord]
    let metadata: ParsedSessionMetadata?
    let issues: [ScanIssue]
}

struct ParsedSessionMetadata: Codable, Sendable {
    let id: String
    let startedAt: Date
    let projectPath: String?
}

private struct ParsedFile {
    let records: [UsageRecord]
    let metadata: ParsedSessionMetadata?
    let issues: [ScanIssue]
}
