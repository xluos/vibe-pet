import Foundation

final class SessionTitleResolver {
    static let shared = SessionTitleResolver()

    private let fileManager = FileManager.default
    private let queue = DispatchQueue(label: "VibePet.SessionTitleResolver", qos: .utility)
    private var cache: [String: String] = [:]
    private var pendingCompletions: [String: [(String?) -> Void]] = [:]

    private init() {}

    func resolveTitle(for session: Session, completion: @escaping (String?) -> Void) {
        let cacheKey = "\(session.source.rawValue):\(session.id)"
        if let cached = cache[cacheKey] {
            completion(cached)
            return
        }

        let source = session.source
        let sessionID = session.id

        queue.async { [weak self] in
            guard let self else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            if self.pendingCompletions[cacheKey] != nil {
                self.pendingCompletions[cacheKey, default: []].append(completion)
                return
            }
            self.pendingCompletions[cacheKey] = [completion]

            let lookupStart = PerfLog.now()
            let title = self.lookupTitle(sessionID: sessionID, source: source)
            if let title, !title.isEmpty {
                self.cache[cacheKey] = title
            }
            let lookupMs = PerfLog.elapsedMS(since: lookupStart)
            let completions = self.pendingCompletions.removeValue(forKey: cacheKey) ?? []

            if lookupMs >= 8 {
                PerfLog.log(
                    "session.title-resolve",
                    "source=\(source.rawValue) session=\(sessionID) found=\(title != nil) totalMs=\(PerfLog.format(lookupMs))"
                )
            }

            DispatchQueue.main.async {
                completions.forEach { $0(title) }
            }
        }
    }

    private func lookupTitle(sessionID: String, source: SessionSource) -> String? {
        switch source {
        case .codex:
            return codexTitle(for: sessionID)
        case .claude:
            return claudeTitle(for: sessionID)
        default:
            return nil
        }
    }

    private func codexTitle(for sessionID: String) -> String? {
        let path = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/session_index.jsonl")
        for line in readLines(at: path) {
            guard let data = line.data(using: String.Encoding.utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = json["id"] as? String,
                  id == sessionID,
                  let title = json["thread_name"] as? String else {
                continue
            }
            return sanitize(title)
        }
        return nil
    }

    private func claudeTitle(for sessionID: String) -> String? {
        let historyPath = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/history.jsonl")
        var firstCandidate: String?

        for line in readLines(at: historyPath) {
            guard let data = line.data(using: String.Encoding.utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = json["sessionId"] as? String,
                  id == sessionID,
                  let display = json["display"] as? String else {
                continue
            }

            let title = sanitize(display)
            guard !title.isEmpty else { continue }

            if firstCandidate == nil {
                firstCandidate = title
            }
            if !isCommandLike(title) {
                return title
            }
        }

        return firstCandidate
    }

    private func sanitize(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isCommandLike(_ text: String) -> Bool {
        text.hasPrefix("/") || text.hasPrefix("<command-message>")
    }

    private func readLines(at path: URL) -> [String] {
        guard let content = try? String(contentsOf: path, encoding: .utf8) else {
            return []
        }
        return content.split(whereSeparator: \.isNewline).map(String.init)
    }
}
