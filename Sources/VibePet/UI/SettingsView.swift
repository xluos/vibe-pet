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
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 660),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.tr("settings.windowTitle")
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
    @AppStorage(DisplayPreferences.lockedDisplayIDKey) private var lockedDisplayID = ""
    @AppStorage(AttentionAnimationPreferences.strongEnabledKey) private var strongAttentionAnimationEnabled = false
    @AppStorage(AttentionAnimationPreferences.styleKey) private var strongAttentionAnimationStyleRawValue = AttentionAnimationPreferences.defaultStrongStyle.rawValue
    @AppStorage(AttentionAnimationPreferences.soundEnabledKey) private var strongAttentionAnimationSoundEnabledStored = true
    @AppStorage(AttentionAnimationPreferences.soundCadenceKey) private var strongAttentionAnimationSoundCadenceRawValue = AttentionAnimationPreferences.defaultSoundCadence.rawValue
    @AppStorage(AttentionAnimationPreferences.mouseCompanionCatEnabledKey) private var mouseCompanionCatEnabled = true
    @AppStorage(AttentionAnimationPreferences.mouseCompanionBubbleEnabledKey) private var mouseCompanionBubbleEnabled = true
    @AppStorage(AttentionAnimationPreferences.mouseCompanionShakeDismissEnabledKey) private var mouseCompanionShakeDismissEnabled = true
    @AppStorage(AttentionAnimationPreferences.mouseCompanionShakeMinimumDistanceKey) private var mouseCompanionShakeMinimumDistance = AttentionAnimationPreferences.defaultMouseCompanionShakeMinimumDistance
    @AppStorage(AttentionAnimationPreferences.mouseCompanionShakeMinimumSpeedKey) private var mouseCompanionShakeMinimumSpeed = AttentionAnimationPreferences.defaultMouseCompanionShakeMinimumSpeed
    @State private var displayOptions = DisplayPreferences.availableDisplays()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header
                VStack(spacing: 4) {
                    Image(systemName: "cat")
                        .font(.system(size: 36))
                        .foregroundColor(.orange)
                    Text(L10n.tr("app.name"))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    Text("v1.0.0")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .padding(.top, 8)
                .padding(.bottom, 4)

                // Sound
                settingsSection(L10n.tr("settings.section.sound")) {
                    settingsToggleRow(L10n.tr("settings.notificationSounds"), icon: "speaker.wave.2", iconColor: .blue, isOn: $soundEnabled)
                    if soundEnabled {
                        Divider().padding(.leading, 40)
                        settingsSliderRow(L10n.tr("settings.volume"), icon: "speaker", iconColor: .blue, value: $soundVolume)
                    }
                }

                // General
                settingsSection(L10n.tr("settings.section.general")) {
                    settingsToggleRow(L10n.tr("settings.launchAtLogin"), icon: "power", iconColor: .green, isOn: $launchAtLogin)
                }

                settingsSection(L10n.tr("settings.section.display")) {
                    settingsDisplayPickerRow(L10n.tr("settings.pinnedDisplay"), icon: "display.2", iconColor: .indigo)
                }

                settingsSection(L10n.tr("settings.section.attention")) {
                    settingsToggleRow(L10n.tr("settings.strongAttentionAnimation"), icon: "sparkles", iconColor: .pink, isOn: $strongAttentionAnimationEnabled)
                    if strongAttentionAnimationEnabled {
                        Divider().padding(.leading, 40)
                        settingsAttentionPickerRow(L10n.tr("settings.animationStyle"), icon: "waveform.path.ecg", iconColor: .pink)
                        Divider().padding(.leading, 40)
                        settingsInfoRow(L10n.tr("settings.effect"), icon: "wand.and.stars", iconColor: .pink, value: selectedStrongAttentionAnimationStyle.settingsSummary)
                        Divider().padding(.leading, 40)
                        settingsToggleRow(L10n.tr("settings.reminderSound"), icon: "bell.badge", iconColor: .orange, isOn: strongAttentionSoundEnabledBinding)
                        if resolvedStrongAttentionSoundEnabled {
                            Divider().padding(.leading, 40)
                            settingsAttentionSoundCadenceRow(L10n.tr("settings.soundCadence"), icon: "metronome", iconColor: .orange)
                            Divider().padding(.leading, 40)
                            settingsInfoRow(L10n.tr("settings.cadence"), icon: "timer", iconColor: .orange, value: selectedStrongAttentionSoundCadence.settingsSummary)
                        }
                    } else {
                        Divider().padding(.leading, 40)
                        settingsInfoRow(L10n.tr("settings.effect"), icon: "wand.and.stars", iconColor: .gray, value: L10n.tr("settings.attentionDisabledHint"))
                    }
                    Divider().padding(.leading, 40)
                    settingsToggleRow(L10n.tr("settings.mouseCat"), icon: "cat", iconColor: .mint, isOn: $mouseCompanionCatEnabled)
                    Divider().padding(.leading, 40)
                    settingsToggleRow(L10n.tr("settings.speechBubble"), icon: "text.bubble", iconColor: .mint, isOn: $mouseCompanionBubbleEnabled)
                    Divider().padding(.leading, 40)
                    settingsToggleRow(L10n.tr("settings.shakeToDismiss"), icon: "hand.draw", iconColor: .mint, isOn: $mouseCompanionShakeDismissEnabled)
                    if mouseCompanionShakeDismissEnabled {
                        Divider().padding(.leading, 40)
                        settingsShakePresetRow(L10n.tr("settings.shakeSensitivity"), icon: "dial.medium", iconColor: .mint)
                        Divider().padding(.leading, 40)
                        settingsNumericSliderRow(
                            L10n.tr("settings.minShakeDistance"),
                            icon: "arrow.left.and.right",
                            iconColor: .mint,
                            value: $mouseCompanionShakeMinimumDistance,
                            in: 8...60,
                            step: 1,
                            valueFormatter: { L10n.tr("unit.px", Int($0)) }
                        )
                        Divider().padding(.leading, 40)
                        settingsNumericSliderRow(
                            L10n.tr("settings.minShakeSpeed"),
                            icon: "speedometer",
                            iconColor: .mint,
                            value: $mouseCompanionShakeMinimumSpeed,
                            in: 600...3000,
                            step: 50,
                            valueFormatter: { L10n.tr("unit.pxPerSecond", Int($0)) }
                        )
                    }
                }

                // Hooks
                settingsSection(L10n.tr("settings.section.hooks")) {
                    settingsInfoRow("Claude Code", icon: "c.circle.fill", iconColor: .orange, value: hookStatus(for: "claude"))
                    Divider().padding(.leading, 40)
                    settingsInfoRow("Codex CLI", icon: "x.circle.fill", iconColor: .green, value: hookStatus(for: "codex"))
                    Divider().padding(.leading, 40)
                    settingsInfoRow("Coco", icon: "c.square.fill", iconColor: .blue, value: hookStatus(for: "coco"))
                }

                // Data
                settingsSection(L10n.tr("settings.section.data")) {
                    settingsInfoRow(L10n.tr("settings.sessionsFile"), icon: "doc", iconColor: .gray, value: "~/.vibe-pet/sessions.json")
                    Divider().padding(.leading, 40)
                    settingsButtonRow(L10n.tr("settings.reinstallHooks"), icon: "arrow.triangle.2.circlepath", iconColor: .blue) {
                        HookInstaller().installAll()
                    }
                    Divider().padding(.leading, 40)
                    settingsButtonRow(L10n.tr("settings.uninstallHooks"), icon: "xmark.circle", iconColor: .red) {
                        HookInstaller().uninstallAll()
                    }
                    Divider().padding(.leading, 40)
                    settingsButtonRow(L10n.tr("settings.openDataFolder"), icon: "folder", iconColor: .blue) {
                        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".vibe-pet")
                        NSWorkspace.shared.open(url)
                    }
                }

                // Quit
                Button(action: { NSApplication.shared.terminate(nil) }) {
                    HStack {
                        Image(systemName: "power")
                        Text(L10n.tr("settings.quit"))
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
        .frame(width: 420, height: 660)
        .onAppear(perform: reloadDisplays)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            reloadDisplays()
        }
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

    private func settingsShakePresetRow(_ label: String, icon: String, iconColor: Color) -> some View {
        HStack(spacing: 10) {
            iconBadge(icon, color: iconColor)
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.primary)
            Spacer()
            HStack(spacing: 6) {
                shakePresetButton(L10n.tr("settings.shakePreset.low"), distance: 18, speed: 1300)
                shakePresetButton(L10n.tr("settings.shakePreset.medium"), distance: 22, speed: 1650)
                shakePresetButton(L10n.tr("settings.shakePreset.high"), distance: 30, speed: 2200)
            }
        }
        .frame(height: 32)
    }

    private func shakePresetButton(_ title: String, distance: Double, speed: Double) -> some View {
        Button(title) {
            mouseCompanionShakeMinimumDistance = distance
            mouseCompanionShakeMinimumSpeed = speed
        }
        .buttonStyle(.bordered)
        .controlSize(.mini)
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

    private func settingsNumericSliderRow(
        _ label: String,
        icon: String,
        iconColor: Color,
        value: Binding<Double>,
        in range: ClosedRange<Double>,
        step: Double,
        valueFormatter: @escaping (Double) -> String
    ) -> some View {
        HStack(spacing: 10) {
            iconBadge(icon, color: iconColor)
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.primary)
            Spacer()
            Slider(value: value, in: range, step: step)
                .frame(width: 120)
            Text(valueFormatter(value.wrappedValue))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 64, alignment: .trailing)
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

    private func settingsDisplayPickerRow(_ label: String, icon: String, iconColor: Color) -> some View {
        HStack(spacing: 10) {
            iconBadge(icon, color: iconColor)
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.primary)
            Spacer()
            Picker("", selection: $lockedDisplayID) {
                Text(L10n.tr("settings.builtinDisplayDefault"))
                    .tag("")
                ForEach(displayOptions) { option in
                    Text(option.name)
                        .tag(option.id)
                }
            }
            .labelsHidden()
            .frame(width: 190)
        }
        .frame(height: 32)
    }

    private func settingsAttentionPickerRow(_ label: String, icon: String, iconColor: Color) -> some View {
        HStack(spacing: 10) {
            iconBadge(icon, color: iconColor)
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.primary)
            Spacer()
            Picker("", selection: strongAttentionAnimationStyleBinding) {
                ForEach(AttentionAnimationVariant.strongOptions) { option in
                    Text(option.displayName)
                        .tag(option)
                }
            }
            .labelsHidden()
            .frame(width: 190)
        }
        .frame(height: 32)
    }

    private func settingsAttentionSoundCadenceRow(_ label: String, icon: String, iconColor: Color) -> some View {
        HStack(spacing: 10) {
            iconBadge(icon, color: iconColor)
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.primary)
            Spacer()
            Picker("", selection: strongAttentionSoundCadenceBinding) {
                ForEach(AttentionReminderSoundCadence.allCases) { option in
                    Text(option.displayName)
                        .tag(option)
                }
            }
            .labelsHidden()
            .frame(width: 190)
        }
        .frame(height: 32)
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
        let path: String
        switch source {
        case "claude": path = "\(home)/.claude/settings.json"
        case "codex": path = "\(home)/.codex/hooks.json"
        case "coco": path = "\(home)/.trae/traecli.yaml"
        default: return L10n.tr("settings.unknown")
        }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let str = String(data: data, encoding: .utf8) else {
            return L10n.tr("settings.notConfigured")
        }
        return str.contains("vibe-pet-bridge") ? L10n.tr("settings.active") : L10n.tr("settings.notConfigured")
    }

    private func reloadDisplays() {
        displayOptions = DisplayPreferences.availableDisplays()
        if !lockedDisplayID.isEmpty && !displayOptions.contains(where: { $0.id == lockedDisplayID }) {
            lockedDisplayID = ""
        }
    }

    private var strongAttentionAnimationStyleBinding: Binding<AttentionAnimationVariant> {
        Binding(
            get: { selectedStrongAttentionAnimationStyle },
            set: { strongAttentionAnimationStyleRawValue = $0.rawValue }
        )
    }

    private var selectedStrongAttentionAnimationStyle: AttentionAnimationVariant {
        AttentionAnimationVariant(rawValue: strongAttentionAnimationStyleRawValue) ?? AttentionAnimationPreferences.defaultStrongStyle
    }

    private var strongAttentionSoundEnabledBinding: Binding<Bool> {
        Binding(
            get: { resolvedStrongAttentionSoundEnabled },
            set: { strongAttentionAnimationSoundEnabledStored = $0 }
        )
    }

    private var resolvedStrongAttentionSoundEnabled: Bool {
        AttentionAnimationPreferences.resolvedSoundEnabled()
    }

    private var strongAttentionSoundCadenceBinding: Binding<AttentionReminderSoundCadence> {
        Binding(
            get: { selectedStrongAttentionSoundCadence },
            set: { strongAttentionAnimationSoundCadenceRawValue = $0.rawValue }
        )
    }

    private var selectedStrongAttentionSoundCadence: AttentionReminderSoundCadence {
        AttentionReminderSoundCadence(rawValue: strongAttentionAnimationSoundCadenceRawValue) ?? AttentionAnimationPreferences.defaultSoundCadence
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
