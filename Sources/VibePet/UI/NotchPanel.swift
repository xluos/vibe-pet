import SwiftUI
import AppKit

class NotchWindowController: NSWindowController {
    private let sessionStore: SessionStore
    private var isExpanded = false
    private var hostingView: NSHostingView<NotchRootView>?
    private var viewModel: NotchViewModel?
    private var haloPanel: NSPanel?
    private var haloHostingView: NSHostingView<AttentionHaloRootView>?

    private var collapsedWidth: CGFloat = 260
    private var collapsedHeight: CGFloat = 33
    private var expandedWidth: CGFloat = 340
    private let collapsedLeftRevealWidth: CGFloat = 28
    private let collapsedRightRevealWidth: CGFloat = 36
    private let expandedOverflowPerSide: CGFloat = 44
    private let preferredExpandedExtraWidth: CGFloat = 80
    private let haloSideInset: CGFloat = 180
    private let haloTopInset: CGFloat = 20
    private let haloBottomInset: CGFloat = 72

    init(sessionStore: SessionStore) {
        self.sessionStore = sessionStore

        let screen = DisplayPreferences.resolvedScreen()
        let screenFrame = screen.frame
        let metrics = Self.metrics(
            for: screen,
            collapsedLeftRevealWidth: collapsedLeftRevealWidth,
            collapsedRightRevealWidth: collapsedRightRevealWidth,
            expandedOverflowPerSide: expandedOverflowPerSide,
            preferredExpandedExtraWidth: preferredExpandedExtraWidth
        )
        let cw = metrics.collapsedWidth
        let ch = metrics.collapsedHeight
        let ew = metrics.expandedWidth

        let x = screenFrame.midX - cw / 2
        let y = screenFrame.maxY - ch

        let panel = NSPanel(
            contentRect: NSRect(x: x, y: y, width: cw, height: ch),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        panel.level = NSWindow.Level(Int(CGShieldingWindowLevel()))
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.isMovable = false
        panel.hidesOnDeactivate = false

        super.init(window: panel)

        self.collapsedWidth = cw
        self.collapsedHeight = ch
        self.expandedWidth = ew

        setupContent()

        let trackingArea = NSTrackingArea(
            rect: panel.contentView!.bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        panel.contentView?.addTrackingArea(trackingArea)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDisplayPreferenceChanged),
            name: UserDefaults.didChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSessionStatusChanged),
            name: .sessionStatusChanged,
            object: nil
        )
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func setupContent() {
        guard let panel = window as? NSPanel else { return }
        let vm = NotchViewModel(
            sessionStore: sessionStore,
            notchWidth: collapsedWidth,
            notchHeight: collapsedHeight,
            onSessionClick: { [weak self] session in self?.jumpToSession(session) },
            onQuit: { NSApplication.shared.terminate(nil) }
        )
        self.viewModel = vm

        let hosting = NSHostingView(rootView: NotchRootView(viewModel: vm))
        hosting.frame = panel.contentView!.bounds
        hosting.autoresizingMask = [.width, .height]
        panel.contentView?.addSubview(hosting)
        self.hostingView = hosting

        setupHaloWindow(relativeTo: panel)
        updateAttentionHalo(relativeTo: panel)
    }

    func toggleExpanded() {
        isExpanded.toggle()
        guard let panel = window as? NSPanel, let viewModel else { return }

        // Close settings when collapsing
        if !isExpanded { viewModel.showSettings = false }

        let sessionCount = sessionStore.allSessions.count
        let expandedContentHeight: CGFloat
        if sessionCount == 0 {
            expandedContentHeight = 80
        } else {
            // Estimate: header(44) + rows + padding
            let perRow: CGFloat = 70
            expandedContentHeight = min(44 + CGFloat(sessionCount) * perRow + 12, 420)
        }
        let w = isExpanded ? expandedWidth : collapsedWidth
        let height = isExpanded ? (collapsedHeight + expandedContentHeight) : collapsedHeight

        repositionPanel(panel, width: w, height: height)
        updateAttentionHalo(relativeTo: panel)

        withAnimation(.easeOut(duration: 0.15)) {
            viewModel.isExpanded = isExpanded
        }
    }

