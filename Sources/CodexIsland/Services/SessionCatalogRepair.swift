import AppKit
import CSQLite
import Foundation

enum SessionCatalogRepairError: LocalizedError {
    case codexIsRunning
    case unsupportedSchema(String)
    case unavailable(String)
    case database(String)
    case verificationFailed

    var errorDescription: String? {
        switch self {
        case .codexIsRunning:
            return AppLocalization.text("请先完全退出 Codex，再执行会话恢复")
        case let .unsupportedSchema(message), let .unavailable(message), let .database(message):
            return message
        case .verificationFailed:
            return AppLocalization.text("恢复后复核失败；原目录数据库未继续写入")
        }
    }
}

/// A deliberately narrow, auditable description of a missing local sidebar entry.
/// It is built from `state_5.sqlite` only after validating that its rollout still exists.
struct SessionCatalogRepairCandidate: Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let rolloutURL: URL
    let createdAt: Double
    let updatedAt: Double
    let cwd: String
    let modelProvider: String
    let gitBranch: String?
    let threadSource: String?
    let recencyAt: Double
    let projectID: String?
    let conversationOrigin: String?
}

struct SessionCatalogRepairPlan: Equatable, Sendable {
    let createdAt: Date
    let candidates: [SessionCatalogRepairCandidate]

    var isEmpty: Bool { candidates.isEmpty }
}

struct SessionCatalogRepairResult: Equatable, Sendable {
    let repairedThreadIDs: [String]
    let backupDirectory: URL
}

/// Restores only missing entries in Codex's local sidebar catalog.
///
/// This service never writes `state_5.sqlite` or rollout files. It fails closed when the
/// observed schema differs from the small schema surface this repair understands.
final class SessionCatalogRepair: @unchecked Sendable {
    static let localHostID = "local"
    private static let codexBundleIdentifier = "com.openai.codex"
    private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private let isCodexRunning: @Sendable () -> Bool
    private let fileManager: FileManager

    init(
        isCodexRunning: @escaping @Sendable () -> Bool = {
            !NSRunningApplication.runningApplications(withBundleIdentifier: codexBundleIdentifier).isEmpty
        },
        fileManager: FileManager = .default
    ) {
        self.isCodexRunning = isCodexRunning
        self.fileManager = fileManager
    }

    func makePlan(codexDirectory: URL, now: Date = Date()) throws -> SessionCatalogRepairPlan {
        try ensureCodexIsNotRunning()
        let stateURL = codexDirectory.appendingPathComponent("state_5.sqlite")
        let catalogURL = codexDirectory.appendingPathComponent("sqlite/codex-dev.db")
        guard fileManager.fileExists(atPath: stateURL.path), fileManager.fileExists(atPath: catalogURL.path) else {
            throw SessionCatalogRepairError.unavailable(AppLocalization.text("找不到 Codex 会话主数据库或侧边栏目录"))
        }

        let catalogThreadIDs = try readCatalogThreadIDs(from: catalogURL)
        let candidates = try readCandidates(from: stateURL, codexDirectory: codexDirectory, catalogThreadIDs: catalogThreadIDs)
        return SessionCatalogRepairPlan(createdAt: now, candidates: candidates)
    }

    /// Takes database snapshots before opening the catalog for writing, then inserts only the
    /// candidates from a freshly computed plan in one transaction.
    func repair(codexDirectory: URL, backupRoot: URL? = nil, now: Date = Date()) throws -> SessionCatalogRepairResult {
        try ensureCodexIsNotRunning()
        let freshPlan = try makePlan(codexDirectory: codexDirectory, now: now)
        guard !freshPlan.isEmpty else {
            return SessionCatalogRepairResult(repairedThreadIDs: [], backupDirectory: try makeBackupDirectory(at: backupRoot, now: now))
        }

        let backupDirectory = try makeBackupDirectory(at: backupRoot, now: now)
        do {
            try snapshotRepairInputs(codexDirectory: codexDirectory, candidates: freshPlan.candidates, into: backupDirectory)
            // Re-check after the potentially long backup step: Codex must stay closed until commit.
            try ensureCodexIsNotRunning()
            try insert(candidates: freshPlan.candidates, into: codexDirectory.appendingPathComponent("sqlite/codex-dev.db"))
        } catch {
            throw error
        }

        let repairedIDs = Set(try readCatalogThreadIDs(from: codexDirectory.appendingPathComponent("sqlite/codex-dev.db")))
        guard freshPlan.candidates.allSatisfy({ repairedIDs.contains($0.id) }) else {
            throw SessionCatalogRepairError.verificationFailed
        }
        return SessionCatalogRepairResult(repairedThreadIDs: freshPlan.candidates.map(\.id), backupDirectory: backupDirectory)
    }

