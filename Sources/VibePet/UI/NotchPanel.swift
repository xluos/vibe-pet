import SwiftUI
import AppKit

class NotchWindowController: NSWindowController {
    private let sessionStore: SessionStore
    private var expandedPresentation: NotchExpandedPresentation = .collapsed
    private var transientPresentationScreen: NSScreen?
    private var hostingView: NSHostingView<NotchRootView>?
    private var viewModel: NotchViewModel?
    private var hoverCollapseWorkItem: DispatchWorkItem?
    private var haloPanel: NSPanel?
    private var haloHostingView: NSHostingView<AttentionHaloRootView>?
    private var mouseCompanionPanel: NSPanel?
    private var mouseCompanionHostingView: NSHostingView<MouseCompanionRootView>?
    private var mouseTrackingTimer: Timer?
    private var lastMouseTrackingSample: MouseTrackingSample?
    private var lastShakeAxis: ShakeAxis?
    private var lastShakeDirection = 0
    private var lastShakeDirectionChangeAt: Date?
    private var recentShakeTurnTimestamps: [Date] = []
    private var currentShakeTravel: CGFloat = 0
    private var dismissedMouseCompanionSignature: String?
    private var proactiveAttentionCollapseTimer: Timer?
    private var acknowledgedAttentionStatuses: [String: SessionStatus] = [:]
    private var isMouseInsidePanel = false
    private var pendingPanelRefreshWorkItem: DispatchWorkItem?
    private var pendingSessionStatusRefreshWorkItem: DispatchWorkItem?
    private var pendingProactiveAttentionPopup = false
    private var cachedExpandedContentSignature: String?
    private var cachedExpandedContentHeight: CGFloat?
    private var lastAttentionPresentationSignature: String?
    private var lastMouseCompanionContentSignature: String?
    private var lastAppliedPanelFrame: NSRect?
    private var haloUpdateGeneration = 0
    private var lastAppliedHaloSignature: String?

    private var collapsedWidth: CGFloat = 260
    private var collapsedHeight: CGFloat = 33
    private var expandedWidth: CGFloat = 340
    private let collapsedLeftRevealWidth: CGFloat = 28
    private let collapsedRightRevealWidth: CGFloat = 36
    private let expandedOverflowPerSide: CGFloat = 44
    private let preferredExpandedExtraWidth: CGFloat = 80
    private let emptyStateHeight: CGFloat = 80
    private let settingsContentHeight: CGFloat = 320
    private let sessionListBaseHeight: CGFloat = 56
    private let estimatedRowHeight: CGFloat = 68
    private let collapseDelay: TimeInterval = 0.25
    private let haloSideInset: CGFloat = 180
    private let haloTopInset: CGFloat = 20
    private let haloBottomInset: CGFloat = 72
    private let mouseCompanionSize = CGSize(width: 96, height: 68)
    private let mouseCompanionOffset = CGPoint(x: 10, y: 16)
    private let sessionStatusRefreshDebounce: TimeInterval = 0.05

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

