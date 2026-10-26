import Foundation

@MainActor
enum L10n {
    private static var language = AppLanguage.system
    private static var bundles: [AppLanguage: Bundle] = [:]

    static func configure(language: AppLanguage) {
        self.language = language
    }

    static var languageCode: String {
        let localization = language.localizationIdentifier
            ?? systemLocalization
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
        if let cached = bundles[language] { return cached }
        let bundle = resolveBundle()
        bundles[language] = bundle
        return bundle
    }

    private static func resolveBundle() -> Bundle {
        guard let identifier = language.localizationIdentifier ?? systemLocalization,
              let path = resources.path(forResource: identifier, ofType: "lproj")
                ?? resources.path(forResource: identifier.lowercased(), ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return resources
        }
        return bundle
    }

    static func preferredLocalization(for preferredLanguages: [String]) -> String? {
        Bundle.preferredLocalizations(from: resources.localizations, forPreferences: preferredLanguages).first
    }

    private static let systemLocalization = preferredLocalization(for: Locale.preferredLanguages)

    private static let resources: Bundle = {
        if let resourceURL = Bundle.main.resourceURL,
           let appBundle = Bundle(
               url: resourceURL.appendingPathComponent("DayVDO_DayVDO.bundle")
           ) {
            return appBundle
        }
        return .module
    }()
}
