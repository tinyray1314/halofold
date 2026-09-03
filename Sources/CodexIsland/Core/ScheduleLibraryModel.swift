import Combine
import Foundation

@MainActor
public final class ScheduleLibraryModel: ObservableObject {
    @Published public private(set) var snapshot: ScheduleSnapshot
    @Published public var selectedDate: Date

    private let store: SchedulePersistenceStore
    private var calendar: Calendar
    private var saveWorkItem: DispatchWorkItem?
    private var hasUnsavedChanges = false

    public init(
        store suppliedStore: SchedulePersistenceStore? = nil,
        selectedDate: Date = Date(),
        calendar: Calendar = .current
    ) {
        self.store = suppliedStore ?? SchedulePersistenceStore()
        self.calendar = calendar
        self.selectedDate = calendar.startOfDay(for: selectedDate)

        if let saved = self.store.load() {
            snapshot = ScheduleSnapshot(
                templates: saved.templates,
                occurrences: saved.occurrences,
                routines: saved.routines
            )
        } else {
            snapshot = ScheduleSnapshot()
        }
    }

    public func occurrences(on date: Date) -> [ScheduleOccurrence] {
        let day = calendar.startOfDay(for: date)
        let storedRepeatingIDs = Set(snapshot.occurrences.compactMap { occurrence in
            occurrence.templateID == nil ? nil : occurrence.id
        })

        var result = snapshot.occurrences.filter {
            !($0.isDeleted)
                && calendar.isDate($0.occurrenceDate, inSameDayAs: day)
                && isStoredOccurrenceVisible($0)
        }

        for template in snapshot.templates where isTemplateScheduled(template, on: day) {
            let occurrenceID = repeatingOccurrenceID(templateID: template.id, date: day)
            guard !storedRepeatingIDs.contains(occurrenceID) else { continue }
            result.append(makeGeneratedOccurrence(from: template, on: day))
        }

        return result.sorted {
            if $0.plannedStart == $1.plannedStart { return $0.id < $1.id }
            return $0.plannedStart < $1.plannedStart
        }
    }

    @discardableResult
    public func add(
        title: String,
        plannedStart: Date,
        durationMinutes: Int,
        repeatRule: ScheduleRepeatRule = .none,
        isEnabled: Bool = true,
        now: Date = Date()
    ) -> ScheduleOccurrence {
        let duration = max(1, durationMinutes)
        let day = calendar.startOfDay(for: plannedStart)

        if repeatRule == .weekly {
            let template = ScheduleTemplate(
                title: title,
                startsAt: plannedStart,
                durationMinutes: duration,
                repeatRule: .weekly,
                isEnabled: isEnabled,
                createdAt: now,
                updatedAt: now
            )
            snapshot.templates.append(template)
            markChanged()
            return makeGeneratedOccurrence(from: template, on: day)
        }

        let occurrence = ScheduleOccurrence(
            occurrenceDate: day,
            title: title,
            plannedStart: plannedStart,
            plannedDurationMinutes: duration,
            createdAt: now,
            updatedAt: now
        )
        snapshot.occurrences.append(occurrence)
        markChanged()
        return occurrence
    }

    @discardableResult
    public func update(
        _ occurrenceID: String,
        title: String? = nil,
        plannedStart: Date? = nil,
        durationMinutes: Int? = nil,
        repeatRule: ScheduleRepeatRule? = nil,
        scope: ScheduleEditScope = .thisOccurrence,
        now: Date = Date()
    ) -> ScheduleOccurrence? {
        guard let existing = resolvedOccurrence(id: occurrenceID) else { return nil }

        if scope == .followingOccurrences, let templateID = existing.templateID {
            return updateFollowing(
                existing,
                templateID: templateID,
                title: title,
                plannedStart: plannedStart,
                durationMinutes: durationMinutes,
                repeatRule: repeatRule,
                now: now
            )
        }

        if existing.templateID == nil, repeatRule == .weekly {
            return convertOneTimeOccurrenceToWeekly(
                existing,
                title: title,
                plannedStart: plannedStart,
                durationMinutes: durationMinutes,
                now: now
            )
        }

        var updated = existing
        updated.title = title ?? existing.title
        updated.plannedStart = plannedStart ?? existing.plannedStart
        updated.plannedDurationMinutes = max(1, durationMinutes ?? existing.plannedDurationMinutes)
        updated.occurrenceDate = calendar.startOfDay(for: updated.plannedStart)
        if updated.status != .running {
            updated.expectedEnd = updated.plannedStart.addingTimeInterval(TimeInterval((updated.plannedDurationMinutes + updated.extendedMinutes) * 60))
        }
        updated.isCorrected = true
        updated.updatedAt = now
        upsert(updated)
        markChanged()
        return updated
    }

