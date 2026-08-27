import AVFoundation
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var model: ApplicationModel
    @ObservedObject var settings: AppSettings
    @State private var selection: SettingsSection = .display
    @State private var feedback: String?
    @State private var isShowingPrivacyPolicy = false

    init(model: ApplicationModel) {
        self.model = model
        _settings = ObservedObject(wrappedValue: model.settings)
        if ProcessInfo.processInfo.arguments.contains("--voice-settings-demo") {
            _selection = State(initialValue: .voice)
        } else if ProcessInfo.processInfo.arguments.contains("--general-settings-demo") {
            _selection = State(initialValue: .general)
        } else if !model.hasCodexFolderAccess {
            _selection = State(initialValue: .general)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            settingsHeader
            settingsTabs
                .padding(.horizontal, 22)
                .padding(.bottom, 16)

            selectedPage
                .id(selection)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .clipped()

            if let feedback {
                HStack(spacing: 7) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.islandBlue)
                    Text(feedback).lineLimit(1)
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.075), in: Capsule())
                .padding(.bottom, 14)
                .transition(.opacity)
            }
        }
        .frame(width: 510, height: 475)
        .foregroundStyle(.white)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(red: 0.055, green: 0.065, blue: 0.07).opacity(0.97))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.white.opacity(0.2), lineWidth: 1))
        )
        .environment(\.colorScheme, .dark)
        .sheet(isPresented: $isShowingPrivacyPolicy) {
            privacyPolicySheet
        }
    }

    private var settingsHeader: some View {
        ZStack {
            Text("设置")
                .font(.system(size: 17, weight: .semibold))

            HStack {
                Button(action: model.finishSettings) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.72))
                .accessibilityLabel("返回任务面板")

                Spacer()

                QuitApplicationButton()

                Button("完成", action: model.finishSettings)
                    .buttonStyle(.plain)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.88))
                    .frame(width: 52, height: 34, alignment: .trailing)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var settingsTabs: some View {
        HStack(spacing: 0) {
            ForEach(SettingsSection.allCases) { section in
                Button {
                    selection = section
                } label: {
                    Label(section.title, systemImage: section.icon)
                        .font(.system(size: 13, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(selection == section ? Color.white.opacity(0.16) : .clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(selection == section ? .white : .white.opacity(0.58))
                if section != SettingsSection.allCases.last {
                    Divider().overlay(Color.white.opacity(0.09)).frame(height: 18)
                }
            }
        }
        .padding(3)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    @ViewBuilder
    private var selectedPage: some View {
        if selection == .display {
            DisplayIslandSettings(settings: settings)
        } else if selection == .voice {
            VoiceIslandSettings(model: model, settings: settings, feedback: $feedback)
        } else {
            GeneralIslandSettings(
                model: model,
                feedback: $feedback,
                showPrivacyPolicy: { isShowingPrivacyPolicy = true }
            )
        }
    }

    private var privacyPolicySheet: some View {
        PrivacyPolicyView(dismiss: { isShowingPrivacyPolicy = false })
    }
}

private enum SettingsSection: String, CaseIterable, Identifiable {
    case display
    case voice
    case general

    var id: String { rawValue }
    var title: String {
        switch self {
        case .display: return AppLocalization.text("显示")
        case .voice: return AppLocalization.text("语音")
        case .general: return AppLocalization.text("通用")
        }
    }
    var icon: String {
        switch self {
        case .display: return "rectangle.3.group"
        case .voice: return "waveform"
        case .general: return "gearshape"
        }
    }
}

private struct DisplayIslandSettings: View {
    @ObservedObject var settings: AppSettings
    @State private var draggingModule: DisplayModule?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CollapsedLayoutModeSelector(settings: settings)
            .padding(.bottom, 12)

            VStack(spacing: 0) {
                ForEach(settings.moduleOrder) { module in
                    displayRow(module)
                        .onDrag {
                            draggingModule = module
                            return NSItemProvider(object: module.rawValue as NSString)
                        }
                        .onDrop(of: [UTType.text], delegate: ModuleDropDelegate(
                            destination: module,
                            dragging: $draggingModule,
                            settings: settings
                        ))
                    if module != settings.moduleOrder.last {
                        Divider().overlay(Color.white.opacity(0.1)).padding(.horizontal, 18)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(Color.black.opacity(0.16))
                    .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1))
            )

            Text("紧凑模式减少菜单栏占用，宽松模式保留完整文案。左右两侧都可点击展开。\n开关和排序会同时影响收起态轮播与展开面板。")
                .font(.system(size: 12.5))
                .foregroundStyle(.white.opacity(0.48))
                .lineSpacing(4)
                .padding(.top, 12)
                .padding(.horizontal, 2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
    }

    private func displayRow(_ module: DisplayModule) -> some View {
        HStack(spacing: 12) {
            moduleIcon(module)
                .frame(width: 22, height: 22)
            Text(module.title)
                .font(.system(size: 15, weight: .medium))
            Spacer()
            IslandSwitch(isOn: Binding(
                get: { settings.isEnabled(module) },
                set: { settings.setEnabled(module, enabled: $0) }
            ))
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
                .frame(width: 29, height: 36)
                .help("拖动调整显示顺序")
        }
        .padding(.horizontal, 18)
        .frame(height: 62)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func moduleIcon(_ module: DisplayModule) -> some View {
        switch module {
        case .taskStatus:
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.white.opacity(0.86))
        case .weeklyRemaining:
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.3), lineWidth: 2.5)
                Circle()
                    .trim(from: 0, to: 0.72)
                    .stroke(Color.islandBlue, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 18, height: 18)
        case .todayTokens:
            Image(systemName: "circle.dotted.circle")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.white.opacity(0.86))
        }
    }
}

private struct CollapsedLayoutModeSelector: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.left.and.right")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.82))
                .frame(width: 22)
            Text("收起态")
                .font(.system(size: 15, weight: .medium))
            Spacer()
            HStack(spacing: 6) {
                ForEach(CollapsedLayoutMode.allCases) { mode in
                    modeButton(mode)
                }
            }
            .accessibilityElement(children: .contain)
        }
        .padding(.horizontal, 18)
        .frame(height: 58)
        .background(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(Color.black.opacity(0.16))
                .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1))
        )
    }

    private func modeButton(_ mode: CollapsedLayoutMode) -> some View {
        let selected = settings.collapsedLayoutMode == mode
        return Button {
            settings.collapsedLayoutMode = mode
        } label: {
            HStack(spacing: 6) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Color.islandBlue : Color.white.opacity(0.35))
                VStack(alignment: .leading, spacing: 1) {
                    Text(mode.title).font(.system(size: 12.5, weight: .semibold))
                    Text(mode.subtitle)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.white.opacity(0.46))
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 38)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(selected ? Color.islandBlue.opacity(0.15) : Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(selected ? Color.islandBlue.opacity(0.65) : Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AppLocalization.format("%@，%@", mode.title, mode.subtitle))
        .accessibilityValue(AppLocalization.text(selected ? "已选择" : "未选择"))
    }
}

