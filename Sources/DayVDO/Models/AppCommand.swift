import AppKit
import SwiftUI

enum AppCommand: String, CaseIterable, Identifiable {
    case newTodo, newProject, search, today, calendar, all, settings, settingsAlternate, undo, redo

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newTodo: "新建待办"
        case .newProject: "新建大项目"
        case .search: "搜索待办"
        case .today: "今日待办"
        case .calendar: "日历"
        case .all: "总待办"
        case .settings: "设置"
        case .settingsAlternate: "设置（备用）"
        case .undo: "撤销"
        case .redo: "重做"
        }
    }

    var defaultShortcut: CommandShortcut {
        switch self {
        case .newTodo: .init(key: "n")
        case .newProject: .init(key: "n", shift: true)
        case .search: .init(key: "f")
        case .today: .init(key: "1")
        case .calendar: .init(key: "2")
        case .all: .init(key: "3")
        case .settings: .init(key: ",")
        case .settingsAlternate: .init(key: "4")
        case .undo: .init(key: "z")
        case .redo: .init(key: "z", shift: true)
        }
    }
}

struct CommandShortcut: Codable, Equatable, Sendable {
    var key: String
    var command = true
    var option = false
    var control = false
    var shift = false

    var isSupported: Bool {
        guard command || control else { return false }
        if Self.specialKeys[key] != nil { return true }
        guard key.utf8.count == 1, let byte = key.utf8.first, (33...126).contains(byte),
              key == key.lowercased() else { return false }
        // Keep standard text-editing and app/window commands available.
        if command && !control && !option {
            if ["q", "w", "m", "h", "`"].contains(key) { return false }
            if !shift && ["a", "c", "v", "x"].contains(key) { return false }
        }
        if command && option && !control && ["h", "m", "w"].contains(key) { return false }
        return true
    }

    var display: String {
        (control ? "⌃" : "") + (option ? "⌥" : "") + (shift ? "⇧" : "")
            + (command ? "⌘" : "") + (Self.specialLabels[key] ?? key.uppercased())
    }

    var keyboardShortcut: KeyboardShortcut? {
        guard isSupported, let character = key.first else { return nil }
        let equivalent = Self.specialKeys[key] ?? KeyEquivalent(character)
        var modifiers: EventModifiers = []
        if command { modifiers.insert(.command) }
        if option { modifiers.insert(.option) }
        if control { modifiers.insert(.control) }
        if shift { modifiers.insert(.shift) }
        return KeyboardShortcut(equivalent, modifiers: modifiers, localization: .withoutMirroring)
    }

    @MainActor
    static func capture(_ event: NSEvent) -> CommandShortcut? {
        guard let characters = event.characters(byApplyingModifiers: [])?.lowercased() else { return nil }
        let key = Self.specialKeys.first { String($0.value.character) == characters }?.key ?? characters
        let flags = event.modifierFlags
        return CommandShortcut(key: key, command: flags.contains(.command),
            option: flags.contains(.option), control: flags.contains(.control), shift: flags.contains(.shift))
    }

    private static let specialKeys: [String: KeyEquivalent] = {
        var keys: [String: KeyEquivalent] = [
            "up": .upArrow, "down": .downArrow, "left": .leftArrow, "right": .rightArrow,
            "home": .home, "end": .end, "pageUp": .pageUp, "pageDown": .pageDown,
            "delete": .delete, "deleteForward": .deleteForward
        ]
        for index in 1...20 {
            if let scalar = UnicodeScalar(NSF1FunctionKey + index - 1) {
                keys["f\(index)"] = KeyEquivalent(Character(scalar))
            }
        }
        return keys
    }()

    private static let specialLabels = [
        "up": "↑", "down": "↓", "left": "←", "right": "→",
        "home": "↖", "end": "↘", "pageUp": "⇞", "pageDown": "⇟",
        "delete": "⌫", "deleteForward": "⌦"
    ]
}
