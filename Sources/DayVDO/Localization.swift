import Foundation

@MainActor
enum L10n {
    private static var language = AppLanguage.system

    static func configure(language: AppLanguage) {
        self.language = language
    }

    static var languageCode: String {
        let localization = language.localizationIdentifier
            ?? resources.preferredLocalizations.first
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
              let path = resources.path(forResource: identifier, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return resources
        }
        return bundle
    }

    private static var resources: Bundle {
        if let resourceURL = Bundle.main.resourceURL,
           let appBundle = Bundle(
               url: resourceURL.appendingPathComponent("DayVDO_DayVDO.bundle")
           ) {
            return appBundle
        }
        return .module
    }
}
