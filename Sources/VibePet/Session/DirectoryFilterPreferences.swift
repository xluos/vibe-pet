import Foundation

struct DirectoryFilterRule: Codable, Identifiable, Equatable {
    let id: UUID
    var pattern: String
    var isRegex: Bool
    var enabled: Bool

    init(id: UUID = UUID(), pattern: String = "", isRegex: Bool = false, enabled: Bool = true) {
        self.id = id
        self.pattern = pattern
        self.isRegex = isRegex
        self.enabled = enabled
    }
}

enum DirectoryFilterPreferences {
    static let rulesKey = "vibepet.directoryFilterRules"
    static let rulesDidChangeNotification = Notification.Name("vibepet.directoryFilterRulesDidChange")

    static func loadRules(defaults: UserDefaults = .standard) -> [DirectoryFilterRule] {
        guard let data = defaults.data(forKey: rulesKey) else { return [] }
        return (try? JSONDecoder().decode([DirectoryFilterRule].self, from: data)) ?? []
    }

    static func saveRules(_ rules: [DirectoryFilterRule], defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(rules) else { return }
        defaults.set(data, forKey: rulesKey)
        NotificationCenter.default.post(name: rulesDidChangeNotification, object: nil)
    }

    static func shouldFilter(cwd: String?, defaults: UserDefaults = .standard) -> Bool {
        guard let cwd, !cwd.isEmpty else { return false }
        let normalized = normalizePath(cwd)
        let rules = loadRules(defaults: defaults)
        for rule in rules where rule.enabled {
            let pattern = rule.pattern.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !pattern.isEmpty else { continue }
            if rule.isRegex {
                if matchesRegex(pattern: pattern, in: normalized) { return true }
            } else {
                if normalized.range(of: normalizePath(pattern), options: .caseInsensitive) != nil {
                    return true
                }
            }
        }
        return false
    }

    private static func normalizePath(_ path: String) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        if expanded.count > 1 && expanded.hasSuffix("/") {
            return String(expanded.dropLast())
        }
        return expanded
    }

    private static func matchesRegex(pattern: String, in text: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return false
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }
}
