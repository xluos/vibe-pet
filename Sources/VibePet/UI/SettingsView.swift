import SwiftUI
import AppKit

class SettingsWindowController: NSWindowController {
    static var shared: SettingsWindowController?

    static func show() {
        if let existing = shared {
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 480),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "VibePet 设置"
        window.center()
        window.isReleasedWhenClosed = false

        let controller = SettingsWindowController(window: window)
        shared = controller

        let hostingView = NSHostingView(rootView: SettingsWindowView())
        window.contentView = hostingView

        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct SettingsWindowView: View {
    @AppStorage("vibepet.soundEnabled") private var soundEnabled = true
    @AppStorage("vibepet.launchAtLogin") private var launchAtLogin = false
    @AppStorage("vibepet.soundVolume") private var soundVolume = 0.5

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header
                VStack(spacing: 4) {
                    Image(systemName: "cat")
                        .font(.system(size: 36))
                        .foregroundColor(.orange)
                    Text("VibePet")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    Text("v1.0.0")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .padding(.top, 8)
                .padding(.bottom, 4)

                // Sound
                settingsSection("声音") {
                    settingsToggleRow("通知声音", icon: "speaker.wave.2", iconColor: .blue, isOn: $soundEnabled)
                    if soundEnabled {
                        Divider().padding(.leading, 40)
                        settingsSliderRow("音量", icon: "speaker", iconColor: .blue, value: $soundVolume)
                    }
                }

                // General
                settingsSection("通用") {
                    settingsToggleRow("开机启动", icon: "power", iconColor: .green, isOn: $launchAtLogin)
                }

                // Hooks
                settingsSection("Hooks") {
                    settingsInfoRow("Claude Code", icon: "c.circle.fill", iconColor: .orange, value: hookStatus(for: "claude"))
                    Divider().padding(.leading, 40)
                    settingsInfoRow("Codex CLI", icon: "x.circle.fill", iconColor: .green, value: hookStatus(for: "codex"))
                    Divider().padding(.leading, 40)
                    settingsInfoRow("Coco", icon: "c.square.fill", iconColor: .blue, value: hookStatus(for: "coco"))
                }

                // Data
                settingsSection("数据") {
                    settingsInfoRow("会话文件", icon: "doc", iconColor: .gray, value: "~/.vibe-pet/sessions.json")
                    Divider().padding(.leading, 40)
                    settingsButtonRow("重新安装 hooks", icon: "arrow.triangle.2.circlepath", iconColor: .blue) {
                        reinstallHooks()
                    }
                    Divider().padding(.leading, 40)
                    settingsButtonRow("卸载 hooks", icon: "xmark.circle", iconColor: .red) {
                        HookInstaller().uninstallAll()
                    }
                    Divider().padding(.leading, 40)
                    settingsButtonRow("Open data folder", icon: "folder", iconColor: .blue) {
                        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".vibe-pet")
                        NSWorkspace.shared.open(url)
                    }
                }

                // Quit
                Button(action: { NSApplication.shared.terminate(nil) }) {
                    HStack {
                        Image(systemName: "power")
                        Text("退出 VibePet")
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(width: 420, height: 480)
    }

    // MARK: - Section

    private func settingsSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
                .padding(.bottom, 6)

            VStack(spacing: 0) {
                content()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
        }
    }

    // MARK: - Rows

    private func settingsToggleRow(_ label: String, icon: String, iconColor: Color, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            iconBadge(icon, color: iconColor)
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.primary)
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .scaleEffect(0.8)
        }
        .frame(height: 32)
    }

    private func settingsSliderRow(_ label: String, icon: String, iconColor: Color, value: Binding<Double>) -> some View {
        HStack(spacing: 10) {
            iconBadge(icon, color: iconColor)
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.primary)
            Spacer()
            Slider(value: value, in: 0...1)
                .frame(width: 120)
        }
        .frame(height: 32)
    }

    private func settingsInfoRow(_ label: String, icon: String, iconColor: Color, value: String) -> some View {
        HStack(spacing: 10) {
            iconBadge(icon, color: iconColor)
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.primary)
            Spacer()
            Text(value)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .frame(height: 32)
    }

    private func settingsButtonRow(_ label: String, icon: String, iconColor: Color, action: @escaping () -> Void) -> some View {
        AsyncActionButton(label: label, icon: icon, iconColor: iconColor, action: action)
    }

    private func iconBadge(_ name: String, color: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.white)
            .frame(width: 26, height: 26)
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Helpers

    private func hookStatus(for source: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        switch source {
        case "claude":
            let path = "\(home)/.claude/settings.json"
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  let str = String(data: data, encoding: .utf8) else {
                return "未配置"
            }
            return str.contains("vibe-pet-bridge") ? "已激活" : "未配置"

        case "codex":
            let configPath = "\(home)/.codex/config.toml"
            let installer = HookInstaller()
            return installer.isCodexHooksEnabled(at: URL(fileURLWithPath: configPath)) ? "已激活" : "未激活"

        case "coco":
            let path = "\(home)/.trae/traecli.yaml"
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  let str = String(data: data, encoding: .utf8) else {
                return "未配置"
            }
            return str.contains("vibe-pet-bridge") ? "已激活" : "未配置"

        default:
            return "未知"
        }
    }

    private func reinstallHooks() {
        let installer = HookInstaller()

        // Check if Codex needs confirmation
        if installer.needsCodexHooksConfirmation() {
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "启用 Codex Hooks？"
                alert.informativeText = "检测到 Codex CLI 已安装，但 config.toml 中的 hooks 未启用。是否启用 hooks？"
                alert.alertStyle = .informational
                alert.addButton(withTitle: "启用 Hooks")
                alert.addButton(withTitle: "跳过")

                let response = alert.runModal()

                if response == .alertFirstButtonReturn {
                    // User chose to enable hooks
                    do {
                        try installer.enableCodexHooks()
                        print("[VibePet] Codex hooks enabled during reinstall")
                    } catch {
                        print("[VibePet] Failed to enable Codex hooks: \(error)")
                        let errorAlert = NSAlert()
                        errorAlert.messageText = "启用 Codex Hooks 失败"
                        errorAlert.informativeText = error.localizedDescription
                        errorAlert.alertStyle = .warning
                        errorAlert.addButton(withTitle: "好的")
                        errorAlert.runModal()
                        return
                    }
                }

                // Install all hooks
                installer.installAll()
            }
        } else {
            // Install all hooks directly
            installer.installAll()
        }
    }
}

// MARK: - Async action button with loading → success feedback

struct AsyncActionButton: View {
    let label: String
    let icon: String
    let iconColor: Color
    let action: () -> Void

    enum State { case idle, loading, success }
    @SwiftUI.State private var state: State = .idle

    var body: some View {
        Button(action: run) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 26, height: 26)
                    .background(iconColor)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                Text(label)
                    .font(.system(size: 13))
                    .foregroundColor(.primary)

                Spacer()

                // Status indicator
                ZStack {
                    switch state {
                    case .idle:
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary.opacity(0.5))
                    case .loading:
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 16, height: 16)
                    case .success:
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.green)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(width: 20)
                .animation(.easeInOut(duration: 0.25), value: state)
            }
            .frame(height: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(state != .idle)
    }

    private func run() {
        state = .loading
        DispatchQueue.global(qos: .userInitiated).async {
            action()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation { state = .success }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation { state = .idle }
                }
            }
        }
    }
}
