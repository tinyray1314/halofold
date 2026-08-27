import XCTest
@testable import CodexIsland

final class TopBarGeometryTests: XCTestCase {
    func testUsesRealNotchEdgesWhenAvailable() {
        let edges = TopBarGeometry.notchEdges(
            frameMidX: 900,
            auxiliaryLeftMaxX: 812,
            auxiliaryRightMinX: 988
        )
        XCTAssertEqual(edges.left, 812)
        XCTAssertEqual(edges.right, 988)
    }

    func testFallsBackToCenteredVirtualNotchOnPlainDisplay() {
        let edges = TopBarGeometry.notchEdges(
            frameMidX: 900,
            auxiliaryLeftMaxX: nil,
            auxiliaryRightMinX: nil
        )
        XCTAssertEqual(edges.left, 807.5)
        XCTAssertEqual(edges.right, 992.5)
    }

    func testPermissionPromptTemporarilyUsesLowerWindowLevel() {
        XCTAssertLessThan(
            IslandWindowLevelPolicy.whilePresentingSystemPermission.rawValue,
            IslandWindowLevelPolicy.normalExpanded.rawValue
        )
    }

    func testExpandedWorkspaceUsesCompactUnifiedSize() {
        XCTAssertEqual(ExpandedIslandLayout.panelWidth, 510)
        XCTAssertEqual(ExpandedIslandLayout.workspaceHeight, 443)
        XCTAssertEqual(ExpandedIslandLayout.windowHeight, 465)
    }
}
