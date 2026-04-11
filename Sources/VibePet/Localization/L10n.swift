import Foundation

enum L10n {
    static let languageKey = "vibepet.language"
    static let languageDidChangeNotification = Notification.Name("vibepet.languageDidChange")

    private static let table = "Localizable"
    private static let bundle = Bundle.module
    private static let fallbackLanguageCode = "en"

    static func tr(_ key: String) -> String {
        localizedBundle.localizedString(forKey: key, value: key, table: table)
    }

    static func tr(_ key: String, _ args: CVarArg...) -> String {
        let format = tr(key)
        return String(format: format, locale: Locale.current, arguments: args)
    }

    static func setLanguage(_ code: String) {
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let current = UserDefaults.standard.string(forKey: languageKey) ?? ""
        guard current != normalized else { return }
        UserDefaults.standard.set(normalized, forKey: languageKey)
        NotificationCenter.default.post(name: languageDidChangeNotification, object: nil)
    }

    private static var localizedBundle: Bundle {
        let selected = UserDefaults.standard.string(forKey: languageKey) ?? ""
        let resolvedLanguage = selected.isEmpty ? preferredSystemLanguageCode : supportedLanguageCode(for: selected)

        // SPM .process() lowercases lproj directory names (e.g. "zh-Hans" -> "zh-hans"),
        // so try the lowercased variant as a fallback.
        for candidate in [resolvedLanguage, resolvedLanguage.lowercased()] {
            if let path = bundle.path(forResource: candidate, ofType: "lproj"),
               let localized = Bundle(path: path) {
                return localized
            }
        }
        return bundle
    }

    private static var preferredSystemLanguageCode: String {
        for preferredLanguage in Locale.preferredLanguages {
            let resolved = supportedLanguageCode(for: preferredLanguage)
            if resolved != fallbackLanguageCode || preferredLanguage.lowercased().hasPrefix("en") {
                return resolved
            }
        }

        if let bundlePreferred = bundle.preferredLocalizations.first {
            return supportedLanguageCode(for: bundlePreferred)
        }

        return fallbackLanguageCode
    }

    private static func supportedLanguageCode(for identifier: String) -> String {
        let normalized = identifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()

        if normalized == "zh" || normalized.hasPrefix("zh-") {
            return "zh-Hans"
        }

        if normalized == "en" || normalized.hasPrefix("en-") {
            return "en"
        }

        return fallbackLanguageCode
    }
}
