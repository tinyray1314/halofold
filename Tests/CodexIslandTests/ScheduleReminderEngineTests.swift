import Foundation
import XCTest
@testable import CodexIsland

final class ScheduleReminderEngineTests: XCTestCase {
    func testDueOccurrencePromptsOnceAndDoesNotStartActualTimer() {
        let engine = ScheduleReminderEngine()
        let start = date(hour: 10, minute: 0)
        let occurrence = occurrence(startingAt: start)

        XCTAssertTrue(tick(engine, at: date(hour: 9, minute: 59), occurrences: [occurrence]).isEmpty)

        let actions = tick(engine, at: start, occurrences: [occurrence])
        XCTAssertEqual(actions, [
            .awaitingStartReminder(
                ScheduleOccurrenceReminder(
                    occurrenceID: occurrence.id,
                    title: "深度阅读",
                    plannedStart: start,
                    nextStatus: .awaitingStart
                )
            )
        ])
        XCTAssertNil(occurrence.actualStart)
        XCTAssertEqual(occurrence.status, .planned)
        XCTAssertTrue(tick(engine, at: date(hour: 10, minute: 1), occurrences: [occurrence]).isEmpty)
    }

    func testUnconfirmedOccurrenceGetsExactlyOneOverdueDecisionAfterTenMinutes() {
        let engine = ScheduleReminderEngine(maximumContinuousTickGap: 15 * 60)
        let start = date(hour: 10, minute: 0)
        let planned = occurrence(startingAt: start)

        _ = tick(engine, at: date(hour: 9, minute: 59), occurrences: [planned])
        _ = tick(engine, at: start, occurrences: [planned])

        var awaiting = planned
        awaiting.status = .awaitingStart
        XCTAssertTrue(tick(engine, at: date(hour: 10, minute: 9, second: 59), occurrences: [awaiting]).isEmpty)

        let actions = tick(engine, at: date(hour: 10, minute: 10), occurrences: [awaiting])
        XCTAssertEqual(actions, [
            .overdueDecision(
                ScheduleOccurrenceReminder(
                    occurrenceID: awaiting.id,
                    title: awaiting.title,
                    plannedStart: start,
                    nextStatus: .overdueDecision
                )
            )
        ])
        XCTAssertTrue(tick(engine, at: date(hour: 10, minute: 11), occurrences: [awaiting]).isEmpty)
    }

    func testDeferredFocusDoesNotGetTreatedAsAnUnstartedOverduePlan() {
        let engine = ScheduleReminderEngine(maximumContinuousTickGap: 15 * 60)
        let start = date(hour: 10, minute: 0)
        let planned = occurrence(startingAt: start)

        _ = tick(engine, at: date(hour: 9, minute: 59), occurrences: [planned])
        _ = tick(engine, at: start, occurrences: [planned])

        var deferred = planned
        deferred.status = .awaitingStart
        deferred.actualStart = start
        deferred.accumulatedActiveSeconds = 120

        XCTAssertTrue(tick(engine, at: date(hour: 10, minute: 10), occurrences: [deferred]).isEmpty)
        XCTAssertTrue(tick(engine, at: date(hour: 10, minute: 11), occurrences: [deferred]).isEmpty)
    }

    func testLockedOrDisabledSessionDoesNotEmitOrCatchUpStartPrompt() {
        let engine = ScheduleReminderEngine()
        let start = date(hour: 10, minute: 0)
        let occurrence = occurrence(startingAt: start)

        _ = tick(engine, at: date(hour: 9, minute: 59), occurrences: [occurrence])
        XCTAssertTrue(tick(engine, at: start, available: false, occurrences: [occurrence]).isEmpty)
        XCTAssertTrue(tick(engine, at: date(hour: 10, minute: 1), occurrences: [occurrence]).isEmpty)

        let disabledEngine = ScheduleReminderEngine()
        _ = tick(disabledEngine, at: date(hour: 9, minute: 59), occurrences: [occurrence])
        XCTAssertTrue(tick(disabledEngine, at: start, moduleEnabled: false, occurrences: [occurrence]).isEmpty)
        XCTAssertTrue(tick(disabledEngine, at: date(hour: 10, minute: 1), occurrences: [occurrence]).isEmpty)
    }

