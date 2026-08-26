import XCTest
@testable import CodexTokenLedger

final class CodexAccountServiceTests: XCTestCase {
    func testParsesAccountScopedQuotaWindowsAndCredits() throws {
        let account: [String: Any] = [
            "account": [
                "type": "chatgpt",
                "email": "person@example.com",
                "planType": "pro",
            ],
            "requiresOpenaiAuth": true,
        ]
        let limits: [String: Any] = [
            "rateLimits": [
                "planType": "pro",
                "primary": [
                    "usedPercent": 23,
                    "windowDurationMins": 300,
                    "resetsAt": 1_800_000_000,
                ],
                "secondary": [
                    "usedPercent": 51,
                    "windowDurationMins": 10_080,
                    "resetsAt": 1_800_100_000,
                ],
                "credits": [
                    "hasCredits": true,
                    "unlimited": false,
                    "balance": "42.5",
                ],
            ],
            "rateLimitsByLimitId": [
                "codex": [:],
                "codex_spark": [
                    "limitName": "Codex Spark",
                    "primary": [
                        "usedPercent": 8,
                        "windowDurationMins": 300,
                        "resetsAt": 1_800_000_000,
                    ],
                ],
            ],
        ]
        let usage: [String: Any] = [
            "summary": [
                "lifetimeTokens": 12_345_678,
                "peakDailyTokens": 2_000_000,
                "longestRunningTurnSec": 480,
                "currentStreakDays": 4,
                "longestStreakDays": 9,
            ],
            "dailyUsageBuckets": [
                ["startDate": "2026-08-23", "tokens": 900_000],
                ["startDate": "2026-08-24", "tokens": 1_250_000],
            ],
        ]

        let snapshot = try CodexAccountService.parse(
            accountResult: account,
            rateLimitsResult: limits,
            accountUsageResult: usage,
            codexHome: URL(fileURLWithPath: "/tmp/codex-account-fixture"),
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )

        XCTAssertEqual(snapshot.email, "person@example.com")
        XCTAssertEqual(snapshot.plan, "pro")
        XCTAssertEqual(snapshot.primaryWindow?.title, "5-hour quota")
        XCTAssertEqual(snapshot.primaryWindow?.remainingPercent, 77)
        XCTAssertEqual(snapshot.secondaryWindow?.title, "Weekly quota")
        XCTAssertEqual(snapshot.credits?.balance, 42.5)
        XCTAssertEqual(snapshot.additionalWindows.first?.title, "Codex Spark")
        XCTAssertEqual(snapshot.accountTokenUsage?.summary.lifetimeTokens, 12_345_678)
        XCTAssertEqual(snapshot.accountTokenUsage?.latestDailyUsage?.tokens, 1_250_000)
    }

    func testAccountCacheUpsertsByStableAccountID() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexTokenLedger-account-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("accounts.json")
        let old = fixture(id: "one", email: "old@example.com", updatedAt: Date(timeIntervalSince1970: 1))
        let replacement = fixture(id: "one", email: "new@example.com", updatedAt: Date(timeIntervalSince1970: 2))
        let other = fixture(id: "two", email: "two@example.com", updatedAt: Date(timeIntervalSince1970: 3))

        let accounts = CodexAccountUsageStore.upserting(replacement, into: [old, other])
        try CodexAccountUsageStore.save(accounts, to: url)
        let loaded = CodexAccountUsageStore.load(from: url)

        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded.first?.id, "two")
        XCTAssertEqual(loaded.first(where: { $0.id == "one" })?.email, "new@example.com")
    }

    private func fixture(id: String, email: String, updatedAt: Date) -> CodexAccountUsageSnapshot {
        CodexAccountUsageSnapshot(
            id: id,
            email: email,
            plan: "plus",
            codexHome: "/tmp/.codex",
            primaryWindow: nil,
            secondaryWindow: nil,
            additionalWindows: [],
            credits: nil,
            updatedAt: updatedAt
        )
    }
}
