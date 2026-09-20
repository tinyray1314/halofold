import SwiftUI

struct NotesWorkspaceView: View {
    @ObservedObject var model: ApplicationModel
    @ObservedObject var notes: NoteLibraryModel
    let spacious: Bool
    @State private var searchText = ""
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

    init(model: ApplicationModel, spacious: Bool = false) {
        self.spacious = spacious
        self.model = model
        _notes = ObservedObject(wrappedValue: model.notes)
    }

    var body: some View {
        HStack(spacing: 0) {
            if spacious { noteSidebar }
            VStack(alignment: .leading, spacing: 0) {
                if !spacious {
                    noteTabs
                    Divider().overlay(Color.white.opacity(0.1))
                }
                if let note = notes.selectedNote {
                    editor(for: note).id(note.id)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.white)

        .environment(\.colorScheme, .dark)
        .animation(.easeOut(duration: 0.16), value: notes.selectedNoteID)
        .onReceive(NotificationCenter.default.publisher(for: .focusExpandedNoteBody)) { _ in
            if spacious { editorFocusRequestID = UUID() }
        }
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

    private var noteSidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("便签").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button(action: createNote) { Image(systemName: "plus").frame(width: 32, height: 32).contentShape(Rectangle()) }
                    .buttonStyle(.plain).help("新建便签").accessibilityLabel("新建便签")
            }
            TextField("查找便签", text: $searchText).textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 5) {
                    ForEach(notes.notes.filter { searchText.isEmpty || $0.displayTitle.localizedCaseInsensitiveContains(searchText) }) { note in
                        Button {
                            NSApp.keyWindow?.makeFirstResponder(nil)
                            notes.select(note)
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(note.displayTitle).font(.system(size: 12, weight: .medium)).lineLimit(2)
                                Text(note.updatedAt, style: .date).font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading).padding(11)
                            .background(notes.selectedNoteID == note.id ? Color.islandMint.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 9))
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        .accessibilityAddTraits(notes.selectedNoteID == note.id ? .isSelected : [])
                    }
                }
            }
        }
        .padding(15).frame(width: 190)
        .frame(maxHeight: .infinity)
        .background(Color.white.opacity(0.02))
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
            NSApp.keyWindow?.makeFirstResponder(nil)
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
            .contentShape(Rectangle())
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
        HStack(spacing: 8) {
            if spacious { Text("⌘⇧Space")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.34))
                .frame(width: 72, alignment: .leading)
                .help(AppLocalization.text("快速召唤")) }

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
            if !spacious {
                Button(action: model.expandNoteEditor) { Image(systemName: "arrow.up.left.and.arrow.down.right").frame(width: 27, height: 31) }
                    .buttonStyle(FormatToolbarButtonStyle()).help("展开编辑").accessibilityLabel("展开编辑")
            }
#if !HALOFOLD_NO_CODEX_TODO
            Button(action: discoverTodos) {
                Image(systemName: "sparkles").frame(width: 31, height: 31)
            }
            .buttonStyle(FormatToolbarButtonStyle())
            .disabled(isDiscoveringTodos)
            .help(AppLocalization.text("发现待办"))
            .accessibilityLabel(AppLocalization.text("发现待办"))
#endif
            Button(role: .destructive) {
                if let id = notes.selectedNoteID, let restore = notes.deleteWithUndo(id) {
                    model.offerUndo("已删除便签", restore: restore)
                }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 31, height: 31)
                    .contentShape(Rectangle())
            }
            .buttonStyle(FormatToolbarButtonStyle())
            .help(AppLocalization.text("删除当前便签"))
            .accessibilityLabel(AppLocalization.text("删除当前便签"))
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



    private func createNote() {
        NSApp.keyWindow?.makeFirstResponder(nil)
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
    static let focusExpandedNoteBody = Notification.Name("Halofold.focusExpandedNoteBody")
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
