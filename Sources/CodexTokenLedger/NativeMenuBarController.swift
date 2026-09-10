import AppKit
import Combine
import SwiftUI

@MainActor
final class CodexTokenLedgerAppDelegate: NSObject, NSApplicationDelegate {
    private let viewModel = DashboardViewModel()
    private let updateService = AppUpdateService()
    private var menuBarController: NativeMenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // Tests create isolated models and windows; do not start production polling.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        updateService.start()
        menuBarController = NativeMenuBarController(
            viewModel: viewModel,
            updateService: updateService
        )
        menuBarController?.startPolling()
        viewModel.loadIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        menuBarController?.stop()
    }
}

@MainActor
final class NativeMenuBarController: NSObject, NSWindowDelegate {
    static let contentWidth = MenuBarDashboardView.contentWidth

    private let viewModel: DashboardViewModel
    private let updateService: AppUpdateService
    let statusItem: NSStatusItem
    private let statusBar: NSStatusBar
    private let panel: FrostedDashboardPanel
    private var updateObservation: AnyCancellable?
    private var themeObservation: AnyCancellable?
    private var localClickMonitor: Any?
    private var globalClickMonitor: Any?
    private var pollingTimer: Timer?
    private var lastAccountTick = Date.distantPast
    private var displayedMetric: MenuBarMetric?
    private var displayedText: String?
    private var displayedAccessibilityText: String?

    init(viewModel: DashboardViewModel, updateService: AppUpdateService, statusBar: NSStatusBar = .system) {
        self.viewModel = viewModel
        self.updateService = updateService
        self.statusBar = statusBar
        statusItem = statusBar.statusItem(withLength: NSStatusItem.variableLength)
        panel = FrostedDashboardPanel(content: AnyView(
            MenuBarDashboardView(updateService: updateService).environmentObject(viewModel)
        ))
        super.init()
        panel.delegate = self
        panel.onDismiss = { [weak self] in self?.dismissDashboard() }
        configureStatusItem()
        observeViewModel()
        applyAppearance()
    }

    func stop() {
        dismissDashboard()
        pollingTimer?.invalidate()
        pollingTimer = nil
        updateObservation?.cancel()
        themeObservation?.cancel()
        updateObservation = nil
        themeObservation = nil
        panel.close()
        statusBar.removeStatusItem(statusItem)
    }

    @objc private func toggleDashboard() {
        if panel.isVisible { dismissDashboard() } else { showDashboard() }
    }

