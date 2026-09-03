import SQLite3
import XCTest
@testable import CodexTokenLedger

final class CodexConversationUsageIndexTests: XCTestCase {
    func testIndexedCounterContinuesAcrossPaginatedTurns() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexConversationUsageIndex-\(UUID().uuidString)", isDirectory: true)
        let sessions = home.appendingPathComponent("sessions/2026/08/23", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let sessionID = "indexed-session"
        let file = sessions.appendingPathComponent("rollout-indexed-session.jsonl")
        var rollout = Data()
        append(
            #"{"timestamp":"2026-08-23T01:00:00.000Z","type":"session_meta","payload":{"id":"indexed-session"}}"#,
            to: &rollout
        )
        let firstStart = Int64(rollout.count)
        append(
            #"{"timestamp":"2026-08-23T01:00:01.000Z","type":"event_msg","payload":{"type":"task_started","turn_id":"turn-1"}}"#,
            to: &rollout
        )
        append(
            #"{"timestamp":"2026-08-23T01:00:02.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"output_tokens":10},"last_token_usage":{"input_tokens":100,"output_tokens":10}}}}"#,
            to: &rollout
        )
        let firstEnd = Int64(rollout.count)
        let secondStart = firstEnd
        append(
            #"{"timestamp":"2026-08-23T01:01:01.000Z","type":"event_msg","payload":{"type":"task_started","turn_id":"turn-2"}}"#,
            to: &rollout
        )
        append(
            #"{"timestamp":"2026-08-23T01:01:02.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":200,"output_tokens":20},"last_token_usage":{"input_tokens":100,"output_tokens":10}}}}"#,
            to: &rollout
        )
        try rollout.write(to: file)

        try createStateDatabase(at: home.appendingPathComponent("state_5.sqlite"), sessionID: sessionID)
        try createTurnDatabase(
            at: home.appendingPathComponent("thread_history_1.sqlite"),
            sessionID: sessionID,
            firstStart: firstStart,
            firstEnd: firstEnd,
            secondStart: secondStart,
            projectionOffset: Int64(rollout.count)
        )

        let checkpoint = CodexConversationUsageIndex().checkpoint(
            file: file,
            sessionID: sessionID,
            codexHome: home
        )

        XCTAssertEqual(checkpoint.completedEpochUsage.totalTokens, 0)
        XCTAssertEqual(checkpoint.currentCounterUsage?.totalTokens, 220)
        XCTAssertEqual(checkpoint.totalUsage.inputTokens, 200)
        XCTAssertEqual(checkpoint.totalUsage.outputTokens, 20)
        XCTAssertEqual(checkpoint.totalUsage.totalTokens, 220)
    }

    func testUnprojectedTurnContinuesTheExistingCounter() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexConversationUsageTail-\(UUID().uuidString)", isDirectory: true)
        let sessions = home.appendingPathComponent("sessions/2026/08/23", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let sessionID = "indexed-tail-session"
        let file = sessions.appendingPathComponent("rollout-indexed-tail-session.jsonl")
        var rollout = Data()
        append(
            #"{"timestamp":"2026-08-23T01:00:00.000Z","type":"session_meta","payload":{"id":"indexed-tail-session"}}"#,
            to: &rollout
        )
        let firstStart = Int64(rollout.count)
        append(
            #"{"timestamp":"2026-08-23T01:00:01.000Z","type":"event_msg","payload":{"type":"task_started","turn_id":"turn-1"}}"#,
            to: &rollout
        )
        append(
            #"{"timestamp":"2026-08-23T01:00:02.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"output_tokens":10},"last_token_usage":{"input_tokens":100,"output_tokens":10}}}}"#,
            to: &rollout
        )
        let projectionOffset = Int64(rollout.count)
        append(
            #"{"timestamp":"2026-08-23T01:01:01.000Z","type":"event_msg","payload":{"type":"task_started","turn_id":"turn-2"}}"#,
            to: &rollout
        )
        append(
            #"{"timestamp":"2026-08-23T01:01:02.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":200,"output_tokens":20},"last_token_usage":{"input_tokens":100,"output_tokens":10}}}}"#,
            to: &rollout
        )
        try rollout.write(to: file)

        try createStateDatabase(at: home.appendingPathComponent("state_5.sqlite"), sessionID: sessionID)
        try createTurnDatabase(
            at: home.appendingPathComponent("thread_history_1.sqlite"),
            sessionID: sessionID,
            rows: [("turn-1", firstStart, projectionOffset)],
            projectionOffset: projectionOffset
        )

        let checkpoint = CodexConversationUsageIndex().checkpoint(
            file: file,
            sessionID: sessionID,
            codexHome: home
        )

        XCTAssertEqual(checkpoint.completedEpochUsage.totalTokens, 0)
        XCTAssertEqual(checkpoint.currentCounterUsage?.totalTokens, 220)
        XCTAssertEqual(checkpoint.totalUsage.totalTokens, 220)
    }

