import Combine
import Foundation

enum NoteSaveState: Equatable {
    case saved(Date)
    case saving
    case failed
}

@MainActor
final class NoteLibraryModel: ObservableObject {
    @Published private(set) var notes: [NoteDocument]
    @Published var selectedNoteID: UUID?
    @Published private(set) var saveState: NoteSaveState

    private let store: NotePersistenceStore
    private var saveWorkItem: DispatchWorkItem?
    private var hasUnsavedChanges = false
    private var removedNoteIDs: Set<UUID> = []

    init(store suppliedStore: NotePersistenceStore? = nil, demoMode: Bool = false) {
        let isDemo = demoMode || ProcessInfo.processInfo.arguments.contains("--notes-demo")
        self.store = suppliedStore ?? NotePersistenceStore(
            fileURL: isDemo ? AppPaths.demoNotesFile : AppPaths.notesFile
        )
        if isDemo {
            let demoNotes = Self.demoNotes
            notes = demoNotes
            selectedNoteID = demoNotes.first?.id
        } else if let snapshot = self.store.load(), !snapshot.notes.isEmpty {
            notes = snapshot.notes
            selectedNoteID = snapshot.notes.contains(where: { $0.id == snapshot.selectedNoteID })
                ? snapshot.selectedNoteID
                : snapshot.notes.first?.id
        } else {
            let first = NoteDocument(title: AppLocalization.text("新便签"))
            notes = [first]
            selectedNoteID = first.id
        }
        saveState = .saved(Date())
    }

    var selectedNote: NoteDocument? {
        guard let selectedNoteID else { return notes.first }
        return notes.first(where: { $0.id == selectedNoteID }) ?? notes.first
    }

    @discardableResult
    func createNote(title: String = "") -> UUID {
        let note = NoteDocument(title: title)
        notes.insert(note, at: 0)
        selectedNoteID = note.id
        scheduleSave()
        return note.id
    }

    func select(_ note: NoteDocument) {
        selectedNoteID = note.id
        scheduleSave()
    }

    func updateTitle(_ title: String, for id: UUID) {
        update(id) { note in note.title = title }
    }

    func updateBody(_ bodyRTF: Data, for id: UUID) {
        update(id) { note in note.bodyRTF = bodyRTF }
    }

    @discardableResult
    func appendTasks(_ tasks: [String], toNoteTitled title: String) -> [String] {
        let cleaned = tasks.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return [] }

        let index: Int
        if let existing = notes.firstIndex(where: { $0.title == title }) {
            index = existing
        } else {
            notes.insert(NoteDocument(title: title), at: 0)
            index = 0
        }
        let existingTasks = Set(NoteContent.plainText(from: notes[index].bodyRTF)
            .components(separatedBy: .newlines)
            .map(Self.normalizedTaskText))
        var seen = existingTasks
        let inserted = cleaned.filter { seen.insert(Self.normalizedTaskText($0)).inserted }
        guard !inserted.isEmpty else {
            selectedNoteID = notes[index].id
            return []
        }
        notes[index].bodyRTF = NoteContent.appendingTasks(inserted, to: notes[index].bodyRTF)
        notes[index].updatedAt = Date()
        selectedNoteID = notes[index].id
        scheduleSave()
        return inserted
    }

    func delete(_ id: UUID) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        removedNoteIDs.insert(id)
        notes.remove(at: index)
        if notes.isEmpty {
            let replacement = NoteDocument(title: AppLocalization.text("新便签"))
            notes = [replacement]
        }
        if selectedNoteID == id {
            selectedNoteID = notes[min(index, notes.count - 1)].id
        }
        scheduleSave()
    }

    func flush() {
        guard hasUnsavedChanges else { return }
        saveWorkItem?.cancel()
        saveNow()
    }

    private func update(_ id: UUID, change: (inout NoteDocument) -> Void) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        change(&notes[index])
        notes[index].updatedAt = Date()
        scheduleSave()
    }

    private func scheduleSave() {
        hasUnsavedChanges = true
        saveState = .saving
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: item)
    }

    private static func normalizedTaskText(_ source: String) -> String {
        var value = source.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("☐") || value.hasPrefix("☑") { value.removeFirst() }
        return value.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
            .trimmingCharacters(in: .punctuationCharacters)
    }

    private func saveNow() {
        guard hasUnsavedChanges else { return }
        saveWorkItem?.cancel()
        saveWorkItem = nil
        do {
            try store.save(
                NoteLibrarySnapshot(notes: notes, selectedNoteID: selectedNoteID),
                removing: removedNoteIDs
            )
            hasUnsavedChanges = false
            removedNoteIDs.removeAll()
            saveState = .saved(Date())
        } catch {
            saveState = .failed
        }
    }

    private static var demoNotes: [NoteDocument] {
        let now = Date()
        return [
            NoteDocument(title: "灵动岛便签功能", bodyRTF: NoteContent.demoRTF(), createdAt: now, updatedAt: now),
            NoteDocument(title: "本周待办", bodyRTF: NoteContent.emptyRTF, createdAt: now.addingTimeInterval(-120), updatedAt: now.addingTimeInterval(-120)),
            NoteDocument(title: "产品思路", bodyRTF: NoteContent.emptyRTF, createdAt: now.addingTimeInterval(-240), updatedAt: now.addingTimeInterval(-240))
        ]
    }
}