    private func showDashboard() {
        guard let button = statusItem.button, let window = button.window else { return }
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = window.screen ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return }
        panel.setFrame(FrostedDashboardPanel.frame(anchoredTo: anchor, visibleFrame: visibleFrame), display: true)
        applyAppearance()
        panel.makeKeyAndOrderFront(nil)
        button.highlight(true)
        viewModel.refreshLaunchAtLoginState()
        viewModel.scheduledLiveContextTick()
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return }
                if event.window !== self.panel && event.window !== self.statusItem.button?.window {
                    self.dismissDashboard()
                }
            }
            return event
        }
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismissDashboard() }
        }
    }

    private func dismissDashboard() {
        if let localClickMonitor { NSEvent.removeMonitor(localClickMonitor) }
        if let globalClickMonitor { NSEvent.removeMonitor(globalClickMonitor) }
        localClickMonitor = nil
        globalClickMonitor = nil
        panel.orderOut(nil)
        statusItem.button?.highlight(false)
    }

    func windowDidResignKey(_ notification: Notification) {
        if panel.attachedSheet == nil { dismissDashboard() }
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.imageScaling = .scaleProportionallyDown
        button.imagePosition = .imageLeading
        button.font = .monospacedSystemFont(ofSize: 12.5, weight: .medium)
        button.target = self
        button.action = #selector(toggleDashboard)
        button.setAccessibilityTitle("Codex Lens")
        button.setAccessibilityIdentifier("CodexTokenLedger.StatusItem")
        refreshStatusItemLabel()
    }

    private func observeViewModel() {
        themeObservation = viewModel.$appTheme.removeDuplicates().sink { [weak self] theme in
            self?.applyAppearance(theme)
        }
        let menuChanges: [AnyPublisher<Void, Never>] = [
            viewModel.$menuBarMetric.map { _ in () }.eraseToAnyPublisher(),
            viewModel.$liveContext.map { _ in () }.eraseToAnyPublisher(),
            viewModel.$liveContexts.map { _ in () }.eraseToAnyPublisher(),
            viewModel.$accountSnapshots.map { _ in () }.eraseToAnyPublisher(),
            viewModel.$selectedAccountID.map { _ in () }.eraseToAnyPublisher(),
            viewModel.$snapshot.map { _ in () }.eraseToAnyPublisher(),
            viewModel.$showConcurrentTaskCount.map { _ in () }.eraseToAnyPublisher(),
            viewModel.$appLanguage.map { _ in () }.eraseToAnyPublisher(),
            viewModel.$abbreviateTokenCounts.map { _ in () }.eraseToAnyPublisher(),
            viewModel.$isScanning.map { _ in () }.eraseToAnyPublisher()
        ]
        // @Published emits before assignment; read the completed state on the run loop.
        updateObservation = Publishers.MergeMany(menuChanges).receive(on: RunLoop.main).sink { [weak self] in
            self?.refreshStatusItemLabel()
        }
    }

    private func applyAppearance(_ theme: AppTheme? = nil) {
        let appearance: NSAppearance?
        switch theme ?? viewModel.appTheme {
        case .system: appearance = nil
        case .light: appearance = NSAppearance(named: .aqua)
        case .dark: appearance = NSAppearance(named: .darkAqua)
        }
        NSApp.appearance = appearance
        panel.appearance = appearance
        panel.contentView?.appearance = appearance
    }

    func startPolling() {
        guard pollingTimer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.viewModel.scheduledLiveContextTick(refreshDisplayClock: self.panel.isVisible)
                if Date().timeIntervalSince(self.lastAccountTick) >= 30 {
                    self.lastAccountTick = Date()
                    self.viewModel.accountTimerTick()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollingTimer = timer
    }

    private func refreshStatusItemLabel() {
        guard let button = statusItem.button else { return }
        let text = viewModel.menuBarMetric == .iconOnly ? "" : viewModel.menuBarText
        if displayedMetric != viewModel.menuBarMetric {
            button.image = statusIcon()
            displayedMetric = viewModel.menuBarMetric
        }
        if displayedText != text {
            button.title = text
            button.imagePosition = text.isEmpty ? .imageOnly : .imageLeading
            displayedText = text
        }
        let metricTitle = viewModel.menuMetricTitle(viewModel.menuBarMetric)
        let accessibleText = text.isEmpty ? "Codex Lens" : "Codex Lens · \(metricTitle): \(text)"
        if displayedAccessibilityText != accessibleText {
            button.toolTip = accessibleText
            button.setAccessibilityTitle(accessibleText)
            displayedAccessibilityText = accessibleText
        }
    }

    /// The status item stays compact by letting one raster glyph carry the
    /// metric meaning. Context input uses the existing arrow artwork rotated
    /// downward; the title can therefore remain a clean numeric readout.
    private func statusIcon() -> NSImage? {
        if viewModel.menuBarMetric == .iconOnly {
            guard let source = NSImage(named: "CodexLensAppIcon") else { return nil }
            let size = NSSize(width: 14, height: 14)
            let image = NSImage(size: size, flipped: false) { rect in
                source.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
                return true
            }
            image.isTemplate = false
            return image
        }

        let specification: (name: String, rotation: CGFloat)
        switch viewModel.menuBarMetric {
        case .contextUsed: specification = ("arrow-right", -90)
        case .requestAPICost, .credits, .usd: specification = ("credits", 0)
        case .quotaRemaining: specification = ("quota", 0)
        case .weeklyRemaining: specification = ("calendar", 0)
        case .tokens: specification = ("ledger", 0)
        case .iconOnly: return nil
        }

        guard let source = NSImage(named: "PulseIcon-\(specification.name)") else { return nil }
        let size = NSSize(width: 13, height: 13)
        let image = NSImage(size: size, flipped: false) { rect in
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }

            if specification.rotation != 0 {
                let transform = NSAffineTransform()
                transform.translateX(by: rect.midX, yBy: rect.midY)
                transform.rotate(byDegrees: specification.rotation)
                transform.translateX(by: -rect.midX, yBy: -rect.midY)
                transform.concat()
            }
            source.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
        image.isTemplate = true
        return image
    }

}

/// A single behind-window material owns the entire surface, including its edges.
@MainActor
final class FrostedDashboardPanel: NSPanel {
    private static let cornerRadius: CGFloat = 14
    private static let cornerMask: NSImage = {
        let radius = cornerRadius
        let size = NSSize(width: radius * 2 + 1, height: radius * 2 + 1)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }()

