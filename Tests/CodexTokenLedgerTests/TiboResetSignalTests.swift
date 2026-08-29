import AppKit
import XCTest
@testable import CodexTokenLedger

final class TiboResetSignalTests: XCTestCase {
    func testLiveEndpointAuditWhenRequested() async throws {
        guard let outputPath = ProcessInfo.processInfo.environment["TIBO_LIVE_AUDIT_OUTPUT"],
              !outputPath.isEmpty
        else {
            throw XCTSkip("Set TIBO_LIVE_AUDIT_OUTPUT to run the public-source audit.")
        }

        let snapshot = try await TiboResetSignalService().fetch()
        let signal = try XCTUnwrap(snapshot.signals.first)
        XCTAssertEqual(snapshot.sourceStatus, .healthy)
        XCTAssertEqual(signal.sourceURL.host?.lowercased(), "x.com")
        XCTAssertEqual(signal.contentHash.count, 64)
        XCTAssertFalse(signal.matchedRuleIDs.isEmpty)
        try TiboResetSignalStore.save(snapshot, to: URL(fileURLWithPath: outputPath))
    }

    func testPropagatedResetIsConfirmedByVersionedExtension() {
        let result = TiboResetRuleEngine.evaluate(
            "Good Sunday. Reset has been propagated to accounts and we landed usage fixes."
        )
        XCTAssertEqual(result.status, .confirmed)
        XCTAssertEqual(result.resetKind, "forced")
        XCTAssertTrue(result.matchedRuleIDs.contains("reset-propagated-completed"))
    }

    func testRuleOnlyFutureResetRemainsCandidateWithoutInventedWindow() {
        let result = TiboResetRuleEngine.evaluate(
            "As part of the fixes tomorrow, we will also do a full reset of the usage for all paid subscriptions."
        )
        XCTAssertEqual(result.status, .candidate)
        XCTAssertTrue(result.matchedRuleIDs.contains("first-person-future-reset"))
    }

    func testBankedResetIsNotReportedAsCompletedForcedReset() {
        let result = TiboResetRuleEngine.evaluate("We added a banked reset to your account.")
        XCTAssertEqual(result.status, .candidate)
        XCTAssertEqual(result.resetKind, "banked")
        XCTAssertTrue(result.matchedRuleIDs.contains("banked-reset"))
    }