    /// Convenience overload for editors that already hold a complete value.
    @discardableResult
    public func update(
        _ occurrence: ScheduleOccurrence,
        scope: ScheduleEditScope = .thisOccurrence,
        now: Date = Date()
    ) -> ScheduleOccurrence? {
        update(
            occurrence.id,
            title: occurrence.title,
            plannedStart: occurrence.plannedStart,
            durationMinutes: occurrence.plannedDurationMinutes,
            scope: scope,
            now: now
        )
    }

    public func delete(
        _ occurrenceID: String,
        scope: ScheduleEditScope = .thisOccurrence,
        now: Date = Date()
    ) {
        guard let occurrence = resolvedOccurrence(id: occurrenceID) else { return }
        guard scope == .thisOccurrence, let templateID = occurrence.templateID else {
            if scope == .followingOccurrences, let templateID = occurrence.templateID {
                endTemplate(templateID, before: recurrenceDay(for: occurrence) ?? occurrence.occurrenceDate, now: now)
                markChanged()
            } else if let index = snapshot.occurrences.firstIndex(where: { $0.id == occurrenceID }) {
                snapshot.occurrences.remove(at: index)
                markChanged()
            }
            return
        }

        var tombstone = occurrence
        tombstone.templateID = templateID
        tombstone.isDeleted = true
        tombstone.updatedAt = now
        upsert(tombstone)
        markChanged()
    }

    public func markAwaitingStart(_ occurrenceID: String, now: Date = Date()) {
        mutateOccurrence(occurrenceID, now: now) { occurrence in
            guard occurrence.status == .planned else { return false }
            occurrence.status = .awaitingStart
            return true
        }
    }

    public func markOverdueDecision(_ occurrenceID: String, now: Date = Date()) {
        mutateOccurrence(occurrenceID, now: now) { occurrence in
            guard occurrence.status == .awaitingStart else { return false }
            occurrence.status = .overdueDecision
            return true
        }
    }

    public func start(_ occurrenceID: String, at date: Date = Date()) {
        mutateOccurrence(occurrenceID, now: date) { occurrence in
            guard [.planned, .awaitingStart, .overdueDecision].contains(occurrence.status) else { return false }
            if occurrence.actualStart == nil { occurrence.actualStart = date }
            occurrence.activeSegmentStartedAt = date
            occurrence.actualEnd = nil
            occurrence.status = .running
            occurrence.expectedEnd = date.addingTimeInterval(occurrence.remainingSeconds(at: date))
            return true
        }
    }

    public func postpone(
        _ occurrenceID: String,
        by minutes: Int = 10,
        now: Date = Date()
    ) {
        let delay = max(1, minutes)
        mutateOccurrence(occurrenceID, now: now) { occurrence in
            guard [.planned, .awaitingStart, .overdueDecision].contains(occurrence.status), occurrence.actualStart == nil else { return false }
            occurrence.plannedStart = now.addingTimeInterval(TimeInterval(delay * 60))
            occurrence.occurrenceDate = calendar.startOfDay(for: occurrence.plannedStart)
            occurrence.expectedEnd = occurrence.plannedStart.addingTimeInterval(TimeInterval((occurrence.plannedDurationMinutes + occurrence.extendedMinutes) * 60))
            occurrence.status = .planned
            occurrence.isCorrected = true
            return true
        }
    }

    public func reschedule(
        _ occurrenceID: String,
        to plannedStart: Date,
        durationMinutes: Int? = nil,
        scope: ScheduleEditScope = .thisOccurrence,
        now: Date = Date()
    ) {
        _ = update(
            occurrenceID,
            plannedStart: plannedStart,
            durationMinutes: durationMinutes,
            scope: scope,
            now: now
        )
    }