    private func ensureCodexIsNotRunning() throws {
        if isCodexRunning() { throw SessionCatalogRepairError.codexIsRunning }
    }

    private func readCatalogThreadIDs(from databaseURL: URL) throws -> Set<String> {
        try withDatabase(at: databaseURL, flags: SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX) { database in
            try requireColumns(["host_id", "thread_id"], in: "local_thread_catalog", database: database)
            try requireColumns(["host_id", "host_kind"], in: "local_thread_catalog_hosts", database: database)
            guard try scalarInt("SELECT COUNT(*) FROM local_thread_catalog_hosts WHERE host_id = 'local' AND host_kind = 'local'", database: database) == 1 else {
                throw SessionCatalogRepairError.unsupportedSchema(AppLocalization.text("未找到 Codex 本地侧边栏目录主机"))
            }
            return try stringSet("SELECT thread_id FROM local_thread_catalog WHERE COALESCE(thread_id, '') <> ''", database: database)
        }
    }

    private func readCandidates(
        from stateURL: URL,
        codexDirectory: URL,
        catalogThreadIDs: Set<String>
    ) throws -> [SessionCatalogRepairCandidate] {
        try withDatabase(at: stateURL, flags: SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX) { database in
            try requireColumns([
                "id", "rollout_path", "created_at", "updated_at", "source", "model_provider", "cwd", "title",
                "archived", "git_branch", "thread_source", "recency_at", "project_id", "originator"
            ], in: "threads", database: database)
            try requireColumns(["child_thread_id"], in: "thread_spawn_edges", database: database)
            let sql = """
            SELECT id, rollout_path, created_at, updated_at, cwd, title, model_provider, git_branch,
                   thread_source, recency_at, project_id, originator
            FROM threads
            WHERE archived = 0
              AND source = 'vscode'
              AND NOT EXISTS (
                SELECT 1 FROM thread_spawn_edges edges WHERE edges.child_thread_id = threads.id
              )
            """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
                throw SessionCatalogRepairError.database(String(cString: sqlite3_errmsg(database)))
            }
            defer { sqlite3_finalize(statement) }

            var candidates: [SessionCatalogRepairCandidate] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let idValue = sqlite3_column_text(statement, 0) else { continue }
                let id = String(cString: idValue)
                guard !catalogThreadIDs.contains(id) else { continue }
                let rolloutPath = string(at: 1, from: statement)
                let rolloutURL = rolloutPath.hasPrefix("/")
                    ? URL(fileURLWithPath: rolloutPath)
                    : codexDirectory.appendingPathComponent(rolloutPath)
                guard !rolloutPath.isEmpty, fileManager.fileExists(atPath: rolloutURL.path) else { continue }
                candidates.append(SessionCatalogRepairCandidate(
                    id: id,
                    title: nonEmpty(string(at: 5, from: statement), fallback: AppLocalization.text("未命名会话")),
                    rolloutURL: rolloutURL,
                    createdAt: sqlite3_column_double(statement, 2),
                    updatedAt: sqlite3_column_double(statement, 3),
                    cwd: string(at: 4, from: statement),
                    modelProvider: nonEmpty(string(at: 6, from: statement), fallback: "unknown"),
                    gitBranch: optionalString(at: 7, from: statement),
                    threadSource: optionalString(at: 8, from: statement),
                    recencyAt: sqlite3_column_double(statement, 9),
                    projectID: optionalString(at: 10, from: statement),
                    conversationOrigin: optionalString(at: 11, from: statement)
                ))
            }
            return candidates.sorted { $0.updatedAt > $1.updatedAt }
        }
    }

    private func snapshotRepairInputs(
        codexDirectory: URL,
        candidates: [SessionCatalogRepairCandidate],
        into backupDirectory: URL
    ) throws {
        let databaseDirectory = backupDirectory.appendingPathComponent("databases", isDirectory: true)
        try fileManager.createDirectory(at: databaseDirectory, withIntermediateDirectories: true)
        try snapshotDatabase(
            source: codexDirectory.appendingPathComponent("state_5.sqlite"),
            destination: databaseDirectory.appendingPathComponent("state_5.sqlite")
        )
        try snapshotDatabase(
            source: codexDirectory.appendingPathComponent("sqlite/codex-dev.db"),
            destination: databaseDirectory.appendingPathComponent("codex-dev.db")
        )
        let rolloutDirectory = backupDirectory.appendingPathComponent("rollouts", isDirectory: true)
        try fileManager.createDirectory(at: rolloutDirectory, withIntermediateDirectories: true)
        for candidate in candidates {
            try fileManager.copyItem(at: candidate.rolloutURL, to: rolloutDirectory.appendingPathComponent("\(candidate.id).jsonl"))
        }
    }

    private func insert(candidates: [SessionCatalogRepairCandidate], into databaseURL: URL) throws {
        try withDatabase(at: databaseURL, flags: SQLITE_OPEN_READWRITE | SQLITE_OPEN_NOMUTEX) { database in
            try requireColumns([
                "host_id", "thread_id", "display_title", "source_created_at", "source_updated_at", "cwd", "source_kind",
                "source_detail", "model_provider", "git_branch", "observation_sequence", "missing_candidate", "thread_source",
                "source_recency_at", "pending_observed_title", "project_id", "conversation_origin"
            ], in: "local_thread_catalog", database: database)
            try execute("BEGIN IMMEDIATE TRANSACTION", database: database)
            do {
                let nextSequence = try scalarInt("SELECT COALESCE(MAX(observation_sequence), 0) + 1 FROM local_thread_catalog", database: database)
                let sql = """
                INSERT OR IGNORE INTO local_thread_catalog (
                  host_id, thread_id, display_title, source_created_at, source_updated_at, cwd, source_kind,
                  source_detail, model_provider, git_branch, observation_sequence, missing_candidate, thread_source,
                  source_recency_at, pending_observed_title, project_id, conversation_origin
                ) VALUES (?, ?, ?, ?, ?, ?, 'vscode', 'halofold-session-repair-v1', ?, ?, ?, 0, ?, ?, 0, ?, ?)
                """
                var statement: OpaquePointer?
                guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
                    throw SessionCatalogRepairError.database(String(cString: sqlite3_errmsg(database)))
                }
                defer { sqlite3_finalize(statement) }
                for (offset, candidate) in candidates.enumerated() {
                    sqlite3_reset(statement)
                    sqlite3_clear_bindings(statement)
                    try bind(SessionCatalogRepair.localHostID, at: 1, to: statement)
                    try bind(candidate.id, at: 2, to: statement)
                    try bind(candidate.title, at: 3, to: statement)
                    sqlite3_bind_double(statement, 4, candidate.createdAt)
                    sqlite3_bind_double(statement, 5, candidate.updatedAt)
                    try bind(candidate.cwd, at: 6, to: statement)
                    try bind(candidate.modelProvider, at: 7, to: statement)
                    try bind(candidate.gitBranch, at: 8, to: statement)
                    sqlite3_bind_int64(statement, 9, sqlite3_int64(nextSequence + offset))
                    try bind(candidate.threadSource, at: 10, to: statement)
                    sqlite3_bind_double(statement, 11, candidate.recencyAt)
                    try bind(candidate.projectID, at: 12, to: statement)
                    try bind(candidate.conversationOrigin, at: 13, to: statement)
                    guard sqlite3_step(statement) == SQLITE_DONE else {
                        throw SessionCatalogRepairError.database(String(cString: sqlite3_errmsg(database)))
                    }
                }
                try execute("COMMIT", database: database)
            } catch {
                _ = try? execute("ROLLBACK", database: database)
                throw error
            }
        }
    }

    private func makeBackupDirectory(at backupRoot: URL?, now: Date) throws -> URL {
        let root = backupRoot ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Halofold/SessionRepairBackups", isDirectory: true)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        let name = "repair-\(formatter.string(from: now).replacingOccurrences(of: ":", with: "-"))-\(UUID().uuidString)"
        let directory = root.appendingPathComponent(name, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func snapshotDatabase(source: URL, destination: URL) throws {
        try withDatabase(at: source, flags: SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX) { sourceDatabase in
            try withDatabase(at: destination, flags: SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX) { destinationDatabase in
                guard let backup = sqlite3_backup_init(destinationDatabase, "main", sourceDatabase, "main") else {
                    throw SessionCatalogRepairError.database(String(cString: sqlite3_errmsg(destinationDatabase)))
                }
                defer { sqlite3_backup_finish(backup) }
                guard sqlite3_backup_step(backup, -1) == SQLITE_DONE else {
                    throw SessionCatalogRepairError.database(String(cString: sqlite3_errmsg(destinationDatabase)))
                }
            }
        }
    }

    private func withDatabase<T>(at url: URL, flags: Int32, work: (OpaquePointer) throws -> T) throws -> T {
        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database, flags, nil) == SQLITE_OK, let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? AppLocalization.text("无法打开 Codex 数据库")
            if let database { sqlite3_close(database) }
            throw SessionCatalogRepairError.unavailable(message)
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 1_000)
        return try work(database)
    }

    private func requireColumns(_ columns: Set<String>, in table: String, database: OpaquePointer) throws {
        let actual = try stringSet("SELECT name FROM pragma_table_info('\(table)')", database: database)
        guard columns.isSubset(of: actual) else {
            throw SessionCatalogRepairError.unsupportedSchema(AppLocalization.text("Codex 数据结构已变化，已停止恢复以保护数据"))
        }
    }

    private func scalarInt(_ sql: String, database: OpaquePointer) throws -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SessionCatalogRepairError.database(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw SessionCatalogRepairError.database(String(cString: sqlite3_errmsg(database)))
        }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private func stringSet(_ sql: String, database: OpaquePointer) throws -> Set<String> {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SessionCatalogRepairError.database(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }
        var result = Set<String>()
        while sqlite3_step(statement) == SQLITE_ROW {
            if let value = sqlite3_column_text(statement, 0) { result.insert(String(cString: value)) }
        }
        return result
    }

    private func execute(_ sql: String, database: OpaquePointer) throws {
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(database, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(database))
            sqlite3_free(error)
            throw SessionCatalogRepairError.database(message)
        }
    }

    private func bind(_ value: String?, at index: Int32, to statement: OpaquePointer) throws {
        let result: Int32
        if let value {
            result = sqlite3_bind_text(statement, index, value, -1, Self.sqliteTransient)
        } else {
            result = sqlite3_bind_null(statement, index)
        }
        guard result == SQLITE_OK else { throw SessionCatalogRepairError.database("无法写入会话目录") }
    }

    private func string(at index: Int32, from statement: OpaquePointer) -> String {
        sqlite3_column_text(statement, index).map { String(cString: $0) } ?? ""
    }

    private func optionalString(at index: Int32, from statement: OpaquePointer) -> String? {
        let value = string(at: index, from: statement)
        return value.isEmpty ? nil : value
    }

    private func nonEmpty(_ value: String, fallback: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : value
    }
}
