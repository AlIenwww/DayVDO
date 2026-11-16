import SwiftUI

enum AppAnimationEffect: String, CaseIterable, Identifiable, Codable, Sendable {
    case completion, planningSections, allTodosList, projectDisclosure, projectReorder, listControls
    case calendarScroll, calendarDrag, calendarTaskStatus, calendarInspector, timelineZoom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .completion: "待办完成"
        case .planningSections: "今日安排列表变化"
        case .allTodosList: "总待办列表变化"
        case .projectDisclosure: "项目展开与折叠"
        case .projectReorder: "项目内拖动排序"
        case .listControls: "列表按钮淡入淡出"
        case .calendarScroll: "日历切换与吸附"
        case .calendarDrag: "日历拖拽"
        case .calendarTaskStatus: "日历任务状态切换"
        case .calendarInspector: "日历详情开合"
        case .timelineZoom: "时间线平滑缩放"
        }
    }

}

extension AppSettings {
    func animation(_ animation: Animation, for effect: AppAnimationEffect, reduceMotion: Bool) -> Animation? {
        !reduceMotion && animates(effect) ? animation : nil
    }

    func allTodosListAnimation(reduceMotion: Bool) -> Animation? {
        animation(.easeInOut(duration: 0.22), for: .allTodosList, reduceMotion: reduceMotion)
    }

    func calendarDragAnimation(reduceMotion: Bool) -> Animation? {
        animation(.interactiveSpring(duration: 0.20, extraBounce: 0), for: .calendarDrag,
                  reduceMotion: reduceMotion)
    }

    func calendarTaskStatusAnimation(reduceMotion: Bool) -> Animation? {
        animation(.easeInOut(duration: 0.18), for: .calendarTaskStatus, reduceMotion: reduceMotion)
    }
}