    public func cancelThisOccurrence(_ occurrenceID: String, now: Date = Date()) {
        mutateOccurrence(occurrenceID, now: now) { occurrence in
            guard ![.completed, .skipped, .cancelled].contains(occurrence.status) else { return false }
            finishActiveSegment(&occurrence, at: now)
            occurrence.status = .cancelled
            occurrence.actualEnd = now
            return true
        }
    }

    public func complete(_ occurrenceID: String, at date: Date = Date()) {
        mutateOccurrence(occurrenceID, now: date) { occurrence in
            guard ![.completed, .skipped, .cancelled].contains(occurrence.status) else { return false }
            if occurrence.actualStart == nil { occurrence.actualStart = date }
            finishActiveSegment(&occurrence, at: date)
            occurrence.actualEnd = date
            occurrence.status = .completed
            return true
        }
    }

    /// Pause a running focus block and return it to the explicit waiting state.
    public func `defer`(_ occurrenceID: String, at date: Date = Date()) {
        mutateOccurrence(occurrenceID, now: date) { occurrence in
            guard occurrence.status == .running else { return false }
            finishActiveSegment(&occurrence, at: date)
            occurrence.status = .awaitingStart
            return true
        }
    }

    public func extend(_ occurrenceID: String, by minutes: Int = 10, now: Date = Date()) {
        let additionalMinutes = max(1, minutes)
        mutateOccurrence(occurrenceID, now: now) { occurrence in
            guard occurrence.status == .running else { return false }
            occurrence.extendedMinutes += additionalMinutes
            occurrence.expectedEnd = occurrence.expectedEnd.addingTimeInterval(TimeInterval(additionalMinutes * 60))
            return true
        }
    }

    public func skip(_ occurrenceID: String, now: Date = Date()) {
        mutateOccurrence(occurrenceID, now: now) { occurrence in
            guard ![.completed, .skipped, .cancelled].contains(occurrence.status) else { return false }
            finishActiveSegment(&occurrence, at: now)
            occurrence.status = .skipped
            occurrence.actualEnd = now
            return true
        }
    }

    public func updateRoutine(
        _ kind: ScheduleRoutineKind,
        intervalMinutes: Int? = nil,
        isEnabled: Bool? = nil,
        now: Date = Date()
    ) {
        guard let index = snapshot.routines.firstIndex(where: { $0.kind == kind }) else { return }
        if let intervalMinutes { snapshot.routines[index].intervalMinutes = max(1, intervalMinutes) }
        if let isEnabled { snapshot.routines[index].isEnabled = isEnabled }
        snapshot.routines[index].updatedAt = now
        markChanged()
    }

    public func markRoutineReminded(_ kind: ScheduleRoutineKind, at date: Date = Date()) {
        guard let index = snapshot.routines.firstIndex(where: { $0.kind == kind }) else { return }
        snapshot.routines[index].lastRemindedAt = date
        snapshot.routines[index].updatedAt = date
        markChanged()
    }

    /// Matches the identifier emitted by `ScheduleReminderEngine` so the app
    /// can persist a delivered routine reminder without translating it first.
    public func markRoutineReminded(_ routineID: UUID, at date: Date = Date()) {
        guard let index = snapshot.routines.firstIndex(where: { $0.id == routineID }) else { return }
        snapshot.routines[index].lastRemindedAt = date
        snapshot.routines[index].updatedAt = date
        markChanged()
    }

    public func flush() {
        guard hasUnsavedChanges else { return }
        saveWorkItem?.cancel()
        saveNow()
    }

