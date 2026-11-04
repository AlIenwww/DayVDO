import AppKit
import Combine
import SwiftUI
import XCTest
@testable import DayVDO

@MainActor
final class ProjectTaskDragSessionTests: XCTestCase {
    func testFilteredVariableHeightOffsetsAndGeometryInvalidation() {
        let projectID = UUID()
        let items = (0..<4).map { TodoItem(title: "Task \($0)", projectID: projectID) }
        let drag = ProjectTaskDragSession()
        let visible = [items[0], items[2], items[3]]
        for (item, height) in zip(visible, [43.0, 30.0, 43.0]) { drag.recordHeight(height, for: item.id) }
        drag.begin(itemID: items[0].id, projectID: projectID, orderedIDs: items.map(\.id))
        drag.hover(over: items[2].id, at: CGPoint(x: 0, y: 300), animation: nil)
        let offsets = drag.offsets(for: visible, ordered: drag.orderedChildren(visible))
        XCTAssertEqual(offsets[items[0].id], 30)
        XCTAssertEqual(offsets[items[2].id], -43)
        XCTAssertEqual(offsets[items[3].id], 0)
        drag.recordHeight(60, for: items[0].id)
        XCTAssertNil(drag.preview, "Changed row heights must not leave stale placement offsets")
        XCTAssertTrue(drag.offsets(for: visible, ordered: visible).isEmpty)
    }

    func testAnimatedTargetsCannotReverseAStationaryOrContinuingPointer() {
        let ids = (0..<4).map { _ in UUID() }
        let drag = ProjectTaskDragSession()
        drag.begin(itemID: ids[0], projectID: UUID(), orderedIDs: ids)
        var updates = 0
        let observation = drag.objectWillChange.sink { updates += 1 }
        defer { observation.cancel() }
        drag.hover(over: ids[1], at: CGPoint(x: 100, y: 300), animation: nil)
        XCTAssertEqual(drag.preview?.orderedIDs, [ids[1], ids[0], ids[2], ids[3]])
        for _ in 0..<50 {
            drag.hover(over: ids[0], at: CGPoint(x: 100, y: 300), animation: nil)
            drag.hover(over: ids[1], at: CGPoint(x: 100, y: 300), animation: nil)
        }
        drag.hover(over: ids[1], at: CGPoint(x: 100, y: 295), animation: nil)
        XCTAssertEqual(updates, 1, "Animation-induced target changes must not publish or reverse the order")
        drag.hover(over: ids[2], at: CGPoint(x: 100, y: 260), animation: nil)
        XCTAssertEqual(drag.preview?.orderedIDs, [ids[1], ids[2], ids[0], ids[3]])
        // Reverse immediately across the same neighbour; no artificial self-entry required.
        drag.hover(over: ids[2], at: CGPoint(x: 100, y: 280), animation: nil)
        XCTAssertEqual(drag.preview?.orderedIDs, [ids[1], ids[0], ids[2], ids[3]])
        XCTAssertEqual(updates, 3)
    }

