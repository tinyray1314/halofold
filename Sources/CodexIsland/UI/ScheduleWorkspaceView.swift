import SwiftUI

/// The expandable, local-only schedule workspace. Its detailed state lives in
/// `ScheduleLibraryModel`; this view keeps only temporary editing presentation
/// state so plans survive closing the panel or restarting Halofold.
@MainActor
struct ScheduleWorkspaceView: View {
    @ObservedObject var model: ApplicationModel
    @ObservedObject private var schedule: ScheduleLibraryModel

    @FocusState private var focusedTitle: Bool
    @State private var selectedTab: ScheduleTab = .week
    @State private var isShowingForm = false
    @State private var editingOccurrenceID: String?
    @State private var editingScope: ScheduleEditScope = .thisOccurrence
    @State private var isEditingRepeatedOccurrence = false
    @State private var isEditingPastDay = false
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
    @State private var isShowingRoutineEditor = false
    @State private var editingRoutineID: UUID?
    @State private var routineDraftTitle = ""
    @State private var routineDraftStyle: ScheduleRoutineReminderStyle = .interval
    @State private var routineDraftInterval = 60
    @State private var routineDraftTime = Date()
    @State private var toast: Toast?
    @State private var pendingSeriesDeletion: ScheduleOccurrence?

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
                segmentedControl
                Divider().overlay(Color.white.opacity(0.1))