        let x = screenFrame.midX - cw / 2
        let y = screenFrame.maxY - ch
        let frame = NSRect(x: x, y: y, width: cw, height: ch)

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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLanguageChanged),
            name: L10n.languageDidChangeNotification,
            object: nil
        )
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        NotificationCenter.default.removeObserver(self)
        mouseTrackingTimer?.invalidate()
        proactiveAttentionCollapseTimer?.invalidate()
        hoverCollapseWorkItem?.cancel()
        pendingPanelRefreshWorkItem?.cancel()
        pendingSessionStatusRefreshWorkItem?.cancel()
    }

    func refreshScreenConfiguration() {
        let screen = activeScreen
        refreshMetrics(for: screen)
        invalidateExpandedContentHeightCache()
        applyFrame()
        guard let panel = window as? NSPanel else { return }
        updateAttentionHalo(relativeTo: panel)
        updateMouseCompanion()
    }

    private func setupContent() {
        guard let panel = window as? NSPanel else { return }
        let vm = NotchViewModel(
            sessionStore: sessionStore,
            notchWidth: collapsedWidth,
            notchHeight: collapsedHeight,
            onSessionClick: { [weak self] session in self?.jumpToSession(session) },
            onAttentionRead: { [weak self] session in self?.markAttentionSessionRead(session) },
            onAttentionArchive: { [weak self] session in self?.archiveAttentionSession(session) },
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
        setupMouseCompanionWindow(relativeTo: panel)
        updateMouseCompanion()
    }

    func toggleExpanded() {
        if isExpanded {
            collapseExpanded()
        } else {
            expand(.manual)
        }
    }

    private func expand(_ presentation: NotchExpandedPresentation) {
        guard let panel = window as? NSPanel, let viewModel else { return }
        if presentation == .transientAttention, let focusScreen = focusScreenForTransientAttention() {
            transientPresentationScreen = focusScreen
            refreshMetrics(for: focusScreen)
        }
        expandedPresentation = presentation
        invalidateExpandedContentHeightCache()
        cancelPendingCollapse()
        proactiveAttentionCollapseTimer?.invalidate()

        // Close settings when collapsing
        if presentation == .transientAttention {
            viewModel.showSettings = false
        }

        syncAttentionPresentation()
        applyFrame()
        updateAttentionHalo(relativeTo: panel)
        updateMouseCompanion()

        withAnimation(.easeOut(duration: 0.15)) {
            viewModel.isExpanded = true
        }

        if presentation == .transientAttention {
            scheduleProactiveAttentionCollapse()
        }
    }

    private func collapseExpanded(resetSettings: Bool = true) {
        guard let panel = window as? NSPanel, let viewModel else { return }
        let wasTransientAttention = expandedPresentation == .transientAttention
        proactiveAttentionCollapseTimer?.invalidate()
        cancelPendingCollapse()
        expandedPresentation = .collapsed
        _ = syncAttentionPresentation()
        if wasTransientAttention {
            transientPresentationScreen = nil
            refreshMetrics(for: preferredScreen)
        }

        if resetSettings {
            viewModel.showSettings = false
        }

        invalidateExpandedContentHeightCache()
        applyFrame()
        updateAttentionHalo(relativeTo: panel)
        updateMouseCompanion()

        withAnimation(.easeOut(duration: 0.15)) {
            viewModel.isExpanded = false
        }
    }

    /// Resize panel when switching to/from settings
    func updatePanelSize() {
        guard let panel = window as? NSPanel, isExpanded else { return }
        invalidateExpandedContentHeightCache()
        applyFrame()
        updateAttentionHalo(relativeTo: panel)
        updateMouseCompanion()
    }

    override func mouseEntered(with event: NSEvent) {
        isMouseInsidePanel = true
        cancelPendingCollapse()
        if expandedPresentation == .transientAttention {
            proactiveAttentionCollapseTimer?.invalidate()
            return
        }
        if !isExpanded {
            expand(.manual)
        }
    }

    override func mouseExited(with event: NSEvent) {
        isMouseInsidePanel = false
        if expandedPresentation == .transientAttention {
            scheduleProactiveAttentionCollapse()
            return
        }
        if expandedPresentation == .manual {
            scheduleCollapseIfNeeded()
        }
    }

    private func jumpToSession(_ session: Session) {
        TerminalJump.jump(to: session)
    }

    @objc
    private func handleScreenParametersChanged() {
        schedulePanelRefresh()
    }

    @objc
    private func handleDisplayPreferenceChanged() {
        schedulePanelRefresh()
    }

    @objc
    private func handleSessionStatusChanged(_ notification: Notification) {
        let oldStatus = SessionStatus(rawValue: notification.userInfo?["oldStatus"] as? String ?? "")
        let newStatus = SessionStatus(rawValue: notification.userInfo?["newStatus"] as? String ?? "")
        pendingProactiveAttentionPopup = pendingProactiveAttentionPopup
            || shouldShowProactiveAttentionPopup(oldStatus: oldStatus, newStatus: newStatus)
        scheduleSessionStatusRefresh()
    }

    private func scheduleSessionStatusRefresh() {
        pendingSessionStatusRefreshWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.applySessionStatusRefresh()
        }
        pendingSessionStatusRefreshWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + sessionStatusRefreshDebounce, execute: workItem)
    }

    private func applySessionStatusRefresh() {
        guard let panel = window as? NSPanel else { return }
        let refreshStart = PerfLog.now()
        pruneAcknowledgedAttentionSessions()
        let presentationChanged = syncAttentionPresentation()
        invalidateExpandedContentHeightCacheIfNeeded()
        updateAttentionHalo(relativeTo: panel)
        updateMouseCompanion()

        if viewModel?.showSettings == true, isExpanded {
            updatePanelSize()
        }

        if pendingProactiveAttentionPopup {
            pendingProactiveAttentionPopup = false
            showProactiveAttentionPopup()
        } else if expandedPresentation == .transientAttention {
            if visibleAttentionSessions.isEmpty {
                collapseExpanded()
            } else {
                updatePanelSize()
            }
        }

        let refreshMs = PerfLog.elapsedMS(since: refreshStart)
        if refreshMs >= 12 {
            PerfLog.log(
                "notch.session-refresh",
                "presentationChanged=\(presentationChanged) expanded=\(isExpanded) visibleAttention=\(visibleAttentionSessions.count) totalMs=\(PerfLog.format(refreshMs))"
            )
        }
    }

    @objc
    private func handleLanguageChanged() {
        invalidateExpandedContentHeightCache()
        refreshAttentionUI()
    }

    private func repositionPanel(_ panel: NSPanel, width: CGFloat, height: CGFloat) {
        panel.setFrame(Self.panelFrame(for: activeScreen, width: width, height: height), display: true)
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
        viewModel?.notchWidth = nextMetrics.collapsedWidth
        viewModel?.notchHeight = nextMetrics.collapsedHeight
        invalidateExpandedContentHeightCache()
    }

    private static func panelFrame(for screen: NSScreen, width: CGFloat, height: CGFloat) -> NSRect {
        let screenFrame = screen.frame
        let x = screenFrame.midX - width / 2
        let y = screenFrame.maxY - height
        return NSRect(x: x, y: y, width: width, height: height)
    }

    private var maxExpandedContentHeight: CGFloat {
        let screen = activeScreen
        let availableHeight = screen.frame.maxY - screen.visibleFrame.minY
        return max(emptyStateHeight, availableHeight - collapsedHeight)
    }

    private func desiredContentHeight() -> CGFloat {
        guard let viewModel else { return emptyStateHeight }

        if viewModel.showSettings {
            return min(settingsContentHeight, maxExpandedContentHeight)
        }

        let signature = expandedContentSignature()
        let rawHeight: CGFloat
        if cachedExpandedContentSignature == signature, let cachedExpandedContentHeight {
            rawHeight = cachedExpandedContentHeight
        } else {
            rawHeight = estimatedExpandedContentHeight()
            cachedExpandedContentSignature = signature
            cachedExpandedContentHeight = rawHeight
        }

        return min(rawHeight, maxExpandedContentHeight)
    }

    private func estimatedExpandedContentHeight() -> CGFloat {
        if expandedPresentation == .transientAttention {
            let count = max(visibleAttentionSessions.count, 1)
            let perRow: CGFloat = 152
            let headerHeight: CGFloat = 41
            let dividerHeight: CGFloat = 1
            let verticalPadding: CGFloat = 24
            return CGFloat(count) * perRow + headerHeight + dividerHeight + verticalPadding
        }

        if sessionStore.allSessions.isEmpty {
            return emptyStateHeight
        }

        return sessionListBaseHeight + CGFloat(sessionStore.allSessions.count) * estimatedRowHeight
    }

    private func currentPanelFrame() -> NSRect {
        let width = isExpanded ? expandedWidth : collapsedWidth
        let contentHeight = isExpanded ? desiredContentHeight() : 0
        let height = collapsedHeight + contentHeight
        return Self.panelFrame(for: activeScreen, width: width, height: height)
    }

    private func applyFrame() {
        guard let panel = window as? NSPanel else { return }
        let targetFrame = currentPanelFrame()
        guard lastAppliedPanelFrame != targetFrame || panel.frame != targetFrame else { return }
        panel.setFrame(targetFrame, display: true)
        lastAppliedPanelFrame = targetFrame
    }

    private func cancelPendingCollapse() {
        hoverCollapseWorkItem?.cancel()
        hoverCollapseWorkItem = nil
    }

    private func scheduleCollapseIfNeeded() {
        guard expandedPresentation == .manual else { return }

        cancelPendingCollapse()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.expandedPresentation == .manual else { return }
            guard !self.isMouseInsidePanel else { return }
            self.collapseExpanded()
        }

        hoverCollapseWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + collapseDelay, execute: workItem)
    }

    private func schedulePanelRefresh() {
        pendingPanelRefreshWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, let panel = self.window as? NSPanel else { return }
            let screen = self.activeScreen
            self.refreshMetrics(for: screen)
            self.applyFrame()
            self.updateAttentionHalo(relativeTo: panel)
            self.updateMouseCompanion()
        }

        pendingPanelRefreshWorkItem = workItem
        DispatchQueue.main.async(execute: workItem)
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
                color: attentionGlowColor,
                variant: AttentionAnimationPreferences.resolvedVariant()
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
        let signature = haloSignature(shouldShowHalo: shouldShowHalo, frame: frame)

        guard signature != lastAppliedHaloSignature else { return }
        haloUpdateGeneration += 1
        let generation = haloUpdateGeneration

        // Avoid forcing child-window relayout from inside the current AppKit/SwiftUI
        // layout pass; doing it synchronously can trip AttributeGraph preconditions.
        DispatchQueue.main.async { [weak self, weak panel] in
            guard let self, let haloPanel = self.haloPanel else { return }
            guard generation == self.haloUpdateGeneration else { return }

            if !shouldShowHalo {
                haloPanel.orderOut(nil)
                self.lastAppliedHaloSignature = signature
                return
            }

            haloPanel.setFrame(frame, display: false)
            self.haloHostingView?.rootView = AttentionHaloRootView(
                notchWidth: self.collapsedWidth,
                notchHeight: self.collapsedHeight,
                sideInset: self.haloSideInset,
                topInset: self.haloTopInset,
                bottomInset: self.haloBottomInset,
                color: self.attentionGlowColor,
                variant: AttentionAnimationPreferences.resolvedVariant()
            )
            self.haloHostingView?.frame = NSRect(origin: .zero, size: frame.size)

            if let panel {
                haloPanel.order(.below, relativeTo: panel.windowNumber)
            } else {
                haloPanel.orderFront(nil)
            }

            self.lastAppliedHaloSignature = signature
        }
    }

    private func setupMouseCompanionWindow(relativeTo panel: NSPanel) {
        guard mouseCompanionPanel == nil else { return }

        let companion = NSPanel(
            contentRect: mouseCompanionFrame(),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        companion.level = panel.level
        companion.isOpaque = false
        companion.backgroundColor = .clear
        companion.hasShadow = false
        companion.collectionBehavior = panel.collectionBehavior
        companion.hidesOnDeactivate = false
        companion.ignoresMouseEvents = true

        let hosting = NSHostingView(
            rootView: MouseCompanionRootView(
                petState: .needsAttention,
                color: attentionGlowColor,
                message: mouseCompanionMessage,
                showsCat: mouseCompanionShowsCat,
                showsBubble: mouseCompanionShowsBubble
            )
        )
        hosting.frame = NSRect(origin: .zero, size: mouseCompanionSize)
        hosting.autoresizingMask = [.width, .height]
        companion.contentView?.addSubview(hosting)

        self.mouseCompanionPanel = companion
        self.mouseCompanionHostingView = hosting
        companion.orderOut(nil)
    }

    private func updateMouseCompanion() {
        let attentionSignature = currentMouseCompanionAttentionSignature
        if attentionSignature.isEmpty {
            dismissedMouseCompanionSignature = nil
            resetMouseShakeTracking()
        } else if !mouseCompanionShakeDismissEnabled {
            dismissedMouseCompanionSignature = nil
            resetMouseShakeTracking()
        } else if dismissedMouseCompanionSignature != nil && dismissedMouseCompanionSignature != attentionSignature {
            dismissedMouseCompanionSignature = nil
            resetMouseShakeTracking()
        }

        let shouldShowCompanion = !attentionSignature.isEmpty
            && dismissedMouseCompanionSignature != attentionSignature
            && (mouseCompanionShowsCat || mouseCompanionShowsBubble)

        guard let companion = mouseCompanionPanel else { return }
        let contentSignature = mouseCompanionContentSignature(
            shouldShowCompanion: shouldShowCompanion,
            attentionSignature: attentionSignature
        )

        if !shouldShowCompanion {
            mouseTrackingTimer?.invalidate()
            mouseTrackingTimer = nil
            lastMouseTrackingSample = nil
            companion.orderOut(nil)
            lastMouseCompanionContentSignature = contentSignature
            return
        }

        if lastMouseCompanionContentSignature != contentSignature {
            mouseCompanionHostingView?.rootView = MouseCompanionRootView(
                petState: .needsAttention,
                color: attentionGlowColor,
                message: mouseCompanionMessage,
                showsCat: mouseCompanionShowsCat,
                showsBubble: mouseCompanionShowsBubble
            )
            lastMouseCompanionContentSignature = contentSignature
        }
        repositionMouseCompanion()

        if mouseTrackingTimer == nil {
            let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
                self?.handleMouseCompanionTick()
            }
            mouseTrackingTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        }

        companion.orderFront(nil)
    }

    private func handleMouseCompanionTick() {
        let mouseLocation = NSEvent.mouseLocation
        if mouseCompanionShakeDismissEnabled {
            processMouseShakeIfNeeded(at: mouseLocation, now: Date())
        } else {
            resetMouseShakeTracking()
        }
        repositionMouseCompanion(using: mouseLocation)
    }

    private func repositionMouseCompanion() {
        guard let companion = mouseCompanionPanel else { return }
        companion.setFrame(mouseCompanionFrame(), display: false)
    }

    private func repositionMouseCompanion(using mouseLocation: CGPoint) {
        guard let companion = mouseCompanionPanel else { return }
        companion.setFrame(mouseCompanionFrame(for: mouseLocation), display: false)
    }

    private func mouseCompanionFrame() -> NSRect {
        mouseCompanionFrame(for: NSEvent.mouseLocation)
    }

    private func mouseCompanionFrame(for mouseLocation: CGPoint) -> NSRect {
        let targetScreen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) })
            ?? DisplayPreferences.resolvedScreen()
        let visibleFrame = targetScreen.visibleFrame

        var originX = mouseLocation.x + mouseCompanionOffset.x
        var originY = mouseLocation.y + mouseCompanionOffset.y - 32

        originX = min(max(originX, visibleFrame.minX), visibleFrame.maxX - mouseCompanionSize.width)
        originY = min(max(originY, visibleFrame.minY), visibleFrame.maxY - mouseCompanionSize.height)

        return NSRect(origin: CGPoint(x: originX, y: originY), size: mouseCompanionSize)
    }

    private func processMouseShakeIfNeeded(at location: CGPoint, now: Date) {
        guard dismissedMouseCompanionSignature == nil else {
            lastMouseTrackingSample = MouseTrackingSample(location: location, timestamp: now)
            return
        }

        defer {
            lastMouseTrackingSample = MouseTrackingSample(location: location, timestamp: now)
        }

        guard let previousSample = lastMouseTrackingSample else { return }
        let dt = now.timeIntervalSince(previousSample.timestamp)
        guard dt > 0 else { return }

        let dx = location.x - previousSample.location.x
        let dy = location.y - previousSample.location.y
        let absDx = abs(dx)
        let absDy = abs(dy)

        let axis: ShakeAxis
        let delta: CGFloat
        if absDx >= absDy {
            axis = .horizontal
            delta = dx
        } else {
            axis = .vertical
            delta = dy
        }

        let magnitude = abs(delta)
        let speed = magnitude / CGFloat(dt)
        guard magnitude >= mouseCompanionShakeMinimumDistance else { return }
        guard speed >= mouseCompanionShakeMinimumSpeed else { return }

        let direction = delta > 0 ? 1 : -1

        if lastShakeAxis != axis {
            lastShakeAxis = axis
            lastShakeDirection = direction
            lastShakeDirectionChangeAt = now
            recentShakeTurnTimestamps.removeAll()
            currentShakeTravel = magnitude
            return
        }

        if direction == lastShakeDirection {
            currentShakeTravel += magnitude
            lastShakeDirectionChangeAt = now
            return
        }

        let changeWindow: TimeInterval = 0.22
        let minimumLegTravel: CGFloat = 110
        if currentShakeTravel >= minimumLegTravel,
           let lastChange = lastShakeDirectionChangeAt,
           now.timeIntervalSince(lastChange) <= changeWindow {
            recentShakeTurnTimestamps.append(now)
            recentShakeTurnTimestamps = recentShakeTurnTimestamps.filter { now.timeIntervalSince($0) <= 0.6 }
            if recentShakeTurnTimestamps.count >= 2 {
                resetMouseShakeTracking()
                if isOptionModifierPressed, completePrimaryAttentionSession() {
                    dismissedMouseCompanionSignature = nil
                } else {
                    dismissedMouseCompanionSignature = currentMouseCompanionAttentionSignature
                }
                refreshAttentionUI()
                return
            }
        } else {
            recentShakeTurnTimestamps.removeAll()
        }

        lastShakeDirection = direction
        lastShakeDirectionChangeAt = now
        currentShakeTravel = magnitude
    }

    private func resetMouseShakeTracking() {
        lastMouseTrackingSample = nil
        lastShakeAxis = nil
        lastShakeDirection = 0
        lastShakeDirectionChangeAt = nil
        recentShakeTurnTimestamps.removeAll()
        currentShakeTravel = 0
    }

    private func completePrimaryAttentionSession() -> Bool {
        guard let session = sessionStore.primaryAttentionSession else { return false }
        sessionStore.archiveSession(session)
        return true
    }

    private func refreshAttentionUI() {
        if let panel = window as? NSPanel {
            updateAttentionHalo(relativeTo: panel)
        }
        updateMouseCompanion()
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

    private var currentPetState: PetState {
        if sessionStore.sessions.values.contains(where: { $0.status == .needsApproval }) {
            return .needsAttention
        } else if sessionStore.hasActiveSession {
            return .active
        } else if sessionStore.activeSessions.isEmpty {
            return .sleeping
        } else {
            return .idle
        }
    }

    private var mouseCompanionMessage: String {
        guard let session = sessionStore.primaryAttentionSession else {
            return L10n.tr("mouseCompanion.reminder")
        }
        if session.status == .needsApproval {
            return L10n.tr("mouseCompanion.needsApproval")
        }
        if session.status == .waitingForInput {
            return L10n.tr("mouseCompanion.waitingInput")
        }
        return L10n.tr("mouseCompanion.reminder")
    }

    private var mouseCompanionShowsCat: Bool {
        AttentionAnimationPreferences.resolvedMouseCompanionCatEnabled()
    }

    private var mouseCompanionShowsBubble: Bool {
        AttentionAnimationPreferences.resolvedMouseCompanionBubbleEnabled()
    }

    private var mouseCompanionShakeDismissEnabled: Bool {
        AttentionAnimationPreferences.resolvedMouseCompanionShakeDismissEnabled()
    }

    private var mouseCompanionShakeMinimumDistance: CGFloat {
        AttentionAnimationPreferences.resolvedMouseCompanionShakeMinimumDistance()
    }

    private var mouseCompanionShakeMinimumSpeed: CGFloat {
        AttentionAnimationPreferences.resolvedMouseCompanionShakeMinimumSpeed()
    }

    private var isOptionModifierPressed: Bool {
        CGEventSource.flagsState(.combinedSessionState).contains(.maskAlternate)
    }

    private var currentMouseCompanionAttentionSignature: String {
        sessionStore.sessions.values
            .filter { $0.status == .needsApproval || $0.status == .waitingForInput }
            .map { "\($0.id):\($0.status.rawValue)" }
            .sorted()
            .joined(separator: "|")
    }

    private var isExpanded: Bool {
        expandedPresentation != .collapsed
    }

    private var preferredScreen: NSScreen {
        DisplayPreferences.resolvedScreen()
    }

    private var activeScreen: NSScreen {
        transientPresentationScreen ?? preferredScreen
    }

    private var visibleAttentionSessions: [Session] {
        sessionStore.attentionSessions.filter { session in
            acknowledgedAttentionStatuses[session.id] != session.status
        }
    }

    private func shouldShowProactiveAttentionPopup(oldStatus: SessionStatus?, newStatus: SessionStatus?) -> Bool {
        guard AttentionAnimationPreferences.resolvedProactivePopupEnabled() else { return false }
        guard let newStatus else { return false }
        guard newStatus == .waitingForInput || newStatus == .needsApproval else { return false }
        return oldStatus != newStatus
    }

    private func showProactiveAttentionPopup() {
        guard !visibleAttentionSessions.isEmpty else { return }
        expand(.transientAttention)
    }

    private func focusScreenForTransientAttention() -> NSScreen? {
        DisplayPreferences.screenContainingMouse() ?? preferredScreen
    }

    private func scheduleProactiveAttentionCollapse() {
        proactiveAttentionCollapseTimer?.invalidate()
        guard expandedPresentation == .transientAttention else { return }
        guard !isMouseInsideTransientAttentionPanel else { return }
        let delay = AttentionAnimationPreferences.resolvedProactivePopupAutoCollapseDelay()
        proactiveAttentionCollapseTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self, self.expandedPresentation == .transientAttention else { return }
            guard !self.isMouseInsideTransientAttentionPanel else {
                self.isMouseInsidePanel = true
                return
            }
            self.collapseExpanded()
        }
        if let proactiveAttentionCollapseTimer {
            RunLoop.main.add(proactiveAttentionCollapseTimer, forMode: .common)
        }
    }

    @discardableResult
    private func syncAttentionPresentation() -> Bool {
        guard let viewModel else { return false }
        let attentionIDs = visibleAttentionSessions.map(\.id)
        let signature = attentionPresentationSignature(attentionIDs: attentionIDs)
        guard signature != lastAttentionPresentationSignature else { return false }

        if expandedPresentation == .transientAttention {
            viewModel.attentionPresentation = .transient
            viewModel.attentionSessionIDs = attentionIDs
        } else {
            viewModel.attentionPresentation = .hidden
            viewModel.attentionSessionIDs = []
        }
        lastAttentionPresentationSignature = signature
        return true
    }

    private func pruneAcknowledgedAttentionSessions() {
        acknowledgedAttentionStatuses = acknowledgedAttentionStatuses.filter { sessionID, status in
            guard let session = sessionStore.sessions[sessionID] else { return false }
            return session.status == status && (status == .needsApproval || status == .waitingForInput)
        }
    }

    private func markAttentionSessionRead(_ session: Session) {
        acknowledgedAttentionStatuses[session.id] = session.status
        syncAttentionPresentation()
        if visibleAttentionSessions.isEmpty, expandedPresentation == .transientAttention {
            collapseExpanded()
        } else if expandedPresentation == .transientAttention {
            updatePanelSize()
        }
    }

    private func archiveAttentionSession(_ session: Session) {
        acknowledgedAttentionStatuses.removeValue(forKey: session.id)
        sessionStore.archiveSession(session)
    }

    private func expandedContentSignature() -> String {
        let settingsShown = viewModel?.showSettings == true
        return [
            expandedPresentationKey,
            settingsShown ? "settings" : "content",
            String(format: "%.1f", expandedWidth),
            String(format: "%.1f", collapsedHeight),
            "sessions=\(sessionStore.allSessions.count)",
            "attention=\(visibleAttentionSessions.count)",
        ].joined(separator: "#")
    }

    private func invalidateExpandedContentHeightCache() {
        cachedExpandedContentSignature = nil
        cachedExpandedContentHeight = nil
    }

    private func invalidateExpandedContentHeightCacheIfNeeded() {
        let signature = expandedContentSignature()
        if cachedExpandedContentSignature != signature {
            invalidateExpandedContentHeightCache()
        }
    }

    private func attentionPresentationSignature(attentionIDs: [String]) -> String {
        "\(expandedPresentationKey)|\(attentionIDs.joined(separator: ","))"
    }

    private func haloSignature(shouldShowHalo: Bool, frame: NSRect) -> String {
        [
            shouldShowHalo ? "shown" : "hidden",
            currentPetState == .needsAttention ? "needsApproval" : "other",
            AttentionAnimationPreferences.resolvedVariant().rawValue,
            String(format: "%.1f", frame.origin.x),
            String(format: "%.1f", frame.origin.y),
            String(format: "%.1f", frame.size.width),
            String(format: "%.1f", frame.size.height),
        ].joined(separator: "|")
    }

    private func mouseCompanionContentSignature(shouldShowCompanion: Bool, attentionSignature: String) -> String {
        [
            shouldShowCompanion ? "shown" : "hidden",
            attentionSignature,
            mouseCompanionMessage,
            mouseCompanionShowsCat ? "cat" : "no-cat",
            mouseCompanionShowsBubble ? "bubble" : "no-bubble",
            currentPetState == .needsAttention ? "needsAttention" : "other",
        ].joined(separator: "|")
    }

    private var expandedPresentationKey: String {
        switch expandedPresentation {
        case .collapsed:
            return "collapsed"
        case .manual:
            return "manual"
        case .transientAttention:
            return "transientAttention"
        }
    }

    private var isMouseInsideTransientAttentionPanel: Bool {
        guard expandedPresentation == .transientAttention,
              let panel = window as? NSPanel else { return false }
        return NSMouseInRect(NSEvent.mouseLocation, panel.frame, false)
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

private enum NotchExpandedPresentation {
    case collapsed
    case manual
    case transientAttention
}

private struct MouseTrackingSample {
    let location: CGPoint
    let timestamp: Date
}

private enum ShakeAxis {
    case horizontal
    case vertical
}

private struct MouseCompanionRootView: View {
    let petState: PetState
    let color: Color
    let message: String
    let showsCat: Bool
    let showsBubble: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
            let phase = pulsePhase(for: context.date)
            ZStack(alignment: .topLeading) {
                if showsBubble {
                    bubble(phase: phase, showsArrow: showsCat)
                        .offset(x: showsCat ? 20 : 8, y: showsCat ? 2 : 10)
                }

                if showsCat {
                    catBadge(phase: phase)
                        .offset(x: showsBubble ? 8 : 14, y: showsBubble ? 28 : 18)
                }
            }
            .frame(width: 96, height: 68, alignment: .topLeading)
            .background(Color.clear)
        }
        .allowsHitTesting(false)
    }

    private func bubble(phase: MouseCompanionPhase, showsArrow: Bool) -> some View {
        let bubbleShape = PixelSpeechBubbleShape(showsArrow: showsArrow)

        return Text(message)
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .foregroundColor(.black.opacity(0.92))
            .padding(.leading, 5)
            .padding(.trailing, 6)
            .padding(.top, 5)
            .padding(.bottom, showsArrow ? 10 : 5)
            .background {
                bubbleShape
                    .fill(Color.white.opacity(0.985))
                    .overlay {
                        bubbleShape
                            .stroke(Color.black.opacity(0.92), lineWidth: 1)
                    }
                    .overlay {
                        bubbleShape
                            .fill(Color.white.opacity(0.12 + phase.flash * 0.04))
                            .padding(2)
                    }
            }
            .fixedSize()
            .shadow(color: color.opacity(0.14 + phase.glow * 0.1), radius: 3, y: 1)
            .scaleEffect(0.99 + phase.beat * 0.025, anchor: .bottomLeading)
    }

    private func catBadge(phase: MouseCompanionPhase) -> some View {
        ZStack {
            Circle()
                .fill(glowGradient(phase: phase))
                .frame(width: 30, height: 30)
                .scaleEffect(0.92 + phase.expansion * 0.18)
                .blur(radius: 1.6 + phase.afterglow * 2.4)

            Circle()
                .stroke(color.opacity(0.25 + phase.flash * 0.45), lineWidth: 1.2)
                .frame(width: 24 + phase.beat * 4, height: 24 + phase.beat * 4)
                .blur(radius: phase.beat * 0.6)

            PetView(state: petState)
                .frame(width: 14, height: 14)
                .scaleEffect(1.0 + phase.beat * 0.08)
                .shadow(color: color.opacity(0.5), radius: 6 + phase.glow * 4)
        }
    }

    private func glowGradient(phase: MouseCompanionPhase) -> RadialGradient {
        RadialGradient(
            colors: [
                color.opacity(0.34 + phase.glow * 0.16),
                color.opacity(0.16 + phase.afterglow * 0.18),
                Color.clear
            ],
            center: .center,
            startRadius: 2,
            endRadius: 15
        )
    }

    private func pulsePhase(for date: Date) -> MouseCompanionPhase {
        let progress = date.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: 1.5) / 1.5
        let primary = pulse(progress: progress, center: 0.12, width: 0.12)
        let secondary = pulse(progress: progress, center: 0.32, width: 0.16)
        let beat = max(primary, secondary * 0.8)
        let afterglow = max(primary * 0.5, secondary * 0.75)
        let ambient = (sin(progress * .pi * 2 - (.pi / 2)) + 1) / 2
        return MouseCompanionPhase(
            beat: beat,
            afterglow: afterglow,
            glow: min(1, beat * 0.85 + afterglow * 0.75 + ambient * 0.15),
            flash: min(1, beat + afterglow * 0.7),
            expansion: beat * 0.4 + afterglow * 0.6
        )
    }

    private func pulse(progress: Double, center: Double, width: Double) -> Double {
        let distance = abs(progress - center)
        guard distance < width else { return 0 }

        let normalized = 1 - (distance / width)
        return normalized * normalized * (3 - 2 * normalized)
    }
}

