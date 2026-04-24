import Foundation

@Observable
final class SessionStore {
    var sessions: [String: Session] = [:]
    private var pendingCodexSessions: [String: Session] = [:]
    private let endedSessionRetentionDays = 7
    private let saveDebounceInterval: TimeInterval = 0.2
    private let persistenceQueue = DispatchQueue(label: "VibePet.SessionStore.Persistence", qos: .utility)
    private var pendingSaveWorkItem: DispatchWorkItem?
    // Codex 启动项目时会并发跑多条内部自动化 session（标题生成 / ambient 建议 / ambient 安全过滤），
    // 它们的 prompt 都是固定模板，这里按 prompt 特征识别后直接丢弃，避免出现多余的会话条目和提示音。
    private let codexInternalPromptFingerprints: [String] = [
        "provide a short title for a task",
        "generate 0 to 3 ambient suggestions",
        "upholding safety and compliance standards for codex ambient suggestions",
    ]
    // Claude Code 的 codex 插件（/codex:* 指令）把 codex CLI 当后台评审器调用，会发出固定模板 prompt。
    // 这类调用不是用户主动开的会话，应当静默过滤，不论宿主终端 bundle 为何。
    private let codexPluginPromptFingerprints: [String] = [
        "you are codex performing an adversarial software review",
        "run a stop-gate review of the previous claude turn",
    ]
    // Stop / SessionEnd 等后续事件通常只带 last_assistant_message，没有 prompt。
    // 记下已经判定为内部自动化的 session id，避免这些事件到来时凭空重新生成一条过滤不掉的会话。
    private var filteredCodexAutomationSessionIds: Set<String> = []
    private let filteredCodexAutomationSessionIdCap = 256

