import Foundation
import AppKit

enum TerminalJump {
    static func jump(to session: Session) {
        guard let bundleId = session.terminalBundleId else {
            // Fallback: try Terminal.app
            activateApp(bundleId: "com.apple.Terminal")
            return
        }

        switch bundleId {
        case "com.apple.Terminal":
            jumpToTerminalApp(tty: session.tty)
        case "com.googlecode.iterm2":
            jumpToITerm(tty: session.tty)
        case "com.mitchellh.ghostty":
            jumpToGhostty(tabId: session.terminalTabId, cwd: session.cwd)
        default:
            activateApp(bundleId: bundleId)
        }
    }

    private static func jumpToTerminalApp(tty: String?) {
        if let tty {
            let script = """
            tell application "Terminal"
                repeat with w in windows
                    repeat with t in tabs of w
                        if tty of t is "\(tty)" then
                            set selected tab of w to t
                            set index of w to 1
                        end if
                    end repeat
                end repeat
                activate
            end tell
            """
            runAppleScript(script)
        } else {
            activateApp(bundleId: "com.apple.Terminal")
        }
    }

    private static func jumpToITerm(tty: String?) {
        if let tty {
            let script = """
            tell application "iTerm2"
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if tty of s is "\(tty)" then
                                select t
                                tell w to select
                            end if
                        end repeat
                    end repeat
                end repeat
                activate
            end tell
            """
            runAppleScript(script)
        } else {
            activateApp(bundleId: "com.googlecode.iterm2")
        }
    }

    private static func jumpToGhostty(tabId: String?, cwd: String?) {
        // One osascript invocation: try tab.id first (stable identifier
        // captured at SessionStart), fall back to working-directory match,
        // otherwise just activate the app. Runs async on a background queue
        // so the UI doesn't hitch on the 50-200ms osascript round-trip;
        // logs the outcome so silent mismatches are diagnosable via
        // `log stream --predicate 'subsystem contains "VibePet"'`.
        let tabClause: String
        if let tabId, !tabId.isEmpty {
            let escaped = escapeForAppleScript(tabId)
            tabClause = """
                set matched to false
                repeat with w in windows
                    repeat with t in tabs of w
                        try
                            if (id of t as text) is equal to "\(escaped)" then
                                select t
                                set matched to true
                                exit repeat
                            end if
                        end try
                    end repeat
                    if matched then exit repeat
                end repeat
                if matched then return "tab"
            """
        } else {
            tabClause = ""
        }

        let cwdClause: String
        if let cwd, !cwd.isEmpty {
            let escaped = escapeForAppleScript(cwd)
            cwdClause = """
                try
                    set matches to every terminal whose working directory is "\(escaped)"
                    if (count of matches) > 0 then
                        focus (item 1 of matches)
                        return "cwd"
                    end if
                end try
            """
        } else {
            cwdClause = ""
        }

        let script = """
        tell application "Ghostty"
            activate
        \(tabClause)
        \(cwdClause)
            return "none"
        end tell
        """

        runAppleScriptLogging(script, label: "ghostty tabId=\(tabId ?? "nil") cwd=\(cwd ?? "nil")")
    }

    private static func escapeForAppleScript(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
             .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func activateApp(bundleId: String) {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first {
            app.activate()
        }
    }

    private static func runAppleScript(_ source: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", source]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()
        }
    }

    /// Async variant that logs the stdout for diagnostics. Use for AppleScript
    /// invocations where the outcome is non-obvious (e.g. silent Ghostty tab
    /// mismatch) so `/tmp/vibe-pet-server.log`-style tails can reveal why a
    /// click did nothing.
    private static func runAppleScriptLogging(_ source: String, label: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", source]
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
            } catch {
                NSLog("[VibePet][\(label)] osascript launch failed: \(error)")
                return
            }
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let out = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            NSLog("[VibePet][\(label)] status=\(process.terminationStatus) output=\(out)")
        }
    }
}
