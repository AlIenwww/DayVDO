import Foundation

enum AppLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case system
    case simplifiedChinese
    case traditionalChinese
    case english
    case japanese
    case korean
    case spanish
    case french
    case german

    var id: String { rawValue }

    @MainActor var title: String {
        switch self {
        case .system: L10n.string("系统默认")
        case .simplifiedChinese: "简体中文"
        case .traditionalChinese: "繁體中文"
        case .english: "English"
        case .japanese: "日本語"
        case .korean: "한국어"
        case .spanish: "Español"
        case .french: "Français"
        case .german: "Deutsch"
        }
    }

    var localizationIdentifier: String? {
        switch self {
        case .system: nil
        case .simplifiedChinese: "zh-Hans"
        case .traditionalChinese: "zh-Hant"
        case .english: "en"
        case .japanese: "ja"
        case .korean: "ko"
        case .spanish: "es"
        case .french: "fr"
        case .german: "de"
        }
    }

    var locale: Locale {
        localizationIdentifier.map(Locale.init(identifier:)) ?? .autoupdatingCurrent
    }
}

enum AppearanceMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case automatic
    case light
    case dark

    var id: String { rawValue }

    @MainActor var title: String {
        switch self {
        case .automatic: L10n.string("自动")
        case .light: L10n.string("白天")
        case .dark: L10n.string("深夜")
        }
    }
}

struct AppSettings: Codable, Equatable, Sendable {
    var showCompleted = true
    var startWeekOnMonday = true
    var defaultPriority = TodoItem.Priority.none
    var confirmBeforeDeleting = true
    var language = AppLanguage.system
    var appearance = AppearanceMode.automatic

    private enum CodingKeys: String, CodingKey {
        case showCompleted
        case startWeekOnMonday
        case defaultPriority
        case confirmBeforeDeleting
        case language
        case appearance
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        showCompleted = try container.decodeIfPresent(Bool.self, forKey: .showCompleted) ?? true
        startWeekOnMonday = try container.decodeIfPresent(Bool.self, forKey: .startWeekOnMonday) ?? true
        defaultPriority = try container.decodeIfPresent(
            TodoItem.Priority.self,
            forKey: .defaultPriority
        ) ?? .none
        confirmBeforeDeleting = try container.decodeIfPresent(
            Bool.self,
            forKey: .confirmBeforeDeleting
        ) ?? true
        language = try container.decodeIfPresent(AppLanguage.self, forKey: .language) ?? .system
        appearance = try container.decodeIfPresent(AppearanceMode.self, forKey: .appearance) ?? .automatic
    }
}
