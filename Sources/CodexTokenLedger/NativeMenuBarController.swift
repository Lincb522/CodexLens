import AppKit
import Combine
import QuartzCore
import SwiftUI

/// Uses the same presentation primitive as CodexBar: a real `NSStatusItem`
/// attached to a native `NSMenu`. AppKit owns the complete menu window and its
/// system backdrop blur; SwiftUI only supplies transparent menu content.
@MainActor
final class CodexTokenLedgerAppDelegate: NSObject, NSApplicationDelegate {
    private let viewModel = DashboardViewModel()
    private var menuBarController: NativeMenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        menuBarController = NativeMenuBarController(viewModel: viewModel)
        viewModel.loadIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        menuBarController?.stop()
    }
}

@MainActor
final class NativeMenuBarController: NSObject, NSMenuDelegate {
    static let contentWidth = MenuBarDashboardView.contentWidth

    private let viewModel: DashboardViewModel
    private let statusItem: NSStatusItem
    private let menu = NativeDashboardMenu()
    private let dashboardItem = NativeDashboardMenuItem()
    private let hostingView: NativeDashboardHostingView
    private let menuTopBridge = MenuTopBridgeView()
    private var updateObservation: AnyCancellable?
    private var themeObservation: AnyCancellable?
    private var layoutObservation: AnyCancellable?
    private var settledLayoutWorkItem: DispatchWorkItem?
    private var pollingTimer: Timer?
    private var lastAccountTick = Date.distantPast

    init(viewModel: DashboardViewModel, statusBar: NSStatusBar = .system) {
        self.viewModel = viewModel
        statusItem = statusBar.statusItem(withLength: NSStatusItem.variableLength)
        hostingView = NativeDashboardHostingView(
            rootView: AnyView(
                MenuBarDashboardView()
                    .environmentObject(viewModel)
            )
        )
        super.init()
        configureStatusItem()
        configureNativeMenu()
        observeViewModel()
        startPolling()
    }

    func stop() {
        pollingTimer?.invalidate()
        pollingTimer = nil
        updateObservation?.cancel()
        updateObservation = nil
        themeObservation?.cancel()
        themeObservation = nil
        layoutObservation?.cancel()
        layoutObservation = nil
        settledLayoutWorkItem?.cancel()
        settledLayoutWorkItem = nil
        menuTopBridge.removeFromSuperview()
        statusItem.menu = nil
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    func menuWillOpen(_ menu: NSMenu) {
        applyAppearance()
        resizeDashboardIfNeeded(force: true)
        viewModel.scheduledLiveContextTick()
        DispatchQueue.main.async { [weak self] in
            self?.installMenuTopBridge()
        }
    }

    func menuDidOpen(_ menu: NSMenu) {
        installMenuTopBridge()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.imageScaling = .scaleProportionallyDown
        button.imagePosition = .imageLeading
        button.font = .monospacedSystemFont(ofSize: 12.5, weight: .medium)
        button.setAccessibilityTitle("Token Pulse")
        button.setAccessibilityIdentifier("CodexTokenLedger.StatusItem")
        refreshStatusItemLabel()
    }

    private func configureNativeMenu() {
        menu.autoenablesItems = false
        menu.delegate = self

        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        // Keep SwiftUI's ideal content height available even after an open
        // NSMenu has temporarily grown for an expanded details transition.
        hostingView.sizingOptions = [.intrinsicContentSize]
        hostingView.frame = NSRect(
            origin: .zero,
            size: NSSize(width: Self.contentWidth, height: 1)
        )

        dashboardItem.title = ""
        dashboardItem.isEnabled = true
        dashboardItem.view = hostingView
        menu.addItem(dashboardItem)
        statusItem.menu = menu

        applyAppearance()
        resizeDashboardIfNeeded(force: true)
    }

    private func observeViewModel() {
        // `objectWillChange` fires before an @Published value is assigned. Use
        // the theme publisher's emitted value directly so the open native menu
        // changes appearance synchronously instead of waiting for it to close.
        themeObservation = viewModel.$appTheme
            .removeDuplicates()
            .sink { [weak self] theme in
                self?.applyAppearance(theme)
            }

        updateObservation = viewModel.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.refreshStatusItemLabel()
                    self.resizeDashboardIfNeeded()
                }
            }

