import AppKit
import Combine
import Foundation

@MainActor
final class OnboardingSession: ObservableObject {
    private struct Archive: Codable, Sendable {
        var version = 2
        var lessons: [String: GuideProgress] = [:]
    }
    private struct Legacy: Decodable {
        let version: Int
        let status: GuideProgress.Status
        let day: LocalDay
        let step: Int
        let snapshot: TodoSnapshot?
        let todoID: UUID?
    }

    @Published private(set) var isPresented = false
    @Published private(set) var progress = GuideProgress()
    @Published private(set) var course = GuideCourse.tour
    @Published private(set) var practice: TodoStore?
    @Published private(set) var error: String?
    @Published private(set) var needsReset = false
    @Published var revealRequest = 0
    let locations = GuideLocations()
    let undoManager = UndoManager()
    let stateURL: URL
    private let formal: TodoStore
    private var archive = Archive()
    private var subscription: AnyCancellable?
    private var checkedAutomaticPresentation = false
    private(set) var page = SidebarDestination.today
    @Published private(set) var week = false
    private var pendingDraft: UUID?
    private var pendingSave: Task<Void, Never>?
    private let writeQueue = DispatchQueue(label: "DayVDO.practice.save", qos: .utility)
    private var writeGeneration = 0
    #if DEBUG
    @Published var simulateSaveFailure = false
    var debugEnabled: Bool {
        Bundle.main.object(forInfoDictionaryKey: "DayVDOTestingDataPath") != nil ||
        Bundle.main.bundleIdentifier?.hasPrefix("com.wuyuchen.DayVDO.CompatibilityTest.") == true
    }

    func preview(_ lesson: GuideCourse, step: GuideStep, day: LocalDay, failSave: Bool) {
        guard debugEnabled, lesson.steps.contains(step) else { return }
        releasePractice()
        course = lesson
        var record = GuideProgress(status: .paused, step: step, day: day)
        var fixture = lesson.seed(&record, settings: formal.settings)
        if lesson == .tour && ![.preferences, .create].contains(step) {
            record.introducedTimeline = step != .timelineIntro
            record.sawCalendarMonth = [.locate, .complete, .done].contains(step)
            let todo = TodoItem(title: L10n.string("取预订的书"), dueDate: day.date(), estimatedMinutes: 20,
                                isCompleted: step == .done)
            record.todoID = todo.id
            fixture.items = [todo]
            if ![.timelineIntro, .schedule].contains(step) {
                let block = DaySchedule(startDay: day, startMinute: 600, durationMinutes: 20, content: .todo(todo.id))
                record.originalSchedule = block
                fixture.schedules = [block]
                if [.complete, .done].contains(step) { record.inspectedSchedule = block.id }
                if step == .done { record.completedInList = true }
            }
        }
        if lesson == .dates, step != .dateRange {
            fixture.items[0].startDay = day
            fixture.items[0].dueDay = day.adding(days: 2)
            fixture.items[0].estimatedMinutes = 30
        }
        if lesson == .organize, step != .assign {
            fixture.items[0].projectID = record.projectID
            fixture.items[0].tagID = record.tagID
        }
        if lesson == .calendar, step != .reschedule {
            record.undoCheckpoint = fixture
            fixture.items[0].dueDate = day.adding(days: 1).date()
            fixture.schedules[0].content = .independent(title: fixture.items[0].title, notes: "")
        }
        if lesson == .timeline, step != .move {
            fixture.schedules[0].startMinute += 60
            record.movedStart = fixture.schedules[0].startMinute
            record.undoCheckpoint = fixture
            if step == .undoResize { fixture.schedules[0].durationMinutes += 15 }
        }
        record.snapshot = fixture
        progress = record
        page = step.destination
        needsReset = false
        isPresented = true
        simulateSaveFailure = failSave
        if step != .preferences { makePractice() }
        persist()
    }
    #endif

