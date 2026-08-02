import Foundation

enum L10n {
    static func text(_ key: String) -> String {
        NSLocalizedString(
            key,
            tableName: nil,
            bundle: localizationBundle,
            value: key,
            comment: ""
        )
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: formattingLocale, arguments: arguments)
    }

    /// Production always follows macOS. UI tests may select one bundled
    /// localization directly because the macOS XCTest runner does not reliably
    /// recreate SwiftUI windows after changing the global AppleLanguages domain.
    private static var testLanguage: String? {
        ProcessInfo.processInfo.arguments
            .first { $0.hasPrefix("--ui-test-language=") }?
            .split(separator: "=", maxSplits: 1)
            .last
            .map(String.init)
    }

    private static var localizationBundle: Bundle {
        guard let language = testLanguage,
              ["en", "fr"].contains(language),
              let path = Bundle.main.path(forResource: language, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return .main
        }
        return bundle
    }

    private static var formattingLocale: Locale {
        switch testLanguage {
        case "fr": return Locale(identifier: "fr_FR")
        case "en": return Locale(identifier: "en_US")
        default: return .current
        }
    }
}
