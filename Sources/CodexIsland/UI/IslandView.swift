import AppKit
import SwiftUI

struct QuitApplicationButton: View {
    @State private var isConfirmingQuit = false

    var body: some View {
        Button {
            isConfirmingQuit = true
        } label: {
            Image(systemName: "power")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(AppLocalization.text("退出 Halofold"))
        .accessibilityLabel(AppLocalization.text("退出 Halofold"))
        .alert(AppLocalization.text("退出 Halofold？"), isPresented: $isConfirmingQuit) {
            Button(AppLocalization.text("取消"), role: .cancel) {}
            Button(AppLocalization.text("退出"), role: .destructive) {
                NSApp.terminate(nil)
            }
        } message: {
            Text(AppLocalization.text("退出后将停止任务监测和提醒。"))
        }
    }
}

enum IslandPresentation {
    case leftWing
    case rightWing
    case expandedContent
}

struct IslandView: View {
    @ObservedObject var model: ApplicationModel
    @ObservedObject var schedule: ScheduleLibraryModel
    @ObservedObject var settings: AppSettings
    let presentation: IslandPresentation
    @State private var isConfirmingQuit = false
    @State private var showsAllRunning = false
    @State private var rotatingUsageIndex = 0
    @State private var expandedResultState: ConversationState?
    private let rotation = Timer.publish(every: 6, on: .main, in: .common).autoconnect()

    init(
        model: ApplicationModel,
        presentation: IslandPresentation = .leftWing
    ) {
        self.model = model
        self.presentation = presentation
        _schedule = ObservedObject(wrappedValue: model.schedule)
        _settings = ObservedObject(wrappedValue: model.settings)
        _expandedResultState = State(initialValue:
            ProcessInfo.processInfo.arguments.contains("--completed-list-demo") ? .completed : nil
        )
    }

