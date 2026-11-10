import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class SidebarPagePresentation {
    init(initialDestination: SidebarDestination = .today) {
        selection = initialDestination
        displayedDestination = initialDestination
    }

    var selection: SidebarDestination? = .today
    private(set) var displayedDestination: SidebarDestination = .today
    @ObservationIgnored let feedback = SidebarSelectionFeedback()
    @ObservationIgnored private var presentationTask: Task<Void, Never>?
    @ObservationIgnored private var requestID: UUID?
    @ObservationIgnored private(set) var calendarPreparationTimedOut = false

    func presentSelection(prepareCalendar: @MainActor () -> CalendarEntryPreparation?) {
        cancelPendingPresentation()
        let destination = selection ?? .today
        guard destination != displayedDestination else { return }
        let id = UUID()
        let deadline = ContinuousClock.now + .milliseconds(50)
        requestID = id
        // Register during the selection update. Starting the task first can
        // miss AppKit's first update and delay presentation until a later one.
        let windowUpdate = feedback.nextWindowUpdate()
        let preparation = destination == .calendar ? prepareCalendar() : nil
        presentationTask = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            defer {
                if self.requestID == id {
                    self.presentationTask = nil
                    self.requestID = nil
                }
            }
            async let calendarReady = preparation?.wait(until: deadline) ?? true
            await windowUpdate.wait()
            let ready = await calendarReady
            guard !Task.isCancelled, self.requestID == id,
                  destination == (self.selection ?? .today) else { return }
            self.calendarPreparationTimedOut = destination == .calendar && (preparation == nil || !ready)
            self.displayedDestination = destination
        }
    }

    func cancelPendingPresentation() {
        requestID = nil
        presentationTask?.cancel()
        presentationTask = nil
    }
}

@MainActor
final class SidebarSelectionFeedback: ObservableObject {
    weak var window: NSWindow?

    func waitForWindowUpdate() async {
        await nextWindowUpdate().wait()
    }

    func nextWindowUpdate() -> WindowUpdateWaiter {
        WindowUpdateWaiter(window: window)
    }
}

@MainActor
final class WindowUpdateWaiter {
    private var continuation: CheckedContinuation<Void, Never>?
    private var observer: NSObjectProtocol?
    private var finished = false

    init(window: NSWindow?) {
        guard let window else {
            finished = true
            return
        }
        observer = NotificationCenter.default.addObserver(
            forName: NSWindow.didUpdateNotification, object: window, queue: .main
        ) { [weak self] _ in
            // Finish after AppKit's update callback returns so the selected
            // sidebar can update before constructing the new detail page.
            DispatchQueue.main.async { self?.finish() }
        }
        window.contentView?.needsDisplay = true
    }

    func wait() async {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !finished, !Task.isCancelled else {
                    continuation.resume()
                    return
                }
                self.continuation = continuation
            }
        } onCancel: {
            Task { @MainActor in self.finish() }
        }
    }

    func finish() {
        guard !finished else { return }
        finished = true
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        continuation?.resume()
        continuation = nil
    }
}

struct SidebarSelectionFeedbackWindow: NSViewRepresentable {
    let feedback: SidebarSelectionFeedback

    func makeNSView(context: Context) -> FeedbackWindowView {
        FeedbackWindowView(feedback: feedback)
    }

    func updateNSView(_ nsView: FeedbackWindowView, context: Context) {
        feedback.window = nsView.window
    }

    final class FeedbackWindowView: NSView {
        private let feedback: SidebarSelectionFeedback

        init(feedback: SidebarSelectionFeedback) {
            self.feedback = feedback
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            feedback.window = window
        }
    }
}
