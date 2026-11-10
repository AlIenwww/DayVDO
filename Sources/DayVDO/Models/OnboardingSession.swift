import AppKit
import Combine
import Foundation

enum GuideStep: Int, Codable, CaseIterable {
    case preferences, concepts, create, schedule, adjust, complete, discover

    var title: String {
        switch self {
        case .preferences: "欢迎使用 DayVDO"
        case .concepts: "认识 DayVDO"
        case .create: "创建待办"
        case .schedule: "安排时间"
        case .adjust: "调整安排"
        case .complete: "标记完成"
        case .discover: "认识其他功能"
        }
    }
}

struct GuideProgress: Codable {
    enum Status: String, Codable { case notStarted, paused, skipped, completed }
    var version = 1
    var status = Status.notStarted
    var step = GuideStep.preferences
    var day = LocalDay(.now)
    var snapshot: TodoSnapshot?
    var todoID: UUID?
    var originalSchedule: DaySchedule?
    var moved = false
    var resized = false
}

/// One atomic record contains both saved practice content and its teaching progress.
/// No tutorial store ever writes to TodoPersistence or changes the process-wide locale.
@MainActor
final class OnboardingSession: ObservableObject {
    @Published private(set) var isPresented = false
    @Published private(set) var progress = GuideProgress()
    @Published private(set) var practice: TodoStore?
    @Published private(set) var error: String?
    @Published private(set) var needsReset = false
    let undoManager = UndoManager()
    let stateURL: URL
    private let formal: TodoStore
    private var subscription: AnyCancellable?
    private var checkedAutomaticPresentation = false

    init(formal: TodoStore, stateURL: URL? = nil) {
        self.formal = formal
        self.stateURL = stateURL ?? formal.fileURL.deletingLastPathComponent()
            .appendingPathComponent("Onboarding/session-v1.json")
        if FileManager.default.fileExists(atPath: self.stateURL.path) {
            do {
                let decoded = try JSONDecoder().decode(GuideProgress.self, from: Data(contentsOf: self.stateURL))
                guard decoded.version == 1 else { throw CocoaError(.coderReadCorrupt) }
                progress = decoded
            } catch {
                self.error = L10n.string("无法读取练习进度。可以重新开始，正式数据不受影响。")
                needsReset = true
            }
        }
    }

    func presentAutomaticallyIfNeeded() {
        guard !checkedAutomaticPresentation, !formal.isInitialLoading else { return }
        checkedAutomaticPresentation = true
        guard formal.isNewInstallation, formal.canModify, formal.persistenceIssue == nil,
              progress.status == .notStarted, !needsReset else { return }
        open()
    }

    func open() {
        if progress.status == .completed { progress = GuideProgress() }
        isPresented = true
        guard !needsReset else { return }
        progress.status = .paused
        if progress.step.rawValue >= GuideStep.create.rawValue { makePractice() }
        _ = persist()
    }

    var canAdvance: Bool {
        guard !needsReset else { return false }
        switch progress.step {
        case .preferences, .concepts, .discover: return true
        case .create: return targetTodo != nil
        case .schedule: return targetSchedule != nil
        case .adjust: return targetSchedule != nil && progress.moved && progress.resized
        case .complete: return targetTodo?.isCompleted == true
        }
    }

    var targetTodo: TodoItem? {
        progress.todoID.flatMap { practice?.item(withID: $0) }
    }
    var targetSchedule: DaySchedule? {
        guard let id = progress.todoID else { return nil }
        if let original = progress.originalSchedule,
           let schedule = practice?.schedule(withID: original.id), schedule.todoID == id { return schedule }
        return practice?.schedules.first { $0.todoID == id }
    }

    func advance() {
        observePractice()
        guard canAdvance, let next = GuideStep(rawValue: progress.step.rawValue + 1) else { return }
        progress.step = next
        if next == .create && practice == nil { makePractice() }
        _ = persist()
    }

    func back() {
        guard let previous = GuideStep(rawValue: progress.step.rawValue - 1) else { return }
        progress.step = previous
        _ = persist()
    }

    func observePractice() {
        guard let practice else { return }
        if progress.todoID.flatMap({ practice.item(withID: $0) }) == nil {
            progress.todoID = practice.items.first?.id
            progress.originalSchedule = nil
            progress.moved = false
            progress.resized = false
        }
        if let schedule = targetSchedule {
            if let original = progress.originalSchedule, original.id == schedule.id {
                if schedule.startMinute != original.startMinute || schedule.startDay != original.startDay {
                    progress.moved = true
                }
                if schedule.durationMinutes != original.durationMinutes { progress.resized = true }
            } else {
                progress.originalSchedule = schedule
                progress.moved = false
                progress.resized = false
            }
        }
        _ = persist()
    }

    @discardableResult
    func close(skipping: Bool = false) -> Bool {
        guard !needsReset else { isPresented = false; return true }
        progress.status = skipping ? .skipped : .paused
        guard persist() else { return false }
        isPresented = false
        return true
    }

    @discardableResult
    func finish() -> Bool {
        let old = progress
        progress.status = .completed
        progress.snapshot = nil
        progress.todoID = nil
        progress.originalSchedule = nil
        guard persist(includePractice: false) else { progress = old; return false }
        subscription = nil
        practice = nil
        undoManager.removeAllActions()
        isPresented = false
        return true
    }

    func restart() {
        // Stop observation before discarding examples; an old publisher must not rewrite the new session.
        subscription = nil
        practice = nil
        undoManager.removeAllActions()
        progress = GuideProgress()
        progress.status = .paused
        needsReset = false
        error = nil
        _ = persist()
    }

    @discardableResult
    func persist(includePractice: Bool = true) -> Bool {
        guard !needsReset else { return false }
        if includePractice, let practice { progress.snapshot = practice.currentSnapshot() }
        do {
            try FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(progress).write(to: stateURL, options: .atomic)
            error = nil
            return true
        } catch {
            self.error = L10n.string("无法保存练习进度，请重试。正式数据不受影响。")
            return false
        }
    }

    private func makePractice() {
        guard practice == nil else { return }
        var snapshot = progress.snapshot ?? TodoSnapshot(items: [], projects: [], tags: [], settings: formal.settings)
        // These teaching preferences are local, so the completed example stays visible.
        snapshot.settings.language = formal.settings.language
        snapshot.settings.appearance = formal.settings.appearance
        snapshot.settings.themeColor = formal.settings.themeColor
        snapshot.settings.disabledAnimations = formal.settings.disabledAnimations
        snapshot.settings.shortcutOverrides = formal.settings.shortcutOverrides
        snapshot.settings.showCompleted = true
        let store = TodoStore(practiceSnapshot: snapshot)
        store.undoManager = undoManager
        practice = store
        subscription = store.$contentRevision.dropFirst().sink { [weak self] _ in
            self?.observePractice()
        }
    }
}
