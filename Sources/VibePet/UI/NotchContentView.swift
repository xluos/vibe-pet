import SwiftUI

// MARK: - Notch extension shape

private enum AttentionPulseStyle {
    static let animation = Animation.easeOut(duration: 1.28).repeatForever(autoreverses: false)
}

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

    private var sessionStore: SessionStore { viewModel.sessionStore }
    private var isExpanded: Bool { viewModel.isExpanded }

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
        .overlay {
            if !isExpanded && sessionStore.hasSessionNeedingAttention {
                AttentionBodyBorderView(
                    shape: shape,
                    color: attentionAccentColor
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
            // Header with pet, title, settings & quit
            expandedHeader

            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 0.5)

            sessionList
        }
    }

    private var expandedHeader: some View {
        HStack(spacing: 8) {
            PetView(state: derivePetState())
                .frame(width: 24, height: 24)

            Text("VibePet")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.white)

            Spacer()

            // Settings button — opens separate window
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

            // Quit button
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
                Text("No active sessions")
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

    var body: some View {
        ZStack(alignment: .top) {
            AttentionHaloView(
                shape: NotchExtensionShape(bottomRadius: 10),
                color: color
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

    @State private var isAnimating = false

    private let topMaskInset: CGFloat = 9
    private let baseOutset: CGFloat = 3

    var body: some View {
        ZStack {
            shape
                .stroke(
                    color.opacity(isAnimating ? 0.22 : 0.88),
                    style: StrokeStyle(
                        lineWidth: isAnimating ? 1.0 : 1.7,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
                .shadow(color: color.opacity(isAnimating ? 0.1 : 0.34), radius: isAnimating ? 4 : 7)
                .scaleEffect(isAnimating ? 1.04 : 1.02)
                .padding(-baseOutset)

            shape
                .stroke(color.opacity(isAnimating ? 0.0 : 0.26), lineWidth: 5.5)
                .blur(radius: isAnimating ? 10 : 4)
                .scaleEffect(isAnimating ? 1.08 : 1.04)
                .padding(-(baseOutset + 1))
        }
        .mask(alignment: .bottom) {
            Rectangle()
                .padding(.top, topMaskInset)
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(AttentionPulseStyle.animation) {
                isAnimating = true
            }
        }
    }
}

private struct AttentionHaloView<S: Shape>: View {
    let shape: S
    let color: Color

    @State private var isAnimating = false

    var body: some View {
        ZStack {
            shape
                .stroke(color.opacity(isAnimating ? 0.0 : 1), lineWidth: 2.6)
                .scaleEffect(isAnimating ? 1.34 : 1.03)
                .blur(radius: isAnimating ? 14 : 4)

            shape
                .stroke(color.opacity(isAnimating ? 0.0 : 0.7), lineWidth: 4.5)
                .scaleEffect(isAnimating ? 1.62 : 1.1)
                .blur(radius: isAnimating ? 26 : 7)

            shape
                .stroke(color.opacity(isAnimating ? 0.0 : 0.4), lineWidth: 8)
                .scaleEffect(isAnimating ? 1.84 : 1.16)
                .blur(radius: isAnimating ? 40 : 10)
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(AttentionPulseStyle.animation) {
                isAnimating = true
            }
        }
    }
}
