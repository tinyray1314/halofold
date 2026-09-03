import SwiftUI

struct NotesWorkspaceView: View {
    @ObservedObject var model: ApplicationModel
    @ObservedObject var notes: NoteLibraryModel
    @FocusState private var titleFocused: Bool
    @State private var editorCommand: RichTextCommand?
    @State private var editorFocusRequestID: UUID?
#if !HALOFOLD_NO_CODEX_TODO
    @State private var isDiscoveringTodos = false
    @State private var isShowingTodoReview = false
    @State private var todoCandidates: [CodexTodoCandidate] = []
    @State private var selectedTodoIDs: Set<String> = []
    @State private var todoDiscoveryMessage: String?
    private let todoImportStore = CodexTodoImportStore()
#endif

    init(model: ApplicationModel) {
        self.model = model
        _notes = ObservedObject(wrappedValue: model.notes)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            noteTabs
            Divider().overlay(Color.white.opacity(0.1))

            if let note = notes.selectedNote {
                editor(for: note)
                    .id(note.id)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .frame(width: ExpandedIslandLayout.panelWidth, height: ExpandedIslandLayout.workspaceHeight)
        .foregroundStyle(.white)
        .background(panelBackground)
        .environment(\.colorScheme, .dark)
        .animation(.easeOut(duration: 0.16), value: notes.selectedNoteID)
        .onReceive(NotificationCenter.default.publisher(for: .focusNewNoteTitle)) { _ in
            titleFocused = true
        }
#if !HALOFOLD_NO_CODEX_TODO
        .sheet(isPresented: $isShowingTodoReview) {
            CodexTodoReviewView(
                candidates: todoCandidates,
                selectedIDs: $selectedTodoIDs,
                message: todoDiscoveryMessage,
                onCancel: { isShowingTodoReview = false },
                onImport: importSelectedTodos
            )
        }
#endif
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text(AppLocalization.text("便签"))
                .font(.system(size: 17, weight: .semibold))
            Spacer()
#if !HALOFOLD_NO_CODEX_TODO
            Button(action: discoverTodos) {
                HStack(spacing: 6) {
                    if isDiscoveringTodos {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "sparkles")
                    }
                    Text(AppLocalization.text("发现待办"))
                }
                .font(.system(size: 12.5, weight: .medium))
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(Color.islandBlue.opacity(0.11), in: Capsule())
                .overlay(Capsule().stroke(Color.islandBlue.opacity(0.38), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(isDiscoveringTodos)
            .help(AppLocalization.text("从最近 Codex 对话中提取待办候选"))
#endif

            if model.settings.isEnabled(.schedule) {
                Button {
                    model.showScheduleWorkspace()
                } label: {
                    Label(AppLocalization.text("日程"), systemImage: "clock")
                        .font(.system(size: 13.5, weight: .medium))
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(Color.islandBlue.opacity(0.1), in: Capsule())
                        .overlay(Capsule().stroke(Color.islandBlue.opacity(0.28), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.islandBlue)
                .accessibilityLabel(AppLocalization.text("打开我的日程"))
            }

            if model.settings.isEnabled(.codexFollowUp) {
                Button {
                    model.showActivityWorkspace()
                } label: {
                    HStack(spacing: 7) {
                        Text(AppLocalization.text("活动"))
                        if activityCount > 0 {
                            Text("\(activityCount)")
                                .font(.system(size: 10.5, weight: .semibold))
                                .padding(.horizontal, 7)
                                .frame(height: 20)
                                .background(Color.white.opacity(0.11), in: Capsule())
                        }
                    }
                    .font(.system(size: 13.5, weight: .medium))
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(Color.white.opacity(0.055), in: Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AppLocalization.format("打开活动，共 %lld 项", Int64(activityCount)))
            }

            Menu {
                Button(AppLocalization.text("删除当前便签"), role: .destructive) {
                    if let id = notes.selectedNoteID { notes.delete(id) }
                }
                Divider()
                Button(AppLocalization.text("打开设置")) { model.showSettings() }
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
            .accessibilityLabel(AppLocalization.text("便签菜单"))

            QuitApplicationButton()
        }
        .padding(.horizontal, 18)
        .padding(.top, 15)
        .padding(.bottom, 12)
    }

    private var noteTabs: some View {
        HStack(spacing: 9) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(notes.notes) { note in
                        noteTab(note)
                    }
                }
                .padding(.vertical, 1)
            }
            Button(action: createNote) {
                Label(AppLocalization.text("新建"), systemImage: "plus")
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .background(Color.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Color.white.opacity(0.11), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .keyboardShortcut("n", modifiers: [.command, .shift])
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 13)
    }

    private func noteTab(_ note: NoteDocument) -> some View {
        let selected = notes.selectedNoteID == note.id
        return Button {
            withAnimation(.easeOut(duration: 0.16)) { notes.select(note) }
        } label: {
            HStack(spacing: 7) {
                Text(note.displayTitle)
                    .lineLimit(1)
            }
            .font(.system(size: 13, weight: selected ? .semibold : .medium))
            .foregroundStyle(selected ? Color.islandBlue : .white.opacity(0.68))
            .padding(.horizontal, 13)
            .frame(height: 36)
            .frame(maxWidth: 158)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(selected ? Color.islandBlue.opacity(0.13) : Color.white.opacity(0.035))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(selected ? Color.islandBlue.opacity(0.72) : Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(note.displayTitle)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func editor(for note: NoteDocument) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField(
                AppLocalization.text("便签标题"),
                text: Binding(
                    get: { notes.selectedNote?.title ?? "" },
                    set: { notes.updateTitle($0, for: note.id) }
                )
            )
            .textFieldStyle(.plain)
            .font(.system(size: NoteTypography.title, weight: .semibold))
            .foregroundStyle(.white.opacity(0.95))
            .focused($titleFocused)
            .onSubmit { editorFocusRequestID = UUID() }
            .padding(.horizontal, 22)
            .padding(.top, 17)
            .padding(.bottom, 7)

            RichNoteEditor(
                documentID: note.id,
                rtfData: note.bodyRTF,
                command: editorCommand,
                focusRequestID: editorFocusRequestID,
                onChange: { notes.updateBody($0, for: note.id) }
            )
            .padding(.horizontal, 16)

            footer
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text("⌘⇧Space")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.34))
                .frame(width: 72, alignment: .leading)
                .help(AppLocalization.text("快速召唤"))

            HStack(spacing: 3) {
                formatTextButton("H", label: "标题", command: .heading)
                formatButton("bold", label: "加粗", command: .bold)
                formatButton("quote.closing", label: "引用", command: .quote)
                formatButton("list.bullet", label: "无序列表", command: .bulletList)
                formatButton("list.number", label: "有序列表", command: .numberedList)
                formatButton("checkmark.square", label: "任务列表", command: .taskList)
            }
            .padding(4)
            .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.white.opacity(0.11), lineWidth: 1))

            Spacer(minLength: 4)
            saveState
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 16)
        .overlay(alignment: .top) { Divider().overlay(Color.white.opacity(0.09)) }
        .animation(.easeInOut(duration: 0.15), value: notes.saveState)
    }

    private func formatButton(_ systemName: String, label: String, command: RichTextCommandKind) -> some View {
        Button {
            editorCommand = RichTextCommand(kind: command)
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 31, height: 31)
                .contentShape(Rectangle())
        }
        .buttonStyle(FormatToolbarButtonStyle())
        .help(AppLocalization.text(label))
        .accessibilityLabel(AppLocalization.text(label))
    }

    private func formatTextButton(_ text: String, label: String, command: RichTextCommandKind) -> some View {
        Button {
            editorCommand = RichTextCommand(kind: command)
        } label: {
            Text(text)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .frame(width: 31, height: 31)
                .contentShape(Rectangle())
        }
        .buttonStyle(FormatToolbarButtonStyle())
        .help(AppLocalization.text(label))
        .accessibilityLabel(AppLocalization.text(label))
    }

    @ViewBuilder
    private var saveState: some View {
        switch notes.saveState {
        case .saved:
            Label(AppLocalization.text("已本地保存"), systemImage: "checkmark")
                .foregroundStyle(.white.opacity(0.46))
        case .saving:
            Label(AppLocalization.text("保存中"), systemImage: "ellipsis")
                .foregroundStyle(.white.opacity(0.38))
        case .failed:
            Label(AppLocalization.text("保存失败"), systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.islandAmber)
        }
    }

    private var activityCount: Int {
        model.runningCount + model.needsActionCount + model.completedCount + model.pausedCount
    }

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(Color(red: 0.055, green: 0.065, blue: 0.07).opacity(0.99))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.white.opacity(0.2), lineWidth: 1))
    }

    private func createNote() {
        withAnimation(.easeOut(duration: 0.18)) { _ = notes.createNote() }
        DispatchQueue.main.async { titleFocused = true }
    }