    /// Resize panel when switching to/from settings
    func updatePanelSize() {
        guard let panel = window as? NSPanel, let viewModel, isExpanded else { return }

        let contentHeight: CGFloat = viewModel.showSettings ? 320 : min(CGFloat(max(sessionStore.allSessions.count, 1) * 52 + 60), 400)
        let height = collapsedHeight + contentHeight
        let w = expandedWidth

        repositionPanel(panel, width: w, height: height)
        updateAttentionHalo(relativeTo: panel)
    }

    override func mouseEntered(with event: NSEvent) {
        if !isExpanded { toggleExpanded() }
    }

    override func mouseExited(with event: NSEvent) {
        if isExpanded { toggleExpanded() }
    }

    private func jumpToSession(_ session: Session) {
        TerminalJump.jump(to: session)
    }

    @objc
    private func handleScreenParametersChanged() {
        guard let panel = window as? NSPanel else { return }
        let screen = DisplayPreferences.resolvedScreen()
        refreshMetrics(for: screen)
        let width = isExpanded ? expandedWidth : collapsedWidth
        let height = panel.frame.height
        repositionPanel(panel, width: width, height: height)
        updateAttentionHalo(relativeTo: panel)
    }

    @objc
    private func handleDisplayPreferenceChanged() {
        guard let panel = window as? NSPanel else { return }
        let screen = DisplayPreferences.resolvedScreen()
        refreshMetrics(for: screen)
        repositionPanel(panel, width: isExpanded ? expandedWidth : collapsedWidth, height: panel.frame.height)
        updateAttentionHalo(relativeTo: panel)
    }

    @objc
    private func handleSessionStatusChanged() {
        guard let panel = window as? NSPanel else { return }
        updateAttentionHalo(relativeTo: panel)
    }

    private func repositionPanel(_ panel: NSPanel, width: CGFloat, height: CGFloat) {
        let screen = DisplayPreferences.resolvedScreen()
        let screenFrame = screen.frame
        let x = screenFrame.midX - width / 2
        let y = screenFrame.maxY - height
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }

    private func refreshMetrics(for screen: NSScreen) {
        let nextMetrics = Self.metrics(
            for: screen,
            collapsedLeftRevealWidth: collapsedLeftRevealWidth,
            collapsedRightRevealWidth: collapsedRightRevealWidth,
            expandedOverflowPerSide: expandedOverflowPerSide,
            preferredExpandedExtraWidth: preferredExpandedExtraWidth
        )
        collapsedWidth = nextMetrics.collapsedWidth
        collapsedHeight = nextMetrics.collapsedHeight
        expandedWidth = nextMetrics.expandedWidth
    }

