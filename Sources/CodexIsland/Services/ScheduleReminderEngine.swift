import Foundation

/// The externally supplied state for one reminder check. The engine owns no
/// timers: the application decides when to call `tick(_:)` and persists any
/// state transition requested by an emitted action.
public struct ScheduleReminderTick: Sendable {
    public var now: Date
    public var isUserSessionAvailable: Bool
    public var scheduleModuleEnabled: Bool
    public var occurrences: [ScheduleOccurrence]
    public var routines: [ScheduleRoutine]

    public init(
        now: Date,
        isUserSessionAvailable: Bool,
        scheduleModuleEnabled: Bool,
        occurrences: [ScheduleOccurrence],
        routines: [ScheduleRoutine]
    ) {
        self.now = now
        self.isUserSessionAvailable = isUserSessionAvailable
        self.scheduleModuleEnabled = scheduleModuleEnabled
        self.occurrences = occurrences
        self.routines = routines
    }
}

/// Information needed by the application to display the start prompt and say
/// its short voice reminder. The application must persist `nextStatus` before
/// the following tick.
public struct ScheduleOccurrenceReminder: Equatable, Sendable {
    public var occurrenceID: String
    public var title: String
    public var plannedStart: Date
    public var nextStatus: ScheduleOccurrenceStatus

    public init(
        occurrenceID: String,
        title: String,
        plannedStart: Date,
        nextStatus: ScheduleOccurrenceStatus
    ) {
        self.occurrenceID = occurrenceID
        self.title = title
        self.plannedStart = plannedStart
        self.nextStatus = nextStatus
    }
}

/// Information needed to speak or display a low-interruption routine reminder.
/// `remindedAt` should be saved as the routine's `lastRemindedAt` after the
/// action is delivered.
public struct ScheduleRoutineReminder: Equatable, Sendable {
    public var routineID: UUID
    public var kind: ScheduleRoutineKind
    public var remindedAt: Date

    public init(routineID: UUID, kind: ScheduleRoutineKind, remindedAt: Date) {
        self.routineID = routineID
        self.kind = kind
        self.remindedAt = remindedAt
    }
}

/// Side effects requested by `ScheduleReminderEngine`. The engine deliberately
/// does not play audio, change UI, or mutate persistence.
public enum ScheduleReminderAction: Equatable, Sendable {
    /// Speak the scheduled-start prompt and persist the occurrence as awaiting start.
    case awaitingStartReminder(ScheduleOccurrenceReminder)
    /// Present the four delayed-start choices and persist the occurrence as overdue.
    case overdueDecision(ScheduleOccurrenceReminder)
    /// Deliver a routine reminder while no focus block is running.
    case routineReminder(ScheduleRoutineReminder)
    /// Deliver one combined routine reminder after a focus block ends.
    case combinedRoutineReminder([ScheduleRoutineReminder])
}

/// A deterministic, timer-free scheduler for the reminder portion of 我的日程.
///
/// A caller should invoke `tick(_:)` on its own lightweight cadence while the
/// app is active. A long gap is treated as an unavailable session rather than
/// an opportunity to replay missed notifications. This is intentional: the
/// product contract explicitly avoids catch-up speech after sleep, lock, or a
/// period when Halofold was not running.
public final class ScheduleReminderEngine {
    /// A larger gap is assumed to be sleep, app suspension, or an unavailable
    /// user session. Normal integration should call `tick(_:)` much more often
    /// than this value (for example once per second).
    public let maximumContinuousTickGap: TimeInterval

    private var lastTickAt: Date?
    private var hadAvailableUserSession = false
    private var hadEnabledScheduleModule = false
    private var wasFocusRunning = false
    private var overdueDecisionStarts: [String: Date] = [:]
    private var routineReferenceDates: [UUID: Date] = [:]
    private var deferredRoutines: [UUID: ScheduleRoutineReminder] = [:]

    public init(maximumContinuousTickGap: TimeInterval = 60) {
        self.maximumContinuousTickGap = max(1, maximumContinuousTickGap)
    }

