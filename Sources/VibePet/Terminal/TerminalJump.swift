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
        // Prefer stable tab.id captured at SessionStart. If missing, fall back to
        // matching by working directory. Last resort — just activate the app.
        if let tabId, !tabId.isEmpty {
            let escaped = escapeForAppleScript(tabId)
            let script = """
            tell application "Ghostty"
                activate
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
                return matched
            end tell
            """
            runAppleScript(script)
            return
        }

        if let cwd, !cwd.isEmpty {
            let escaped = escapeForAppleScript(cwd)
            let script = """
            tell application "Ghostty"
                activate
                try
                    set matches to every terminal whose working directory is "\(escaped)"
                    if (count of matches) > 0 then
                        focus (item 1 of matches)
                    end if
                end try
            end tell
            """
            runAppleScript(script)
            return
        }

        activateApp(bundleId: "com.mitchellh.ghostty")
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
}
