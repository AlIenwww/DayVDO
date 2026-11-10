import SwiftUI

enum AppAnimationEffect: String, CaseIterable, Identifiable, Codable, Sendable {
    case completion, planningSections, projectDisclosure, projectReorder, listControls
    case calendarScroll, calendarInspector, timelineZoom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .completion: "待办完成"
        case .planningSections: "今日安排列表变化"
        case .projectDisclosure: "项目展开与折叠"
        case .projectReorder: "项目内拖动排序"
        case .listControls: "列表按钮淡入淡出"
        case .calendarScroll: "日历切换与吸附"
        case .calendarInspector: "日历详情开合"
        case .timelineZoom: "时间线平滑缩放"
        }
    }
}

extension AppSettings {
    func animation(_ animation: Animation, for effect: AppAnimationEffect, reduceMotion: Bool) -> Animation? {
        !reduceMotion && animates(effect) ? animation : nil
    }
}
