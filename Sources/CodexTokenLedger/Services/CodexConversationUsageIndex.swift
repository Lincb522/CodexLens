import Darwin
import Foundation
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Durable accounting state for one Codex rollout. `total_token_usage` remains
/// cumulative across ordinary turns and occasionally starts a new counter
/// epoch. Completed epochs plus the current raw counter form the task total.
struct CodexConversationUsageCheckpoint: Codable, Hashable, Sendable {
    var completedEpochUsage = TokenUsage()
    var currentCounterUsage: TokenUsage?
    var currentTurnID: String?
    var currentTurnOffset: Int64?
    var processedOffset: Int64 = 0
    var latestTokenTimestamp: String?
    var awaitingCounterAfterTurnStart = false

    var totalUsage: TokenUsage {
        completedEpochUsage + (currentCounterUsage ?? TokenUsage())
    }
}

struct CodexConversationUsageIndex: Sendable {
    private let maximumEventLineBytes = 1_048_576
    private let prefixBytes = 2_048

    func checkpoint(
        file: URL,
        sessionID: String,
        codexHome: URL?,
        previous: CodexConversationUsageCheckpoint? = nil
    ) -> CodexConversationUsageCheckpoint {
        let fileSize = Self.fileSize(file)
        guard fileSize > 0 else { return CodexConversationUsageCheckpoint() }

        if let previous, previous.processedOffset == fileSize {
            return previous
        }

        let historyMode = codexHome.flatMap {
            CodexThreadHistoryModeReader().historyMode(sessionID: sessionID, codexHome: $0)
        }

        if let codexHome,
           let indexed = CodexTurnHistoryUsageReader().checkpoint(
               file: file,
               fileSize: fileSize,
               sessionID: sessionID,
               codexHome: codexHome,
               previous: previous
           ) {
            return advancing(indexed, through: file, fileSize: fileSize)
        }

        if historyMode == "legacy",
           let legacy = CodexLegacySessionUsageReader().checkpoint(file: file, fileSize: fileSize) {
            return legacy
        }

        if let previous,
           previous.processedOffset >= 0,
           previous.processedOffset < fileSize {
            return advancing(previous, through: file, fileSize: fileSize)
        }

        guard let data = try? Data(contentsOf: file, options: [.mappedIfSafe]) else {
            return previous ?? CodexConversationUsageCheckpoint()
        }
        return advancing(
            CodexConversationUsageCheckpoint(),
            through: data,
            range: data.startIndex..<data.endIndex,
            absoluteBaseOffset: 0
        )
    }

    static func inferredCodexHome(for rollout: URL) -> URL? {
        let path = rollout.standardizedFileURL.path
        for marker in ["/sessions/", "/archived_sessions/"] {
            guard let range = path.range(of: marker) else { continue }
            return URL(fileURLWithPath: String(path[..<range.lowerBound]), isDirectory: true)
        }
        return nil
    }

    private func advancing(
        _ checkpoint: CodexConversationUsageCheckpoint,
        through file: URL,
        fileSize: Int64
    ) -> CodexConversationUsageCheckpoint {
        guard checkpoint.processedOffset < fileSize,
              let handle = try? FileHandle(forReadingFrom: file)
        else { return checkpoint }
        defer { try? handle.close() }

        do {
            try handle.seek(toOffset: UInt64(checkpoint.processedOffset))
            guard let data = try handle.readToEnd(), !data.isEmpty else { return checkpoint }
            return advancing(
                checkpoint,
                through: data,
                range: data.startIndex..<data.endIndex,
                absoluteBaseOffset: checkpoint.processedOffset
            )
        } catch {
            return checkpoint
        }
    }

