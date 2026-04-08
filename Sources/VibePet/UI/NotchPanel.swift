import SwiftUI
import AppKit

class NotchWindowController: NSWindowController {
    private let sessionStore: SessionStore
    private var isExpanded = false
    private var hostingView: NSHostingView<NotchRootView>?
    private var viewModel: NotchViewModel?
    private var hoverCollapseWorkItem: DispatchWorkItem?

    private var collapsedWidth: CGFloat = 260
    private var collapsedHeight: CGFloat = 33
    private var expandedWidth: CGFloat = 340
    private let sidePadding: CGFloat = 40
    private let emptyStateHeight: CGFloat = 80
    private let settingsContentHeight: CGFloat = 320
    private let sessionListBaseHeight: CGFloat = 56
    private let estimatedRowHeight: CGFloat = 68
    private let collapseDelay: TimeInterval = 0.25

    init(sessionStore: SessionStore) {
        self.sessionStore = sessionStore

        let screen = Self.targetScreen()
        let metrics = Self.metrics(for: screen, sidePadding: sidePadding)
        let frame = Self.panelFrame(
            for: screen,
            width: metrics.collapsedWidth,
            height: metrics.collapsedHeight
        )

        let panel = NSPanel(
            contentRect: frame,
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

        self.collapsedWidth = metrics.collapsedWidth
        self.collapsedHeight = metrics.collapsedHeight
        self.expandedWidth = metrics.expandedWidth

        setupContent()
        refreshScreenConfiguration()

        let trackingArea = NSTrackingArea(
            rect: panel.contentView!.bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        panel.contentView?.addTrackingArea(trackingArea)
    }

    required init?(coder: NSCoder) { fatalError() }

    private static func targetScreen() -> NSScreen {
        NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 })
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    private static func metrics(
        for screen: NSScreen,
        sidePadding: CGFloat
    ) -> (collapsedWidth: CGFloat, collapsedHeight: CGFloat, expandedWidth: CGFloat) {
        let screenFrame = screen.frame
        let safe = screen.safeAreaInsets
        let leftArea = screen.auxiliaryTopLeftArea ?? .zero
        let rightArea = screen.auxiliaryTopRightArea ?? .zero
        let notchWidth = screenFrame.width - leftArea.width - rightArea.width
        let menuBarHeight: CGFloat
        if safe.top > 0 {
            menuBarHeight = safe.top
        } else {
            let derived = screenFrame.maxY - (screen.visibleFrame.maxY)
            menuBarHeight = derived > 0 ? derived : 24
        }
        let hasNotch = safe.top > 0 && notchWidth > 0
        let collapsedWidth = hasNotch ? (notchWidth + sidePadding * 2) : 220
        let collapsedHeight = hasNotch ? menuBarHeight + 1 : menuBarHeight
        let expandedWidth = max(collapsedWidth + 80, 340)
        return (collapsedWidth, collapsedHeight, expandedWidth)
    }

    private static func panelFrame(
        for screen: NSScreen,
        width: CGFloat,
        height: CGFloat
    ) -> NSRect {
        let screenFrame = screen.frame
        let x = screenFrame.midX - width / 2
        let y = screenFrame.maxY - height
        return NSRect(x: x, y: y, width: width, height: height)
    }

    private var maxExpandedContentHeight: CGFloat {
        let screen = Self.targetScreen()
        let availableHeight = screen.frame.maxY - screen.visibleFrame.minY
        return max(emptyStateHeight, availableHeight - collapsedHeight)
    }

    private func desiredContentHeight(showSettings: Bool) -> CGFloat {
        let rawHeight: CGFloat
        if showSettings {
            rawHeight = settingsContentHeight
        } else if sessionStore.allSessions.isEmpty {
            rawHeight = emptyStateHeight
        } else {
            rawHeight = sessionListBaseHeight + CGFloat(sessionStore.allSessions.count) * estimatedRowHeight
        }

        return min(rawHeight, maxExpandedContentHeight)
    }

    private func currentPanelFrame(showSettings: Bool) -> NSRect {
        let screen = Self.targetScreen()
        let width = isExpanded ? expandedWidth : collapsedWidth
        let contentHeight = isExpanded ? desiredContentHeight(showSettings: showSettings) : 0
        return Self.panelFrame(
            for: screen,
            width: width,
            height: collapsedHeight + contentHeight
        )
    }

    private func applyFrame(showSettings: Bool) {
        guard let panel = window as? NSPanel else { return }
        panel.setFrame(currentPanelFrame(showSettings: showSettings), display: true)
    }

    private func cancelPendingCollapse() {
        hoverCollapseWorkItem?.cancel()
        hoverCollapseWorkItem = nil
    }

    private func scheduleCollapseIfNeeded() {
        guard isExpanded else { return }

        cancelPendingCollapse()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.isExpanded, let panel = self.window else { return }
            guard let contentView = panel.contentView else {
                self.toggleExpanded()
                return
            }

            let mouseLocation = contentView.convert(panel.mouseLocationOutsideOfEventStream, from: nil)
            if !contentView.bounds.contains(mouseLocation) {
                self.toggleExpanded()
            }
        }

        hoverCollapseWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + collapseDelay, execute: workItem)
    }

    func refreshScreenConfiguration() {
        let screen = Self.targetScreen()
        let metrics = Self.metrics(for: screen, sidePadding: sidePadding)

        collapsedWidth = metrics.collapsedWidth
        collapsedHeight = metrics.collapsedHeight
        expandedWidth = metrics.expandedWidth

        viewModel?.notchWidth = collapsedWidth
        viewModel?.notchHeight = collapsedHeight

        applyFrame(showSettings: viewModel?.showSettings ?? false)
    }

    private func setupContent() {
        guard let panel = window else { return }
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
    }

    func toggleExpanded() {
        isExpanded.toggle()
        guard let panel = window as? NSPanel, let viewModel else { return }

        // Close settings when collapsing
        if !isExpanded { viewModel.showSettings = false }
        if isExpanded {
            cancelPendingCollapse()
        }

        panel.setFrame(currentPanelFrame(showSettings: viewModel.showSettings), display: true)

        withAnimation(.easeOut(duration: 0.15)) {
            viewModel.isExpanded = isExpanded
        }
    }

    /// Resize panel when switching to/from settings
    func updatePanelSize() {
        guard let panel = window as? NSPanel, let viewModel, isExpanded else { return }
        panel.setFrame(currentPanelFrame(showSettings: viewModel.showSettings), display: true)
    }

    override func mouseEntered(with event: NSEvent) {
        cancelPendingCollapse()
        if !isExpanded { toggleExpanded() }
    }

    override func mouseExited(with event: NSEvent) {
        scheduleCollapseIfNeeded()
    }

    private func jumpToSession(_ session: Session) {
        TerminalJump.jump(to: session)
    }
}

@Observable
class NotchViewModel {
    let sessionStore: SessionStore
    var notchWidth: CGFloat
    var notchHeight: CGFloat
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