    private func updateFollowing(
        _ occurrence: ScheduleOccurrence,
        templateID: UUID,
        title: String?,
        plannedStart: Date?,
        durationMinutes: Int?,
        repeatRule: ScheduleRepeatRule?,
        now: Date
    ) -> ScheduleOccurrence? {
        guard let templateIndex = snapshot.templates.firstIndex(where: { $0.id == templateID }) else { return nil }
        let originalTemplate = snapshot.templates[templateIndex]
        let cutoverDay = recurrenceDay(for: occurrence) ?? occurrence.occurrenceDate
        let originalEndDate = originalTemplate.endDate

        var previous = originalTemplate
        previous.endDate = dayBefore(cutoverDay)
        previous.updatedAt = now
        snapshot.templates[templateIndex] = previous

        let newTitle = title ?? occurrence.title
        let newStart = plannedStart ?? occurrence.plannedStart
        let newDuration = max(1, durationMinutes ?? occurrence.plannedDurationMinutes)
        let newRule = repeatRule ?? originalTemplate.repeatRule

        if newRule == .none {
            removeOverrides(for: templateID, onOrAfter: cutoverDay)
            let replacement = ScheduleOccurrence(
                occurrenceDate: calendar.startOfDay(for: newStart),
                title: newTitle,
                plannedStart: newStart,
                plannedDurationMinutes: newDuration,
                isCorrected: true,
                createdAt: now,
                updatedAt: now
            )
            snapshot.occurrences.append(replacement)
            markChanged()
            return replacement
        }

        let replacementTemplate = ScheduleTemplate(
            title: newTitle,
            startsAt: newStart,
            durationMinutes: newDuration,
            repeatRule: .weekly,
            isEnabled: originalTemplate.isEnabled,
            endDate: originalEndDate,
            createdAt: now,
            updatedAt: now
        )
        snapshot.templates.append(replacementTemplate)
        moveOverrides(
            from: templateID,
            to: replacementTemplate.id,
            onOrAfter: cutoverDay,
            now: now
        )
        markChanged()
        return makeGeneratedOccurrence(
            from: replacementTemplate,
            on: calendar.startOfDay(for: newStart)
        )
    }

    private func convertOneTimeOccurrenceToWeekly(
        _ occurrence: ScheduleOccurrence,
        title: String?,
        plannedStart: Date?,
        durationMinutes: Int?,
        now: Date
    ) -> ScheduleOccurrence {
        snapshot.occurrences.removeAll { $0.id == occurrence.id }
        let start = plannedStart ?? occurrence.plannedStart
        let template = ScheduleTemplate(
            title: title ?? occurrence.title,
            startsAt: start,
            durationMinutes: max(1, durationMinutes ?? occurrence.plannedDurationMinutes),
            repeatRule: .weekly,
            createdAt: now,
            updatedAt: now
        )
        snapshot.templates.append(template)
        markChanged()
        return makeGeneratedOccurrence(from: template, on: calendar.startOfDay(for: start))
    }

    private func mutateOccurrence(
        _ occurrenceID: String,
        now: Date,
        change: (inout ScheduleOccurrence) -> Bool
    ) {
        guard var occurrence = resolvedOccurrence(id: occurrenceID), change(&occurrence) else { return }
        occurrence.updatedAt = now
        upsert(occurrence)
        markChanged()
    }

    private func resolvedOccurrence(id: String) -> ScheduleOccurrence? {
        if let stored = snapshot.occurrences.first(where: { $0.id == id }) { return stored }
        guard let reference = repeatingReference(from: id),
              let template = snapshot.templates.first(where: { $0.id == reference.templateID }),
              isTemplateScheduled(template, on: reference.date)
        else { return nil }
        return makeGeneratedOccurrence(from: template, on: reference.date)
    }

    private func upsert(_ occurrence: ScheduleOccurrence) {
        if let index = snapshot.occurrences.firstIndex(where: { $0.id == occurrence.id }) {
            snapshot.occurrences[index] = occurrence
        } else {
            snapshot.occurrences.append(occurrence)
        }
    }

    private func isStoredOccurrenceVisible(_ occurrence: ScheduleOccurrence) -> Bool {
        guard let templateID = occurrence.templateID else { return true }
        guard let sourceDay = recurrenceDay(for: occurrence),
              let template = snapshot.templates.first(where: { $0.id == templateID })
        else { return false }
        return isTemplateScheduled(template, on: sourceDay)
    }

    private func isTemplateScheduled(_ template: ScheduleTemplate, on day: Date) -> Bool {
        guard template.isEnabled, template.repeatRule == .weekly else { return false }
        let candidateDay = calendar.startOfDay(for: day)
        let firstDay = calendar.startOfDay(for: template.startsAt)
        guard candidateDay >= firstDay else { return false }
        if let endDate = template.endDate, candidateDay > calendar.startOfDay(for: endDate) { return false }
        return calendar.component(.weekday, from: candidateDay) == calendar.component(.weekday, from: firstDay)
    }