    @ViewBuilder
    var body: some View {
        Group {
            switch presentation {
            case .leftWing:
                notchWing(side: .left)
            case .rightWing:
                notchWing(side: .right)
            case .expandedContent:
                VStack(spacing: 0) {
                    Capsule()
                        .fill(Color.black.opacity(0.96))
                        .frame(width: 42, height: 14)
                        .offset(y: -7)
                        .padding(.bottom, -7)
                    ZStack(alignment: .top) {
                        workspaceShell
                            .opacity(model.isShowingSettings ? 0 : 1)
                            .allowsHitTesting(!model.isShowingSettings)
                            .accessibilityHidden(model.isShowingSettings)
                        if model.isShowingSettings { SettingsView(model: model) }
                    }
                    .onChange(of: model.expandedWorkspace) { NSApp.keyWindow?.makeFirstResponder(nil) }
                    .onChange(of: model.isShowingSettings) { NSApp.keyWindow?.makeFirstResponder(nil) }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .onReceive(rotation) { _ in
            let count = enabledUsageModules.count
            if count > 0 { rotatingUsageIndex = (rotatingUsageIndex + 1) % count }
        }
    }

    fileprivate enum WingSide { case left, right }

    private func notchWing(side: WingSide) -> some View {
        Button(action: model.toggleExpanded) {
            Group {
                if side == .left {
                taskStatusWing
                } else {
                rotatingUsageView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AppLocalization.text(model.isExpanded ? "收起 Halofold" : "展开 Halofold"))
    }

    @ViewBuilder
    private var taskStatusWing: some View {
        HStack(spacing: 7) {
            if settings.isEnabled(.codexFollowUp), settings.isEnabled(.taskStatus), model.needsActionCount > 0 {
                Image(systemName: "hand.raised.fill").foregroundStyle(Color.islandMint)
                Text("待处理 \(model.needsActionCount)")
            } else if settings.isEnabled(.codexFollowUp), settings.isEnabled(.taskStatus), model.runningCount > 0 {
                Circle().fill(Color.islandMint).frame(width: 6, height: 6)
                Text("进行中 \(model.runningCount)")
            } else {
                Image(systemName: "square.grid.2x2").foregroundStyle(Color.islandMint)
                Text("随手记")
            }
        }
        .font(.system(size: 12, weight: .medium))
        .padding(.leading, 14)
        .padding(.trailing, settings.collapsedLayoutMode.notchContentSafetyInset)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var rotatingUsageView: some View {
        let modules = enabledUsageModules
        if settings.isEnabled(.schedule), let item = schedule.snapshot.occurrences.first(where: { !$0.isDeleted && $0.status == .running }) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let seconds = max(0, Int(item.expectedEnd.timeIntervalSince(context.date)))
                HStack(spacing: 7) {
                    Image(systemName: "timer").foregroundStyle(Color.islandMint)
                    Text(String(format: "%02d:%02d", seconds / 60, seconds % 60)).monospacedDigit()
                }.font(.system(size: 12, weight: .medium))
            }
        } else if !modules.isEmpty {
            let module = modules[min(rotatingUsageIndex, modules.count - 1)]
            switch module {
            case .weeklyRemaining:
                HStack(spacing: settings.collapsedLayoutMode == .compact ? 7 : 9) {
                    ProgressRing(
                        progress: (model.usage.weeklyRemainingPercent ?? 0) / 100,
                        color: .islandBlue,
                        centerText: compactPercentText,
                        lineWidth: settings.collapsedLayoutMode == .compact ? 3.2 : 3.5,
                        centerFontSize: settings.collapsedLayoutMode == .compact ? 7 : 7.5
                    )
                        .frame(width: settings.collapsedLayoutMode == .compact ? 24 : 26,
                               height: settings.collapsedLayoutMode == .compact ? 24 : 26)
                    Text(AppLocalization.text(settings.collapsedLayoutMode == .compact ? "周" : "本周剩余"))
                }
                .font(.system(size: 12.5))
                .padding(.leading, 8)
                .padding(.trailing, settings.collapsedLayoutMode == .compact ? 11 : 14)
            case .todayTokens:
                HStack(spacing: settings.collapsedLayoutMode == .compact ? 7 : 9) {
                    Image(systemName: "circle.dotted.circle").foregroundStyle(Color.white.opacity(0.9))
                    Text("今日")
                    Text(tokenText(model.usage.todayLocalTokens)).foregroundStyle(Color.islandBlue).fontWeight(.semibold)
                }
                .font(.system(size: 12.5))
                .padding(.leading, 8)
                .padding(.trailing, settings.collapsedLayoutMode == .compact ? 11 : 14)
            case .taskStatus:
                EmptyView()
            }
        }
    }

    private var expandedCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            if settings.isEnabled(.taskStatus), let first = needsActionConversations.first {
                VStack(alignment: .leading, spacing: 3) {
                    Label("需要你处理 · \(needsActionConversations.count) 项", systemImage: "hand.raised.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.islandBlue)
                        .padding(.horizontal, 24)
                        .padding(.top, 8)
                    ConversationRow(conversation: first, delegatedCount: model.delegatedChildren(of: first).count) {
                        model.open(first)
                    }
                }
                .background(Color.islandBlue.opacity(0.07))
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(settings.moduleOrder.filter(settings.isEnabled)) { module in
                        switch module {
                        case .taskStatus:
                            taskList
                        case .weeklyRemaining:
                            weeklySection
                        case .todayTokens:
                            todaySection
                        }
                    }
                }
            }
            .scrollIndicators(.visible)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            sessionVisibilityPanel

            HStack(spacing: 6) {
                Circle()
                    .fill(model.sourceHasWarning ? Color.islandAmber : Color.white.opacity(0.35))
                    .frame(width: 5, height: 5)
                Text(model.sourceStatusText)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.64))
                if model.sourceHasWarning {
                    Spacer(minLength: 4)
                    Button(model.sourceRecoveryTitle, action: model.recoverSource)
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.islandBlue)
                        .fixedSize()
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 13)
            .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.white)
    }

