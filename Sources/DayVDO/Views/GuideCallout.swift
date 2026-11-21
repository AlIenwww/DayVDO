import AppKit
import SwiftUI

enum GuideTarget: Hashable {
    case add, sidebar(SidebarDestination), row(UUID), block(UUID), panel, timeline, mode, filter, pane
    case helpCategory, settingsCategories, openTutorials

    var isToolbarControl: Bool { self == .add || self == .mode || self == .filter }
}

struct GuideFocus: Equatable {
    var target: GuideTarget
    var alternate: GuideTarget?
    var secondary: GuideTarget?

    init(_ target: GuideTarget, alternate: GuideTarget? = nil, secondary: GuideTarget? = nil) {
        self.target = target
        self.alternate = alternate
        self.secondary = secondary
    }
}

@MainActor
final class GuideLocations {
    private let views = NSHashTable<GuideMarker>.weakObjects()

    func add(_ marker: GuideMarker) { views.add(marker) }

    func rect(_ target: GuideTarget, in base: NSView) -> CGRect? {
        guard let window = base.window else { return nil }
        for marker in views.allObjects where marker.target == target && marker.window === window {
            guard !marker.isHiddenOrHasHiddenAncestor,
                  marker.visibleRect.width > 2, marker.visibleRect.height > 2,
                  marker.bounds.width > 2, marker.bounds.height > 2 else { continue }
            let bounds = base.convert(marker.bounds, from: marker)
            if target.isToolbarControl {
                // A SwiftUI toolbar item can measure only its label. The system adds
                // its pill and hit area outside the SwiftUI hosting view.
                let minimumWidth: CGFloat = target == .mode ? 96 : 38
                let width = max(bounds.width, minimumWidth)
                let height = max(bounds.height, 38)
                return CGRect(x: bounds.midX - width / 2, y: bounds.midY - height / 2,
                              width: width, height: height)
            }
            return bounds
        }
        return nil
    }
}

private struct GuideAnchor: NSViewRepresentable {
    let target: GuideTarget
    let locations: GuideLocations

    func makeNSView(context: Context) -> GuideMarker {
        let marker = GuideMarker()
        locations.add(marker)
        return marker
    }

    func updateNSView(_ marker: GuideMarker, context: Context) { marker.target = target }
}

@MainActor
final class GuideMarker: NSView {
    var target: GuideTarget?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

extension View {
    func guideTarget(_ target: GuideTarget?) -> some View {
        modifier(GuideTargetModifier(target: target))
    }
}

private struct GuideTargetModifier: ViewModifier {
    @Environment(\.guideLocations) private var locations
    let target: GuideTarget?

    func body(content: Content) -> some View {
        content.background {
            if let target, let locations {
                GuideAnchor(target: target, locations: locations)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }
}

private struct GuideCoordinateSpace: NSViewRepresentable {
    let view: GuideCoordinateView

    func makeNSView(context: Context) -> GuideCoordinateView { view }
    func updateNSView(_ view: GuideCoordinateView, context: Context) {}
    static func dismantleNSView(_ view: GuideCoordinateView, coordinator: ()) { view.clearOutlines() }
}

private final class GuideCoordinateView: NSView {
    private let outlineView = GuideOutlineView()

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func updateOutlines(_ primary: CGRect?, secondary: CGRect?, color: NSColor) {
        // The frame view includes the AppKit toolbar. A SwiftUI overlay on
        // the split view can only draw below those native controls.
        guard primary != nil || secondary != nil,
              let frameView = window?.contentView?.superview else {
            clearOutlines()
            return
        }
        if outlineView.superview !== frameView {
            outlineView.frame = frameView.bounds
            outlineView.autoresizingMask = [.width, .height]
            frameView.addSubview(outlineView, positioned: .above, relativeTo: nil)
        }
        outlineView.update(primary.map { outlineView.convert($0, from: self) },
                           secondary: secondary.map { outlineView.convert($0, from: self) }, color: color)
    }

    func clearOutlines() { outlineView.removeFromSuperview() }
}

private final class GuideOutlineView: NSView {
    private var primary: CGRect?
    private var secondary: CGRect?
    private var color = NSColor.controlAccentColor

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func update(_ primary: CGRect?, secondary: CGRect?, color: NSColor) {
        guard self.primary != primary || self.secondary != secondary || self.color != color else { return }
        self.primary = primary
        self.secondary = secondary
        self.color = color
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        if let primary { stroke(around: primary, dashed: false) }
        if let secondary { stroke(around: secondary, dashed: true) }
    }

    private func stroke(around target: CGRect, dashed: Bool) {
        let rect = target.insetBy(dx: -4, dy: -4).intersection(bounds.insetBy(dx: 2, dy: 2))
        guard rect.width > 4, rect.height > 4 else { return }
        let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        if dashed { path.setLineDash([5, 4], count: 2, phase: 0) }
        NSColor.windowBackgroundColor.setStroke()
        path.lineWidth = 4
        path.stroke()
        color.setStroke()
        path.lineWidth = 2
        path.stroke()
    }
}

struct GuideCallout<Actions: View>: View {
    @Environment(\.guideLocations) private var locations
    @Environment(\.accessibilityReduceTransparency) private var opaque
    @EnvironmentObject private var store: TodoStore
    @State private var coordinates = GuideCoordinateView()
    @State private var placement: Placement?
    @State private var measuredAnchor: CGRect?
    @State private var missingSince: ContinuousClock.Instant?

    let focus: GuideFocus
    let title: String
    let message: String
    let isInteractive: Bool
    @ViewBuilder var actions: Actions

    private struct Placement: Equatable {
        let focus: GuideFocus
        let target: GuideTarget
        let rect: CGRect?
    }

    var body: some View {
        GeometryReader { proxy in
            if let placement, placement.focus == focus {
                GuideCalloutLayout(anchor: placement.rect, target: placement.target) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text(message).font(.body).fixedSize(horizontal: false, vertical: true)
                        actions
                    }
                    .padding(12)
                    .frame(width: min(270, max(0, proxy.size.width - 20)), alignment: .leading)
                    .background(.background, in: RoundedRectangle(cornerRadius: 10))
                    .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(.separator) }
                    .shadow(color: .black.opacity(opaque ? 0 : 0.12), radius: 5, y: 2)
                    .allowsHitTesting(isInteractive)
                }
            }
        }
        .background(GuideCoordinateSpace(view: coordinates).allowsHitTesting(false).accessibilityHidden(true))
        .task(id: focus) {
            coordinates.clearOutlines()
            missingSince = nil
            measuredAnchor = nil
            while !Task.isCancelled {
                resolvePlacement()
                try? await Task.sleep(for: .milliseconds(45))
            }
        }
        .transaction { $0.animation = nil }
        .onChange(of: message) { _, text in
            if NSWorkspace.shared.isVoiceOverEnabled {
                NSAccessibility.post(element: coordinates, notification: .announcementRequested,
                    userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
            }
        }
    }

