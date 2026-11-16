import SwiftUI

/// Vector miniatures share the app's visual vocabulary, without rendering real user data.
enum SettingsIllustrationScene {
    case animation(AppAnimationEffect)
    case concept(GlossaryTerm)
}

struct SettingsIllustration: View {
    @Environment(\.colorScheme) private var colorScheme
    let scene: SettingsIllustrationScene
    var progress: CGFloat = 1
    var tint: Color = .accentColor

    var body: some View {
        let minuteLabel = L10n.string("分钟")
        return Canvas { context, size in
            let concept: Bool = if case .concept = scene { true } else { false }
            let logical = concept ? CGSize(width: 180, height: 120) : CGSize(width: 360, height: 200)
            context.scaleBy(x: size.width / logical.width, y: size.height / logical.height)
            let drawing = IllustrationDrawing(context: context, tint: tint, dark: colorScheme == .dark, minuteLabel: minuteLabel)
            switch scene {
            case .animation(let effect): drawing.animation(effect, progress: progress)
            case .concept(let term): drawing.concept(term)
            }
        }
        .aspectRatio(scene.aspectRatio, contentMode: .fit)
        .background(tint.opacity(colorScheme == .dark ? 0.08 : 0.045))
        .clipShape(.rect(cornerRadius: 10))
        .accessibilityHidden(true) // The adjacent title and explanation describe the same content.
        .allowsHitTesting(false)
    }
}

private extension SettingsIllustrationScene {
    var aspectRatio: CGFloat {
        if case .concept = self { 1.5 } else { 1.8 }
    }
}

private struct IllustrationDrawing {
    var context: GraphicsContext
    let tint: Color
    let dark: Bool
    let minuteLabel: String
    private var surface: Color { dark ? Color(white: 0.19) : .white }
    private var ink: Color { dark ? Color(white: 0.84) : Color(white: 0.28) }
    private var faint: Color { ink.opacity(0.13) }

