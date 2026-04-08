import Foundation

enum AttentionAnimationVariant: String, CaseIterable, Identifiable {
    case subtle
    case urgentPulse
    case goldenAlert
    case hyperRipple
    case attentionShake

    static let strongOptions: [AttentionAnimationVariant] = [
        .urgentPulse,
        .goldenAlert,
        .hyperRipple,
        .attentionShake
    ]

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .subtle:
            return "Default"
        case .urgentPulse:
            return "Urgent Pulse"
        case .goldenAlert:
            return "Golden Alert"
        case .hyperRipple:
            return "Hyper Ripple"
        case .attentionShake:
            return "Attention Shake"
        }
    }

    var settingsSummary: String {
        switch self {
        case .subtle:
            return "低干扰的默认提醒"
        case .urgentPulse:
            return "双击脉冲，主体和外圈同步强调"
        case .goldenAlert:
            return "高优先级单次爆发，边框与扩散同时放大"
        case .hyperRipple:
            return "连续波纹，不断向外扩散"
        case .attentionShake:
            return "抖动配合高亮，更像强制提醒"
        }
    }
}

enum AttentionReminderSoundCadence: String, CaseIterable, Identifiable {
    case everyCycle
    case everyTwoCycles
    case everyThreeCycles
    case everyFourCycles

    var id: String { rawValue }

    var cycleMultiplier: Int {
        switch self {
        case .everyCycle:
            return 1
        case .everyTwoCycles:
            return 2
        case .everyThreeCycles:
            return 3
        case .everyFourCycles:
            return 4
        }
    }

    var displayName: String {
        switch self {
        case .everyCycle:
            return "每轮"
        case .everyTwoCycles:
            return "每 2 轮"
        case .everyThreeCycles:
            return "每 3 轮"
        case .everyFourCycles:
            return "每 4 轮"
        }
    }

    var settingsSummary: String {
        "每 \(cycleMultiplier) 轮强提醒动画播放一次声音"
    }

    var interval: TimeInterval {
        AttentionAnimationPreferences.cycleDuration * Double(cycleMultiplier)
    }
}

enum AttentionAnimationPreferences {
    static let strongEnabledKey = "vibepet.strongAttentionAnimationEnabled"
    static let styleKey = "vibepet.strongAttentionAnimationStyle"
    static let soundEnabledKey = "vibepet.strongAttentionAnimationSoundEnabled"
    static let soundCadenceKey = "vibepet.strongAttentionAnimationSoundCadence"
    static let mouseCompanionCatEnabledKey = "vibepet.mouseCompanionCatEnabled"
    static let mouseCompanionBubbleEnabledKey = "vibepet.mouseCompanionBubbleEnabled"
    static let defaultStrongStyle: AttentionAnimationVariant = .urgentPulse
    static let defaultSoundCadence: AttentionReminderSoundCadence = .everyCycle
    static let cycleDuration: TimeInterval = 1.5

    static func resolvedVariant(defaults: UserDefaults = .standard) -> AttentionAnimationVariant {
        resolvedVariant(
            strongEnabled: defaults.bool(forKey: strongEnabledKey),
            styleRawValue: defaults.string(forKey: styleKey)
        )
    }

    static func resolvedVariant(strongEnabled: Bool, styleRawValue: String?) -> AttentionAnimationVariant {
        guard strongEnabled else { return .subtle }
        return AttentionAnimationVariant(rawValue: styleRawValue ?? "") ?? defaultStrongStyle
    }

    static func resolvedSoundEnabled(defaults: UserDefaults = .standard) -> Bool {
        if defaults.object(forKey: soundEnabledKey) != nil {
            return defaults.bool(forKey: soundEnabledKey)
        }
        if defaults.object(forKey: "vibepet.soundEnabled") != nil {
            return defaults.bool(forKey: "vibepet.soundEnabled")
        }
        return true
    }

    static func resolvedSoundCadence(defaults: UserDefaults = .standard) -> AttentionReminderSoundCadence {
        AttentionReminderSoundCadence(rawValue: defaults.string(forKey: soundCadenceKey) ?? "") ?? defaultSoundCadence
    }

    static func resolvedMouseCompanionCatEnabled(defaults: UserDefaults = .standard) -> Bool {
        if defaults.object(forKey: mouseCompanionCatEnabledKey) != nil {
            return defaults.bool(forKey: mouseCompanionCatEnabledKey)
        }
        return true
    }

    static func resolvedMouseCompanionBubbleEnabled(defaults: UserDefaults = .standard) -> Bool {
        if defaults.object(forKey: mouseCompanionBubbleEnabledKey) != nil {
            return defaults.bool(forKey: mouseCompanionBubbleEnabledKey)
        }
        return true
    }
}
