import SwiftUI

/// The expandable, local-only schedule workspace. Its detailed state lives in
/// `ScheduleLibraryModel`; this view keeps only temporary editing presentation
/// state so plans survive closing the panel or restarting Halofold.
@MainActor
struct ScheduleWorkspaceView: View {
    @ObservedObject var model: ApplicationModel
    @ObservedObject private var schedule: ScheduleLibraryModel

    @State private var selectedTab: ScheduleTab = .week
    @State private var isShowingForm = false
    @State private var editingOccurrenceID: String?
    @State private var editingScope: ScheduleEditScope = .thisOccurrence
    @State private var isEditingPastDay = false
    @State private var isShowingMoreSettings = false
    @State private var draftTitle = ""
    /// The day selected in the weekly planner. It must not be derived from the
    /// time-only picker: macOS may substitute that picker's hidden date with
    /// the current day.
    @State private var draftDay = Date()
    @State private var draftStart = Date()
    @State private var draftDuration = 60
    @State private var draftRepeatRule: ScheduleRepeatRule = .none
    @State private var isShowingTimeAdjustment = false
    @State private var adjustmentStart = Date()
    @State private var adjustmentDuration = 60
    @State private var toast: Toast?
    @State private var deletedOneTimeOccurrence: ScheduleOccurrence?

    private let calendar: Calendar = {
        var value = Calendar.current
        // Product contract: the weekly planner always reads from Monday through Sunday.
        value.firstWeekday = 2
        return value
    }()