    private func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat,
                     _ color: Color, radius: CGFloat = 4) {
        guard w > 0, h > 0 else { return }
        context.fill(Path(roundedRect: CGRect(x: x, y: y, width: w, height: h),
                          cornerRadius: radius), with: .color(color))
    }

    private func line(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, color: Color? = nil, height: CGFloat = 4) {
        box(x, y, w, height, color ?? faint, radius: height / 2)
    }

    private func symbol(_ name: String, _ x: CGFloat, _ y: CGFloat, size: CGFloat = 14, color: Color? = nil) {
        context.draw(Text(Image(systemName: name)).font(.system(size: size, weight: .medium))
            .foregroundStyle(color ?? tint), at: CGPoint(x: x, y: y))
    }

    private func text(_ value: String, _ x: CGFloat, _ y: CGFloat, size: CGFloat = 9) {
        context.draw(Text(verbatim: value).font(.system(size: size, weight: .medium, design: .rounded))
            .foregroundStyle(ink.opacity(0.65)), at: CGPoint(x: x, y: y))
    }

    private func todo(_ x: CGFloat, _ y: CGFloat, width: CGFloat = 190, highlight: Bool = false,
                      checked: Bool = false, opacity: Double = 1) {
        box(x, y, width, 29, (highlight ? tint.opacity(0.16) : surface).opacity(opacity), radius: 5)
        symbol(checked ? "checkmark.circle.fill" : "circle", x + 14, y + 14,
               size: 12, color: (checked ? tint : ink.opacity(0.35)).opacity(opacity))
        line(x + 28, y + 10, width * 0.48, color: ink.opacity((checked ? 0.26 : 0.55) * opacity))
        line(x + 28, y + 19, width * 0.28, color: faint.opacity(opacity), height: 3)
        if checked { line(x + 26, y + 12, width * 0.5, color: ink.opacity(0.5 * opacity), height: 1) }
    }

    private func window() {
        box(20, 14, 320, 172, surface, radius: 9)
        box(20, 14, 320, 22, faint.opacity(0.5), radius: 9)
        for i in 0..<3 { box(30 + CGFloat(i) * 9, 23, 5, 5, ink.opacity(0.2), radius: 3) }
        box(20, 36, 66, 150, faint.opacity(0.4), radius: 0)
        for i in 0..<4 {
            box(28, 50 + CGFloat(i) * 23, 49, 17, i == 1 ? tint.opacity(0.16) : .clear)
            line(35, 57 + CGFloat(i) * 23, 32, color: i == 1 ? tint.opacity(0.7) : faint)
        }
        line(100, 48, 61, color: ink.opacity(0.55), height: 5)
    }

    func animation(_ effect: AppAnimationEffect, progress: CGFloat) {
        window()
        let p = min(1, max(0, progress))
        switch effect {
        case .completion:
            todo(100, 72, width: 223, highlight: true, opacity: Double(1 - p))
            todo(100, 72, width: 223, highlight: true, checked: true, opacity: Double(p))
            todo(100, 108, width: 223)
            todo(100, 144, width: 223)
            pointer(118, 87, pressed: p > 0.3 && p < 0.6)
        case .planningSections:
            line(103, 69, 68, color: tint.opacity(0.7))
            todo(100, 81, width: 223)
            line(103, 120 + 35 * (1 - p), 56, color: tint.opacity(0.7))
            todo(100, 130 + 35 * (1 - p), width: 223, highlight: true)
            todo(100, 116, width: 223, opacity: Double(1 - p))
            symbol("chevron.down", 315, 71, size: 9)
        case .allTodosList:
            todo(100, 72, width: 223, opacity: Double(1 - p))
            let y = 108 - 36 * p
            symbol("folder.fill", 110, y + 12, size: 11)
            line(124, y + 11, 80, color: ink.opacity(0.55))
            todo(100, 144 - 36 * p, width: 223)
        case .projectDisclosure:
            symbol(p > 0.5 ? "chevron.down" : "chevron.right", 110, 77, size: 9)
            symbol("folder.fill", 130, 77)
            line(146, 75, 86, color: ink.opacity(0.55))
            var children = self
            children.context.clip(to: Path(CGRect(x: 112, y: 94, width: 214, height: 78 * p)))
            children.todo(118, 98, width: 205)
            children.todo(118, 134, width: 205)
            pointer(111, 78, pressed: p > 0.1 && p < 0.4)
        case .projectReorder:
            symbol("folder.fill", 109, 66, size: 11)
            line(122, 64, 77, color: ink.opacity(0.55))
            todo(100, 113 - 34 * p, width: 223)
            todo(100, 147, width: 223)
            line(100, 107 + 34 * p, 223, color: tint, height: 2)
            todo(104, 79 + 34 * p, width: 223, highlight: true)
            pointer(265, 97 + 34 * p, pressed: true)
        case .listControls:
            todo(100, 75, width: 223)
            todo(100, 111, width: 223)
            box(101, 151, 222, 23, tint.opacity(0.07 * Double(p)))
            symbol("plus", 112, 162, size: 11, color: tint.opacity(Double(p)))
            line(125, 160, 64, color: tint.opacity(0.7 * Double(p)))
            pointer(257, 177 - 15 * p)
        case .calendarScroll:
            var grid = self
            grid.context.clip(to: Path(CGRect(x: 99, y: 66, width: 225, height: 108)))
            grid.calendar(x: 99, y: 66 - 36 * p, width: 225, rows: 5)
            symbol("chevron.down", 214, 178, size: 9)
        case .calendarDrag:
            calendar(x: 99, y: 66, width: 225)
            let x = 103 + 96 * p
            box(x, 81, 57, 10, tint.opacity(0.75))
            pointer(x + 24, 89, pressed: p > 0 && p < 1)
        case .calendarTaskStatus:
            calendar(x: 99, y: 66, width: 225)
            box(103, 79, 80, 15, tint.opacity(Double(0.24 - 0.12 * p)))
            let progressOpacity = max(0, 1 - abs(2 * p - 1))
            symbol("circle", 111, 86, size: 8, color: ink.opacity(Double(max(0, 1 - 2 * p))))
            symbol("circle.lefthalf.filled", 111, 86, size: 8,
                color: .orange.opacity(Double(progressOpacity)))
            symbol("checkmark.circle.fill", 111, 86, size: 8 + sin(.pi * p) * 1.5,
                color: tint.opacity(Double(max(0, 2 * p - 1))))
            line(119, 85, 55, color: ink.opacity(Double(0.65 - 0.30 * p)), height: 2)
            line(119, 86, 55, color: ink.opacity(Double(max(0, 2 * p - 1))), height: 0.5)
        case .calendarInspector:
            var grid = self
            grid.context.clip(to: Path(CGRect(x: 99, y: 66, width: 225 - 92 * p, height: 108)))
            grid.calendar(x: 99, y: 66, width: 225 - 92 * p)
            box(329 - 91 * p, 62, 91 * p, 116, faint.opacity(0.4))
            var inspector = self
            inspector.context.opacity = Double(p)
            inspector.symbol("calendar", 252, 77, size: 12)
            inspector.line(245, 94, 62, color: tint.opacity(0.7))
            inspector.line(245, 108, 48)
            inspector.line(245, 125, 58)
            inspector.box(245, 144, 63, 20, tint.opacity(0.16))
        case .timelineZoom:
            var timeline = self
            timeline.context.clip(to: Path(CGRect(x: 99, y: 65, width: 225, height: 110)))
            let hour: CGFloat = 35 + 31 * p
            for i in -1..<4 {
                let y = 116 + CGFloat(i) * hour
                timeline.text(String(format: "%02d:00", 10 + i), 116, y)
                timeline.line(138, y, 183, height: 1)
            }
            timeline.box(144, 116 - hour / 2, 173, hour * 0.75, tint.opacity(0.2))
            timeline.line(155, 123 - hour / 2, 82, color: tint.opacity(0.85))
            symbol("plus.magnifyingglass", 307, 49, size: 11)
        }
    }

    private func calendar(x: CGFloat, y: CGFloat, width: CGFloat, rows: Int = 3) {
        let column = width / 7
        for row in 0..<rows {
            for col in 0..<7 {
                let left = x + CGFloat(col) * column
                let top = y + CGFloat(row) * 36
                box(left + 1, top + 1, column - 2, 34, faint.opacity(0.25), radius: 2)
                line(left + 5, top + 6, 7, height: 2)
                if (row * 3 + col) % 4 == 0 {
                    box(left + 3, top + 16, column - 6, 7, tint.opacity(0.35), radius: 2)
                }
            }
        }
    }

    private func pointer(_ x: CGFloat, _ y: CGFloat, pressed: Bool = false) {
        if pressed {
            context.stroke(Path(ellipseIn: CGRect(x: x - 10, y: y - 10, width: 20, height: 20)),
                           with: .color(tint.opacity(0.5)), lineWidth: 2)
        }
        symbol("cursorarrow", x + 4, y + 7, size: 16, color: ink)
    }

    func concept(_ term: GlossaryTerm) {
        switch term {
        case .todo:
            todo(17, 25, width: 146, highlight: true)
            todo(17, 64, width: 146)
            symbol("calendar", 55, 46, size: 7)
            symbol("tag.fill", 71, 46, size: 7)
            symbol("clock", 87, 46, size: 7)
        case .schedule:
            for i in 0..<3 {
                let y = 23 + CGFloat(i) * 37
                text(String(format: "%02d:00", 9 + i), 28, y)
                line(49, y, 112, height: 1)
            }
            box(55, 29, 105, 54, tint.opacity(0.2))
            line(65, 40, 70, color: tint.opacity(0.8))
            symbol("link", 67, 65, size: 11)
            line(79, 63, 59)
        case .project:
            symbol("folder.fill", 34, 23, size: 20)
            line(52, 20, 89, color: tint.opacity(0.8))
            line(32, 43, 2, height: 53)
            for i in 0..<2 {
                let y = 43 + CGFloat(i) * 35
                line(32, y + 13, 14, height: 1)
                todo(47, y, width: 116)
            }
        case .tag:
            for i in 0..<2 {
                let y = 23 + CGFloat(i) * 51
                symbol("folder", 24, y + 14, size: 12, color: ink.opacity(0.45))
                todo(38, y, width: 124)
                box(124, y + 8, 28, 13, tint.opacity(0.2), radius: 6)
                symbol("tag.fill", 138, y + 14, size: 8)
            }
        case .priority:
            todo(16, 13, width: 148)
            todo(16, 47, width: 148, highlight: true)
            todo(16, 81, width: 148)
            for (index, color) in [ink.opacity(0.25), Color.orange, Color.red].enumerated() {
                symbol("flag.fill", 146, 27 + CGFloat(index) * 34, size: 11, color: color)
            }
        case .urgency:
            box(17, 23, 146, 74, surface, radius: 7)
            symbol("clock", 56, 59, size: 41)
            symbol("exclamationmark.triangle.fill", 105, 44, size: 18, color: .orange)
            line(96, 64, 50, color: ink.opacity(0.5))
            line(96, 77, 35)
        case .duration:
            context.stroke(Path(ellipseIn: CGRect(x: 23, y: 28, width: 63, height: 63)),
                           with: .color(faint), lineWidth: 5)
            var arc = Path()
            arc.addArc(center: CGPoint(x: 54.5, y: 59.5), radius: 31.5,
                       startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: false)
            context.stroke(arc, with: .color(tint), style: StrokeStyle(lineWidth: 5, lineCap: .round))
            symbol("clock", 55, 60, size: 26)
            box(102, 34, 52, 51, surface, radius: 6)
            text("30", 128, 51, size: 20)
            text(minuteLabel, 128, 72, size: 8)
        }
    }
}