    private var workspaceShell: some View {
        VStack(spacing: 0) {
            HStack(spacing: 3) {
                workspaceTab(.now, title: "现在", icon: "square.grid.2x2", action: model.showQuickPanel)
                if settings.isEnabled(.codexFollowUp) { workspaceTab(.activity, title: "活动", icon: "waveform.path", action: model.showActivityWorkspace) }
                if settings.isEnabled(.quickNotes) { workspaceTab(.notes, title: "便签", icon: "note.text", action: { model.showNotesWorkspace() }) }
                if settings.isEnabled(.schedule) { workspaceTab(.schedule, title: "日程", icon: "calendar", action: model.showScheduleWorkspace) }
                Spacer(minLength: 4)
                Button(action: model.showSettings) {
                    Image(systemName: "gearshape").frame(width: 32, height: 34)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("打开设置")
                Button(action: model.toggleExpanded) {
                    Image(systemName: "chevron.up").frame(width: 28, height: 34)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("收起面板")
                Menu {
                    Button("退出 Halofold…") { isConfirmingQuit = true }
                } label: { Image(systemName: "ellipsis").frame(width: 24, height: 34) }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("应用菜单")
            }
            .padding(.horizontal, 18)
            .padding(.top, 13)
            .padding(.bottom, 10)
            if model.expandedWorkspace != .now { FocusStatusBar(model: model, schedule: model.schedule) }
            ZStack(alignment: .top) {
                WorkspaceSurface(isVisible: model.expandedWorkspace == .now && !model.isShowingSettings) { QuickAssistantView(model: model) }
                WorkspaceSurface(isVisible: model.expandedWorkspace == .activity && !model.isShowingSettings) { expandedCard }
                WorkspaceSurface(isVisible: model.expandedWorkspace == .notes && !model.isShowingSettings) { NotesWorkspaceView(model: model) }
                WorkspaceSurface(isVisible: model.expandedWorkspace == .schedule && !model.isShowingSettings) { ScheduleWorkspaceView(model: model) }
            }
            if let notice = model.undoNotice {
                HStack {
                    Text(notice.message).lineLimit(1)
                    Spacer()
                    Button("撤销", action: model.undoLastDeletion)
                        .buttonStyle(.plain).foregroundStyle(Color.islandBlue)
                }
                .font(.system(size: 13, weight: .medium))
                .padding(12)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 18).padding(.bottom, 12)
            }
        }
        .frame(width: ExpandedIslandLayout.panelWidth, height: ExpandedIslandLayout.workspaceHeight)
        .foregroundStyle(.white.opacity(0.9))
        .background(Color(red: 0.055, green: 0.065, blue: 0.07), in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.white.opacity(0.16), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .environment(\.colorScheme, .dark)
        .preferredColorScheme(.dark)
        .alert("退出 Halofold？", isPresented: $isConfirmingQuit) {
            Button("取消", role: .cancel) {}
            Button("退出", role: .destructive) { NSApp.terminate(nil) }
        } message: { Text("退出后将停止任务监测和提醒。") }
        .alert("确认补回缺失的侧边栏入口？", isPresented: $model.isSessionCatalogRepairConfirmationPresented) {
            Button("取消", role: .cancel) {}
            Button("创建备份并恢复", role: .destructive) {
                model.applyAuthorizedSessionCatalogRepair()
            }
        } message: {
            Text("请确认 Codex 已完全退出。将再次检查条件、为两份数据库和候选 rollout 创建快照，然后只新增缺失的本地侧边栏入口；不会删除、覆盖或修改会话主库、rollout、账号或 provider 配置。")
        }
    }

    private func workspaceTab(_ workspace: ExpandedWorkspace, title: String, icon: String, action: @escaping () -> Void) -> some View {
        let selected = model.expandedWorkspace == workspace
        return Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 13, weight: selected ? .semibold : .medium))
                .padding(.horizontal, 8).frame(height: 34)
                .foregroundStyle(selected ? Color.islandMint : Color.white.opacity(0.65))
                .background(selected ? Color.islandMint.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 9))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("打开" + title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var taskList: some View {
        VStack(spacing: 0) {
            Divider().overlay(Color.white.opacity(0.11)).padding(.horizontal, 24)
            if model.visibleConversations.isEmpty {
                HStack(spacing: 11) {
                    Image(systemName: "moon.zzz")
                    Text("暂无需要跟踪的新对话")
                }
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.5))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
            } else {
                if !runningConversations.isEmpty {
                    LazyVStack(spacing: 0) {
                        ForEach(showsAllRunning ? runningConversations : Array(runningConversations.prefix(3))) { conversation in
                            ConversationRow(conversation: conversation, delegatedCount: model.delegatedChildren(of: conversation).count) {
                                model.open(conversation)
                            }
                            if conversation.id != runningConversations.last?.id {
                                Divider().overlay(Color.white.opacity(0.08)).padding(.leading, 55)
                            }
                        }
                    }
                }
                if runningConversations.count > 3 {
                    Button(showsAllRunning ? "收起运行中的任务" : "显示全部 \(runningConversations.count) 项运行任务") { showsAllRunning.toggle() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.islandBlue)
                        .padding(12)
                }
                if needsActionConversations.count > 1 {
                    Divider().overlay(Color.white.opacity(0.11)).padding(.horizontal, 24)
                    resultDisclosure(state: .needsAction, conversations: needsActionConversations)
                }
                if !completedConversations.isEmpty {
                    Divider().overlay(Color.white.opacity(0.11)).padding(.horizontal, 24)
                    resultDisclosure(state: .completed, conversations: completedConversations)
                }
                if !pausedConversations.isEmpty {
                    Divider().overlay(Color.white.opacity(0.11)).padding(.horizontal, 24)
                    resultDisclosure(state: .paused, conversations: pausedConversations)
                }
            }
        }
    }

