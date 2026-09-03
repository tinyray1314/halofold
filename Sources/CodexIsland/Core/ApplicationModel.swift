import AppKit
import Combine
import Foundation
import ServiceManagement

@MainActor
final class ApplicationModel: ObservableObject {
    private enum SourceHealth {
        case normal
        case usageWarning
        case sourceWarning
    }

    @Published private(set) var conversations: [ConversationRecord] = []
    @Published private(set) var usage: UsageSnapshot = .empty
    @Published private(set) var sourceMessage = AppLocalization.text("正在连接 Codex 本地数据…")
    @Published private var sourceHealth: SourceHealth = .normal
    @Published private(set) var hasCodexFolderAccess = CodexDataAccess.shared.codexDirectory != nil
    @Published private(set) var recordingAlertKind: AlertKind?
    @Published private(set) var isRecordingVoiceDraft = false
    @Published private(set) var isPresentingSystemPermissionPrompt = false
    @Published var isExpanded = false
    @Published var isShowingSettings = false
    @Published var expandedWorkspace: ExpandedWorkspace = .activity {
        didSet { UserDefaults.standard.set(expandedWorkspace.rawValue, forKey: "expandedWorkspace.v1") }
    }

    let settings: AppSettings
    let notes: NoteLibraryModel
    let schedule: ScheduleLibraryModel
    private let persistence: PersistenceStore
    private let eventSource: CodexEventSource
    private let usageClient: CodexUsageClient
    private let audioNotifier: AudioNotifier
    private let audioDirectory: URL
    private let audioRecorder: LocalAudioRecorder
    private let scheduleReminderEngine = ScheduleReminderEngine()
    private let funVoiceGenerator = FunVoiceGenerator()
    private let speechTranscriber = LocalSpeechTranscriber()
    private var snapshot: TrackerSnapshot
    private var usageTimer: Timer?
    private var scheduleTimer: Timer?
    private var saveWorkItem: DispatchWorkItem?
    private var featureSettingsCancellable: AnyCancellable?
    private var hasStarted = false
    private var isCodexMonitoring = false
    private(set) var isDemoMode = false

    init(
        settings suppliedSettings: AppSettings? = nil,
        persistence: PersistenceStore = PersistenceStore(),
        eventSource: CodexEventSource = LocalCodexEventSource(),
        usageClient: CodexUsageClient = CodexUsageClient(),
        audioDirectory: URL = AppPaths.audioDirectory
    ) {
        let settings = suppliedSettings ?? AppSettings()
        self.settings = settings
        self.notes = NoteLibraryModel()
        self.schedule = ScheduleLibraryModel()
        self.persistence = persistence
        self.eventSource = eventSource
        self.usageClient = usageClient
        self.audioNotifier = AudioNotifier(settings: settings)
        self.audioDirectory = audioDirectory
        self.audioRecorder = LocalAudioRecorder(audioDirectory: audioDirectory)
        self.snapshot = persistence.load() ?? TrackerSnapshot.fresh()
        expandedWorkspace = UserDefaults.standard.string(forKey: "expandedWorkspace.v1")
            .flatMap(ExpandedWorkspace.init(rawValue:)) ?? .activity
        if ProcessInfo.processInfo.arguments.contains("--notes-demo") {
            expandedWorkspace = .notes
        } else if ProcessInfo.processInfo.arguments.contains("--activity-demo") {
            expandedWorkspace = .activity
        }
        normalizeExpandedWorkspace()
        featureSettingsCancellable = settings.$enabledFeatures.sink { [weak self] _ in
            self?.handleFeatureSettingsChanged()
        }
        refreshPublishedState()
    }

    var visibleConversations: [ConversationRecord] {
        conversations.filter { !$0.isArchived && $0.isPrimaryStatusItem }.sorted {
            if $0.state.sortOrder != $1.state.sortOrder { return $0.state.sortOrder < $1.state.sortOrder }
            return $0.updatedAt > $1.updatedAt
        }
    }

    var runningCount: Int { visibleConversations.filter { $0.state == .running }.count }
    var needsActionCount: Int { visibleConversations.filter { $0.state == .needsAction }.count }
    var completedCount: Int { visibleConversations.filter { $0.state == .completed && $0.isCompletionUnread }.count }
    var pausedCount: Int { visibleConversations.filter { $0.state == .paused }.count }
    var sourceHasWarning: Bool { sourceHealth != .normal }

