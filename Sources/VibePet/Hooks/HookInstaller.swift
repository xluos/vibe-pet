import Foundation
import TOMLKit

final class HookInstaller {
    private var bridgeCommand: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.vibe-pet/bin/vibe-pet-bridge"
    }

    func installAll() {
        do {
            try installClaudeHooks()
            print("[VibePet] Claude Code hooks installed")
        } catch {
            print("[VibePet] Failed to install Claude hooks: \(error)")
        }

        do {
            try installCodexHooks()
            print("[VibePet] Codex hooks installed")
        } catch {
            print("[VibePet] Failed to install Codex hooks: \(error)")
        }

        do {
            try installCocoHooks()
            print("[VibePet] Coco hooks installed")
        } catch {
            print("[VibePet] Failed to install Coco hooks: \(error)")
        }

        UserDefaults.standard.set(true, forKey: "vibepet.hooksInstalled")
    }

    func uninstallAll() {
        do { try uninstallClaudeHooks(); print("[VibePet] Claude hooks removed") }
        catch { print("[VibePet] Failed to remove Claude hooks: \(error)") }

        do { try uninstallCodexHooks(); print("[VibePet] Codex hooks removed") }
        catch { print("[VibePet] Failed to remove Codex hooks: \(error)") }

        do { try uninstallCocoHooks(); print("[VibePet] Coco hooks removed") }
        catch { print("[VibePet] Failed to remove Coco hooks: \(error)") }

        UserDefaults.standard.set(false, forKey: "vibepet.hooksInstalled")
    }

    /// Only install if not explicitly uninstalled by user
    func installIfNeeded() {
        // First launch (key doesn't exist) or previously installed → install
        let key = "vibepet.hooksInstalled"
        if UserDefaults.standard.object(forKey: key) == nil || UserDefaults.standard.bool(forKey: key) {
            installAll()
        } else {
            print("[VibePet] Hooks previously uninstalled by user, skipping auto-install")
        }
    }

    /// Check if Codex hooks need user confirmation (directory exists but hooks disabled)
    func needsCodexHooksConfirmation() -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let codexDir = home.appendingPathComponent(".codex")

        guard FileManager.default.fileExists(atPath: codexDir.path) else {
            return false
        }

        let configPath = codexDir.appendingPathComponent("config.toml")
        guard FileManager.default.fileExists(atPath: configPath.path) else {
            return false
        }

        return !isCodexHooksEnabled(at: configPath)
    }

    // MARK: - Claude Code (~/.claude/settings.json)

    private func installClaudeHooks() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".claude")
        guard FileManager.default.fileExists(atPath: dir.path) else {
            print("[VibePet] ~/.claude not found, skipping Claude hooks")
            return
        }
        let settingsPath = dir.appendingPathComponent("settings.json")

        var config = readJSON(at: settingsPath) ?? [:]

        // Create backup
        backup(file: settingsPath)

        // Get or create hooks dict
        var hooks = config["hooks"] as? [String: Any] ?? [:]

        let claudeEvents = [
            "SessionStart", "SessionEnd", "Stop", "PermissionRequest",
            "Notification", "UserPromptSubmit", "PreToolUse", "PostToolUse",
        ]

        for event in claudeEvents {
            let timeout: Int = event == "PermissionRequest" ? 86400 : 10
            hooks[event] = mergeHookEntry(
                existing: hooks[event] as? [[String: Any]] ?? [],
                command: "\(bridgeCommand) --source claude",
                timeout: timeout
            )
        }

        config["hooks"] = hooks
        try writeJSON(config, to: settingsPath)
    }

    // MARK: - Codex (~/.codex/hooks.json + config.toml)

    private func installCodexHooks() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".codex")
        guard FileManager.default.fileExists(atPath: dir.path) else {
            print("[VibePet] ~/.codex not found, skipping Codex hooks")
            return
        }

        // Check if hooks are explicitly disabled in config.toml
        let configPath = dir.appendingPathComponent("config.toml")
        if FileManager.default.fileExists(atPath: configPath.path) {
            if !isCodexHooksEnabled(at: configPath) {
                print("[VibePet] Codex hooks explicitly disabled in config.toml, skipping")
                // Store pending state for UI to prompt user
                UserDefaults.standard.set(true, forKey: "vibepet.codexHooksPending")
                return
            }
        }

        let hooksPath = dir.appendingPathComponent("hooks.json")

        var config = readJSON(at: hooksPath) ?? [:]

        backup(file: hooksPath)

        var hooks = config["hooks"] as? [String: Any] ?? [:]

        let codexEvents = ["SessionStart", "UserPromptSubmit", "Stop"]

        for event in codexEvents {
            hooks[event] = mergeHookEntry(
                existing: hooks[event] as? [[String: Any]] ?? [],
                command: "\(bridgeCommand) --source codex",
                timeout: 5
            )
        }

        config["hooks"] = hooks
        try writeJSON(config, to: hooksPath)

        // Clear pending state
        UserDefaults.standard.removeObject(forKey: "vibepet.codexHooksPending")
    }

    /// Enable Codex hooks by modifying both config.toml and hooks.json
    func enableCodexHooks() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".codex")
        let configPath = dir.appendingPathComponent("config.toml")

        guard FileManager.default.fileExists(atPath: configPath.path) else {
            throw NSError(domain: "VibePet", code: 1, userInfo: [NSLocalizedDescriptionKey: "config.toml not found"])
        }

        // Enable hooks in config.toml
        try enableCodexHooksInConfig(at: configPath)

        // Install hooks to hooks.json
        try installCodexHooks()
    }

    /// Check if hooks are enabled in Codex config.toml
    /// Returns true only if [features] codex_hooks = true is explicitly set
    func isCodexHooksEnabled(at url: URL) -> Bool {
        guard let content = try? String(contentsOf: url, encoding: .utf8),
              let table = try? TOMLTable(string: content) else {
            return false
        }

        // Check [features] section for codex_hooks
        if let featuresTable = table["features"]?.table,
           let enabled = featuresTable["codex_hooks"]?.bool {
            return enabled
        }

        // No config or no codex_hooks → disabled by default
        return false
    }

    /// Enable hooks in Codex config.toml
    private func enableCodexHooksInConfig(at url: URL) throws {
        backup(file: url)

        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            throw NSError(domain: "VibePet", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to read config.toml"])
        }

        let table = (try? TOMLTable(string: content)) ?? TOMLTable()

        // Get or create [features] section
        let featuresTable = table["features"]?.table ?? TOMLTable()
        featuresTable["codex_hooks"] = true
        table["features"] = featuresTable

        // Write back
        let newContent = table.convert(to: .toml)
        try newContent.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Helpers

    // MARK: - Coco / Trae CLI (~/.trae/traecli.yaml)

    private func installCocoHooks() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".trae")
        guard FileManager.default.fileExists(atPath: dir.path) else {
            print("[VibePet] ~/.trae not found, skipping Coco hooks")
            return
        }
        let yamlPath = dir.appendingPathComponent("traecli.yaml")

        backup(file: yamlPath)

        var content = (try? String(contentsOf: yamlPath, encoding: .utf8)) ?? ""

        // First remove any existing vibe-pet hook block
        content = removeCocoVibePetBlock(from: content)

        // Append our hook entry to the hooks array
        let hookBlock = """
          - type: command
            command: '\(bridgeCommand) --source coco'
            matchers:
              - event: user_prompt_submit
              - event: post_tool_use
              - event: stop
              - event: subagent_stop
        """

        if content.contains("\nhooks:") || content.hasPrefix("hooks:") {
            // Append to existing hooks array
            content += "\n" + hookBlock + "\n"
        } else {
            // Create hooks section
            content += "\nhooks:\n" + hookBlock + "\n"
        }

        try content.write(to: yamlPath, atomically: true, encoding: .utf8)
    }

    private func uninstallCocoHooks() throws {
        let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".trae/traecli.yaml")
        guard let content = try? String(contentsOf: path, encoding: .utf8) else { return }
        guard content.contains("vibe-pet-bridge") else { return }
        backup(file: path)

        let cleaned = removeCocoVibePetBlock(from: content)
        try cleaned.write(to: path, atomically: true, encoding: .utf8)
    }

    /// Remove the vibe-pet hook block from Coco YAML content
    private func removeCocoVibePetBlock(from content: String) -> String {
        let lines = content.components(separatedBy: "\n")
        var result: [String] = []
        var i = 0

        while i < lines.count {
            let line = lines[i]

            // Detect start of a hook entry: "  - type: command"
            // Then look ahead to see if it contains vibe-pet-bridge
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("- type: command") {
                // Collect this entire hook block
                var block: [String] = [line]
                let baseIndent = line.prefix(while: { $0 == " " }).count
                var j = i + 1

                while j < lines.count {
                    let nextLine = lines[j]
                    let trimmed = nextLine.trimmingCharacters(in: .whitespaces)
                    if trimmed.isEmpty { j += 1; continue }
                    let indent = nextLine.prefix(while: { $0 == " " }).count
                    // If indent is greater than base, it's part of this block
                    // If it's another "- type:" at same level, it's a new block
                    if indent > baseIndent || (indent == baseIndent && !trimmed.hasPrefix("- ")) {
                        block.append(nextLine)
                        j += 1
                    } else {
                        break
                    }
                }

                let blockText = block.joined(separator: "\n")
                if blockText.contains("vibe-pet-bridge") || blockText.contains("VibePet") {
                    // Skip this block (also skip preceding comment)
                    if let last = result.last, last.contains("VibePet") {
                        result.removeLast()
                    }
                    i = j
                    continue
                } else if blockText.trimmingCharacters(in: .whitespacesAndNewlines) == "- type: command" {
                    // Empty/orphaned entry, skip it
                    i = j
                    continue
                } else {
                    result.append(contentsOf: block)
                    i = j
                    continue
                }
            }

            // Skip standalone VibePet comment lines
            if line.contains("# VibePet") {
                i += 1
                continue
            }

            result.append(line)
            i += 1
        }

        // Clean up trailing empty lines
        while result.last?.trimmingCharacters(in: .whitespaces).isEmpty == true && result.count > 1 {
            result.removeLast()
        }

        return result.joined(separator: "\n") + "\n"
    }

    private func isVibePetCommand(_ cmd: String?) -> Bool {
        guard let cmd else { return false }
        return cmd.contains("vibe-pet-bridge") || cmd.contains("vibe-cat-bridge")
    }

    private func uninstallClaudeHooks() throws {
        let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
        guard var config = readJSON(at: path) else { return }
        guard var hooks = config["hooks"] as? [String: Any] else { return }
        backup(file: path)
        for key in hooks.keys {
            if var entries = hooks[key] as? [[String: Any]] {
                entries.removeAll { entry in
                    guard let h = entry["hooks"] as? [[String: Any]] else { return false }
                    return h.contains { isVibePetCommand($0["command"] as? String) }
                }
                hooks[key] = entries.isEmpty ? nil : entries
            }
        }
        config["hooks"] = hooks.isEmpty ? nil : hooks
        try writeJSON(config, to: path)
    }

    private func uninstallCodexHooks() throws {
        let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/hooks.json")
        guard var config = readJSON(at: path) else { return }
        guard var hooks = config["hooks"] as? [String: Any] else { return }
        backup(file: path)
        for key in hooks.keys {
            if var entries = hooks[key] as? [[String: Any]] {
                entries.removeAll { entry in
                    guard let h = entry["hooks"] as? [[String: Any]] else { return false }
                    return h.contains { isVibePetCommand($0["command"] as? String) }
                }
                hooks[key] = entries.isEmpty ? nil : entries
            }
        }
        config["hooks"] = hooks.isEmpty ? nil : hooks
        try writeJSON(config, to: path)
    }

    // MARK: - Helpers (JSON)

    /// Merge our hook entry into existing entries without removing others
    private func mergeHookEntry(existing: [[String: Any]], command: String, timeout: Int) -> [[String: Any]] {
        let vibePetHook: [String: Any] = [
            "type": "command",
            "command": command,
            "timeout": timeout,
        ]

        let vibePetEntry: [String: Any] = [
            "matcher": "*",
            "hooks": [vibePetHook],
        ]

        // Check if we already have a vibe-pet entry
        var entries = existing
        if let idx = entries.firstIndex(where: { entry in
            guard let hooks = entry["hooks"] as? [[String: Any]] else { return false }
            return hooks.contains { hook in
                (hook["command"] as? String)?.contains("vibe-pet-bridge") == true
            }
        }) {
            entries[idx] = vibePetEntry
        } else {
            entries.append(vibePetEntry)
        }

        return entries
    }

    private func readJSON(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }

    private func writeJSON(_ dict: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(
            withJSONObject: dict,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: url, options: .atomic)
    }

    private func backup(file url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let backupURL = url.appendingPathExtension("vibe-pet-backup")
        try? FileManager.default.removeItem(at: backupURL)
        try? FileManager.default.copyItem(at: url, to: backupURL)
    }
}
