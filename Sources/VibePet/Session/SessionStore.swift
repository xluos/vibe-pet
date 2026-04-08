import Foundation

@Observable
final class SessionStore {
    var sessions: [String: Session] = [:]
    private let endedSessionRetentionDays = 7

    private static var storePath: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".vibe-pet")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("sessions.json")
    }

    init() {
        load()
        purgeExpiredEndedSessions()
        refreshMissingTitles()
    }

    // MARK: - Computed

    var activeSessions: [Session] {
        sessions.values
            .filter { $0.status != .ended && $0.status != .archived }
            .sorted { $0.lastEventAt > $1.lastEventAt }
    }

    var allSessions: [Session] {
        sessions.values
            .filter { $0.status != .archived }
            .sorted { $0.lastEventAt > $1.lastEventAt }
    }

    var archivedSessions: [Session] {
        sessions.values
            .filter { $0.status == .archived }
            .sorted { $0.lastEventAt > $1.lastEventAt }
    }

    var hasSessionNeedingAttention: Bool {
        sessions.values.contains { $0.status == .needsApproval || $0.status == .waitingForInput }
    }

    var primaryAttentionSession: Session? {
        sessions.values
            .filter { $0.status == .needsApproval || $0.status == .waitingForInput }
            .sorted {
                let lhsPriority = attentionPriority(for: $0.status)
                let rhsPriority = attentionPriority(for: $1.status)
                if lhsPriority != rhsPriority {
                    return lhsPriority > rhsPriority
                }
                return $0.lastEventAt > $1.lastEventAt
            }
            .first
    }

    var hasActiveSession: Bool {
        sessions.values.contains { $0.status == .active || $0.status == .starting }
    }

    // MARK: - Events

    func handleEvent(_ message: BridgeMessage) {
        let source = SessionSource(rawValue: message.source) ?? .unknown
        let session = sessions[message.sessionId] ?? Session(
            id: message.sessionId,
            source: source,
            cwd: message.cwd,
            tty: message.tty,
            terminalBundleId: message.terminalBundleId
        )

        // Revive archived sessions that are still sending events (e.g. app restarted while CLI still running)
        if session.status == .archived && message.hookEvent != "SessionEnd" {
            session.status = .active
        } else if session.status == .archived {
            return
        }

        if let cwd = message.cwd { session.cwd = cwd }
        if let tty = message.tty { session.tty = tty }
        if let bid = message.terminalBundleId { session.terminalBundleId = bid }
        if let tool = message.toolName { session.lastToolName = tool }
        if let prompt = message.prompt { session.lastPrompt = prompt }
        if let assistMsg = message.lastAssistantMessage { session.lastAssistantMessage = assistMsg }
        session.lastEventAt = message.date

        let previousStatus = session.status
        switch message.hookEvent {
        case "SessionStart":
            session.status = .starting
        case "UserPromptSubmit":
            session.status = .active
        case "PreToolUse", "PostToolUse":
            session.status = .active
        case "Stop":
            session.status = .waitingForInput
        case "PermissionRequest":
            session.status = .needsApproval
        case "SessionEnd":
            session.status = .ended
        case "Notification":
            break
        default:
            break
        }

        sessions[message.sessionId] = session
        refreshTitleIfNeeded(for: session)
        save()

        if session.status != previousStatus {
            NotificationCenter.default.post(
                name: .sessionStatusChanged,
                object: nil,
                userInfo: [
                    "sessionId": session.id,
                    "oldStatus": previousStatus.rawValue,
                    "newStatus": session.status.rawValue,
                    "hookEvent": message.hookEvent,
                ]
            )
        }
    }

    func archiveSession(_ session: Session) {
        session.status = .archived
        save()
    }

    func removeSession(_ session: Session) {
        sessions.removeValue(forKey: session.id)
        save()
    }

    // MARK: - Persistence

    private func save() {
        purgeExpiredEndedSessions()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(Array(sessions.values)) else { return }
        try? data.write(to: Self.storePath, options: .atomic)
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.storePath) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let list = try? decoder.decode([Session].self, from: data) else { return }
        for session in list {
            sessions[session.id] = session
        }
    }

    private func refreshMissingTitles() {
        for session in sessions.values where session.title == nil || session.title?.isEmpty == true {
            refreshTitleIfNeeded(for: session)
        }
    }

    private func refreshTitleIfNeeded(for session: Session) {
        guard session.title == nil || session.title?.isEmpty == true else { return }
        guard session.source == .codex || session.source == .claude else { return }

        SessionTitleResolver.shared.resolveTitle(for: session) { [weak self, weak session] title in
            guard let self, let session, let title, !title.isEmpty else { return }
            guard session.title != title else { return }
            session.title = title
            self.save()
        }
    }

    private func purgeExpiredEndedSessions(referenceDate: Date = Date()) {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -endedSessionRetentionDays, to: referenceDate) else {
            return
        }

        sessions = sessions.filter { _, session in
            session.status != .ended || session.lastEventAt >= cutoff
        }
    }

    private func attentionPriority(for status: SessionStatus) -> Int {
        switch status {
        case .needsApproval:
            return 2
        case .waitingForInput:
            return 1
        default:
            return 0
        }
    }
}

extension Notification.Name {
    static let sessionStatusChanged = Notification.Name("VibePet.sessionStatusChanged")
}
