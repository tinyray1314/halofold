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
}
