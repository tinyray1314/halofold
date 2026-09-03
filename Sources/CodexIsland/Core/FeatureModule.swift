import Foundation

/// Halofold 的一级功能模块。它与收起态的 DisplayModule 分开：后者控制
/// 状态条显示项，前者控制用户可进入的工作空间和提醒能力。
enum FeatureModule: String, Codable, CaseIterable, Identifiable, Sendable {
    case quickNotes
    case codexFollowUp
    case schedule

    var id: String { rawValue }

    var title: String {
        switch self {
        case .quickNotes: return AppLocalization.text("快速便签")
        case .codexFollowUp: return AppLocalization.text("Codex 跟进")
        case .schedule: return AppLocalization.text("我的日程")
        }
    }

    var subtitle: String {
        switch self {
        case .quickNotes: return AppLocalization.text("快速记录与本地保存")
        case .codexFollowUp: return AppLocalization.text("任务状态与语音提醒")
        case .schedule: return AppLocalization.text("周计划、倒计时与例行提醒")
        }
    }

    var symbolName: String {
        switch self {
        case .quickNotes: return "square.and.pencil"
        case .codexFollowUp: return "bubble.left.and.bubble.right"
        case .schedule: return "clock"
        }
    }
}
