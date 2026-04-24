import Foundation

// MARK: - VibePetBridge CLI
// Invoked by Claude Code / Codex hooks. Reads stdin + env, sends JSON to the main app via Unix socket.
// For approval events (both Claude and Codex `PermissionRequest`) the bridge
// blocks on the socket waiting for the user's decision from the VibePet UI,
// then emits the hook response JSON. PermissionRequest fires only after each
// CLI has evaluated its own allow/deny rules, so we never pop cards for calls
// the user's config already whitelisted.

// Envelope shapes duplicated here to keep the bridge target dependency-free.
// Must stay in lock-step with Sources/VibePet/IPC/ApprovalEnvelope.swift.
struct ApprovalRequestPayload: Codable {
    let type: String
    let requestId: String
    let sessionId: String
    let source: String
    let hookEvent: String
    let cwd: String?
    let tty: String?
    let terminalBundleId: String?
    let terminalTabId: String?
    let toolName: String?
    let toolInputPreview: String?
    let timestamp: Double
}

struct ApprovalDecisionPayload: Codable {
    let requestId: String
    let decision: String
    let reason: String?
}

/// VibePet's approval card interception is opt-in. Existence of this file
/// means the user flipped the toggle in VibePet Settings → Approvals; absent
/// → bridge falls through to each CLI's native permission flow. Stays in
/// lock-step with Sources/VibePet/IPC/ApprovalPreferences.swift.
let approvalInterceptFlagRelativePath = ".vibe-pet/approval-intercept-enabled"

func approvalInterceptEnabled() -> Bool {
    let home = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
    let path = "\(home)/\(approvalInterceptFlagRelativePath)"
    return FileManager.default.fileExists(atPath: path)
}

let logFile = "/tmp/vibe-pet-bridge.log"
let performanceThresholdMS = 4.0
let verboseBridgeLogs = ProcessInfo.processInfo.environment["VIBEPET_BRIDGE_VERBOSE_LOGS"] == "1"

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

func debugLog(_ msg: String) {
    guard verboseBridgeLogs else { return }
    log(msg)
}

func now() -> UInt64 {
    DispatchTime.now().uptimeNanoseconds
}

func elapsedMS(since start: UInt64) -> Double {
    Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
}