                ScrollViewReader { proxy in
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
                    .onChange(of: isShowingForm) { _, showing in
                        if showing { revealEditor(proxy) }
                    }
                    .onChange(of: editingOccurrenceID) { _, id in
                        if id != nil { revealEditor(proxy) }
                    }
                    .onChange(of: isShowingRoutineEditor) { _, showing in
                        if showing { revealEditor(proxy) }
                    }
                    .onChange(of: editingRoutineID) { _, id in
                        if id != nil { revealEditor(proxy) }
                    }
                }
            }
            .disabled(isPresentingStateOverlay)
            .allowsHitTesting(!isPresentingStateOverlay)
            .accessibilityElement(children: .contain)
            .accessibilityHidden(isPresentingStateOverlay)

            if selectedTab == .week, model.isShowingFocusDetail, let occurrence = runningOccurrence {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.white)

        .environment(\.colorScheme, .dark)
        .onChange(of: model.isShowingFocusDetail) { _, showing in
            if showing { selectedTab = .week }
        }
        .animation(.easeOut(duration: 0.16), value: selectedTab)
        .animation(.easeOut(duration: 0.16), value: isShowingForm)
        .alert("删除本次及后续重复日程？", isPresented: Binding(
            get: { pendingSeriesDeletion != nil },
            set: { if !$0 { pendingSeriesDeletion = nil } }
        )) {
            Button("取消", role: .cancel) { pendingSeriesDeletion = nil }
            Button("删除后续", role: .destructive) {
                if let item = pendingSeriesDeletion { schedule.delete(item.id, scope: .followingOccurrences) }
                pendingSeriesDeletion = nil
            }
        } message: {
            if let item = pendingSeriesDeletion {
                Text("将删除「\(item.title)」从\(item.plannedStart.formatted(date: .abbreviated, time: .omitted))起的重复安排，之前的记录保留。")
            }
        }
        .sheet(isPresented: $isShowingTimeAdjustment) {
            timeAdjustmentSheet.preferredColorScheme(.dark)
        }
    }

    // MARK: - Header and navigation

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
            if tab == .routine { model.isShowingFocusDetail = false }
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
            HStack {
                Text(schedule.selectedDate.formatted(.dateTime.year().month().day()))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.65))
                Spacer()
                Button("今天") { select(Date()) }
                    .buttonStyle(.plain).foregroundStyle(Color.islandBlue)
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.bottom, 9)
            weekNavigator
                .padding(.bottom, 15)

            if isPastSelectedDate {
                historyHeader
            } else {
                upcomingHeader
            }

            if isShowingForm || editingOccurrenceID != nil {
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
            } else if !isShowingForm && editingOccurrenceID == nil {
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
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
            }
            .frame(width: 115, alignment: .leading)

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
            Text("\(editingOccurrenceID == nil ? "添加日程" : "编辑日程") · \(draftDay.formatted(.dateTime.month().day()))")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.65))
            TextField("项目名称", text: $draftTitle, prompt: Text("例如：深度阅读"))
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.94))
                .padding(.horizontal, 11)
                .frame(height: 35)
                .background(Color.black.opacity(0.21), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.white.opacity(0.1), lineWidth: 1))
                .accessibilityLabel("项目名称")
                .focused($focusedTitle)

            HStack(spacing: 9) {
                fieldLabel("开始时间")
                DatePicker("开始时间", selection: $draftStart, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .tint(Color.islandBlue)
                    .accessibilityLabel("开始时间")
                Spacer(minLength: 8)
                fieldLabel("持续时长")
                TextField("分钟", value: $draftDuration, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 48)
                    .accessibilityLabel("持续分钟数")
                Stepper(value: $draftDuration, in: 5...600, step: 5) {
                    Text("分钟")
                        .font(.system(size: 12.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.78))
                }
                .fixedSize()
                .accessibilityLabel("持续时长，\(draftDuration) 分钟")
            }

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
                    .disabled(editingOccurrenceID != nil && isEditingRepeatedOccurrence && editingScope == .thisOccurrence)
                }
                .padding(.horizontal, 2)
            if editingOccurrenceID != nil && isEditingRepeatedOccurrence && editingScope == .thisOccurrence {
                Text("正在修改本次安排；要调整重复规则，请在菜单中选择“修改后续”。")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.65))
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
        .id("schedule-editor")
        .padding(12)
        .background(Color.white.opacity(0.037), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(Color.white.opacity(0.1), lineWidth: 1))
    }

    // MARK: - History, routines, and timer states

    private var routinePlan: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("例行计划")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button(action: beginAddingRoutine) {
                    Label("添加事项", systemImage: "plus")
                }
                .buttonStyle(WorkspaceSecondaryButtonStyle(accented: true))
                .accessibilityLabel("添加例行事项")
            }
            Text("只在电脑唤醒且未锁屏时提醒")
                .font(.system(size: 12.5))
                .foregroundStyle(.white.opacity(0.46))
                .padding(.top, 3)
                .padding(.bottom, 11)

            if isShowingRoutineEditor {
                routineEditor
                    .id("schedule-editor")
                    .padding(.bottom, 12)
            }
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
                Text(routine.displayTitle)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.93))
                if routine.kind != .custom, routine.reminderStyle == .interval {
                    Stepper(value: routineIntervalBinding(for: routine), in: 10...240, step: 5) {
                        Text("每 \(routine.intervalMinutes) 分钟")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.white.opacity(0.46))
                    }
                    .fixedSize()
                    .disabled(!routine.isEnabled)
                    .accessibilityLabel("\(routine.displayTitle)间隔，\(routine.intervalMinutes) 分钟")
                } else {
                    Text(routineScheduleText(routine))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.46))
                }
            }
            Spacer()
            if routine.kind == .custom {
                Menu {
                    Button("编辑") { beginEditingRoutine(routine) }
                    Divider()
                    Button("删除", role: .destructive) {
                        if let restore = schedule.deleteRoutineWithUndo(routine.id) {
                            model.offerUndo("已删除例行事项", restore: restore)
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(routine.displayTitle)更多操作")
            }
            Toggle(routine.displayTitle, isOn: routineEnabledBinding(for: routine))
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(Color.islandBlue)
                .accessibilityLabel("\(routine.displayTitle)提醒")
        }
        .padding(.vertical, 13)
    }

    private var routineEditor: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(editingRoutineID == nil ? "添加例行事项" : "编辑例行事项")
                .font(.system(size: 13.5, weight: .semibold))
            TextField("例如：点外卖", text: $routineDraftTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .padding(.horizontal, 11)
                .frame(height: 36)
                .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.white.opacity(0.1), lineWidth: 1))
                .accessibilityLabel("例行事项名称")

            Picker("提醒方式", selection: $routineDraftStyle) {
                Text("间隔提醒").tag(ScheduleRoutineReminderStyle.interval)
                Text("每日定时").tag(ScheduleRoutineReminderStyle.dailyTime)
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("例行提醒方式")

            HStack(spacing: 9) {
                if routineDraftStyle == .interval {
                    fieldLabel("提醒间隔")
                    Stepper(value: $routineDraftInterval, in: 5...720, step: 5) {
                        Text("每 \(routineDraftInterval) 分钟")
                            .font(.system(size: 13.5, weight: .medium))
                    }
                    .fixedSize()
                    .accessibilityLabel("每\(routineDraftInterval)分钟提醒")
                } else {
                    fieldLabel("每天提醒")
                    DatePicker("每天提醒", selection: $routineDraftTime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .tint(Color.islandBlue)
                        .accessibilityLabel("每日定时提醒时间")
                }
                Spacer()
            }

            HStack(spacing: 8) {
                Button("取消", action: cancelRoutineEditor)
                    .buttonStyle(WorkspaceSecondaryButtonStyle())
                Spacer()
                Button(editingRoutineID == nil ? "添加" : "保存", action: commitRoutineEditor)
                    .buttonStyle(WorkspacePrimaryButtonStyle())
                    .disabled(routineDraftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel(editingRoutineID == nil ? "添加例行事项" : "保存例行事项")
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.037), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(Color.white.opacity(0.1), lineWidth: 1))
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
                Button("返回日程列表") { model.isShowingFocusDetail = false }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.islandBlue)
                    .padding(.bottom, 4)
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
            .background(Color(red: 0.045, green: 0.052, blue: 0.058))
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
            set: { isEnabled in
                if routine.kind == .custom {
                    _ = schedule.updateCustomRoutine(
                        routine.id,
                        title: routine.displayTitle,
                        reminderStyle: routine.reminderStyle,
                        intervalMinutes: routine.intervalMinutes,
                        dailyTimeMinutes: routine.dailyTimeMinutes,
                        isEnabled: isEnabled
                    )
                } else {
                    schedule.updateRoutine(routine.kind, isEnabled: isEnabled)
                }
            }
        )
    }

    private func routineIntervalBinding(for routine: ScheduleRoutine) -> Binding<Int> {
        Binding(
            get: { routine.intervalMinutes },
            set: { schedule.updateRoutine(routine.kind, intervalMinutes: $0) }
        )
    }

    private func beginAddingRoutine() {
        editingRoutineID = nil
        routineDraftTitle = ""
        routineDraftStyle = .interval
        routineDraftInterval = 60
        routineDraftTime = date(on: Date(), hour: 9, minute: 0)
        withAnimation(.easeOut(duration: 0.16)) { isShowingRoutineEditor = true }
    }

    private func beginEditingRoutine(_ routine: ScheduleRoutine) {
        editingRoutineID = routine.id
        routineDraftTitle = routine.displayTitle
        routineDraftStyle = routine.reminderStyle
        routineDraftInterval = routine.intervalMinutes
        let minutes = routine.dailyTimeMinutes ?? (9 * 60)
        routineDraftTime = date(on: Date(), hour: minutes / 60, minute: minutes % 60)
        withAnimation(.easeOut(duration: 0.16)) { isShowingRoutineEditor = true }
    }

    private func commitRoutineEditor() {
        let title = routineDraftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let dailyTimeMinutes = routineDraftStyle == .dailyTime ? minutesAfterMidnight(routineDraftTime) : nil
        if let editingRoutineID {
            _ = schedule.updateCustomRoutine(
                editingRoutineID,
                title: title,
                reminderStyle: routineDraftStyle,
                intervalMinutes: routineDraftInterval,
                dailyTimeMinutes: dailyTimeMinutes
            )
            showToast("已保存例行事项", icon: "checkmark")
        } else if schedule.addCustomRoutine(
            title: title,
            reminderStyle: routineDraftStyle,
            intervalMinutes: routineDraftInterval,
            dailyTimeMinutes: dailyTimeMinutes
        ) != nil {
            showToast("已添加例行事项", icon: "checkmark")
        }
        cancelRoutineEditor()
    }

    private func cancelRoutineEditor() {
        editingRoutineID = nil
        withAnimation(.easeOut(duration: 0.16)) { isShowingRoutineEditor = false }
    }

    private func select(_ day: Date) {
        withAnimation(.easeOut(duration: 0.14)) {
            schedule.selectedDate = calendar.startOfDay(for: day)
            if isShowingForm {
                draftDay = calendar.startOfDay(for: day)
                draftStart = ScheduleDateTime.combining(day: draftDay, time: draftStart, calendar: calendar)
            }
            isEditingPastDay = false
        }
    }

    private func moveWeek(by offset: Int) {
        guard let moved = calendar.date(byAdding: .weekOfYear, value: offset, to: schedule.selectedDate) else { return }
        select(moved)
    }

    private func revealEditor(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.16)) { proxy.scrollTo("schedule-editor", anchor: .top) }
            if selectedTab == .week { focusedTitle = true }
        }
    }

    private func beginAdding() {
        editingOccurrenceID = nil
        editingScope = .thisOccurrence
        isEditingRepeatedOccurrence = false
        draftTitle = ""
        draftStart = ScheduleDateTime.suggestedStart(on: schedule.selectedDate, calendar: calendar)
        draftDay = calendar.startOfDay(for: draftStart)
        draftDuration = 60
        draftRepeatRule = .none
        withAnimation(.easeOut(duration: 0.16)) { isShowingForm = true }
    }

    private func beginEditing(_ occurrence: ScheduleOccurrence, scope: ScheduleEditScope) {
        editingOccurrenceID = occurrence.id
        editingScope = scope
        isEditingRepeatedOccurrence = occurrence.templateID != nil
        draftTitle = occurrence.title
        draftDay = calendar.startOfDay(for: occurrence.plannedStart)
        draftStart = occurrence.plannedStart
        draftDuration = occurrence.plannedDurationMinutes
        draftRepeatRule = occurrence.templateID == nil ? .none : .weekly
        withAnimation(.easeOut(duration: 0.16)) { isShowingForm = false }
    }

    private func commitForm() {
        let title = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        draftDuration = min(600, max(5, draftDuration))
        let plannedStart = ScheduleDateTime.combining(day: draftDay, time: draftStart, calendar: calendar)
        if let editingOccurrenceID {
            _ = schedule.update(
                editingOccurrenceID,
                title: title,
                plannedStart: plannedStart,
                durationMinutes: draftDuration,
                repeatRule: draftRepeatRule,
                scope: editingScope
            )
            showToast("已保存修改", icon: "checkmark")
        } else {
            _ = schedule.add(
                title: title,
                plannedStart: plannedStart,
                durationMinutes: draftDuration,
                repeatRule: draftRepeatRule
            )
            showToast("已添加日程", icon: "checkmark")
        }
        cancelForm()
    }

    private func cancelForm() {
        isShowingForm = false
        editingOccurrenceID = nil
        editingScope = .thisOccurrence
    }

    private func delete(_ occurrence: ScheduleOccurrence, scope: ScheduleEditScope) {
        if scope == .followingOccurrences {
            pendingSeriesDeletion = occurrence
        } else if let restore = schedule.deleteOccurrenceWithUndo(occurrence.id) {
            model.offerUndo("已删除日程", restore: restore)
        }
    }

    private func showToast(_ message: String, icon: String, actionTitle: String? = nil) {
        let newToast = Toast(message: message, icon: icon, actionTitle: actionTitle)
        withAnimation(.easeOut(duration: 0.16)) { toast = newToast }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
            guard toast?.id == newToast.id else { return }
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

    private var isPresentingStateOverlay: Bool {
        selectedTab == .week && ((model.isShowingFocusDetail && runningOccurrence != nil)
            || overdueOccurrence != nil || awaitingOccurrence != nil)
    }

    private var runningOccurrence: ScheduleOccurrence? {
        schedule.snapshot.occurrences.first { !$0.isDeleted && $0.status == .running }
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
        case .planned: return .white.opacity(0.62)
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

    private func routineScheduleText(_ routine: ScheduleRoutine) -> String {
        switch routine.reminderStyle {
        case .interval:
            return "每 \(routine.intervalMinutes) 分钟"
        case .dailyTime:
            let minutes = routine.dailyTimeMinutes ?? (9 * 60)
            return "每天 \(String(format: "%02d:%02d", minutes / 60, minutes % 60))"
        }
    }

    private func minutesAfterMidnight(_ date: Date) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
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

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(0.65))
    }

    private func toastView(_ toast: Toast) -> some View {
        HStack(spacing: 9) {
            Label(toast.message, systemImage: toast.icon)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))

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
        case .custom: return "自定义提醒"
        }
    }

    var symbolName: String {
        switch self {
        case .hydration: return "drop"
        case .activity: return "figure.stand"
        case .custom: return "bell"
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