#if !HALOFOLD_NO_CODEX_TODO
    private func discoverTodos() {
        guard !isDiscoveringTodos else { return }
        isDiscoveringTodos = true
        todoDiscoveryMessage = nil
        let importedIDs = todoImportStore.loadIDs()
        let since = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date().addingTimeInterval(-604_800)

        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result {
                try CodexTodoExtractor().discover(since: since, excluding: importedIDs)
            }
            DispatchQueue.main.async {
                isDiscoveringTodos = false
                switch result {
                case let .success(candidates):
                    todoCandidates = candidates
                    selectedTodoIDs = Set(candidates.filter { $0.confidence == .explicit }.map(\.id))
                    todoDiscoveryMessage = nil
                case let .failure(error):
                    todoCandidates = []
                    selectedTodoIDs = []
                    todoDiscoveryMessage = error.localizedDescription
                }
                isShowingTodoReview = true
            }
        }
    }

    private func importSelectedTodos() {
        let selected = todoCandidates.filter { selectedTodoIDs.contains($0.id) }
        guard !selected.isEmpty else { return }
        _ = notes.appendTasks(selected.map(\.title), toNoteTitled: AppLocalization.text("Codex 待办"))
        try? todoImportStore.markImported(Set(selected.map(\.id)))
        isShowingTodoReview = false
    }
#endif
}

extension Notification.Name {
    static let focusNewNoteTitle = Notification.Name("Halofold.focusNewNoteTitle")
}

private struct FormatToolbarButtonStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white.opacity(configuration.isPressed ? 1 : 0.72))
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.15 : (hovering ? 0.09 : 0)))
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.09), value: configuration.isPressed)
            .onHover { hovering = $0 }
    }
}
