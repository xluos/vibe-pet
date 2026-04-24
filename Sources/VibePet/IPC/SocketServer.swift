import Foundation

final class SocketServer {
    static let socketPath = "/tmp/vibe-pet.sock"
    private static let logPath = "/tmp/vibe-pet-server.log"

    private let onMessage: (BridgeMessage) -> Void
    private let onApprovalRequest: (ApprovalRequest, @escaping (ApprovalDecision) -> Void) -> Void
    private var serverFD: Int32 = -1
    private var running = false
    private let queue = DispatchQueue(label: "com.vibe-pet.socket", qos: .userInitiated)
    // Approval fds are long-lived (waiting for user click). We dispatch the
    // respond-then-close on this concurrent queue so a pending approval never
    // blocks the accept loop or another approval.
    private let approvalQueue = DispatchQueue(label: "com.vibe-pet.socket.approval", attributes: .concurrent)

    init(
        onMessage: @escaping (BridgeMessage) -> Void,
        onApprovalRequest: @escaping (ApprovalRequest, @escaping (ApprovalDecision) -> Void) -> Void
    ) {
        self.onMessage = onMessage
        self.onApprovalRequest = onApprovalRequest
        // Writing to a socket whose remote end has closed raises SIGPIPE by
        // default, which would kill the app. Writes return EPIPE after this.
        signal(SIGPIPE, SIG_IGN)
    }

    private func log(_ msg: String) {
        let ts = ISO8601DateFormatter().string(from: Date())
        let line = "[VibePet-Server \(ts)] \(msg)\n"
        if let fh = FileHandle(forWritingAtPath: Self.logPath) {
            fh.seekToEndOfFile()
            fh.write(Data(line.utf8))
            fh.closeFile()
        } else {
            FileManager.default.createFile(atPath: Self.logPath, contents: Data(line.utf8))
        }
    }

    func start() {
        unlink(Self.socketPath)
        log("Starting socket server...")

        serverFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverFD >= 0 else {
            log("ERROR: Failed to create socket, errno=\(errno)")
            return
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Self.socketPath.utf8CString
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: 104) { dest in
                pathBytes.withUnsafeBufferPointer { src in
                    let count = min(src.count, 104)
                    dest.update(from: src.baseAddress!, count: count)
                }
            }
        }

        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(serverFD, sockPtr, addrLen)
            }
        }

        guard bindResult == 0 else {
            log("ERROR: Failed to bind, errno=\(errno)")
            close(serverFD)
            return
        }

        chmod(Self.socketPath, 0o700)

        guard listen(serverFD, 16) == 0 else {
            log("ERROR: Failed to listen, errno=\(errno)")
            close(serverFD)
            return
        }

        running = true
        log("Listening on \(Self.socketPath)")

        queue.async { [weak self] in
            self?.acceptLoop()
        }
    }

    func stop() {
        running = false
        if serverFD >= 0 {
            close(serverFD)
            serverFD = -1
        }
        unlink(Self.socketPath)
        log("Server stopped")
    }

    private func acceptLoop() {
        log("Accept loop started on thread \(Thread.current)")
        while running {
            var clientAddr = sockaddr_un()
            var clientAddrLen = socklen_t(MemoryLayout<sockaddr_un>.size)

            let clientFD = withUnsafeMutablePointer(to: &clientAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    accept(serverFD, sockPtr, &clientAddrLen)
                }
            }

            if clientFD < 0 {
                if running {
                    log("Accept returned \(clientFD), errno=\(errno), continuing...")
                    usleep(10_000)
                }
                continue
            }

            log("Accepted connection, clientFD=\(clientFD)")
            handleClient(fd: clientFD)
        }
        log("Accept loop exited")
    }

    private func handleClient(fd: Int32) {
        // Read one \n-terminated JSON line, routed by the `type` field.
        // Plain events: call onMessage and close immediately.
        // Approval requests: hand the fd to an approval waiter that keeps it
        // open until the UI resolves, then writes the decision + closes.
        guard let line = readLine(from: fd, timeoutSeconds: 5) else {
            log("Empty / unreadable data from client, closing fd=\(fd)")
            close(fd)
            return
        }

        let raw = String(data: line, encoding: .utf8) ?? "<binary>"
        log("Incoming line (fd=\(fd)): \(raw.prefix(400))")

        let type = detectType(in: line)

        if type == ApprovalProtocol.requestType {
            do {
                let req = try JSONDecoder().decode(ApprovalRequest.self, from: line)
                log("Approval request: reqId=\(req.requestId) session=\(req.sessionId) tool=\(req.toolName ?? "?")")
                handleApprovalRequest(req, fd: fd)
            } catch {
                log("Approval decode error: \(error) — falling through and closing fd")
                close(fd)
            }
            return
        }

        // Default: treat as BridgeMessage event.
        do {
            let message = try JSONDecoder().decode(BridgeMessage.self, from: line)
            log("Decoded event=\(message.hookEvent) session=\(message.sessionId) source=\(message.source)")
            onMessage(message)
        } catch {
            log("Decode error: \(error) raw=\(raw.prefix(200))")
        }
        close(fd)
    }

    private func handleApprovalRequest(_ req: ApprovalRequest, fd: Int32) {
        // The callback may fire at any time — minutes or hours later. Close
        // the fd after writing exactly once; guard with an atomic flag so a
        // duplicate resolution doesn't double-close.
        let responded = DispatchQueue(label: "com.vibe-pet.socket.approval.flag.\(req.requestId)")
        var didRespond = false

        let respond: (ApprovalDecision) -> Void = { [weak self] decision in
            responded.sync {
                guard !didRespond else { return }
                didRespond = true
                self?.approvalQueue.async {
                    self?.writeApprovalDecision(fd: fd, decision: decision)
                    close(fd)
                }
            }
        }

        onApprovalRequest(req, respond)
    }

    private func writeApprovalDecision(fd: Int32, decision: ApprovalDecision) {
        do {
            var data = try JSONEncoder().encode(decision)
            data.append(0x0a)  // newline terminator matches bridge's line reader
            _ = data.withUnsafeBytes { buf -> Int in
                write(fd, buf.baseAddress, buf.count)
            }
            log("Wrote decision reqId=\(decision.requestId) decision=\(decision.decision)")
        } catch {
            log("Failed to encode decision: \(error)")
        }
    }

    /// Blocking read of a single \n-terminated line from the client. Returns
    /// the line excluding the newline, or nil on EOF / timeout / error.
    private func readLine(from fd: Int32, timeoutSeconds: Int) -> Data? {
        var tv = timeval(tv_sec: timeoutSeconds, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let bytesRead = read(fd, &buffer, buffer.count)
            if bytesRead <= 0 {
                if bytesRead < 0 {
                    log("readLine error: errno=\(errno)")
                }
                return data.isEmpty ? nil : data
            }
            data.append(buffer, count: bytesRead)
            if let idx = data.firstIndex(of: 0x0a) {
                return data[..<idx]
            }
            // No delimiter yet — keep reading. Safety cap to avoid runaway
            // allocations from a malformed sender.
            if data.count > 256 * 1024 {
                log("readLine exceeded 256KB without newline, aborting")
                return nil
            }
        }
    }

    /// Peek at the `type` field without a full decode so we know how to route.
    private func detectType(in data: Data) -> String {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String else {
            return ""
        }
        return type
    }
}
