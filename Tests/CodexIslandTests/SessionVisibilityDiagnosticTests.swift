import CSQLite
import XCTest
@testable import CodexIsland

final class SessionVisibilityDiagnosticTests: XCTestCase {
    func testHealthyStoresNeedNoAttention() {
        let report = SessionVisibilityDiagnostic.evaluate(
            threads: [
                SessionVisibilityThread(id: "active", isArchived: false, hasRollout: true, isProtectedHistoricalThread: false),
                SessionVisibilityThread(id: "archived", isArchived: true, hasRollout: true, isProtectedHistoricalThread: false)
            ],
            catalogThreadIDs: ["active", "archived"],
            scannedAt: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(report.activeThreadCount, 1)
        XCTAssertEqual(report.missingCatalogEntryCount, 0)
        XCTAssertEqual(report.catalogOnlyEntryCount, 0)
        XCTAssertEqual(report.missingRolloutCount, 0)
        XCTAssertFalse(report.needsAttention)
    }

    func testReportSeparatesMissingEntriesOrphansAndMissingRollouts() {
        let report = SessionVisibilityDiagnostic.evaluate(
            threads: [
                SessionVisibilityThread(id: "visible", isArchived: false, hasRollout: true, isProtectedHistoricalThread: false),
                SessionVisibilityThread(id: "missing-sidebar", isArchived: false, hasRollout: true, isProtectedHistoricalThread: true),
                SessionVisibilityThread(id: "missing-rollout", isArchived: false, hasRollout: false, isProtectedHistoricalThread: false),
                SessionVisibilityThread(id: "archived", isArchived: true, hasRollout: true, isProtectedHistoricalThread: false)
            ],
            catalogThreadIDs: ["visible", "missing-rollout", "archived", "orphan"],
            scannedAt: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(report.activeThreadCount, 3)
        XCTAssertEqual(report.missingCatalogEntryCount, 1)
        XCTAssertEqual(report.catalogOnlyEntryCount, 1)
        XCTAssertEqual(report.missingRolloutCount, 1)
        XCTAssertEqual(report.protectedHistoricalThreadCount, 1)
        XCTAssertTrue(report.needsAttention)
    }

    func testScanReadsSQLiteFixturesWithoutChangingSourceDatabases() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("session-visibility-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("sqlite"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("sessions"), withIntermediateDirectories: true)
        try Data().write(to: root.appendingPathComponent("sessions/visible.jsonl"))
        try Data().write(to: root.appendingPathComponent("sessions/missing-sidebar.jsonl"))

        try createDatabase(at: root.appendingPathComponent("state_5.sqlite")) { database in
            try execute(database, """
                CREATE TABLE threads (
                    id TEXT PRIMARY KEY,
                    archived INTEGER NOT NULL,
                    rollout_path TEXT NOT NULL,
                    history_mode TEXT NOT NULL,
                    has_user_event INTEGER NOT NULL
                );
                INSERT INTO threads VALUES
                    ('visible', 0, 'sessions/visible.jsonl', 'paginated', 1),
                    ('missing-sidebar', 0, 'sessions/missing-sidebar.jsonl', 'paginated', 0),
                    ('missing-rollout', 0, 'sessions/not-on-disk.jsonl', 'paginated', 1),
                    ('archived', 1, 'sessions/visible.jsonl', 'legacy', 1);
                """)
        }
        try createDatabase(at: root.appendingPathComponent("sqlite/codex-dev.db")) { database in
            try execute(database, """
                CREATE TABLE local_thread_catalog (thread_id TEXT NOT NULL);
                INSERT INTO local_thread_catalog VALUES ('visible'), ('missing-rollout'), ('archived'), ('orphan');
                """)
        }

        let stateURL = root.appendingPathComponent("state_5.sqlite")
        let catalogURL = root.appendingPathComponent("sqlite/codex-dev.db")
        let stateBefore = try Data(contentsOf: stateURL)
        let catalogBefore = try Data(contentsOf: catalogURL)

        let report = try SessionVisibilityDiagnostic().scan(codexDirectory: root, now: Date(timeIntervalSince1970: 0))

        XCTAssertEqual(report.activeThreadCount, 3)
        XCTAssertEqual(report.missingCatalogEntryCount, 1)
        XCTAssertEqual(report.catalogOnlyEntryCount, 1)
        XCTAssertEqual(report.missingRolloutCount, 1)
        XCTAssertEqual(report.protectedHistoricalThreadCount, 1)
        XCTAssertEqual(try Data(contentsOf: stateURL), stateBefore)
        XCTAssertEqual(try Data(contentsOf: catalogURL), catalogBefore)
    }

    private func createDatabase(at url: URL, setup: (OpaquePointer) throws -> Void) throws {
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil), SQLITE_OK)
        guard let database else {
            throw NSError(domain: "SessionVisibilityDiagnosticTests", code: 1)
        }
        defer { sqlite3_close(database) }
        try execute(database, "PRAGMA journal_mode = WAL;")
        try setup(database)
    }

    private func execute(_ database: OpaquePointer, _ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(database, sql, nil, nil, &errorMessage) == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? "Unknown SQLite error"
            sqlite3_free(errorMessage)
            throw NSError(domain: "SessionVisibilityDiagnosticTests", code: 2, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }
}