func formatMS(_ value: Double) -> String {
    String(format: "%.2f", value)
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
    let totalStart = now()
    let args = CommandLine.arguments
    debugLog("Bridge started, args: \(args)")

    // Parse --source flag
    var source = "unknown"
    if let idx = args.firstIndex(of: "--source"), idx + 1 < args.count {
        source = args[idx + 1]
    }

    // Read stdin (hook context JSON from Claude Code / Codex)
    let stdinStart = now()
    var stdinData = Data()
    while let line = readLine(strippingNewline: false) {
        stdinData.append(Data(line.utf8))
    }
    let stdinReadMs = elapsedMS(since: stdinStart)
    debugLog("Read \(stdinData.count) bytes from stdin")
    if let stdinStr = String(data: stdinData, encoding: .utf8) {
        debugLog("stdin: \(stdinStr.prefix(500))")
    }

    // Parse hook event name from stdin JSON
    let parseStart = now()
    var hookEvent = "Unknown"
    var sessionId: String?
    var toolName: String?
    var prompt: String?
    var lastAssistantMessage: String?
    var transcriptPath: String?
    var toolInputPreview: String?

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
        if let toolInput = json["toolInput"] as? [String: Any] ?? json["tool_input"] as? [String: Any] {
            toolInputPreview = buildToolInputPreview(toolName: toolName, toolInput: toolInput)
        }
    }
    let jsonParseMs = elapsedMS(since: parseStart)

    // Collect environment variables
    let env = ProcessInfo.processInfo.environment
    if sessionId == nil {
        sessionId = env["CLAUDE_SESSION_ID"] ?? env["CLAUDE_CONVERSATION_ID"] ?? env["CODEX_SESSION_ID"]
    }

    // If still no session ID, generate one from PID chain
    if sessionId == nil {
        sessionId = "pid-\(ProcessInfo.processInfo.processIdentifier)"
    }

    let terminalBundleId = env["__CFBundleIdentifier"] ?? detectTerminalBundleId(from: env)
    let ttyStart = now()
    let tty: String?
    if terminalBundleId == "com.apple.Terminal" || terminalBundleId == "com.googlecode.iterm2" {
        tty = detectTTY(from: env)
    } else {
        tty = env["TTY"] ?? env["SSH_TTY"]
    }
    let ttyDetectMs = elapsedMS(since: ttyStart)
    let cwd = env["CLAUDE_CWD"] ?? env["PWD"]

    // Ghostty tab.id is only reachable via AppleScript. Capture once at SessionStart —
    // the id is stable for Ghostty's process lifetime and survives tab moves.
    var terminalTabId: String?
    if hookEvent == "SessionStart", terminalBundleId == "com.mitchellh.ghostty" {
        terminalTabId = detectGhosttyTabId()
    }

    // PermissionRequest hooks only fire when the CLI has already evaluated
    // its allow/deny rules and decided to actually prompt. We hand it off to
    // VibePet and block until the user decides. Any other event (including
    // Claude's PreToolUse) flows through as a plain observability event
    // below — we never try to override rule evaluation ourselves.
    if shouldInterceptApproval(source: source, hookEvent: hookEvent) {
        let sid = sessionId ?? UUID().uuidString
        let req = ApprovalRequestPayload(
            type: "approvalRequest",
            requestId: UUID().uuidString,
            sessionId: sid,
            source: source,
            hookEvent: hookEvent,
            cwd: cwd,
            tty: tty,
            terminalBundleId: terminalBundleId,
            terminalTabId: terminalTabId,
            toolName: toolName,
            toolInputPreview: toolInputPreview,
            timestamp: Date().timeIntervalSince1970
        )
        let decision = exchangeApproval(request: req)
        writeHookResponse(source: source, hookEvent: hookEvent, decision: decision)
        let totalMs = elapsedMS(since: totalStart)
        log("APPROVAL source=\(source) event=\(hookEvent) tool=\(toolName ?? "?") decision=\(decision?.decision ?? "fallthrough") totalMs=\(formatMS(totalMs))")
        exit(0)
    }

    // Build message
    let message: [String: Any?] = [
        "sessionId": sessionId,
        "hookEvent": hookEvent,
        "source": source,
        "cwd": cwd,
        "tty": tty,
        "terminalBundleId": terminalBundleId,
        "terminalTabId": terminalTabId,
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

    debugLog("Sending to socket: \(jsonString.trimmingCharacters(in: .whitespacesAndNewlines))")

    // Send to Unix socket
    let socketStart = now()
    sendToSocket(jsonString)
    let socketWriteMs = elapsedMS(since: socketStart)
    let totalMs = elapsedMS(since: totalStart)

    if totalMs >= performanceThresholdMS || ttyDetectMs >= performanceThresholdMS {
        log(
            "PERF event=\(hookEvent) source=\(source) session=\(sessionId ?? "unknown") bytes=\(stdinData.count) stdinMs=\(formatMS(stdinReadMs)) parseMs=\(formatMS(jsonParseMs)) ttyMs=\(formatMS(ttyDetectMs)) socketMs=\(formatMS(socketWriteMs)) totalMs=\(formatMS(totalMs)) terminal=\(terminalBundleId ?? "unknown") tty=\(tty ?? "nil")"
        )
    } else {
        debugLog(
            "PERF event=\(hookEvent) source=\(source) session=\(sessionId ?? "unknown") bytes=\(stdinData.count) stdinMs=\(formatMS(stdinReadMs)) parseMs=\(formatMS(jsonParseMs)) ttyMs=\(formatMS(ttyDetectMs)) socketMs=\(formatMS(socketWriteMs)) totalMs=\(formatMS(totalMs))"
        )
    }
    debugLog("Bridge done")
}

// MARK: - Approval interception

/// We only ever intercept `PermissionRequest`. Both Claude and Codex fire this
/// hook strictly AFTER their own rule / policy evaluation, so user-configured
/// `permissions.allow` / `approval_policy = "never"` / YOLO / etc. already
/// short-circuit before the bridge sees anything — no danger-list heuristics
/// required.
func shouldInterceptApproval(source: String, hookEvent: String) -> Bool {
    guard approvalInterceptEnabled() else { return false }
    guard hookEvent == "PermissionRequest" else { return false }
    return source == "claude" || source == "codex"
}

