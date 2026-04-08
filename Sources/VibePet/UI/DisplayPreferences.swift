import AppKit
import CoreGraphics

enum DisplayPreferences {
    static let lockedDisplayIDKey = "vibepet.lockedDisplayID"

    static func resolvedScreen() -> NSScreen {
        let lockedDisplayID = UserDefaults.standard.string(forKey: lockedDisplayIDKey)
        return resolvedScreen(for: lockedDisplayID)
    }

    static func resolvedScreen(for lockedDisplayID: String?) -> NSScreen {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { fatalError("No screens available") }

        if let lockedDisplayID,
           !lockedDisplayID.isEmpty,
           let lockedScreen = screens.first(where: { $0.displayIDString == lockedDisplayID }) {
            return lockedScreen
        }

        if let builtInScreen = screens.first(where: \.isBuiltInDisplay) {
            return builtInScreen
        }

        return NSScreen.main ?? screens[0]
    }

    static func availableDisplays() -> [DisplayOption] {
        NSScreen.screens.enumerated().compactMap { index, screen in
            guard let displayID = screen.displayIDString else { return nil }
            return DisplayOption(
                id: displayID,
                name: screen.displayName(index: index)
            )
        }
    }
}

struct DisplayOption: Identifiable, Hashable {
    let id: String
    let name: String
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber).map { CGDirectDisplayID($0.uint32Value) }
    }

    var displayIDString: String? {
        displayID.map(String.init)
    }

    var notchWidth: CGFloat {
        let leftArea = auxiliaryTopLeftArea ?? .zero
        let rightArea = auxiliaryTopRightArea ?? .zero
        return frame.width - leftArea.width - rightArea.width
    }

    func centeredWidth(overflowPerSide: CGFloat) -> CGFloat {
        if hasUsableNotch {
            return notchWidth + overflowPerSide * 2
        }
        return frame.width
    }

    var hasUsableNotch: Bool {
        safeAreaInsets.top > 0 && notchWidth > 0
    }

    var menuBarHeight: CGFloat {
        safeAreaInsets.top > 0 ? safeAreaInsets.top : 24
    }

    var isBuiltInDisplay: Bool {
        guard let displayID else { return false }
        return CGDisplayIsBuiltin(displayID) != 0
    }

    func displayName(index: Int) -> String {
        if isBuiltInDisplay {
            return L10n.tr("display.builtin")
        }

        let baseName = localizedName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !baseName.isEmpty {
            return baseName
        }

        return L10n.tr("display.external.indexed", index + 1)
    }
}