    /// Returns effects that are due exactly in the continuously observed time
    /// interval ending at `input.now`. It never changes an occurrence's
    /// status, actual start, or actual end by itself.
    public func tick(_ input: ScheduleReminderTick) -> [ScheduleReminderAction] {
        let isAvailable = input.isUserSessionAvailable && input.scheduleModuleEnabled

        guard isAvailable else {
            establishBaseline(with: input, rebaseRoutines: true)
            hadAvailableUserSession = input.isUserSessionAvailable
            hadEnabledScheduleModule = input.scheduleModuleEnabled
            return []
        }

        guard let previousTick = lastTickAt,
              hadAvailableUserSession,
              hadEnabledScheduleModule,
              input.now >= previousTick,
              input.now.timeIntervalSince(previousTick) <= maximumContinuousTickGap
        else {
            establishBaseline(with: input, rebaseRoutines: true)
            hadAvailableUserSession = true
            hadEnabledScheduleModule = true
            return []
        }

        defer {
            lastTickAt = input.now
            hadAvailableUserSession = true
            hadEnabledScheduleModule = true
        }

        let activeOccurrences = input.occurrences.filter { !$0.isDeleted }
        let runningFocus = activeOccurrences.contains(where: { $0.status == .running })
        let validRoutineIDs = Set(input.routines.map(\.id))
        let enabledRoutineIDs = Set(input.routines.filter(\.isEnabled).map(\.id))
        routineReferenceDates = routineReferenceDates.filter { validRoutineIDs.contains($0.key) }
        deferredRoutines = deferredRoutines.filter { enabledRoutineIDs.contains($0.key) }
        for routine in input.routines where !routine.isEnabled {
            // Turning a rule back on starts a fresh interval rather than
            // delivering a reminder that accumulated while it was disabled.
            routineReferenceDates[routine.id] = input.now
        }
        overdueDecisionStarts = overdueDecisionStarts.filter { occurrenceID, plannedStart in
            activeOccurrences.contains {
                $0.id == occurrenceID &&
                $0.status == .awaitingStart &&
                $0.actualStart == nil &&
                $0.plannedStart == plannedStart
            }
        }

        var actions: [ScheduleReminderAction] = []

        let newlyAwaiting = activeOccurrences
            .filter {
                $0.status == .planned &&
                crosses($0.plannedStart, from: previousTick, to: input.now)
            }
            .sorted { lhs, rhs in
                lhs.plannedStart == rhs.plannedStart ? lhs.id < rhs.id : lhs.plannedStart < rhs.plannedStart
            }

        for occurrence in newlyAwaiting {
            actions.append(.awaitingStartReminder(
                ScheduleOccurrenceReminder(
                    occurrenceID: occurrence.id,
                    title: occurrence.title,
                    plannedStart: occurrence.plannedStart,
                    nextStatus: .awaitingStart
                )
            ))
        }

        let newlyOverdue = activeOccurrences
            .filter {
                guard $0.status == .awaitingStart, $0.actualStart == nil else { return false }
                let decisionAt = $0.plannedStart.addingTimeInterval(Self.overdueDecisionDelay)
                return overdueDecisionStarts[$0.id] != $0.plannedStart &&
                    crosses(decisionAt, from: previousTick, to: input.now)
            }
            .sorted { lhs, rhs in
                lhs.plannedStart == rhs.plannedStart ? lhs.id < rhs.id : lhs.plannedStart < rhs.plannedStart
            }

        for occurrence in newlyOverdue {
            overdueDecisionStarts[occurrence.id] = occurrence.plannedStart
            actions.append(.overdueDecision(
                ScheduleOccurrenceReminder(
                    occurrenceID: occurrence.id,
                    title: occurrence.title,
                    plannedStart: occurrence.plannedStart,
                    nextStatus: .overdueDecision
                )
            ))
        }

        let dueRoutineReminders = dueRoutines(in: input, at: input.now)
        if runningFocus {
            for reminder in dueRoutineReminders {
                deferredRoutines[reminder.routineID] = reminder
            }
        } else if wasFocusRunning {
            var combined = Array(deferredRoutines.values)
            let deferredIDs = Set(combined.map(\.routineID))
            combined.append(contentsOf: dueRoutineReminders.filter { !deferredIDs.contains($0.routineID) })
            combined.sort { lhs, rhs in lhs.kind.rawValue < rhs.kind.rawValue }
            deferredRoutines.removeAll()
            if !combined.isEmpty {
                combined = combined.map {
                    ScheduleRoutineReminder(
                        routineID: $0.routineID,
                        kind: $0.kind,
                        remindedAt: input.now
                    )
                }
                markRoutinesReminded(combined, at: input.now)
                actions.append(.combinedRoutineReminder(combined))
            }
        } else {
            for reminder in dueRoutineReminders {
                markRoutinesReminded([reminder], at: input.now)
                actions.append(.routineReminder(reminder))
            }
        }

        wasFocusRunning = runningFocus
        return actions
    }

    /// Clears transient observation state. Call this when the application
    /// knows it is about to suspend and will not tick while unavailable.
    public func resetObservation(at now: Date) {
        lastTickAt = now
        hadAvailableUserSession = false
        hadEnabledScheduleModule = false
        wasFocusRunning = false
        deferredRoutines.removeAll()
        routineReferenceDates.removeAll()
    }

    private static let overdueDecisionDelay: TimeInterval = 10 * 60

    private func establishBaseline(with input: ScheduleReminderTick, rebaseRoutines: Bool) {
        lastTickAt = input.now
        wasFocusRunning = input.occurrences.contains { !$0.isDeleted && $0.status == .running }
        deferredRoutines.removeAll()
        if rebaseRoutines {
            routineReferenceDates = Dictionary(
                uniqueKeysWithValues: input.routines.map { ($0.id, input.now) }
            )
        }
    }

    private func dueRoutines(in input: ScheduleReminderTick, at now: Date) -> [ScheduleRoutineReminder] {
        input.routines
            .filter(\.isEnabled)
            .sorted { lhs, rhs in lhs.kind.rawValue < rhs.kind.rawValue }
            .compactMap { routine in
                let inMemoryReference = routineReferenceDates[routine.id] ?? now
                let reference = max(inMemoryReference, routine.lastRemindedAt ?? .distantPast)
                let interval = TimeInterval(routine.intervalMinutes * 60)
                guard now.timeIntervalSince(reference) >= interval else { return nil }
                return ScheduleRoutineReminder(
                    routineID: routine.id,
                    kind: routine.kind,
                    remindedAt: now
                )
            }
    }

    private func markRoutinesReminded(_ reminders: [ScheduleRoutineReminder], at now: Date) {
        for reminder in reminders {
            routineReferenceDates[reminder.routineID] = now
        }
    }

    private func crosses(_ instant: Date, from previousTick: Date, to now: Date) -> Bool {
        instant > previousTick && instant <= now
    }
}
