import SwiftUI

@main
struct VibePetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var socketServer: SocketServer?
    private var sessionStore = SessionStore()
    private var notchPanel: NotchWindowController?
    private var soundObserver: Any?
    private var localeObserver: Any?
    private let attentionReminderCoordinator = AttentionReminderCoordinator()
    private var screenObserver: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Install launcher script and hooks
        installLauncher()
        HookInstaller().installIfNeeded()

        // Check Codex hooks status on first launch
        checkCodexHooksOnFirstLaunch()

        // Start IPC socket server
        socketServer = SocketServer { [weak self] message in
            let enqueuedAt = PerfLog.now()
            DispatchQueue.main.async {
                let mainQueueWaitMs = PerfLog.elapsedMS(since: enqueuedAt)
                if mainQueueWaitMs >= 4 {
                    PerfLog.log(
                        "app.main-queue",
                        "event=\(message.hookEvent) session=\(message.sessionId) waitMs=\(PerfLog.format(mainQueueWaitMs))"
                    )
                }
                self?.sessionStore.handleEvent(message)
            }
        }
        socketServer?.start()

        // Wire sound notifications
        soundObserver = NotificationCenter.default.addObserver(
            forName: .sessionStatusChanged,
            object: nil,
            queue: .main
        ) { notification in
            // Default to enabled if key not set
            if UserDefaults.standard.object(forKey: "vibepet.soundEnabled") != nil
                && !UserDefaults.standard.bool(forKey: "vibepet.soundEnabled") { return }
            guard let hookEvent = notification.userInfo?["hookEvent"] as? String else { return }
            switch hookEvent {
            case "SessionStart":
                SoundManager.shared.play(.sessionStart)
            case "UserPromptSubmit":
                SoundManager.shared.play(.sessionStart)
            case "Stop":
                SoundManager.shared.play(.taskComplete)
            case "PermissionRequest":
                SoundManager.shared.play(.needsAttention)
            case "SessionEnd":
                SoundManager.shared.play(.sessionEnd)
            default:
                break
            }
        }

        localeObserver = NotificationCenter.default.addObserver(
            forName: NSLocale.currentLocaleDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            let selectedLanguage = UserDefaults.standard.string(forKey: L10n.languageKey) ?? ""
            guard selectedLanguage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            NotificationCenter.default.post(name: L10n.languageDidChangeNotification, object: nil)
        }

        // Create notch panel UI
        notchPanel = NotchWindowController(sessionStore: sessionStore)
        notchPanel?.showWindow(nil)
        attentionReminderCoordinator.start(sessionStore: sessionStore)
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.notchPanel?.refreshScreenConfiguration()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        sessionStore.flushPendingSave(reason: "app-terminate")
        socketServer?.stop()
        attentionReminderCoordinator.stop()
        if let observer = soundObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = localeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = screenObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func installLauncher() {
        let launcherDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".vibe-pet/bin")
        let launcherPath = launcherDir.appendingPathComponent("vibe-pet-bridge")

        // Always overwrite to keep launcher up-to-date
        try? FileManager.default.createDirectory(at: launcherDir, withIntermediateDirectories: true)

        // Find the real bridge binary path (in .app bundle or dev build)
        let bundleHelperPath = Bundle.main.executableURL?
            .deletingLastPathComponent() // MacOS/
            .deletingLastPathComponent() // Contents/
            .appendingPathComponent("Helpers/vibe-pet-bridge").path ?? ""

        let script = """
        #!/bin/bash
        # VibePet bridge launcher - auto-generated, do not edit
        BRIDGE_NAME="vibe-pet-bridge"
        LOG_FILE="/tmp/vibe-pet-bridge.log"

        log() { echo "[VibePetBridge] $(date '+%H:%M:%S') $*" >> "$LOG_FILE"; }
        log "Invoked with args: $*"

        # 1. Try the bundle helper path from when the app was last launched
        BUNDLE_PATH="\(bundleHelperPath)"
        if [ -x "$BUNDLE_PATH" ]; then
            log "Using bundle path: $BUNDLE_PATH"
            exec "$BUNDLE_PATH" "$@"
        fi

        # 2. Try known .app locations
        for p in "/Applications/VibePet.app/Contents/Helpers/$BRIDGE_NAME" \\
                 "$HOME/Applications/VibePet.app/Contents/Helpers/$BRIDGE_NAME"; do
            if [ -x "$p" ]; then
                log "Using: $p"
                exec "$p" "$@"
            fi
        done

        # 3. Try dev build directory
        DEV_PATH="$HOME/my-project/vibe-pet/.build/release/VibePetBridge"
        if [ -x "$DEV_PATH" ]; then
            log "Using dev build: $DEV_PATH"
            exec "$DEV_PATH" "$@"
        fi
        DEV_PATH_DBG="$HOME/my-project/vibe-pet/.build/debug/VibePetBridge"
        if [ -x "$DEV_PATH_DBG" ]; then
            log "Using debug build: $DEV_PATH_DBG"
            exec "$DEV_PATH_DBG" "$@"
        fi

        # 4. mdfind fallback
        APP=$(mdfind "kMDItemCFBundleIdentifier = 'com.vibe-pet.app'" 2>/dev/null | head -1)
        if [ -n "$APP" ] && [ -x "$APP/Contents/Helpers/$BRIDGE_NAME" ]; then
            log "Using mdfind: $APP/Contents/Helpers/$BRIDGE_NAME"
            exec "$APP/Contents/Helpers/$BRIDGE_NAME" "$@"
        fi

        log "ERROR: Bridge binary not found"
        exit 1
        """
        try? script.write(to: launcherPath, atomically: true, encoding: .utf8)
        chmod(launcherPath.path, 0o755)
        print("[VibePet] Launcher installed at \(launcherPath.path)")
    }

    private func checkCodexHooksOnFirstLaunch() {
        // Only check once per installation
        let checkedKey = "vibepet.codexHooksChecked"
        guard UserDefaults.standard.object(forKey: checkedKey) == nil else {
            return
        }

        // Mark as checked
        UserDefaults.standard.set(true, forKey: checkedKey)

        let home = FileManager.default.homeDirectoryForCurrentUser
        let codexDir = home.appendingPathComponent(".codex")

        // Check if ~/.codex exists
        guard FileManager.default.fileExists(atPath: codexDir.path) else {
            print("[VibePet] ~/.codex not found, skipping Codex hooks check")
            return
        }

        let configPath = codexDir.appendingPathComponent("config.toml")
        guard FileManager.default.fileExists(atPath: configPath.path) else {
            print("[VibePet] ~/.codex/config.toml not found, skipping Codex hooks check")
            return
        }

        // Check if hooks are explicitly disabled
        let installer = HookInstaller()
        let hooksEnabled = installer.isCodexHooksEnabled(at: configPath)

        if !hooksEnabled {
            // Only show dialog if hooks are explicitly disabled (codex_hooks = false)
            DispatchQueue.main.async {
                self.showCodexHooksEnableDialog()
            }
        }
    }

    private func showCodexHooksEnableDialog() {
        let alert = NSAlert()
        alert.messageText = L10n.tr("codexHooks.enableDialog.title")
        alert.informativeText = L10n.tr("codexHooks.enableDialog.message")
        alert.alertStyle = .informational
        alert.addButton(withTitle: L10n.tr("codexHooks.enableDialog.confirm"))
        alert.addButton(withTitle: L10n.tr("codexHooks.enableDialog.cancel"))

        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            // User chose to enable hooks
            do {
                try HookInstaller().enableCodexHooks()
                print("[VibePet] Codex hooks enabled by user")

                // Show success message
                let successAlert = NSAlert()
                successAlert.messageText = L10n.tr("codexHooks.enableSuccess.title")
                successAlert.informativeText = L10n.tr("codexHooks.enableSuccess.message")
                successAlert.alertStyle = .informational
                successAlert.addButton(withTitle: L10n.tr("common.ok"))
                successAlert.runModal()
            } catch {
                print("[VibePet] Failed to enable Codex hooks: \(error)")

                // Show error message
                let errorAlert = NSAlert()
                errorAlert.messageText = L10n.tr("codexHooks.enableError.title")
                errorAlert.informativeText = L10n.tr("codexHooks.enableError.message", error.localizedDescription)
                errorAlert.alertStyle = .warning
                errorAlert.addButton(withTitle: L10n.tr("common.ok"))
                errorAlert.runModal()
            }
        } else {
            print("[VibePet] User declined to enable Codex hooks")
        }
    }
}
