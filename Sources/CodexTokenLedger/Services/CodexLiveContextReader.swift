import Darwin
import Foundation

enum CodexLiveContextReaderError: AppLocalizedError {
    case noSessionDirectory(String)

    var localizationKey: String { "error.live.noSessions" }
    var localizationArguments: [CVarArg] {
        guard case .noSessionDirectory(let path) = self else { return [] }
        return [path]
    }
}

/// Reads Codex's accounting stream directly. The latest model call is used for
/// context occupancy, while every distinct cumulative delta after the latest
/// task_started event is aggregated as the current user turn.
struct CodexLiveContextReader: Sendable {
    private let maximumCandidateFiles = 24
    private let activeDiscoveryWindow: TimeInterval = 30 * 60
    private let maximumEventLineBytes = 1_048_576

    func read(codexHome: URL, preferredSourcePath: String? = nil) throws -> CodexLiveContextSnapshot? {
        if let preferredSourcePath {
            let preferred = URL(fileURLWithPath: preferredSourcePath)
            if FileManager.default.fileExists(atPath: preferred.path), let value = read(file: preferred) {
                return value
            }
        }

        let sessions = codexHome.appendingPathComponent("sessions", isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: sessions.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw CodexLiveContextReaderError.noSessionDirectory(sessions.path)
        }

        for file in recentJSONLFiles(in: sessions).prefix(maximumCandidateFiles) {
            if let value = read(file: file) { return value }
        }
        return nil
    }

    /// Discovers every unfinished task among the most recently written Codex
    /// rollouts. When there is no unfinished task, the latest completed context
    /// is returned as an inactive fallback so the menu does not go blank.
    func readActiveContexts(
        codexHome: URL,
        preferredSourcePaths: [String] = [],
        maximumResults: Int = 8
    ) throws -> [CodexLiveContextSnapshot] {
        let sessions = codexHome.appendingPathComponent("sessions", isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: sessions.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw CodexLiveContextReaderError.noSessionDirectory(sessions.path)
        }

        var seen = Set<String>()
        let preferred = preferredSourcePaths.map(URL.init(fileURLWithPath:))
        let preferredSet = Set(preferred.map { $0.standardizedFileURL.path })
        let candidates = (preferred + Array(recentJSONLFiles(in: sessions).prefix(maximumCandidateFiles)))
            .filter { seen.insert($0.standardizedFileURL.path).inserted }

        var active: [CodexLiveContextSnapshot] = []
        var fallback: CodexLiveContextSnapshot?
        for file in candidates {
            if !preferredSet.contains(file.standardizedFileURL.path) {
                let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                guard Date().timeIntervalSince(modified) <= activeDiscoveryWindow else { continue }
            }
            guard let data = try? Data(contentsOf: file, options: [.mappedIfSafe]), !data.isEmpty,
                  let context = read(file: file, data: data)
            else { continue }
            if fallback == nil || context.updatedAt > fallback!.updatedAt { fallback = context }
            if context.isTaskActive {
                active.append(context)
                if active.count >= max(1, maximumResults) { break }
            }
        }

        if active.isEmpty, let fallback { return [fallback] }
        return active.sorted { $0.updatedAt > $1.updatedAt }
    }

    func read(file: URL) -> CodexLiveContextSnapshot? {
        guard let data = try? Data(contentsOf: file, options: [.mappedIfSafe]), !data.isEmpty else { return nil }
        return read(file: file, data: data)
    }

