import Foundation

/// Sent from bridge → app when a hook needs a user decision (PreToolUse /
/// PermissionRequest). The bridge keeps its socket connection open and blocks
/// on the matching `ApprovalDecision` written back by the app.
struct ApprovalRequest: Codable {
    let type: String  // "approvalRequest"
    let requestId: String
    let sessionId: String
    let source: String
    let hookEvent: String
    let cwd: String?
    let tty: String?
    let terminalBundleId: String?
    let terminalTabId: String?
    let toolName: String?
    /// A short preview of the tool input (e.g. the bash command or the file
    /// path being edited) rendered by the bridge so the UI can show it
    /// without decoding provider-specific schemas.
    let toolInputPreview: String?
    let timestamp: Double

    var date: Date { Date(timeIntervalSince1970: timestamp) }
}

/// Sent from app → bridge in response to an `ApprovalRequest`.
/// `decision` mirrors Claude Code's `permissionDecision` semantics; the bridge
/// translates to the source-specific hook response JSON before exiting.
struct ApprovalDecision: Codable {
    let requestId: String
    let decision: String  // "allow" | "deny" | "ask"
    let reason: String?
}

enum ApprovalProtocol {
    static let requestType = "approvalRequest"
    static let decisionAllow = "allow"
    static let decisionDeny = "deny"
    static let decisionAsk = "ask"

    /// Claude Code PreToolUse tools that should trigger a VibePet approval
    /// card. Tools outside this list get an immediate "ask" response from the
    /// bridge so the normal Claude Code prompt (or its allow/deny rules) can
    /// handle them — otherwise every Grep/Read would pop a card.
    static let claudeDangerousTools: Set<String> = ["Bash", "Write", "Edit", "MultiEdit"]
}