        // Page and console-tab state live in SwiftUI. The revision bridges
        // those changes back to AppKit so the NSMenu item is remeasured both
        // immediately and after the page transition finishes. Without this,
        // a shorter console can remain centered in the taller overview frame,
        // leaving empty bands above and below it.
        layoutObservation = viewModel.$menuLayoutRevision
            .dropFirst()
            .sink { [weak self] _ in
                guard let self else { return }
                self.settledLayoutWorkItem?.cancel()
                DispatchQueue.main.async { [weak self] in
                    self?.resizeDashboardIfNeeded(force: true)
                }

                // Page transitions and the detail view's deferred unmount can
                // briefly report an intermediate fitting height. Only the
                // newest state gets a settled pass, so stale layout work cannot
                // enlarge the menu again after the user has collapsed it.
                let workItem = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    self.hostingView.invalidateIntrinsicContentSize()
                    // Do not force an identical second NSMenu update. The
                    // delayed pass only exists to catch a genuinely changed
                    // post-transition intrinsic height; redundant updates can
                    // visibly nudge an already settled menu window.
                    self.resizeDashboardIfNeeded()
                }
                self.settledLayoutWorkItem = workItem
                DispatchQueue.main.asyncAfter(
                    deadline: .now() + 0.62,
                    execute: workItem
                )
            }
    }

    private func startPolling() {
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.viewModel.scheduledLiveContextTick()
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
        button.image = statusIcon()
        button.title = text
        button.imagePosition = text.isEmpty ? .imageOnly : .imageLeading
        let metricTitle = viewModel.menuMetricTitle(viewModel.menuBarMetric)
        let accessibleText = text.isEmpty ? "Token Pulse" : "Token Pulse · \(metricTitle): \(text)"
        button.toolTip = accessibleText
        button.setAccessibilityTitle(accessibleText)
    }

    /// The status item stays compact by letting one raster glyph carry the
    /// metric meaning. Context input uses the existing arrow artwork rotated
    /// downward; the title can therefore remain a clean numeric readout.
    private func statusIcon() -> NSImage? {
        if viewModel.menuBarMetric == .iconOnly {
            guard let source = NSImage(named: "TokenPulseAppIcon") else { return nil }
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

    private func applyAppearance(_ theme: AppTheme? = nil) {
        let appearance: NSAppearance?
        switch theme ?? viewModel.appTheme {
        case .system:
            // Nil is important: assigning the current effective appearance
            // would freeze the menu when macOS changes between light and dark.
            appearance = nil
        case .light:
            appearance = NSAppearance(named: .aqua)
        case .dark:
            appearance = NSAppearance(named: .darkAqua)
        }

        // NSMenu owns the glass window. Applying the theme only to SwiftUI
        // changes text but leaves that window in its previous appearance.
        // Keep the application, menu, hosting view and already-open menu window
        // on the same explicit appearance, or nil when following macOS.
        NSApp.appearance = appearance
        menu.appearance = appearance
        hostingView.appearance = appearance
        hostingView.window?.appearance = appearance
        hostingView.needsLayout = true
        hostingView.needsDisplay = true
        hostingView.window?.contentView?.needsDisplay = true
        hostingView.window?.invalidateShadow()
        menuTopBridge.updateAppearance(
            theme: theme ?? viewModel.appTheme,
            fallback: hostingView.effectiveAppearance
        )
        menu.update()
    }

    private func resizeDashboardIfNeeded(force: Bool = false) {
        hostingView.invalidateIntrinsicContentSize()
        hostingView.frame = NSRect(
            origin: .zero,
            size: NSSize(width: Self.contentWidth, height: max(1, hostingView.frame.height))
        )
        hostingView.layoutSubtreeIfNeeded()
        let intrinsicHeight = hostingView.intrinsicContentSize.height
        let idealHeight = intrinsicHeight.isFinite && intrinsicHeight > 0
            ? intrinsicHeight
            : hostingView.fittingSize.height
        let measuredHeight = max(1, ceil(idealHeight))
        guard force || abs(hostingView.frame.height - measuredHeight) > 0.5 else { return }
        hostingView.frame = NSRect(
            origin: .zero,
            size: NSSize(width: Self.contentWidth, height: measuredHeight)
        )
        hostingView.layoutSubtreeIfNeeded()
        menu.update()
        DispatchQueue.main.async { [weak self] in
            self?.installMenuTopBridge()
        }
    }

    /// A native NSMenu reserves a small strip above a custom menu-item view.
    /// On the overview that strip exposed the light menu material above the
    /// edge-to-edge hero gradient. Cover only that reserved inset, leaving the
    /// rest of AppKit's glass and rounded window untouched.
    private func installMenuTopBridge() {
        guard viewModel.menuUsesHeroTopBridge,
              let contentView = hostingView.window?.contentView
        else {
            menuTopBridge.removeFromSuperview()
            return
        }

        let bounds = contentView.bounds
        let hosted = hostingView.convert(hostingView.bounds, to: contentView)
        guard let bridgeFrame = NativeMenuTopBridgeGeometry.frame(
            contentBounds: bounds,
            hostedFrame: hosted,
            contentIsFlipped: contentView.isFlipped
        ) else {
            // NSMenu can briefly report stale coordinates while its window is
            // opening or resizing. Never let that transient value turn this
            // decorative inset into an overlay that clips the identity row.
            menuTopBridge.removeFromSuperview()
            return
        }

        if menuTopBridge.superview !== contentView {
            menuTopBridge.removeFromSuperview()
            contentView.addSubview(menuTopBridge, positioned: .above, relativeTo: nil)
        }

        // The frame ends exactly where the hosted SwiftUI view begins. There
        // is deliberately no one-point overlap: the bridge may fill AppKit's
        // reserved inset, but it can never cover or crop the hero itself.
        menuTopBridge.frame = bridgeFrame
        menuTopBridge.updateAppearance(
            theme: viewModel.appTheme,
            fallback: hostingView.effectiveAppearance
        )
    }
}

/// Computes a bounded, non-overlapping frame for AppKit's native menu inset.
/// Normal NSMenu top padding is only a few points; a larger value is stale
/// window geometry and must be rejected rather than painted over SwiftUI.
enum NativeMenuTopBridgeGeometry {
    static let minimumGap: CGFloat = 0.5
    static let maximumGap: CGFloat = 12

    static func frame(
        contentBounds: NSRect,
        hostedFrame: NSRect,
        contentIsFlipped: Bool
    ) -> NSRect? {
        let measuredGap = contentIsFlipped
            ? hostedFrame.minY - contentBounds.minY
            : contentBounds.maxY - hostedFrame.maxY

        guard measuredGap.isFinite,
              measuredGap >= minimumGap,
              measuredGap <= maximumGap,
              contentBounds.width.isFinite,
              contentBounds.width > 0
        else { return nil }

        return NSRect(
            x: contentBounds.minX,
            y: contentIsFlipped ? contentBounds.minY : hostedFrame.maxY,
            width: contentBounds.width,
            height: measuredGap
        )
    }
}

private final class NativeDashboardMenu: NSMenu {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown,
              event.modifierFlags.intersection([.command, .option, .control, .shift]) == .command
        else {
            return super.performKeyEquivalent(with: event)
        }
        if event.charactersIgnoringModifiers?.lowercased() == "q" {
            NSApp.terminate(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// Prevents AppKit from painting a full-row selection behind the dashboard.
private final class NativeDashboardMenuItem: NSMenuItem {
    override var isHighlighted: Bool { false }
}

private final class NativeDashboardHostingView: NSHostingView<AnyView> {
    override var allowsVibrancy: Bool { true }
    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Paints only the NSMenu-reserved top inset so the overview gradient reaches
/// the rounded menu edge. It is event-transparent and removed on other pages.
private final class MenuTopBridgeView: NSView {
    private let heroTopGradient = CAGradientLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.clear.cgColor
        heroTopGradient.startPoint = CGPoint(x: 0, y: 0.5)
        heroTopGradient.endPoint = CGPoint(x: 1, y: 0.5)
        heroTopGradient.locations = MenuHeroTopPalette.bridgeLocations
        heroTopGradient.actions = [
            "bounds": NSNull(),
            "position": NSNull(),
            "colors": NSNull(),
            "locations": NSNull(),
        ]
        layer?.addSublayer(heroTopGradient)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        heroTopGradient.frame = bounds
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func updateAppearance(theme: AppTheme, fallback: NSAppearance) {
        let isDark: Bool
        switch theme {
        case .dark:
            isDark = true
        case .light:
            isDark = false
        case .system:
            isDark = fallback.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }

        let base: NSColor
        let trailing: NSColor
        if isDark {
            base = MenuHeroTopPalette.darkBase
            trailing = MenuHeroTopPalette.darkTopTrailing
        } else {
            base = MenuHeroTopPalette.lightBase
            trailing = MenuHeroTopPalette.lightTopTrailing
        }
        heroTopGradient.colors = [base.cgColor, base.cgColor, trailing.cgColor]
    }
}
