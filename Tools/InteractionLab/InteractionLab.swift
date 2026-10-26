import AppKit
import QuartzCore

@main
@MainActor
enum InteractionLab {
    static func main() {
        let app = NSApplication.shared
        let delegate = LabDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
        withExtendedLifetime(delegate) { }
    }
}

@MainActor
final class LabDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 160, y: 120, width: 780, height: 660),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "DayVDO · 操作手感对照"
        window.minSize = NSSize(width: 620, height: 640)
        let content = LabContent(frame: NSRect(x: 0, y: 0, width: 780, height: 660))
        window.contentView = content
        window.center(); window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if CommandLine.arguments.contains("--snapshot") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                content.layoutSubtreeIfNeeded()
                if let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
                    content.cacheDisplay(in: content.bounds, to: bitmap)
                    try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/tmp/dayvdo-interaction-lab.png"))
                }
                NSApp.terminate(nil)
            }
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@MainActor
final class LabContent: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill(); bounds.fill()
    }
    override var isFlipped: Bool { true }
    private let mode = NSPopUpButton()
    private let variant = NSSegmentedControl(labels: ["原有算法", "候选算法"], trackingMode: .selectOne, target: nil, action: nil)
    private let reset = NSButton(title: "重置", target: nil, action: nil)
    private let hint = NSTextField(wrappingLabelWithString: "")
    private let readout = NSTextField(labelWithString: "")
    private let canvas = LabCanvas()
    override init(frame: NSRect) {
        super.init(frame: frame)
        mode.addItems(withTitles: ["吸附防抖", "排序换位防抖", "渐进边缘滚动", "按时间推进缩放"])
        mode.target = self; mode.action = #selector(change)
        variant.selectedSegment = 0; variant.target = self; variant.action = #selector(change)
        reset.target = self; reset.action = #selector(resetCanvas)
        hint.textColor = .secondaryLabelColor
        readout.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        for view in [mode, variant, reset, hint, readout, canvas] { addSubview(view) }
        canvas.setAccessibilityLabel("操作手感实验区域")
        canvas.setAccessibilityHelp("使用鼠标拖动；按 Escape 取消。上方控件切换算法。")
        canvas.report = { [weak self] in self?.readout.stringValue = $0 }
        change()
    }
    required init?(coder: NSCoder) { nil }
    override func layout() {
        super.layout()
        mode.frame = NSRect(x: 20, y: 16, width: 190, height: 28)
        variant.frame = NSRect(x: 224, y: 16, width: 224, height: 28)
        reset.frame = NSRect(x: bounds.width - 88, y: 16, width: 68, height: 28)
        hint.frame = NSRect(x: 20, y: 58, width: bounds.width - 40, height: 45)
        readout.frame = NSRect(x: 20, y: 106, width: bounds.width - 40, height: 22)
        canvas.frame = NSRect(x: 20, y: 140, width: bounds.width - 40, height: bounds.height - 160)
    }
    @objc private func change() {
        canvas.cancel()
        canvas.mode = mode.indexOfSelectedItem
        canvas.candidate = variant.selectedSegment == 1
        hint.stringValue = [
            "拖动蓝色安排的上边缘，在虚线附近来回微调。候选：6 点吸附、9 点释放。Esc 取消。",
            "拖动任意任务上下换位。候选：越过相邻行中线 4 点后换位。松手确认，Esc 恢复。",
            "按住蓝色安排拖到顶部或底部 36 点区域并停留。候选：越靠边越快。Esc 恢复。",
            "在区域内上下拖动，或使用触控板缩放。比较快速反向和松手后的响应。Esc 恢复。"
        ][canvas.mode]
        canvas.reset()
    }
    @objc private func resetCanvas() { canvas.cancel(); canvas.reset() }
}

