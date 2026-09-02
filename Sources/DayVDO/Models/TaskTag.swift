import AppKit
import Foundation
import SwiftUI

struct TagColor: Codable, Hashable, Sendable {
    var red: Double
    var green: Double
    var blue: Double

    static let defaultBlue = TagColor(red: 0.20, green: 0.48, blue: 0.95)

    var color: Color {
        Color(red: red, green: green, blue: blue)
    }

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    init(color: Color) {
        let resolved = NSColor(color).usingColorSpace(.sRGB) ?? .systemBlue
        red = Double(resolved.redComponent)
        green = Double(resolved.greenComponent)
        blue = Double(resolved.blueComponent)
    }
}

struct TaskTag: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var color: TagColor
    var createdAt: Date
    var sortOrder: Int

    init(
        id: UUID = UUID(),
        name: String,
        color: TagColor = .defaultBlue,
        createdAt: Date = .now,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.createdAt = createdAt
        self.sortOrder = sortOrder
    }

    var normalizedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
