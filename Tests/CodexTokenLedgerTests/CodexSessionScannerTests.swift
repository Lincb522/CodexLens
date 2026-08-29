import Foundation
import XCTest
@testable import CodexTokenLedger

final class CodexSessionScannerTests: XCTestCase {
    func testScannerPreservesAuthoritativeTotalWhenOldEventHasNoBreakdown() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexTokenLedgerTotalOnly-\(UUID().uuidString)", isDirectory: true)
        let sessions = root.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let fixture = #"""
        {"timestamp":"2026-08-23T01:00:00.000Z","type":"session_meta","payload":{"id":"total-only"}}
        {"timestamp":"2026-08-23T01:00:01.000Z","type":"turn_context","payload":{"model":"gpt-5.6-sol"}}
        {"timestamp":"2026-08-23T01:00:02.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":0,"cached_input_tokens":0,"output_tokens":0,"reasoning_output_tokens":0,"total_tokens":9657}}}}
        """#
        try fixture.write(to: sessions.appendingPathComponent("old.jsonl"), atomically: true, encoding: .utf8)

        let snapshot = try CodexSessionScanner().scan(codexHome: root, includeArchived: false)

        XCTAssertEqual(snapshot.totalUsage.totalTokens, 9_657)
        XCTAssertFalse(snapshot.totalUsage.hasCompleteBreakdown)
        XCTAssertFalse(BillingCalculator.total(records: snapshot.records).isPriced)
    }

    func testScannerUsesLastCumulativeCounterAsFastExactSessionTotal() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexTokenLedgerCumulative-\(UUID().uuidString)", isDirectory: true)
        let sessions = root.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let fixture = #"""
        {"timestamp":"2026-08-23T01:00:00.000Z","type":"session_meta","payload":{"id":"cumulative","cwd":"/tmp/fast"}}
        {"timestamp":"2026-08-23T01:00:01.000Z","type":"turn_context","payload":{"model":"gpt-5.6-sol","effort":"high"}}
        {"timestamp":"2026-08-23T01:00:02.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":50,"cache_write_input_tokens":0,"output_tokens":10,"reasoning_output_tokens":3},"last_token_usage":{"input_tokens":100,"cached_input_tokens":50,"output_tokens":10}}}}
        {"timestamp":"2026-08-23T01:00:03.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":300,"cached_input_tokens":150,"cache_write_input_tokens":0,"output_tokens":30,"reasoning_output_tokens":7},"last_token_usage":{"input_tokens":200,"cached_input_tokens":100,"output_tokens":20}}}}
        """#
        try fixture.write(to: sessions.appendingPathComponent("fast.jsonl"), atomically: true, encoding: .utf8)

        let snapshot = try CodexSessionScanner().scan(codexHome: root, includeArchived: false)

        XCTAssertEqual(snapshot.records.count, 1)
        XCTAssertEqual(snapshot.sessions.count, 1)
        XCTAssertEqual(snapshot.totalUsage.inputTokens, 300)
        XCTAssertEqual(snapshot.totalUsage.cachedInputTokens, 150)
        XCTAssertEqual(snapshot.totalUsage.outputTokens, 30)
        XCTAssertEqual(snapshot.totalUsage.reasoningOutputTokens, 7)
        XCTAssertEqual(snapshot.sessions.first?.latestModel, "gpt-5.6-sol")
        XCTAssertEqual(snapshot.sessions.first?.projectName, "fast")
    }

    func testQuotaCycleUsageReplaysCallsForASessionThatCrossesTheResetBoundary() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexTokenLedgerQuotaCycle-\(UUID().uuidString)", isDirectory: true)
        let sessions = root.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let fixture = #"""
        {"timestamp":"2026-08-23T00:00:00.000Z","type":"session_meta","payload":{"id":"crossing"}}
        {"timestamp":"2026-08-23T00:00:01.000Z","type":"turn_context","payload":{"model":"gpt-5.6-sol"}}
        {"timestamp":"2026-08-23T00:30:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":900,"cached_input_tokens":0,"output_tokens":100},"last_token_usage":{"input_tokens":900,"cached_input_tokens":0,"output_tokens":100}}}}
        {"timestamp":"2026-08-23T01:30:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1440,"cached_input_tokens":0,"output_tokens":160},"last_token_usage":{"input_tokens":540,"cached_input_tokens":0,"output_tokens":60}}}}
        {"timestamp":"2026-08-23T02:30:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1800,"cached_input_tokens":0,"output_tokens":200},"last_token_usage":{"input_tokens":360,"cached_input_tokens":0,"output_tokens":40}}}}
        """#
        let file = sessions.appendingPathComponent("crossing.jsonl")
        try fixture.write(to: file, atomically: true, encoding: .utf8)

        let scanner = CodexSessionScanner()
        let snapshot = try scanner.scan(codexHome: root, includeArchived: false)
        let cycleStart = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-23T01:00:00Z"))
        let observedAt = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-23T03:00:00Z"))
        let usage = try XCTUnwrap(scanner.quotaCycleUsage(
            snapshot: snapshot,
            window: CodexQuotaWindow(
                id: "weekly",
                title: "Weekly",
                usedPercent: 40,
                windowMinutes: 10_080,
                resetsAt: cycleStart.addingTimeInterval(7 * 24 * 3_600)
            ),
            observedAt: observedAt
        ))

        XCTAssertEqual(snapshot.totalUsage.totalTokens, 2_000)
        XCTAssertEqual(usage.totalTokens, 1_000)
        XCTAssertEqual(usage.sessionCount, 1)

        let laterEvent = #"{"timestamp":"2026-08-23T03:30:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":2250,"cached_input_tokens":0,"output_tokens":250},"last_token_usage":{"input_tokens":450,"cached_input_tokens":0,"output_tokens":50}}}}"#
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(("\n" + laterEvent).utf8))
        try handle.close()
        let updatedSnapshot = try scanner.scan(codexHome: root, includeArchived: false)
        try FileManager.default.removeItem(at: file)
        let advanced = try XCTUnwrap(scanner.quotaCycleUsage(
            snapshot: updatedSnapshot,
            window: CodexQuotaWindow(
                id: "weekly",
                title: "Weekly",
                usedPercent: 50,
                windowMinutes: 10_080,
                resetsAt: cycleStart.addingTimeInterval(7 * 24 * 3_600)
            ),
            observedAt: try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-23T04:00:00Z")),
            previous: usage
        ))
        XCTAssertEqual(advanced.totalTokens, 1_500)
    }

    func testScannerReadsIncrementalTokenEventsAndIgnoresMessageBodies() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexTokenLedgerTests-\(UUID().uuidString)", isDirectory: true)
        let sessions = root.appendingPathComponent("sessions/2026/08/23", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let fixture = [
            #"{"timestamp":"2026-08-23T01:00:00.000Z","type":"session_meta","payload":{"id":"session-1","cwd":"/tmp/demo","timestamp":"2026-08-23T01:00:00.000Z"}}"#,
            #"{"timestamp":"2026-08-23T01:00:01.000Z","type":"turn_context","payload":{"model":"gpt-5.6-terra","effort":"high","cwd":"/tmp/demo"}}"#,
            #"{"timestamp":"2026-08-23T01:00:02.000Z","type":"event_msg","payload":{"type":"user_message","message":"THIS MUST NEVER BE STORED"}}"#,
            #"{"timestamp":"2026-08-23T01:00:03.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":1000,"cached_input_tokens":600,"cache_write_input_tokens":0,"output_tokens":200,"reasoning_output_tokens":50,"total_tokens":1200}}}}"#,
            #"{"timestamp":"2026-08-23T01:00:04.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":500,"cached_input_tokens":0,"cache_write_input_tokens":0,"output_tokens":100,"reasoning_output_tokens":0,"total_tokens":600}}}}"#,
            #"{"type":"token_count",broken}"#
        ].joined(separator: "\n")
        let file = sessions.appendingPathComponent("rollout-test.jsonl")
        try fixture.write(to: file, atomically: true, encoding: .utf8)

        let snapshot = try CodexSessionScanner().scan(codexHome: root, includeArchived: false)

        XCTAssertEqual(snapshot.fileCount, 1)
        XCTAssertEqual(snapshot.records.count, 2)
        XCTAssertEqual(snapshot.sessions.count, 1)
        XCTAssertEqual(snapshot.totalUsage.inputTokens, 1_500)
        XCTAssertEqual(snapshot.totalUsage.cachedInputTokens, 600)
        XCTAssertEqual(snapshot.totalUsage.outputTokens, 300)
        XCTAssertEqual(snapshot.totalUsage.reasoningOutputTokens, 50)
        XCTAssertEqual(snapshot.sessions.first?.latestModel, "gpt-5.6-terra")
        XCTAssertEqual(snapshot.sessions.first?.projectName, "demo")
        XCTAssertEqual(snapshot.issues.count, 1)

        let encoded = try JSONEncoder().encode(snapshot)
        XCTAssertNil(String(data: encoded, encoding: .utf8)?.range(of: "THIS MUST NEVER BE STORED"))
    }

    func testScannerDeduplicatesSameArchivedAndActiveEvent() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexTokenLedgerDedup-\(UUID().uuidString)", isDirectory: true)
        let active = root.appendingPathComponent("sessions", isDirectory: true)
        let archived = root.appendingPathComponent("archived_sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: active, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: archived, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let event = #"""
        {"timestamp":"2026-08-23T01:00:00.000Z","type":"session_meta","payload":{"id":"same","cwd":"/tmp/demo"}}
        {"timestamp":"2026-08-23T01:00:01.000Z","type":"turn_context","payload":{"model":"gpt-5.6-luna"}}
        {"timestamp":"2026-08-23T01:00:02.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"cached_input_tokens":0,"output_tokens":10,"reasoning_output_tokens":0}}}}
        """#
        try event.write(to: active.appendingPathComponent("a.jsonl"), atomically: true, encoding: .utf8)
        try event.write(to: archived.appendingPathComponent("b.jsonl"), atomically: true, encoding: .utf8)

        let snapshot = try CodexSessionScanner().scan(codexHome: root, includeArchived: true)
        XCTAssertEqual(snapshot.records.count, 1)
        XCTAssertEqual(snapshot.totalUsage.totalTokens, 110)
    }

    func testScannerPrefersNewerActiveCumulativeTotalOverArchivedCopy() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexTokenLedgerRolloutCopies-\(UUID().uuidString)", isDirectory: true)
        let active = root.appendingPathComponent("sessions", isDirectory: true)
        let archived = root.appendingPathComponent("archived_sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: active, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: archived, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let archivedFixture = cumulativeFixture(
            sessionID: "same-cumulative",
            timestamp: "2026-08-23T01:00:02.000Z",
            input: 100,
            output: 10
        )
        let activeFixture = cumulativeFixture(
            sessionID: "same-cumulative",
            timestamp: "2026-08-23T01:00:04.000Z",
            input: 300,
            output: 30
        )
        try archivedFixture.write(
            to: archived.appendingPathComponent("archived.jsonl"),
            atomically: true,
            encoding: .utf8
        )
        try activeFixture.write(
            to: active.appendingPathComponent("active.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let snapshot = try CodexSessionScanner().scan(codexHome: root, includeArchived: true)

        XCTAssertEqual(snapshot.records.count, 1)
        XCTAssertEqual(snapshot.totalUsage.totalTokens, 330)
        XCTAssertTrue(snapshot.records.first?.sourcePath.hasSuffix("/sessions/active.jsonl") == true)
    }

    func testCumulativeSummarySupersedesOlderDetailedEventsForSameSession() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexTokenLedgerMixedCounters-\(UUID().uuidString)", isDirectory: true)
        let sessions = root.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let detailed = #"""
        {"timestamp":"2026-08-23T01:00:00.000Z","type":"session_meta","payload":{"id":"mixed"}}
        {"timestamp":"2026-08-23T01:00:01.000Z","type":"turn_context","payload":{"model":"gpt-5.6-sol"}}
        {"timestamp":"2026-08-23T01:00:02.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"cached_input_tokens":0,"output_tokens":10}}}}
        """#
        try detailed.write(
            to: sessions.appendingPathComponent("legacy.jsonl"),
            atomically: true,
            encoding: .utf8
        )
        try cumulativeFixture(
            sessionID: "mixed",
            timestamp: "2026-08-23T01:00:04.000Z",
            input: 300,
            output: 30
        ).write(
            to: sessions.appendingPathComponent("modern.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let snapshot = try CodexSessionScanner().scan(codexHome: root, includeArchived: false)

        XCTAssertEqual(snapshot.records.count, 1)
        XCTAssertTrue(snapshot.records[0].isCumulativeSessionSummary)
        XCTAssertEqual(snapshot.totalUsage.totalTokens, 330)
    }

    func testIncrementalCacheIsReusableAndInvalidatesWhenFileGrows() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexTokenLedgerCache-\(UUID().uuidString)", isDirectory: true)
        let sessions = root.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let file = sessions.appendingPathComponent("cache.jsonl")
        let header = #"""
        {"timestamp":"2026-08-23T01:00:00.000Z","type":"session_meta","payload":{"id":"cached"}}
        {"timestamp":"2026-08-23T01:00:01.000Z","type":"turn_context","payload":{"model":"gpt-5.6-luna"}}
        {"timestamp":"2026-08-23T01:00:02.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"cached_input_tokens":0,"output_tokens":10}}}}
        """#
        try header.write(to: file, atomically: true, encoding: .utf8)

        let scanner = CodexSessionScanner()
        let first = try scanner.scanWithCache(codexHome: root, includeArchived: false, cache: nil)
        let reused = try scanner.scanWithCache(codexHome: root, includeArchived: false, cache: first.cache)
        XCTAssertEqual(reused.snapshot.records.count, 1)

        let appended = #"""

        {"timestamp":"2026-08-23T01:00:03.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":200,"cached_input_tokens":100,"output_tokens":20}}}}
        """#
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(appended.utf8))
        try handle.close()

        let refreshed = try scanner.scanWithCache(codexHome: root, includeArchived: false, cache: reused.cache)
        XCTAssertEqual(refreshed.snapshot.records.count, 2)
        XCTAssertEqual(refreshed.snapshot.totalUsage.totalTokens, 330)
    }

    private func cumulativeFixture(
        sessionID: String,
        timestamp: String,
        input: Int64,
        output: Int64
    ) -> String {
        #"""
        {"timestamp":"2026-08-23T01:00:00.000Z","type":"session_meta","payload":{"id":"\#(sessionID)"}}
        {"timestamp":"2026-08-23T01:00:01.000Z","type":"turn_context","payload":{"model":"gpt-5.6-sol"}}
        {"timestamp":"\#(timestamp)","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":\#(input),"cached_input_tokens":0,"cache_write_input_tokens":0,"output_tokens":\#(output),"reasoning_output_tokens":0},"last_token_usage":{"input_tokens":\#(input),"cached_input_tokens":0,"output_tokens":\#(output)}}}}
        """#
    }
}