    private var sessionVisibilityPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.3.group")
                    .foregroundStyle(model.sessionVisibilityReport?.needsAttention == true ? Color.islandAmber : Color.white.opacity(0.68))
                Text("会话可见性")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.82))
                Spacer(minLength: 6)
                if model.isScanningSessionVisibility {
                    ProgressView().controlSize(.small)
                } else {
                    Button(model.sessionVisibilityReport == nil ? "检查" : "重新检查", action: model.scanSessionVisibility)
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.islandBlue)
                }
            }
            if let report = model.sessionVisibilityReport {
                Text(sessionVisibilitySummary(report))
                    .font(.system(size: 11.5))
                    .foregroundStyle(report.needsAttention ? Color.islandAmber : .white.opacity(0.58))
                    .fixedSize(horizontal: false, vertical: true)
                if report.protectedHistoricalThreadCount > 0 {
                    Text("发现 \(report.protectedHistoricalThreadCount) 条新版历史结构；自动修复已禁用。")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.42))
                }
                sessionCatalogRepairControls(report: report)
            } else if let error = model.sessionVisibilityError {
                Text(error)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.islandAmber)
            } else {
                Text("只读检查主会话、侧边栏目录和 rollout 文件；不会修改 Codex 数据。")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.48))
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 9)
        .background(Color.white.opacity(0.035))
    }

    @ViewBuilder
    private func sessionCatalogRepairControls(report: SessionVisibilityReport) -> some View {
        if model.isPreparingSessionCatalogRepair || model.isApplyingSessionCatalogRepair {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(model.isApplyingSessionCatalogRepair ? "正在备份、补回并复核…" : "正在生成只读恢复计划…")
            }
            .font(.system(size: 10.5))
            .foregroundStyle(.white.opacity(0.5))
        } else if let plan = model.sessionCatalogRepairPlan, !plan.isEmpty {
            Text("已找到 \(plan.candidates.count) 个可安全补回的本地根会话；仅会新增侧边栏入口。")
                .font(.system(size: 10.5))
                .foregroundStyle(Color.islandMint.opacity(0.88))
            Button("申请写入权限并确认恢复", action: model.authorizeSessionCatalogRepair)
                .buttonStyle(.plain)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Color.islandBlue)
        } else if report.missingCatalogEntryCount > 0 {
            Button("生成安全恢复计划", action: model.prepareSessionCatalogRepair)
                .buttonStyle(.plain)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Color.islandBlue)
        }

        if let error = model.sessionCatalogRepairError {
            Text(error)
                .font(.system(size: 10.5))
                .foregroundStyle(Color.islandAmber)
                .fixedSize(horizontal: false, vertical: true)
        }
        if let result = model.sessionCatalogRepairResult {
            Text("已补回 \(result.repairedThreadIDs.count) 个入口，备份已保存到 Halofold 应用支持目录。")
                .font(.system(size: 10.5))
                .foregroundStyle(Color.islandMint.opacity(0.88))
        }
    }

    private func sessionVisibilitySummary(_ report: SessionVisibilityReport) -> String {
        if !report.needsAttention {
            return "已检查 \(report.activeThreadCount) 条未归档会话：目录与本地记录一致。"
        }
        var issues: [String] = []
        if report.missingCatalogEntryCount > 0 { issues.append("缺少 \(report.missingCatalogEntryCount) 个侧边栏入口") }
        if report.catalogOnlyEntryCount > 0 { issues.append("\(report.catalogOnlyEntryCount) 个孤立目录项") }
        if report.missingRolloutCount > 0 { issues.append("\(report.missingRolloutCount) 个缺失 rollout") }
        return issues.joined(separator: "；")
    }

    private var runningConversations: [ConversationRecord] {
        model.visibleConversations.filter { $0.state == .running }
    }

    private var completedConversations: [ConversationRecord] {
        model.visibleConversations.filter { $0.state == .completed }
    }

    private var needsActionConversations: [ConversationRecord] {
        model.visibleConversations.filter { $0.state == .needsAction }
    }

    private var pausedConversations: [ConversationRecord] {
        model.visibleConversations.filter { $0.state == .paused }
    }

    @ViewBuilder
    private func resultDisclosure(state: ConversationState, conversations: [ConversationRecord]) -> some View {
        let isExpanded = expandedResultState == state
        let unreadCount = state == .completed ? conversations.filter(\.isCompletionUnread).count : conversations.count
        HStack(spacing: 11) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expandedResultState = isExpanded ? nil : state
                }
            } label: {
                HStack(spacing: 11) {
                resultStateIcon(state)
                Text(disclosureTitle(for: state, count: conversations.count))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.92))
                Spacer()
                if state == .completed {
                    Text(unreadCount > 0 ? AppLocalization.format("%lld 未查看", Int64(unreadCount)) : AppLocalization.text("均已查看"))
                        .font(.system(size: 11.5, weight: unreadCount > 0 ? .semibold : .regular))
                        .foregroundStyle(unreadCount > 0 ? Color.islandGreen : Color.white.opacity(0.42))
                }
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.65))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if state == .completed, unreadCount > 0 {
                Button("全部已查看") { model.markAllCompletionsRead() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.islandBlue)
            }
        }
        .padding(.horizontal, 24)
        .frame(height: 54)

        if isExpanded {
            LazyVStack(spacing: 0) {
                ForEach(conversations) { conversation in
                    ConversationRow(conversation: conversation, delegatedCount: model.delegatedChildren(of: conversation).count) { model.open(conversation) }
                    if conversation.id != conversations.last?.id {
                        Divider().overlay(Color.white.opacity(0.08)).padding(.leading, 55)
                    }
                }
            }
            .background(Color.white.opacity(0.025))
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private func disclosureTitle(for state: ConversationState, count: Int) -> String {
        switch state {
        case .running: return AppLocalization.format("运行中 · %lld", Int64(count))
        case .needsAction: return AppLocalization.format("待你处理 · %lld", Int64(count))
        case .completed: return AppLocalization.format("完成记录 · %lld", Int64(count))
        case .paused: return AppLocalization.format("中断 · %lld", Int64(count))
        }
    }

    private func resultStateIcon(_ state: ConversationState) -> some View {
        let isCompleted = state == .completed
        let isAction = state == .needsAction
        return ZStack {
            Circle()
                .fill(isCompleted ? Color.white.opacity(0.92) : (isAction ? Color.islandBlue : Color.islandAmber))
                .frame(width: 23, height: 23)
            Image(systemName: isCompleted ? "checkmark" : (isAction ? "hand.raised.fill" : "exclamationmark"))
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(isCompleted ? Color.black.opacity(0.75) : Color.white)
        }
    }

    private var weeklySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionDividerAndTitle(AppLocalization.text("使用情况"))
            HStack(spacing: 13) {
                ProgressRing(
                    progress: (model.usage.weeklyRemainingPercent ?? 0) / 100,
                    color: .islandBlue,
                    centerText: percentText
                )
                    .frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 4) {
                    Text("本周剩余")
                        .font(.system(size: 16, weight: .medium))
                    Text(weeklyResetText)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.48))
                }
                Spacer()
                ProgressView(value: (model.usage.weeklyRemainingPercent ?? 0) / 100)
                    .progressViewStyle(.linear)
                    .tint(.islandBlue)
                    .frame(width: 150)
            }
            .padding(.horizontal, 24)
        }
        .padding(.top, 6)
    }

    private var todaySection: some View {
        HStack(spacing: 13) {
            Image(systemName: "circle.dotted.circle")
                .font(.system(size: 29, weight: .medium))
                .foregroundStyle(.white.opacity(0.88))
                .frame(width: 34)
            Text("本机今日")
                .font(.system(size: 16, weight: .medium))
            Text(tokenText(model.usage.todayLocalTokens))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.islandBlue)
            Text("tokens")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.7))
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
    }

    private func sectionDividerAndTitle(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Divider().overlay(Color.white.opacity(0.11))
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(.horizontal, 24)
    }

    private func compactMetric(color: Color, icon: String?, label: String, value: Int) -> some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().fill(color).frame(width: 18, height: 18)
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(icon == "checkmark" ? Color.black.opacity(0.74) : Color.white)
                }
            }
            Text(label).foregroundStyle(.white.opacity(0.86))
            Text("\(value)").fontWeight(.semibold)
        }
        .font(.system(size: 14))
        .fixedSize()
    }

    private func notchMetric(color: Color, icon: String?, label: String, value: Int) -> some View {
        HStack(spacing: 5) {
            ZStack {
                Circle().fill(color).frame(width: 13, height: 13)
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(icon == "checkmark" ? Color.black.opacity(0.74) : Color.white)
                }
            }
            Text(label)
            Text("\(value)").fontWeight(.semibold)
        }
        .font(.system(size: 11.5))
        .foregroundStyle(.white.opacity(0.9))
        .fixedSize()
    }

    private var enabledUsageModules: [DisplayModule] {
        settings.moduleOrder.filter { $0 != .taskStatus && settings.isEnabled($0) }
    }

    private var percentText: String {
        guard let value = model.usage.weeklyRemainingPercent else { return "—" }
        return "\(Int(value.rounded()))%"
    }

    private var compactPercentText: String {
        guard let value = model.usage.weeklyRemainingPercent else { return "—" }
        return "\(Int(value.rounded()))%"
    }

    private var weeklyResetText: String {
        guard let reset = model.usage.weeklyResetAt else { return AppLocalization.text("重置时间暂不可用") }
        return AppLocalization.format("%@重置", reset.formatted(.dateTime.month(.abbreviated).day()))
    }

    private func tokenText(_ value: Int) -> String {
        if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
        if value >= 1_000 { return String(format: value >= 100_000 ? "%.0fK" : "%.1fK", Double(value) / 1_000) }
        return value.formatted()
    }
}