    private func read(file: URL, data: Data) -> CodexLiveContextSnapshot? {
        let metadata = firstEventObject(kind: "session_meta", in: data)
        let metadataPayload = metadata?["payload"] as? [String: Any] ?? [:]
        let fallbackID = file.deletingPathExtension().lastPathComponent
        let sessionID = string(metadataPayload["id"] ?? metadataPayload["session_id"]) ?? fallbackID
        let fallbackDate = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            ?? Date()

        guard let taskLine = lastEventLine(kind: "task_started", in: data, range: data.startIndex..<data.endIndex),
              let taskObject = jsonObject(data.subdata(in: taskLine)),
              isEvent(taskObject, kind: "task_started")
        else {
            return readLatestCallFallback(
                file: file,
                data: data,
                metadataPayload: metadataPayload,
                sessionID: sessionID,
                fallbackDate: fallbackDate
            )
        }

        let taskPayload = taskObject["payload"] as? [String: Any] ?? [:]
        let turnID = string(taskPayload["turn_id"])
        var projectPath = string(metadataPayload["cwd"])
        var currentModel = "unknown"
        var reasoningEffort: String?
        var contextWindow = integer(taskPayload["model_context_window"])

        if let priorContext = lastEventObject(
            kind: "turn_context",
            in: data,
            range: data.startIndex..<taskLine.lowerBound
        ), let payload = priorContext["payload"] as? [String: Any] {
            currentModel = string(payload["model"]) ?? currentModel
            reasoningEffort = string(payload["effort"])
            projectPath = string(payload["cwd"]) ?? projectPath
        }

        var previousCumulative = lastValidTokenEvent(
            in: data,
            before: taskLine.lowerBound
        )?.total
        var latestCall: TokenUsage?
        var latestTotal: TokenUsage?
        var latestTimestamp = parseDate(taskObject["timestamp"]) ?? fallbackDate
        var calls: [CodexModelCallUsage] = []
        var turnUsage = TokenUsage()
        var duplicatesIgnored = 0

        walkLines(in: data, range: taskLine.lowerBound..<data.endIndex) { line in
            guard isPotentialAccountingEvent(line),
                  let object = jsonObject(line),
                  let payload = object["payload"] as? [String: Any]
            else { return }

            if isEvent(object, kind: "turn_context") {
                currentModel = string(payload["model"]) ?? currentModel
                reasoningEffort = string(payload["effort"]) ?? reasoningEffort
                projectPath = string(payload["cwd"]) ?? projectPath
                return
            }

            guard isEvent(object, kind: "token_count"),
                  let info = payload["info"] as? [String: Any],
                  let lastDictionary = info["last_token_usage"] as? [String: Any],
                  let totalDictionary = info["total_token_usage"] as? [String: Any],
                  let emittedLast = parseUsage(lastDictionary),
                  let total = parseUsage(totalDictionary),
                  emittedLast.totalTokens > 0
            else { return }

            contextWindow = integer(info["model_context_window"]) ?? contextWindow
            let eventTimestamp = parseDate(object["timestamp"]) ?? latestTimestamp

            let accepted: TokenUsage?
            if let previousCumulative {
                if total == previousCumulative || total.totalTokens == previousCumulative.totalTokens {
                    duplicatesIgnored += 1
                    accepted = nil
                } else if let delta = total.subtracting(previousCumulative) {
                    accepted = delta
                } else {
                    // A cumulative session counter is monotonic. Ignore stale
                    // or out-of-order events instead of accepting last_usage
                    // and then double-counting the recovery delta.
                    duplicatesIgnored += 1
                    accepted = nil
                }
            } else {
                accepted = emittedLast
            }

            guard let accepted else { return }
            previousCumulative = total
            latestCall = emittedLast.hasCompleteBreakdown ? emittedLast : accepted
            latestTotal = total
            latestTimestamp = eventTimestamp

            guard accepted.totalTokens > 0 else { return }
            turnUsage += accepted
            calls.append(
                CodexModelCallUsage(
                    id: "\(turnID ?? sessionID)|\(total.totalTokens)",
                    timestamp: latestTimestamp,
                    model: currentModel,
                    usage: accepted,
                    cumulativeTaskUsage: total
                )
            )
        }

        guard let latestCall, let latestTotal else {
            return readLatestCallFallback(
                file: file,
                data: data,
                metadataPayload: metadataPayload,
                sessionID: sessionID,
                fallbackDate: fallbackDate
            )
        }

        return CodexLiveContextSnapshot(
            id: sessionID,
            sourcePath: file.path,
            projectPath: projectPath,
            threadTitle: nil,
            titleSource: nil,
            turnID: turnID,
            model: currentModel,
            reasoningEffort: reasoningEffort,
            updatedAt: latestTimestamp,
            lastRequest: latestCall,
            currentTurnUsage: turnUsage,
            currentTurnCalls: calls,
            taskTotal: latestTotal,
            modelContextWindow: contextWindow,
            duplicateEventsIgnored: duplicatesIgnored,
            isTaskActive: taskIsActive(in: data)
        )
    }

