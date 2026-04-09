import SwiftUI

// MARK: - Attention animation timing

private enum AttentionPulseStyle {
    static let cycleDuration: TimeInterval = 1.5
    static let rippleDelays: [CGFloat] = [0.0, 0.16, 0.32]
    static let hyperRippleDelays: [CGFloat] = [0.0, 0.12, 0.24, 0.36]

    static func phase(at date: Date) -> AttentionPulsePhase {
        let rawProgress = date.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: cycleDuration) / cycleDuration
        return AttentionPulsePhase(progress: CGFloat(rawProgress))
    }

    static func wrappedDistance(progress: CGFloat, center: CGFloat) -> CGFloat {
        let wrapped = wrap(progress - center)
        return min(wrapped, 1 - wrapped)
    }

    static func softPulse(progress: CGFloat, center: CGFloat, width: CGFloat) -> CGFloat {
        let distance = wrappedDistance(progress: progress, center: center)
        guard distance < width else { return 0 }

        let normalized = 1 - (distance / width)
        return normalized * normalized * (3 - 2 * normalized)
    }

    static func wrap(_ value: CGFloat) -> CGFloat {
        let wrapped = value.truncatingRemainder(dividingBy: 1)
        return wrapped >= 0 ? wrapped : (wrapped + 1)
    }
}

private struct AttentionPulsePhase {
    let progress: CGFloat

    var beat: CGFloat {
        max(
            AttentionPulseStyle.softPulse(progress: progress, center: 0.08, width: 0.085),
            AttentionPulseStyle.softPulse(progress: progress, center: 0.22, width: 0.095)
        )
    }

    var afterglow: CGFloat {
        max(
            AttentionPulseStyle.softPulse(progress: progress, center: 0.14, width: 0.18) * 0.52,
            AttentionPulseStyle.softPulse(progress: progress, center: 0.3, width: 0.22) * 0.72
        )
    }

    var ambient: CGFloat {
        let wave = (sin(Double(progress) * .pi * 2 - (.pi / 2)) + 1) / 2
        return CGFloat(wave)
    }

    var borderFlash: CGFloat {
        min(1, beat + afterglow * 0.7)
    }

    var borderExpansion: CGFloat {
        beat * 0.38 + afterglow * 0.62
    }

    var glow: CGFloat {
        min(1, beat * 0.92 + afterglow * 0.74 + ambient * 0.14)
    }

    var goldenBurst: CGFloat {
        AttentionPulseStyle.softPulse(progress: progress, center: 0.14, width: 0.16)
    }

    var shakeEnvelope: CGFloat {
        max(
            AttentionPulseStyle.softPulse(progress: progress, center: 0.08, width: 0.14),
            AttentionPulseStyle.softPulse(progress: progress, center: 0.24, width: 0.14)
        )
    }

    var shakeOffset: CGFloat {
        CGFloat(sin(Double(progress) * .pi * 24)) * shakeEnvelope * 3.2
    }

    func rippleProgress(delay: CGFloat, activeWindow: CGFloat = 0.58) -> CGFloat? {
        let shifted = AttentionPulseStyle.wrap(progress - delay)
        guard shifted <= activeWindow else { return nil }
        return shifted / activeWindow
    }
}

private struct AttentionPulseTimeline<Content: View>: View {
    @ViewBuilder let content: (AttentionPulsePhase) -> Content

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
            content(AttentionPulseStyle.phase(at: context.date))
        }
    }
}

private struct AttentionEffectMetrics {
    let islandSize: CGSize
    let variant: AttentionAnimationVariant

    private var width: CGFloat { max(islandSize.width, 1) }
    private var height: CGFloat { max(islandSize.height, 1) }

    var topMaskInset: CGFloat {
        height * 0.27
    }

    var baseOutset: CGFloat {
        switch variant {
        case .subtle:
            return height * 0.12
        case .urgentPulse:
            return height * 0.27
        case .goldenAlert:
            return height * 0.33
        case .hyperRipple:
            return height * 0.15
        case .attentionShake:
            return height * 0.18
        }
    }