    private func makeGeneratedOccurrence(from template: ScheduleTemplate, on day: Date) -> ScheduleOccurrence {
        let plannedStart = date(on: day, withTimeFrom: template.startsAt)
        return ScheduleOccurrence(
            id: repeatingOccurrenceID(templateID: template.id, date: day),
            templateID: template.id,
            occurrenceDate: calendar.startOfDay(for: day),
            title: template.title,
            plannedStart: plannedStart,
            plannedDurationMinutes: template.durationMinutes,
            createdAt: template.createdAt,
            updatedAt: template.updatedAt
        )
    }

    private func date(on day: Date, withTimeFrom source: Date) -> Date {
        let dayComponents = calendar.dateComponents([.year, .month, .day], from: day)
        let timeComponents = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: source)
        var components = DateComponents()
        components.year = dayComponents.year
        components.month = dayComponents.month
        components.day = dayComponents.day
        components.hour = timeComponents.hour
        components.minute = timeComponents.minute
        components.second = timeComponents.second
        components.nanosecond = timeComponents.nanosecond
        return calendar.date(from: components) ?? day
    }

    private func finishActiveSegment(_ occurrence: inout ScheduleOccurrence, at date: Date) {
        if let activeSegmentStartedAt = occurrence.activeSegmentStartedAt {
            occurrence.accumulatedActiveSeconds += max(0, date.timeIntervalSince(activeSegmentStartedAt))
        }
        occurrence.activeSegmentStartedAt = nil
    }

    private func endTemplate(_ templateID: UUID, before day: Date, now: Date) {
        guard let index = snapshot.templates.firstIndex(where: { $0.id == templateID }) else { return }
        snapshot.templates[index].endDate = dayBefore(day)
        snapshot.templates[index].updatedAt = now
        removeOverrides(for: templateID, onOrAfter: day)
    }

    private func removeOverrides(for templateID: UUID, onOrAfter day: Date) {
        snapshot.occurrences.removeAll { occurrence in
            guard occurrence.templateID == templateID,
                  let recurrenceDay = recurrenceDay(for: occurrence)
            else { return false }
            return recurrenceDay >= calendar.startOfDay(for: day)
        }
    }

    private func moveOverrides(from oldTemplateID: UUID, to newTemplateID: UUID, onOrAfter day: Date, now: Date) {
        let threshold = calendar.startOfDay(for: day)
        for index in snapshot.occurrences.indices {
            guard snapshot.occurrences[index].templateID == oldTemplateID,
                  let sourceDay = recurrenceDay(for: snapshot.occurrences[index]),
                  sourceDay >= threshold
            else { continue }
            snapshot.occurrences[index].templateID = newTemplateID
            snapshot.occurrences[index].id = repeatingOccurrenceID(templateID: newTemplateID, date: sourceDay)
            snapshot.occurrences[index].updatedAt = now
        }
    }

    private func recurrenceDay(for occurrence: ScheduleOccurrence) -> Date? {
        repeatingReference(from: occurrence.id)?.date
    }

    private func repeatingOccurrenceID(templateID: UUID, date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "weekly:%@:%04d%02d%02d", templateID.uuidString, year, month, day)
    }

    private func repeatingReference(from identifier: String) -> (templateID: UUID, date: Date)? {
        let parts = identifier.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0] == "weekly",
              let templateID = UUID(uuidString: String(parts[1])),
              parts[2].count == 8,
              let year = Int(parts[2].prefix(4)),
              let month = Int(parts[2].dropFirst(4).prefix(2)),
              let day = Int(parts[2].suffix(2))
        else { return nil }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        guard let date = calendar.date(from: components) else { return nil }
        return (templateID, calendar.startOfDay(for: date))
    }

    private func dayBefore(_ date: Date) -> Date? {
        calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: date))
    }

    private func markChanged() {
        hasUnsavedChanges = true
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: item)
    }

    private func saveNow() {
        guard hasUnsavedChanges else { return }
        saveWorkItem?.cancel()
        saveWorkItem = nil
        do {
            try store.save(snapshot)
            hasUnsavedChanges = false
        } catch {
            // The UI owns presentation of save errors. Keeping the dirty flag
            // allows the next state change or explicit flush to retry safely.
            hasUnsavedChanges = true
        }
    }
}