    func testHoverDoesNotSaveAndDropCommitsOnceWithUndoAndHiddenChildren() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DragSession-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TodoStore(fileURL: directory.appendingPathComponent("todos.json"))
        let project = TodoProject(title: "Project", usesManualTaskOrder: true)
        store.upsertProject(project)
        let items = (0..<5).map { TodoItem(title: "Task \($0)", projectID: project.id, projectSortOrder: $0) }
        for item in items { store.upsert(item) }
        let saved = await store.flushPersistence(); XCTAssertTrue(saved)
        let ids = items.map(\.id)
        let undo = UndoManager(); undo.groupsByEvent = false; store.undoManager = undo
        let revision = store.contentRevision
        let drag = ProjectTaskDragSession()
        drag.begin(itemID: ids[0], projectID: project.id, orderedIDs: ids)
        drag.hover(over: ids[2], at: CGPoint(x: 0, y: 300), animation: nil)
        XCTAssertEqual(store.contentRevision, revision)
        XCTAssertFalse(store.hasPendingPersistence)
        XCTAssertFalse(undo.canUndo)
        XCTAssertEqual(drag.orderedChildren([items[0], items[2], items[4]]).map(\.id), [ids[2], ids[0], ids[4]])
        drag.hover(over: nil, at: CGPoint(x: 0, y: 200), animation: nil)
        undo.beginUndoGrouping()
        XCTAssertTrue(drag.commit(store: store, projectID: project.id))
        undo.endUndoGrouping()
        XCTAssertEqual(store.contentRevision, revision + 1)
        XCTAssertEqual(store.items(in: project).map(\.id), [ids[1], ids[2], ids[3], ids[4], ids[0]])
        XCTAssertNil(drag.preview)
        undo.undo()
        XCTAssertEqual(store.items(in: project).map(\.id), ids)
        XCTAssertFalse(undo.canUndo)
        undo.redo()
        XCTAssertEqual(store.items(in: project).last?.id, ids[0])
        let finalSave = await store.flushPersistence(); XCTAssertTrue(finalSave)
    }

    func testFrameCoalescingFlushAndCancelInNativeWindow() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.activate(ignoringOtherApps: true)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let anchor = NSView(frame: window.contentView!.bounds)
        window.contentView = anchor
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        let ids = (0..<6).map { _ in UUID() }
        let drag = ProjectTaskDragSession()
        drag.scheduler.view = anchor
        drag.begin(itemID: ids[0], projectID: UUID(), orderedIDs: ids)
        for index in 1..<6 {
            drag.hover(over: ids[index], at: CGPoint(x: 50, y: 300 - index * 20), animation: nil)
        }
        XCTAssertEqual(drag.preview?.orderedIDs, ids, "Inputs wait for the display callback")
        drag.scheduler.flush()
        XCTAssertEqual(drag.preview?.orderedIDs, Array(ids.dropFirst()) + [ids[0]])
        drag.hover(over: ids[1], at: CGPoint(x: 50, y: 400), animation: nil)
        drag.cancel(animation: nil)
        drag.scheduler.flush()
        XCTAssertNil(drag.preview, "Cancelled callbacks must never resurrect a preview")
        drag.begin(itemID: ids[0], projectID: UUID(), orderedIDs: ids)
        drag.hover(over: ids[3], at: CGPoint(x: 50, y: 200), animation: nil)
        drag.exit(targetID: ids[3])
        drag.scheduler.flush()
        XCTAssertEqual(drag.preview?.orderedIDs, ids, "Leaving a target discards its queued hover")
        drag.hover(over: ids[2], at: CGPoint(x: 50, y: 200), animation: nil)
        for _ in 0..<20 where drag.preview?.orderedIDs == ids {
            pumpEvents()
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(drag.preview?.orderedIDs, [ids[1], ids[2], ids[0], ids[3], ids[4], ids[5]],
            "The real display callback must deliver pending hover input")
        drag.cancel(animation: nil)
    }

    private func pumpEvents() {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
    }

    func testMixedHeightRowsMoveAndCancellationRestoresNativeFrames() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DragFrames-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TodoStore(fileURL: directory.appendingPathComponent("todos.json"))
        let project = TodoProject(title: "Project", usesManualTaskOrder: true)
        store.upsertProject(project)
        let items = (0..<4).map { TodoItem(title: "Task \($0)", notes: $0 % 2 == 0 ? "Notes" : "",
            projectID: project.id, projectSortOrder: $0) }
        for item in items { store.upsert(item) }
        let drag = ProjectTaskDragSession()
        let host = NSHostingView(rootView: LiveProjectHarness(project: project, drag: drag).environmentObject(store))
        let window = NSWindow(contentRect: CGRect(x: 20, y: 20, width: 800, height: 400),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host; window.makeKeyAndOrderFront(nil)
        defer { drag.cancel(animation: nil); window.contentView = nil; window.close() }
        await settle(host)
        let targets = descendants(host).filter { !$0.registeredDraggedTypes.isEmpty }
            .sorted { $0.convert($0.bounds, to: host).minY < $1.convert($1.bounds, to: host).minY }
        XCTAssertEqual(targets.count, 5)
        let first = try XCTUnwrap(targets.first)
        let initial = first.convert(first.bounds, to: host)
        let secondHeight = targets[1].convert(targets[1].bounds, to: host).height
        let thirdHeight = targets[2].convert(targets[2].bounds, to: host).height
        XCTAssertNotEqual(initial.height, secondHeight, "Exercise different row heights")
        drag.begin(itemID: items[0].id, projectID: project.id, orderedIDs: items.map(\.id))
        drag.hover(over: items[2].id, at: CGPoint(x: 100, y: 200), animation: .spring(duration: 0.32, bounce: 0.16))
        drag.scheduler.flush()
        await settle(host)
        XCTAssertEqual(first.convert(first.bounds, to: host).minY,
            initial.minY + secondHeight + thirdHeight, accuracy: 1)
        drag.cancel(animation: .spring(duration: 0.32, bounce: 0.16))
        await settle(host)
        XCTAssertEqual(first.convert(first.bounds, to: host).minY, initial.minY, accuracy: 1)
        XCTAssertEqual(store.items(in: project).map(\.id), items.map(\.id))
        drag.begin(itemID: items[0].id, projectID: project.id, orderedIDs: items.map(\.id))
        drag.hover(over: items[2].id, at: CGPoint(x: 100, y: 200), animation: nil)
        drag.scheduler.flush()
        XCTAssertTrue(drag.commit(store: store, projectID: project.id))
        await settle(host)
        XCTAssertNil(drag.preview)
        XCTAssertEqual(first.convert(first.bounds, to: host).minY,
            initial.minY + secondHeight + thirdHeight, accuracy: 1,
            "Committing structural order must preserve the preview's final visual position")
        var updated = items[1]
        updated.notes = "New metadata adds a second line"
        store.upsert(updated)
        await settle(host)
        XCTAssertGreaterThan(first.convert(first.bounds, to: host).minY,
            initial.minY + secondHeight + thirdHeight,
            "Metadata changes must invalidate cached row sizes")
        let saved = await store.flushPersistence(); XCTAssertTrue(saved)
    }

    private func settle(_ host: NSView) async {
        for _ in 0..<20 {
            host.layoutSubtreeIfNeeded(); host.window?.displayIfNeeded()
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }

}

private struct LiveProjectHarness: View {
    @EnvironmentObject private var store: TodoStore
    let project: TodoProject
    let drag: ProjectTaskDragSession
    var body: some View {
        ProjectTaskList(project: project, children: store.items(in: project),
            editingItem: .constant(nil), today: LocalDay(.now), drag: drag)
    }
}
