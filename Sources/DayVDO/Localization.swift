import Foundation

@MainActor
enum L10n {
    private static var language = AppLanguage.system

    static func configure(language: AppLanguage) {
        self.language = language
    }

    static var languageCode: String {
        let localization = language.localizationIdentifier
            ?? Bundle.module.preferredLocalizations.first
            ?? Locale.current.language.languageCode?.identifier
            ?? "zh-Hans"
        return localization
            .replacingOccurrences(of: "_", with: "-")
            .split(separator: "-")
            .first
            .map(String.init)
            ?? "zh"
    }

    static var prefersCompactControls: Bool {
        ["zh", "ja", "ko"].contains(languageCode)
    }

    static func string(_ key: String) -> String {
        localizedBundle.localizedString(forKey: key, value: key, table: nil)
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: string(key), locale: locale, arguments: arguments)
    }

    static var locale: Locale {
        language.locale
    }

    private static var localizedBundle: Bundle {
        guard let identifier = language.localizationIdentifier,
              let path = Bundle.module.path(forResource: identifier, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return .module
        }
        return bundle
    }
}