private struct ConversationRow: View {
    let conversation: ConversationRecord
    let delegatedCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                statusIcon
                VStack(alignment: .leading, spacing: 2) {
                    Text(conversation.title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        if conversation.kind == .automation {
                            Text("自动化")
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(Color.islandBlue)
                        }
                        if delegatedCount > 0 {
                            Text(AppLocalization.format("委派 %lld", Int64(delegatedCount)))
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.55))
                        }
                        if conversation.state == .completed, conversation.isCompletionUnread {
                            Text("未查看")
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(Color.islandGreen)
                        }
                    }
                    if conversation.state == .paused, let reason = conversation.pauseReason {
                        Text(reason)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.islandAmber.opacity(0.86))
                            .lineLimit(1)
                    }
                    if conversation.state == .needsAction, let prompt = conversation.actionPrompt {
                        Text(prompt)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.islandBlue.opacity(0.9))
                            .lineLimit(1)
                    }
                }
                Spacer()
                Text(relativeTime)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.62))
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.76))
            }
            .padding(.horizontal, 24)
            .frame(height: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var statusIcon: some View {
        switch conversation.state {
        case .running:
            Circle().fill(Color.islandGreen).frame(width: 17, height: 17)
        case .needsAction:
            ZStack {
                Circle().fill(Color.islandBlue).frame(width: 22, height: 22)
                Image(systemName: "hand.raised.fill").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
            }
        case .completed:
            ZStack {
                Circle().fill(Color.white.opacity(0.9)).frame(width: 22, height: 22)
                Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.black.opacity(0.75))
            }
        case .paused:
            ZStack {
                Circle().fill(Color.islandAmber).frame(width: 22, height: 22)
                Image(systemName: "exclamationmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
            }
        }
    }

    private var relativeTime: String {
        if conversation.state == .running, let started = conversation.turnStartedAt {
            let minutes = max(1, Int(Date().timeIntervalSince(started) / 60))
            return minutes >= 60
                ? AppLocalization.format("%lld 小时 %lld 分", Int64(minutes / 60), Int64(minutes % 60))
                : AppLocalization.format("%lld 分钟", Int64(minutes))
        }
        return conversation.updatedAt.formatted(date: .omitted, time: .shortened)
    }
}

