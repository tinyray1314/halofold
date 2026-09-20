import Foundation

/// Keeps the calendar day selected in the planner separate from a time-only
/// picker value. On macOS, a `DatePicker` configured for hour/minute can
/// replace the hidden date component with today, so callers must recombine the
/// two values before saving or validating a schedule.
public enum ScheduleDateTime {
    /// Today starts at the next five-minute boundary; other selected days start
    /// at 09:00. Near midnight the suggested date advances with the time.
    public static func suggestedStart(on day: Date, now: Date = Date(), calendar: Calendar = .current) -> Date {
        if calendar.isDate(day, inSameDayAs: now) {
            let minute = calendar.dateInterval(of: .minute, for: now)?.start ?? now
            let step = 5 - calendar.component(.minute, from: now) % 5
            return calendar.date(byAdding: .minute, value: step, to: minute) ?? now
        }
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
    }

    public static func combining(day: Date, time: Date, calendar: Calendar = .current) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: time)
        components.hour = timeComponents.hour
        components.minute = timeComponents.minute
        components.second = timeComponents.second
        return calendar.date(from: components) ?? time
    }
}

public enum ScheduleRepeatRule: String, Codable, CaseIterable, Equatable, Sendable {
    case none
    case weekly
}

public enum ScheduleEditScope: String, Codable, CaseIterable, Equatable, Sendable {
    case thisOccurrence
    case followingOccurrences
}

public enum ScheduleOccurrenceStatus: String, Codable, CaseIterable, Equatable, Sendable {
    case planned
    case awaitingStart
    case overdueDecision
    case running
    case completed
    case skipped
    case cancelled
}

public enum ScheduleRoutineKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case hydration
    case activity
    case custom

    public var id: String { rawValue }

    /// Only these rules are created automatically for every user. `.custom`
    /// may have any number of user-created entries.
    public static var builtInCases: [ScheduleRoutineKind] { [.hydration, .activity] }

    public var defaultIntervalMinutes: Int {
        switch self {
        case .hydration: 40
        case .activity: 80
        case .custom: 60
        }
    }

    public var defaultTitle: String {
        switch self {
        case .hydration: return "喝水"
        case .activity: return "起身活动"
        case .custom: return "自定义提醒"
        }
    }
}

public enum ScheduleRoutineReminderStyle: String, Codable, CaseIterable, Equatable, Sendable {
    case interval
    case dailyTime
}

/// A reusable plan. For a weekly plan, `startsAt` determines both the first
/// occurrence and the weekday used by later occurrences.
public struct ScheduleTemplate: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var startsAt: Date
    public var durationMinutes: Int
    public var repeatRule: ScheduleRepeatRule
    public var isEnabled: Bool
    /// Inclusive final day for this segment of a recurring series.
    public var endDate: Date?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        startsAt: Date,
        durationMinutes: Int,
        repeatRule: ScheduleRepeatRule = .none,
        isEnabled: Bool = true,
        endDate: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.startsAt = startsAt
        self.durationMinutes = max(1, durationMinutes)
        self.repeatRule = repeatRule
        self.isEnabled = isEnabled
        self.endDate = endDate
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// One schedulable time block. Repeating plans create these values on demand;
/// an edited/cancelled generated value is persisted as an override.
public struct ScheduleOccurrence: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var templateID: UUID?
    /// The calendar day this occurrence belongs to. It is stored separately so
    /// a user can move the planned time without losing the original day key.
    public var occurrenceDate: Date
    public var title: String
    public var plannedStart: Date
    public var plannedDurationMinutes: Int
    public var expectedEnd: Date
    public var status: ScheduleOccurrenceStatus
    public var actualStart: Date?
    public var actualEnd: Date?
    /// The start of the currently active focus segment. It is nil while a
    /// deferred task is waiting to resume.
    public var activeSegmentStartedAt: Date?
    /// Seconds accumulated across completed focus segments before the current
    /// one. This keeps "稍后处理" from counting paused time as focus time.
    public var accumulatedActiveSeconds: TimeInterval
    public var extendedMinutes: Int
    public var isCorrected: Bool
    /// Used as a tombstone for a deleted member of a repeating series.
    public var isDeleted: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = "one:\(UUID().uuidString)",
        templateID: UUID? = nil,
        occurrenceDate: Date,
        title: String,
        plannedStart: Date,
        plannedDurationMinutes: Int,
        expectedEnd: Date? = nil,
        status: ScheduleOccurrenceStatus = .planned,
        actualStart: Date? = nil,
        actualEnd: Date? = nil,
        activeSegmentStartedAt: Date? = nil,
        accumulatedActiveSeconds: TimeInterval = 0,
        extendedMinutes: Int = 0,
        isCorrected: Bool = false,
        isDeleted: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.templateID = templateID
        self.occurrenceDate = occurrenceDate
        self.title = title
        self.plannedStart = plannedStart
        self.plannedDurationMinutes = max(1, plannedDurationMinutes)
        self.expectedEnd = expectedEnd ?? plannedStart.addingTimeInterval(TimeInterval(max(1, plannedDurationMinutes) * 60))
        self.status = status
        self.actualStart = actualStart
        self.actualEnd = actualEnd
        self.activeSegmentStartedAt = activeSegmentStartedAt
        self.accumulatedActiveSeconds = max(0, accumulatedActiveSeconds)
        self.extendedMinutes = max(0, extendedMinutes)
        self.isCorrected = isCorrected
        self.isDeleted = isDeleted
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var plannedEnd: Date {
        plannedStart.addingTimeInterval(TimeInterval(plannedDurationMinutes * 60))
    }

    public var totalPlannedSeconds: TimeInterval {
        TimeInterval((plannedDurationMinutes + extendedMinutes) * 60)
    }

    public func actualDurationSeconds(at date: Date = Date()) -> TimeInterval {
        let activeSeconds: TimeInterval
        if status == .running, let activeSegmentStartedAt {
            activeSeconds = max(0, date.timeIntervalSince(activeSegmentStartedAt))
        } else {
            activeSeconds = 0
        }
        return max(0, accumulatedActiveSeconds + activeSeconds)
    }

    public func actualDurationMinutes(at date: Date = Date()) -> Int {
        Int((actualDurationSeconds(at: date) / 60).rounded())
    }

    public func remainingSeconds(at date: Date = Date()) -> TimeInterval {
        max(0, totalPlannedSeconds - actualDurationSeconds(at: date))
    }
}

