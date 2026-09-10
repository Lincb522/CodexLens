import AppKit
import Combine
import Darwin
import SwiftUI
import XCTest
@testable import CodexTokenLedger

final class DashboardPerformanceTests: XCTestCase {
    @MainActor
    func testRepeatedLiveSnapshotsDoNotPublishButChangesAndSelectionStillApply() throws {
        let (model, defaults, suite) = try isolatedModel()
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = context(id: "one")
        let second = context(id: "two")
        model.applyLiveContexts([first, second])
        model.selectLiveContext(second.id)
        var publications = 0
        let observation = model.objectWillChange.sink { publications += 1 }
        defer { observation.cancel() }
        for _ in 0..<30 {
            model.applyLiveContexts([first, second])
            model.selectLiveContext(second.id)
        }
        XCTAssertEqual(publications, 0)
        XCTAssertEqual(defaults.string(forKey: "selectedLiveContextID"), second.id)

        let changed = context(id: "two", input: 9_999, title: "Updated title", active: false)
        model.applyLiveContexts([changed, first])
        XCTAssertEqual(model.liveContext, changed)
        XCTAssertEqual(model.selectedLiveContextID, second.id)
        XCTAssertEqual(model.activeTaskCount, 1)
        XCTAssertEqual(publications, 2)

        model.applyLiveContexts([first])
        XCTAssertEqual(model.liveContext, first)
        XCTAssertEqual(defaults.string(forKey: "selectedLiveContextID"), first.id)
        model.applyLiveContexts([])
        XCTAssertNil(model.liveContext)
        XCTAssertNil(model.selectedLiveContextID)
        XCTAssertNil(defaults.string(forKey: "selectedLiveContextID"))
        XCTAssertNotNil(model.liveContextErrorMessage)
        let emptyCount = publications
        model.applyLiveContexts([])
        XCTAssertEqual(publications, emptyCount)
        model.applyLiveContexts([first])
        XCTAssertNil(model.liveContextErrorMessage)
        XCTAssertEqual(model.liveContext, first)
    }

