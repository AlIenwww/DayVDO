import Foundation

@MainActor
enum L10n {
    private static var language = AppLanguage.system
    private static var bundles: [String: Bundle] = [:]
    private static var systemLocalization = resolveSystemLocalization()

    static func configure(language: AppLanguage) {
        if language == .system { systemLocalization = resolveSystemLocalization() }
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
        bundle(for: language.localizationIdentifier ?? systemLocalization)
            .localizedString(forKey: key, value: key, table: nil)
    }

    static func systemString(_ key: String) -> String {
        bundle(for: systemLocalization).localizedString(forKey: key, value: key, table: nil)
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: string(key), locale: locale, arguments: arguments)
    }

    static var locale: Locale {
        language.locale
    }

    private static func bundle(for identifier: String?) -> Bundle {
        guard let identifier else { return resources }
        if let cached = bundles[identifier] { return cached }
        guard let path = resources.path(forResource: identifier, ofType: "lproj")
                ?? resources.path(forResource: identifier.lowercased(), ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return resources
        }
        bundles[identifier] = bundle
        return bundle
    }

    static func preferredLocalization(for preferredLanguages: [String]) -> String? {
        Bundle.preferredLocalizations(from: resources.localizations, forPreferences: preferredLanguages).first
    }

    private static func resolveSystemLocalization() -> String? {
        // macOS can supply a per-app AppleLanguages value ahead of the global one.
        let globalLanguages = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["AppleLanguages"] as? [String]
        return preferredLocalization(for: globalLanguages ?? Locale.preferredLanguages)
    }

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