    private func setupHaloWindow(relativeTo panel: NSPanel) {
        guard haloPanel == nil else { return }

        let frame = haloFrame(relativeTo: panel.frame)
        let halo = NSPanel(
            contentRect: frame,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        halo.level = panel.level
        halo.isOpaque = false
        halo.backgroundColor = .clear
        halo.hasShadow = false
        halo.collectionBehavior = panel.collectionBehavior
        halo.hidesOnDeactivate = false
        halo.ignoresMouseEvents = true

        let hosting = NSHostingView(
            rootView: AttentionHaloRootView(
                notchWidth: collapsedWidth,
                notchHeight: collapsedHeight,
                sideInset: haloSideInset,
                topInset: haloTopInset,
                bottomInset: haloBottomInset,
                color: attentionGlowColor
            )
        )
        hosting.frame = NSRect(origin: .zero, size: frame.size)
        hosting.autoresizingMask = [.width, .height]
        halo.contentView?.addSubview(hosting)

        self.haloPanel = halo
        self.haloHostingView = hosting

        panel.addChildWindow(halo, ordered: .below)
        halo.orderOut(nil)
    }

    private func updateAttentionHalo(relativeTo panel: NSPanel) {
        let shouldShowHalo = !isExpanded && sessionStore.hasSessionNeedingAttention
        let frame = haloFrame(relativeTo: panel.frame)

        // Avoid forcing child-window relayout from inside the current AppKit/SwiftUI
        // layout pass; doing it synchronously can trip AttributeGraph preconditions.
        DispatchQueue.main.async { [weak self, weak panel] in
            guard let self, let haloPanel = self.haloPanel else { return }

            if !shouldShowHalo {
                haloPanel.orderOut(nil)
                return
            }

            haloPanel.setFrame(frame, display: false)
            self.haloHostingView?.rootView = AttentionHaloRootView(
                notchWidth: self.collapsedWidth,
                notchHeight: self.collapsedHeight,
                sideInset: self.haloSideInset,
                topInset: self.haloTopInset,
                bottomInset: self.haloBottomInset,
                color: self.attentionGlowColor
            )
            self.haloHostingView?.frame = NSRect(origin: .zero, size: frame.size)

            if let panel {
                haloPanel.order(.below, relativeTo: panel.windowNumber)
            } else {
                haloPanel.orderFront(nil)
            }
        }
    }

    private func haloFrame(relativeTo panelFrame: NSRect) -> NSRect {
        NSRect(
            x: panelFrame.minX - haloSideInset,
            y: panelFrame.minY - haloBottomInset,
            width: panelFrame.width + haloSideInset * 2,
            height: collapsedHeight + haloTopInset + haloBottomInset
        )
    }

    private var attentionGlowColor: Color {
        if sessionStore.sessions.values.contains(where: { $0.status == .needsApproval }) {
            return Color(red: 1.0, green: 0.22, blue: 0.18)
        }
        return Color(red: 1.0, green: 0.74, blue: 0.08)
    }

    private static func metrics(
        for screen: NSScreen,
        collapsedLeftRevealWidth: CGFloat,
        collapsedRightRevealWidth: CGFloat,
        expandedOverflowPerSide: CGFloat,
        preferredExpandedExtraWidth: CGFloat
    ) -> (collapsedWidth: CGFloat, collapsedHeight: CGFloat, expandedWidth: CGFloat) {
        let menuBarHeight = screen.menuBarHeight
        let hasNotch = screen.hasUsableNotch
        let collapsedWidth = hasNotch
            ? (screen.notchWidth + collapsedLeftRevealWidth + collapsedRightRevealWidth)
            : 220
        let collapsedHeight = hasNotch ? (menuBarHeight + 1) : 25

        let preferredExpandedWidth = max(collapsedWidth + preferredExpandedExtraWidth, 340)
        let expandedWidth: CGFloat
        if hasNotch {
            expandedWidth = max(
                preferredExpandedWidth,
                screen.centeredWidth(overflowPerSide: expandedOverflowPerSide)
            )
        } else {
            expandedWidth = preferredExpandedWidth
        }

        return (collapsedWidth, collapsedHeight, expandedWidth)
    }
}

@Observable
class NotchViewModel {
    let sessionStore: SessionStore
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    let onSessionClick: (Session) -> Void
    let onQuit: () -> Void
    var isExpanded: Bool = false
    var showSettings: Bool = false

    init(sessionStore: SessionStore, notchWidth: CGFloat, notchHeight: CGFloat, onSessionClick: @escaping (Session) -> Void, onQuit: @escaping () -> Void) {
        self.sessionStore = sessionStore
        self.notchWidth = notchWidth
        self.notchHeight = notchHeight
        self.onSessionClick = onSessionClick
        self.onQuit = onQuit
    }
}