private struct ProgressRing: View {
    let progress: Double
    let color: Color
    var centerText: String? = nil
    var lineWidth: CGFloat = 5
    var centerFontSize: CGFloat = 9.5
    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.02, min(1, progress)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if let centerText {
                Text(centerText)
                    .font(.system(size: centerText.count > 2 ? centerFontSize : centerFontSize + 1, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                    .minimumScaleFactor(0.55)
                    .lineLimit(1)
                    .padding(lineWidth + 1)
            }
        }
    }
}

extension Color {
    static let islandGreen = Color(red: 0.24, green: 0.84, blue: 0.47)
    static let islandBlue = Color(red: 0.22, green: 0.59, blue: 1.0)
    static let islandAmber = Color(red: 1.0, green: 0.62, blue: 0.13)
}

private struct HorizontalFadeModifier: ViewModifier {
    let opacity: Double
    let offset: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .offset(x: offset)
    }
}

private extension AnyTransition {
    static func horizontalFade(offset: CGFloat) -> AnyTransition {
        .modifier(
            active: HorizontalFadeModifier(opacity: 0, offset: offset),
            identity: HorizontalFadeModifier(opacity: 1, offset: 0)
        )
    }
}

extension Notification.Name {
    static let showCodexIslandSettings = Notification.Name("showCodexIslandSettings")
}

