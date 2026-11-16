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
        case .system: L10n.systemString("系统默认")
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

enum StartupPage: String, Codable, CaseIterable, Identifiable, Sendable {
    case today, calendar, all
    var id: String { rawValue }
    var destination: SidebarDestination { SidebarDestination(rawValue: rawValue) ?? .today }
    var title: String { destination.title }
}

struct AppSettings: Codable, Equatable, Sendable {
    var startupPage = StartupPage.today
    var defaultUrgency = TodoItem.Urgency.none
    var defaultScheduleMinutes = 30
    var estimatedDurationUnit = EstimatedDurationUnit.mixed
    var showCompleted = true
    var startWeekOnMonday = true
    var defaultPriority = TodoItem.Priority.none
    var confirmBeforeDeleting = true
    var language = AppLanguage.system
    var appearance = AppearanceMode.automatic
    var themeColor: TagColor?
    var shortcutOverrides: [String: CommandShortcut] = [:]
    var disabledAnimations: Set<AppAnimationEffect> = []

    func shortcut(for command: AppCommand) -> CommandShortcut {
        shortcutOverrides[command.rawValue] ?? command.defaultShortcut
    }

    func shortcutConflict(_ shortcut: CommandShortcut, excluding command: AppCommand) -> AppCommand? {
        AppCommand.allCases.first { $0 != command && self.shortcut(for: $0) == shortcut }
    }

    @discardableResult
    mutating func assignShortcut(_ shortcut: CommandShortcut, to command: AppCommand) -> Bool {
        guard shortcut.isSupported, shortcutConflict(shortcut, excluding: command) == nil else { return false }
        shortcutOverrides[command.rawValue] = shortcut == command.defaultShortcut ? nil : shortcut
        return true
    }

    func animates(_ effect: AppAnimationEffect) -> Bool {
        !disabledAnimations.contains(effect)
    }

    private enum CodingKeys: String, CodingKey {
        case startupPage, defaultUrgency, defaultScheduleMinutes
        case estimatedDurationUnit
        case showCompleted
        case startWeekOnMonday
        case defaultPriority
        case confirmBeforeDeleting
        case language
        case appearance
        case themeColor, shortcutOverrides, disabledAnimations
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        startupPage = (try? container.decode(StartupPage.self, forKey: .startupPage)) ?? .today
        defaultUrgency = (try? container.decode(TodoItem.Urgency.self, forKey: .defaultUrgency)) ?? .none
        let minutes = (try? container.decode(Int.self, forKey: .defaultScheduleMinutes)) ?? 30
        defaultScheduleMinutes = (1...1440).contains(minutes) ? minutes : 30
        estimatedDurationUnit = (try? container.decode(EstimatedDurationUnit.self, forKey: .estimatedDurationUnit)) ?? .mixed
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
        themeColor = try? container.decode(TagColor.self, forKey: .themeColor)
        shortcutOverrides = ((try? container.decode([String: CommandShortcut].self, forKey: .shortcutOverrides)) ?? [:])
            .filter { AppCommand(rawValue: $0.key) != nil && $0.value.isSupported }
        disabledAnimations = Set(((try? container.decode([String].self, forKey: .disabledAnimations)) ?? [])
            .compactMap(AppAnimationEffect.init(rawValue:)))
    }
}