    func outwardPadding(baseHeightRatio: CGFloat, animatedRatio: CGFloat = 0, phase: CGFloat = 0, extraWidthRatio: CGFloat = 0) -> CGFloat {
        let vertical = height * baseHeightRatio + height * animatedRatio * phase
        let horizontal = extraWidthRatio > 0 ? width * extraWidthRatio : 0
        return -(baseOutset + max(vertical, horizontal))
    }

    func cutoutInsets(for phase: AttentionPulsePhase) -> (horizontal: CGFloat, vertical: CGFloat) {
        switch variant {
        case .subtle:
            return (height * 0.08, height * 0.08)
        case .urgentPulse:
            return (
                max(width * 0.018, height * 0.34) + height * 0.06 * phase.beat,
                height * 0.24 + height * 0.05 * phase.beat
            )
        case .goldenAlert:
            return (
                max(width * 0.022, height * 0.42) + height * 0.08 * phase.goldenBurst,
                height * 0.28 + height * 0.06 * phase.goldenBurst
            )
        case .hyperRipple:
            return (
                max(width * 0.012, height * 0.2),
                height * 0.14
            )
        case .attentionShake:
            return (
                max(width * 0.016, height * 0.24),
                height * 0.18
            )
        }
    }
}

// MARK: - Notch extension shape

struct NotchExtensionShape: Shape {
    let bottomRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let br = bottomRadius
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: rect.maxX, y: 0))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - br, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: br, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: 0, y: rect.maxY - br),
            control: CGPoint(x: 0, y: rect.maxY)
        )
        path.closeSubpath()
        return path
    }
}

// MARK: - Root view

struct NotchRootView: View {
    let viewModel: NotchViewModel

    var body: some View {
        NotchContentView(viewModel: viewModel)
    }
}

// MARK: - Content

struct NotchContentView: View {
    let viewModel: NotchViewModel

    @AppStorage(L10n.languageKey) private var appLanguage = ""
    @State private var languageRefreshID = UUID()
    @AppStorage(AttentionAnimationPreferences.strongEnabledKey) private var strongAttentionAnimationEnabled = false
    @AppStorage(AttentionAnimationPreferences.styleKey) private var strongAttentionAnimationStyleRawValue = AttentionAnimationPreferences.defaultStrongStyle.rawValue

    private var sessionStore: SessionStore { viewModel.sessionStore }
    private var isExpanded: Bool { viewModel.isExpanded }
    private var attentionSessions: [Session] {
        viewModel.attentionSessionIDs.compactMap { sessionStore.sessions[$0] }
    }
    private var showsTransientAttentionPanel: Bool {
        viewModel.attentionPresentation == .transient && !attentionSessions.isEmpty
    }
    private var proactivePopupAutoCollapseDelay: TimeInterval {
        AttentionAnimationPreferences.resolvedProactivePopupAutoCollapseDelay()
    }

    var body: some View {
        let shape = NotchExtensionShape(bottomRadius: isExpanded ? 18 : 10)

        VStack(spacing: 0) {
            capsuleBar

            if isExpanded {
                expandedContent
                    .transition(.opacity)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.black)
        .clipShape(shape)
        .id(languageRefreshID)
        .onReceive(NotificationCenter.default.publisher(for: L10n.languageDidChangeNotification)) { _ in
            languageRefreshID = UUID()
        }
        .overlay {
            if !isExpanded && sessionStore.hasSessionNeedingAttention {
                AttentionBodyBorderView(
                    shape: shape,
                    color: attentionAccentColor,
                    variant: attentionAnimationVariant,
                    islandSize: CGSize(width: viewModel.notchWidth, height: viewModel.notchHeight)
                )
            }
        }
    }

    // MARK: - Collapsed bar

    private var capsuleBar: some View {
        HStack(spacing: 4) {
            PetView(state: derivePetState())
                .frame(width: 15, height: 15)

            Spacer()

            if !sessionStore.activeSessions.isEmpty {
                HStack(spacing: 4) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 5, height: 5)
                    Text("\(sessionStore.activeSessions.count)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white)
                }
            } else {
                Circle()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 4, height: 4)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 33)
    }

    // MARK: - Expanded content