    private func resolvePlacement() {
        guard let locations, let window = coordinates.window else { return }
        let rect = locations.rect(focus.target, in: coordinates)
        let alternate = rect == nil ? focus.alternate : nil
        let anchor = rect ?? alternate.flatMap { locations.rect($0, in: coordinates) }
        let target = rect == nil ? alternate ?? focus.target : focus.target

        if let anchor {
            missingSince = nil
            if placement?.focus != focus || placement?.rect == nil {
                guard measuredAnchor == anchor else {
                    measuredAnchor = anchor
                    return
                }
            }
        } else if focus.target == .pane {
            missingSince = nil
        } else {
            if missingSince == nil { missingSince = .now }
            guard let since = missingSince, since.duration(to: .now) >= .milliseconds(700) else { return }
        }

        let next = Placement(focus: focus, target: target, rect: anchor)
        if placement != next { placement = next }
        let secondary = focus.secondary.flatMap { locations.rect($0, in: coordinates) }
        let color = store.settings.themeColor.map { NSColor($0.color) } ?? .controlAccentColor
        let hasSheet = window.attachedSheet != nil
        coordinates.updateOutlines(hasSheet ? nil : anchor, secondary: hasSheet ? nil : secondary, color: color)
    }
}

private struct GuideCalloutLayout: Layout {
    let anchor: CGRect?
    let target: GuideTarget

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let card = subviews.first else { return }
        let visible = bounds.insetBy(dx: 10, dy: 10)
        let size = card.sizeThatFits(.unspecified)
        let fallback = CGPoint(x: visible.maxX - size.width, y: visible.minY)

        func fit(_ point: CGPoint) -> CGPoint {
            CGPoint(x: max(visible.minX, min(visible.maxX - size.width, point.x)),
                    y: max(visible.minY, min(visible.maxY - size.height, point.y)))
        }

        var origin = fallback
        if let anchor {
            let targetRect = anchor.offsetBy(dx: bounds.minX, dy: bounds.minY)
            let above = CGPoint(x: targetRect.midX - size.width / 2, y: targetRect.minY - size.height - 12)
            let below = CGPoint(x: above.x, y: targetRect.maxY + 12)
            let right = CGPoint(x: targetRect.maxX + 12, y: targetRect.midY - size.height / 2)
            let left = CGPoint(x: targetRect.minX - size.width - 12, y: right.y)
            let candidates: [CGPoint] = switch target {
            case .sidebar, .timeline: [right, below, above, left]
            default: [below, above, left, right]
            }
            let occupied = targetRect.insetBy(dx: -7, dy: -7)
            origin = candidates.map(fit).first { !CGRect(origin: $0, size: size).intersects(occupied) } ?? fit(fallback)
        }
        card.place(at: origin, anchor: .topLeading, proposal: ProposedViewSize(size))
    }
}
