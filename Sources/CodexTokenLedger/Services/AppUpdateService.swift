import Combine
import Foundation
import Sparkle

enum AppUpdatePhase: Equatable {
    case idle
    case checking
    case current
    case available(String)
    case failed
}

@MainActor
final class AppUpdateService: NSObject, ObservableObject, SPUUpdaterDelegate {
    @Published private(set) var phase: AppUpdatePhase = .idle
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates = true
    @Published private(set) var automaticallyDownloadsUpdates = true
    @Published private(set) var lastUpdateCheckDate: Date?

    private var updaterController: SPUStandardUpdaterController!
    private var observations: [NSKeyValueObservation] = []
    private var hasStarted = false

    override init() {
        super.init()
        updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        updaterController.startUpdater()
        observeUpdater()
        syncSettings()
    }

    func checkForUpdates() {
        if !hasStarted { start() }
        guard updaterController.updater.canCheckForUpdates else { return }
        phase = .checking
        updaterController.checkForUpdates(nil)
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        updaterController.updater.automaticallyChecksForUpdates = enabled
        syncSettings()
    }

    func setAutomaticallyDownloadsUpdates(_ enabled: Bool) {
        updaterController.updater.automaticallyDownloadsUpdates = enabled
        syncSettings()
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        phase = .available(item.displayVersionString)
        syncSettings()
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        phase = .current
        syncSettings()
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        if phase != .current {
            phase = .failed
        }
        syncSettings()
    }

    private func observeUpdater() {
        let updater = updaterController.updater
        observations = [
            updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.syncSettings() }
            },
            updater.observe(\.automaticallyChecksForUpdates, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.syncSettings() }
            },
            updater.observe(\.automaticallyDownloadsUpdates, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.syncSettings() }
            },
            updater.observe(\.lastUpdateCheckDate, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.syncSettings() }
            },
        ]
    }

    private func syncSettings() {
        let updater = updaterController.updater
        canCheckForUpdates = updater.canCheckForUpdates
        automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
        automaticallyDownloadsUpdates = updater.automaticallyDownloadsUpdates
        lastUpdateCheckDate = updater.lastUpdateCheckDate
    }
}
