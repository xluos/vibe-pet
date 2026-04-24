import Foundation

enum PerfLog {
    private static let logPath = "/tmp/vibe-pet-performance.log"
    private static let queue = DispatchQueue(label: "com.vibe-pet.perf-log", qos: .utility)

    static func now() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }

    static func elapsedMS(since start: UInt64) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    }

    static func format(_ ms: Double) -> String {
        String(format: "%.2f", ms)
    }

    static func log(_ category: String, _ message: String) {
        let ts = ISO8601DateFormatter().string(from: Date())
        let line = "[VibePetPerf \(ts)] [\(category)] \(message)\n"

        queue.async {
            if let fh = FileHandle(forWritingAtPath: logPath) {
                fh.seekToEndOfFile()
                fh.write(Data(line.utf8))
                try? fh.close()
            } else {
                FileManager.default.createFile(atPath: logPath, contents: Data(line.utf8))
            }
        }
    }
}
