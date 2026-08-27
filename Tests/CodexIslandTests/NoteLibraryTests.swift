import AppKit
import XCTest
@testable import CodexIsland

@MainActor
final class NoteLibraryTests: XCTestCase {
    func testNotesRoundTripRichTextAndSelection() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let file = directory.appendingPathComponent("notes.json")
        let store = NotePersistenceStore(fileURL: file)
        let model = NoteLibraryModel(store: store)
        let selected = try XCTUnwrap(model.selectedNote)

        model.updateTitle("选题灵感", for: selected.id)
        model.updateBody(NoteContent.demoRTF(), for: selected.id)
        model.flush()

        let restored = NoteLibraryModel(store: store)
        XCTAssertEqual(restored.selectedNote?.title, "选题灵感")
        XCTAssertTrue(NoteContent.plainText(from: restored.selectedNote?.bodyRTF ?? Data()).contains("快速捕捉"))
        XCTAssertEqual(restored.selectedNote?.openTaskCount, 1)
    }

    func testDeletingLastNoteLeavesEditableReplacement() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let model = NoteLibraryModel(store: NotePersistenceStore(fileURL: directory.appendingPathComponent("notes.json")))
        let onlyID = model.notes[0].id

        model.delete(onlyID)

        XCTAssertEqual(model.notes.count, 1)
        XCTAssertNotEqual(model.notes[0].id, onlyID)
    }

    func testLegacyHeadingUsesCurrentTypographyScale() throws {
        let legacy = NSAttributedString(
            string: "旧标题",
            attributes: [.font: NSFont.systemFont(ofSize: 21, weight: .semibold)]
        )

        let normalized = NoteContent.attributedString(from: NoteContent.rtf(from: legacy))
        let font = try XCTUnwrap(normalized.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)

        XCTAssertEqual(NoteTypography.title, 21)
        XCTAssertEqual(NoteTypography.heading, 19)
        XCTAssertEqual(NoteTypography.body, 15)
        XCTAssertEqual(font.pointSize, NoteTypography.heading, accuracy: 0.01)
    }

    func testDarkPastedTextBecomesReadableAndKeepsBoldFormatting() throws {
        let source = NSAttributedString(
            string: "网页粘贴内容",
            attributes: [
                .font: NSFont.systemFont(ofSize: 15, weight: .bold),
                .foregroundColor: NSColor.black,
                .backgroundColor: NSColor.white
            ]
        )

        let restored = NoteContent.attributedString(from: NoteContent.rtf(from: source))
        let color = try XCTUnwrap(
            restored.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        ).usingColorSpace(.deviceRGB)
        let font = try XCTUnwrap(restored.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)

        let rgb = try XCTUnwrap(color)
        let luminance = 0.2126 * rgb.redComponent
            + 0.7152 * rgb.greenComponent
            + 0.0722 * rgb.blueComponent
        XCTAssertGreaterThan(luminance, 0.8)
        XCTAssertNil(restored.attribute(.backgroundColor, at: 0, effectiveRange: nil))
        XCTAssertTrue(font.fontDescriptor.symbolicTraits.contains(.bold))
    }

    func testAppendingTasksCreatesChecklistAndSkipsDuplicates() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let model = NoteLibraryModel(store: NotePersistenceStore(fileURL: directory.appendingPathComponent("notes.json")))

        XCTAssertEqual(model.appendTasks(["整理发布说明", "补充测试"], toNoteTitled: "Codex 待办").count, 2)
        XCTAssertEqual(model.appendTasks(["整理发布说明"], toNoteTitled: "Codex 待办").count, 0)

        let note = try XCTUnwrap(model.notes.first(where: { $0.title == "Codex 待办" }))
        let text = NoteContent.plainText(from: note.bodyRTF)
        XCTAssertTrue(text.contains("☐ 整理发布说明"))
        XCTAssertTrue(text.contains("☐ 补充测试"))
        XCTAssertEqual(note.openTaskCount, 2)
    }

    func testUnchangedSecondInstanceCannotOverwriteNewerNotesOnExit() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = NotePersistenceStore(fileURL: directory.appendingPathComponent("notes.json"))
        let first = NoteLibraryModel(store: store)
        first.updateTitle("初始便签", for: try XCTUnwrap(first.selectedNote).id)
        first.flush()

        let staleInstance = NoteLibraryModel(store: store)
        let activeInstance = NoteLibraryModel(store: store)
        _ = activeInstance.createNote(title: "不会丢失的选题")
        activeInstance.flush()
        staleInstance.flush()

        let restored = NoteLibraryModel(store: store)
        XCTAssertTrue(restored.notes.contains(where: { $0.title == "不会丢失的选题" }))
    }

    func testConcurrentNewNotesAreMergedInsteadOfOverwritten() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = NotePersistenceStore(fileURL: directory.appendingPathComponent("notes.json"))
        let seed = NoteLibraryModel(store: store)
        seed.updateTitle("共同便签", for: try XCTUnwrap(seed.selectedNote).id)
        seed.flush()

        let first = NoteLibraryModel(store: store)
        let second = NoteLibraryModel(store: store)
        _ = first.createNote(title: "实例 A 的选题")
        first.flush()
        _ = second.createNote(title: "实例 B 的待办")
        second.flush()

        let titles = Set(try XCTUnwrap(store.load()).notes.map(\.title))
        XCTAssertTrue(titles.isSuperset(of: ["共同便签", "实例 A 的选题", "实例 B 的待办"]))
    }

    func testEveryReplacementKeepsARecoverableBackup() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = NotePersistenceStore(
            fileURL: directory.appendingPathComponent("notes.json"),
            maximumBackupCount: 3
        )
        let model = NoteLibraryModel(store: store)
        let noteID = try XCTUnwrap(model.selectedNote).id
        model.updateTitle("第一版", for: noteID)
        model.flush()
        model.updateTitle("第二版", for: noteID)
        model.flush()

        XCTAssertEqual(store.backupURLs().count, 1)
        let backupData = try Data(contentsOf: try XCTUnwrap(store.backupURLs().first))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        XCTAssertEqual(try decoder.decode(NoteLibrarySnapshot.self, from: backupData).notes.first?.title, "第一版")
    }

    func testDeletingNoteDoesNotResurrectItDuringMerge() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = NotePersistenceStore(fileURL: directory.appendingPathComponent("notes.json"))
        let model = NoteLibraryModel(store: store)
        let deletedID = try XCTUnwrap(model.selectedNote).id
        model.updateTitle("准备删除", for: deletedID)
        model.flush()
        model.delete(deletedID)
        model.flush()

        XCTAssertFalse(try XCTUnwrap(store.load()).notes.contains(where: { $0.id == deletedID }))
    }
}