    init(formal: TodoStore, stateURL: URL? = nil) {
        self.formal = formal
        let folder = formal.fileURL.deletingLastPathComponent().appendingPathComponent("Onboarding")
        self.stateURL = stateURL ?? folder.appendingPathComponent("courses-v2.json")
        do {
            if FileManager.default.fileExists(atPath: self.stateURL.path) {
                let data = try Data(contentsOf: self.stateURL)
                archive = try JSONDecoder().decode(Archive.self, from: data)
                guard archive.version == 2 else { throw CocoaError(.coderReadCorrupt) }
            } else if stateURL == nil {
                let legacy = folder.appendingPathComponent("session-v1.json")
                if FileManager.default.fileExists(atPath: legacy.path) {
                    let old = try JSONDecoder().decode(Legacy.self, from: Data(contentsOf: legacy))
                    guard old.version == 1 else { throw CocoaError(.coderReadCorrupt) }
                    var record = GuideProgress(status: old.status, day: old.day, snapshot: old.snapshot, todoID: old.todoID)
                    if old.step >= 2 {
                        record.step = .create
                        if let id = old.todoID, old.snapshot?.items.contains(where: { $0.id == id }) == true {
                            record.originalSchedule = old.snapshot?.schedules.first { $0.todoID == id }
                            record.step = record.originalSchedule == nil ? .timelineIntro : .calendarIntro
                        }
                    }
                    archive.lessons[GuideCourse.tour.rawValue] = record
                }
            }
            progress = archive.lessons[course.rawValue] ?? GuideProgress()
        } catch {
            archive = Archive()
            self.error = L10n.string("无法读取练习进度。可以重新开始，正式数据不受影响。")
            needsReset = true
        }
    }

    func status(_ course: GuideCourse) -> GuideProgress.Status { archive.lessons[course.rawValue]?.status ?? .notStarted }

    func presentAutomaticallyIfNeeded() {
        guard !checkedAutomaticPresentation, !formal.isInitialLoading else { return }
        checkedAutomaticPresentation = true
        guard formal.isNewInstallation, formal.canModify, formal.persistenceIssue == nil,
              status(.tour) == .notStarted, !needsReset else { return }
        open()
    }

    func open(_ lesson: GuideCourse = .tour) {
        if isPresented { guard close() else { return } }
        releasePractice()
        course = lesson
        progress = archive.lessons[lesson.rawValue] ?? GuideProgress(step: lesson.steps[0])
        if progress.status == .completed { progress = GuideProgress(step: lesson.steps[0]) }
        isPresented = true
        guard !needsReset else { return }
        progress.status = .paused
        page = progress.step.destination
        if progress.step != .preferences { makePractice() }
        persist()
    }

    var targetTodo: TodoItem? { practice?.item(withID: progress.todoID) }
    var targetSchedule: DaySchedule? { practice?.schedule(withID: progress.originalSchedule?.id) }

    func startTour() {
        guard progress.step == .preferences else { return }
        progress.step = .create
        makePractice()
        persist()
    }

    func bindDraft(_ id: UUID) { if progress.step == .create { pendingDraft = id } }

    func displayed(_ page: SidebarDestination, week: Bool) {
        self.page = page
        if self.week != week { self.week = week }
        if course == .tour, page == .calendar, !week, targetSchedule != nil, progress.sawCalendarMonth != true {
            progress.sawCalendarMonth = true
        }
        observePractice()
    }

    func acknowledgeTimeline() {
        guard progress.step == .timelineIntro, page == .today else { return }
        progress.introducedTimeline = true
        observePractice()
    }

    func inspected(_ schedule: UUID) {
        guard page == .calendar, week, targetSchedule?.id == schedule, progress.step == .locate else { return }
        progress.inspectedSchedule = schedule
        observePractice()
    }

    func filtered(query: String, filter: TodoFilterState, at page: SidebarDestination) {
        guard self.page == page, page == progress.step.destination, let targetTodo else { return }
        let visible = practice?.items.filter { filter.includes($0, showCompletedPreference: true, today: progress.day) } ?? []
        let usesTag = progress.tagID.map { filter.tagIDs.contains($0) } == true && visible.contains { $0.id == targetTodo.id }
        let matches = visible.filter { $0.title.localizedCaseInsensitiveContains(query) }
        switch progress.step {
        case .search where !query.isEmpty && matches.count == 1 && matches.first?.id == targetTodo.id: next()
        case .filter where query.isEmpty && usesTag, .tagSearch where usesTag && Set(visible.compactMap(\.projectID)).count >= 2, .calendarFilter where usesTag: next()
        case .clearFilter where !filter.isActive: next()
        default: return
        }
        persist()
    }