    init(model: ApplicationModel) {
        self.model = model
        _schedule = ObservedObject(wrappedValue: model.schedule)
    }

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 0) {
                header
                segmentedControl
                Divider().overlay(Color.white.opacity(0.1))

                ScrollView {
                    Group {
                        switch selectedTab {
                        case .week:
                            weekPlan
                        case .routine:
                            routinePlan
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 15)
                }
                .scrollIndicators(.visible)
            }

            if selectedTab == .week, let occurrence = runningOccurrence {
                runningOverlay(for: occurrence)
            } else if selectedTab == .week, let occurrence = overdueOccurrence {
                overdueOverlay(for: occurrence)
            } else if selectedTab == .week, let occurrence = awaitingOccurrence {
                awaitingStartOverlay(for: occurrence)
            }

            if let toast {
                toastView(toast)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(width: ExpandedIslandLayout.panelWidth, height: ExpandedIslandLayout.workspaceHeight)
        .foregroundStyle(.white)
        .background(panelBackground)
        .environment(\.colorScheme, .dark)
        .animation(.easeOut(duration: 0.16), value: selectedTab)
        .animation(.easeOut(duration: 0.16), value: isShowingForm)
        .sheet(isPresented: $isShowingTimeAdjustment) {
            timeAdjustmentSheet
        }
    }

    // MARK: - Header and navigation

    private var header: some View {
        HStack(spacing: 10) {
            Text("我的日程")
                .font(.system(size: 17, weight: .semibold))
            Spacer()
            if model.settings.isEnabled(.quickNotes) {
                Button {
                    model.showNotesWorkspace()
                } label: {
                    Label("便签", systemImage: "note.text")
                        .font(.system(size: 13.5, weight: .medium))
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(Color.white.opacity(0.055), in: Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("打开便签")
            }
            if model.settings.isEnabled(.codexFollowUp) {
                Button {
                    model.showActivityWorkspace()
                } label: {
                    Text("活动")
                        .font(.system(size: 13.5, weight: .medium))
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(Color.white.opacity(0.055), in: Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("打开活动")
            }

            Menu {
                Button("打开设置") { model.showSettings() }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .background(Color.white.opacity(0.055), in: Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.1), lineWidth: 1))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("日程菜单")

            QuitApplicationButton()
        }
        .padding(.horizontal, 18)
        .padding(.top, 15)
        .padding(.bottom, 12)
    }

    private var segmentedControl: some View {
        HStack(spacing: 6) {
            segmentButton(.week, title: "本周计划", icon: "calendar")
            segmentButton(.routine, title: "例行计划", icon: "arrow.triangle.2.circlepath")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
    }

    private func segmentButton(_ tab: ScheduleTab, title: String, icon: String) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            withAnimation(.easeOut(duration: 0.16)) { selectedTab = tab }
        } label: {
            Label(title, systemImage: icon)
                .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? Color.islandBlue : .white.opacity(0.66))
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(isSelected ? Color.islandBlue.opacity(0.13) : Color.white.opacity(0.035))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(isSelected ? Color.islandBlue.opacity(0.72) : Color.white.opacity(0.08), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Week plan

    private var weekPlan: some View {
        VStack(alignment: .leading, spacing: 0) {
            weekNavigator
                .padding(.bottom, 15)

            if isPastSelectedDate {
                historyHeader
            } else {
                upcomingHeader
            }

            if isShowingForm {
                scheduleForm
                    .padding(.top, 11)
                    .padding(.bottom, 5)
            }

            if dayOccurrences.isEmpty && !isShowingForm {
                emptyDayState
                    .padding(.vertical, 28)
            } else {
                scheduleRows
                    .padding(.top, 7)
            }

            if isPastSelectedDate {
                historyActions
                    .padding(.top, 13)
            } else if !isShowingForm {
                Button(action: beginAdding) {
                    Label("添加日程", systemImage: "plus")
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(Color.islandBlue)
                        .padding(.horizontal, 13)
                        .frame(height: 34)
                        .background(Color.islandBlue.opacity(0.1), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Color.islandBlue.opacity(0.34), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .padding(.top, 14)
                .accessibilityLabel("为所选日期添加日程")
            }
        }
    }

    private var weekNavigator: some View {
        HStack(spacing: 6) {
            Button(action: { moveWeek(by: -1) }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 40)
                    .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.7))
            .accessibilityLabel("上一周")

            HStack(spacing: 4) {
                ForEach(daysInSelectedWeek, id: \.self) { day in
                    dayButton(for: day)
                }
            }
            .frame(maxWidth: .infinity)

            Button(action: { moveWeek(by: 1) }) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 40)
                    .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.7))
            .accessibilityLabel("下一周")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("周选择器")
    }

    private func dayButton(for day: Date) -> some View {
        let isSelected = calendar.isDate(day, inSameDayAs: schedule.selectedDate)
        let isToday = calendar.isDateInToday(day)
        let occurrences = schedule.occurrences(on: day)
        let count = occurrences.count
        let hasAttention = occurrences.contains { [.awaitingStart, .overdueDecision, .running].contains($0.status) }

        return Button {
            select(day)
        } label: {
            VStack(spacing: 2) {
                Text(weekdayText(for: day))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isSelected ? Color.islandBlue : .white.opacity(0.48))
                Text("\(calendar.component(.day, from: day))")
                    .font(.system(size: 15, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.77))
                HStack(spacing: 3) {
                    if hasAttention {
                        Circle().fill(Color.islandBlue).frame(width: 4, height: 4)
                    } else if count > 0 {
                        Circle().fill(Color.white.opacity(0.38)).frame(width: 4, height: 4)
                    } else {
                        Color.clear.frame(width: 4, height: 4)
                    }
                    if isToday {
                        Text("今")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(Color.islandBlue)
                    } else if count > 0 {
                        Text("\(count)")
                            .font(.system(size: 8.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.42))
                    }
                }
                .frame(height: 10)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.islandBlue.opacity(0.13) : Color.white.opacity(0.025))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(isSelected ? Color.islandBlue.opacity(0.65) : Color.white.opacity(0.055), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(fullDateText(for: day))，\(count) 项日程")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var upcomingHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(calendar.isDateInToday(schedule.selectedDate) ? "下一件" : "当天安排")
                    .font(.system(size: 15, weight: .semibold))
                if let next = nextOccurrence {
                    Text(nextSummary(for: next))
                        .font(.system(size: 12.5))
                        .foregroundStyle(.white.opacity(0.48))
                } else {
                    Text("还没有安排")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.white.opacity(0.42))
                }
            }
            Spacer()
            if calendar.isDateInToday(schedule.selectedDate) {
                Text("今天")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Color.islandBlue)
            }
        }
    }

    private var historyHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("当天结果")
                    .font(.system(size: 15, weight: .semibold))
                Text("默认冻结显示，需要时可修正或补记")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.white.opacity(0.46))
            }
            Spacer()
            if isEditingPastDay {
                Text("编辑中")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Color.islandBlue)
            }
        }
    }

    private var emptyDayState: some View {
        VStack(spacing: 8) {
            Image(systemName: isPastSelectedDate ? "checklist" : "calendar.badge.plus")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.white.opacity(0.38))
            Text(isPastSelectedDate ? "当天没有日程记录" : "当天还没有安排")
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.52))
        }
        .frame(maxWidth: .infinity)
    }

    private var scheduleRows: some View {
        LazyVStack(spacing: 0) {
            ForEach(dayOccurrences) { occurrence in
                VStack(spacing: 0) {
                    occurrenceRow(occurrence)
                    if editingOccurrenceID == occurrence.id {
                        scheduleForm
                            .padding(.vertical, 10)
                    }
                    if occurrence.id != dayOccurrences.last?.id {
                        Divider().overlay(Color.white.opacity(0.085)).padding(.leading, 59)
                    }
                }
            }
        }
        .overlay(alignment: .top) { Divider().overlay(Color.white.opacity(0.1)) }
        .overlay(alignment: .bottom) { Divider().overlay(Color.white.opacity(0.1)) }
    }

    private func occurrenceRow(_ occurrence: ScheduleOccurrence) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(timeText(occurrence.plannedStart))
                    .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                Text("\(occurrence.plannedDurationMinutes + occurrence.extendedMinutes) 分钟 · 至 \(timeText(occurrence.expectedEnd))")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.38))
                    .lineLimit(1)
            }
            .frame(width: 103, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Text(occurrence.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.94))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    statusLabel(for: occurrence)
                    if occurrence.isCorrected {
                        Text("已修正")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.38))
                    }
                }
            }
            Spacer(minLength: 4)

            occurrenceMenu(occurrence)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(occurrence.title)，\(timeText(occurrence.plannedStart))，\(statusText(for: occurrence))")
    }

    private func occurrenceMenu(_ occurrence: ScheduleOccurrence) -> some View {
        Menu {
            if isPastSelectedDate {
                Button("修正项目") { beginEditing(occurrence, scope: .thisOccurrence) }
                if occurrence.templateID != nil {
                    Button("修改后续") { beginEditing(occurrence, scope: .followingOccurrences) }
                }
                Divider()
                if occurrence.status == .planned || occurrence.status == .awaitingStart {
                    Button("标记为跳过") { schedule.skip(occurrence.id) }
                    Button("取消本次", role: .destructive) { schedule.cancelThisOccurrence(occurrence.id) }
                }
            } else {
                if occurrence.status == .awaitingStart, occurrence.actualStart != nil {
                    Button("继续") { schedule.start(occurrence.id) }
                    Divider()
                }
                Button("编辑") { beginEditing(occurrence, scope: .thisOccurrence) }
                if occurrence.templateID != nil {
                    Button("修改后续") { beginEditing(occurrence, scope: .followingOccurrences) }
                }
                Divider()
                Button("删除本次", role: .destructive) { delete(occurrence, scope: .thisOccurrence) }
                if occurrence.templateID != nil {
                    Button("删除后续", role: .destructive) { delete(occurrence, scope: .followingOccurrences) }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.52))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("\(occurrence.title)的更多操作")
    }

    private var historyActions: some View {
        HStack(spacing: 9) {
            Button {
                isEditingPastDay.toggle()
                if !isEditingPastDay { cancelForm() }
            } label: {
                Label(isEditingPastDay ? "完成编辑" : "编辑当天", systemImage: isEditingPastDay ? "checkmark" : "pencil")
            }
            .buttonStyle(WorkspaceSecondaryButtonStyle())
            .accessibilityLabel(isEditingPastDay ? "完成编辑当天" : "编辑当天")

            Button {
                beginAdding()
            } label: {
                Label("补记事项", systemImage: "plus")
            }
            .buttonStyle(WorkspaceSecondaryButtonStyle(accented: true))
            .accessibilityLabel("补记事项")
        }
    }

    // MARK: - Add and edit form

    private var scheduleForm: some View {
        VStack(alignment: .leading, spacing: 11) {
            TextField("项目名称", text: $draftTitle, prompt: Text("例如：深度阅读"))
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.94))
                .padding(.horizontal, 11)
                .frame(height: 35)
                .background(Color.black.opacity(0.21), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.white.opacity(0.1), lineWidth: 1))
                .accessibilityLabel("项目名称")

            HStack(spacing: 9) {
                fieldLabel("开始时间")
                DatePicker("开始时间", selection: $draftStart, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .tint(Color.islandBlue)
                    .accessibilityLabel("开始时间")
                Spacer(minLength: 8)
                fieldLabel("持续时长")
                Stepper(value: $draftDuration, in: 5...600, step: 5) {
                    Text("\(draftDuration) 分钟")
                        .font(.system(size: 12.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.78))
                }
                .fixedSize()
                .accessibilityLabel("持续时长，\(draftDuration) 分钟")
            }

            Button {
                withAnimation(.easeOut(duration: 0.15)) { isShowingMoreSettings.toggle() }
            } label: {
                Label("更多设置", systemImage: isShowingMoreSettings ? "chevron.up" : "chevron.down")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.53))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isShowingMoreSettings ? "收起更多设置" : "展开更多设置")

            if isShowingMoreSettings {
                HStack {
                    Text("重复")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.white.opacity(0.52))
                    Spacer()
                    Picker("重复", selection: $draftRepeatRule) {
                        Text("仅这一次").tag(ScheduleRepeatRule.none)
                        Text("每周重复").tag(ScheduleRepeatRule.weekly)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .tint(.white.opacity(0.8))
                    .accessibilityLabel("重复规则")
                }
                .padding(.horizontal, 2)
            }

            if let conflictCount = conflictCount, conflictCount > 0 {
                Label("与当天 \(conflictCount) 项日程重叠，添加后会保留两项安排", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.islandAmber.opacity(0.92))
                    .accessibilityLabel("与 \(conflictCount) 项日程重叠，仍可保存")
            }

            HStack(spacing: 8) {
                Button("取消", action: cancelForm)
                    .buttonStyle(WorkspaceSecondaryButtonStyle())
                    .accessibilityLabel("取消编辑日程")
                Spacer()
                Button(editingOccurrenceID == nil ? "添加" : "保存", action: commitForm)
                    .buttonStyle(WorkspacePrimaryButtonStyle())
                    .disabled(draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel(editingOccurrenceID == nil ? "添加日程" : "保存日程")
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.037), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(Color.white.opacity(0.1), lineWidth: 1))
    }

    // MARK: - History, routines, and timer states

    private var routinePlan: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("例行计划")
                .font(.system(size: 15, weight: .semibold))
            Text("只在电脑唤醒且未锁屏时提醒")
                .font(.system(size: 12.5))
                .foregroundStyle(.white.opacity(0.46))
                .padding(.top, 3)
                .padding(.bottom, 11)

            LazyVStack(spacing: 0) {
                ForEach(schedule.snapshot.routines) { routine in
                    routineRow(routine)
                    if routine.id != schedule.snapshot.routines.last?.id {
                        Divider().overlay(Color.white.opacity(0.085)).padding(.leading, 44)
                    }
                }
            }
            .overlay(alignment: .top) { Divider().overlay(Color.white.opacity(0.1)) }
            .overlay(alignment: .bottom) { Divider().overlay(Color.white.opacity(0.1)) }

            Label("专注进行中时，会在结束后合并提醒一次。", systemImage: "speaker.wave.2")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.43))
                .padding(.top, 13)
        }
    }

    private func routineRow(_ routine: ScheduleRoutine) -> some View {
        HStack(spacing: 12) {
            Image(systemName: routine.kind.symbolName)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(routine.isEnabled ? Color.islandBlue : .white.opacity(0.4))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(routine.kind.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.93))
                Stepper(value: routineIntervalBinding(for: routine), in: 10...240, step: 5) {
                    Text("每 \(routine.intervalMinutes) 分钟")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.46))
                }
                .fixedSize()
                .disabled(!routine.isEnabled)
                .accessibilityLabel("\(routine.kind.title)间隔，\(routine.intervalMinutes) 分钟")
            }
            Spacer()
            Toggle(routine.kind.title, isOn: routineEnabledBinding(for: routine))
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(Color.islandBlue)
                .accessibilityLabel("\(routine.kind.title)提醒")
        }
        .padding(.vertical, 13)
    }

    private func awaitingStartOverlay(for occurrence: ScheduleOccurrence) -> some View {
        stateOverlay {
            Image(systemName: "bell.badge")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(Color.islandBlue)
            Text("该开始了")
                .font(.system(size: 18, weight: .semibold))
            Text(occurrence.title)
                .font(.system(size: 14.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.78))
            Text("计划于 \(timeText(occurrence.plannedStart)) 开始 · \(occurrence.plannedDurationMinutes) 分钟")
                .font(.system(size: 12.5))
                .foregroundStyle(.white.opacity(0.47))
            HStack(spacing: 9) {
                Button("现在开始") { schedule.start(occurrence.id) }
                    .buttonStyle(WorkspacePrimaryButtonStyle())
                    .accessibilityLabel("现在开始\(occurrence.title)")
                Button("延后 10 分钟") { schedule.postpone(occurrence.id) }
                    .buttonStyle(WorkspaceSecondaryButtonStyle())
                    .accessibilityLabel("延后\(occurrence.title)十分钟")
            }
        }
    }

    private func overdueOverlay(for occurrence: ScheduleOccurrence) -> some View {
        stateOverlay {
            Image(systemName: "clock.badge.exclamationmark")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(Color.islandAmber)
            Text("计划还没开始")
                .font(.system(size: 18, weight: .semibold))
            Text(occurrence.title)
                .font(.system(size: 14.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.78))
            Text("现在开始会从此刻完整计入 \(occurrence.plannedDurationMinutes) 分钟")
                .font(.system(size: 12.5))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.47))
                .frame(maxWidth: 350)
            HStack(spacing: 8) {
                Button("现在开始") { schedule.start(occurrence.id) }
                    .buttonStyle(WorkspacePrimaryButtonStyle())
                    .accessibilityLabel("现在开始\(occurrence.title)")
                Button("延后 10 分钟") { schedule.postpone(occurrence.id) }
                    .buttonStyle(WorkspaceSecondaryButtonStyle())
                    .accessibilityLabel("延后\(occurrence.title)十分钟")
            }
            HStack(spacing: 8) {
                Button("调整时间") {
                    adjustmentStart = occurrence.plannedStart
                    adjustmentDuration = occurrence.plannedDurationMinutes
                    editingOccurrenceID = occurrence.id
                    isShowingTimeAdjustment = true
                }
                .buttonStyle(WorkspaceSecondaryButtonStyle())
                .accessibilityLabel("调整\(occurrence.title)时间")
                Button("取消本次") { schedule.cancelThisOccurrence(occurrence.id) }
                    .buttonStyle(WorkspaceDestructiveButtonStyle())
                    .accessibilityLabel("取消\(occurrence.title)本次")
            }
        }
    }

    private func runningOverlay(for occurrence: ScheduleOccurrence) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            stateOverlay {
                Text("进行中")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.islandBlue)
                Text(occurrence.title)
                    .font(.system(size: 20, weight: .semibold))
                    .lineLimit(1)
                Text(remainingTimeText(for: occurrence, at: context.date))
                    .font(.system(size: 42, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.95))
                Text("实际开始 \(timeText(occurrence.actualStart ?? context.date)) · 预计结束 \(timeText(occurrence.expectedEnd))")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.white.opacity(0.47))
                HStack(spacing: 8) {
                    Button("完成") { schedule.complete(occurrence.id) }
                        .buttonStyle(WorkspacePrimaryButtonStyle())
                        .accessibilityLabel("完成\(occurrence.title)")
                    Button("延长 10 分钟") { schedule.extend(occurrence.id) }
                        .buttonStyle(WorkspaceSecondaryButtonStyle())
                        .accessibilityLabel("延长\(occurrence.title)十分钟")
                    Button("稍后处理") { schedule.defer(occurrence.id) }
                        .buttonStyle(WorkspaceSecondaryButtonStyle())
                        .accessibilityLabel("稍后处理\(occurrence.title)")
                }
            }
        }
    }

    private func stateOverlay<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 9, content: content)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 22)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(red: 0.045, green: 0.052, blue: 0.058).opacity(0.985))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.white.opacity(0.19), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .transition(.opacity)
    }

    private var timeAdjustmentSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("调整时间")
                .font(.system(size: 18, weight: .semibold))
            DatePicker("开始时间", selection: $adjustmentStart, displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.compact)
            Stepper(value: $adjustmentDuration, in: 5...600, step: 5) {
                Text("持续时长：\(adjustmentDuration) 分钟")
            }
            HStack {
                Spacer()
                Button("取消") { isShowingTimeAdjustment = false }
                Button("保存") {
                    if let editingOccurrenceID {
                        schedule.reschedule(editingOccurrenceID, to: adjustmentStart, durationMinutes: adjustmentDuration)
                    }
                    editingOccurrenceID = nil
                    isShowingTimeAdjustment = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(22)
        .frame(width: 320)
        .environment(\.colorScheme, .dark)
    }

    // MARK: - Bindings and actions

    private func routineEnabledBinding(for routine: ScheduleRoutine) -> Binding<Bool> {
        Binding(
            get: { routine.isEnabled },
            set: { schedule.updateRoutine(routine.kind, isEnabled: $0) }
        )
    }

    private func routineIntervalBinding(for routine: ScheduleRoutine) -> Binding<Int> {
        Binding(
            get: { routine.intervalMinutes },
            set: { schedule.updateRoutine(routine.kind, intervalMinutes: $0) }
        )
    }

    private func select(_ day: Date) {
        withAnimation(.easeOut(duration: 0.14)) {
            schedule.selectedDate = calendar.startOfDay(for: day)
            cancelForm()
            isEditingPastDay = false
        }
    }

    private func moveWeek(by offset: Int) {
        guard let moved = calendar.date(byAdding: .weekOfYear, value: offset, to: schedule.selectedDate) else { return }
        select(moved)
    }

    private func beginAdding() {
        editingOccurrenceID = nil
        editingScope = .thisOccurrence
        draftTitle = ""
        draftDay = calendar.startOfDay(for: schedule.selectedDate)
        draftStart = date(on: draftDay, hour: 9, minute: 0)
        draftDuration = 60
        draftRepeatRule = .none
        isShowingMoreSettings = false
        withAnimation(.easeOut(duration: 0.16)) { isShowingForm = true }
    }

    private func beginEditing(_ occurrence: ScheduleOccurrence, scope: ScheduleEditScope) {
        editingOccurrenceID = occurrence.id
        editingScope = scope
        draftTitle = occurrence.title
        draftDay = calendar.startOfDay(for: occurrence.plannedStart)
        draftStart = occurrence.plannedStart
        draftDuration = occurrence.plannedDurationMinutes
        draftRepeatRule = occurrence.templateID == nil ? .none : .weekly
        isShowingMoreSettings = false
        withAnimation(.easeOut(duration: 0.16)) { isShowingForm = false }
    }

    private func commitForm() {
        let title = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let plannedStart = ScheduleDateTime.combining(day: draftDay, time: draftStart, calendar: calendar)
        if let editingOccurrenceID {
            _ = schedule.update(
                editingOccurrenceID,
                title: title,
                plannedStart: plannedStart,
                durationMinutes: draftDuration,
                repeatRule: isShowingMoreSettings ? draftRepeatRule : nil,
                scope: editingScope
            )
            showToast("已保存修改", icon: "checkmark")
        } else {
            _ = schedule.add(
                title: title,
                plannedStart: plannedStart,
                durationMinutes: draftDuration,
                repeatRule: isShowingMoreSettings ? draftRepeatRule : .none
            )
            showToast("已添加日程", icon: "checkmark")
        }
        cancelForm()
    }

    private func cancelForm() {
        isShowingForm = false
        editingOccurrenceID = nil
        editingScope = .thisOccurrence
        isShowingMoreSettings = false
    }

    private func delete(_ occurrence: ScheduleOccurrence, scope: ScheduleEditScope) {
        schedule.delete(occurrence.id, scope: scope)
        let message = scope == .followingOccurrences ? "已删除后续日程" : "已删除日程"
        if scope == .thisOccurrence, occurrence.templateID == nil {
            deletedOneTimeOccurrence = occurrence
            showToast(message, icon: "trash", actionTitle: "撤销")
        } else {
            deletedOneTimeOccurrence = nil
            showToast(message, icon: "trash")
        }
    }

    private func restoreDeletedOccurrence() {
        guard let occurrence = deletedOneTimeOccurrence else { return }
        _ = schedule.add(
            title: occurrence.title,
            plannedStart: occurrence.plannedStart,
            durationMinutes: occurrence.plannedDurationMinutes,
            repeatRule: .none
        )
        deletedOneTimeOccurrence = nil
        withAnimation(.easeOut(duration: 0.16)) { toast = nil }
    }

    private func showToast(_ message: String, icon: String, actionTitle: String? = nil) {
        let newToast = Toast(message: message, icon: icon, actionTitle: actionTitle)
        withAnimation(.easeOut(duration: 0.16)) { toast = newToast }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
            guard toast?.id == newToast.id else { return }
            deletedOneTimeOccurrence = nil
            withAnimation(.easeIn(duration: 0.16)) { toast = nil }
        }
    }

    // MARK: - Derived values and formatting

    private var dayOccurrences: [ScheduleOccurrence] {
        schedule.occurrences(on: schedule.selectedDate)
    }

    private var nextOccurrence: ScheduleOccurrence? {
        let now = Date()
        return dayOccurrences.first { occurrence in
            occurrence.status == .planned && occurrence.plannedStart >= now
        } ?? dayOccurrences.first { $0.status == .planned }
    }

    private var runningOccurrence: ScheduleOccurrence? {
        schedule.occurrences(on: Date()).first { $0.status == .running }
    }

    private var overdueOccurrence: ScheduleOccurrence? {
        schedule.occurrences(on: Date()).first { $0.status == .overdueDecision }
    }

    private var awaitingOccurrence: ScheduleOccurrence? {
        schedule.occurrences(on: Date()).first {
            $0.status == .awaitingStart && $0.actualStart == nil
        }
    }

    private var isPastSelectedDate: Bool {
        calendar.startOfDay(for: schedule.selectedDate) < calendar.startOfDay(for: Date())
    }

    private var daysInSelectedWeek: [Date] {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: schedule.selectedDate) else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: interval.start) }
    }

    private var conflictCount: Int? {
        let start = ScheduleDateTime.combining(day: draftDay, time: draftStart, calendar: calendar)
        let end = start.addingTimeInterval(TimeInterval(draftDuration * 60))
        let matchingDay = schedule.occurrences(on: start)
        let count = matchingDay.filter { occurrence in
            guard occurrence.id != editingOccurrenceID else { return false }
            return start < occurrence.expectedEnd && end > occurrence.plannedStart
        }.count
        return count
    }

    private func statusLabel(for occurrence: ScheduleOccurrence) -> some View {
        Text(statusText(for: occurrence))
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(statusColor(for: occurrence))
    }

    private func statusText(for occurrence: ScheduleOccurrence) -> String {
        if isPastSelectedDate && occurrence.status == .planned { return "未开始" }
        switch occurrence.status {
        case .planned: return "已计划"
        case .awaitingStart: return occurrence.actualStart == nil ? "待开始" : "待继续"
        case .overdueDecision: return "需要决定"
        case .running: return "进行中"
        case .completed:
            return "已完成 · 实际 \(occurrence.actualDurationMinutes()) 分钟"
        case .skipped: return "已跳过"
        case .cancelled: return "已取消"
        }
    }

    private func statusColor(for occurrence: ScheduleOccurrence) -> Color {
        switch occurrence.status {
        case .awaitingStart, .running: return .islandBlue
        case .overdueDecision: return .islandAmber
        case .completed: return .islandGreen
        case .skipped, .cancelled: return .white.opacity(0.45)
        case .planned: return .white.opacity(0.48)
        }
    }

    private func nextSummary(for occurrence: ScheduleOccurrence) -> String {
        "\(timeText(occurrence.plannedStart)) · \(occurrence.title) · \(occurrence.plannedDurationMinutes) 分钟"
    }

    private func remainingTimeText(for occurrence: ScheduleOccurrence, at date: Date) -> String {
        let seconds = max(0, Int(occurrence.remainingSeconds(at: date).rounded(.down)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private func weekdayText(for date: Date) -> String {
        let index = calendar.component(.weekday, from: date) - 1
        return ["日", "一", "二", "三", "四", "五", "六"][max(0, min(index, 6))]
    }

    private func timeText(_ date: Date) -> String {
        Self.timeFormatter.string(from: date)
    }

    private func fullDateText(for date: Date) -> String {
        Self.dateFormatter.string(from: date)
    }

    private func date(on day: Date, hour: Int, minute: Int) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components) ?? day
    }

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(Color(red: 0.055, green: 0.065, blue: 0.07).opacity(0.99))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.white.opacity(0.2), lineWidth: 1))
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11.5))
            .foregroundStyle(.white.opacity(0.48))
    }

    private func toastView(_ toast: Toast) -> some View {
        HStack(spacing: 9) {
            Label(toast.message, systemImage: toast.icon)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
            if toast.actionTitle != nil, deletedOneTimeOccurrence != nil {
                Button("撤销", action: restoreDeletedOccurrence)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Color.islandBlue)
                    .buttonStyle(.plain)
                    .accessibilityLabel("撤销删除日程")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(Color.black.opacity(0.82), in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
        .frame(maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 14)
        .accessibilityLabel(toast.message)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "M月d日 EEEE"
        return formatter
    }()
}

private extension ScheduleWorkspaceView {
    enum ScheduleTab {
        case week
        case routine
    }

    struct Toast: Identifiable, Equatable {
        let id = UUID()
        let message: String
        let icon: String
        let actionTitle: String?
    }
}

private extension ScheduleRoutineKind {
    var title: String {
        switch self {
        case .hydration: return "喝水"
        case .activity: return "起身活动"
        }
    }

    var symbolName: String {
        switch self {
        case .hydration: return "drop"
        case .activity: return "figure.stand"
        }
    }
}

private struct WorkspacePrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(Color.islandBlue.opacity(configuration.isPressed ? 0.68 : 0.88), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

private struct WorkspaceSecondaryButtonStyle: ButtonStyle {
    var accented = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(accented ? Color.islandBlue : .white.opacity(0.76))
            .padding(.horizontal, 11)
            .frame(height: 32)
            .background(
                (accented ? Color.islandBlue.opacity(0.1) : Color.white.opacity(0.065)),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(accented ? Color.islandBlue.opacity(0.36) : Color.white.opacity(0.11), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}

private struct WorkspaceDestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(Color.islandAmber.opacity(0.94))
            .padding(.horizontal, 11)
            .frame(height: 32)
            .background(Color.islandAmber.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.islandAmber.opacity(0.28), lineWidth: 1))
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}