    private var expandedContent: some View {
        VStack(spacing: 0) {
            expandedHeader

            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 0.5)

            if showsTransientAttentionPanel {
                attentionSessionList
            } else {
                sessionList
            }
        }
    }

    private var expandedHeader: some View {
        HStack(spacing: 8) {
            PetView(state: derivePetState())
                .frame(width: 24, height: 24)

            Text(L10n.tr("app.name"))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.white)

            if showsTransientAttentionPanel {
                Text(L10n.tr("notch.attentionPanelTitle", attentionSessions.count))
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(attentionAccentColor.opacity(0.95))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(attentionAccentColor.opacity(0.14))
                    .clipShape(Capsule())
            }

            Spacer()

            Button(action: {
                SettingsWindowController.show()
            }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                    .frame(width: 24, height: 24)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            Button(action: viewModel.onQuit) {
                Image(systemName: "power")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.red.opacity(0.8))
                    .frame(width: 24, height: 24)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var sessionList: some View {
        Group {
            if sessionStore.allSessions.isEmpty {
                Text(L10n.tr("notch.noActiveSessions"))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Color.white.opacity(0.35))
                    .padding(.vertical, 16)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(sessionStore.allSessions) { session in
                            SessionRowView(session: session, onArchive: {
                                sessionStore.archiveSession(session)
                            })
                            .onTapGesture { viewModel.onSessionClick(session) }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
            }
        }
    }

    private var attentionSessionList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(attentionSessions) { session in
                    SessionRowView(
                        session: session,
                        variant: .attention,
                        onMarkRead: { viewModel.onAttentionRead(session) },
                        onArchive: { viewModel.onAttentionArchive(session) }
                    )
                    .onTapGesture { viewModel.onSessionClick(session) }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Helpers

    private var statusColor: Color {
        if sessionStore.sessions.values.contains(where: { $0.status == .needsApproval }) {
            return .red
        } else if sessionStore.hasActiveSession {
            return .green
        } else {
            return .yellow
        }
    }

    private var attentionAccentColor: Color {
        if sessionStore.sessions.values.contains(where: { $0.status == .needsApproval }) {
            return Color(red: 1.0, green: 0.22, blue: 0.18)
        }
        return Color(red: 1.0, green: 0.74, blue: 0.08)
    }

    private var attentionAnimationVariant: AttentionAnimationVariant {
        AttentionAnimationPreferences.resolvedVariant(
            strongEnabled: strongAttentionAnimationEnabled,
            styleRawValue: strongAttentionAnimationStyleRawValue
        )
    }

    private func derivePetState() -> PetState {
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
}

struct AttentionHaloRootView: View {
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    let sideInset: CGFloat
    let topInset: CGFloat
    let bottomInset: CGFloat
    let color: Color
    let variant: AttentionAnimationVariant

    var body: some View {
        ZStack(alignment: .top) {
            AttentionHaloView(
                shape: NotchExtensionShape(bottomRadius: 10),
                color: color,
                variant: variant
            )
            .frame(width: notchWidth, height: notchHeight)
            .padding(.top, topInset)
        }
        .frame(
            width: notchWidth + sideInset * 2,
            height: notchHeight + topInset + bottomInset,
            alignment: .top
        )
        .background(Color.clear)
        .allowsHitTesting(false)
    }
}

private struct AttentionBodyBorderView<S: Shape>: View {
    let shape: S
    let color: Color
    let variant: AttentionAnimationVariant
    let islandSize: CGSize

    private var effectColor: Color { variant.visualColor(fallback: color) }

    var body: some View {
        GeometryReader { proxy in
            let metrics = AttentionEffectMetrics(islandSize: islandSize, variant: variant)

            AttentionPulseTimeline { phase in
                ZStack {
                    bodyLayers(for: phase, metrics: metrics)
                    bodyCutout(for: phase, metrics: metrics)
                        .blendMode(.destinationOut)
                }
                .compositingGroup()
                .offset(x: variant == .attentionShake ? phase.shakeOffset : 0)
                .mask(alignment: .bottom) {
                    Rectangle()
                        .padding(.top, metrics.topMaskInset)
                }
                .allowsHitTesting(false)
            }
        }
    }

    private func bodyCutout(for phase: AttentionPulsePhase, metrics: AttentionEffectMetrics) -> some View {
        let inset = metrics.cutoutInsets(for: phase)

        return shape
            .fill(Color.black)
            .padding(.horizontal, -inset.horizontal)
            .padding(.vertical, -inset.vertical)
    }

    @ViewBuilder
    private func bodyLayers(for phase: AttentionPulsePhase, metrics: AttentionEffectMetrics) -> some View {
        switch variant {
        case .subtle:
            subtleBodyLayers(for: phase, metrics: metrics)
        case .urgentPulse:
            urgentPulseBodyLayers(for: phase, metrics: metrics)
        case .goldenAlert:
            goldenAlertBodyLayers(for: phase, metrics: metrics)
        case .hyperRipple:
            hyperRippleBodyLayers(for: phase, metrics: metrics)
        case .attentionShake:
            attentionShakeBodyLayers(for: phase, metrics: metrics)
        }
    }

    private func subtleBodyLayers(for phase: AttentionPulsePhase, metrics: AttentionEffectMetrics) -> some View {
        ZStack {
            // Solid thin ring border
            shape
                .stroke(
                    effectColor.opacity(0.35 + phase.borderFlash * 0.55),
                    style: StrokeStyle(
                        lineWidth: 1.2 + phase.borderFlash * 1.0,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
                .shadow(color: effectColor.opacity(0.15 + phase.glow * 0.35), radius: 3 + phase.glow * 5)
                .scaleEffect(1.02 + phase.borderExpansion * 0.028)
                .padding(metrics.outwardPadding(baseHeightRatio: 0, animatedRatio: 0.16, phase: phase.borderExpansion))

            // Soft glow border
            shape
                .stroke(effectColor.opacity(0.1 + phase.borderFlash * 0.25), lineWidth: 4.8)
                .blur(radius: 3 + phase.glow * 8)
                .scaleEffect(1.05 + phase.borderExpansion * 0.05)
                .padding(metrics.outwardPadding(baseHeightRatio: 0.06, animatedRatio: 0.18, phase: phase.borderExpansion))

            // Outer glow pulse
            shape
                .stroke(effectColor.opacity(phase.beat * 0.22), lineWidth: 8)
                .blur(radius: 8 + phase.glow * 10)
                .scaleEffect(1.08 + phase.borderExpansion * 0.08)
                .padding(metrics.outwardPadding(baseHeightRatio: 0.15, animatedRatio: 0.24, phase: phase.borderExpansion))
        }
    }

    private func urgentPulseBodyLayers(for phase: AttentionPulsePhase, metrics: AttentionEffectMetrics) -> some View {
        ZStack {
            // Background glow
            shape
                .fill(effectColor.opacity(0.1 + phase.beat * 0.3))
                .blur(radius: 10 + phase.beat * 12)
                .scaleEffect(1.11 + phase.beat * 0.08)
                .padding(metrics.outwardPadding(baseHeightRatio: 0.3, animatedRatio: 0.36, phase: phase.beat))

            // Solid ring border (always visible, pulses brighter)
            shape
                .stroke(
                    effectColor.opacity(0.5 + phase.beat * 0.5),
                    style: StrokeStyle(
                        lineWidth: 2.0 + phase.beat * 1.5,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
                .shadow(color: effectColor.opacity(0.3 + phase.glow * 0.5), radius: 6 + phase.glow * 8)
                .scaleEffect(1.08 + phase.beat * 0.05)
                .padding(metrics.outwardPadding(baseHeightRatio: 0.12, animatedRatio: 0.27, phase: phase.beat))

            // Expanding ripple rings
            ForEach(Array([CGFloat(0.0), 0.11].enumerated()), id: \.offset) { index, delay in
                if let ripple = phase.rippleProgress(delay: delay, activeWindow: 0.34) {
                    shape
                        .stroke(
                            effectColor.opacity((1 - ripple) * (index == 0 ? 0.92 : 0.62)),
                            style: StrokeStyle(lineWidth: max(1.5, 2.5 - ripple * 0.9))
                        )
                        .blur(radius: 1 + ripple * 6)
                        .scaleEffect(1.1 + ripple * (0.24 + CGFloat(index) * 0.07))
                        .padding(
                            metrics.outwardPadding(
                                baseHeightRatio: 0.24 + CGFloat(index) * 0.12,
                                animatedRatio: 0.54,
                                phase: ripple
                            )
                        )
                }
            }
        }
    }

    private func goldenAlertBodyLayers(for phase: AttentionPulsePhase, metrics: AttentionEffectMetrics) -> some View {
        let burst = phase.goldenBurst

        return ZStack {
            // Background glow
            shape
                .fill(effectColor.opacity(0.12 + burst * 0.28))
                .blur(radius: 10 + burst * 10)
                .scaleEffect(1.13 + burst * 0.08)
                .padding(metrics.outwardPadding(baseHeightRatio: 0.36, animatedRatio: 0.36, phase: burst))

            // Ring border – appears on burst, fades between beats
            shape
                .stroke(
                    effectColor.opacity(0.15 + burst * 0.8),
                    style: StrokeStyle(
                        lineWidth: 1.2 + burst * 2.2,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
                .shadow(color: effectColor.opacity(0.1 + burst * 0.6), radius: 4 + burst * 8)
                .scaleEffect(1.02 + burst * 0.06)
                .padding(metrics.outwardPadding(baseHeightRatio: 0.04, animatedRatio: 0.22, phase: burst))

            // Expanding border ring (fades out as it grows, like reference)
            ForEach(Array([CGFloat(0.0), 0.08].enumerated()), id: \.offset) { index, delay in
                if let ripple = phase.rippleProgress(delay: delay, activeWindow: 0.42) {
                    shape
                        .stroke(
                            effectColor.opacity((1 - ripple) * (index == 0 ? 1.0 : 0.7)),
                            style: StrokeStyle(lineWidth: max(1.5, 2.8 - ripple))
                        )
                        .blur(radius: 1 + ripple * 7)
                        .scaleEffect(1.11 + ripple * (0.28 + CGFloat(index) * 0.1))
                        .padding(
                            metrics.outwardPadding(
                                baseHeightRatio: 0.3 + CGFloat(index) * 0.15,
                                animatedRatio: 0.6,
                                phase: ripple
                            )
                        )
                }
            }
        }
    }

    private func hyperRippleBodyLayers(for phase: AttentionPulsePhase, metrics: AttentionEffectMetrics) -> some View {
        ZStack {
            // Solid base ring border
            shape
                .stroke(
                    effectColor.opacity(0.55 + phase.ambient * 0.3),
                    style: StrokeStyle(
                        lineWidth: 1.8 + phase.ambient * 0.6,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
                .shadow(color: effectColor.opacity(0.3 + phase.ambient * 0.35), radius: 5 + phase.ambient * 6)
                .padding(metrics.outwardPadding(baseHeightRatio: 0.03))

            // Background glow fill
            shape
                .fill(effectColor.opacity(0.08 + phase.ambient * 0.12))
                .blur(radius: 8 + phase.ambient * 8)
                .scaleEffect(1.05 + phase.ambient * 0.03)
                .padding(metrics.outwardPadding(baseHeightRatio: 0.15))

            // Continuous wave ripples with shadow
            ForEach(Array(AttentionPulseStyle.hyperRippleDelays.enumerated()), id: \.offset) { index, delay in
                if let ripple = phase.rippleProgress(delay: delay, activeWindow: 0.55) {
                    shape
                        .stroke(
                            effectColor.opacity((1 - ripple) * (index == 0 ? 1.0 : 0.75)),
                            lineWidth: max(1.5, 2.5 - ripple * 0.7)
                        )
                        .shadow(color: effectColor.opacity((1 - ripple) * 0.4), radius: 3 + ripple * 5)
                        .blur(radius: ripple * 4)
                        .scaleEffect(1.02 + ripple * (0.2 + CGFloat(index) * 0.06))
                        .padding(
                            metrics.outwardPadding(
                                baseHeightRatio: 0.12 + CGFloat(index) * 0.09,
                                animatedRatio: 0.42,
                                phase: ripple
                            )
                        )
                }
            }
        }
    }

    private func attentionShakeBodyLayers(for phase: AttentionPulsePhase, metrics: AttentionEffectMetrics) -> some View {
        let burst = max(phase.beat, phase.afterglow)

        return ZStack {
            // Background glow
            shape
                .fill(effectColor.opacity(0.1 + burst * 0.25))
                .blur(radius: 10 + burst * 12)
                .scaleEffect(1.08 + burst * 0.08)
                .padding(metrics.outwardPadding(baseHeightRatio: 0.24, animatedRatio: 0.3, phase: burst))

            // Solid ring border (like reference border-red-500/50 border)
            shape
                .stroke(
                    effectColor.opacity(0.5 + burst * 0.5),
                    style: StrokeStyle(
                        lineWidth: 2.0 + burst * 1.5,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
                .shadow(color: effectColor.opacity(0.3 + burst * 0.5), radius: 6 + burst * 8)
                .padding(metrics.outwardPadding(baseHeightRatio: 0.06, animatedRatio: 0.24, phase: burst))

            // Expanding ripple rings
            ForEach(Array([CGFloat(0.0), 0.18].enumerated()), id: \.offset) { index, delay in
                if let ripple = phase.rippleProgress(delay: delay, activeWindow: 0.4) {
                    shape
                        .stroke(
                            effectColor.opacity((1 - ripple) * (index == 0 ? 0.9 : 0.55)),
                            style: StrokeStyle(lineWidth: max(1.5, 2.5 - ripple * 0.8))
                        )
                        .blur(radius: 1 + ripple * 6)
                        .scaleEffect(1.04 + ripple * (0.18 + CGFloat(index) * 0.08))
                        .padding(
                            metrics.outwardPadding(
                                baseHeightRatio: 0.12 + CGFloat(index) * 0.12,
                                animatedRatio: 0.42,
                                phase: ripple
                            )
                        )
                }
            }
        }
    }
}

private struct AttentionHaloView<S: Shape>: View {
    let shape: S
    let color: Color
    let variant: AttentionAnimationVariant

    private var effectColor: Color { variant.visualColor(fallback: color) }

    var body: some View {
        AttentionPulseTimeline { phase in
            ZStack {
                haloLayers(for: phase)
            }
            .offset(x: variant == .attentionShake ? phase.shakeOffset * 1.2 : 0)
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func haloLayers(for phase: AttentionPulsePhase) -> some View {
        switch variant {
        case .subtle:
            subtleHaloLayers(for: phase)
        case .urgentPulse:
            urgentPulseHaloLayers(for: phase)
        case .goldenAlert:
            goldenAlertHaloLayers(for: phase)
        case .hyperRipple:
            hyperRippleHaloLayers(for: phase)
        case .attentionShake:
            attentionShakeHaloLayers(for: phase)
        }
    }

    private func subtleHaloLayers(for phase: AttentionPulsePhase) -> some View {
        ZStack {
            shape
                .fill(effectColor.opacity(0.06 + phase.glow * 0.12))
                .blur(radius: 8 + phase.glow * 12)
                .scaleEffect(1.04 + phase.glow * 0.08)

            shape
                .stroke(effectColor.opacity(0.2 + phase.borderFlash * 0.3), lineWidth: 2.4)
                .blur(radius: 1 + phase.glow * 4)
                .scaleEffect(1.015 + phase.borderExpansion * 0.02)

            ForEach(Array(AttentionPulseStyle.rippleDelays.enumerated()), id: \.offset) { index, delay in
                if let ripple = phase.rippleProgress(delay: delay) {
                    shape
                        .stroke(
                            effectColor.opacity((1 - ripple) * (index == 0 ? 0.55 : 0.38)),
                            lineWidth: max(1.2, 2.8 - ripple * 1.2)
                        )
                        .blur(radius: 1 + ripple * 12)
                        .scaleEffect(1.02 + ripple * (0.48 + CGFloat(index) * 0.12))
                }
            }
        }
    }

    private func urgentPulseHaloLayers(for phase: AttentionPulsePhase) -> some View {
        ZStack {
            shape
                .fill(effectColor.opacity(0.1 + phase.beat * 0.3 + phase.afterglow * 0.1))
                .blur(radius: 10 + phase.glow * 12)
                .scaleEffect(1.14 + phase.beat * 0.12)

            shape
                .stroke(effectColor.opacity(0.35 + phase.beat * 0.5), lineWidth: 2.6)
                .blur(radius: 2 + phase.glow * 4)
                .scaleEffect(1.1 + phase.beat * 0.06)

            ForEach(Array([CGFloat(0.0), 0.12].enumerated()), id: \.offset) { index, delay in
                if let ripple = phase.rippleProgress(delay: delay, activeWindow: 0.38) {
                    shape
                        .stroke(
                            effectColor.opacity((1 - ripple) * (index == 0 ? 0.9 : 0.6)),
                            lineWidth: max(1.5, 2.8 - ripple)
                        )
                        .blur(radius: 2 + ripple * 10)
                        .scaleEffect(1.12 + ripple * (0.46 + CGFloat(index) * 0.12))
                }
            }
        }
    }

    private func goldenAlertHaloLayers(for phase: AttentionPulsePhase) -> some View {
        let burst = phase.goldenBurst

        return ZStack {
            shape
                .fill(effectColor.opacity(0.12 + burst * 0.28))
                .blur(radius: 10 + burst * 10)
                .scaleEffect(1.16 + burst * 0.1)

            shape
                .stroke(effectColor.opacity(0.3 + burst * 0.5), lineWidth: 2.4)
                .blur(radius: 1 + burst * 4)
                .scaleEffect(1.1 + burst * 0.05)

            ForEach(Array([CGFloat(0.0), 0.08].enumerated()), id: \.offset) { index, delay in
                if let ring = phase.rippleProgress(delay: delay, activeWindow: 0.46) {
                    shape
                        .stroke(effectColor.opacity((1 - ring) * (index == 0 ? 1.0 : 0.7)), lineWidth: max(1.5, 3.0 - ring * 1.1))
                        .blur(radius: 2 + ring * 8)
                        .scaleEffect(1.14 + ring * (0.58 + CGFloat(index) * 0.12))
                }
            }
        }
    }

    private func hyperRippleHaloLayers(for phase: AttentionPulsePhase) -> some View {
        ZStack {
            shape
                .fill(effectColor.opacity(0.1 + phase.ambient * 0.15))
                .blur(radius: 10 + phase.ambient * 8)
                .scaleEffect(1.08 + phase.ambient * 0.06)

            shape
                .stroke(effectColor.opacity(0.3 + phase.ambient * 0.3), lineWidth: 2.2)
                .blur(radius: 1 + phase.ambient * 3)
                .scaleEffect(1.03 + phase.ambient * 0.03)

            ForEach(Array(AttentionPulseStyle.hyperRippleDelays.enumerated()), id: \.offset) { index, delay in
                if let ripple = phase.rippleProgress(delay: delay, activeWindow: 0.62) {
                    shape
                        .stroke(
                            effectColor.opacity((1 - ripple) * (index == 0 ? 1.0 : 0.7)),
                            lineWidth: max(1.5, 2.8 - ripple)
                        )
                        .blur(radius: 1 + ripple * 10)
                        .scaleEffect(1.05 + ripple * (0.66 + CGFloat(index) * 0.12))
                }
            }
        }
    }

    private func attentionShakeHaloLayers(for phase: AttentionPulsePhase) -> some View {
        let burst = max(phase.beat, phase.afterglow)

        return ZStack {
            shape
                .fill(effectColor.opacity(0.12 + burst * 0.28))
                .blur(radius: 10 + burst * 12)
                .scaleEffect(1.1 + burst * 0.1)

            shape
                .stroke(effectColor.opacity(0.35 + burst * 0.5), lineWidth: 2.6)
                .blur(radius: 2 + burst * 5)
                .scaleEffect(1.04 + burst * 0.04)

            ForEach(Array([CGFloat(0.0), 0.18].enumerated()), id: \.offset) { index, delay in
                if let ripple = phase.rippleProgress(delay: delay, activeWindow: 0.44) {
                    shape
                        .stroke(
                            effectColor.opacity((1 - ripple) * (index == 0 ? 0.85 : 0.55)),
                            lineWidth: max(1.5, 2.6 - ripple)
                        )
                        .blur(radius: 2 + ripple * 8)
                        .scaleEffect(1.04 + ripple * (0.44 + CGFloat(index) * 0.12))
                }
            }
        }
    }
}

private extension AttentionAnimationVariant {
    func visualColor(fallback: Color) -> Color {
        // Always use the status-based color passed from the parent view
        return fallback
    }
}
