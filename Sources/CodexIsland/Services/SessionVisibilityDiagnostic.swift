import CSQLite
import Foundation

enum SessionVisibilityDiagnosticError: LocalizedError {
    case unavailable(String)
    case query(String)

    var errorDescription: String? {
        switch self {
        case let .unavailable(message), let .query(message): return message
        }
    }
}

struct SessionVisibilityThread: Equatable, Sendable {
    let id: String
    let isArchived: Bool
    let hasRollout: Bool
    let isProtectedHistoricalThread: Bool
}

/// Compares the two local stores Codex currently uses for a conversation and its sidebar entry.
/// It opens databases with SQLITE_OPEN_READONLY and only checks rollout file existence.
final class SessionVisibilityDiagnostic: Sendable {
    func scan(codexDirectory: URL, now: Date = Date()) throws -> SessionVisibilityReport {
        let stateURL = codexDirectory.appendingPathComponent("state_5.sqlite")
        let catalogURL = codexDirectory.appendingPathComponent("sqlite/codex-dev.db")
        guard FileManager.default.fileExists(atPath: stateURL.path) else {
            throw SessionVisibilityDiagnosticError.unavailable(AppLocalization.text("找不到 Codex 会话主数据库"))
        }
        guard FileManager.default.fileExists(atPath: catalogURL.path) else {
            throw SessionVisibilityDiagnosticError.unavailable(AppLocalization.text("找不到 Codex 侧边栏目录"))
        }

        let threads = try readThreads(from: stateURL, codexDirectory: codexDirectory)
        let catalogThreadIDs = try readCatalogThreadIDs(from: catalogURL)
        return Self.evaluate(threads: threads, catalogThreadIDs: catalogThreadIDs, scannedAt: now)
    }

    static func evaluate(
        threads: [SessionVisibilityThread],
        catalogThreadIDs: Set<String>,
        scannedAt: Date
    ) -> SessionVisibilityReport {
        let activeThreads = threads.filter { !$0.isArchived }
        let activeIDs = Set(activeThreads.map(\.id))
        let canonicalIDs = Set(threads.map(\.id))
        return SessionVisibilityReport(
            scannedAt: scannedAt,
            activeThreadCount: activeThreads.count,
            missingCatalogEntryCount: activeIDs.subtracting(catalogThreadIDs).count,
            catalogOnlyEntryCount: catalogThreadIDs.subtracting(canonicalIDs).count,
            missingRolloutCount: activeThreads.filter { !$0.hasRollout }.count,
            protectedHistoricalThreadCount: activeThreads.filter(\.isProtectedHistoricalThread).count
        )
    }

    private func readThreads(from databaseURL: URL, codexDirectory: URL) throws -> [SessionVisibilityThread] {
        try withReadOnlyDatabase(at: databaseURL) { database in
            let sql = "SELECT id, archived, rollout_path, history_mode, has_user_event FROM threads"
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
                throw SessionVisibilityDiagnosticError.query(String(cString: sqlite3_errmsg(database)))
            }
            defer { sqlite3_finalize(statement) }

            var threads: [SessionVisibilityThread] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let idText = sqlite3_column_text(statement, 0) else { continue }
                let rolloutPath = sqlite3_column_text(statement, 2).map { String(cString: $0) } ?? ""
                let historyMode = sqlite3_column_text(statement, 3).map { String(cString: $0) } ?? ""
                let hasUserEvent = sqlite3_column_int(statement, 4) != 0
                let rolloutURL = rolloutPath.hasPrefix("/")
                    ? URL(fileURLWithPath: rolloutPath)
                    : codexDirectory.appendingPathComponent(rolloutPath)
                threads.append(SessionVisibilityThread(
                    id: String(cString: idText),
                    isArchived: sqlite3_column_int(statement, 1) != 0,
                    hasRollout: !rolloutPath.isEmpty && FileManager.default.fileExists(atPath: rolloutURL.path),
                    isProtectedHistoricalThread: historyMode == "paginated" && !hasUserEvent
                ))
            }
            return threads
        }
    }

    private func readCatalogThreadIDs(from databaseURL: URL) throws -> Set<String> {
        try withReadOnlyDatabase(at: databaseURL) { database in
            let sql = "SELECT thread_id FROM local_thread_catalog WHERE COALESCE(thread_id, '') <> ''"
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
                throw SessionVisibilityDiagnosticError.query(String(cString: sqlite3_errmsg(database)))
            }
            defer { sqlite3_finalize(statement) }

            var identifiers = Set<String>()
            while sqlite3_step(statement) == SQLITE_ROW {
                if let text = sqlite3_column_text(statement, 0) {
                    identifiers.insert(String(cString: text))
                }
            }
            return identifiers
        }
    }

    private func withReadOnlyDatabase<T>(at url: URL, work: (OpaquePointer) throws -> T) throws -> T {
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(url.path, &database, flags, nil) == SQLITE_OK, let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? AppLocalization.text("无法读取 Codex 本地数据库")
            if let database { sqlite3_close(database) }
            throw SessionVisibilityDiagnosticError.unavailable(message)
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 700)
        return try work(database)
    }
}