/// Send the approval request over the socket and block until the app writes
/// back a decision (or the connection dies / read times out).
func exchangeApproval(request: ApprovalRequestPayload) -> ApprovalDecisionPayload? {
    let socketPath = "/tmp/vibe-pet.sock"
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else {
        log("APPROVAL socket() failed, errno=\(errno)")
        return nil
    }
    defer { close(fd) }

    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let pathBytes = socketPath.utf8CString
    withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
        ptr.withMemoryRebound(to: CChar.self, capacity: 104) { dest in
            pathBytes.withUnsafeBufferPointer { src in
                let count = min(src.count, 104)
                dest.update(from: src.baseAddress!, count: count)
            }
        }
    }
    let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
    let connectResult = withUnsafePointer(to: &addr) { ptr in
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
            connect(fd, sockPtr, addrLen)
        }
    }
    guard connectResult == 0 else {
        log("APPROVAL connect failed, errno=\(errno)")
        return nil
    }

    // Write the request as newline-terminated JSON.
    guard var data = try? JSONEncoder().encode(request) else {
        log("APPROVAL failed to encode request")
        return nil
    }
    data.append(0x0a)
    let written = data.withUnsafeBytes { buf -> Int in
        write(fd, buf.baseAddress, buf.count)
    }
    guard written == data.count else {
        log("APPROVAL write short: \(written) / \(data.count), errno=\(errno)")
        return nil
    }

    // Block on the response. The hook's own timeout (configured in
    // settings.json to 86400s) will kill us if the user never decides.
    var responseData = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while true {
        let n = read(fd, &buffer, buffer.count)
        if n <= 0 {
            if n < 0 {
                log("APPROVAL read error errno=\(errno)")
            }
            return nil
        }
        responseData.append(buffer, count: n)
        if let idx = responseData.firstIndex(of: 0x0a) {
            let slice = Data(responseData[..<idx])
            return try? JSONDecoder().decode(ApprovalDecisionPayload.self, from: slice)
        }
        if responseData.count > 64 * 1024 {
            log("APPROVAL response exceeded 64KB without newline")
            return nil
        }
    }
}

/// Write the hook response to stdout. Claude and Codex's `PermissionRequest`
/// hooks both expect the same shape:
/// `{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow|deny","message":"…"}}}`
/// No stdout = fall through to the CLI's native terminal prompt.
func writeHookResponse(source: String, hookEvent: String, decision: ApprovalDecisionPayload?) {
    guard let decision else { return }

    let behavior: String
    switch decision.decision.lowercased() {
    case "allow": behavior = "allow"
    case "deny": behavior = "deny"
    default: return  // "ask" / unknown → silent fall-through
    }

    let reason = decision.reason ?? "VibePet"
    let payload: [String: Any] = [
        "hookSpecificOutput": [
            "hookEventName": "PermissionRequest",
            "decision": [
                "behavior": behavior,
                "message": reason,
            ],
        ]
    ]
    emitStdoutJSON(payload)
}

func emitStdoutJSON(_ payload: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
          let str = String(data: data, encoding: .utf8) else {
        return
    }
    FileHandle.standardOutput.write(Data((str + "\n").utf8))
}

/// Build a short, human-readable preview of the tool arguments so the UI can
/// show "what's about to run" without understanding every schema.
func buildToolInputPreview(toolName: String?, toolInput: [String: Any]) -> String? {
    func truncate(_ s: String, _ cap: Int = 220) -> String {
        let collapsed = s.replacingOccurrences(of: "\n", with: " ")
        return collapsed.count > cap ? String(collapsed.prefix(cap)) + "…" : collapsed
    }
    if let cmd = toolInput["command"] as? String { return truncate(cmd) }
    if let path = toolInput["file_path"] as? String ?? toolInput["filePath"] as? String {
        if let content = toolInput["content"] as? String {
            return truncate("\(path) — \(content)")
        }
        return truncate(path)
    }
    if let query = toolInput["query"] as? String { return truncate(query) }
    if let url = toolInput["url"] as? String { return truncate(url) }
    if let data = try? JSONSerialization.data(withJSONObject: toolInput, options: []),
       let str = String(data: data, encoding: .utf8) {
        return truncate(str)
    }
    _ = toolName
    return nil
}

// MARK: - TTY / terminal detection

func detectTTY(from env: [String: String]) -> String? {
    if let tty = env["TTY"], !tty.isEmpty {
        return tty.hasPrefix("/dev/") ? tty : "/dev/\(tty)"
    }
    if let sshTTY = env["SSH_TTY"], !sshTTY.isEmpty {
        return sshTTY
    }

    var pid = ProcessInfo.processInfo.processIdentifier

    // Walk up the process tree to find a TTY
    for _ in 0..<6 {
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

func detectGhosttyTabId() -> String? {
    // Ask Ghostty for the id of the currently selected tab of the front window.
    // Ghostty's AppleScript dictionary (1.3.0+) exposes `id` on tab.
    let script = """
    tell application \"Ghostty\"
        try
            return id of selected tab of front window as text
        on error
            return \"\"
        end try
    end tell
    """
    let pipe = Pipe()
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = ["-e", script]
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice

    do {
        try process.run()
    } catch {
        return nil
    }
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { return nil }

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return raw.isEmpty ? nil : raw
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

    debugLog("Connected to socket")
    let written = message.utf8CString.withUnsafeBufferPointer { buf in
        write(fd, buf.baseAddress!, message.utf8.count)
    }
    debugLog("Wrote \(written) bytes to socket")
}

main()