    let presentation = DashboardPresentationState()
    let backdrop = NSVisualEffectView()
    private let viewport = NSScrollView()
    let hostingView: NSHostingView<AnyView>
    var onDismiss: (() -> Void)?

    init(content: AnyView) {
        hostingView = TransparentDashboardHostingView(rootView: AnyView(
            DashboardPresentationContent(presentation: presentation, content: content)
        ))
        super.init(contentRect: NSRect(x: 0, y: 0, width: MenuBarDashboardView.contentWidth, height: MenuBarDashboardView.primaryPageHeight),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isMovable = false
        level = .popUpMenu
        collectionBehavior = [.transient, .moveToActiveSpace, .fullScreenAuxiliary]
        animationBehavior = .none
        backdrop.material = .menu
        backdrop.blendingMode = .behindWindow
        backdrop.state = .active
        // Layer clipping alone does not shape the behind-window material or its shadow.
        backdrop.maskImage = Self.cornerMask
        backdrop.wantsLayer = true
        backdrop.layer?.cornerRadius = Self.cornerRadius
        backdrop.layer?.masksToBounds = true
        backdrop.layer?.borderWidth = 0.5
        backdrop.layer?.borderColor = NSColor(calibratedWhite: 1, alpha: 0.24).cgColor
        contentView = backdrop

        // Small displays retain the full layout with native vertical scrolling;
        // at the normal 680 pt height there is no scroll range or scroller.
        viewport.drawsBackground = false
        viewport.contentView.drawsBackground = false
        viewport.borderType = .noBorder
        viewport.hasVerticalScroller = true
        viewport.autohidesScrollers = true
        viewport.scrollerStyle = .overlay
        viewport.horizontalScrollElasticity = .none
        viewport.verticalScrollElasticity = .none
        viewport.translatesAutoresizingMaskIntoConstraints = false
        hostingView.frame = NSRect(x: 0, y: 0, width: MenuBarDashboardView.contentWidth, height: MenuBarDashboardView.primaryPageHeight)
        hostingView.sizingOptions = []
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        viewport.documentView = hostingView
        backdrop.addSubview(viewport)
        NSLayoutConstraint.activate([
            viewport.leadingAnchor.constraint(equalTo: backdrop.leadingAnchor),
            viewport.trailingAnchor.constraint(equalTo: backdrop.trailingAnchor),
            viewport.topAnchor.constraint(equalTo: backdrop.topAnchor),
            viewport.bottomAnchor.constraint(equalTo: backdrop.bottomAnchor)
        ])
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func orderFront(_ sender: Any?) {
        presentation.setVisible(true)
        super.orderFront(sender)
    }

    override func makeKeyAndOrderFront(_ sender: Any?) {
        presentation.setVisible(true)
        super.makeKeyAndOrderFront(sender)
    }

    override func orderOut(_ sender: Any?) {
        presentation.setVisible(false)
        super.orderOut(sender)
    }

    override func close() {
        presentation.setVisible(false)
        super.close()
    }

    override func cancelOperation(_ sender: Any?) { onDismiss?() }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection([.command, .option, .control, .shift]) == .command,
           event.charactersIgnoringModifiers?.lowercased() == "q" {
            NSApp.terminate(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    static func frame(anchoredTo anchor: NSRect, visibleFrame: NSRect) -> NSRect {
        let margin: CGFloat = 8
        let width = MenuBarDashboardView.contentWidth
        let top = min(anchor.minY - 6, visibleFrame.maxY - margin)
        let height = min(MenuBarDashboardView.primaryPageHeight, max(1, top - visibleFrame.minY - margin))
        let x = min(max(anchor.midX - width / 2, visibleFrame.minX + margin), visibleFrame.maxX - width - margin)
        return NSRect(x: x, y: top - height, width: width, height: height)
    }
}

private final class TransparentDashboardHostingView: NSHostingView<AnyView> {
    override var allowsVibrancy: Bool { true }
    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class DashboardPresentationState: ObservableObject {
    @Published private(set) var isVisible = false

    func setVisible(_ visible: Bool) {
        guard isVisible != visible else { return }
        isVisible = visible
    }
}

private struct DashboardVisibilityKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var dashboardIsVisible: Bool {
        get { self[DashboardVisibilityKey.self] }
        set { self[DashboardVisibilityKey.self] = newValue }
    }
}

private struct DashboardPresentationContent: View {
    @ObservedObject var presentation: DashboardPresentationState
    let content: AnyView

    var body: some View {
        // Keep navigation and scroll state alive while suspending hidden animations.
        content.environment(\.dashboardIsVisible, presentation.isVisible)
    }
}
