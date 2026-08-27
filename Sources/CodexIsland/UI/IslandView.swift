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
    @ObservedObject var settings: AppSettings
    let presentation: IslandPresentation
    @State private var rotatingUsageIndex = 0
    @State private var expandedResultState: ConversationState?
    private let rotation = Timer.publish(every: 6, on: .main, in: .common).autoconnect()

    init(
        model: ApplicationModel,
        presentation: IslandPresentation = .leftWing
    ) {
        self.model = model
        self.presentation = presentation
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
                    if model.isShowingSettings {
                        SettingsView(model: model)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    } else {
                        ZStack(alignment: .top) {
                            if model.expandedWorkspace == .notes {
                                NotesWorkspaceView(model: model)
                                    .transition(.horizontalFade(offset: -14))
                            } else {
                                expandedCard
                                    .transition(.horizontalFade(offset: 14))
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(Color(red: 0.055, green: 0.065, blue: 0.07))
                        )
                        .animation(.easeOut(duration: 0.2), value: model.expandedWorkspace)
                    }
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
        if settings.isEnabled(.taskStatus) {
            HStack(spacing: settings.collapsedLayoutMode == .compact ? 8 : 11) {
                notchMetric(color: .islandGreen, icon: nil, label: AppLocalization.text(settings.collapsedLayoutMode == .compact ? "运行" : "运行中"), value: model.runningCount)
                notchMetric(color: .white.opacity(0.92), icon: "checkmark", label: AppLocalization.text("完成"), value: model.completedCount)
                notchMetric(color: .islandAmber, icon: "exclamationmark", label: AppLocalization.text("中断"), value: model.pausedCount)
            }
            .padding(.leading, settings.collapsedLayoutMode == .compact ? 11 : 14)
            .padding(.trailing, settings.collapsedLayoutMode.notchContentSafetyInset)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var rotatingUsageView: some View {
        let modules = enabledUsageModules
        if !modules.isEmpty {
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
            HStack {
                Text("活动")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.68))
                Spacer()
                Button {
                    model.showNotesWorkspace()
                } label: {
                    Label("便签", systemImage: "note.text")
                        .font(.system(size: 12.5, weight: .medium))
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(Color.white.opacity(0.07), in: Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.78))
                .accessibilityLabel("打开便签")
                Button {
                    NotificationCenter.default.post(name: .showCodexIslandSettings, object: nil)
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("打开设置")
                QuitApplicationButton()
            }
            .padding(.horizontal, 24)
            .padding(.top, 17)
            .padding(.bottom, 12)

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

            HStack(spacing: 6) {
                Circle()
                    .fill(model.sourceHasWarning ? Color.islandAmber : Color.white.opacity(0.35))
                    .frame(width: 5, height: 5)
                Text(freshnessText)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.42))
            }
            .padding(.horizontal, 24)
            .padding(.top, 13)
            .padding(.bottom, 18)
        }
        .frame(width: ExpandedIslandLayout.panelWidth, height: ExpandedIslandLayout.workspaceHeight)
        .foregroundStyle(.white)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(red: 0.055, green: 0.065, blue: 0.07).opacity(0.96))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.white.opacity(0.2), lineWidth: 1))
        )
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
                        ForEach(runningConversations) { conversation in
                            ConversationRow(conversation: conversation, delegatedCount: model.delegatedChildren(of: conversation).count) {
                                model.open(conversation)
                            }
                            if conversation.id != runningConversations.last?.id {
                                Divider().overlay(Color.white.opacity(0.08)).padding(.leading, 55)
                            }
                        }
                    }
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

    private var runningConversations: [ConversationRecord] {
        model.visibleConversations.filter { $0.state == .running }
    }

    private var completedConversations: [ConversationRecord] {
        model.visibleConversations.filter { $0.state == .completed }
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
                Text(AppLocalization.format(state == .completed ? "完成记录 · %lld" : "中断 · %lld", Int64(conversations.count)))
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

    private func resultStateIcon(_ state: ConversationState) -> some View {
        ZStack {
            Circle()
                .fill(state == .completed ? Color.white.opacity(0.92) : Color.islandAmber)
                .frame(width: 23, height: 23)
            Image(systemName: state == .completed ? "checkmark" : "exclamationmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(state == .completed ? Color.black.opacity(0.75) : Color.white)
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

    private var freshnessText: String {
        guard let date = model.usage.updatedAt else { return model.sourceMessage }
        let source = AppLocalization.text(model.usage.source == .official ? "官方周用量" : "官方用量 · 本机同步")
        return AppLocalization.format("更新于 %@ · %@", date.formatted(date: .omitted, time: .shortened), source)
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