    var launchAtLoginEnabled: Bool { SMAppService.mainApp.status == .enabled }

    func start() {
        hasStarted = true
        startScheduleMonitoring()
        if ProcessInfo.processInfo.arguments.contains("--demo") || ProcessInfo.processInfo.environment["CODEX_ISLAND_DEMO"] == "1" {
            loadDemoData()
            return
        }

        guard settings.isEnabled(.codexFollowUp) else { return }
        guard hasCodexFolderAccess else {
            setSourceMessage("需要授权只读访问 .codex 文件夹", warning: true)
            isShowingSettings = true
            isExpanded = true
            return
        }
        startMonitoring()
    }

    private func startMonitoring() {
        guard !isCodexMonitoring else { return }
        isCodexMonitoring = true
        let isFirstLaunch = persistence.load() == nil
        resetDailyCounterIfNeeded()
        eventSource.start(snapshot: snapshot, isFirstLaunch: isFirstLaunch) { [weak self] update in
            DispatchQueue.main.async { self?.handle(update) }
        }
        if !CodexDataAccess.shared.isSandboxed {
            refreshOfficialUsage()
            usageTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
                DispatchQueue.main.async { [weak self] in
                    self?.refreshOfficialUsage()
                }
            }
        }
    }

    private func stopCodexMonitoring() {
        eventSource.stop()
        usageTimer?.invalidate()
        usageTimer = nil
        isCodexMonitoring = false
    }

    private func startScheduleMonitoring() {
        guard scheduleTimer == nil else { return }
        scheduleTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                self?.checkScheduleReminders()
            }
        }
        if let scheduleTimer {
            RunLoop.main.add(scheduleTimer, forMode: .common)
        }
        checkScheduleReminders()
    }

    private func checkScheduleReminders(now: Date = Date()) {
        let frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let isUserSessionAvailable = frontmostBundleID != "com.apple.loginwindow"
            && frontmostBundleID != "com.apple.ScreenSaver.Engine"
        let actions = scheduleReminderEngine.tick(
            ScheduleReminderTick(
                now: now,
                isUserSessionAvailable: isUserSessionAvailable,
                scheduleModuleEnabled: settings.isEnabled(.schedule),
                occurrences: schedule.occurrences(on: now),
                routines: schedule.snapshot.routines
            )
        )

        for action in actions {
            switch action {
            case let .awaitingStartReminder(reminder):
                schedule.markAwaitingStart(reminder.occurrenceID, now: now)
                audioNotifier.speak(
                    "现在 " + scheduleTimeText(reminder.plannedStart) + "，该开始" + reminder.title + "了",
                    interrupt: true
                )
                showScheduleWorkspace()
            case let .overdueDecision(reminder):
                schedule.markOverdueDecision(reminder.occurrenceID, now: now)
                showScheduleWorkspace()
            case let .routineReminder(reminder):
                schedule.markRoutineReminded(reminder.routineID, at: reminder.remindedAt)
                audioNotifier.speak(routineReminderText(for: reminder.kind))
            case let .combinedRoutineReminder(reminders):
                for reminder in reminders {
                    schedule.markRoutineReminded(reminder.routineID, at: reminder.remindedAt)
                }
                audioNotifier.speak(combinedRoutineReminderText(for: reminders.map(\.kind)))
            }
        }
    }

    private func scheduleTimeText(_ date: Date) -> String {
        Self.scheduleTimeFormatter.string(from: date)
    }

    private func routineReminderText(for kind: ScheduleRoutineKind) -> String {
        switch kind {
        case .hydration: return "提醒你喝点水"
        case .activity: return "提醒你起来活动一下"
        }
    }

    private func combinedRoutineReminderText(for kinds: [ScheduleRoutineKind]) -> String {
        let uniqueKinds = Set(kinds)
        if uniqueKinds.contains(.hydration), uniqueKinds.contains(.activity) {
            return "提醒你喝水，也起来活动一下"
        }
        return uniqueKinds.contains(.hydration) ? routineReminderText(for: .hydration) : routineReminderText(for: .activity)
    }

    private func handleFeatureSettingsChanged() {
        if !settings.isEnabled(.schedule) {
            for occurrence in schedule.snapshot.occurrences where occurrence.status == .running {
                schedule.defer(occurrence.id)
            }
            scheduleReminderEngine.resetObservation(at: Date())
        }
        if hasStarted, !isDemoMode {
            if settings.isEnabled(.codexFollowUp) {
                if hasCodexFolderAccess { startMonitoring() }
            } else {
                stopCodexMonitoring()
            }
        }
        normalizeExpandedWorkspace()
        objectWillChange.send()
    }

    private func normalizeExpandedWorkspace() {
        guard !isWorkspaceEnabled(expandedWorkspace) else { return }
        expandedWorkspace = fallbackWorkspace
    }

    private func showFallbackWorkspace() {
        isShowingSettings = false
        expandedWorkspace = fallbackWorkspace
        isExpanded = true
    }

    private var fallbackWorkspace: ExpandedWorkspace {
        if settings.isEnabled(.schedule) { return .schedule }
        if settings.isEnabled(.quickNotes) { return .notes }
        return .activity
    }

    private func isWorkspaceEnabled(_ workspace: ExpandedWorkspace) -> Bool {
        switch workspace {
        case .notes: return settings.isEnabled(.quickNotes)
        case .activity: return settings.isEnabled(.codexFollowUp)
        case .schedule: return settings.isEnabled(.schedule)
        }
    }

    private static let scheduleTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    @discardableResult
    func requestCodexFolderAccess() throws -> Bool {
        guard let _ = try CodexDataAccess.shared.requestAccess() else { return false }
        hasCodexFolderAccess = true
        setSourceMessage("正在连接 Codex 本地数据…")
        stopCodexMonitoring()
        if settings.isEnabled(.codexFollowUp) { startMonitoring() }
        return true
    }

    func stop() {
        cancelAlertRecording()
        hasStarted = false
        stopCodexMonitoring()
        scheduleTimer?.invalidate()
        scheduleTimer = nil
        schedule.flush()
        notes.flush()
        saveNow()
    }

    func toggleExpanded() {
        if isShowingSettings {
            isShowingSettings = false
            isExpanded = false
        } else {
            isExpanded.toggle()
        }
    }

    func showSettings() {
        isShowingSettings = true
        isExpanded = true
    }

    func showNotesWorkspace(createNew: Bool = false) {
        guard settings.isEnabled(.quickNotes) else {
            showFallbackWorkspace()
            return
        }
        isShowingSettings = false
        expandedWorkspace = .notes
        isExpanded = true
        if createNew { _ = notes.createNote() }
    }

    func showActivityWorkspace() {
        guard settings.isEnabled(.codexFollowUp) else {
            showFallbackWorkspace()
            return
        }
        isShowingSettings = false
        expandedWorkspace = .activity
        isExpanded = true
    }

    func showScheduleWorkspace() {
        guard settings.isEnabled(.schedule) else {
            showFallbackWorkspace()
            return
        }
        isShowingSettings = false
        expandedWorkspace = .schedule
        isExpanded = true
    }

    func finishSettings() {
        isShowingSettings = false
        isExpanded = true
    }

    func enterDemoMode() {
        stopCodexMonitoring()
        loadDemoData()
        isShowingSettings = false
        isExpanded = true
    }

    func exitDemoMode() {
        guard isDemoMode else { return }
        isDemoMode = false
        conversations = []
        usage = .empty
        refreshPublishedState()
        if !settings.isEnabled(.codexFollowUp) {
            return
        } else if hasCodexFolderAccess {
            setSourceMessage("正在连接 Codex 本地数据…")
            startMonitoring()
        } else {
            setSourceMessage("需要授权只读访问 .codex 文件夹", warning: true)
            isShowingSettings = true
            isExpanded = true
        }
    }

    func open(_ conversation: ConversationRecord) {
        markCompletionRead(conversation)
        guard let url = URL(string: "codex://threads/\(conversation.id)") else { return }
        NSWorkspace.shared.open(url)
    }

    func markCompletionRead(_ conversation: ConversationRecord) {
        guard var record = snapshot.records[conversation.id], record.isCompletionUnread else { return }
        record.isCompletionUnread = false
        snapshot.records[conversation.id] = record
        refreshPublishedState()
        scheduleSave()
    }

    func markAllCompletionsRead() {
        var changed = false
        for (id, var record) in snapshot.records where record.kind != .subagent && record.isCompletionUnread {
            record.isCompletionUnread = false
            snapshot.records[id] = record
            changed = true
        }
        guard changed else { return }
        refreshPublishedState()
        scheduleSave()
    }

    func delegatedChildren(of conversation: ConversationRecord) -> [ConversationRecord] {
        conversations.filter { $0.kind == .subagent && $0.parentThreadID == conversation.id }
    }

    func previewAlert(_ kind: AlertKind) throws {
        try audioNotifier.preview(kind)
    }

    func previewActionAlert() {
        audioNotifier.previewAction()
    }

    func importAudio(for kind: AlertKind, from sourceURL: URL) throws -> URL {
        try audioNotifier.validateAudio(at: sourceURL)
        try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        let suffix = sourceURL.pathExtension.lowercased()
        let destination = audioDirectory.appendingPathComponent("\(kind.rawValue).\(suffix)")
        let staged = audioDirectory.appendingPathComponent(".\(kind.rawValue)-\(UUID().uuidString).\(suffix)")
        try FileManager.default.copyItem(at: sourceURL, to: staged)
        do {
            try audioNotifier.validateAudio(at: staged)
            if FileManager.default.fileExists(atPath: destination.path) {
                _ = try FileManager.default.replaceItemAt(destination, withItemAt: staged)
            } else {
                try FileManager.default.moveItem(at: staged, to: destination)
            }
        } catch {
            try? FileManager.default.removeItem(at: staged)
            throw error
        }

        let previousPath = kind == .completed ? settings.completionAudioPath : settings.pauseAudioPath
        if kind == .completed {
            settings.completionAudioPath = destination.path
            settings.completionMode = .importedAudio
        } else {
            settings.pauseAudioPath = destination.path
            settings.pauseMode = .importedAudio
        }
        removeSupersededManagedAudio(previousPath, keeping: destination)
        return destination
    }

    func startAlertRecording(for kind: AlertKind) async throws {
        guard recordingAlertKind == nil, !isRecordingVoiceDraft else { throw AudioRecordingError.alreadyRecording }
        let needsPermissionPrompt = audioRecorder.microphonePermissionNeedsPrompt
        if needsPermissionPrompt { isPresentingSystemPermissionPrompt = true }
        defer {
            if needsPermissionPrompt { isPresentingSystemPermissionPrompt = false }
        }
        try await audioRecorder.start(filePrefix: kind.rawValue)
        recordingAlertKind = kind
    }

    func finishAlertRecording(for kind: AlertKind) throws -> URL {
        guard recordingAlertKind == kind else { throw AudioRecordingError.notRecording }
        let result = try audioRecorder.stop()
        recordingAlertKind = nil
        defer { try? FileManager.default.removeItem(at: result) }
        return try importAudio(for: kind, from: result)
    }

    func startVoiceDraftRecording() async throws {
        guard recordingAlertKind == nil, !isRecordingVoiceDraft else { throw AudioRecordingError.alreadyRecording }
        let needsPermissionPrompt = audioRecorder.microphonePermissionNeedsPrompt
        if needsPermissionPrompt { isPresentingSystemPermissionPrompt = true }
        defer {
            if needsPermissionPrompt { isPresentingSystemPermissionPrompt = false }
        }
        try await audioRecorder.start(filePrefix: "voice-draft")
        isRecordingVoiceDraft = true
    }

    func finishVoiceDraftRecordingAndTranscribe() async throws -> String {
        guard isRecordingVoiceDraft else { throw AudioRecordingError.notRecording }
        let recordingURL = try audioRecorder.stop()
        isRecordingVoiceDraft = false
        defer { try? FileManager.default.removeItem(at: recordingURL) }
        let needsPermissionPrompt = speechTranscriber.authorizationNeedsPrompt
        if needsPermissionPrompt { isPresentingSystemPermissionPrompt = true }
        defer {
            if needsPermissionPrompt { isPresentingSystemPermissionPrompt = false }
        }
        let text = try await speechTranscriber.transcribe(audioAt: recordingURL)
        guard !text.isEmpty else { throw FunVoiceError.emptyTranscription }
        return text
    }

    func previewFunVoice(text: String, preset: FunVoicePreset) throws {
        try funVoiceGenerator.preview(
            text: text,
            preset: preset,
            voice: settings.selectedVoice,
            volume: Float(settings.voiceVolume)
        )
    }

    func generateFunVoiceAlert(for kind: AlertKind, text: String, preset: FunVoicePreset) async throws -> URL {
        try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        let temporaryURL = audioDirectory.appendingPathComponent("fun-voice-\(UUID().uuidString).aiff")
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        try await funVoiceGenerator.render(
            text: text,
            preset: preset,
            voice: settings.selectedVoice,
            volume: Float(settings.voiceVolume),
            to: temporaryURL
        )
        return try importAudio(for: kind, from: temporaryURL)
    }

    func cancelAlertRecording() {
        audioRecorder.cancel()
        recordingAlertKind = nil
        isRecordingVoiceDraft = false
    }

    private func removeSupersededManagedAudio(_ path: String?, keeping destination: URL) {
        guard let path else { return }
        let previous = URL(fileURLWithPath: path).standardizedFileURL
        let managedDirectory = audioDirectory.standardizedFileURL.path + "/"
        guard previous != destination.standardizedFileURL,
              previous.path.hasPrefix(managedDirectory)
        else { return }
        try? FileManager.default.removeItem(at: previous)
    }

    func setLaunchAtLogin(_ enabled: Bool) throws {
        if enabled { try SMAppService.mainApp.register() }
        else { try SMAppService.mainApp.unregister() }
        objectWillChange.send()
    }

    func refreshOfficialUsage() {
        usageClient.readWeeklyUsage { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                guard self.settings.isEnabled(.codexFollowUp) else { return }
                switch result {
                case let .success(value):
                    self.usage.weeklyRemainingPercent = value.remainingPercent
                    self.usage.weeklyResetAt = value.resetAt
                    self.usage.updatedAt = value.fetchedAt
                    self.usage.source = .official
                    if self.sourceHealth == .usageWarning {
                        self.setSourceMessage("正在监测 Codex 对话")
                    }
                case let .failure(error):
                    if self.usage.weeklyRemainingPercent == nil { self.usage.source = .unavailable }
                    self.sourceMessage = AppLocalization.format("任务状态正常；周用量更新失败：%@", error.localizedDescription)
                    self.sourceHealth = .usageWarning
                }
            }
        }
    }

    private func handle(_ update: CodexSourceUpdate) {
        guard settings.isEnabled(.codexFollowUp) else { return }
        resetDailyCounterIfNeeded()
        switch update {
        case let .bootstrap(active, checkpoints, todayTokens, metadata):
            snapshot.records = Dictionary(uniqueKeysWithValues: active.map { ($0.id, $0) })
            snapshot.checkpoints = checkpoints
            snapshot.todayTokens = todayTokens
            mergeMetadata(metadata)
            setSourceMessage("正在监测 Codex 对话")
            scheduleSave()
        case let .todayTokenBaseline(tokens):
            snapshot.todayTokens = tokens
            scheduleSave()
        case let .activity(metadata, signals, checkpoint):
            snapshot.checkpoints[metadata.rolloutPath] = checkpoint
            apply(signals: signals, metadata: metadata)
            setSourceMessage("正在监测 Codex 对话")
            scheduleSave()
        case let .metadata(metadata, scannedAt):
            snapshot.lastDatabaseScanAt = scannedAt
            mergeMetadata(metadata)
            setSourceMessage("正在监测 Codex 对话")
            scheduleSave()
        case let .localRateLimit(used, resetAt, date):
            usage.weeklyRemainingPercent = min(100, max(0, 100 - used))
            usage.weeklyResetAt = resetAt
            usage.updatedAt = date
            usage.source = .localFallback
        case let .failed(message):
            sourceMessage = message
            sourceHealth = .sourceWarning
        }
        refreshPublishedState()
    }

    private func apply(signals: [CodexSignal], metadata: ThreadMetadata) {
        for signal in signals {
            switch signal {
            case .taskStarted, .taskNeedsAction, .taskCompleted, .taskPaused:
                if snapshot.records[metadata.id] == nil {
                    guard case .taskStarted = signal else { continue }
                    snapshot.records[metadata.id] = ConversationRecord(
                        id: metadata.id,
                        title: metadata.title,
                        rolloutPath: metadata.rolloutPath,
                        state: .running,
                        updatedAt: metadata.updatedAt,
                        isArchived: metadata.archived,
                        kind: metadata.kind,
                        parentThreadID: metadata.parentThreadID
                    )
                }
                guard var record = snapshot.records[metadata.id] else { continue }
                record.title = metadata.title.isEmpty ? record.title : metadata.title
                record.rolloutPath = metadata.rolloutPath
                record.isArchived = metadata.archived
                record.kind = metadata.kind
                record.parentThreadID = metadata.parentThreadID
                let transition = ConversationReducer.apply(signal, to: &record)
                snapshot.records[metadata.id] = record
                if metadata.kind != .subagent {
                    if transition == .needsAction {
                        audioNotifier.enqueueAction(record.actionPrompt ?? AppLocalization.text("Codex 有一项任务需要你处理，请打开查看"))
                        refreshOfficialUsage()
                    }
                    if transition == .completed {
                        audioNotifier.enqueue(.completed)
                        refreshOfficialUsage()
                    }
                    if transition == .paused {
                        audioNotifier.enqueue(.paused)
                        refreshOfficialUsage()
                    }
                }

            case let .tokenDelta(delta, date):
                if Calendar.current.isDateInToday(date) { snapshot.todayTokens += delta }

            case let .localRateLimit(used, resetAt, date):
                guard usage.source != .official || (usage.updatedAt ?? .distantPast) < date.addingTimeInterval(-360) else { continue }
                usage.weeklyRemainingPercent = min(100, max(0, 100 - used))
                usage.weeklyResetAt = resetAt
                usage.updatedAt = date
                usage.source = .localFallback
            }
        }
    }

    private func mergeMetadata(_ metadata: [ThreadMetadata]) {
        for item in metadata {
            guard var record = snapshot.records[item.id] else { continue }
            record.title = item.title.isEmpty ? record.title : item.title
            record.rolloutPath = item.rolloutPath
            record.isArchived = item.archived
            record.kind = item.kind
            record.parentThreadID = item.parentThreadID
            snapshot.records[item.id] = record
        }
    }

    private func resetDailyCounterIfNeeded() {
        let today = TrackerSnapshot.dayKey(for: Date())
        guard snapshot.todayTokenDate != today else { return }
        snapshot.todayTokenDate = today
        snapshot.todayTokens = 0
        scheduleSave()
    }

    private func refreshPublishedState() {
        conversations = Array(snapshot.records.values)
        usage.todayLocalTokens = snapshot.todayTokens
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: item)
    }

    private func saveNow() {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        try? persistence.save(snapshot)
    }

    private func setSourceMessage(_ key: String, warning: Bool = false) {
        sourceMessage = AppLocalization.text(key)
        sourceHealth = warning ? .sourceWarning : .normal
    }

    private func loadDemoData() {
        isDemoMode = true
        let now = Date()
        let titles = [
            "优化数据导入性能", "重构用户权限模块", "修复移动端布局问题",
            "设计系统组件更新", "API 接口稳定性提升", "报表导出功能增强",
            "完善空状态交互", "更新离线缓存策略"
        ].map(AppLocalization.text)
        var demo = titles.enumerated().map { index, title in
            ConversationRecord(id: UUID().uuidString, title: title, rolloutPath: "", state: .running,
                               updatedAt: now.addingTimeInterval(TimeInterval(-index * 1280)), turnStartedAt: now.addingTimeInterval(TimeInterval(-index * 1280)))
        }
        demo.append(ConversationRecord(id: UUID().uuidString, title: AppLocalization.text("整理发布说明"), rolloutPath: "", state: .completed, updatedAt: now.addingTimeInterval(-6300), isCompletionUnread: true))
        demo.append(ConversationRecord(id: UUID().uuidString, title: AppLocalization.text("发布前账号确认"), rolloutPath: "", state: .needsAction, updatedAt: now.addingTimeInterval(-900), actionPrompt: AppLocalization.text("Codex 需要你登录账号")))
        demo.append(ConversationRecord(id: UUID().uuidString, title: AppLocalization.text("Launch Radar 自动监测"), rolloutPath: "", state: .completed, updatedAt: now.addingTimeInterval(-3100), kind: .automation, isCompletionUnread: true))
        demo.append(ConversationRecord(id: UUID().uuidString, title: AppLocalization.text("同步远端依赖"), rolloutPath: "", state: .paused, updatedAt: now.addingTimeInterval(-4200), pauseReason: AppLocalization.text("网络连接中断")))
        conversations = demo
        usage = UsageSnapshot(weeklyRemainingPercent: 64, weeklyResetAt: Calendar.current.date(byAdding: .day, value: 4, to: now), todayLocalTokens: 182_000, updatedAt: now, source: .official)
        setSourceMessage("视觉验收演示数据")
        isExpanded = !ProcessInfo.processInfo.arguments.contains("--collapsed-demo")
            && !ProcessInfo.processInfo.arguments.contains("--notes-demo")
        if ProcessInfo.processInfo.arguments.contains("--settings-demo") {
            isShowingSettings = true
        }
    }
}
