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
            return L10n.tr("attention.variant.subtle.name")
        case .urgentPulse:
            return L10n.tr("attention.variant.urgentPulse.name")
        case .goldenAlert:
            return L10n.tr("attention.variant.goldenAlert.name")
        case .hyperRipple:
            return L10n.tr("attention.variant.hyperRipple.name")
        case .attentionShake:
            return L10n.tr("attention.variant.attentionShake.name")
        }
    }

    var settingsSummary: String {
        switch self {
        case .subtle:
            return L10n.tr("attention.variant.subtle.summary")
        case .urgentPulse:
            return L10n.tr("attention.variant.urgentPulse.summary")
        case .goldenAlert:
            return L10n.tr("attention.variant.goldenAlert.summary")
        case .hyperRipple:
            return L10n.tr("attention.variant.hyperRipple.summary")
        case .attentionShake:
            return L10n.tr("attention.variant.attentionShake.summary")
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
            return L10n.tr("attention.cadence.everyCycle.name")
        case .everyTwoCycles:
            return L10n.tr("attention.cadence.everyTwoCycles.name")
        case .everyThreeCycles:
            return L10n.tr("attention.cadence.everyThreeCycles.name")
        case .everyFourCycles:
            return L10n.tr("attention.cadence.everyFourCycles.name")
        }
    }

    var settingsSummary: String {
        L10n.tr("attention.cadence.summary", cycleMultiplier)
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
    static let proactivePopupEnabledKey = "vibepet.proactiveAttentionPopupEnabled"
    static let proactivePopupAutoCollapseDelayKey = "vibepet.proactiveAttentionPopupAutoCollapseDelay"
    static let mouseCompanionCatEnabledKey = "vibepet.mouseCompanionCatEnabled"
    static let mouseCompanionBubbleEnabledKey = "vibepet.mouseCompanionBubbleEnabled"
    static let mouseCompanionShakeDismissEnabledKey = "vibepet.mouseCompanionShakeDismissEnabled"
    static let mouseCompanionShakeMinimumDistanceKey = "vibepet.mouseCompanionShakeMinimumDistance"
    static let mouseCompanionShakeMinimumSpeedKey = "vibepet.mouseCompanionShakeMinimumSpeed"
    static let defaultStrongStyle: AttentionAnimationVariant = .urgentPulse
    static let defaultSoundCadence: AttentionReminderSoundCadence = .everyCycle
    static let cycleDuration: TimeInterval = 1.5
    static let defaultProactivePopupAutoCollapseDelay: TimeInterval = 2.5
    static let defaultMouseCompanionShakeMinimumDistance: Double = 22
    static let defaultMouseCompanionShakeMinimumSpeed: Double = 1650

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

    static func resolvedProactivePopupEnabled(defaults: UserDefaults = .standard) -> Bool {
        if defaults.object(forKey: proactivePopupEnabledKey) != nil {
            return defaults.bool(forKey: proactivePopupEnabledKey)
        }
        return true
    }

    static func resolvedProactivePopupAutoCollapseDelay(defaults: UserDefaults = .standard) -> TimeInterval {
        if defaults.object(forKey: proactivePopupAutoCollapseDelayKey) != nil {
            return defaults.double(forKey: proactivePopupAutoCollapseDelayKey)
        }
        return defaultProactivePopupAutoCollapseDelay
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

    static func resolvedMouseCompanionShakeDismissEnabled(defaults: UserDefaults = .standard) -> Bool {
        if defaults.object(forKey: mouseCompanionShakeDismissEnabledKey) != nil {
            return defaults.bool(forKey: mouseCompanionShakeDismissEnabledKey)
        }
        return true
    }

    static func resolvedMouseCompanionShakeMinimumDistance(defaults: UserDefaults = .standard) -> CGFloat {
        if defaults.object(forKey: mouseCompanionShakeMinimumDistanceKey) != nil {
            return CGFloat(defaults.double(forKey: mouseCompanionShakeMinimumDistanceKey))
        }
        return CGFloat(defaultMouseCompanionShakeMinimumDistance)
    }

    static func resolvedMouseCompanionShakeMinimumSpeed(defaults: UserDefaults = .standard) -> CGFloat {
        if defaults.object(forKey: mouseCompanionShakeMinimumSpeedKey) != nil {
            return CGFloat(defaults.double(forKey: mouseCompanionShakeMinimumSpeedKey))
        }
        return CGFloat(defaultMouseCompanionShakeMinimumSpeed)
    }
}
