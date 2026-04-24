import Foundation

/// Persisted cross-process flag controlling whether VibePet's approval cards
/// intercept Claude / Codex `PermissionRequest` hooks. Stored as a plain
/// file under `~/.vibe-pet/` so the Bridge subprocess can read it without
/// sharing a UserDefaults suite with the app.
enum ApprovalPreferences {
    static let flagRelativePath = ".vibe-pet/approval-intercept-enabled"

    private static var flagURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(flagRelativePath)
    }

    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: flagURL.path)
    }

    static func setEnabled(_ on: Bool) {
        let url = flagURL
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        if on {
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: Data())
            }
        } else {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
