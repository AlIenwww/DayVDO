import Foundation

enum GuideCourse: String, CaseIterable, Codable {
    case tour, dates, timeline, calendar, organize, find

    var title: String {
        switch self {
        case .tour: "DayVDO 新手引导"
        case .dates: "设置日期和预计时长"
        case .timeline: "调整一天的时间安排"
        case .calendar: "在日历里改计划"
        case .organize: "用项目和标签整理事情"
        case .find: "找回一项待办"
        }
    }

    var steps: [GuideStep] {
        switch self {
        case .tour: [.preferences, .create, .timelineIntro, .schedule, .calendarIntro, .locate, .complete, .done]
        case .dates: [.dateRange, .seeDates, .done]
        case .timeline: [.move, .resize, .undoResize, .done]
        case .calendar: [.reschedule, .inspectWeek, .undoDate, .done]
        case .organize: [.assign, .tagSearch, .done]
        case .find: [.search, .filter, .calendarFilter, .clearFilter, .done]
        }
    }
}

enum GuideStep: String, Codable, CaseIterable {
    case preferences, create, timelineIntro, schedule, calendarIntro, locate, complete, done
    case dateRange, seeDates, move, resize, undoResize, reschedule, inspectWeek, undoDate
    case assign, tagSearch, search, filter, calendarFilter, clearFilter

    var title: String {
        switch self {
        case .preferences: "DayVDO 新手引导"
        case .create: "点＋，记下一件今天想做的事。"
        case .timelineIntro: "右边是要做的事，左边按小时排列的是今天的时间线。把事情放到几点，就为它留出那段时间。"
        case .schedule: "按住右侧刚建的待办，拖到左侧想开始的时间后松开。也可以右键点待办，选择「安排时间…」。"
        case .calendarIntro: "月视图可以一眼看到哪些天有待办。点击工具栏中的「周」，查看一周里每天的具体时间安排。"
        case .locate: "在日历的周视图中，点开刚才安排的时间块。"
        case .complete: "在总待办找到这件事，点它左边的圆圈。"
        case .done: "练习完成"
        case .dateRange: "编辑示例待办，设置不同的开始和截止日期，预计时长填 30 分钟。"
        case .seeDates: "到日历的月视图，查看刚设置的日期范围。"
        case .move: "拖动时间块的中间，换一个开始时间。也可以选「编辑安排」。"
        case .resize: "拖动时间块的下边缘，改变时长。也可以编辑结束时间。"
        case .undoResize: "撤销刚才的时长调整，保留新的开始时间。"
        case .reschedule: "将待办的日期移到明天，选择「保留为普通安排」。"
        case .inspectWeek: "切到周视图，查看留在原日期的普通安排。"
        case .undoDate: "撤销改期，让时间块重新关联到原待办。"
        case .assign: "编辑示例待办，选择「旅行准备」项目和「外出」标签。"
        case .tagSearch: "按「外出」标签筛选，找到分属两个项目的待办。"
        case .search: "在总待办搜索示例待办的名称。"
        case .filter: "清除搜索，再按「外出」标签筛选待办。"
        case .calendarFilter: "进入日历，也按「外出」标签筛选。"
        case .clearFilter: "清除日历筛选，让其他待办重新出现。"
        }
    }

    var destination: SidebarDestination {
        switch self {
        case .calendarIntro, .locate, .seeDates, .reschedule, .inspectWeek, .undoDate, .calendarFilter, .clearFilter: .calendar
        case .complete, .dateRange, .assign, .tagSearch, .search, .filter: .all
        default: .today
        }
    }
}

struct GuideProgress: Codable {
    enum Status: String, Codable { case notStarted, paused, skipped, completed }
    var status = Status.notStarted
    var step = GuideStep.preferences
    var day = LocalDay(.now)
    var snapshot: TodoSnapshot?
    var todoID: UUID?
    var originalSchedule: DaySchedule?
    var recoveryItem: TodoItem?
    var completedInList: Bool?
    var introducedTimeline: Bool?
    var sawCalendarMonth: Bool?
    var inspectedSchedule: UUID?
    var undoCheckpoint: TodoSnapshot?
    var movedStart: Int?
    var projectID: UUID?
    var tagID: UUID?
}

extension GuideCourse {
    @MainActor func seed(_ progress: inout GuideProgress, settings: AppSettings) -> TodoSnapshot {
        var snapshot = TodoSnapshot(items: [], projects: [], tags: [], settings: settings)
        guard self != .tour else { return snapshot }
        let day = progress.day
        var task = TodoItem(title: L10n.string(self == .dates ? "交读书笔记" : "取预订的书"),
                            dueDate: self == .dates ? nil : day.date())
        if self == .timeline || self == .calendar {
            let schedule = DaySchedule(startDay: day, startMinute: 600, durationMinutes: 30, content: .todo(task.id))
            snapshot.schedules = [schedule]
            progress.originalSchedule = schedule
        }
        if self == .organize || self == .find {
            let project = TodoProject(title: L10n.string("旅行准备"))
            let other = TodoProject(title: L10n.string("日常"))
            let tag = TaskTag(name: L10n.string("外出"))
            progress.projectID = project.id
            progress.tagID = tag.id
            snapshot.projects = [project, other]
            snapshot.tags = [tag]
            if self == .find { task.projectID = project.id; task.tagID = tag.id }
            snapshot.items = [TodoItem(title: L10n.string("买水果"), dueDate: day.date(), projectID: other.id, tagID: tag.id),
                              TodoItem(title: L10n.string("交读书笔记"), dueDate: day.date())]
        }
        snapshot.items.insert(task, at: 0)
        progress.todoID = task.id
        return snapshot
    }
}