private struct MouseCompanionPhase {
    let beat: Double
    let afterglow: Double
    let glow: Double
    let flash: Double
    let expansion: Double
}

private struct PixelSpeechBubbleShape: Shape {
    let showsArrow: Bool

    func path(in rect: CGRect) -> Path {
        guard showsArrow else {
            return RoundedRectangle(cornerRadius: 6, style: .continuous).path(in: rect)
        }

        let arrowHeight: CGFloat = 5
        let cornerRadius: CGFloat = 6
        let bodyBottom = rect.maxY - arrowHeight
        let radius = min(cornerRadius, (bodyBottom - rect.minY) / 2)
        let arrowTipX = rect.minX + 16
        let arrowBaseLeft = rect.minX + 22
        let arrowBaseRight = rect.minX + 34

        var path = Path()

        path.move(to: CGPoint(x: rect.minX + radius, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + radius),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: bodyBottom - radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - radius, y: bodyBottom),
            control: CGPoint(x: rect.maxX, y: bodyBottom)
        )
        path.addLine(to: CGPoint(x: arrowBaseRight, y: bodyBottom))
        path.addQuadCurve(
            to: CGPoint(x: arrowTipX, y: rect.maxY),
            control: CGPoint(x: rect.minX + 26, y: bodyBottom + arrowHeight * 0.2)
        )
        path.addQuadCurve(
            to: CGPoint(x: arrowBaseLeft, y: bodyBottom),
            control: CGPoint(x: rect.minX + 18, y: bodyBottom + arrowHeight * 0.6)
        )
        path.addLine(to: CGPoint(x: rect.minX + radius, y: bodyBottom))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: bodyBottom - radius),
            control: CGPoint(x: rect.minX, y: bodyBottom)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + radius, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        path.closeSubpath()

        return path
    }
}

@Observable
class NotchViewModel {
    let sessionStore: SessionStore
    var notchWidth: CGFloat
    var notchHeight: CGFloat
    let onSessionClick: (Session) -> Void
    let onAttentionRead: (Session) -> Void
    let onAttentionArchive: (Session) -> Void
    let onQuit: () -> Void
    var isExpanded: Bool = false
    var showSettings: Bool = false
    var attentionPresentation: AttentionPanelPresentation = .hidden
    var attentionSessionIDs: [String] = []

    init(
        sessionStore: SessionStore,
        notchWidth: CGFloat,
        notchHeight: CGFloat,
        onSessionClick: @escaping (Session) -> Void,
        onAttentionRead: @escaping (Session) -> Void,
        onAttentionArchive: @escaping (Session) -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.sessionStore = sessionStore
        self.notchWidth = notchWidth
        self.notchHeight = notchHeight
        self.onSessionClick = onSessionClick
        self.onAttentionRead = onAttentionRead
        self.onAttentionArchive = onAttentionArchive
        self.onQuit = onQuit
    }
}

enum AttentionPanelPresentation {
    case hidden
    case transient
}
