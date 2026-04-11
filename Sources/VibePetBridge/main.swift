import Foundation

// MARK: - VibePetBridge CLI
// Invoked by Claude Code / Codex hooks. Reads stdin + env, sends JSON to the main app via Unix socket.

let logFile = "/tmp/vibe-pet-bridge.log"

func log(_ msg: String) {
    let ts = ISO8601DateFormatter().string(from: Date())
    let line = "[\(ts)] \(msg)\n"
    if let fh = FileHandle(forWritingAtPath: logFile) {
        fh.seekToEndOfFile()
        fh.write(Data(line.utf8))
        fh.closeFile()
    } else {
        FileManager.default.createFile(atPath: logFile, contents: Data(line.utf8))
    }
}

func normalizeEvent(_ event: String) -> String {
    // Normalize various event name formats to our internal PascalCase names
    switch event.lowercased() {
    case "sessionstart", "session_start": return "SessionStart"
    case "sessionend", "session_end": return "SessionEnd"
    case "stop": return "Stop"
    case "userpromptsubmit", "user_prompt_submit": return "UserPromptSubmit"
    case "pretooluse", "pre_tool_use": return "PreToolUse"
    case "posttooluse", "post_tool_use": return "PostToolUse"
    case "permissionrequest", "permission_request": return "PermissionRequest"
    case "notification": return "Notification"
    case "subagent_stop", "subagentstop": return "Stop"
    default: return event
    }
}

func main() {
    let args = CommandLine.arguments
    log("Bridge started, args: \(args)")

    // Parse --source flag
    var source = "unknown"
    if let idx = args.firstIndex(of: "--source"), idx + 1 < args.count {
        source = args[idx + 1]
    }

    // Read stdin (hook context JSON from Claude Code / Codex)
    var stdinData = Data()
    while let line = readLine(strippingNewline: false) {
        stdinData.append(Data(line.utf8))
    }
    log("Read \(stdinData.count) bytes from stdin")
    if let stdinStr = String(data: stdinData, encoding: .utf8) {
        log("stdin: \(stdinStr.prefix(500))")
    }

    // Parse hook event name from stdin JSON
    var hookEvent = "Unknown"
    var sessionId: String?
    var toolName: String?
    var prompt: String?
    var lastAssistantMessage: String?
    var transcriptPath: String?

    if let json = try? JSONSerialization.jsonObject(with: stdinData) as? [String: Any] {
        if let event = json["hookEventName"] as? String ?? json["hook_event_name"] as? String ?? json["event"] as? String {
            hookEvent = normalizeEvent(event)
        }
        if let sid = json["sessionId"] as? String ?? json["session_id"] as? String ?? json["conversation_id"] as? String {
            sessionId = sid
        }
        if let tool = json["toolName"] as? String ?? json["tool_name"] as? String {
            toolName = tool
        }
        if let p = json["prompt"] as? String {
            // Truncate to 200 chars to keep message small
            prompt = String(p.prefix(200))
        }
        if let msg = json["last_assistant_message"] as? String ?? json["lastAssistantMessage"] as? String {
            lastAssistantMessage = String(msg.prefix(300))
        }
        if let path = json["transcript_path"] as? String ?? json["transcriptPath"] as? String {
            transcriptPath = path
        }
    }

    // Collect environment variables
    let env = ProcessInfo.processInfo.environment
    if sessionId == nil {
        sessionId = env["CLAUDE_SESSION_ID"] ?? env["CLAUDE_CONVERSATION_ID"] ?? env["CODEX_SESSION_ID"]
    }

    // If still no session ID, generate one from PID chain
    if sessionId == nil {
        sessionId = "pid-\(ProcessInfo.processInfo.processIdentifier)"
    }

    let tty = detectTTY()
    let terminalBundleId = env["__CFBundleIdentifier"] ?? detectTerminalBundleId(from: env)
    let cwd = env["CLAUDE_CWD"] ?? env["PWD"]

    // Build message
    let message: [String: Any?] = [
        "sessionId": sessionId,
        "hookEvent": hookEvent,
        "source": source,
        "cwd": cwd,
        "tty": tty,
        "terminalBundleId": terminalBundleId,
        "toolName": toolName,
        "prompt": prompt,
        "lastAssistantMessage": lastAssistantMessage,
        "transcriptPath": transcriptPath,
        "timestamp": Date().timeIntervalSince1970,
    ]

    // Filter nil values
    let filtered = message.compactMapValues { $0 }

    guard let jsonData = try? JSONSerialization.data(withJSONObject: filtered),
          var jsonString = String(data: jsonData, encoding: .utf8) else {
        exit(1)
    }
    jsonString += "\n"

    log("Sending to socket: \(jsonString.trimmingCharacters(in: .whitespacesAndNewlines))")

    // Send to Unix socket
    sendToSocket(jsonString)
    log("Bridge done")
}

func detectTTY() -> String? {
    var pid = ProcessInfo.processInfo.processIdentifier

    // Walk up the process tree to find a TTY
    for _ in 0..<10 {
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-o", "tty=,ppid=", "-p", "\(pid)"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            break
        }

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let parts = output.split(separator: " ", maxSplits: 1).map(String.init)

        if parts.count >= 1 {
            let tty = parts[0]
            if tty != "??" && tty != "-" && !tty.isEmpty {
                return "/dev/\(tty)"
            }
        }

        if parts.count >= 2, let ppid = Int32(parts[1]), ppid > 1 {
            pid = ppid
        } else {
            break
        }
    }

    return nil
}

func detectTerminalBundleId(from env: [String: String]) -> String? {
    if env["ITERM_SESSION_ID"] != nil { return "com.googlecode.iterm2" }
    if env["TERM_SESSION_ID"] != nil { return "com.apple.Terminal" }
    if let termProgram = env["TERM_PROGRAM"] {
        switch termProgram.lowercased() {
        case "iterm.app": return "com.googlecode.iterm2"
        case "apple_terminal": return "com.apple.Terminal"
        case "ghostty": return "com.mitchellh.ghostty"
        case "kitty": return "net.kovidgoyal.kitty"
        case "warpterm": return "dev.warp.Warp-Stable"
        default: break
        }
    }
    return nil
}

func sendToSocket(_ message: String) {
    let socketPath = "/tmp/vibe-pet.sock"
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else {
        log("ERROR: Failed to create socket fd, errno=\(errno)")
        return
    }
    defer { close(fd) }

    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let pathBytes = socketPath.utf8CString
    withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
        ptr.withMemoryRebound(to: CChar.self, capacity: Int(104)) { dest in
            pathBytes.withUnsafeBufferPointer { src in
                let count = min(src.count, 104)
                dest.update(from: src.baseAddress!, count: count)
            }
        }
    }

    let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
    let result = withUnsafePointer(to: &addr) { ptr in
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
            connect(fd, sockPtr, addrLen)
        }
    }

    guard result == 0 else {
        log("ERROR: Failed to connect to \(socketPath), errno=\(errno)")
        return
    }

    log("Connected to socket")
    let written = message.utf8CString.withUnsafeBufferPointer { buf in
        write(fd, buf.baseAddress!, message.utf8.count)
    }
    log("Wrote \(written) bytes to socket")
}

main()
