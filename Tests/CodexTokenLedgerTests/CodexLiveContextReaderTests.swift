import XCTest
@testable import CodexTokenLedger

final class CodexLiveContextReaderTests: XCTestCase {
    func testReadsLatestUpstreamTokenEventAsLiveContext() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexTokenLedger-live-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("rollout-fixture.jsonl")

        let lines: [[String: Any]] = [
            [
                "timestamp": "2026-08-24T01:00:00.000Z",
                "type": "session_meta",
                "payload": ["id": "thread-live", "cwd": "/Projects/ContextMeter"],
            ],
            [
                "timestamp": "2026-08-24T01:00:01.000Z",
                "type": "turn_context",
                "payload": [
                    "cwd": "/Projects/ContextMeter",
                    "model": "gpt-5.6-sol",
                    "effort": "xhigh",
                ],
            ],
            [
                "timestamp": "2026-08-24T01:00:02.000Z",
                "type": "event_msg",
                "payload": [
                    "type": "token_count",
                    "info": [
                        "total_token_usage": [
                            "input_tokens": 1_000,
                            "cached_input_tokens": 800,
                            "output_tokens": 200,
                            "reasoning_output_tokens": 50,
                            "total_tokens": 1_200,
                        ],
                        "last_token_usage": [
                            "input_tokens": 600,
                            "cached_input_tokens": 500,
                            "output_tokens": 100,
                            "reasoning_output_tokens": 40,
                            "total_tokens": 700,
                        ],
                        "model_context_window": 1_000,
                    ],
                ],
            ],
        ]
        let data = try lines.map { object -> Data in
            var value = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            value.append(0x0A)
            return value
        }.reduce(into: Data()) { $0.append($1) }
        try data.write(to: file)

        let snapshot = try XCTUnwrap(CodexLiveContextReader().read(file: file))

