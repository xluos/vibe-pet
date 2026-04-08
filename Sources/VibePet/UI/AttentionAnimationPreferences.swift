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

enum AttentionAnimationPreferences {
    static let strongEnabledKey = "vibepet.strongAttentionAnimationEnabled"
    static let styleKey = "vibepet.strongAttentionAnimationStyle"
    static let defaultStrongStyle: AttentionAnimationVariant = .urgentPulse

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
}
