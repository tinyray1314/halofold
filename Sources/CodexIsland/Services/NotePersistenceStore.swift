import Foundation

extension AppPaths {
    static var notesFile: URL { supportDirectory.appendingPathComponent("notes.json") }
    static var demoNotesFile: URL {
        supportDirectory
            .appendingPathComponent("Demo", isDirectory: true)
            .appendingPathComponent("notes.json")
    }
}

final class NotePersistenceStore {
    private let fileURL: URL
    private let backupDirectory: URL
    private let maximumBackupCount: Int
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileURL: URL = AppPaths.notesFile, maximumBackupCount: Int = 30) {
        self.fileURL = fileURL
        self.backupDirectory = fileURL.deletingLastPathComponent()
            .appendingPathComponent("Note Backups", isDirectory: true)
        self.maximumBackupCount = maximumBackupCount
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() -> NoteLibrarySnapshot? {
        if let snapshot = decode(fileURL) { return snapshot }
        return backupURLs().lazy.compactMap(decode).first
    }

    func save(_ snapshot: NoteLibrarySnapshot, removing removedNoteIDs: Set<UUID> = []) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let merged = merge(snapshot, with: decode(fileURL), removing: removedNoteIDs)
        let data = try encoder.encode(merged)
        try backupCurrentFileIfNeeded(replacingWith: data)
        try data.write(to: fileURL, options: .atomic)
        pruneBackups()
    }

    func backupURLs() -> [URL] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: backupDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return files.filter { $0.pathExtension == "json" }.sorted {
            let left = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let right = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return left > right
        }
    }

    private func decode(_ url: URL) -> NoteLibrarySnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(NoteLibrarySnapshot.self, from: data)
    }

    private func merge(
        _ incoming: NoteLibrarySnapshot,
        with existing: NoteLibrarySnapshot?,
        removing removedNoteIDs: Set<UUID>
    ) -> NoteLibrarySnapshot {
        guard let existing else { return incoming }

        var notesByID = Dictionary(uniqueKeysWithValues: existing.notes
            .filter { !removedNoteIDs.contains($0.id) }
            .map { ($0.id, $0) })
        for note in incoming.notes {
            if let saved = notesByID[note.id], saved.updatedAt > note.updatedAt {
                continue
            }
            notesByID[note.id] = note
        }

        let incomingIDs = Set(incoming.notes.map(\.id))
        let mergedNotes = incoming.notes.compactMap { notesByID[$0.id] }
            + existing.notes.filter {
                !incomingIDs.contains($0.id) && !removedNoteIDs.contains($0.id)
            }
        let selection = incoming.selectedNoteID.flatMap { selected in
            mergedNotes.contains(where: { $0.id == selected }) ? selected : nil
        } ?? mergedNotes.first?.id
        return NoteLibrarySnapshot(notes: mergedNotes, selectedNoteID: selection)
    }

    private func backupCurrentFileIfNeeded(replacingWith newData: Data) throws {
        guard maximumBackupCount > 0,
              let currentData = try? Data(contentsOf: fileURL),
              currentData != newData else { return }
        try FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        let name = "notes-\(formatter.string(from: Date()))-\(UUID().uuidString.prefix(8)).json"
        try currentData.write(to: backupDirectory.appendingPathComponent(name), options: .atomic)
    }

    private func pruneBackups() {
        guard maximumBackupCount >= 0 else { return }
        for url in backupURLs().dropFirst(maximumBackupCount) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
