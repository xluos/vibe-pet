import Foundation

enum L10n {
    static let languageKey = "vibepet.language"
    static let languageDidChangeNotification = Notification.Name("vibepet.languageDidChange")

    private static let table = "Localizable"
    private static let bundle = Bundle.module

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
        guard !selected.isEmpty else { return bundle }
        // SPM .process() lowercases lproj directory names (e.g. "zh-Hans" -> "zh-hans"),
        // so try the lowercased variant as a fallback.
        for candidate in [selected, selected.lowercased()] {
            if let path = bundle.path(forResource: candidate, ofType: "lproj"),
               let localized = Bundle(path: path) {
                return localized
            }
        }
        return bundle
    }
}
