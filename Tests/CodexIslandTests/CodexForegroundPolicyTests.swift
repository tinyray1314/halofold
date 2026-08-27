import XCTest
@testable import CodexIsland

final class CodexForegroundPolicyTests: XCTestCase {
    func testOfficialCodexBundleIsHidden() {
        XCTAssertTrue(CodexForegroundPolicy.shouldHide(for: "com.openai.codex"))
    }

    func testOtherApplicationsRemainVisible() {
        XCTAssertFalse(CodexForegroundPolicy.shouldHide(for: "com.apple.finder"))
        XCTAssertFalse(CodexForegroundPolicy.shouldHide(for: "com.tinyray.halofold"))
        XCTAssertFalse(CodexForegroundPolicy.shouldHide(for: nil))
    }
}
