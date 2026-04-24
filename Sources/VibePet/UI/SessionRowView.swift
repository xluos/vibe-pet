import SwiftUI

struct SessionRowView: View {
    let session: Session
    var variant: SessionRowVariant = .standard
    var onMarkRead: (() -> Void)?
    var onArchive: (() -> Void)?
    var onJumpToTerminal: (() -> Void)?
    var onApprovalDecision: ((String) -> Void)?
    @AppStorage(L10n.languageKey) private var appLanguage = ""
    @State private var languageRefreshID = UUID()
    @State private var now = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(alignment: .top, spacing: variant.leadingIconSpacing) {
            Circle()
                .fill(statusColor)
                .frame(width: variant.statusDotSize, height: variant.statusDotSize)
                .padding(.top, variant.statusDotTopInset)

            VStack(alignment: .leading, spacing: variant.verticalSpacing) {
                headerLine
                if let prompt = trimmedPrompt {
                    messagePreviewRow(
                        color: .white.opacity(0.78),
                        weight: .medium,
                        content: L10n.tr("session.prompt.userPrefix", prompt),
                        lineLimit: variant.promptLineLimit
                    )
                }
                if shouldShowAssistantStatus, let message = assistantStatusLabel {
                    messagePreviewRow(
                        color: .white.opacity(0.45),
                        weight: .regular,
                        content: message,
                        lineLimit: variant.statusLineLimit
                    )
                }
                if let assistMessage = trimmedAssistantMessage, !shouldShowAssistantStatus {
                    messagePreviewRow(
                        color: .white.opacity(0.55),
                        weight: .regular,
                        content: assistMessage,
                        lineLimit: variant.bodyLineLimit
                    )
                }
                if let approval = session.pendingApproval {
                    approvalCard(for: approval)
                } else if variant == .attention {
                    attentionActions
                }
            }
        }
        .padding(.horizontal, variant.horizontalPadding)
        .padding(.vertical, variant.verticalPadding)
        .background(
            RoundedRectangle(cornerRadius: variant.cornerRadius)
                .fill(variant == .attention ? Color.clear : Color.white.opacity(0.025))
        )
        .id(languageRefreshID)
        .contentShape(Rectangle())
        // Attach the row-level tap here (not at the call site) so it lives
        // next to the contentShape. At the call site the inner Terminal /
        // approval / archive Buttons could partially shadow tap handling.
        .onTapGesture {
            onJumpToTerminal?()
        }
        .onReceive(timer) { now = $0 }
        .onReceive(NotificationCenter.default.publisher(for: L10n.languageDidChangeNotification)) { _ in
            languageRefreshID = UUID()
        }
    }

    // MARK: - Sub views

    private var headerLine: some View {
        HStack(alignment: .center, spacing: 8) {
            sourceBadge

            Text(titleLabel)
                .font(.system(size: variant.titleFontSize, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 8)

            if onJumpToTerminal != nil {
                terminalButton
            }

            Text(timeAgo)
                .font(.system(size: variant.timeFontSize, weight: .regular, design: .monospaced))
                .foregroundColor(.white.opacity(0.45))
                .lineLimit(1)

            // Hide the row-level acknowledge button while an approval card is
            // showing: tapping it would archive the session and leave the
            // bridge process blocked on the socket forever. The approval
            // buttons below are the only valid exit path.
            if let onArchive,
               session.status != .archived,
               session.pendingApproval == nil,
               variant == .standard {
                Button(action: onArchive) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.55))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var sourceBadge: some View {
        Text(sourceLabel)
            .font(.system(size: variant.badgeFontSize, weight: .semibold))
            .foregroundColor(sourceTextColor)
            .padding(.horizontal, variant.badgeHorizontalPadding)
            .padding(.vertical, variant.badgeVerticalPadding)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(sourceBackgroundColor)
            )
    }

    private var terminalButton: some View {
        Button(action: { onJumpToTerminal?() }) {
            Text(L10n.tr("session.action.terminal"))
                .font(.system(size: variant.terminalButtonFontSize, weight: .regular))
                .foregroundColor(.white.opacity(0.72))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func approvalCard(for approval: PendingApproval) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                Text(approval.toolName ?? L10n.tr("approval.toolUnknown"))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.9))
                if let preview = approval.toolInputPreview, !preview.isEmpty {
                    Text(preview)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(4)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(L10n.tr("approval.inputEmpty"))
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.05))
            )

            HStack(spacing: 8) {
                approvalButton(
                    title: L10n.tr("approval.deny"),
                    fill: Color.white.opacity(0.10),
                    textColor: .white.opacity(0.85),
                    action: { onApprovalDecision?("deny") }
                )
                approvalButton(
                    title: L10n.tr("approval.allowOnce"),
                    fill: Color(red: 1.0, green: 0.78, blue: 0.18),
                    textColor: .black,
                    action: { onApprovalDecision?("allow") }
                )
                approvalButton(
                    title: L10n.tr("approval.allowSession"),
                    fill: Color(red: 0.23, green: 0.70, blue: 0.96),
                    textColor: .black,
                    action: { onApprovalDecision?("allowSession") }
                )
            }
        }
        .padding(.top, 6)
    }

    @ViewBuilder
    private func approvalButton(title: String, fill: Color, textColor: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(textColor)
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(fill)
                )
        }
        .buttonStyle(.plain)
    }

    private var attentionActions: some View {
        HStack(spacing: 10) {
            if let onMarkRead {
                Button(action: onMarkRead) {
                    Text(L10n.tr("session.action.markRead"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
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
                        .frame(height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(red: 1.0, green: 0.78, blue: 0.18))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private func messagePreviewRow(color: Color, weight: Font.Weight, content: String, lineLimit: Int) -> some View {
        Text(content)
            .font(.system(size: variant.bodyFontSize, weight: weight))
            .foregroundColor(color)
            .lineLimit(lineLimit)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Data

    private var sourceLabel: String {
        switch session.source {
        case .claude: return L10n.tr("session.source.claude")
        case .codex: return L10n.tr("session.source.codex")
        case .coco: return L10n.tr("session.source.coco")
        case .unknown: return L10n.tr("session.source.unknown")
        }
    }

    private var sourceBackgroundColor: Color {
        switch session.source {
        case .claude: return Color(red: 0.98, green: 0.55, blue: 0.30).opacity(0.22)
        case .codex: return Color.white.opacity(0.10)
        case .coco: return Color(red: 0.18, green: 0.78, blue: 0.45).opacity(0.22)
        case .unknown: return Color.white.opacity(0.10)
        }
    }

    private var sourceTextColor: Color {
        switch session.source {
        case .claude: return Color(red: 1.0, green: 0.72, blue: 0.45)
        case .codex: return Color.white.opacity(0.75)
        case .coco: return Color(red: 0.35, green: 0.90, blue: 0.58)
        case .unknown: return Color.white.opacity(0.60)
        }
    }

    private var titleLabel: String {
        if let trimmedTitle = session.title?.trimmingCharacters(in: .whitespacesAndNewlines),
           !trimmedTitle.isEmpty,
           trimmedTitle != cwdLabel {
            return trimmedTitle
        }
        return cwdLabel
    }

    private var cwdLabel: String {
        if let cwd = session.cwd {
            return URL(fileURLWithPath: cwd).lastPathComponent
        }
        return session.id.prefix(8).description
    }

    private var trimmedPrompt: String? {
        guard let prompt = session.lastPrompt?.trimmingCharacters(in: .whitespacesAndNewlines),
              !prompt.isEmpty else {
            return nil
        }
        return prompt
    }

    private var trimmedAssistantMessage: String? {
        guard let msg = session.lastAssistantMessage?.trimmingCharacters(in: .whitespacesAndNewlines),
              !msg.isEmpty else {
            return nil
        }
        return msg
    }

    private var shouldShowAssistantStatus: Bool {
        session.status == .waitingForInput || session.status == .needsApproval
    }

    private var assistantStatusLabel: String? {
        switch session.status {
        case .waitingForInput:
            return L10n.tr("session.status.waitingForInput.assistant", assistantName)
        case .needsApproval:
            return L10n.tr("session.status.needsApproval")
        default:
            return nil
        }
    }

    private var assistantName: String {
        switch session.source {
        case .claude: return L10n.tr("session.assistant.claude")
        case .codex: return L10n.tr("session.assistant.codex")
        case .coco: return L10n.tr("session.assistant.coco")
        case .unknown: return L10n.tr("app.name")
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

    private var timeAgo: String {
        let interval = max(0, now.timeIntervalSince(session.lastEventAt))
        let totalSeconds = Int(interval)
        let day = 24 * 3600
        let hour = 3600
        let minute = 60

        if totalSeconds >= day {
            let days = totalSeconds / day
            let hours = (totalSeconds % day) / hour
            return hours > 0 ? "\(days)d \(hours)h" : "\(days)d"
        }
        if totalSeconds >= hour {
            let hours = totalSeconds / hour
            let minutes = (totalSeconds % hour) / minute
            return minutes > 0 ? "\(hours)h\(minutes)m" : "\(hours)h"
        }
        if totalSeconds >= minute {
            let minutes = totalSeconds / minute
            let seconds = totalSeconds % minute
            return seconds > 0 ? "\(minutes)m\(seconds)s" : "\(minutes)m"
        }
        return "\(totalSeconds)s"
    }
}

enum SessionRowVariant {
    case standard
    case attention

    var titleFontSize: CGFloat { self == .attention ? 13 : 12 }
    var badgeFontSize: CGFloat { self == .attention ? 10 : 9 }
    var badgeHorizontalPadding: CGFloat { self == .attention ? 7 : 6 }
    var badgeVerticalPadding: CGFloat { self == .attention ? 3 : 2 }
    var timeFontSize: CGFloat { self == .attention ? 11 : 10 }
    var terminalButtonFontSize: CGFloat { self == .attention ? 11 : 10 }
    var bodyFontSize: CGFloat { self == .attention ? 12 : 11 }
    var bodyLineLimit: Int { self == .attention ? 2 : 1 }
    var promptLineLimit: Int { self == .attention ? 2 : 1 }
    var statusLineLimit: Int { 1 }
    var statusDotSize: CGFloat { self == .attention ? 8 : 7 }
    var statusDotTopInset: CGFloat { self == .attention ? 8 : 6 }
    var leadingIconSpacing: CGFloat { self == .attention ? 10 : 8 }
    var verticalSpacing: CGFloat { self == .attention ? 4 : 3 }
    var horizontalPadding: CGFloat { self == .attention ? 14 : 10 }
    var verticalPadding: CGFloat { self == .attention ? 12 : 8 }
    var cornerRadius: CGFloat { self == .attention ? 12 : 8 }
}