    private static var storePath: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".vibe-pet")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("sessions.json")
    }

    init() {
        load()
        let beforePurgeCount = sessions.count
        purgeInternalCodexAutomationSessions()
        purgeExpiredEndedSessions()
        if sessions.count != beforePurgeCount {
            save(reason: "init-cleanup", immediate: true)
        }
        refreshMissingTitles()
    }

    // MARK: - Computed

    var activeSessions: [Session] {
        sessions.values
            .filter { !isInternalCodexAutomationSession($0) }
            .filter { $0.status != .ended && $0.status != .archived }
            .sorted { $0.lastEventAt > $1.lastEventAt }
    }

    var allSessions: [Session] {
        sessions.values
            .filter { !isInternalCodexAutomationSession($0) }
            .filter { $0.status != .archived }
            .sorted { $0.lastEventAt > $1.lastEventAt }
    }

    var archivedSessions: [Session] {
        sessions.values
            .filter { !isInternalCodexAutomationSession($0) }
            .filter { $0.status == .archived }
            .sorted { $0.lastEventAt > $1.lastEventAt }
    }

    var hasSessionNeedingAttention: Bool {
        sessions.values.contains {
            !isInternalCodexAutomationSession($0) && ($0.status == .needsApproval || $0.status == .waitingForInput)
        }
    }

    var primaryAttentionSession: Session? {
        attentionSessions.first
    }

    var attentionSessions: [Session] {
        sessions.values
            .filter { !isInternalCodexAutomationSession($0) }
            .filter { $0.status == .needsApproval || $0.status == .waitingForInput }
            .sorted {
                let lhsPriority = attentionPriority(for: $0.status)
                let rhsPriority = attentionPriority(for: $1.status)
                if lhsPriority != rhsPriority {
                    return lhsPriority > rhsPriority
                }
                return $0.lastEventAt > $1.lastEventAt
            }
    }

    var hasActiveSession: Bool {
        sessions.values.contains {
            !isInternalCodexAutomationSession($0) && ($0.status == .active || $0.status == .starting)
        }
    }

    // MARK: - Events

    func handleEvent(_ message: BridgeMessage) {
        let handleStart = PerfLog.now()
        if filteredCodexAutomationSessionIds.contains(message.sessionId) {
            sessions.removeValue(forKey: message.sessionId)
            pendingCodexSessions.removeValue(forKey: message.sessionId)
            return
        }

        let effectiveCwd = message.cwd ?? sessions[message.sessionId]?.cwd ?? pendingCodexSessions[message.sessionId]?.cwd
        if DirectoryFilterPreferences.shouldFilter(cwd: effectiveCwd) {
            return
        }

        let source = SessionSource(rawValue: message.source) ?? .unknown
        let isNewSession = sessions[message.sessionId] == nil
        let session = sessions[message.sessionId] ?? pendingCodexSessions[message.sessionId] ?? Session(
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

        // Codex creates an internal "title generation" task before the real task starts.
        // It has its own session id and should not be rendered as a user-facing session.
        if isInternalCodexAutomationSession(session) {
            rememberFilteredCodexAutomationSession(message.sessionId)
            pendingCodexSessions.removeValue(forKey: message.sessionId)
            sessions.removeValue(forKey: message.sessionId)
            save(reason: "drop-internal-title-session")
            PerfLog.log(
                "session.handle-event",
                "event=\(message.hookEvent) session=\(message.sessionId) result=dropInternal totalMs=\(PerfLog.format(PerfLog.elapsedMS(since: handleStart)))"
            )
            return
        }

        if shouldDiscardPendingCodexSession(session, for: message) {
            pendingCodexSessions.removeValue(forKey: message.sessionId)
            return
        }

        if shouldDelayCodexSession(session, for: message) {
            pendingCodexSessions[message.sessionId] = session
            return
        }
        pendingCodexSessions.removeValue(forKey: message.sessionId)

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
        let saveScheduledAt = PerfLog.now()
        save(reason: "event-\(message.hookEvent)")
        let saveScheduleMs = PerfLog.elapsedMS(since: saveScheduledAt)

        let notificationStart = PerfLog.now()
        if session.status != previousStatus || isNewSession {
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

        let totalMs = PerfLog.elapsedMS(since: handleStart)
        let notificationMs = PerfLog.elapsedMS(since: notificationStart)
        if totalMs >= 4 || notificationMs >= 2 || saveScheduleMs >= 1 {
            PerfLog.log(
                "session.handle-event",
                "event=\(message.hookEvent) session=\(message.sessionId) new=\(isNewSession) totalMs=\(PerfLog.format(totalMs)) saveScheduleMs=\(PerfLog.format(saveScheduleMs)) notificationMs=\(PerfLog.format(notificationMs)) status=\(previousStatus.rawValue)->\(session.status.rawValue)"
            )
        }
    }

    func archiveSession(_ session: Session) {
        let previousStatus = session.status
        session.status = .archived
        save(reason: "archive-session")
        NotificationCenter.default.post(
            name: .sessionStatusChanged,
            object: nil,
            userInfo: [
                "sessionId": session.id,
                "oldStatus": previousStatus.rawValue,
                "newStatus": session.status.rawValue,
                "hookEvent": "ArchiveSession",
            ]
        )
    }

    func removeSession(_ session: Session) {
        sessions.removeValue(forKey: session.id)
        save(reason: "remove-session")
    }

    // MARK: - Persistence

    func flushPendingSave(reason: String = "flush") {
        pendingSaveWorkItem?.cancel()
        pendingSaveWorkItem = nil
        let snapshots = makePersistenceSnapshots()
        persistenceQueue.sync {
            persistSnapshots(snapshots, reason: reason)
        }
    }

    private func save(reason: String, immediate: Bool = false) {
        purgeExpiredEndedSessions()
        let snapshots = makePersistenceSnapshots()
        pendingSaveWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self, snapshots] in
            self?.persistSnapshots(snapshots, reason: reason)
        }
        pendingSaveWorkItem = workItem

        if immediate {
            persistenceQueue.sync(execute: workItem)
        } else {
            persistenceQueue.asyncAfter(deadline: .now() + saveDebounceInterval, execute: workItem)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.storePath) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let list = try? decoder.decode([PersistedSession].self, from: data) else { return }
        for session in list {
            let restored = session.makeSession()
            sessions[restored.id] = restored
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
            self.save(reason: "title-refresh")
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

    private func purgeInternalCodexAutomationSessions() {
        sessions = sessions.filter { _, session in
            !isInternalCodexAutomationSession(session)
        }
    }

    // Codex CLI 的 SessionStart 只带元数据、没有 prompt，真实意图要等到第一条 UserPromptSubmit 才能判定。
    // 在此之前先把会话挂起，既能让插件自动化 prompt 在抵达时被静默过滤，也避免正常 CLI 的空启动事件触发提示音。
    private func shouldDelayCodexSession(_ session: Session, for message: BridgeMessage) -> Bool {
        guard session.source == .codex else { return false }

        let hasVisiblePrompt = !(session.lastPrompt?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let hasVisibleAssistantMessage = !(session.lastAssistantMessage?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        return !hasVisiblePrompt && !hasVisibleAssistantMessage
    }

    private func shouldDiscardPendingCodexSession(_ session: Session, for message: BridgeMessage) -> Bool {
        guard pendingCodexSessions[session.id] != nil else { return false }
        guard message.hookEvent == "SessionEnd" else { return false }

        let hasVisiblePrompt = !(session.lastPrompt?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let hasVisibleAssistantMessage = !(session.lastAssistantMessage?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        return !hasVisiblePrompt && !hasVisibleAssistantMessage
    }

    private func isInternalCodexAutomationSession(_ session: Session) -> Bool {
        guard session.source == .codex else { return false }
        let prompt = session.lastPrompt?.lowercased() ?? ""
        let assistantMessage = session.lastAssistantMessage?.lowercased() ?? ""
        let fromCodexApp = session.terminalBundleId == "com.openai.codex"

        let promptMatchesInternalTemplate = codexInternalPromptFingerprints.contains { prompt.contains($0) }
        let promptMatchesPluginTemplate = codexPluginPromptFingerprints.contains { prompt.contains($0) }
        let assistantLooksLikeTitleJSON = assistantMessage.contains("\"title\"")
            && assistantMessage.contains("{")
            && assistantMessage.contains("}")

        // Codex app 还会在 cwd 为 "/" 的伪上下文里跑一些内部脚本（例如返回 {"exclude":[]} 之类的
        // JSON-only 响应）。真实的用户会话一定有具体的项目目录，所以 cwd=="/" 可直接判定为自动化。
        let cwdLooksSynthetic = (session.cwd ?? "").trimmingCharacters(in: .whitespacesAndNewlines) == "/"

        // Codex 内部自动化 session 满足以下任一条件：
        // 1) 来自 Codex app 且 prompt / assistant / cwd 命中已知自动化特征。
        // 2) prompt 命中 app 内部模板且 assistant 呈 JSON title 响应（兼容仅见到 Stop 事件的 title 会话）。
        // 3) prompt 命中 codex 插件模板（如 adversarial-review / stop-review-gate），此时与宿主 bundle 无关。
        return (fromCodexApp && (promptMatchesInternalTemplate || assistantLooksLikeTitleJSON || cwdLooksSynthetic))
            || (promptMatchesInternalTemplate && assistantLooksLikeTitleJSON)
            || promptMatchesPluginTemplate
    }

    private func rememberFilteredCodexAutomationSession(_ sessionId: String) {
        filteredCodexAutomationSessionIds.insert(sessionId)
        guard filteredCodexAutomationSessionIds.count > filteredCodexAutomationSessionIdCap else { return }
        let overflow = filteredCodexAutomationSessionIds.count - filteredCodexAutomationSessionIdCap / 2
        for _ in 0..<overflow {
            guard let victim = filteredCodexAutomationSessionIds.first else { break }
            filteredCodexAutomationSessionIds.remove(victim)
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

    private func makePersistenceSnapshots() -> [PersistedSession] {
        Array(sessions.values).map(PersistedSession.init)
    }

    private func persistSnapshots(_ snapshots: [PersistedSession], reason: String) {
        let persistStart = PerfLog.now()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let data = try? encoder.encode(snapshots) else {
            PerfLog.log("session.persist", "reason=\(reason) status=encode-failed count=\(snapshots.count)")
            return
        }

        do {
            try data.write(to: Self.storePath, options: .atomic)
            let totalMs = PerfLog.elapsedMS(since: persistStart)
            if totalMs >= 4 {
                PerfLog.log(
                    "session.persist",
                    "reason=\(reason) count=\(snapshots.count) bytes=\(data.count) totalMs=\(PerfLog.format(totalMs))"
                )
            }
        } catch {
            PerfLog.log("session.persist", "reason=\(reason) status=write-failed error=\(error)")
        }
    }
}

extension Notification.Name {
    static let sessionStatusChanged = Notification.Name("VibePet.sessionStatusChanged")
}
