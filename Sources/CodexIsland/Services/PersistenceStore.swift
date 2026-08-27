import Foundation

struct AppPaths {
    static let supportDirectory: URL = {
        if let override = ProcessInfo.processInfo.environment["HALOFOLD_SUPPORT_DIR"]
            ?? ProcessInfo.processInfo.environment["CODEX_ISLAND_SUPPORT_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let current = base.appendingPathComponent("Halofold", isDirectory: true)
        let legacy = base.appendingPathComponent("Codex Island", isDirectory: true)
        if !FileManager.default.fileExists(atPath: current.path),
           FileManager.default.fileExists(atPath: legacy.path) {
            try? FileManager.default.copyItem(at: legacy, to: current)
        }
        return current
    }()

    static var trackerFile: URL { supportDirectory.appendingPathComponent("tracker.json") }
    static var audioDirectory: URL { supportDirectory.appendingPathComponent("Audio", isDirectory: true) }

    static func prepare() throws {
        try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
    }
}

final class PersistenceStore {
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    func load() -> TrackerSnapshot? {
        guard let data = try? Data(contentsOf: AppPaths.trackerFile) else { return nil }
        return try? decoder.decode(TrackerSnapshot.self, from: data)
    }

    func save(_ snapshot: TrackerSnapshot) throws {
        try AppPaths.prepare()
        let data = try encoder.encode(snapshot)
        try data.write(to: AppPaths.trackerFile, options: .atomic)
    }
}