    private func readLatestCallFallback(
        file: URL,
        data: Data,
        metadataPayload: [String: Any],
        sessionID: String,
        fallbackDate: Date
    ) -> CodexLiveContextSnapshot? {
        guard let event = lastValidTokenEvent(in: data, before: data.endIndex) else { return nil }
        let contextObject = lastEventObject(
            kind: "turn_context",
            in: data,
            range: data.startIndex..<data.endIndex
        )
        let contextPayload = contextObject?["payload"] as? [String: Any] ?? [:]
        let timestamp = parseDate(event.object["timestamp"]) ?? fallbackDate
        let model = string(contextPayload["model"]) ?? "unknown"
        let call = CodexModelCallUsage(
            id: "\(sessionID)|\(event.total.totalTokens)",
            timestamp: timestamp,
            model: model,
            usage: event.last,
            cumulativeTaskUsage: event.total
        )
        return CodexLiveContextSnapshot(
            id: sessionID,
            sourcePath: file.path,
            projectPath: string(contextPayload["cwd"] ?? metadataPayload["cwd"]),
            threadTitle: nil,
            titleSource: nil,
            turnID: string(contextPayload["turn_id"]),
            model: model,
            reasoningEffort: string(contextPayload["effort"]),
            updatedAt: timestamp,
            lastRequest: event.last,
            currentTurnUsage: event.last,
            currentTurnCalls: [call],
            taskTotal: event.total,
            modelContextWindow: event.contextWindow,
            duplicateEventsIgnored: 0,
            isTaskActive: taskIsActive(in: data)
        )
    }

    private func taskIsActive(in data: Data) -> Bool {
        guard let started = lastEventLine(
            kind: "task_started",
            in: data,
            range: data.startIndex..<data.endIndex
        ) else { return false }
        guard let completed = lastEventLine(
            kind: "task_complete",
            in: data,
            range: data.startIndex..<data.endIndex
        ) else { return true }
        return started.lowerBound > completed.lowerBound
    }

    private func recentJSONLFiles(in root: URL) -> [URL] {
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey,
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var files: [(URL, Date)] = []
        for case let url as URL in enumerator where url.pathExtension.lowercased() == "jsonl" {
            let values = try? url.resourceValues(forKeys: keys)
            guard values?.isRegularFile == true, values?.isSymbolicLink != true else { continue }
            files.append((url, values?.contentModificationDate ?? .distantPast))
        }
        return files.sorted { $0.1 > $1.1 }.map(\.0)
    }

    private func firstEventObject(kind: String, in data: Data) -> [String: Any]? {
        let upper = min(data.endIndex, data.startIndex + min(data.count, 1_048_576))
        guard let line = firstEventLine(kind: kind, in: data, range: data.startIndex..<upper) else { return nil }
        return jsonObject(data.subdata(in: line))
    }

    private func lastEventObject(kind: String, in data: Data, range: Range<Data.Index>) -> [String: Any]? {
        guard let line = lastEventLine(kind: kind, in: data, range: range) else { return nil }
        return jsonObject(data.subdata(in: line))
    }

    private func firstEventLine(kind: String, in data: Data, range: Range<Data.Index>) -> Range<Data.Index>? {
        let matches = eventNeedles(kind).compactMap { data.range(of: $0, in: range) }
        guard let match = matches.min(by: { $0.lowerBound < $1.lowerBound }) else { return nil }
        return completeLine(around: match, in: data, limits: range)
    }

    private func lastEventLine(kind: String, in data: Data, range: Range<Data.Index>) -> Range<Data.Index>? {
        guard !range.isEmpty else { return nil }
        let matches = eventNeedles(kind).compactMap { data.range(of: $0, options: .backwards, in: range) }
        guard let match = matches.max(by: { $0.lowerBound < $1.lowerBound }) else { return nil }
        return completeLine(around: match, in: data, limits: range)
    }

