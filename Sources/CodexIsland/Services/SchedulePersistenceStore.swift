import Foundation

extension AppPaths {
    static var schedulesFile: URL { supportDirectory.appendingPathComponent("schedules.json") }
}

/// Local-first JSON storage for `我的日程`. A replacement first copies the
/// previous valid file to a bounded backup list, so a malformed/interrupted
/// primary file can be recovered on the next launch.
public final class SchedulePersistenceStore {
    private let fileURL: URL
    private let backupDirectory: URL
    private let maximumBackupCount: Int
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL? = nil, maximumBackupCount: Int = 30) {
        let resolvedFileURL = fileURL ?? AppPaths.schedulesFile
        self.fileURL = resolvedFileURL
        self.backupDirectory = resolvedFileURL.deletingLastPathComponent()
            .appendingPathComponent("Schedule Backups", isDirectory: true)
        self.maximumBackupCount = maximumBackupCount

        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    public func load() -> ScheduleSnapshot? {
        if let snapshot = decode(fileURL) { return snapshot }
        return backupURLs().lazy.compactMap(decode).first
    }

    public func save(_ snapshot: ScheduleSnapshot) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(snapshot)
        try backupCurrentFileIfNeeded(replacingWith: data)
        try data.write(to: fileURL, options: .atomic)
        pruneBackups()
    }

    public func backupURLs() -> [URL] {
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

    private func decode(_ url: URL) -> ScheduleSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(ScheduleSnapshot.self, from: data)
    }

    private func backupCurrentFileIfNeeded(replacingWith newData: Data) throws {
        guard maximumBackupCount > 0,
              let currentData = try? Data(contentsOf: fileURL),
              currentData != newData
        else { return }

        try FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        let name = "schedules-\(formatter.string(from: Date()))-\(UUID().uuidString.prefix(8)).json"
        try currentData.write(to: backupDirectory.appendingPathComponent(name), options: .atomic)
    }

    private func pruneBackups() {
        guard maximumBackupCount >= 0 else { return }
        for url in backupURLs().dropFirst(maximumBackupCount) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