public struct ScheduleRoutine: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var kind: ScheduleRoutineKind
    /// Built-ins derive their title from `kind`; custom rules keep the user's
    /// own text here.
    public var title: String?
    public var reminderStyle: ScheduleRoutineReminderStyle
    public var intervalMinutes: Int
    /// Minutes after local midnight, used only by `.dailyTime`.
    public var dailyTimeMinutes: Int?
    public var isEnabled: Bool
    public var lastRemindedAt: Date?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        kind: ScheduleRoutineKind,
        title: String? = nil,
        reminderStyle: ScheduleRoutineReminderStyle = .interval,
        intervalMinutes: Int? = nil,
        dailyTimeMinutes: Int? = nil,
        isEnabled: Bool = true,
        lastRemindedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.title = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.reminderStyle = reminderStyle
        self.intervalMinutes = max(1, intervalMinutes ?? kind.defaultIntervalMinutes)
        self.dailyTimeMinutes = reminderStyle == .dailyTime
            ? min(max(0, dailyTimeMinutes ?? (9 * 60)), (24 * 60) - 1)
            : nil
        self.isEnabled = isEnabled
        self.lastRemindedAt = lastRemindedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var displayTitle: String {
        if let title, !title.isEmpty { return title }
        return kind.defaultTitle
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, title, reminderStyle, intervalMinutes, dailyTimeMinutes
        case isEnabled, lastRemindedAt, createdAt, updatedAt
    }

    /// Existing local schedule files only contain the interval fields. Decode
    /// those files as interval routines so adding this feature never resets
    /// a user's current hydration/activity configuration.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try container.decodeIfPresent(ScheduleRoutineKind.self, forKey: .kind) ?? .custom
        title = try container.decodeIfPresent(String.self, forKey: .title)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        reminderStyle = try container.decodeIfPresent(ScheduleRoutineReminderStyle.self, forKey: .reminderStyle) ?? .interval
        intervalMinutes = max(1, try container.decodeIfPresent(Int.self, forKey: .intervalMinutes) ?? kind.defaultIntervalMinutes)
        if reminderStyle == .dailyTime {
            dailyTimeMinutes = min(max(0, try container.decodeIfPresent(Int.self, forKey: .dailyTimeMinutes) ?? (9 * 60)), (24 * 60) - 1)
        } else {
            dailyTimeMinutes = nil
        }
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        lastRemindedAt = try container.decodeIfPresent(Date.self, forKey: .lastRemindedAt)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encode(reminderStyle, forKey: .reminderStyle)
        try container.encode(intervalMinutes, forKey: .intervalMinutes)
        try container.encodeIfPresent(dailyTimeMinutes, forKey: .dailyTimeMinutes)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encodeIfPresent(lastRemindedAt, forKey: .lastRemindedAt)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

public struct ScheduleSnapshot: Codable, Equatable, Sendable {
    public var templates: [ScheduleTemplate]
    /// Includes one-off events and overrides/tombstones for repeating events.
    public var occurrences: [ScheduleOccurrence]
    public var routines: [ScheduleRoutine]

    public init(
        templates: [ScheduleTemplate] = [],
        occurrences: [ScheduleOccurrence] = [],
        routines: [ScheduleRoutine] = ScheduleSnapshot.defaultRoutines
    ) {
        self.templates = templates
        self.occurrences = occurrences
        self.routines = ScheduleSnapshot.normalizedRoutines(routines)
    }

    public static var defaultRoutines: [ScheduleRoutine] {
        [
            ScheduleRoutine(kind: .hydration),
            ScheduleRoutine(kind: .activity)
        ]
    }

    public static func normalizedRoutines(_ source: [ScheduleRoutine]) -> [ScheduleRoutine] {
        var routines = source
        for kind in ScheduleRoutineKind.builtInCases where !routines.contains(where: { $0.kind == kind }) {
            routines.append(ScheduleRoutine(kind: kind))
        }
        return routines
    }
}