    func testIndexedCounterAddsOnlyARealResetEvenWhenTheNewTurnLaterGrowsLarger() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexConversationUsageReset-\(UUID().uuidString)", isDirectory: true)
        let sessions = home.appendingPathComponent("sessions/2026/08/23", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let sessionID = "indexed-reset-session"
        let file = sessions.appendingPathComponent("rollout-indexed-reset-session.jsonl")
        var rollout = Data()
        append(
            #"{"timestamp":"2026-08-23T01:00:00.000Z","type":"session_meta","payload":{"id":"indexed-reset-session"}}"#,
            to: &rollout
        )
        let firstStart = Int64(rollout.count)
        append(
            #"{"timestamp":"2026-08-23T01:00:01.000Z","type":"event_msg","payload":{"type":"task_started","turn_id":"turn-1"}}"#,
            to: &rollout
        )
        append(
            #"{"timestamp":"2026-08-23T01:00:02.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"output_tokens":10},"last_token_usage":{"input_tokens":100,"output_tokens":10}}}}"#,
            to: &rollout
        )
        let firstEnd = Int64(rollout.count)
        let secondStart = firstEnd
        append(
            #"{"timestamp":"2026-08-23T01:01:01.000Z","type":"event_msg","payload":{"type":"task_started","turn_id":"turn-2"}}"#,
            to: &rollout
        )
        append(
            #"{"timestamp":"2026-08-23T01:01:02.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":8,"output_tokens":2},"last_token_usage":{"input_tokens":8,"output_tokens":2}}}}"#,
            to: &rollout
        )
        append(
            #"{"timestamp":"2026-08-23T01:01:03.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":200,"output_tokens":20},"last_token_usage":{"input_tokens":192,"output_tokens":18}}}}"#,
            to: &rollout
        )
        try rollout.write(to: file)

        try createStateDatabase(at: home.appendingPathComponent("state_5.sqlite"), sessionID: sessionID)
        try createTurnDatabase(
            at: home.appendingPathComponent("thread_history_1.sqlite"),
            sessionID: sessionID,
            firstStart: firstStart,
            firstEnd: firstEnd,
            secondStart: secondStart,
            projectionOffset: Int64(rollout.count)
        )

        let checkpoint = CodexConversationUsageIndex().checkpoint(
            file: file,
            sessionID: sessionID,
            codexHome: home
        )

        XCTAssertEqual(checkpoint.completedEpochUsage.totalTokens, 110)
        XCTAssertEqual(checkpoint.currentCounterUsage?.totalTokens, 220)
        XCTAssertEqual(checkpoint.totalUsage.totalTokens, 330)
    }

    private func append(_ line: String, to data: inout Data) {
        data.append(Data((line + "\n").utf8))
    }

    private func createStateDatabase(at url: URL, sessionID: String) throws {
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &database), SQLITE_OK)
        guard let database else { throw CocoaError(.fileWriteUnknown) }
        defer { sqlite3_close(database) }
        try execute(
            """
            CREATE TABLE threads (id TEXT PRIMARY KEY, history_mode TEXT NOT NULL);
            INSERT INTO threads (id, history_mode) VALUES ('\(sessionID)', 'paginated');
            """,
            database: database
        )
    }

    private func createTurnDatabase(
        at url: URL,
        sessionID: String,
        firstStart: Int64,
        firstEnd: Int64,
        secondStart: Int64,
        projectionOffset: Int64
    ) throws {
        try createTurnDatabase(
            at: url,
            sessionID: sessionID,
            rows: [
                ("turn-1", firstStart, firstEnd),
                ("turn-2", secondStart, nil),
            ],
            projectionOffset: projectionOffset
        )
    }

    private func createTurnDatabase(
        at url: URL,
        sessionID: String,
        rows: [(id: String, start: Int64, end: Int64?)],
        projectionOffset: Int64
    ) throws {
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &database), SQLITE_OK)
        guard let database else { throw CocoaError(.fileWriteUnknown) }
        defer { sqlite3_close(database) }
        try execute(
            """
            CREATE TABLE thread_turns (
                thread_id TEXT NOT NULL,
                turn_id TEXT NOT NULL,
                rollout_ordinal INTEGER NOT NULL,
                rollout_byte_offset INTEGER NOT NULL,
                rollout_end_byte_offset INTEGER
            );
            CREATE TABLE thread_history_projection_state (
                thread_id TEXT PRIMARY KEY,
                next_rollout_byte_offset INTEGER NOT NULL,
                next_rollout_ordinal INTEGER NOT NULL
            );
            """,
            database: database
        )
        for (ordinal, row) in rows.enumerated() {
            let end = row.end.map(String.init) ?? "NULL"
            try execute(
                "INSERT INTO thread_turns VALUES ('\(sessionID)', '\(row.id)', \(ordinal + 1), \(row.start), \(end));",
                database: database
            )
        }
        try execute(
            "INSERT INTO thread_history_projection_state VALUES ('\(sessionID)', \(projectionOffset), \(rows.count + 1));",
            database: database
        )
    }

    private func execute(_ sql: String, database: OpaquePointer) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(database, sql, nil, nil, &errorMessage)
        defer { sqlite3_free(errorMessage) }
        guard result == SQLITE_OK else {
            let message = errorMessage.map { String(cString: UnsafePointer($0)) } ?? "SQLite error \(result)"
            throw NSError(domain: "CodexConversationUsageIndexTests", code: Int(result), userInfo: [
                NSLocalizedDescriptionKey: message,
            ])
        }
    }
}
