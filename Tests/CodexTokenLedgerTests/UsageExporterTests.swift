import XCTest
@testable import CodexTokenLedger

final class UsageExporterTests: XCTestCase {
    func testGPT6AstraExportIncludesItsAPIEstimate() throws {
        let record = UsageRecord(id: "astra", timestamp: .distantPast, sessionID: "astra",
                                 sourcePath: "/tmp/astra.jsonl", projectPath: nil,
                                 model: "gpt-6-astra", reasoningEffort: nil,
                                 usage: TokenUsage(inputTokens: 1_000, cachedInputTokens: 400, outputTokens: 100))
        let csv = try XCTUnwrap(String(data: UsageExporter.csv(records: [record]), encoding: .utf8))
        XCTAssertTrue(csv.contains("\"gpt-6-astra\""))
        XCTAssertTrue(csv.contains(",0.0114,official_api_rate_estimate\n"))
        XCTAssertFalse(csv.contains(",unavailable\n"))
    }

    func testCSVLabelsAPICostAsEstimateAndLeavesUnknownModelsUnavailable() throws {
        let records = [
            UsageRecord(
                id: "priced",
                timestamp: Date(timeIntervalSince1970: 0),
                sessionID: "one",
                sourcePath: "/tmp/one.jsonl",
                projectPath: nil,
                model: "gpt-5.6-sol",
                reasoningEffort: nil,
                usage: TokenUsage(inputTokens: 1_000, outputTokens: 100)
            ),
            UsageRecord(
                id: "unavailable",
                timestamp: Date(timeIntervalSince1970: 1),
                sessionID: "two",
                sourcePath: "/tmp/two.jsonl",
                projectPath: nil,
                model: "unpublished-model",
                reasoningEffort: nil,
                usage: TokenUsage(inputTokens: 2_000, outputTokens: 200)
            ),
        ]

        let csv = try XCTUnwrap(String(data: UsageExporter.csv(records: records), encoding: .utf8))
        XCTAssertTrue(csv.contains("api_equivalent_usd_estimate,api_pricing_evidence"))
        XCTAssertTrue(csv.contains("official_api_rate_estimate"))
        XCTAssertTrue(csv.contains(",,unavailable\n"))
        XCTAssertFalse(csv.contains("estimated_credits"))
    }
}
