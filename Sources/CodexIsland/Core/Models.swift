import Foundation

enum ConversationState: String, Codable, CaseIterable, Hashable, Sendable {
    case running
    case needsAction
    case completed
    case paused

    var sortOrder: Int {
        switch self {
        case .running: return 0
        case .needsAction: return 1
        case .completed: return 2
        case .paused: return 3
        }
    }
}

enum ConversationKind: String, Codable, Sendable {
    case user
    case automation
    case subagent
}

struct ConversationRecord: Identifiable, Codable, Equatable, Sendable {
    let id: String
    var title: String
    var rolloutPath: String
    var state: ConversationState
    var updatedAt: Date
    var turnStartedAt: Date?
    var isArchived: Bool
    var pauseReason: String?
    var actionPrompt: String?
    var kind: ConversationKind
    var parentThreadID: String?
    var isCompletionUnread: Bool

    var isPrimaryStatusItem: Bool { kind != .subagent }

    init(
        id: String,
        title: String,
        rolloutPath: String,
        state: ConversationState,
        updatedAt: Date,
        turnStartedAt: Date? = nil,
        isArchived: Bool = false,
        pauseReason: String? = nil,
        actionPrompt: String? = nil,
        kind: ConversationKind = .user,
        parentThreadID: String? = nil,
        isCompletionUnread: Bool = false
    ) {
        self.id = id
        self.title = title.isEmpty ? AppLocalization.text("未命名 Codex 对话") : title
        self.rolloutPath = rolloutPath
        self.state = state
        self.updatedAt = updatedAt
        self.turnStartedAt = turnStartedAt
        self.isArchived = isArchived
        self.pauseReason = pauseReason
        self.actionPrompt = actionPrompt
        self.kind = kind
        self.parentThreadID = parentThreadID
        self.isCompletionUnread = isCompletionUnread
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, rolloutPath, state, updatedAt, turnStartedAt, isArchived, pauseReason, actionPrompt
        case kind, parentThreadID, isCompletionUnread
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        rolloutPath = try values.decode(String.self, forKey: .rolloutPath)
        state = try values.decode(ConversationState.self, forKey: .state)
        updatedAt = try values.decode(Date.self, forKey: .updatedAt)
        turnStartedAt = try values.decodeIfPresent(Date.self, forKey: .turnStartedAt)
        isArchived = try values.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
        pauseReason = try values.decodeIfPresent(String.self, forKey: .pauseReason)
        actionPrompt = try values.decodeIfPresent(String.self, forKey: .actionPrompt)
        kind = try values.decodeIfPresent(ConversationKind.self, forKey: .kind) ?? .user
        parentThreadID = try values.decodeIfPresent(String.self, forKey: .parentThreadID)
        // 升级前的完成记录一律视为已查看，避免安装新版后历史结果全部变成新提醒。
        isCompletionUnread = try values.decodeIfPresent(Bool.self, forKey: .isCompletionUnread) ?? false
    }
}

struct UsageSnapshot: Codable, Equatable, Sendable {
    enum Source: String, Codable, Sendable {
        case official
        case localFallback
        case unavailable
    }

    var weeklyRemainingPercent: Double?
    var weeklyResetAt: Date?
    var todayLocalTokens: Int
    var updatedAt: Date?
    var source: Source

    static let empty = UsageSnapshot(
        weeklyRemainingPercent: nil,
        weeklyResetAt: nil,
        todayLocalTokens: 0,
        updatedAt: nil,
        source: .unavailable
    )
}

enum DisplayModule: String, Codable, CaseIterable, Identifiable, Sendable {
    case taskStatus
    case weeklyRemaining
    case todayTokens

    var id: String { rawValue }

    var title: String {
        switch self {
        case .taskStatus: return AppLocalization.text("任务状态")
        case .weeklyRemaining: return AppLocalization.text("本周剩余")
        case .todayTokens: return AppLocalization.text("本机今日 Token")
        }
    }
}

enum ExpandedWorkspace: String, Codable, Sendable {
    case notes
    case activity
    case schedule
}

enum CollapsedLayoutMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case compact
    case relaxed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compact: return AppLocalization.text("紧凑")
        case .relaxed: return AppLocalization.text("宽松")
        }
    }

    var subtitle: String {
        switch self {
        case .compact: return AppLocalization.text("少占空间")
        case .relaxed: return AppLocalization.text("完整文案")
        }
    }

    var leftWingWidth: Double {
        switch self {
        case .compact: return 258
        case .relaxed: return 274
        }
    }

    /// 实体刘海下缘带圆角，系统给出的安全区边界仍可能在肉眼视角遮住贴边文字。
    /// 左翼内容必须在窗口边界之外再保留这段不可放文字的区域。
    var notchContentSafetyInset: Double {
        switch self {
        case .compact: return 24
        case .relaxed: return 28
        }
    }

    var rightWingWidth: Double {
        switch self {
        case .compact: return 132
        case .relaxed: return 206
        }
    }
}

enum VoiceMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case system
    case importedAudio

    var id: String { rawValue }
    var title: String { AppLocalization.text(self == .system ? "系统语音" : "自定义音频") }
}

enum CodexSignal: Equatable, Sendable {
    case taskStarted(turnID: String?, at: Date)
    case taskNeedsAction(prompt: String, at: Date)
    case taskCompleted(at: Date)
    case taskPaused(reason: String, at: Date)
    case tokenDelta(Int, at: Date)
    case localRateLimit(usedPercent: Double, resetsAt: Date?, at: Date)
}

struct ThreadMetadata: Equatable, Sendable {
    let id: String
    let title: String
    let rolloutPath: String
    let updatedAt: Date
    let archived: Bool
    let kind: ConversationKind
    let parentThreadID: String?
}

struct FileCheckpoint: Codable, Equatable, Sendable {
    var offset: UInt64
    var trailingBytes: Data

    init(offset: UInt64 = 0, trailingBytes: Data = Data()) {
        self.offset = offset
        self.trailingBytes = trailingBytes
    }
}

struct TrackerSnapshot: Codable, Sendable {
    var installedAt: Date
    var lastDatabaseScanAt: Date
    var records: [String: ConversationRecord]
    var checkpoints: [String: FileCheckpoint]
    var todayTokenDate: String
    var todayTokens: Int

    static func fresh(now: Date = Date(), calendar: Calendar = .current) -> TrackerSnapshot {
        TrackerSnapshot(
            installedAt: now,
            lastDatabaseScanAt: now,
            records: [:],
            checkpoints: [:],
            todayTokenDate: Self.dayKey(for: now, calendar: calendar),
            todayTokens: 0
        )
    }

    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}

extension ISO8601DateFormatter {
    static let codex: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let codexWithoutFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parseCodex(_ value: String) -> Date? {
        codex.date(from: value) ?? codexWithoutFraction.date(from: value)
    }
}