private struct ModuleDropDelegate: DropDelegate {
    let destination: DisplayModule
    @Binding var dragging: DisplayModule?
    let settings: AppSettings

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != destination else { return }
        settings.moveModule(dragging, before: destination)
    }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
}

private struct VoiceIslandSettings: View {
    @ObservedObject var model: ApplicationModel
    @ObservedObject var settings: AppSettings
    @Binding var feedback: String?
    @State private var funVoiceTarget: FunVoiceTarget?

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                voiceBlock(kind: .completed, title: AppLocalization.text("任务完成"), tint: .islandGreen)
                voiceBlock(kind: .paused, title: AppLocalization.text("任务中断"), tint: .islandAmber)
                voiceAndVolume
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 16)
        }
        .scrollIndicators(.visible)
        .onDisappear {
            guard model.recordingAlertKind != nil else { return }
            model.cancelAlertRecording()
            feedback = AppLocalization.text("已取消录音，原提醒音保持不变")
        }
        .sheet(item: $funVoiceTarget) { target in
            FunVoiceComposerSheet(
                model: model,
                settings: settings,
                kind: target.kind,
                dismiss: { funVoiceTarget = nil },
                completed: { message in
                    feedback = message
                    funVoiceTarget = nil
                }
            )
        }
    }

    private func voiceBlock(kind: AlertKind, title: String, tint: Color) -> some View {
        let enabled = Binding(
            get: { kind == .completed ? settings.completionEnabled : settings.pauseEnabled },
            set: { kind == .completed ? (settings.completionEnabled = $0) : (settings.pauseEnabled = $0) }
        )
        let mode = Binding(
            get: { kind == .completed ? settings.completionMode : settings.pauseMode },
            set: { kind == .completed ? (settings.completionMode = $0) : (settings.pauseMode = $0) }
        )
        let text = Binding(
            get: { kind == .completed ? settings.completionText : settings.pauseText },
            set: { kind == .completed ? (settings.completionText = $0) : (settings.pauseText = $0) }
        )

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: kind == .completed ? "checkmark.circle.fill" : "pause.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
                Spacer()
                IslandSwitch(isOn: enabled)
            }

            sourceSelector(kind: kind, title: title, mode: mode)

            if model.recordingAlertKind == kind {
                recordingContentRow(kind: kind, title: title)
            } else if mode.wrappedValue == .system {
                textContentRow(kind: kind, title: title, text: text)
            } else {
                audioContentRow(kind: kind, title: title)
            }

            Button {
                funVoiceTarget = FunVoiceTarget(kind: kind)
            } label: {
                Label("使用趣味音色朗读文案", systemImage: "sparkles")
                    .font(.system(size: 11.5, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.58))
            .disabled(model.recordingAlertKind != nil)
        }
        .padding(12)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private enum VoiceSourceChoice {
        case text
        case recording
        case file

        var title: String {
            switch self {
            case .text: return AppLocalization.text("文案朗读")
            case .recording: return AppLocalization.text("直接录音")
            case .file: return AppLocalization.text("音频文件")
            }
        }

        var icon: String {
            switch self {
            case .text: return "text.bubble"
            case .recording: return "mic"
            case .file: return "waveform"
            }
        }
    }

    private func sourceSelector(
        kind: AlertKind,
        title: String,
        mode: Binding<VoiceMode>
    ) -> some View {
        HStack(spacing: 0) {
            sourceButton(.text, kind: kind, title: title, mode: mode)
            Divider().overlay(Color.white.opacity(0.11)).frame(height: 24)
            sourceButton(.recording, kind: kind, title: title, mode: mode)
            Divider().overlay(Color.white.opacity(0.11)).frame(height: 24)
            sourceButton(.file, kind: kind, title: title, mode: mode)
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.14))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.13), lineWidth: 1)
                )
        )
    }

    private func sourceButton(
        _ choice: VoiceSourceChoice,
        kind: AlertKind,
        title: String,
        mode: Binding<VoiceMode>
    ) -> some View {
        let isRecording = model.recordingAlertKind == kind
        let selected: Bool = switch choice {
        case .text: mode.wrappedValue == .system && !isRecording
        case .recording: isRecording
        case .file: mode.wrappedValue == .importedAudio && !isRecording
        }

        return Button {
            switch choice {
            case .text:
                mode.wrappedValue = .system
            case .recording:
                if !isRecording {
                    startRecording(kind, title: title)
                }
            case .file:
                if audioName(kind) == nil {
                    chooseAudio(kind)
                } else {
                    mode.wrappedValue = .importedAudio
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: choice == .recording && isRecording ? "record.circle" : choice.icon)
                    .font(.system(size: 13, weight: .medium))
                Text(choice == .recording && isRecording ? AppLocalization.text("录音中") : choice.title)
                    .font(.system(size: 11, weight: selected ? .semibold : .medium))
                    .lineLimit(1)
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Color.islandBlue)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? Color.islandBlue.opacity(0.15) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(selected ? .white.opacity(0.9) : .white.opacity(0.58))
        .disabled(model.recordingAlertKind != nil && !isRecording)
    }

    private func textContentRow(
        kind: AlertKind,
        title: String,
        text: Binding<String>
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "text.bubble")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 24)
            TextField("提醒文案", text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
            previewButton(kind: kind, title: title)
        }
        .padding(.horizontal, 12)
        .frame(height: 46)
        .background(contentRowBackground)
    }

    private func audioContentRow(kind: AlertKind, title: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "music.note")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 24)
            Text(audioName(kind) ?? AppLocalization.text("尚未选择音频"))
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.white.opacity(audioName(kind) == nil ? 0.42 : 0.78))
                .lineLimit(1)
            Spacer(minLength: 6)
            Button(AppLocalization.text(audioName(kind) == nil ? "选择" : "更换")) { chooseAudio(kind) }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.islandBlue)
            previewButton(kind: kind, title: title)
        }
        .padding(.horizontal, 12)
        .frame(height: 46)
        .background(contentRowBackground)
    }

    private func recordingContentRow(kind: AlertKind, title: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "record.circle.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.red.opacity(0.9))
            Text("正在录音…")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.78))
            Spacer()
            Button("取消") {
                model.cancelAlertRecording()
                feedback = AppLocalization.text("已取消录音，原提醒音保持不变")
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white.opacity(0.55))

            Button {
                finishRecording(kind, title: title)
            } label: {
                Label("停止并替换", systemImage: "stop.fill")
                    .font(.system(size: 11.5, weight: .semibold))
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(Color.islandBlue, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .accessibilityLabel(AppLocalization.format("停止录音并替换%@提醒音", title))
        }
        .padding(.horizontal, 12)
        .frame(height: 46)
        .background(contentRowBackground)
    }

    private var contentRowBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.black.opacity(0.13))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.11), lineWidth: 1)
            )
    }

    private func previewButton(kind: AlertKind, title: String) -> some View {
        Button {
            do {
                try model.previewAlert(kind)
                feedback = AppLocalization.format("正在播放%@预览", title)
            } catch {
                feedback = error.localizedDescription
            }
        } label: {
            Image(systemName: "play.fill")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 30, height: 30)
                .background(Color.islandBlue.opacity(0.13), in: Circle())
                .overlay(Circle().stroke(Color.islandBlue.opacity(0.38), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.islandBlue)
        .accessibilityLabel(AppLocalization.format("预览%@提醒音", title))
    }

    private var voiceAndVolume: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("系统音色与音量")
                .font(.system(size: 14, weight: .semibold))
            Picker("音色", selection: $settings.voiceIdentifier) {
                Text("系统默认音色").tag("")
                ForEach(compatibleVoices, id: \.identifier) { voice in
                    Text("\(voice.name) · \(voice.language)").tag(voice.identifier)
                }
            }
            HStack {
                Image(systemName: "speaker.fill")
                Slider(value: $settings.voiceVolume, in: 0...1)
                Image(systemName: "speaker.wave.3.fill")
            }
            .foregroundStyle(.white.opacity(0.65))
        }
        .padding(16)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var compatibleVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(AppLocalization.voiceLanguagePrefix) }
            .sorted { $0.name < $1.name }
    }

    private func audioName(_ kind: AlertKind) -> String? {
        let path = kind == .completed ? settings.completionAudioPath : settings.pauseAudioPath
        return path.map { URL(fileURLWithPath: $0).lastPathComponent }
    }

    private func chooseAudio(_ kind: AlertKind) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [UTType.audio]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            _ = try model.importAudio(for: kind, from: url)
            feedback = AppLocalization.text("音频已导入本地目录")
        } catch {
            feedback = error.localizedDescription
        }
    }

    private func startRecording(_ kind: AlertKind, title: String) {
        Task {
            do {
                try await model.startAlertRecording(for: kind)
                feedback = AppLocalization.format("正在录制%@提醒，完成后点击“停止并替换”", title)
            } catch {
                feedback = error.localizedDescription
            }
        }
    }

    private func finishRecording(_ kind: AlertKind, title: String) {
        do {
            _ = try model.finishAlertRecording(for: kind)
            feedback = AppLocalization.format("%@已替换为新录音", title)
        } catch {
            feedback = error.localizedDescription
        }
    }
}

