import CSQLite
import Foundation

enum CodexDatabaseError: LocalizedError {
    case unavailable(String)
    case query(String)

    var errorDescription: String? {
        switch self {
        case let .unavailable(message), let .query(message): return message
        }
    }
}

final class CodexDatabase {
    private let dataAccess: CodexDataAccess
    private let explicitDirectory: URL?

    init(homeDirectory: URL? = nil, dataAccess: CodexDataAccess = .shared) {
        self.dataAccess = dataAccess
        explicitDirectory = homeDirectory?.appendingPathComponent(".codex", isDirectory: true)
    }

    var codexDirectory: URL? { explicitDirectory ?? dataAccess.codexDirectory }

    func recentThreads(limit: Int = 500, includingArchived: Bool = true) throws -> [ThreadMetadata] {
        let archiveClause = includingArchived ? "" : "WHERE archived = 0"
        return try query(
            sql: """
            SELECT id, title, rollout_path, updated_at, archived, thread_source, source,
                   (SELECT parent_thread_id FROM thread_spawn_edges
                    WHERE child_thread_id = threads.id LIMIT 1)
            FROM threads
            \(archiveClause)
            ORDER BY updated_at DESC
            LIMIT ?
            """,
            bind: { statement in sqlite3_bind_int(statement, 1, Int32(limit)) }
        )
    }

    func threads(updatedAfter date: Date) throws -> [ThreadMetadata] {
        try query(
            sql: """
            SELECT id, title, rollout_path, updated_at, archived, thread_source, source,
                   (SELECT parent_thread_id FROM thread_spawn_edges
                    WHERE child_thread_id = threads.id LIMIT 1)
            FROM threads
            WHERE updated_at >= ?
            ORDER BY updated_at ASC
            """,
            bind: { statement in
                sqlite3_bind_int64(statement, 1, sqlite3_int64(date.timeIntervalSince1970.rounded(.down)))
            }
        )
    }

    private func query(
        sql: String,
        bind: (OpaquePointer) -> Void
    ) throws -> [ThreadMetadata] {
        guard let databaseURL = codexDirectory?.appendingPathComponent("state_5.sqlite") else {
            throw CodexDatabaseError.unavailable(AppLocalization.text("尚未授权访问 .codex 文件夹"))
        }
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(databaseURL.path, &database, flags, nil) == SQLITE_OK, let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? AppLocalization.text("找不到 Codex 本地数据库")
            if let database { sqlite3_close(database) }
            throw CodexDatabaseError.unavailable(message)
        }
        defer { sqlite3_close(database) }

        sqlite3_busy_timeout(database, 700)
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw CodexDatabaseError.query(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }
        bind(statement)

        var rows: [ThreadMetadata] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard
                let idText = sqlite3_column_text(statement, 0),
                let pathText = sqlite3_column_text(statement, 2)
            else { continue }

            let title = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ""
            let threadSource = sqlite3_column_text(statement, 5).map { String(cString: $0) } ?? ""
            let source = sqlite3_column_text(statement, 6).map { String(cString: $0) } ?? ""
            let kind: ConversationKind
            if threadSource == "automation" {
                kind = .automation
            } else if threadSource == "subagent" || source.contains("\"subagent\"") || title.hasPrefix("<codex_delegation>") {
                kind = .subagent
            } else {
                kind = .user
            }
            let storedParent = sqlite3_column_text(statement, 7).map { String(cString: $0) }
            let sourceParent: String? = {
                guard let data = source.data(using: .utf8),
                      let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let subagent = root["subagent"] as? [String: Any],
                      let spawn = subagent["thread_spawn"] as? [String: Any]
                else { return nil }
                return spawn["parent_thread_id"] as? String
            }()
            let legacyDelegationParent: String? = {
                guard let start = title.range(of: "<source_thread_id>"),
                      let end = title.range(of: "</source_thread_id>", range: start.upperBound..<title.endIndex)
                else { return nil }
                let value = String(title[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? nil : value
            }()
            rows.append(ThreadMetadata(
                id: String(cString: idText),
                title: title,
                rolloutPath: String(cString: pathText),
                updatedAt: Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(statement, 3))),
                archived: sqlite3_column_int(statement, 4) != 0,
                kind: kind,
                parentThreadID: storedParent ?? sourceParent ?? legacyDelegationParent
            ))
        }
        return rows
    }
}