@MainActor
final class LabCanvas: NSView {
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    var mode = 0
    var candidate = false
    var report: ((String) -> Void)?
    private var link: CADisplayLink?
    private var lastTime: CFTimeInterval = 0
    private var accumulator: Double = 0
    private var pointer = CGPoint.zero
    private var down: CGPoint?
    private var snap = InteractionComparisonPolicy.Snap()
    private var top: Double = 125
    private var savedTop: Double = 125
    private var order = Array(0..<8)
    private var savedOrder = Array(0..<8)
    private var dragged: Int?
    private var lastTarget: Int?
    private var scroll: Double = 0
    private var savedScroll: Double = 0
    private var zoom: Double = 90
    private var targetZoom: Double = 90
    private var savedZoom: Double = 90
    private var boundaries: [Double] { stride(from: 80.0, through: Double(bounds.height - 50), by: 80).map { $0 } }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stop() }
    }
    func reset() {
        top = 125; order = Array(0..<8); scroll = 0; zoom = 90; targetZoom = 90
        snap.reset(); lastTarget = nil; updateReadout(); needsDisplay = true
    }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        pointer = convert(event.locationInWindow, from: nil); down = pointer
        savedTop = top; savedScroll = scroll; savedOrder = order; savedZoom = zoom
        snap.reset(); lastTarget = nil
        if mode == 1 {
            let index = Int((pointer.y - 35) / 48)
            guard pointer.y >= 35, order.indices.contains(index) else { down = nil; return }
            dragged = order[index]
        }
        start()
    }
    override func mouseDragged(with event: NSEvent) {
        pointer = convert(event.locationInWindow, from: nil)
        applyPointer(); needsDisplay = true
    }
    private func applyPointer() {
        guard let down else { return }
        switch mode {
        case 0:
            let requested = min(Double(bounds.height - 40), max(0, savedTop + Double(pointer.y - down.y)))
            top = snap.value(pointer: requested, boundaries: boundaries, enabled: candidate)
        case 1:
            guard let dragged, let source = order.firstIndex(of: dragged) else { return }
            let target = min(order.count - 1, max(0, Int((pointer.y - 35) / 48)))
            if source == target { lastTarget = nil; return }
            let id = order[target]
            if candidate {
                let midpoint = Double(35 + target * 48 + 24)
                guard InteractionComparisonPolicy.crossesRow(pointer: pointer.y, midpoint: midpoint, movingDown: source < target) else { return }
            } else if lastTarget == id { return }
            order.remove(at: source); order.insert(dragged, at: target); lastTarget = id
        case 3:
            targetZoom = min(180, max(45, savedZoom + Double(down.y - pointer.y) * 0.4))
        default: break
        }
        updateReadout()
    }
    override func mouseUp(with event: NSEvent) {
        pointer = convert(event.locationInWindow, from: nil); applyPointer()
        down = nil; dragged = nil; snap.reset(); needsDisplay = true
        if mode != 3 { stop() }
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { cancel() } else { super.keyDown(with: event) }
    }
    func cancel() {
        if down != nil { top = savedTop; order = savedOrder; scroll = savedScroll; zoom = savedZoom; targetZoom = savedZoom }
        down = nil; dragged = nil; snap.reset(); stop(); needsDisplay = true; updateReadout()
    }
    override func magnify(with event: NSEvent) {
        guard mode == 3 else { return }
        targetZoom = min(180, max(45, targetZoom * (1 + Double(event.magnification))))
        start()
    }
    private func start() {
        guard link == nil else { return }
        lastTime = CACurrentMediaTime(); accumulator = 0
        let link = displayLink(target: self, selector: #selector(tick(_:)))
        self.link = link; link.add(to: .main, forMode: .common)
    }
    private func stop() { link?.invalidate(); link = nil }
    @objc private func tick(_ sender: CADisplayLink) {
        let now = CACurrentMediaTime(), dt = min(0.1, max(0, now - lastTime)); lastTime = now
        if mode == 2, down != nil {
            if candidate {
                scroll += InteractionComparisonPolicy.edgeVelocity(pointer: pointer.y, height: bounds.height) * dt
            } else {
                accumulator += dt
                while accumulator >= 0.05 {
                    let direction: Double = pointer.y < 36 ? -1 : (pointer.y > bounds.height - 36 ? 1 : 0)
                    scroll += direction * 12; accumulator -= 0.05
                }
            }
            scroll = min(2000, max(0, scroll))
        } else if mode == 3 {
            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { zoom = targetZoom }
            else if candidate { zoom = InteractionComparisonPolicy.zoom(current: zoom, target: targetZoom, elapsed: dt) }
            else {
                accumulator += dt
                if accumulator >= 0.016 { zoom = abs(targetZoom - zoom) < 0.1 ? targetZoom : zoom + (targetZoom - zoom) * 0.45; accumulator = 0 }
            }
            if down == nil && zoom == targetZoom { stop() }
        } else if down == nil { stop() }
        updateReadout(); needsDisplay = true
    }
    private func updateReadout() {
        report?(["位置 \(String(format: "%.1f", top)) 点",
            "顺序 " + order.map { "\($0 + 1)" }.joined(separator: " → "),
            "滚动位置 \(String(format: "%.1f", scroll)) 点",
            "当前 \(String(format: "%.1f", zoom)) / 目标 \(String(format: "%.1f", targetZoom)) 点每小时"][mode])
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.textBackgroundColor.setFill(); bounds.fill()
        switch mode {
        case 0:
            for value in boundaries {
                let line = NSBezierPath(); line.move(to: NSPoint(x: 24, y: value)); line.line(to: NSPoint(x: bounds.width - 24, y: value))
                line.setLineDash([4, 4], count: 2, phase: 0); NSColor.separatorColor.setStroke(); line.stroke()
                text("边界 \(Int(value))", x: 24, y: value - 23)
            }
            block("拖动微调安排", rect: NSRect(x: 165, y: top, width: bounds.width - 200, height: 36), active: true)
        case 1:
            for (index, id) in order.enumerated() {
                block("任务 \(id + 1)", rect: NSRect(x: 60, y: 35 + index * 48, width: Int(bounds.width) - 120, height: 42), active: id == dragged)
            }
        case 2:
            NSColor.controlAccentColor.withAlphaComponent(0.09).setFill()
            NSRect(x: 0, y: 0, width: bounds.width, height: 36).fill()
            NSRect(x: 0, y: bounds.height - 36, width: bounds.width, height: 36).fill()
            for index in 0..<60 {
                let y = Double(index * 48) - scroll
                if y > -48 && y < bounds.height { text("时间位置 \(index * 48)", x: 24, y: y + 10) }
            }
            block("按住并拖至边缘", rect: NSRect(x: 200, y: down == nil ? 100 : pointer.y - 18, width: bounds.width - 230, height: 36), active: true)
        default:
            for hour in 0..<24 {
                let y = Double(hour) * zoom - zoom * 8 + bounds.height / 2
                if y >= 0 && y < bounds.height {
                    text(String(format: "%02d:00", hour), x: 24, y: y)
                    NSColor.separatorColor.setFill(); NSRect(x: 85, y: y + 8, width: bounds.width - 100, height: 1).fill()
                }
            }
            block("固定 08:00 锚点", rect: NSRect(x: 130, y: bounds.height / 2, width: bounds.width - 170, height: zoom * 0.6), active: true)
        }
    }
    private func text(_ value: String, x: Double, y: Double) {
        (value as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.labelColor])
    }
    private func block(_ title: String, rect: NSRect, active: Bool) {
        (active ? NSColor.controlAccentColor.withAlphaComponent(0.22) : NSColor.controlBackgroundColor).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
        text(title, x: rect.minX + 14, y: rect.minY + 10)
    }
}
