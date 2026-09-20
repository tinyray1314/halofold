import Foundation
import XCTest
@testable import CodexIsland

@MainActor
final class ScheduleLibraryTests: XCTestCase {
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    }

    func testUndoCompletedScheduleRestoresFocusHistoryAndKeepsOtherChanges() throws {
        let model = makeModel()
        let start = date(2026, 9, 14, 10, 0)
        let item = model.add(title: "专注记录", plannedStart: start, durationMinutes: 45)
        model.start(item.id, at: start)
        model.extend(item.id, now: start.addingTimeInterval(600))
        model.complete(item.id, at: start.addingTimeInterval(900))
        let original = try XCTUnwrap(model.occurrences(on: start).first)
        let undo = try XCTUnwrap(model.deleteOccurrenceWithUndo(item.id))
        let added = model.add(title: "后来增加", plannedStart: start.addingTimeInterval(3600), durationMinutes: 30)
        undo()
        XCTAssertEqual(model.occurrences(on: start).first(where: { $0.id == item.id }), original)
        XCTAssertTrue(model.occurrences(on: start).contains(where: { $0.id == added.id }))
    }

    func testUndoGeneratedAndModifiedRepeatingOccurrences() throws {
        let model = makeModel()
        let start = date(2026, 9, 14, 10, 0)
        let item = model.add(title: "每周复盘", plannedStart: start, durationMinutes: 30, repeatRule: .weekly)
        let undoGenerated = try XCTUnwrap(model.deleteOccurrenceWithUndo(item.id))
        XCTAssertTrue(model.occurrences(on: start).isEmpty)
        undoGenerated()
        XCTAssertEqual(model.occurrences(on: start).first?.id, item.id)
        _ = model.update(item.id, title: "本次调整", durationMinutes: 45)
        let modified = try XCTUnwrap(model.occurrences(on: start).first)
        let undoModified = try XCTUnwrap(model.deleteOccurrenceWithUndo(item.id))
        undoModified()
        XCTAssertEqual(model.occurrences(on: start).first, modified)
    }

    func testUndoRoutineRestoresIdentityAndTime() throws {
        let model = makeModel()
        let item = try XCTUnwrap(model.addCustomRoutine(title: "每日复盘", reminderStyle: .dailyTime, dailyTimeMinutes: 1260))
        let undo = try XCTUnwrap(model.deleteRoutineWithUndo(item.id))
        XCTAssertFalse(model.snapshot.routines.contains(where: { $0.id == item.id }))
        undo()
        XCTAssertEqual(model.snapshot.routines.first(where: { $0.id == item.id }), item)
    }

    func testSuggestedStartUsesUpcomingTimeAndRollsMidnightExplicitly() {
        let now = date(2026, 9, 14, 16, 32)
        XCTAssertEqual(ScheduleDateTime.suggestedStart(on: now, now: now, calendar: calendar), date(2026, 9, 14, 16, 35))
        let late = date(2026, 9, 14, 23, 58)
        XCTAssertEqual(ScheduleDateTime.suggestedStart(on: late, now: late, calendar: calendar), date(2026, 9, 15, 0, 0))
        XCTAssertEqual(ScheduleDateTime.suggestedStart(on: date(2026, 9, 16, 0, 0), now: now, calendar: calendar), date(2026, 9, 16, 9, 0))
    }

    func testAddUpdateAndDeleteOneTimeOccurrence() throws {
        let model = makeModel()
        let start = date(2026, 8, 26, 10, 0)
        let added = model.add(title: "深度阅读", plannedStart: start, durationMinutes: 60)

        XCTAssertEqual(model.occurrences(on: start).map(\.title), ["深度阅读"])

        let updated = try XCTUnwrap(model.update(
            added.id,
            title: "深度阅读（修正）",
            durationMinutes: 75,
            now: date(2026, 8, 25, 9, 0)
        ))
        XCTAssertEqual(updated.title, "深度阅读（修正）")
        XCTAssertEqual(updated.plannedDurationMinutes, 75)
        XCTAssertTrue(updated.isCorrected)
        XCTAssertEqual(updated.expectedEnd, date(2026, 8, 26, 11, 15))

        model.delete(added.id)
        XCTAssertTrue(model.occurrences(on: start).isEmpty)
    }

    func testTimeOnlyPickerValueKeepsThePlannerSelectedDay() {
        let selectedDay = date(2026, 8, 31, 0, 0)
        // This represents a time-only DatePicker replacing its hidden date
        // component with the current day while the user enters 17:00.
        let pickerValue = date(2026, 9, 1, 17, 0)
        let plannedStart = ScheduleDateTime.combining(day: selectedDay, time: pickerValue, calendar: calendar)

        XCTAssertEqual(plannedStart, date(2026, 8, 31, 17, 0))

        let model = makeModel()
        _ = model.add(title: "下午任务", plannedStart: plannedStart, durationMinutes: 60)
        XCTAssertEqual(model.occurrences(on: selectedDay).map(\.title), ["下午任务"])
        XCTAssertTrue(model.occurrences(on: date(2026, 9, 1, 0, 0)).isEmpty)
    }

    func testStartDeferExtendAndCompletePreservesActualFocusTime() throws {
        let model = makeModel()
        let plannedStart = date(2026, 8, 26, 10, 0)
        let occurrence = model.add(title: "Twitter 运营", plannedStart: plannedStart, durationMinutes: 60)

        model.markAwaitingStart(occurrence.id, now: plannedStart)
        model.start(occurrence.id, at: date(2026, 8, 26, 10, 12))
        var running = try XCTUnwrap(model.occurrences(on: plannedStart).first)
        XCTAssertEqual(running.status, .running)
        XCTAssertEqual(running.actualStart, date(2026, 8, 26, 10, 12))
        XCTAssertEqual(running.expectedEnd, date(2026, 8, 26, 11, 12))

        model.extend(occurrence.id, by: 10, now: date(2026, 8, 26, 10, 20))
        model.defer(occurrence.id, at: date(2026, 8, 26, 10, 32))
        running = try XCTUnwrap(model.occurrences(on: plannedStart).first)
        XCTAssertEqual(running.status, .awaitingStart)
        XCTAssertEqual(running.actualDurationMinutes(at: date(2026, 8, 26, 10, 32)), 20)
        XCTAssertEqual(running.extendedMinutes, 10)

        model.start(occurrence.id, at: date(2026, 8, 26, 11, 0))
        running = try XCTUnwrap(model.occurrences(on: plannedStart).first)
        XCTAssertEqual(running.expectedEnd, date(2026, 8, 26, 11, 50))

        model.complete(occurrence.id, at: date(2026, 8, 26, 11, 50))
        let completed = try XCTUnwrap(model.occurrences(on: plannedStart).first)
        XCTAssertEqual(completed.status, .completed)
        XCTAssertEqual(completed.actualEnd, date(2026, 8, 26, 11, 50))
        XCTAssertEqual(completed.actualDurationMinutes(at: completed.actualEnd!), 70)
    }

    func testWeeklyUpdateThisOccurrenceAndFollowingAreRepresentedSeparately() throws {
        let model = makeModel()
        let firstTuesday = date(2026, 8, 25, 10, 0)
        let first = model.add(
            title: "深度阅读",
            plannedStart: firstTuesday,
            durationMinutes: 60,
            repeatRule: .weekly
        )
        let secondTuesday = date(2026, 9, 1, 10, 0)
        let thirdTuesday = date(2026, 9, 8, 10, 0)
        let second = try XCTUnwrap(model.occurrences(on: secondTuesday).first)

        _ = model.update(second.id, title: "本周特别阅读", scope: .thisOccurrence, now: date(2026, 8, 30, 8, 0))
        XCTAssertEqual(model.occurrences(on: secondTuesday).first?.title, "本周特别阅读")
        XCTAssertEqual(model.occurrences(on: thirdTuesday).first?.title, "深度阅读")

        let third = try XCTUnwrap(model.occurrences(on: thirdTuesday).first)
        _ = model.update(
            third.id,
            title: "新的阅读节奏",
            plannedStart: date(2026, 9, 8, 11, 0),
            durationMinutes: 90,
            scope: .followingOccurrences,
            now: date(2026, 9, 2, 8, 0)
        )

        XCTAssertEqual(model.occurrences(on: firstTuesday).first?.title, first.title)
        XCTAssertEqual(model.occurrences(on: secondTuesday).first?.title, "本周特别阅读")
        XCTAssertEqual(model.occurrences(on: thirdTuesday).first?.title, "新的阅读节奏")
        XCTAssertEqual(model.occurrences(on: thirdTuesday).first?.plannedStart, date(2026, 9, 8, 11, 0))
        XCTAssertEqual(model.occurrences(on: date(2026, 9, 15, 11, 0)).first?.plannedDurationMinutes, 90)
    }

    func testPastAndFutureQueriesSortByPlannedStartAndCancellationStaysLocal() throws {
        let model = makeModel()
        let past = date(2026, 8, 23, 9, 0)
        let future = date(2026, 8, 31, 9, 0)
        _ = model.add(title: "下午任务", plannedStart: date(2026, 8, 23, 13, 0), durationMinutes: 30)
        let morning = model.add(title: "上午任务", plannedStart: past, durationMinutes: 30)
        let recurring = model.add(title: "每周回顾", plannedStart: future, durationMinutes: 30, repeatRule: .weekly)

        XCTAssertEqual(model.occurrences(on: past).map(\.title), ["上午任务", "下午任务"])
        model.cancelThisOccurrence(recurring.id, now: date(2026, 8, 31, 9, 5))
        XCTAssertEqual(model.occurrences(on: future).first?.status, .cancelled)
        XCTAssertEqual(model.occurrences(on: date(2026, 9, 7, 9, 0)).first?.status, .planned)

        model.delete(morning.id)
        XCTAssertEqual(model.occurrences(on: past).map(\.title), ["下午任务"])
    }

    func testRoutineRulesCanBeChangedAndPersisted() throws {
        let file = temporaryFile()
        let store = SchedulePersistenceStore(fileURL: file)
        let model = ScheduleLibraryModel(store: store, selectedDate: date(2026, 8, 26, 9, 0), calendar: calendar)

        model.updateRoutine(.hydration, intervalMinutes: 45, isEnabled: false, now: date(2026, 8, 26, 9, 0))
        model.markRoutineReminded(.activity, at: date(2026, 8, 26, 10, 20))
        model.flush()

        let restored = ScheduleLibraryModel(store: store, selectedDate: date(2026, 8, 26, 9, 0), calendar: calendar)
        let hydration = try XCTUnwrap(restored.snapshot.routines.first(where: { $0.kind == .hydration }))
        let activity = try XCTUnwrap(restored.snapshot.routines.first(where: { $0.kind == .activity }))
        XCTAssertEqual(hydration.intervalMinutes, 45)
        XCTAssertFalse(hydration.isEnabled)
        XCTAssertEqual(activity.lastRemindedAt, date(2026, 8, 26, 10, 20))
    }

    func testCustomRoutineSupportsDailyTimeAndPersists() throws {
        let file = temporaryFile()
        let store = SchedulePersistenceStore(fileURL: file)
        let model = ScheduleLibraryModel(store: store, selectedDate: date(2026, 8, 26, 9, 0), calendar: calendar)

        let added = try XCTUnwrap(model.addCustomRoutine(
            title: "点外卖",
            reminderStyle: .dailyTime,
            dailyTimeMinutes: 11 * 60 + 30,
            now: date(2026, 8, 26, 9, 0)
        ))
        XCTAssertEqual(added.displayTitle, "点外卖")
        XCTAssertEqual(added.reminderStyle, .dailyTime)
        XCTAssertEqual(added.dailyTimeMinutes, 11 * 60 + 30)

        XCTAssertTrue(model.updateCustomRoutine(
            added.id,
            title: "订午饭",
            reminderStyle: .interval,
            intervalMinutes: 45,
            dailyTimeMinutes: nil,
            now: date(2026, 8, 26, 9, 5)
        ))
        model.flush()

        let restored = ScheduleLibraryModel(store: store, selectedDate: date(2026, 8, 26, 9, 0), calendar: calendar)
        let routine = try XCTUnwrap(restored.snapshot.routines.first(where: { $0.id == added.id }))
        XCTAssertEqual(routine.displayTitle, "订午饭")
        XCTAssertEqual(routine.reminderStyle, .interval)
        XCTAssertEqual(routine.intervalMinutes, 45)
        XCTAssertNil(routine.dailyTimeMinutes)
    }

    func testRestartRoundTripRestoresPlansAndActualExecution() throws {
        let file = temporaryFile()
        let store = SchedulePersistenceStore(fileURL: file)
        let start = date(2026, 8, 26, 10, 0)
        let model = ScheduleLibraryModel(store: store, selectedDate: start, calendar: calendar)
        let occurrence = model.add(title: "深度阅读", plannedStart: start, durationMinutes: 60)
        model.start(occurrence.id, at: date(2026, 8, 26, 10, 12))
        model.complete(occurrence.id, at: date(2026, 8, 26, 11, 12))
        _ = model.add(title: "周复盘", plannedStart: date(2026, 8, 28, 16, 0), durationMinutes: 30, repeatRule: .weekly)
        model.flush()

        let restored = ScheduleLibraryModel(store: store, selectedDate: start, calendar: calendar)
        let completed = try XCTUnwrap(restored.occurrences(on: start).first)
        XCTAssertEqual(completed.status, .completed)
        XCTAssertEqual(completed.actualStart, date(2026, 8, 26, 10, 12))
        XCTAssertEqual(completed.actualEnd, date(2026, 8, 26, 11, 12))
        XCTAssertEqual(restored.occurrences(on: date(2026, 9, 4, 16, 0)).first?.title, "周复盘")
    }

    private func makeModel() -> ScheduleLibraryModel {
        ScheduleLibraryModel(
            store: SchedulePersistenceStore(fileURL: temporaryFile()),
            selectedDate: date(2026, 8, 26, 9, 0),
            calendar: calendar
        )
    }

    private func temporaryFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("schedules.json")
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ))!
    }
}