private struct FunVoiceTarget: Identifiable {
    let kind: AlertKind
    var id: String { kind.rawValue }
}

private struct FunVoiceComposerSheet: View {
    @ObservedObject var model: ApplicationModel
    @ObservedObject var settings: AppSettings
    let kind: AlertKind
    let dismiss: () -> Void
    let completed: (String) -> Void

    @State private var draftText: String
    @State private var preset = FunVoicePreset.lively
    @State private var status: String?
    @State private var isWorking = false

    init(
        model: ApplicationModel,
        settings: AppSettings,
        kind: AlertKind,
        dismiss: @escaping () -> Void,
        completed: @escaping (String) -> Void
    ) {
        self.model = model
        self.settings = settings
        self.kind = kind
        self.dismiss = dismiss
        self.completed = completed
        _draftText = State(initialValue: kind == .completed ? settings.completionText : settings.pauseText)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            HStack(alignment: .top, spacing: 18) {
                scriptColumn

                Rectangle()
                    .fill(Color.white.opacity(0.10))
                    .frame(width: 1)

                effectColumn
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 16)

            if let status {
                HStack(spacing: 7) {
                    Image(systemName: isWorking ? "clock" : "info.circle")
                    Text(status)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.62))
                .padding(.horizontal, 22)
                .padding(.bottom, 12)
            }