        XCTAssertEqual(snapshot.id, "thread-live")
        XCTAssertEqual(snapshot.projectName, "ContextMeter")
        XCTAssertEqual(snapshot.model, "gpt-5.6-sol")
        XCTAssertEqual(snapshot.reasoningEffort, "xhigh")
        XCTAssertEqual(snapshot.lastRequest.inputTokens, 600)
        XCTAssertEqual(snapshot.lastRequest.cachedInputTokens, 500)
        XCTAssertEqual(snapshot.lastRequest.outputTokens, 100)
        XCTAssertEqual(snapshot.lastRequest.reasoningOutputTokens, 40)
        XCTAssertEqual(snapshot.contextTokens, 700)
        XCTAssertEqual(snapshot.contextInputTokens, 600)
        XCTAssertEqual(snapshot.modelContextWindow, 1_000)
        XCTAssertEqual(snapshot.publishedContextWindow, 1_050_000)
        XCTAssertEqual(snapshot.contextCapacityWindow, 1_050_000)
        XCTAssertEqual(try XCTUnwrap(snapshot.contextUsedPercent), 600.0 / 1_050_000.0 * 100, accuracy: 0.000_001)
        XCTAssertEqual(snapshot.contextRemainingTokens, 1_049_400)
        XCTAssertTrue(snapshot.runtimeWindowDiffersFromPublished)
        XCTAssertEqual(snapshot.taskTotal.totalTokens, 1_200)
        XCTAssertEqual(snapshot.currentTurnUsage.totalTokens, 700)
        XCTAssertEqual(snapshot.currentTurnCalls.count, 1)
    }

    func testAggregatesLatestTurnFromCumulativeDeltasAndIgnoresDuplicates() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexTokenLedger-turn-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("rollout-turn.jsonl")

        let fixture = #"""
        {"timestamp":"2026-08-24T01:00:00.000Z","type":"session_meta","payload":{"id":"thread-turn","cwd":"/Projects/TokenPulse"}}
        {"timestamp":"2026-08-24T01:00:01.000Z","type":"turn_context","payload":{"turn_id":"old-turn","cwd":"/Projects/TokenPulse","model":"gpt-5.6-sol","effort":"high"}}
        {"timestamp":"2026-08-24T01:00:02.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":50,"output_tokens":10,"reasoning_output_tokens":2},"last_token_usage":{"input_tokens":100,"cached_input_tokens":50,"output_tokens":10,"reasoning_output_tokens":2},"model_context_window":1000}}}
        {"timestamp":"2026-08-24T01:01:00.000Z","type":"event_msg","payload":{"type":"task_started","turn_id":"current-turn","model_context_window":1000}}
        {"timestamp":"2026-08-24T01:01:01.000Z","type":"turn_context","payload":{"turn_id":"current-turn","cwd":"/Projects/TokenPulse","model":"gpt-5.6-sol","effort":"xhigh"}}
        {"timestamp":"2026-08-24T01:01:02.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":300,"cached_input_tokens":170,"output_tokens":30,"reasoning_output_tokens":8},"last_token_usage":{"input_tokens":200,"cached_input_tokens":120,"output_tokens":20,"reasoning_output_tokens":6},"model_context_window":1000}}}
        {"timestamp":"2026-08-24T01:01:02.100Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":300,"cached_input_tokens":170,"output_tokens":30,"reasoning_output_tokens":8},"last_token_usage":{"input_tokens":200,"cached_input_tokens":120,"output_tokens":20,"reasoning_output_tokens":6},"model_context_window":1000}}}
        {"timestamp":"2026-08-24T01:01:02.500Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":250,"cached_input_tokens":140,"output_tokens":25,"reasoning_output_tokens":7},"last_token_usage":{"input_tokens":50,"cached_input_tokens":30,"output_tokens":5,"reasoning_output_tokens":1},"model_context_window":1000}}}
        {"timestamp":"2026-08-24T01:01:03.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":450,"cached_input_tokens":260,"output_tokens":50,"reasoning_output_tokens":12},"last_token_usage":{"input_tokens":150,"cached_input_tokens":90,"output_tokens":20,"reasoning_output_tokens":4},"model_context_window":1000}}}
        """#
        try fixture.write(to: file, atomically: true, encoding: .utf8)

        let snapshot = try XCTUnwrap(CodexLiveContextReader().read(file: file))

        XCTAssertEqual(snapshot.turnID, "current-turn")
        XCTAssertEqual(snapshot.currentTurnCalls.count, 2)
        XCTAssertEqual(snapshot.duplicateEventsIgnored, 2)
        XCTAssertEqual(snapshot.currentTurnUsage.inputTokens, 350)
        XCTAssertEqual(snapshot.currentTurnUsage.cachedInputTokens, 210)
        XCTAssertEqual(snapshot.currentTurnUsage.outputTokens, 40)
        XCTAssertEqual(snapshot.currentTurnUsage.reasoningOutputTokens, 10)
        XCTAssertEqual(snapshot.lastRequest.totalTokens, 170)
        XCTAssertEqual(snapshot.modelContextWindow, 1_000)
        XCTAssertEqual(snapshot.publishedContextWindow, 1_050_000)
        XCTAssertEqual(try XCTUnwrap(snapshot.contextUsedPercent), 150.0 / 1_050_000.0 * 100, accuracy: 0.000_001)
        XCTAssertEqual(snapshot.taskTotal.totalTokens, 500)
    }

    func testDuplicateCounterCanCorrectLatestBreakdownWithoutAddingTokens() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexTokenLedger-counter-correction-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("rollout.jsonl")
        let fixture = #"""
        {"timestamp":"2026-08-24T01:00:00.000Z","type":"session_meta","payload":{"id":"corrected"}}
        {"timestamp":"2026-08-24T01:00:01.000Z","type":"event_msg","payload":{"type":"task_started","turn_id":"turn"}}
        {"timestamp":"2026-08-24T01:00:02.000Z","type":"turn_context","payload":{"model":"gpt-5.6-sol"}}
        {"timestamp":"2026-08-24T01:00:03.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":200,"cached_input_tokens":100,"output_tokens":20},"last_token_usage":{"input_tokens":200,"cached_input_tokens":100,"output_tokens":20}}}}
        {"timestamp":"2026-08-24T01:00:04.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":200,"cached_input_tokens":120,"output_tokens":20},"last_token_usage":{"input_tokens":200,"cached_input_tokens":120,"output_tokens":20}}}}
        """#
        try fixture.write(to: file, atomically: true, encoding: .utf8)

        let snapshot = try XCTUnwrap(CodexLiveContextReader().read(file: file))

        XCTAssertEqual(snapshot.duplicateEventsIgnored, 1)
        XCTAssertEqual(snapshot.currentTurnCalls.count, 1)
        XCTAssertEqual(snapshot.currentTurnUsage.totalTokens, 220)
        XCTAssertEqual(snapshot.currentTurnUsage.cachedInputTokens, 120)
        XCTAssertEqual(snapshot.lastRequest.cachedInputTokens, 120)
    }

    func testDiscoversMultipleUnfinishedTasksAndExcludesCompletedTask() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexTokenLedger-multi-live-\(UUID().uuidString)", isDirectory: true)
        let sessions = home.appendingPathComponent("sessions/2026/08/24", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        func fixture(id: String, minute: Int, completed: Bool) -> String {
            let finish = completed
                ? "\n{\"timestamp\":\"2026-08-24T01:\(String(format: "%02d", minute)):04.000Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"task_complete\"}}"
                : ""
            return """
            {"timestamp":"2026-08-24T01:\(String(format: "%02d", minute)):00.000Z","type":"session_meta","payload":{"id":"\(id)","cwd":"/Projects/\(id)"}}
            {"timestamp":"2026-08-24T01:\(String(format: "%02d", minute)):01.000Z","type":"event_msg","payload":{"type":"task_started","turn_id":"turn-\(id)","model_context_window":258400}}
            {"timestamp":"2026-08-24T01:\(String(format: "%02d", minute)):02.000Z","type":"turn_context","payload":{"turn_id":"turn-\(id)","cwd":"/Projects/\(id)","model":"gpt-5.6-sol","effort":"high"}}
            {"timestamp":"2026-08-24T01:\(String(format: "%02d", minute)):03.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1000,"cached_input_tokens":800,"output_tokens":100},"last_token_usage":{"input_tokens":600,"cached_input_tokens":500,"output_tokens":50},"model_context_window":258400}}}\(finish)
            """
        }

        try fixture(id: "active-one", minute: 10, completed: false)
            .write(to: sessions.appendingPathComponent("one.jsonl"), atomically: true, encoding: .utf8)
        try fixture(id: "active-two", minute: 11, completed: false)
            .write(to: sessions.appendingPathComponent("two.jsonl"), atomically: true, encoding: .utf8)
        try fixture(id: "completed", minute: 12, completed: true)
            .write(to: sessions.appendingPathComponent("done.jsonl"), atomically: true, encoding: .utf8)

        let contexts = try CodexLiveContextReader().readActiveContexts(codexHome: home)

        XCTAssertEqual(Set(contexts.map(\.id)), ["active-one", "active-two"])
        XCTAssertTrue(contexts.allSatisfy(\.isTaskActive))

        let limited = try CodexLiveContextReader().readActiveContexts(codexHome: home, maximumResults: 1)
        XCTAssertEqual(limited.count, 1)
    }
}
