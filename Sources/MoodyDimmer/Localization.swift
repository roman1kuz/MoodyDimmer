import Foundation

/// UI language. `auto` follows the system languages and falls back to English.
enum AppLanguage: Int, CaseIterable {
    case auto = 0
    case english = 1
    case russian = 2
    case spanish = 3

    /// .lproj name; nil for `auto`.
    var code: String? {
        switch self {
        case .auto: nil
        case .english: "en"
        case .russian: "ru"
        case .spanish: "es"
        }
    }

    /// Languages are listed in their own language, so they are easy to find in any UI language.
    var title: String {
        switch self {
        case .auto: L("Match System")
        case .english: "English"
        case .russian: "Русский"
        case .spanish: "Español"
        }
    }
}

/// Picks the strings table for the chosen language and switches it at runtime, without a relaunch.
enum Localization {
    static let supported = AppLanguage.allCases.compactMap(\.code)
    private static var bundle = Bundle.main
    /// Locale of the current UI language (for case conversion and formatting).
    private(set) static var locale = Locale(identifier: "en")

    static func use(_ language: AppLanguage) {
        let code = language.code ?? systemCode()
        locale = Locale(identifier: code)
        if let path = Bundle.main.path(forResource: code, ofType: "lproj"), let b = Bundle(path: path) {
            bundle = b
        } else {
            bundle = Bundle.main
        }
    }

    /// The best match among the supported languages for the user's system languages; English otherwise.
    private static func systemCode() -> String {
        let match = Bundle.preferredLocalizations(from: supported, forPreferences: Locale.preferredLanguages).first
        return match.flatMap { supported.contains($0) ? $0 : nil } ?? "en"
    }

    static func string(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: key, table: nil)
    }
}

/// UI string in the current language (Resources/<lang>.lproj/Localizable.strings).
/// The English text is the key, so a missing translation falls back to English.
func L(_ key: String) -> String {
    Localization.string(key)
}
