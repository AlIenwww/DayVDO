import AppKit
import SwiftUI
import XCTest
@testable import DayVDO

@MainActor
final class ProjectTaskDropWindowTests: XCTestCase {
    func testExpandedProjectRegistersATrailingNativeDropTarget() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DayVDO-ProjectDrop-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TodoStore(fileURL: directory.appendingPathComponent("todos.json"))
        let project = TodoProject(title: "Project", usesManualTaskOrder: true)
        store.upsertProject(project)
        let tasks = (0..<3).map { TodoItem(title: "Task \($0)", projectID: project.id) }
        for task in tasks { store.upsert(task) }
        let suite = "DayVDO-ProjectDrop-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let expansion = ProjectExpansionState(defaults: defaults)
        expansion.setExpanded(true, for: project.id)
        let host = NSHostingView(rootView: AllTodosView(editingItem: .constant(nil), editingProject: .constant(nil),
            searchFocusRequest: 0, query: .constant(""), filter: .constant(.init()),
            scrollPosition: .constant(ScrollPosition()), expansionState: expansion,
            presentationCache: AllTodosView.PresentationCache()).environmentObject(store))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.contentView = nil; window.close() }
        for _ in 0..<20 { host.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(20)) }
        let destinations = views(host).filter { !$0.registeredDraggedTypes.isEmpty }
        let destination = try XCTUnwrap(destinations.last)
        let endFrame = destination.convert(destination.bounds, to: host)
        for row in destinations.dropLast() {
            XCTAssertLessThanOrEqual(row.convert(row.bounds, to: host).maxY, endFrame.minY)
        }
        XCTAssertEqual(destinations.count, tasks.count + 1)
        XCTAssertGreaterThan(endFrame.height, 0)
        XCTAssertTrue(host.visibleRect.contains(endFrame))
        let saved = await store.flushPersistence()
        XCTAssertTrue(saved)
    }

    private func views(_ root: NSView) -> [NSView] { [root] + root.subviews.flatMap(views) }
}
