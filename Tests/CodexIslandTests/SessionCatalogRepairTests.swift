import CSQLite
import XCTest
@testable import CodexIsland

final class SessionCatalogRepairTests: XCTestCase {
    func testRepairAddsOnlyEligibleMissingLocalRootAndSnapshotsInputs() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let stateBefore = try Data(contentsOf: fixture.stateURL)
        let childRolloutBefore = try Data(contentsOf: fixture.root.appendingPathComponent("sessions/child.jsonl"))
        let backupRoot = fixture.root.appendingPathComponent("backups")
        let repair = SessionCatalogRepair(isCodexRunning: { false })

        let plan = try repair.makePlan(codexDirectory: fixture.root, now: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(plan.candidates.map(\.id), ["missing-root"])
        XCTAssertEqual(plan.candidates.first?.title, "Missing root")

        let result = try repair.repair(
            codexDirectory: fixture.root,
            backupRoot: backupRoot,
            now: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(result.repairedThreadIDs, ["missing-root"])
        XCTAssertEqual(try catalogIDs(at: fixture.catalogURL), ["existing", "missing-root"])
        XCTAssertEqual(try Data(contentsOf: fixture.stateURL), stateBefore)
        XCTAssertEqual(try Data(contentsOf: fixture.root.appendingPathComponent("sessions/child.jsonl")), childRolloutBefore)
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.backupDirectory.appendingPathComponent("databases/state_5.sqlite").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.backupDirectory.appendingPathComponent("databases/codex-dev.db").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.backupDirectory.appendingPathComponent("rollouts/missing-root.jsonl").path))
        XCTAssertEqual(try catalogIDs(at: result.backupDirectory.appendingPathComponent("databases/codex-dev.db")), ["existing"])
        XCTAssertEqual(try Data(contentsOf: result.backupDirectory.appendingPathComponent("rollouts/missing-root.jsonl")), Data("root".utf8))
    }

    func testRepairDoesNothingWhenCodexIsRunning() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let catalogBefore = try Data(contentsOf: fixture.catalogURL)
        let repair = SessionCatalogRepair(isCodexRunning: { true })

        XCTAssertThrowsError(try repair.makePlan(codexDirectory: fixture.root)) { error in
            guard case .codexIsRunning = error as? SessionCatalogRepairError else {
                return XCTFail("Expected Codex-running protection, got \(error)")
            }
        }
        XCTAssertEqual(try Data(contentsOf: fixture.catalogURL), catalogBefore)
    }

    func testRepairStopsBeforeCommitIfCodexStartsDuringBackup() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let catalogBefore = try Data(contentsOf: fixture.catalogURL)
        let checks = LockedCounter()
        let repair = SessionCatalogRepair(isCodexRunning: {
            checks.incrementAndRead() >= 3
        })

        XCTAssertThrowsError(try repair.repair(
            codexDirectory: fixture.root,
            backupRoot: fixture.root.appendingPathComponent("backups")
        )) { error in
            guard case .codexIsRunning = error as? SessionCatalogRepairError else {
                return XCTFail("Expected Codex-running protection, got \(error)")
            }
        }
        XCTAssertEqual(try Data(contentsOf: fixture.catalogURL), catalogBefore)
    }

    private func makeFixture() throws -> (root: URL, stateURL: URL, catalogURL: URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("session-repair-\(UUID().uuidString)")
        let stateURL = root.appendingPathComponent("state_5.sqlite")
        let catalogURL = root.appendingPathComponent("sqlite/codex-dev.db")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("sqlite"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("sessions"), withIntermediateDirectories: true)
        for (name, contents) in [("root", "root"), ("child", "child"), ("existing", "existing"), ("archived", "archived"), ("other-source", "other")] {
            try Data(contents.utf8).write(to: root.appendingPathComponent("sessions/\(name).jsonl"))
        }

        try createDatabase(at: stateURL, sql: """
        CREATE TABLE threads (
          id TEXT PRIMARY KEY, rollout_path TEXT NOT NULL, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
          source TEXT NOT NULL, model_provider TEXT NOT NULL, cwd TEXT NOT NULL, title TEXT NOT NULL,
          archived INTEGER NOT NULL, git_branch TEXT, thread_source TEXT, recency_at INTEGER NOT NULL,
          project_id TEXT, originator TEXT
        );
        CREATE TABLE thread_spawn_edges (parent_thread_id TEXT NOT NULL, child_thread_id TEXT NOT NULL PRIMARY KEY, status TEXT NOT NULL);
        INSERT INTO threads VALUES
          ('missing-root', 'sessions/root.jsonl', 10, 20, 'vscode', 'openai', '/workspace', 'Missing root', 0, 'main', 'user', 20, 'project-a', 'local'),
          ('child', 'sessions/child.jsonl', 11, 21, 'vscode', 'openai', '/workspace', 'Child', 0, NULL, 'subagent', 21, NULL, NULL),
          ('existing', 'sessions/existing.jsonl', 12, 22, 'vscode', 'openai', '/workspace', 'Existing', 0, NULL, 'user', 22, NULL, NULL),
          ('archived', 'sessions/archived.jsonl', 13, 23, 'vscode', 'openai', '/workspace', 'Archived', 1, NULL, 'user', 23, NULL, NULL),
          ('missing-rollout', 'sessions/nope.jsonl', 14, 24, 'vscode', 'openai', '/workspace', 'No rollout', 0, NULL, 'user', 24, NULL, NULL),
          ('other-source', 'sessions/other-source.jsonl', 15, 25, 'chatgpt', 'openai', '/workspace', 'Other source', 0, NULL, 'user', 25, NULL, NULL);
        INSERT INTO thread_spawn_edges VALUES ('missing-root', 'child', 'completed');
        """)
        try createDatabase(at: catalogURL, sql: """
        CREATE TABLE local_thread_catalog_hosts (host_id TEXT PRIMARY KEY, host_kind TEXT NOT NULL);
        INSERT INTO local_thread_catalog_hosts VALUES ('local', 'local');
        CREATE TABLE local_thread_catalog (
          host_id TEXT NOT NULL, thread_id TEXT NOT NULL, display_title TEXT NOT NULL,
          source_created_at REAL NOT NULL, source_updated_at REAL NOT NULL, cwd TEXT,
          source_kind TEXT NOT NULL, source_detail TEXT, model_provider TEXT, git_branch TEXT,
          observation_sequence INTEGER NOT NULL, missing_candidate INTEGER NOT NULL DEFAULT 0,
          thread_source TEXT, source_recency_at REAL NOT NULL DEFAULT 0,
          pending_observed_title INTEGER NOT NULL DEFAULT 0, project_id TEXT, conversation_origin TEXT,
          PRIMARY KEY (host_id, thread_id)
        );
        INSERT INTO local_thread_catalog VALUES ('local', 'existing', 'Existing', 12, 22, '/workspace', 'vscode', NULL, 'openai', NULL, 4, 0, 'user', 22, 0, NULL, NULL);
        """)
        return (root, stateURL, catalogURL)
    }

    private func createDatabase(at url: URL, sql: String) throws {
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil), SQLITE_OK)
        guard let database else { throw NSError(domain: "SessionCatalogRepairTests", code: 1) }
        defer { sqlite3_close(database) }
        var error: UnsafeMutablePointer<CChar>?
        XCTAssertEqual(sqlite3_exec(database, sql, nil, nil, &error), SQLITE_OK, error.map { String(cString: $0) } ?? "Unknown SQLite error")
        sqlite3_free(error)
    }

    private func catalogIDs(at url: URL) throws -> [String] {
        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let database else {
            throw NSError(domain: "SessionCatalogRepairTests", code: 2)
        }
        defer { sqlite3_close(database) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT thread_id FROM local_thread_catalog ORDER BY thread_id", -1, &statement, nil) == SQLITE_OK, let statement else {
            throw NSError(domain: "SessionCatalogRepairTests", code: 3)
        }
        defer { sqlite3_finalize(statement) }
        var ids: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            ids.append(String(cString: sqlite3_column_text(statement, 0)))
        }
        return ids
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func incrementAndRead() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }
}
