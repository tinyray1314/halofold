import AppKit
import XCTest
@testable import CodexIsland

@MainActor
final class NoteEditorHandoffTests: XCTestCase {
    func testHiddenUneditedSurfaceCannotOverwriteNewerContent() {
        var shared = NoteContent.emptyRTF
        let stale = RichNoteEditor(documentID: UUID(), rtfData: shared, command: nil, focusRequestID: nil, onChange: { shared = $0 })
        let coordinator = stale.makeCoordinator()
        let text = NSTextView()
        text.string = "旧内容"
        shared = NoteContent.demoRTF()
        let latest = shared
        coordinator.flush(text)
        XCTAssertEqual(shared, latest)
    }

    func testImmediateHandoffFlushesPendingRichTextOnlyOnce() {
        var emissions: [Data] = []
        let editor = RichNoteEditor(documentID: UUID(), rtfData: NoteContent.emptyRTF, command: nil, focusRequestID: nil, onChange: { emissions.append($0) })
        let coordinator = editor.makeCoordinator()
        let text = NSTextView()
        text.textStorage?.setAttributedString(NSAttributedString(string: "马上展开的中文内容", attributes: [.font: NSFont.boldSystemFont(ofSize: 16)]))
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: text))
        coordinator.flush(text)
        coordinator.flush(text)
        XCTAssertEqual(emissions.count, 1)
        XCTAssertEqual(NoteContent.plainText(from: emissions[0]), "马上展开的中文内容")
        let restored = NoteContent.attributedString(from: emissions[0])
        let font = restored.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        XCTAssertTrue(NSFontManager.shared.traits(of: font!).contains(.boldFontMask))
    }
}
