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

    func testExpandedWorkspaceUsesBentoUnifiedSize() {
        XCTAssertEqual(ExpandedIslandLayout.panelWidth, 510)
        XCTAssertEqual(ExpandedIslandLayout.workspaceHeight, 480)
        XCTAssertEqual(ExpandedIslandLayout.windowHeight, 502)
    }
}

extension TopBarGeometryTests {
    func testNoteWorkspaceAttachesToIslandOnOffsetDisplay() {
        let screen = CGRect(x: -1440, y: 200, width: 1440, height: 900)
        let visible = CGRect(x: -1440, y: 250, width: 1440, height: 818)
        let frame = AnchoredNoteGeometry.frame(screen: screen, visible: visible)
        XCTAssertEqual(frame.midX, screen.midX)
        XCTAssertEqual(frame.maxY, screen.maxY - 32)
        XCTAssertGreaterThanOrEqual(frame.minY, visible.minY + 16)
    }

    func testNoteWorkspaceFitsSmallDisplay() {
        let screen = CGRect(x: 0, y: 0, width: 800, height: 600)
        let visible = CGRect(x: 0, y: 40, width: 800, height: 528)
        let frame = AnchoredNoteGeometry.frame(screen: screen, visible: visible)
        XCTAssertEqual(frame.width, 768)
        XCTAssertEqual(frame.maxY, 568)
        XCTAssertEqual(frame.minY, 56)
    }
}