    func testFxPayloadUsesOnlyRecentTiboAuthoredEvidence() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "code": 200,
            "results": [
                status(
                    id: "other-newer",
                    author: "someone_else",
                    date: "Tue Aug 25 02:00:00 +0000 2026",
                    text: "Reset has been propagated to accounts."
                ),
                status(
                    id: "confirmed",
                    author: "thsottiaux",
                    date: "Mon Aug 24 00:46:51 +0000 2026",
                    text: "Reset has been propagated to accounts and usage fixes landed."
                ),
                status(
                    id: "expected",
                    author: "thsottiaux",
                    date: "Sun Aug 23 00:46:51 +0000 2026",
                    text: "Tomorrow we will do a full reset of the usage for all paid subscriptions."
                ),
                status(
                    id: "old",
                    author: "thsottiaux",
                    date: "Wed Jul 01 00:00:00 +0000 2026",
                    text: "Reset has been propagated to accounts."
                ),
            ],
        ])
        let now = ISO8601DateFormatter().date(from: "2026-08-25T03:00:00Z")!
        let snapshot = try TiboResetSignalService.decode(data, now: now)

        XCTAssertEqual(snapshot.sourceStatus, .healthy)
        XCTAssertEqual(snapshot.latestSignal?.postID, "confirmed")
        XCTAssertEqual(snapshot.latestSignal?.status, .confirmed)
        XCTAssertEqual(snapshot.latestSignal?.contentHash.count, 64)
        XCTAssertEqual(snapshot.latestSignal?.ruleVersion, TiboResetSignalService.ruleVersion)
        XCTAssertEqual(snapshot.signals.map(\.postID), ["confirmed", "expected"])
        XCTAssertEqual(snapshot.signals.map(\.status), [.confirmed, .expected])
    }

    func testForecastPayloadKeepsConfirmedFactAndBoundedTeaseSeparate() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "updated_at": "2026-08-29T09:27:00.868Z",
            "last_reset_at": "2026-08-27T16:35:05.000Z",
            "evidence": [[
                "code": "last_reset",
                "href": "https://x.com/thsottiaux/status/2093014447833116908",
            ]],
            "official_signal": NSNull(),
            "teased_window": [
                "tweet_id": "2093551005711679557",
                "summary": "There is a place and a time for resets. Soon, but not today",
                "url": "https://x.com/thsottiaux/status/2093551005711679557",
                "at": "2026-08-29T04:07:10.000Z",
                "window": [
                    "start_at": "2026-08-29T07:00:00.000Z",
                    "end_at": "2026-08-30T06:59:59.999Z",
                    "time_zone": "America/Los_Angeles",
                ],
            ],
        ])
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-29T09:27:01Z"))
        let snapshot = try TiboResetSignalService.decodeForecast(data, now: now)
        let cycle = snapshot.cycle(now: now)

        XCTAssertEqual(snapshot.sourceStatus, .healthy)
        XCTAssertEqual(snapshot.latestSignal?.postID, "2093551005711679557")
        XCTAssertEqual(snapshot.latestSignal?.status, .forecast)
        XCTAssertEqual(cycle.lastConfirmedSignal?.postID, "2093014447833116908")
        XCTAssertEqual(cycle.activePrediction?.postID, "2093551005711679557")
        XCTAssertEqual(
            cycle.displayedNextResetAt,
            isoDate("2026-08-29T07:00:00Z")
        )
        XCTAssertEqual(
            cycle.displayedNextResetEnd,
            isoDate("2026-08-30T06:59:59.999Z")
        )
    }

    func testSoonButNotTodayUsesTiboLocalDayAsForecastWindow() throws {
        let postedAt = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-29T04:07:10Z"))
        let result = TiboResetRuleEngine.evaluate(
            "There is a place and a time for resets. Soon, but not today",
            postedAt: postedAt
        )

        XCTAssertEqual(result.status, .forecast)
        XCTAssertEqual(result.expectedStart, isoDate("2026-08-29T07:00:00Z"))
        XCTAssertEqual(
            try XCTUnwrap(result.expectedEnd).timeIntervalSince1970,
            try XCTUnwrap(isoDate("2026-08-30T06:59:59.999Z")).timeIntervalSince1970,
            accuracy: 0.002
        )
    }

    func testConfirmedResetDoesNotCreateFutureSchedule() throws {
        let confirmedAt = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-08-13T01:01:37Z")
        )
        let snapshot = monitor(signals: [signal(id: "done", at: confirmedAt, status: .confirmed)])
        let cycle = snapshot.cycle(now: confirmedAt.addingTimeInterval(60))

        XCTAssertEqual(cycle.lastConfirmedSignal?.postID, "done")
        XCTAssertEqual(cycle.lastObservedResetAt, confirmedAt)
        XCTAssertNil(cycle.displayedNextResetAt)
    }

    func testNewStructuredPredictionKeepsConfirmation() throws {
        let confirmedAt = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-08-13T01:01:37Z")
        )
        let expectedAt = confirmedAt.addingTimeInterval(6 * 86_400)
        var prediction = signal(
            id: "promise",
            at: confirmedAt.addingTimeInterval(86_400),
            status: .expected
        )
        prediction.expectedStart = expectedAt
        prediction.expectedEnd = expectedAt.addingTimeInterval(3_600)
        let snapshot = monitor(signals: [prediction, signal(id: "done", at: confirmedAt, status: .confirmed)])
        let cycle = snapshot.cycle(now: confirmedAt.addingTimeInterval(2 * 86_400))

        XCTAssertEqual(cycle.lastConfirmedSignal?.postID, "done")
        XCTAssertEqual(cycle.activePrediction?.postID, "promise")
        XCTAssertEqual(cycle.displayedNextResetAt, expectedAt)
        XCTAssertTrue(cycle.usesSignalPrediction)
    }

    func testConfirmationClearsFulfilledPredictionImmediately() throws {
        let predictedAt = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-08-13T00:00:00Z")
        )
        var prediction = signal(
            id: "promise",
            at: predictedAt.addingTimeInterval(-86_400),
            status: .expected
        )
        // The promised time may even fall after the confirmation post. The
        // confirmation still closes every prediction published before it.
        prediction.expectedStart = predictedAt.addingTimeInterval(7_200)
        prediction.expectedEnd = predictedAt.addingTimeInterval(10_800)
        let confirmation = signal(
            id: "done",
            at: predictedAt.addingTimeInterval(3_600),
            status: .confirmed
        )
        let cycle = monitor(signals: [confirmation, prediction])
            .cycle(now: predictedAt.addingTimeInterval(14_400))

        XCTAssertNil(cycle.activePrediction)
        XCTAssertEqual(cycle.lastConfirmedSignal?.postID, "done")
        XCTAssertNil(cycle.displayedNextResetAt)
    }

    func testExpiredPredictionDoesNotBecomeAResetFact() throws {
        let predictedAt = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-08-13T00:00:00Z")
        )
        var prediction = signal(
            id: "promise",
            at: predictedAt.addingTimeInterval(-86_400),
            status: .expected
        )
        prediction.expectedStart = predictedAt
        prediction.expectedEnd = predictedAt.addingTimeInterval(7_200)
        let cycle = monitor(signals: [prediction])
            .cycle(now: predictedAt.addingTimeInterval(7_201))

        XCTAssertNil(cycle.lastObservedResetAt)
        XCTAssertNil(cycle.activePrediction)
        XCTAssertNil(cycle.displayedNextResetAt)
    }

    func testCandidateDoesNotCreateFutureWindow() throws {
        let confirmedAt = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-08-13T01:01:37Z")
        )
        let candidate = signal(
            id: "candidate",
            at: confirmedAt.addingTimeInterval(86_400),
            status: .candidate
        )
        let cycle = monitor(
            signals: [candidate, signal(id: "done", at: confirmedAt, status: .confirmed)]
        ).cycle(now: candidate.postedAt.addingTimeInterval(60))

        XCTAssertEqual(cycle.activeCandidate?.postID, "candidate")
        XCTAssertNil(cycle.activePrediction)
        XCTAssertNil(cycle.displayedNextResetAt)
    }

    func testRemoteRefreshKeepsOlderConfirmedFacts() throws {
        let old = signal(
            id: "old-confirmed",
            at: try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-01T00:00:00Z")),
            status: .confirmed
        )
        let current = signal(
            id: "new-candidate",
            at: try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-14T00:00:00Z")),
            status: .candidate
        )
        let merged = monitor(signals: [old]).mergingRemote(monitor(signals: [current]))

        XCTAssertEqual(merged.signals.map(\.postID), ["new-candidate", "old-confirmed"])
        XCTAssertEqual(merged.cycle(now: current.postedAt).lastConfirmedSignal?.postID, "old-confirmed")
    }

    func testRemoteRefreshCannotDowngradeConfirmedPost() throws {
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-14T00:00:00Z"))
        let confirmed = signal(id: "same", at: date, status: .confirmed)
        let candidate = signal(id: "same", at: date, status: .candidate)

        let merged = monitor(signals: [confirmed]).mergingRemote(monitor(signals: [candidate]))

        XCTAssertEqual(merged.signals.count, 1)
        XCTAssertEqual(merged.latestSignal?.status, .confirmed)
    }

    func testStoreRoundTripsWithoutPostBody() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = directory.appendingPathComponent("signal.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let signal = TiboResetSignal(
            postID: "123",
            sourceURL: URL(string: "https://x.com/thsottiaux/status/123")!,
            postedAt: Date(timeIntervalSince1970: 1_700_000_000),
            status: .confirmed,
            resetKind: "forced",
            matchedRuleIDs: ["rule"],
            ruleVersion: "v1",
            contentHash: String(repeating: "a", count: 64)
        )
        let snapshot = TiboResetMonitorSnapshot(
            sourceStatus: .healthy,
            checkedAt: signal.postedAt,
            lastSuccessAt: signal.postedAt,
            latestSignal: signal,
            recentSignals: [signal],
            lastErrorCode: nil
        )

        try TiboResetSignalStore.save(snapshot, to: url)
        XCTAssertEqual(TiboResetSignalStore.load(from: url), snapshot)
        let stored = try String(contentsOf: url)
        XCTAssertFalse(stored.contains("Reset has been"))
    }

    func testSignalTimestampConvertsUTCInstantToRequestedTimezone() throws {
        let sourceDate = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-08-24T00:46:51Z")
        )
        let shanghai = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let value = TiboResetSignalFormatter.localTimestamp(
            sourceDate,
            localeIdentifier: "zh-Hans",
            timeZone: shanghai
        )

        XCTAssertTrue(value.contains("08:46"), value)
        XCTAssertTrue(value.contains("UTC+8"), value)
        XCTAssertFalse(value.contains("00:46"), value)
    }

    func testLocalizedVisibleSignalFitsTheFixedWidthRow() throws {
        let sourceDate = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-08-24T00:46:51Z")
        )
        let shanghai = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let font = NSFont.systemFont(ofSize: 12, weight: .semibold)

        for language in AppLanguage.allCases where language != .system {
            let title = LocalizationCatalog.text("tibo.signalTitle", language: language)
            let status = LocalizationCatalog.text("tibo.short.confirmed", language: language)
            let timestamp = TiboResetSignalFormatter.localTimestamp(
                sourceDate,
                localeIdentifier: language.localeIdentifier,
                timeZone: shanghai
            )
            let textWidth = [title, status, "· \(timestamp)"].reduce(CGFloat.zero) {
                $0 + ($1 as NSString).size(withAttributes: [.font: font]).width
            }
            // 290pt is the forecast row's usable width after all container
            // padding; 25pt covers the dot and inter-item spacing.
            XCTAssertLessThanOrEqual(textWidth + 25, 290, "\(language): \(title) · \(status) · \(timestamp)")
        }
    }

    func testLocalizedCyclePointLabelsFitThreeColumnsWithoutShrinking() {
        let font = NSFont.systemFont(ofSize: 12, weight: .medium)
        let keys = [
            "tibo.cycle.lastConfirmed",
            "tibo.cycle.currentSignal",
            "tibo.cycle.predictedTime",
            "tibo.cycle.forecastWindow",
            "tibo.cycle.nextSignal",
        ]

        for language in AppLanguage.allCases where language != .system {
            for key in keys {
                let value = LocalizationCatalog.text(key, language: language)
                let width = (value as NSString).size(withAttributes: [.font: font]).width
                XCTAssertLessThanOrEqual(width, 100, "\(language) \(key): \(value)")
            }
        }
    }

    private func status(id: String, author: String, date: String, text: String) -> [String: Any] {
        [
            "type": "status",
            "id": id,
            "url": "https://x.com/\(author)/status/\(id)",
            "text": text,
            "created_at": date,
            "author": ["screen_name": author],
        ]
    }

    private func isoDate(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private func signal(
        id: String,
        at date: Date,
        status: TiboSignalStatus,
        resetKind: String = "forced"
    ) -> TiboResetSignal {
        TiboResetSignal(
            postID: id,
            sourceURL: URL(string: "https://x.com/thsottiaux/status/\(id)")!,
            postedAt: date,
            status: status,
            resetKind: resetKind,
            matchedRuleIDs: ["fixture"],
            ruleVersion: "fixture-v1",
            contentHash: String(repeating: "a", count: 64)
        )
    }

    private func monitor(signals: [TiboResetSignal]) -> TiboResetMonitorSnapshot {
        TiboResetMonitorSnapshot(
            sourceStatus: .healthy,
            checkedAt: signals.first?.postedAt,
            lastSuccessAt: signals.first?.postedAt,
            latestSignal: signals.sorted { $0.postedAt > $1.postedAt }.first,
            recentSignals: signals.sorted { $0.postedAt > $1.postedAt },
            lastErrorCode: nil
        )
    }
}