            Rectangle()
                .fill(Color.white.opacity(0.10))
                .frame(height: 1)

            footer
        }
        .frame(width: 570)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.075, green: 0.085, blue: 0.095),
                    Color(red: 0.045, green: 0.052, blue: 0.060)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .preferredColorScheme(.dark)
        .onDisappear {
            if model.isRecordingVoiceDraft { model.cancelAlertRecording() }
        }
        .onChange(of: draftText) { _, newValue in
            if newValue.count > 500 {
                draftText = String(newValue.prefix(500))
            }
        }
    }

    private var header: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 4) {
                HStack(spacing: 9) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 19, weight: .semibold))
                    Text("趣味音色朗读")
                        .font(.system(size: 21, weight: .bold))
                }
                Text(AppLocalization.text(kind == .completed ? "为「任务完成」生成新的提醒音" : "为「任务中断」生成新的提醒音"))
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.50))
            }
            .frame(maxWidth: .infinity)

            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.72))
                    .frame(width: 32, height: 32)
                    .background(Color.white.opacity(0.055), in: Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.14), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("关闭趣味音色朗读")
        }
        .padding(.horizontal, 22)
        .padding(.top, 20)
        .padding(.bottom, 18)
    }

    private var scriptColumn: some View {
        VStack(alignment: .leading, spacing: 11) {
            sectionTitle(AppLocalization.text("朗读文案"), icon: "text.bubble")

            ZStack(alignment: .bottomTrailing) {
                TextEditor(text: $draftText)
                    .font(.system(size: 14))
                    .scrollContentBackground(.hidden)
                    .padding(9)
                    .frame(height: 166)
                    .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 9))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )

                Text("\(draftText.count)/500")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.38))
                    .padding(10)
                    .allowsHitTesting(false)
            }

            HStack(spacing: 7) {
                Image(systemName: "checkmark.shield")
                Text("文字仅在本地处理，音频不上传，保障隐私安全。")
                    .lineLimit(1)
            }
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(Color.white.opacity(0.48))

            if model.isRecordingVoiceDraft {
                HStack(spacing: 8) {
                    Button {
                        finishDraftRecording()
                    } label: {
                        Label("停止并转成文案", systemImage: "stop.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)

                    Button("取消") {
                        model.cancelAlertRecording()
                        status = AppLocalization.text("已取消，文案未改变")
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                Button {
                    startDraftRecording()
                } label: {
                    Label("录音转文案", systemImage: "mic.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 31)
                }
                .buttonStyle(.plain)
                .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .disabled(isWorking)
    }

    private var effectColumn: some View {
        VStack(alignment: .leading, spacing: 11) {
            sectionTitle(AppLocalization.text("选择效果"), icon: "waveform")

            VStack(spacing: 0) {
                ForEach(FunVoicePreset.allCases) { item in
                    Button {
                        preset = item
                    } label: {
                        HStack(spacing: 9) {
                            ZStack {
                                Circle()
                                    .stroke(
                                        preset == item ? Color.islandBlue : Color.white.opacity(0.45),
                                        lineWidth: preset == item ? 2 : 1
                                    )
                                    .frame(width: 18, height: 18)
                                if preset == item {
                                    Circle()
                                        .fill(Color.islandBlue)
                                        .frame(width: 10, height: 10)
                                }
                            }
                            Text(item.title)
                                .font(.system(size: 12.5, weight: preset == item ? .semibold : .regular))
                            Spacer(minLength: 4)
                            Image(systemName: presetIcon(item))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(preset == item ? Color.islandBlue : Color.white.opacity(0.40))
                        }
                        .foregroundStyle(Color.white.opacity(preset == item ? 0.92 : 0.70))
                        .padding(.horizontal, 10)
                        .frame(height: 34)
                        .background(preset == item ? Color.islandBlue.opacity(0.10) : Color.clear)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if item != FunVoicePreset.allCases.last {
                        Rectangle()
                            .fill(Color.white.opacity(0.085))
                            .frame(height: 1)
                    }
                }
            }
            .background(Color.black.opacity(0.14), in: RoundedRectangle(cornerRadius: 9))
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: 5) {
                Text(preset.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.84))
                Text(preset.subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.white.opacity(0.48))
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Color.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )

            HStack(spacing: 8) {
                Image(systemName: "shippingbox")
                Text("本地 AI 音色包：未安装")
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(Color.white.opacity(0.36))
            .padding(9)
            .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
        }
        .frame(width: 225, alignment: .topLeading)
        .disabled(isWorking)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Button("关闭", action: dismiss)
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.72))
                .frame(width: 86, height: 36)
                .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.11)))

            Spacer()

            Button {
                do {
                    try model.previewFunVoice(text: draftText, preset: preset)
                    status = AppLocalization.text("正在试听；{count} 在生成音频时按 1 朗读")
                } catch {
                    status = error.localizedDescription
                }
            } label: {
                Label("试听", systemImage: "play.fill")
                    .frame(width: 105, height: 34)
            }
            .buttonStyle(.plain)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.80))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.islandBlue, lineWidth: 1))
            .disabled(isWorking || model.isRecordingVoiceDraft)

            Button {
                generate()
            } label: {
                HStack(spacing: 7) {
                    if isWorking { ProgressView().controlSize(.small) }
                    Text("生成并替换")
                }
                .frame(width: 126, height: 36)
            }
            .buttonStyle(.plain)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.white)
            .background(Color.islandBlue, in: RoundedRectangle(cornerRadius: 8))
            .disabled(isWorking || model.isRecordingVoiceDraft)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 15)
    }

    private func sectionTitle(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.system(size: 13.5, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.78))
    }

    private func presetIcon(_ item: FunVoicePreset) -> String {
        switch item {
        case .lively: return "waveform"
        case .cartoon: return "face.smiling"
        case .uncle: return "person.crop.circle"
        case .slowMotion: return "tortoise"
        case .brisk: return "bolt"
        }
    }

    private func startDraftRecording() {
        Task {
            do {
                try await model.startVoiceDraftRecording()
                status = AppLocalization.text("正在录音…说完后点击“停止并转成文案”")
            } catch {
                status = error.localizedDescription
            }
        }
    }

    private func finishDraftRecording() {
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                draftText = try await model.finishVoiceDraftRecordingAndTranscribe()
                status = AppLocalization.text("已在本机转成文案，可继续修改")
            } catch {
                status = error.localizedDescription
            }
        }
    }

    private func generate() {
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                _ = try await model.generateFunVoiceAlert(for: kind, text: draftText, preset: preset)
                completed(AppLocalization.text("趣味提醒音已生成并替换"))
            } catch {
                status = error.localizedDescription
            }
        }
    }
}