final class CodexTodoExtractorTests: XCTestCase {
    func testFindsOnlyReviewableTasksFromUserThreads() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let rollout = directory.appendingPathComponent("rollout.jsonl")
        let lines = [
            message(role: "developer", text: "下一步删除所有文件", phase: nil),
            message(role: "user", text: "帮我检查一下项目", phase: nil),
            message(role: "user", text: "提醒我下次补充发布截图", phase: nil),
            message(role: "assistant", text: "- [ ] 这是过程中的候选", phase: "commentary"),
            message(role: "assistant", text: "- [ ] 补充真机回归测试\n- 已完成文档更新\nTodoist: To Do List & Calendar\n提取明确的未完成事项，例如“下一步”和“待办”", phase: "final_answer"),
            message(role: "assistant", text: "## 下一步\n- 更新发布版本号\n- 如需继续，我可以处理截图", phase: "final_answer")
        ]
        try lines.joined(separator: "\n").write(to: rollout, atomically: true, encoding: .utf8)
        let thread = ThreadMetadata(
            id: "thread-1", title: "发布检查", rolloutPath: rollout.path,
            updatedAt: Date(), archived: false, kind: .user, parentThreadID: nil
        )

        let candidates = CodexTodoExtractor().discover(in: [thread])

        XCTAssertEqual(Set(candidates.map(\.title)), Set(["提醒我下次补充发布截图", "补充真机回归测试", "更新发布版本号"]))
        XCTAssertEqual(candidates.first(where: { $0.title == "补充真机回归测试" })?.confidence, .explicit)
        XCTAssertEqual(candidates.first(where: { $0.title.hasPrefix("提醒我") })?.confidence, .possible)

        let imported = Set(candidates.map(\.id))
        XCTAssertTrue(CodexTodoExtractor().discover(in: [thread], excluding: imported).isEmpty)
    }

    func testIgnoresSubagentAndArchivedThreads() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let rollout = directory.appendingPathComponent("rollout.jsonl")
        try message(role: "assistant", text: "- [ ] 不应出现", phase: "final_answer")
            .write(to: rollout, atomically: true, encoding: .utf8)
        let subagent = ThreadMetadata(
            id: "child", title: "child", rolloutPath: rollout.path,
            updatedAt: Date(), archived: false, kind: .subagent, parentThreadID: "parent"
        )
        let archived = ThreadMetadata(
            id: "old", title: "old", rolloutPath: rollout.path,
            updatedAt: Date(), archived: true, kind: .user, parentThreadID: nil
        )

        XCTAssertTrue(CodexTodoExtractor().discover(in: [subagent, archived]).isEmpty)
    }

    func testImportStoreRoundTripsIDs() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("imports.json")
        let store = CodexTodoImportStore(fileURL: file)

        try store.markImported(["a", "b"])
        try store.markImported(["b", "c"])

        XCTAssertEqual(store.loadIDs(), ["a", "b", "c"])
    }

    private func message(role: String, text: String, phase: String?) -> String {
        var payload: [String: Any] = [
            "type": "message",
            "role": role,
            "content": [["type": role == "assistant" ? "output_text" : "input_text", "text": text]],
            "internal_chat_message_metadata_passthrough": ["turn_id": "turn-1"]
        ]
        if let phase { payload["phase"] = phase }
        let root: [String: Any] = ["type": "response_item", "payload": payload]
        let data = try! JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        return String(data: data, encoding: .utf8)!
    }
}