@MainActor
private struct FocusStatusBar: View {
    @ObservedObject var model: ApplicationModel
    @ObservedObject var schedule: ScheduleLibraryModel

    var body: some View {
        if let item = schedule.snapshot.occurrences.first(where: { !$0.isDeleted && $0.status == .running }) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Button {
                    model.showScheduleWorkspace()
                    model.isShowingFocusDetail = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "timer")
                        Text(item.title).lineLimit(1)
                        Spacer()
                        let seconds = max(0, Int(item.expectedEnd.timeIntervalSince(context.date)))
                        Text(String(format: "%02d:%02d", seconds / 60, seconds % 60)).monospacedDigit()
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                    }
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Color.islandBlue)
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(Color.islandBlue.opacity(0.09), in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("查看专注详情：" + item.title)
                .accessibilityValue("剩余 \(max(0, Int(item.expectedEnd.timeIntervalSince(context.date))) / 60) 分钟")
            }
            .padding(.horizontal, 18).padding(.bottom, 10)
        }
    }
}

/// Keep the native hosting view alive while hiding it from both keyboard focus
/// and accessibility. Opacity alone leaves AppKit text editors in the AX tree.
private struct WorkspaceSurface<Content: View>: NSViewRepresentable {
    let isVisible: Bool
    @ViewBuilder var content: () -> Content

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        let host = NSHostingView(rootView: content())
        host.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            host.topAnchor.constraint(equalTo: container.topAnchor),
            host.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        return container
    }

    func updateNSView(_ view: NSView, context: Context) {
        guard let host = view.subviews.first as? NSHostingView<Content> else { return }
        host.rootView = content()
        view.isHidden = !isVisible
        view.setAccessibilityHidden(!isVisible)
    }
}
