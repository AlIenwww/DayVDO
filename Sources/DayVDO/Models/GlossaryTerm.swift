import Foundation

enum GlossaryTerm: String, CaseIterable, Identifiable {
    case todo, schedule, project, tag, priority, urgency, duration

    var id: String { rawValue }

    var title: String {
        switch self {
        case .todo: "待办"
        case .schedule: "安排"
        case .project: "项目"
        case .tag: "标签"
        case .priority: "重要度"
        case .urgency: "紧急度"
        case .duration: "预计时长"
        }
    }

    var definition: String {
        switch self {
        case .todo: "要做的一件事，可以设置日期、标签和预计时长。"
        case .schedule: "在时间线上留出的一段时间，可以关联待办，也可以独立存在。"
        case .project: "一组相关待办，用于跟踪共同目标。"
        case .tag: "可跨项目使用的颜色分类，也可以用来筛选。"
        case .priority: "事情有多重要。"
        case .urgency: "事情需要多快处理。"
        case .duration: "完成待办大约需要的时间。"
        }
    }
}
