import AppKit
import XCTest
@testable import DayVDO

@MainActor
final class WindowKeyMonitorTests: XCTestCase {
    private final class Probe: WindowKeyMonitorView {
        var received = 0
        override func handleKeyDown(_ event: NSEvent, in window: NSWindow) -> Bool {
            received += 1
            return true
        }
    }

    func testNativeMonitorTracksEnableDisableAndDetachment() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.activate(ignoringOtherApps: true)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 100, height: 100),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let view = Probe(frame: window.contentView!.bounds)
        window.contentView!.addSubview(view)
        window.makeKeyAndOrderFront(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        defer { view.stop(); window.close() }
        func sendKey() {
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, characters: "x", charactersIgnoringModifiers: "x", isARepeat: false, keyCode: 7)!
            NSApp.postEvent(event, atStart: true)
            if let queued = NSApp.nextEvent(matching: .keyDown, until: Date().addingTimeInterval(0.02),
                                            inMode: .default, dequeue: true) {
                NSApp.sendEvent(queued)
            }
        }
        sendKey()
        XCTAssertEqual(view.received, 0)
        view.enabled = true
        sendKey()
        XCTAssertEqual(view.received, 1)
        view.enabled = false
        sendKey()
        XCTAssertEqual(view.received, 1)
        view.enabled = true
        sendKey()
        XCTAssertEqual(view.received, 2)
        view.removeFromSuperview()
        sendKey()
        XCTAssertEqual(view.received, 2)
    }
}
