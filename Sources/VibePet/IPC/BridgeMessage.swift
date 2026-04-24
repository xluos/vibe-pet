import Foundation

struct BridgeMessage: Codable {
    let sessionId: String
    let hookEvent: String
    let source: String
    let cwd: String?
    let tty: String?
    let terminalBundleId: String?
    let terminalTabId: String?
    let toolName: String?
    let prompt: String?
    let lastAssistantMessage: String?
    let transcriptPath: String?
    let timestamp: Double

    var date: Date {
        Date(timeIntervalSince1970: timestamp)
    }
}