    func testFirstObservationAfterAPlannedStartDoesNotReplayIt() {
        let engine = ScheduleReminderEngine()
        let occurrence = occurrence(startingAt: date(hour: 10, minute: 0))

        XCTAssertTrue(tick(engine, at: date(hour: 10, minute: 30), occurrences: [occurrence]).isEmpty)
        XCTAssertTrue(tick(engine, at: date(hour: 10, minute: 31), occurrences: [occurrence]).isEmpty)
    }

    func testRoutineFiresAtItsOwnIntervalOnlyOnce() {
        let engine = ScheduleReminderEngine(maximumContinuousTickGap: 60 * 60)
        let hydration = routine(kind: .hydration, intervalMinutes: 40)

        _ = tick(engine, at: date(hour: 10, minute: 0), routines: [hydration])
        let dueActions = tick(engine, at: date(hour: 10, minute: 40), routines: [hydration])
        XCTAssertEqual(dueActions, [
            .routineReminder(ScheduleRoutineReminder(
                routineID: hydration.id,
                kind: .hydration,
                remindedAt: date(hour: 10, minute: 40)
            ))
        ])
        XCTAssertTrue(tick(engine, at: date(hour: 10, minute: 41), routines: [hydration]).isEmpty)

        var disabled = hydration
        disabled.isEnabled = false
        XCTAssertTrue(tick(engine, at: date(hour: 11, minute: 20), routines: [disabled]).isEmpty)
        XCTAssertTrue(tick(engine, at: date(hour: 11, minute: 21), routines: [hydration]).isEmpty)
    }

    func testFocusDefersDueRoutinesAndReleasesOneCombinedReminderAtFocusEnd() {
        let engine = ScheduleReminderEngine(maximumContinuousTickGap: 60 * 60)
        let hydration = routine(kind: .hydration, intervalMinutes: 40)
        let activity = routine(kind: .activity, intervalMinutes: 80)
        var focus = occurrence(startingAt: date(hour: 10, minute: 0))
        focus.status = .running

        _ = tick(engine, at: date(hour: 10, minute: 0), occurrences: [focus], routines: [hydration, activity])
        XCTAssertTrue(tick(engine, at: date(hour: 10, minute: 40), occurrences: [focus], routines: [hydration, activity]).isEmpty)

        focus.status = .completed
        let actions = tick(engine, at: date(hour: 10, minute: 41), occurrences: [focus], routines: [hydration, activity])
        XCTAssertEqual(actions, [
            .combinedRoutineReminder([
                ScheduleRoutineReminder(
                    routineID: hydration.id,
                    kind: .hydration,
                    remindedAt: date(hour: 10, minute: 41)
                )
            ])
        ])
        XCTAssertTrue(tick(engine, at: date(hour: 10, minute: 42), occurrences: [focus], routines: [hydration, activity]).isEmpty)
    }

    private func tick(
        _ engine: ScheduleReminderEngine,
        at now: Date,
        available: Bool = true,
        moduleEnabled: Bool = true,
        occurrences: [ScheduleOccurrence] = [],
        routines: [ScheduleRoutine] = []
    ) -> [ScheduleReminderAction] {
        engine.tick(ScheduleReminderTick(
            now: now,
            isUserSessionAvailable: available,
            scheduleModuleEnabled: moduleEnabled,
            occurrences: occurrences,
            routines: routines
        ))
    }

    private func occurrence(startingAt start: Date) -> ScheduleOccurrence {
        ScheduleOccurrence(
            id: "reading",
            occurrenceDate: start,
            title: "深度阅读",
            plannedStart: start,
            plannedDurationMinutes: 60
        )
    }

    private func routine(kind: ScheduleRoutineKind, intervalMinutes: Int) -> ScheduleRoutine {
        ScheduleRoutine(
            id: UUID(uuidString: kind == .hydration
                ? "00000000-0000-0000-0000-000000000001"
                : "00000000-0000-0000-0000-000000000002")!,
            kind: kind,
            intervalMinutes: intervalMinutes
        )
    }

    private func date(hour: Int, minute: Int, second: Int = 0) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = 2026
        components.month = 8
        components.day = 30
        components.hour = hour
        components.minute = minute
        components.second = second
        return components.date!
    }
}