    @MainActor
    func testHiddenClockStillCollectsNewTokenEvents() async throws {
        let (model, defaults, suite) = try isolatedModel()
        defer { defaults.removePersistentDomain(forName: suite) }
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        let sessions = home.appendingPathComponent("sessions")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        try #"""
        {"timestamp":"2026-09-10T01:00:00Z","type":"session_meta","payload":{"id":"hidden-poll","cwd":"/Projects/Fixture"}}
        {"timestamp":"2026-09-10T01:00:01Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1200,"cached_input_tokens":900,"output_tokens":130},"last_token_usage":{"input_tokens":200,"cached_input_tokens":100,"output_tokens":30},"model_context_window":258400}}}
        """#.write(to: sessions.appendingPathComponent("fixture.jsonl"), atomically: true, encoding: .utf8)
        model.codexHomePath = home.path
        let initialClock = model.clockNow
        var clockUpdates = 0
        let clockObservation = model.$clockNow.dropFirst().sink { _ in clockUpdates += 1 }
        let collected = expectation(description: "Hidden window still collects tokens")
        let liveObservation = model.$liveContext.compactMap { $0 }.prefix(1).sink { _ in collected.fulfill() }
        defer { clockObservation.cancel(); liveObservation.cancel() }
        model.scheduledLiveContextTick(refreshDisplayClock: false)
        await fulfillment(of: [collected], timeout: 10)
        XCTAssertEqual(model.clockNow, initialClock)
        XCTAssertEqual(clockUpdates, 0)
        XCTAssertEqual(model.liveContext?.lastRequest.inputTokens, 200)
        XCTAssertEqual(model.liveContext?.taskTotal.totalTokens, 1_330)
        XCTAssertFalse(model.isLiveContextRefreshing)
        model.scheduledLiveContextTick()
        XCTAssertEqual(clockUpdates, 1)
        XCTAssertGreaterThan(model.clockNow, initialClock)
    }

    @MainActor
    func testStatusItemReusesItsImageUntilTheMetricChanges() async throws {
        let (model, defaults, suite) = try isolatedModel()
        let priorAppearance = NSApp.appearance
        defer { defaults.removePersistentDomain(forName: suite); NSApp.appearance = priorAppearance }
        model.applyLiveContexts([context(id: "one")])
        model.menuBarMetric = .contextUsed
        let controller = NativeMenuBarController(viewModel: model, updateService: AppUpdateService())
        defer { controller.stop() }
        let button = try XCTUnwrap(controller.statusItem.button)
        let originalImage = try XCTUnwrap(button.image)
        model.errorMessage = "Unrelated error"
        model.searchText = "Unrelated search"
        model.applyLiveContexts([context(id: "one", input: 9_999)])
        await waitUntil { button.title == model.menuBarText }
        XCTAssertTrue(button.image === originalImage)
        XCTAssertTrue(button.toolTip?.contains(button.title) == true)
        model.abbreviateTokenCounts.toggle()
        await waitUntil { button.title == model.menuBarText }
        XCTAssertTrue(button.image === originalImage)
        model.menuBarMetric = .iconOnly
        await waitUntil { button.title.isEmpty }
        XCTAssertFalse(button.image === originalImage)
        XCTAssertEqual(button.imagePosition, .imageOnly)
        XCTAssertEqual(button.toolTip, "Codex Lens")
        model.menuBarMetric = .contextUsed
        await waitUntil { button.title == model.menuBarText }
        XCTAssertEqual(button.imagePosition, .imageLeading)
    }

    @MainActor
    func testPanelVisibilityReachesContentWithoutReplacingItsState() async throws {
        let probe = DashboardVisibilityProbe()
        let panel = FrostedDashboardPanel(content: AnyView(DashboardVisibilityProbeView(probe: probe)))
        defer { panel.close() }
        XCTAssertFalse(panel.presentation.isVisible)
        panel.orderFront(nil)
        await waitUntil { probe.values.last?.visible == true }
        let originalID = try XCTUnwrap(probe.values.last?.identity)
        panel.orderOut(nil)
        await waitUntil { probe.values.last?.visible == false }
        XCTAssertFalse(panel.isVisible)
        panel.makeKeyAndOrderFront(nil)
        await waitUntil { probe.values.last?.visible == true }
        XCTAssertTrue(panel.isVisible)
        XCTAssertTrue(probe.values.allSatisfy { $0.identity == originalID })
        panel.close()
        XCTAssertFalse(panel.presentation.isVisible)
    }

    @MainActor
    private func waitUntil(_ condition: @escaping () -> Bool) async {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        await fulfillment(of: [ready], timeout: 5)
    }

    @MainActor
    private func isolatedModel() throws -> (DashboardViewModel, UserDefaults, String) {
        let suite = "CodexTokenLedger.Performance.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let model = DashboardViewModel(defaults: defaults, initialQuotaHistorySamples: [], initialTiboSignalSnapshot: .empty)
        model.autoRefresh = false
        model.tiboMonitoringEnabled = false
        model.accountSnapshots = []
        model.selectedAccountID = nil
        return (model, defaults, suite)
    }

    private func context(id: String, input: Int64 = 1_000, title: String = "Fixture", active: Bool = true) -> CodexLiveContextSnapshot {
        CodexLiveContextSnapshot(
            id: id, sourcePath: "/tmp/\(id).jsonl", projectPath: "/Projects/Fixture",
            threadTitle: title, titleSource: .desktopCatalog, turnID: "turn-\(id)",
            model: "gpt-5.6-sol", reasoningEffort: "high", updatedAt: Date(timeIntervalSince1970: 1_789_000_000),
            lastRequest: TokenUsage(inputTokens: input, cachedInputTokens: input / 2, outputTokens: 50),
            currentTurnUsage: TokenUsage(inputTokens: input, outputTokens: 50), currentTurnCalls: [],
            taskTotal: TokenUsage(inputTokens: input, outputTokens: 50), modelContextWindow: 258_400,
            duplicateEventsIgnored: 0, isTaskActive: active
        )
    }

    @MainActor
    func testDashboardCPUWhenVisibleAndHidden() throws {
        guard let output = ProcessInfo.processInfo.environment["DASHBOARD_CPU_AUDIT_OUTPUT"] else {
            throw XCTSkip("Set DASHBOARD_CPU_AUDIT_OUTPUT to run the bounded CPU benchmark")
        }
        let root = URL(fileURLWithPath: output, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let environment = ProcessInfo.processInfo.environment
        let sampleSeconds = min(60, max(5, Double(environment["DASHBOARD_CPU_SAMPLE_SECONDS"] ?? "5") ?? 5))
        let polling = environment["DASHBOARD_CPU_LIVE_POLLING"] == "1"
        let suite = "CodexTokenLedger.CPU.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = DashboardViewModel(defaults: defaults, initialQuotaHistorySamples: [], initialTiboSignalSnapshot: .empty)
        model.appLanguage = .zhHans
        model.appTheme = .dark
        model.autoRefresh = false
        model.tiboMonitoringEnabled = false
        let home = root.appendingPathComponent("empty-home")
        try FileManager.default.createDirectory(at: home.appendingPathComponent("sessions"), withIntermediateDirectories: true)
        model.codexHomePath = home.path
        model.accountSnapshots = (0..<4).map { index in
            CodexAccountUsageSnapshot(
                id: "fixture-\(index)", email: "account-\(index)-long-name@example.invalid", plan: "pro",
                codexHome: "/tmp/codex-cpu-fixture-\(index)", primaryWindow: nil, secondaryWindow: nil,
                additionalWindows: [], credits: nil, updatedAt: Date()
            )
        }
        model.selectedAccountID = model.accountSnapshots.first?.id
        model.liveContexts = []
        model.liveContext = nil
        let service = AppUpdateService()
        var results: [[String: Any]] = []
        for (label, page) in [("settings", MenuPopoverPage.settings), ("loading", .overview)] {
            if let selectedPage = environment["DASHBOARD_CPU_PAGE"], selectedPage != label { continue }
            model.isScanning = label == "loading"
            let content = MenuBarDashboardView(updateService: service, initialPage: page, initialConsolePanel: .account)
                .environmentObject(model)
            let panel = FrostedDashboardPanel(content: AnyView(content))
            panel.setFrameOrigin(NSPoint(x: 70, y: 120))
            defer { panel.close() }
            let timer = Timer(timeInterval: 1, repeats: true) { _ in
                MainActor.assumeIsolated {
                    model.scheduledLiveContextTick(refreshDisplayClock: panel.isVisible)
                }
            }
            if polling { RunLoop.main.add(timer, forMode: .common) }
            defer { timer.invalidate() }
            for visible in [true, false, true] {
                if visible { panel.orderFront(nil) } else { panel.orderOut(nil) }
                XCTAssertEqual(panel.isVisible, visible)
                runLoop(for: 1)
                let startCPU = cpuSeconds()
                let start = ProcessInfo.processInfo.systemUptime
                runLoop(for: sampleSeconds)
                let elapsed = ProcessInfo.processInfo.systemUptime - start
                let cpu = cpuSeconds() - startCPU
                results.append(["page": label, "visible": visible, "elapsedSeconds": elapsed,
                                "cpuSeconds": cpu, "oneCoreCPUPercent": 100 * cpu / elapsed])
                if visible {
                    let host = panel.hostingView
                    host.layoutSubtreeIfNeeded()
                    let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                        .write(to: root.appendingPathComponent("\(label).png"))
                }
            }
            panel.close()
        }
        let data = try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: root.appendingPathComponent("cpu.json"))
        print("Dashboard CPU benchmark: \(String(decoding: data, as: UTF8.self))")
    }

    private func cpuSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
            + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
    }

    @MainActor
    private func runLoop(for duration: TimeInterval) {
        let end = Date().addingTimeInterval(duration)
        while Date() < end {
            RunLoop.main.run(until: min(end, Date().addingTimeInterval(0.02)))
        }
    }
}

@MainActor
private final class DashboardVisibilityProbe {
    var values: [(visible: Bool, identity: UUID)] = []
}

private struct DashboardVisibilityProbeView: View {
    let probe: DashboardVisibilityProbe
    @Environment(\.dashboardIsVisible) private var visible
    @State private var identity = UUID()

    var body: some View {
        Text("Visibility fixture")
            .onAppear { probe.values.append((visible, identity)) }
            .onChange(of: visible) { _, value in probe.values.append((value, identity)) }
    }
}