    private func advancing(
        _ checkpoint: CodexConversationUsageCheckpoint,
        through data: Data,
        range: Range<Data.Index>,
        absoluteBaseOffset: Int64
    ) -> CodexConversationUsageCheckpoint {
        guard !range.isEmpty else { return checkpoint }
        var result = checkpoint

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

                let lineLength = endOffset - offset
                if lineLength > 0, lineLength <= maximumEventLineBytes {
                    let prefixLength = min(lineLength, prefixBytes)
                    if prefixContainsAccountingEvent(
                        base: base.advanced(by: offset),
                        length: prefixLength
                    ) {
                        let line = Data(bytes: base.advanced(by: offset), count: lineLength)
                        consume(
                            line,
                            absoluteOffset: absoluteBaseOffset + Int64(offset - range.lowerBound),
                            into: &result
                        )
                    }
                }

                offset = endOffset < range.upperBound ? endOffset + 1 : range.upperBound
            }
        }

        result.processedOffset = absoluteBaseOffset + Int64(range.count)
        return result
    }

    private func prefixContainsAccountingEvent(base: UnsafePointer<UInt8>, length: Int) -> Bool {
        guard length > 0 else { return false }
        return Self.accountingNeedles.contains { needle in
            needle.withUnsafeBytes { needleBuffer in
                guard let needleBase = needleBuffer.baseAddress else { return false }
                return memmem(base, length, needleBase, needleBuffer.count) != nil
            }
        }
    }

    private func consume(
        _ line: Data,
        absoluteOffset: Int64,
        into checkpoint: inout CodexConversationUsageCheckpoint
    ) {
        guard let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
              let payload = object["payload"] as? [String: Any]
        else { return }

        if Self.isEvent(object, payload: payload, kind: "task_started") {
            if checkpoint.currentTurnOffset != absoluteOffset {
                checkpoint.currentTurnID = Self.string(payload["turn_id"])
                checkpoint.currentTurnOffset = absoluteOffset
                checkpoint.awaitingCounterAfterTurnStart = true
            }
            return
        }

        guard Self.isEvent(object, payload: payload, kind: "token_count"),
              let info = payload["info"] as? [String: Any],
              let dictionary = info["total_token_usage"] as? [String: Any],
              let total = CodexTokenUsageParser.parse(dictionary),
              total.totalTokens > 0
        else { return }
        let lastUsage = (info["last_token_usage"] as? [String: Any]).flatMap(CodexTokenUsageParser.parse)

        if let previous = checkpoint.currentCounterUsage {
            if checkpoint.awaitingCounterAfterTurnStart {
                if Self.startsNewCounterEpoch(previous: previous, next: total, lastUsage: lastUsage) {
                    checkpoint.completedEpochUsage += previous
                }
            } else if total.totalTokens < previous.totalTokens {
                // A lower counter without a task boundary is stale or out of order.
                return
            }
        }
        checkpoint.currentCounterUsage = total
        checkpoint.latestTokenTimestamp = Self.string(object["timestamp"])
        checkpoint.awaitingCounterAfterTurnStart = false
    }

    fileprivate static func startsNewCounterEpoch(
        previous: TokenUsage,
        next: TokenUsage,
        lastUsage: TokenUsage?
    ) -> Bool {
        if next.totalTokens < previous.totalTokens { return true }
        guard let lastUsage else { return false }
        let delta = next.totalTokens - previous.totalTokens
        if delta == lastUsage.totalTokens { return false }
        return next.totalTokens == lastUsage.totalTokens
    }

    private static func isEvent(
        _ object: [String: Any],
        payload: [String: Any],
        kind: String
    ) -> Bool {
        if object["type"] as? String == kind { return true }
        return object["type"] as? String == "event_msg" && payload["type"] as? String == kind
    }

    private static func string(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func fileSize(_ file: URL) -> Int64 {
        let values = try? file.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }

    private static let accountingNeedles: [Data] = ["task_started", "token_count"].flatMap { kind in
        [
            Data(("\"type\":\"" + kind + "\"").utf8),
            Data(("\"type\": \"" + kind + "\"").utf8),
        ]
    }
}

private struct CodexThreadHistoryModeReader {
    func historyMode(sessionID: String, codexHome: URL) -> String? {
        let databaseURL = codexHome.appendingPathComponent("state_5.sqlite")
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return nil }
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(databaseURL.path, &database, flags, nil) == SQLITE_OK,
              let database
        else {
            if let database { sqlite3_close(database) }
            return nil
        }
        defer { sqlite3_close(database) }

        var statement: OpaquePointer?
        let sql = "SELECT history_mode FROM threads WHERE id = ? LIMIT 1"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else { return nil }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, sessionID, -1, sqliteTransient)
        guard sqlite3_step(statement) == SQLITE_ROW,
              let value = sqlite3_column_text(statement, 0)
        else { return nil }
        return String(cString: value)
    }
}

private struct CodexIndexedTokenEvent {
    let usage: TokenUsage
    let lastUsage: TokenUsage?
    let timestamp: String?
}

private struct CodexRolloutTokenRangeReader {
    private let initialTailBytes: Int64 = 256 * 1_024
    private let initialHeadBytes: Int64 = 256 * 1_024
    private let maximumEventLineBytes = 1_048_576

    func firstTokenEvent(handle: FileHandle, start: Int64, end: Int64) -> CodexIndexedTokenEvent? {
        var window = min(initialHeadBytes, end - start)
        while window > 0 {
            do {
                try handle.seek(toOffset: UInt64(start))
                let data = try handle.read(upToCount: Int(window)) ?? Data()
                if let event = firstTokenEvent(in: data, upperIsRangeEnd: start + window == end) {
                    return event
                }
            } catch {
                return nil
            }
            if start + window == end { return nil }
            window = min(end - start, window * 4)
        }
        return nil
    }