    private func completeLine(
        around match: Range<Data.Index>,
        in data: Data,
        limits: Range<Data.Index>
    ) -> Range<Data.Index>? {
        let newline = Data([0x0A])
        let start = data.range(of: newline, options: .backwards, in: limits.lowerBound..<match.lowerBound)?.upperBound
            ?? limits.lowerBound
        let end = data.range(of: newline, in: match.upperBound..<limits.upperBound)?.lowerBound
            ?? limits.upperBound
        guard end > start, end - start <= maximumEventLineBytes else { return nil }
        return start..<end
    }

    private struct ValidTokenEvent {
        let object: [String: Any]
        let last: TokenUsage
        let total: TokenUsage
        let contextWindow: Int64?
    }

    private func lastValidTokenEvent(in data: Data, before upperBound: Data.Index) -> ValidTokenEvent? {
        var searchUpperBound = upperBound
        var attempts = 0
        while searchUpperBound > data.startIndex, attempts < 128 {
            attempts += 1
            guard let line = lastEventLine(
                kind: "token_count",
                in: data,
                range: data.startIndex..<searchUpperBound
            ) else { return nil }
            searchUpperBound = line.lowerBound
            guard let object = jsonObject(data.subdata(in: line)),
                  isEvent(object, kind: "token_count"),
                  let payload = object["payload"] as? [String: Any],
                  let info = payload["info"] as? [String: Any],
                  let lastDictionary = info["last_token_usage"] as? [String: Any],
                  let totalDictionary = info["total_token_usage"] as? [String: Any],
                  let last = parseUsage(lastDictionary),
                  let total = parseUsage(totalDictionary),
                  last.totalTokens > 0
            else { continue }
            return ValidTokenEvent(
                object: object,
                last: last,
                total: total,
                contextWindow: integer(info["model_context_window"])
            )
        }
        return nil
    }

    private func walkLines(in data: Data, range: Range<Data.Index>, consume: (Data) -> Void) {
        data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return }
            var offset = range.lowerBound
            while offset < range.upperBound {
                let remaining = range.upperBound - offset
                let found = memchr(base.advanced(by: offset), Int32(0x0A), remaining)
                let endOffset: Int
                if let found {
                    endOffset = base.distance(to: found.assumingMemoryBound(to: UInt8.self))
                } else {
                    endOffset = range.upperBound
                }
                let length = endOffset - offset
                if length > 0, length <= maximumEventLineBytes {
                    consume(Data(bytes: base.advanced(by: offset), count: length))
                }
                offset = endOffset < range.upperBound ? endOffset + 1 : range.upperBound
            }
        }
    }

    private func isPotentialAccountingEvent(_ line: Data) -> Bool {
        line.range(of: Data("\"type\":\"turn_context\"".utf8)) != nil
            || line.range(of: Data("\"type\": \"turn_context\"".utf8)) != nil
            || line.range(of: Data("\"type\":\"token_count\"".utf8)) != nil
            || line.range(of: Data("\"type\": \"token_count\"".utf8)) != nil
    }

    private func eventNeedles(_ kind: String) -> [Data] {
        [Data("\"type\":\"\(kind)\"".utf8), Data("\"type\": \"\(kind)\"".utf8)]
    }

    private func isEvent(_ object: [String: Any], kind: String) -> Bool {
        if object["type"] as? String == kind { return true }
        guard object["type"] as? String == "event_msg",
              let payload = object["payload"] as? [String: Any]
        else { return false }
        return payload["type"] as? String == kind
    }

    private func jsonObject(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private func parseUsage(_ dictionary: [String: Any]) -> TokenUsage? {
        guard let input = integer(dictionary["input_tokens"]),
              let output = integer(dictionary["output_tokens"])
        else { return nil }
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

    private func parseDate(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }

    private func integer(_ value: Any?) -> Int64? {
        if let value = value as? NSNumber { return value.int64Value }
        if let value = value as? String { return Int64(value) }
        return nil
    }

    private func string(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
