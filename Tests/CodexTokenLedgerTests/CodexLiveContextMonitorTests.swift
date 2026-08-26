import XCTest
@testable import CodexTokenLedger

final class CodexLiveContextMonitorTests: XCTestCase {
    func testReusesExactSnapshotForIrrelevantAppendsAndReparsesAccountingEvents() async throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexTokenLedger-monitor-\(UUID().uuidString)", isDirectory: true)
        let sessions = home.appendingPathComponent("sessions/2026/08/25", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let file = sessions.appendingPathComponent("live.jsonl")

        let fixture = #"""
        {"timestamp":"2026-08-25T01:00:00.000Z","type":"session_meta","payload":{"id":"thread-monitor","cwd":"/Projects/Monitor"}}
        {"timestamp":"2026-08-25T01:00:01.000Z","type":"event_msg","payload":{"type":"task_started","turn_id":"turn-monitor","model_context_window":258400}}
        {"timestamp":"2026-08-25T01:00:02.000Z","type":"turn_context","payload":{"turn_id":"turn-monitor","cwd":"/Projects/Monitor","model":"gpt-5.6-sol","effort":"high"}}
        {"timestamp":"2026-08-25T01:00:03.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1000,"cached_input_tokens":800,"output_tokens":100},"last_token_usage":{"input_tokens":600,"cached_input_tokens":500,"output_tokens":50},"model_context_window":258400}}}
        """#
        try fixture.write(to: file, atomically: true, encoding: .utf8)

        let monitor = CodexLiveContextMonitor()
        let first = try await monitor.readContexts(
            codexHome: home,
            preferredSourcePaths: [],
            maximumResults: 8,
            discover: true
        )
        let initial = try XCTUnwrap(first.first)
        XCTAssertEqual(initial.lastRequest.inputTokens, 600)
        let initialParseCount = await monitor.fullParseCountForTesting()
        XCTAssertEqual(initialParseCount, 1)

        try append(
            #"{"timestamp":"2026-08-25T01:00:04.000Z","type":"response_item","payload":{"type":"message","text":"not accounting"}}"#,
            to: file
        )
        let unchanged = try await monitor.readContexts(
            codexHome: home,
            preferredSourcePaths: [file.path],
            maximumResults: 8,
            discover: false
        )
        XCTAssertEqual(unchanged.first, initial)
        let irrelevantAppendParseCount = await monitor.fullParseCountForTesting()
        XCTAssertEqual(irrelevantAppendParseCount, 1)

        try append(
            #"{"timestamp":"2026-08-25T01:00:05.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1200,"cached_input_tokens":900,"output_tokens":130},"last_token_usage":{"input_tokens":200,"cached_input_tokens":100,"output_tokens":30},"model_context_window":258400}}}"#,
            to: file
        )
        let changed = try await monitor.readContexts(
            codexHome: home,
            preferredSourcePaths: [file.path],
            maximumResults: 8,
            discover: false
        )
        XCTAssertEqual(changed.first?.lastRequest.inputTokens, 200)
        XCTAssertEqual(changed.first?.taskTotal.inputTokens, 1_200)
        let accountingAppendParseCount = await monitor.fullParseCountForTesting()
        XCTAssertEqual(accountingAppendParseCount, 2)
    }

    private func append(_ line: String, to file: URL) throws {
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(("\n" + line + "\n").utf8))
    }
}
