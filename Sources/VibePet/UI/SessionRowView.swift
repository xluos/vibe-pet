import SwiftUI

struct SessionRowView: View {
    let session: Session
    var variant: SessionRowVariant = .standard
    var onMarkRead: (() -> Void)?
    var onArchive: (() -> Void)?
    @AppStorage(L10n.languageKey) private var appLanguage = ""
    @State private var languageRefreshID = UUID()
    @State private var now = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(sourceBadge)
                    .font(.system(size: variant.badgeFontSize, weight: .bold, design: .monospaced))
                    .foregroundColor(.black)
                    .frame(width: variant.badgeWidth, height: variant.badgeHeight)
                    .background(sourceColor)
                    .clipShape(RoundedRectangle(cornerRadius: 3))

                Circle()
                    .fill(statusColor)
                    .frame(width: variant.statusDotSize, height: variant.statusDotSize)

                HStack(spacing: 4) {
                    Text(cwdLabel)
                        .font(.system(size: variant.titleFontSize, weight: .medium, design: .monospaced))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    if let title = sessionTitle {
                        Text("·")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.gray)

                        Text(title)
                            .font(.system(size: max(variant.titleFontSize - 1, 10)))
                            .foregroundColor(.gray)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Text(timeAgo)
                    .font(.system(size: variant.timeFontSize, design: .monospaced))
                    .foregroundColor(.gray)

                if variant == .standard, let onArchive, session.status != .archived {
                    Button(action: onArchive) {
                        Image(systemName: "archivebox")
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(.plain)
                }
            }

            Text(statusLabel)
                .font(.system(size: variant.statusFontSize, weight: variant == .attention ? .medium : .regular, design: .monospaced))
                .foregroundColor(.gray)
                .lineLimit(1)

            if let prompt = session.lastPrompt, !prompt.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "person.fill")
                        .font(.system(size: variant.metaIconSize))
                        .foregroundColor(.cyan.opacity(0.6))
                    Text(prompt)
                        .font(.system(size: variant.bodyFontSize))
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(variant.bodyLineLimit)
                        .truncationMode(.tail)
                }
            }

            if let response = session.lastAssistantMessage, !response.isEmpty {
                HStack(alignment: .top, spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: variant.metaIconSize))
                        .foregroundColor(.orange.opacity(0.6))
                    Text(response)
                        .font(.system(size: variant.bodyFontSize))
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(variant.bodyLineLimit)
                        .truncationMode(.tail)
                }
            }

            if variant == .attention {
                HStack(spacing: 10) {
                    if let onMarkRead {
                        Button(action: onMarkRead) {
                            Text(L10n.tr("session.action.markRead"))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 34)
                                .background(
                                    RoundedRectangle(cornerRadius: 9)
                                        .fill(Color.white.opacity(0.12))
                                )
                        }
                        .buttonStyle(.plain)
                    }

                    if let onArchive, session.status != .archived {
                        Button(action: onArchive) {
                            Text(L10n.tr("session.action.archive"))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .frame(height: 34)
                                .background(
                                    RoundedRectangle(cornerRadius: 9)
                                        .fill(Color(red: 1.0, green: 0.78, blue: 0.18))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 6)
            }
        }
        .padding(.horizontal, variant.horizontalPadding)
        .padding(.vertical, variant.verticalPadding)
        .background(
            RoundedRectangle(cornerRadius: variant.cornerRadius)
                .fill(variant == .attention ? Color.white.opacity(0.08) : Color.white.opacity(0.05))
        )
        .id(languageRefreshID)
        .contentShape(Rectangle())
        .onReceive(timer) { now = $0 }
        .onReceive(NotificationCenter.default.publisher(for: L10n.languageDidChangeNotification)) { _ in
            languageRefreshID = UUID()
        }
    }

    private var sourceBadge: String {
        switch session.source {
        case .claude: return "CC"
        case .codex: return "CX"
        case .coco: return "CO"
        case .unknown: return "?"
        }
    }

    private var sourceColor: Color {
        switch session.source {
        case .claude: return .orange
        case .codex: return .green
        case .coco: return .blue
        case .unknown: return .gray
        }
    }

    private var statusColor: Color {
        switch session.status {
        case .starting: return .blue
        case .active: return .green
        case .waitingForInput: return .yellow
        case .needsApproval: return .red
        case .ended: return .gray
        case .archived: return .gray.opacity(0.5)
        }
    }

    private var cwdLabel: String {
        if let cwd = session.cwd {
            return URL(fileURLWithPath: cwd).lastPathComponent
        }
        return session.id.prefix(8).description
    }

    private var sessionTitle: String? {
        guard let title = session.title?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else {
            return nil
        }
        if title == cwdLabel {
            return nil
        }
        return title
    }

    private var statusLabel: String {
        switch session.status {
        case .starting: return L10n.tr("session.status.starting")
        case .active:
            if let tool = session.lastToolName {
                return L10n.tr("session.status.usingTool", tool)
            }
            return L10n.tr("session.status.working")
        case .waitingForInput: return L10n.tr("session.status.waitingForInput")
        case .needsApproval: return L10n.tr("session.status.needsApproval")
        case .ended: return L10n.tr("session.status.ended")
        case .archived: return L10n.tr("session.status.archived")
        }
    }

    private var timeAgo: String {
        let interval = now.timeIntervalSince(session.lastEventAt)
        if interval < 60 { return "\(Int(interval))s" }
        if interval < 3600 { return "\(Int(interval / 60))m" }
        return "\(Int(interval / 3600))h"
    }
}

enum SessionRowVariant {
    case standard
    case attention

    var badgeFontSize: CGFloat { self == .attention ? 8 : 7 }
    var badgeWidth: CGFloat { self == .attention ? 26 : 22 }
    var badgeHeight: CGFloat { self == .attention ? 20 : 18 }
    var statusDotSize: CGFloat { self == .attention ? 8 : 6 }
    var titleFontSize: CGFloat { self == .attention ? 12 : 11 }
    var timeFontSize: CGFloat { self == .attention ? 10 : 9 }
    var statusFontSize: CGFloat { self == .attention ? 11 : 9 }
    var metaIconSize: CGFloat { self == .attention ? 9 : 8 }
    var bodyFontSize: CGFloat { self == .attention ? 11 : 10 }
    var bodyLineLimit: Int { 2 }
    var horizontalPadding: CGFloat { self == .attention ? 12 : 8 }
    var verticalPadding: CGFloat { self == .attention ? 10 : 6 }
    var cornerRadius: CGFloat { self == .attention ? 10 : 6 }
}
