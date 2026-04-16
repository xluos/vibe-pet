import Foundation

enum SessionSource: String, Codable {
    case claude
    case codex
    case coco
    case unknown
}

enum SessionStatus: String, Codable {
    case starting
    case active
    case waitingForInput
    case needsApproval
    case ended
    case archived
}

@Observable
final class Session: Identifiable, Codable {
    let id: String
    let source: SessionSource
    var status: SessionStatus
    var cwd: String?
    var tty: String?
    var terminalBundleId: String?
    var title: String?
    var lastToolName: String?
    var lastPrompt: String?
    var lastAssistantMessage: String?
    var startedAt: Date
    var lastEventAt: Date

    init(
        id: String,
        source: SessionSource,
        status: SessionStatus = .starting,
        cwd: String? = nil,
        tty: String? = nil,
        terminalBundleId: String? = nil,
        startedAt: Date = Date(),
        lastEventAt: Date = Date()
    ) {
        self.id = id
        self.source = source
        self.status = status
        self.cwd = cwd
        self.tty = tty
        self.terminalBundleId = terminalBundleId
        self.startedAt = startedAt
        self.lastEventAt = lastEventAt
    }

    // Codable
    enum CodingKeys: String, CodingKey {
        case id, source, status, cwd, tty, terminalBundleId, title, lastToolName, lastPrompt, lastAssistantMessage, startedAt, lastEventAt
    }

    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        source = try c.decode(SessionSource.self, forKey: .source)
        status = try c.decode(SessionStatus.self, forKey: .status)
        cwd = try c.decodeIfPresent(String.self, forKey: .cwd)
        tty = try c.decodeIfPresent(String.self, forKey: .tty)
        terminalBundleId = try c.decodeIfPresent(String.self, forKey: .terminalBundleId)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        lastToolName = try c.decodeIfPresent(String.self, forKey: .lastToolName)
        lastPrompt = try c.decodeIfPresent(String.self, forKey: .lastPrompt)
        lastAssistantMessage = try c.decodeIfPresent(String.self, forKey: .lastAssistantMessage)
        startedAt = try c.decode(Date.self, forKey: .startedAt)
        lastEventAt = try c.decode(Date.self, forKey: .lastEventAt)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(source, forKey: .source)
        try c.encode(status, forKey: .status)
        try c.encodeIfPresent(cwd, forKey: .cwd)
        try c.encodeIfPresent(tty, forKey: .tty)
        try c.encodeIfPresent(terminalBundleId, forKey: .terminalBundleId)
        try c.encodeIfPresent(title, forKey: .title)
        try c.encodeIfPresent(lastToolName, forKey: .lastToolName)
        try c.encodeIfPresent(lastPrompt, forKey: .lastPrompt)
        try c.encodeIfPresent(lastAssistantMessage, forKey: .lastAssistantMessage)
        try c.encode(startedAt, forKey: .startedAt)
        try c.encode(lastEventAt, forKey: .lastEventAt)
    }
}

struct PersistedSession: Codable {
    let id: String
    let source: SessionSource
    let status: SessionStatus
    let cwd: String?
    let tty: String?
    let terminalBundleId: String?
    let title: String?
    let lastToolName: String?
    let lastPrompt: String?
    let lastAssistantMessage: String?
    let startedAt: Date
    let lastEventAt: Date

    init(_ session: Session) {
        id = session.id
        source = session.source
        status = session.status
        cwd = session.cwd
        tty = session.tty
        terminalBundleId = session.terminalBundleId
        title = session.title
        lastToolName = session.lastToolName
        lastPrompt = session.lastPrompt
        lastAssistantMessage = session.lastAssistantMessage
        startedAt = session.startedAt
        lastEventAt = session.lastEventAt
    }

    func makeSession() -> Session {
        let session = Session(
            id: id,
            source: source,
            status: status,
            cwd: cwd,
            tty: tty,
            terminalBundleId: terminalBundleId,
            startedAt: startedAt,
            lastEventAt: lastEventAt
        )
        session.title = title
        session.lastToolName = lastToolName
        session.lastPrompt = lastPrompt
        session.lastAssistantMessage = lastAssistantMessage
        return session
    }
}
