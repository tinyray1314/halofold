import Foundation

/// Keeps the calendar day selected in the planner separate from a time-only
/// picker value. On macOS, a `DatePicker` configured for hour/minute can
/// replace the hidden date component with today, so callers must recombine the
/// two values before saving or validating a schedule.
public enum ScheduleDateTime {
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

    public var id: String { rawValue }

    public var defaultIntervalMinutes: Int {
        switch self {
        case .hydration: 40
        case .activity: 80
        }
    }
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
    public var intervalMinutes: Int
    public var isEnabled: Bool
    public var lastRemindedAt: Date?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        kind: ScheduleRoutineKind,
        intervalMinutes: Int? = nil,
        isEnabled: Bool = true,
        lastRemindedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.intervalMinutes = max(1, intervalMinutes ?? kind.defaultIntervalMinutes)
        self.isEnabled = isEnabled
        self.lastRemindedAt = lastRemindedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
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
        for kind in ScheduleRoutineKind.allCases where !routines.contains(where: { $0.kind == kind }) {
            routines.append(ScheduleRoutine(kind: kind))
        }
        return routines
    }
}