private struct GeneralIslandSettings: View {
    @ObservedObject var model: ApplicationModel
    @Binding var feedback: String?
    let showPrivacyPolicy: () -> Void
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                settingsRow(icon: "power", title: AppLocalization.text("登录 Mac 后自动启动")) {
                IslandSwitch(isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            try model.setLaunchAtLogin(enabled)
                            feedback = AppLocalization.text(enabled ? "已开启自动启动" : "已关闭自动启动")
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                            feedback = AppLocalization.format("自动启动失败：%@", error.localizedDescription)
                        }
                    }
                }
                Divider().overlay(Color.white.opacity(0.1)).padding(.horizontal, 18)
                settingsRow(icon: "externaldrive", title: AppLocalization.text("Codex 数据 · 只读")) {
                Button(AppLocalization.text(model.hasCodexFolderAccess ? "重新选择" : "选择 .codex 文件夹")) {
                    do {
                        if try model.requestCodexFolderAccess() {
                            feedback = AppLocalization.text("已获得 .codex 文件夹的只读授权")
                        }
                    } catch {
                        feedback = error.localizedDescription
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                }
                Divider().overlay(Color.white.opacity(0.1)).padding(.horizontal, 18)
                infoRow(icon: "folder", title: AppLocalization.text("本地数据"), value: "Application Support")
                Divider().overlay(Color.white.opacity(0.1)).padding(.horizontal, 18)
                infoRow(
                    icon: "chart.pie",
                    title: AppLocalization.text("官方周用量"),
                    value: AppLocalization.text(CodexDataAccess.shared.isSandboxed ? "本机同步" : "主动刷新 + 本机同步")
                )
                Divider().overlay(Color.white.opacity(0.1)).padding(.horizontal, 18)
                settingsRow(icon: "sparkles.rectangle.stack", title: AppLocalization.text("无 Codex 数据时预览")) {
                Button(AppLocalization.text(model.isDemoMode ? "退出演示" : "打开演示")) {
                    if model.isDemoMode {
                        model.exitDemoMode()
                        feedback = AppLocalization.text("已退出演示模式")
                    } else {
                        model.enterDemoMode()
                        feedback = AppLocalization.text("已打开本机演示数据")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                }
                Divider().overlay(Color.white.opacity(0.1)).padding(.horizontal, 18)
                settingsRow(icon: "hand.raised", title: AppLocalization.text("隐私政策")) {
                Button("查看", action: showPrivacyPolicy)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(Color.black.opacity(0.16))
                    .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1))
            )

            Label("所有数据仅在本机处理，不读取或保存 Codex 登录凭据。", systemImage: "lock.fill")
                .font(.system(size: 11.5))
                .foregroundStyle(.white.opacity(0.42))
                .padding(.top, 12)
                .padding(.bottom, 18)
        }
        .scrollIndicators(.visible)
        .padding(.horizontal, 22)
    }

    private func settingsRow<Content: View>(icon: String, title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).frame(width: 22).foregroundStyle(.white.opacity(0.78))
            Text(title).font(.system(size: 14.5, weight: .medium))
            Spacer()
            content()
        }
        .padding(.horizontal, 18)
        .frame(height: 65)
    }

    private func infoRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).frame(width: 22).foregroundStyle(.white.opacity(0.78))
            Text(title).font(.system(size: 14.5, weight: .medium))
            Spacer()
            Text(value).font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.48)).lineLimit(1)
        }
        .padding(.horizontal, 18)
        .frame(height: 65)
    }
}

