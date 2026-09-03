import AVFoundation
import Foundation
import XCTest
@testable import CodexIsland

final class EventParserTests: XCTestCase {
    private let parser = CodexEventParser()

    func testParsesLifecycleSignals() throws {
        let started = data("""
        {"timestamp":"2026-08-13T18:10:11.123Z","type":"event_msg","payload":{"type":"task_started","turn_id":"turn-1"}}
        """)
        let completed = data("""
        {"timestamp":"2026-08-13T18:12:00Z","type":"event_msg","payload":{"type":"task_complete"}}
        """)
        let paused = data("""
        {"timestamp":"2026-08-13T18:13:00Z","type":"event_msg","payload":{"type":"turn_aborted","reason":"网络连接中断"}}
        """)

        guard case let .taskStarted(turnID, _)? = parser.parse(line: started) else { return XCTFail("missing start") }
        XCTAssertEqual(turnID, "turn-1")
        guard case .taskCompleted? = parser.parse(line: completed) else { return XCTFail("missing complete") }
        guard case let .taskPaused(reason, _)? = parser.parse(line: paused) else { return XCTFail("missing pause") }
        XCTAssertEqual(reason, "网络连接中断")
    }

    func testRetryableErrorDoesNotPause() {
        let line = data("""
        {"timestamp":"2026-08-13T18:13:00Z","type":"event_msg","payload":{"type":"stream_error","will_retry":true,"message":"temporary"}}
        """)
        XCTAssertNil(parser.parse(line: line))
    }

    func testFatalErrorPauses() {
        let line = data("""
        {"timestamp":"2026-08-13T18:13:00Z","type":"event_msg","payload":{"type":"error","retryable":false,"message":"system error"}}
        """)
        guard case let .taskPaused(reason, _)? = parser.parse(line: line) else { return XCTFail("missing pause") }
        XCTAssertEqual(reason, "system error")
    }

    func testTokenAndRateLimitAreBothEmitted() {
        let line = data("""
        {"timestamp":"2026-08-13T18:14:00Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"total_tokens":1250},"rate_limits":{"primary":{"used_percent":36,"resets_at":1790000000}}}}}
        """)
        let signals = parser.parseAll(line: line)
        XCTAssertEqual(signals.count, 2)
        guard case let .tokenDelta(tokens, _) = signals[0] else { return XCTFail("missing token delta") }
        XCTAssertEqual(tokens, 1250)
        guard case let .localRateLimit(used, _, _) = signals[1] else { return XCTFail("missing rate limit") }
        XCTAssertEqual(used, 36)
    }

    func testParsesCurrentPayloadRateLimitLocation() {
        let line = data("""
        {"timestamp":"2026-08-17T05:04:24.740Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"total_tokens":860}},"rate_limits":{"primary":{"used_percent":28,"resets_at":1790000000,"window_minutes":10080}}}}
        """)
        let signals = parser.parseAll(line: line)
        XCTAssertEqual(signals.count, 2)
        guard case let .localRateLimit(used, resetAt, _) = signals[1] else {
            return XCTFail("missing current-schema rate limit")
        }
        XCTAssertEqual(used, 28)
        XCTAssertEqual(resetAt, Date(timeIntervalSince1970: 1_790_000_000))
    }

    private func data(_ string: String) -> Data { Data(string.utf8) }
}

final class ConversationReducerTests: XCTestCase {
    func testCompletedConversationReturnsToRunningOnNextTurn() {
        let now = Date()
        var record = ConversationRecord(id: "id", title: "测试", rolloutPath: "/tmp/test", state: .running, updatedAt: now)
        XCTAssertEqual(ConversationReducer.apply(.taskCompleted(at: now), to: &record), .completed)
        XCTAssertEqual(record.state, .completed)
        XCTAssertEqual(ConversationReducer.apply(.taskStarted(turnID: "next", at: now.addingTimeInterval(5)), to: &record), .running)
        XCTAssertEqual(record.state, .running)
    }

    func testOpeningUICannotMutateConversationState() {
        let now = Date()
        var record = ConversationRecord(id: "id", title: "测试", rolloutPath: "/tmp/test", state: .completed, updatedAt: now)
        XCTAssertNil(ConversationReducer.apply(.tokenDelta(100, at: now), to: &record))
        XCTAssertEqual(record.state, .completed)
    }

    func testCompletionBecomesUnreadAndNextTurnClearsIt() {
        let now = Date()
        var record = ConversationRecord(id: "id", title: "测试", rolloutPath: "/tmp/test", state: .running, updatedAt: now)
        _ = ConversationReducer.apply(.taskCompleted(at: now), to: &record)
        XCTAssertTrue(record.isCompletionUnread)
        _ = ConversationReducer.apply(.taskStarted(turnID: "next", at: now.addingTimeInterval(1)), to: &record)
        XCTAssertFalse(record.isCompletionUnread)
    }

