import AppKit

enum LocalizedControlSizing {
    static func popUpWidth(for titles: [String]) -> CGFloat {
        clamped(maximumTextWidth(in: titles) + 58, minimum: 92, maximum: 176)
    }

    static func segmentedWidth(for titles: [String]) -> CGFloat {
        guard !titles.isEmpty else { return 220 }
        let segmentWidth = clamped(maximumTextWidth(in: titles) + 30, minimum: 70, maximum: 112)
        return segmentWidth * CGFloat(titles.count)
    }

    static func menuLabelWidth(for titles: [String]) -> CGFloat {
        clamped(maximumTextWidth(in: titles) + 34, minimum: 88, maximum: 184)
    }

    private static func maximumTextWidth(in titles: [String]) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize)
        ]
        return titles
            .map { ceil(($0 as NSString).size(withAttributes: attributes).width) }
            .max() ?? 0
    }

    private static func clamped(_ value: CGFloat, minimum: CGFloat, maximum: CGFloat) -> CGFloat {
        min(max(value, minimum), maximum)
    }
}