private struct PrivacyPolicyView: View {
    let dismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("隐私政策")
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                Button("完成", action: dismiss)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            .padding(18)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    policySection(AppLocalization.text("本机数据访问"), AppLocalization.text("仅在你主动选择并授权后，应用才会以只读方式访问 .codex 文件夹，用于显示任务状态、对话标题、本机 Token 统计和官方用量快照。当你主动使用“发现待办”时，应用还会在本机分析最近对话正文。对话内容不会上传，应用也不会读取、复制或保存 Codex 登录凭据。"))
                    policySection(AppLocalization.text("数据收集与传输"), AppLocalization.text("应用不收集个人数据，不使用分析或广告 SDK，不跟踪用户，也不会把 .codex 文件夹内容发送给开发者或任何第三方服务器。"))
                    policySection(AppLocalization.text("本地存储"), AppLocalization.text("应用设置、任务读取断点、安全作用域书签和你主动录制或导入的提醒音频，只保存在这台 Mac 的应用容器中。"))
                    policySection(AppLocalization.text("第三方服务"), AppLocalization.text("点击任务时，应用仅通过本机 codex:// 链接打开已安装的 Codex app。"))
                    Text(AppLocalization.text("最后更新：2026 年 8 月 21 日"))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                .padding(20)
            }
        }
        .frame(width: 520, height: 430)
    }

    private func policySection(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 14, weight: .semibold))
            Text(text)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .lineSpacing(4)
        }
    }
}

private struct IslandSwitch: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? Color.islandBlue : Color.white.opacity(0.22))
                    .frame(width: 48, height: 28)
                Circle()
                    .fill(.white)
                    .frame(width: 24, height: 24)
                    .shadow(color: .black.opacity(0.22), radius: 2, y: 1)
                    .padding(2)
            }
            .animation(.easeOut(duration: 0.16), value: isOn)
        }
        .buttonStyle(.plain)
        .accessibilityValue(AppLocalization.text(isOn ? "已开启" : "已关闭"))
    }
}