    func testActionRequestHasIndependentStateAndPrompt() {
        let now = Date()
        var record = ConversationRecord(id: "id", title: "测试", rolloutPath: "/tmp/test", state: .running, updatedAt: now)
        XCTAssertEqual(
            ConversationReducer.apply(.taskNeedsAction(prompt: "Codex 需要你登录账号", at: now), to: &record),
            .needsAction
        )
        XCTAssertEqual(record.actionPrompt, "Codex 需要你登录账号")
        XCTAssertFalse(record.isCompletionUnread)
        _ = ConversationReducer.apply(.taskStarted(turnID: "next", at: now.addingTimeInterval(1)), to: &record)
        XCTAssertNil(record.actionPrompt)
    }

    func testLegacyCompletionDecodesAsRead() throws {
        let json = """
        {"id":"old","title":"旧记录","rolloutPath":"/tmp/old","state":"completed","updatedAt":"2026-08-13T18:00:00Z","isArchived":false}
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let record = try decoder.decode(ConversationRecord.self, from: json)
        XCTAssertFalse(record.isCompletionUnread)
        XCTAssertEqual(record.kind, .user)
    }

    func testSubagentIsNotPrimaryStatusItem() {
        let child = ConversationRecord(
            id: "child", title: "内部守护", rolloutPath: "/tmp/child",
            state: .completed, updatedAt: Date(), kind: .subagent,
            parentThreadID: "parent", isCompletionUnread: true
        )
        XCTAssertFalse(child.isPrimaryStatusItem)
    }
}

final class CodexActionRequestDetectorTests: XCTestCase {
    private let detector = CodexActionRequestDetector()

    func testDetectsExplicitLoginRequest() {
        XCTAssertEqual(detect("构建已经完成。\n请先登录账号，我再继续验证。")?.prompt, "Codex 需要你登录账号")
    }

    func testIgnoresOptionalOffer() {
        XCTAssertNil(detect("本次修改已经完成。如果需要，我可以继续帮你上传文件。"))
    }

    func testIgnoresNormalCompletion() {
        XCTAssertNil(detect("修复已完成，测试全部通过。"))
    }

    func testSensitiveRequestUsesSafeSecurityPrompt() {
        let prompt = detect("请提供验证码 938211 以继续登录。")?.prompt
        XCTAssertEqual(prompt, "Codex 需要你完成安全验证，请打开查看")
        XCTAssertFalse(prompt?.contains("938211") ?? true)
    }

    func testLatestCompletedTurnWins() {
        let data = transcript(finals: [
            "请登录账号后继续。",
            "修复已完成，测试全部通过。"
        ])
        XCTAssertNil(detector.detect(in: data))
    }

    func testDetectsEnglishConfirmationRequest() {
        XCTAssertEqual(detect("Please confirm the account information before I continue.")?.prompt, "Codex 需要你确认信息")
    }

    private func detect(_ final: String) -> CodexActionRequest? {
        detector.detect(in: transcript(finals: [final]))
    }

    private func transcript(finals: [String]) -> Data {
        var lines: [String] = []
        for (index, final) in finals.enumerated() {
            lines.append(#"{"timestamp":"2026-08-13T18:10:11Z","type":"event_msg","payload":{"type":"task_started","turn_id":"turn-\#(index)"}}"#)
            let escaped = final.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n")
            lines.append(#"{"timestamp":"2026-08-13T18:11:00Z","type":"response_item","payload":{"type":"message","role":"assistant","phase":"final_answer","content":[{"type":"output_text","text":"\#(escaped)"}]}}"#)
            lines.append(#"{"timestamp":"2026-08-13T18:12:00Z","type":"event_msg","payload":{"type":"task_complete"}}"#)
        }
        return Data((lines.joined(separator: "\n") + "\n").utf8)
    }
}

final class TrackerSnapshotTests: XCTestCase {
    func testSnapshotRoundTripPreservesOffsetsAndTokenCount() throws {
        var snapshot = TrackerSnapshot.fresh(now: Date(timeIntervalSince1970: 1_700_000_000))
        snapshot.todayTokens = 42_123
        snapshot.checkpoints["/tmp/a.jsonl"] = FileCheckpoint(offset: 987)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(TrackerSnapshot.self, from: encoder.encode(snapshot))
        XCTAssertEqual(restored.todayTokens, 42_123)
        XCTAssertEqual(restored.checkpoints["/tmp/a.jsonl"]?.offset, 987)
    }
}

final class CodexUsageClientTests: XCTestCase {
    func testChoosesMainCodexWeeklyBucketInsteadOfSpark() {
        let response: [String: Any] = [
            "rateLimitsByLimitId": [
                "codex_bengalfox": [
                    "primary": ["usedPercent": 0, "windowDurationMins": 10080, "resetsAt": 2_000_000_000]
                ],
                "codex": [
                    "primary": ["usedPercent": 14, "windowDurationMins": 10080, "resetsAt": 1_900_000_000]
                ]
            ]
        ]
        let result = CodexUsageClient.parseRateLimits(response, now: Date(timeIntervalSince1970: 10))
        XCTAssertEqual(result?.remainingPercent, 86)
        XCTAssertEqual(result?.resetAt, Date(timeIntervalSince1970: 1_900_000_000))
    }

    func testIgnoresShortWindowWhenSelectingWeeklyLimit() {
        let response: [String: Any] = [
            "rateLimits": [
                "limitId": "codex",
                "primary": ["usedPercent": 25, "windowDurationMins": 15, "resetsAt": 100]
            ],
            "rateLimitsByLimitId": [
                "codex": [
                    "primary": ["usedPercent": 13, "windowDurationMins": 10080, "resetsAt": 200]
                ]
            ]
        ]
        XCTAssertEqual(CodexUsageClient.parseRateLimits(response)?.remainingPercent, 87)
    }
}

final class AlertBatchAccumulatorTests: XCTestCase {
    func testSameTypeMergesAndPausedComesFirst() {
        var batch = AlertBatchAccumulator()
        batch.add(.completed)
        batch.add(.paused, count: 2)
        batch.add(.completed, count: 3)
        let output = batch.drain()
        XCTAssertEqual(output.count, 2)
        XCTAssertEqual(output[0].0, .paused)
        XCTAssertEqual(output[0].1, 2)
        XCTAssertEqual(output[1].0, .completed)
        XCTAssertEqual(output[1].1, 4)
        XCTAssertTrue(batch.drain().isEmpty)
    }
}

@MainActor
final class AppSettingsTests: XCTestCase {
    func testCompactLayoutIsSmallerThanRelaxedLayout() {
        XCTAssertLessThan(CollapsedLayoutMode.compact.leftWingWidth, CollapsedLayoutMode.relaxed.leftWingWidth)
        XCTAssertLessThan(CollapsedLayoutMode.compact.rightWingWidth, CollapsedLayoutMode.relaxed.rightWingWidth)
        XCTAssertGreaterThanOrEqual(CollapsedLayoutMode.compact.notchContentSafetyInset, 24)
        XCTAssertGreaterThanOrEqual(CollapsedLayoutMode.relaxed.notchContentSafetyInset, 24)
    }

    func testModulesAndVoiceSettingsPersist() {
        let suite = "CodexIslandTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        var first: AppSettings? = AppSettings(defaults: defaults)
        first?.setEnabled(.todayTokens, enabled: false)
        first?.completionText = "完成 {count} 个"
        first?.voiceVolume = 0.41
        first?.collapsedLayoutMode = .relaxed
        first = nil

        let restored = AppSettings(defaults: defaults)
        XCTAssertFalse(restored.isEnabled(.todayTokens))
        XCTAssertEqual(restored.completionText, "完成 {count} 个")
        XCTAssertEqual(restored.voiceVolume, 0.41, accuracy: 0.001)
        XCTAssertEqual(restored.collapsedLayoutMode, .relaxed)
    }

    func testFeatureSettingsKeepLegacyUsersUndisturbedAndRequireOneEnabledFeature() {
        let suite = "CodexIslandTests.Features.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        // An existing alert preference identifies an install that predates
        // 我的日程. Its established modules stay on, while the new schedule
        // module remains opt-in.
        defaults.set(true, forKey: "completionEnabled")
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.enabledFeatures, [.quickNotes, .codexFollowUp])
        XCTAssertFalse(settings.isEnabled(.schedule))

        settings.setEnabled(.schedule, enabled: true)
        settings.setEnabled(.quickNotes, enabled: false)
        settings.setEnabled(.codexFollowUp, enabled: false)
        settings.setEnabled(.schedule, enabled: false)

        XCTAssertEqual(settings.enabledFeatures, [.schedule])
        XCTAssertFalse(settings.canDisable(.schedule))

        let restored = AppSettings(defaults: defaults)
        XCTAssertEqual(restored.enabledFeatures, [.schedule])
    }

    func testModuleMoveBeforePersistsOrder() {
        let suite = "CodexIslandTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        settings.moveModule(.todayTokens, before: .taskStatus)
        XCTAssertEqual(settings.moduleOrder, [.todayTokens, .taskStatus, .weeklyRemaining])
    }

    func testLegacyDefaultAlertTextMigratesWithoutBecomingCustomContent() {
        let suite = "CodexIslandTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("有 {count} 个 Codex 任务已完成", forKey: "completionText")
        defaults.set("有 {count} 个 Codex 任务已暂停", forKey: "pauseText")

        let settings = AppSettings(defaults: defaults)

        XCTAssertEqual(settings.completionText, AppLocalization.defaultCompletionText)
        XCTAssertEqual(settings.pauseText, AppLocalization.defaultPauseText)
    }
}

@MainActor
final class ApplicationModelPresentationTests: XCTestCase {
    func testSettingsReplacesExpandedPanelAndReturnsWithoutCollapsing() {
        let model = ApplicationModel()
        XCTAssertFalse(model.isExpanded)
        XCTAssertFalse(model.isShowingSettings)
        model.showSettings()
        XCTAssertTrue(model.isExpanded)
        XCTAssertTrue(model.isShowingSettings)
        model.finishSettings()
        XCTAssertTrue(model.isExpanded)
        XCTAssertFalse(model.isShowingSettings)
    }

    func testReviewerCanEnterBuiltInDemoWithoutCodexData() {
        let model = ApplicationModel()
        model.enterDemoMode()
        XCTAssertTrue(model.isDemoMode)
        XCTAssertTrue(model.isExpanded)
        XCTAssertFalse(model.isShowingSettings)
        XCTAssertFalse(model.conversations.isEmpty)
        XCTAssertEqual(model.usage.source, .official)
    }

    func testImportAudioReplacesPreviousFileAndSelectsCustomMode() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("HalofoldAudioTests-\(UUID().uuidString)", isDirectory: true)
        let sourceDirectory = root.appendingPathComponent("Sources", isDirectory: true)
        let managedDirectory = root.appendingPathComponent("Managed", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let first = sourceDirectory.appendingPathComponent("first.wav")
        let second = sourceDirectory.appendingPathComponent("second.wav")
        try makeTestWAV(sample: 1_000, at: first)
        try makeTestWAV(sample: 4_000, at: second)

        let suite = "CodexIslandAudioTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        let model = ApplicationModel(settings: settings, audioDirectory: managedDirectory)

        let destination = try model.importAudio(for: .completed, from: first)
        let firstContents = try Data(contentsOf: destination)
        XCTAssertEqual(settings.completionMode, .importedAudio)
        XCTAssertEqual(settings.completionAudioPath, destination.path)

        let replacement = try model.importAudio(for: .completed, from: second)
        XCTAssertEqual(replacement, destination)
        XCTAssertNotEqual(try Data(contentsOf: replacement), firstContents)
        let managedFiles = try FileManager.default.contentsOfDirectory(atPath: managedDirectory.path)
        XCTAssertEqual(managedFiles, ["completed.wav"])
    }

    private func makeTestWAV(sample: Int16, at url: URL) throws {
        let sampleCount = 8_000
        let dataSize = sampleCount * MemoryLayout<Int16>.size
        var data = Data()
        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36 + dataSize), to: &data)
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        append(UInt32(16), to: &data)
        append(UInt16(1), to: &data)
        append(UInt16(1), to: &data)
        append(UInt32(8_000), to: &data)
        append(UInt32(16_000), to: &data)
        append(UInt16(2), to: &data)
        append(UInt16(16), to: &data)
        data.append(contentsOf: Array("data".utf8))
        append(UInt32(dataSize), to: &data)
        for _ in 0..<sampleCount { append(UInt16(bitPattern: sample), to: &data) }
        try data.write(to: url, options: .atomic)
    }

    private func append<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }
}

@MainActor
final class FunVoiceGeneratorTests: XCTestCase {
    func testRenderCreatesPlayableAudio() async throws {
        if ProcessInfo.processInfo.environment["CI"] == "true" {
            throw XCTSkip("AVSpeechSynthesizer rendering requires interactive macOS audio services")
        }

        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("HalofoldFunVoice-\(UUID().uuidString).aiff")
        defer { try? FileManager.default.removeItem(at: destination) }

        let generator = FunVoiceGenerator()
        try await generator.render(
            text: "任务已完成",
            preset: .cartoon,
            voice: AVSpeechSynthesisVoice(language: "zh-CN"),
            volume: 0.8,
            to: destination
        )

        let player = try AVAudioPlayer(contentsOf: destination)
        XCTAssertGreaterThan(player.duration, 0)
    }
}