    private func next() {
        guard let index = course.steps.firstIndex(of: progress.step), index + 1 < course.steps.count else { return }
        progress.step = course.steps[index + 1]
    }

    func observePractice() {
        guard let practice, isPresented else { return }
        if let id = pendingDraft, practice.item(withID: id) != nil {
            progress.todoID = id
            pendingDraft = nil
        }
        if course == .tour {
            let step: GuideStep
            if targetTodo == nil {
                step = .create
            } else {
                if targetSchedule == nil || targetSchedule?.todoID != progress.todoID {
                    progress.originalSchedule = practice.schedules.first { $0.todoID == progress.todoID }
                }
                if targetTodo?.isCompleted == false { progress.completedInList = nil }
                else if page == .all, progress.step == .complete, progress.recoveryItem?.isCompleted == false {
                    progress.completedInList = true
                }
                if targetSchedule == nil {
                    progress.inspectedSchedule = nil
                    step = progress.introducedTimeline == true ? .schedule : .timelineIntro
                } else if progress.inspectedSchedule != targetSchedule?.id {
                    step = progress.sawCalendarMonth == true && week ? .locate : .calendarIntro
                }
                else if targetTodo?.isCompleted == true && progress.completedInList == true { step = .done }
                else { step = .complete }
            }
            if progress.step != step { progress.step = step }
        } else if let item = targetTodo {
            if course == .timeline, let original = progress.originalSchedule, let block = targetSchedule {
                if block.startMinute == original.startMinute && progress.step != .move { progress.step = .move }
                else if progress.step == .done && block.durationMinutes != original.durationMinutes { progress.step = .undoResize }
            }
            if course == .dates && (item.startDay == nil || item.startDay == item.dueDay || item.estimatedMinutes != 30) && progress.step != .dateRange {
                progress.step = .dateRange
            }
            if course == .organize && (item.projectID != progress.projectID || item.tagID != progress.tagID) && progress.step != .assign {
                progress.step = .assign
            }
            if course == .calendar && progress.step == .inspectWeek && item.startDay == progress.day {
                progress.step = .reschedule
            }
            switch progress.step {
            case .dateRange where item.startDay != nil && item.dueDay != nil && item.startDay != item.dueDay && item.estimatedMinutes == 30: next()
            case .seeDates where page == .calendar && !week: next()
            case .move where targetSchedule?.startMinute != progress.originalSchedule?.startMinute && targetSchedule != nil:
                progress.undoCheckpoint = practice.currentSnapshot()
                progress.movedStart = targetSchedule?.startMinute
                next()
            case .resize where targetSchedule?.durationMinutes != progress.originalSchedule?.durationMinutes && targetSchedule != nil: next()
            case .undoResize where targetSchedule?.startMinute == progress.movedStart && targetSchedule?.durationMinutes == progress.originalSchedule?.durationMinutes: next()
            case .reschedule where item.startDay == progress.day.adding(days: 1) && targetSchedule != nil && targetSchedule?.todoID == nil: next()
            case .inspectWeek where page == .calendar && week: next()
            case .undoDate where item.startDay == progress.day && targetSchedule?.todoID == item.id: next()
            case .assign where item.projectID == progress.projectID && item.tagID == progress.tagID: next()
            default: break
            }
        }
        if let targetTodo, targetTodo != progress.recoveryItem { progress.recoveryItem = targetTodo }
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            self?.saveInBackground()
        }
    }

    @discardableResult func close(skipping: Bool = false) -> Bool {
        guard !needsReset else { discardAndClose(); return true }
        progress.status = skipping ? .skipped : .paused
        guard persist() else { return false }
        isPresented = false
        releasePractice()
        return true
    }

    func discardAndClose() {
        isPresented = false
        releasePractice()
        progress = archive.lessons[course.rawValue] ?? GuideProgress(step: course.steps[0])
    }

    @discardableResult func finish() -> Bool {
        guard progress.step == .done else { return false }
        let old = progress
        progress = GuideProgress(status: .completed, step: .done)
        guard persist(includePractice: false) else { progress = old; return false }
        isPresented = false
        releasePractice()
        return true
    }

    private func releasePractice() {
        subscription = nil
        practice = nil
        pendingDraft = nil
        pendingSave?.cancel()
        undoManager.removeAllActions()
    }

    func restoreExample() {
        guard let practice, targetTodo == nil, let id = progress.todoID else { return }
        if let item = progress.recoveryItem {
            let original = progress.originalSchedule
            _ = practice.upsert(item)
            if let block = original, block.todoID == id, practice.schedule(withID: block.id) == nil {
                _ = practice.upsertSchedule(block)
            }
        } else {
            _ = practice.upsert(TodoItem(id: id, title: L10n.string("取预订的书"), dueDate: progress.day.date(), estimatedMinutes: 20))
        }
    }

    func restart() {
        releasePractice()
        needsReset = false
        progress = GuideProgress(status: .paused, step: course.steps[0])
        if progress.step != .preferences { makePractice() }
        persist()
    }

    private func checkpoint(includePractice: Bool) -> Archive {
        var record = progress
        if includePractice, let practice { record.snapshot = practice.currentSnapshot() }
        var candidate = archive
        candidate.lessons[course.rawValue] = record
        return candidate
    }

    private var shouldFailWrite: Bool {
        #if DEBUG
        simulateSaveFailure
        #else
        false
        #endif
    }

    private nonisolated static func write(_ candidate: Archive, to url: URL, simulateFailure: Bool) -> Bool {
        do {
            if simulateFailure { throw CocoaError(.fileWriteUnknown) }
            let data = try JSONEncoder().encode(candidate)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            return true
        } catch { return false }
    }

    private func saveInBackground() {
        guard isPresented, !needsReset else { return }
        writeGeneration += 1
        let generation = writeGeneration
        let candidate = checkpoint(includePractice: true)
        let fail = shouldFailWrite
        writeQueue.async { [stateURL, weak self] in
            let saved = Self.write(candidate, to: stateURL, simulateFailure: fail)
            Task { @MainActor [weak self] in
                guard let self, generation == self.writeGeneration else { return }
                self.recordWrite(candidate, saved: saved)
            }
        }
    }

    private func recordWrite(_ candidate: Archive, saved: Bool) {
        if saved {
            archive = candidate
            if error != nil { error = nil }
        } else {
            error = L10n.string("无法保存练习进度，请重试。正式数据不受影响。")
        }
    }

    @discardableResult func persist(includePractice: Bool = true) -> Bool {
        pendingSave?.cancel()
        guard !needsReset else { return false }
        writeGeneration += 1
        let candidate = checkpoint(includePractice: includePractice)
        let fail = shouldFailWrite
        // Flush on the same queue so an earlier autosave cannot overwrite a completed lesson.
        let saved = writeQueue.sync { Self.write(candidate, to: stateURL, simulateFailure: fail) }
        recordWrite(candidate, saved: saved)
        return saved
    }

    private func makePractice() {
        var record = progress
        var snapshot = record.snapshot ?? course.seed(&record, settings: formal.settings)
        if course == .calendar && record.undoCheckpoint == nil { record.undoCheckpoint = snapshot }
        progress = record
        snapshot.settings.language = formal.settings.language
        snapshot.settings.appearance = formal.settings.appearance
        snapshot.settings.themeColor = formal.settings.themeColor
        snapshot.settings.disabledAnimations = formal.settings.disabledAnimations
        snapshot.settings.shortcutOverrides = formal.settings.shortcutOverrides
        snapshot.settings.showCompleted = true
        let store = TodoStore(practiceSnapshot: snapshot)
        store.undoManager = undoManager
        if let checkpoint = record.undoCheckpoint, [.undoResize, .inspectWeek, .undoDate].contains(record.step) {
            store.installPracticeUndo(checkpoint, name: L10n.string(course.title))
        }
        practice = store
        subscription = store.$contentRevision.dropFirst().sink { [weak self] _ in self?.observePractice() }
    }
}