    func lastTokenEvent(handle: FileHandle, start: Int64, end: Int64) -> CodexIndexedTokenEvent? {
        var window = min(initialTailBytes, end - start)
        while window > 0 {
            let lower = max(start, end - window)
            do {
                try handle.seek(toOffset: UInt64(lower))
                let data = try handle.read(upToCount: Int(end - lower)) ?? Data()
                if let event = lastTokenEvent(in: data, lowerIsRangeStart: lower == start) {
                    return event
                }
            } catch {
                return nil
            }
            if lower == start { return nil }
            window = min(end - start, window * 4)
        }
        return nil
    }

    private func firstTokenEvent(in data: Data, upperIsRangeEnd: Bool) -> CodexIndexedTokenEvent? {
        guard !data.isEmpty else { return nil }
        var searchLowerBound = data.startIndex
        var attempts = 0
        while searchLowerBound < data.endIndex, attempts < 64 {
            attempts += 1
            let range = searchLowerBound..<data.endIndex
            let matches = Self.tokenNeedles.compactMap { data.range(of: $0, in: range) }
            guard let match = matches.min(by: { $0.lowerBound < $1.lowerBound }) else { return nil }
            searchLowerBound = match.upperBound

            let lineStart = data.range(
                of: Self.newline,
                options: .backwards,
                in: data.startIndex..<match.lowerBound
            )?.upperBound ?? data.startIndex
            let lineEnd = data.range(
                of: Self.newline,
                in: match.upperBound..<data.endIndex
            )?.lowerBound ?? data.endIndex
            if lineEnd == data.endIndex, !upperIsRangeEnd { return nil }
            guard lineEnd > lineStart, lineEnd - lineStart <= maximumEventLineBytes else { continue }
            if let event = tokenEvent(from: data.subdata(in: lineStart..<lineEnd)) { return event }
        }
        return nil
    }

    private func lastTokenEvent(in data: Data, lowerIsRangeStart: Bool) -> CodexIndexedTokenEvent? {
        guard !data.isEmpty else { return nil }
        var searchUpperBound = data.endIndex
        var attempts = 0
        while searchUpperBound > data.startIndex, attempts < 64 {
            attempts += 1
            let range = data.startIndex..<searchUpperBound
            let matches = Self.tokenNeedles.compactMap {
                data.range(of: $0, options: .backwards, in: range)
            }
            guard let match = matches.max(by: { $0.lowerBound < $1.lowerBound }) else { return nil }
            searchUpperBound = match.lowerBound

            let lineStart = data.range(
                of: Self.newline,
                options: .backwards,
                in: data.startIndex..<match.lowerBound
            )?.upperBound ?? data.startIndex
            if lineStart == data.startIndex, !lowerIsRangeStart {
                return nil
            }
            let lineEnd = data.range(
                of: Self.newline,
                in: match.upperBound..<data.endIndex
            )?.lowerBound ?? data.endIndex
            guard lineEnd > lineStart, lineEnd - lineStart <= maximumEventLineBytes else { continue }
            if let event = tokenEvent(from: data.subdata(in: lineStart..<lineEnd)) { return event }
        }
        return nil
    }

    private func tokenEvent(from line: Data) -> CodexIndexedTokenEvent? {
        guard let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
              object["type"] as? String == "event_msg",
              let payload = object["payload"] as? [String: Any],
              payload["type"] as? String == "token_count",
              let info = payload["info"] as? [String: Any],
              let dictionary = info["total_token_usage"] as? [String: Any],
              let usage = CodexTokenUsageParser.parse(dictionary),
              usage.totalTokens > 0
        else { return nil }
        let lastUsage = (info["last_token_usage"] as? [String: Any]).flatMap(CodexTokenUsageParser.parse)
        return CodexIndexedTokenEvent(
            usage: usage,
            lastUsage: lastUsage,
            timestamp: object["timestamp"] as? String
        )
    }

    private static let newline = Data([0x0A])
    private static let tokenNeedles = [
        Data("\"type\":\"token_count\"".utf8),
        Data("\"type\": \"token_count\"".utf8),
    ]
}

private struct CodexLegacySessionUsageReader {
    func checkpoint(file: URL, fileSize: Int64) -> CodexConversationUsageCheckpoint? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        guard let event = CodexRolloutTokenRangeReader().lastTokenEvent(
            handle: handle,
            start: 0,
            end: fileSize
        ) else { return nil }
        return CodexConversationUsageCheckpoint(
            completedEpochUsage: TokenUsage(),
            currentCounterUsage: event.usage,
            currentTurnID: nil,
            currentTurnOffset: nil,
            processedOffset: fileSize,
            latestTokenTimestamp: event.timestamp,
            awaitingCounterAfterTurnStart: false
        )
    }
}

