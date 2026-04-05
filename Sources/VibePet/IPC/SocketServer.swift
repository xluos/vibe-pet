import Foundation

final class SocketServer {
    static let socketPath = "/tmp/vibe-pet.sock"
    private static let logPath = "/tmp/vibe-pet-server.log"

    private let onMessage: (BridgeMessage) -> Void
    private var serverFD: Int32 = -1
    private var running = false
    private let queue = DispatchQueue(label: "com.vibe-pet.socket", qos: .userInitiated)

    init(onMessage: @escaping (BridgeMessage) -> Void) {
        self.onMessage = onMessage
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
        // Remove stale socket
        unlink(Self.socketPath)

        log("Starting socket server...")

        // Create Unix domain socket
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

        // Accept loop on background thread
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

            // Handle synchronously on this queue to avoid issues
            handleClient(fd: clientFD)
        }
        log("Accept loop exited")
    }

    private func handleClient(fd: Int32) {
        defer { close(fd) }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)

        // Set a read timeout so we don't block forever
        var tv = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        while true {
            let bytesRead = read(fd, &buffer, buffer.count)
            if bytesRead <= 0 {
                if bytesRead < 0 {
                    log("Read error: errno=\(errno)")
                }
                break
            }
            data.append(buffer, count: bytesRead)
            log("Read \(bytesRead) bytes (total: \(data.count))")
        }

        guard !data.isEmpty else {
            log("Empty data from client")
            return
        }

        let raw = String(data: data, encoding: .utf8) ?? "<binary>"
        log("Full message: \(raw)")

        // Support newline-delimited JSON
        let lines = data.split(separator: UInt8(ascii: "\n"))
        let decoder = JSONDecoder()

        for line in lines {
            do {
                let message = try decoder.decode(BridgeMessage.self, from: Data(line))
                log("Decoded: event=\(message.hookEvent) session=\(message.sessionId) source=\(message.source)")
                onMessage(message)
            } catch {
                log("Decode error: \(error)")
                log("Raw line: \(String(data: Data(line), encoding: .utf8) ?? "<binary>")")
            }
        }
    }
}