private struct CodexTurnHistoryUsageReader {
    private struct TurnRow {
        let id: String
        let start: Int64
        let end: Int64?
    }

    func checkpoint(
        file: URL,
        fileSize: Int64,
        sessionID: String,
        codexHome: URL,
        previous: CodexConversationUsageCheckpoint?
    ) -> CodexConversationUsageCheckpoint? {
        let databaseURL = codexHome.appendingPathComponent("thread_history_1.sqlite")
        guard FileManager.default.fileExists(atPath: databaseURL.path),
              let database = openReadOnly(databaseURL)
        else { return nil }
        defer { sqlite3_close(database) }

        guard let projectedOffset = projectionOffset(database: database, sessionID: sessionID),
              projectedOffset > 0,
              let rows = turnRows(database: database, sessionID: sessionID),
              !rows.isEmpty
        else { return nil }

        let safeOffset = min(fileSize, projectedOffset)
        guard safeOffset > rows[0].start,
              let handle = try? FileHandle(forReadingFrom: file)
        else { return nil }
        defer { try? handle.close() }

        var result: CodexConversationUsageCheckpoint
        var firstRowToRead: Int

        if let previous,
           let previousTurnID = previous.currentTurnID,
           let previousIndex = rows.firstIndex(where: { $0.id == previousTurnID }) {
            result = previous
            result.processedOffset = min(previous.processedOffset, safeOffset)
            firstRowToRead = previousIndex
        } else {
            result = CodexConversationUsageCheckpoint()
            firstRowToRead = 0
        }

        if firstRowToRead > rows.count - 1 { return nil }

        for index in firstRowToRead..<rows.count {
            let row = rows[index]
            let nextStart = index + 1 < rows.count ? rows[index + 1].start : safeOffset
            let end = min(safeOffset, row.end ?? nextStart)
            guard row.start < end else { continue }

            let rangeReader = CodexRolloutTokenRangeReader()
            let firstEvent = rangeReader.firstTokenEvent(
                handle: handle,
                start: row.start,
                end: end
            )
            let lastEvent = rangeReader.lastTokenEvent(
                handle: handle,
                start: row.start,
                end: end
            )

            if index == firstRowToRead,
               let previous,
               previous.currentTurnID == row.id {
                if let lastEvent,
                   let current = result.currentCounterUsage,
                   lastEvent.usage.totalTokens >= current.totalTokens {
                    result.currentCounterUsage = lastEvent.usage
                }
                result.currentTurnID = row.id
                result.currentTurnOffset = row.start
                result.latestTokenTimestamp = lastEvent?.timestamp ?? result.latestTokenTimestamp
            } else {
                if let firstEvent,
                   let current = result.currentCounterUsage,
                   CodexConversationUsageIndex.startsNewCounterEpoch(
                       previous: current,
                       next: firstEvent.usage,
                       lastUsage: firstEvent.lastUsage
                   ) {
                    result.completedEpochUsage += current
                }
                result.currentCounterUsage = lastEvent?.usage ?? result.currentCounterUsage
                result.currentTurnID = row.id
                result.currentTurnOffset = row.start
                result.latestTokenTimestamp = lastEvent?.timestamp ?? result.latestTokenTimestamp
            }
        }

        result.processedOffset = safeOffset
        result.awaitingCounterAfterTurnStart = false
        return result
    }

    private func openReadOnly(_ url: URL) -> OpaquePointer? {
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(url.path, &database, flags, nil) == SQLITE_OK else {
            if let database { sqlite3_close(database) }
            return nil
        }
        return database
    }

    private func projectionOffset(database: OpaquePointer, sessionID: String) -> Int64? {
        var statement: OpaquePointer?
        let sql = "SELECT next_rollout_byte_offset FROM thread_history_projection_state WHERE thread_id = ? LIMIT 1"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else { return nil }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, sessionID, -1, sqliteTransient)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return sqlite3_column_int64(statement, 0)
    }

    private func turnRows(database: OpaquePointer, sessionID: String) -> [TurnRow]? {
        var statement: OpaquePointer?
        let sql = """
        SELECT turn_id, rollout_ordinal, rollout_byte_offset, rollout_end_byte_offset
        FROM thread_turns
        WHERE thread_id = ?
        ORDER BY rollout_ordinal
        """
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else { return nil }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, sessionID, -1, sqliteTransient)

        var rows: [TurnRow] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let idPointer = sqlite3_column_text(statement, 0) else { continue }
            let end: Int64? = sqlite3_column_type(statement, 3) == SQLITE_NULL
                ? nil
                : sqlite3_column_int64(statement, 3)
            rows.append(
                TurnRow(
                    id: String(cString: idPointer),
                    start: sqlite3_column_int64(statement, 2),
                    end: end
                )
            )
        }
        return rows
    }

}
