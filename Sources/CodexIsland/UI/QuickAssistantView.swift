import AppKit
import SwiftUI

/// A stable overview: live information changes inside cards, never their order.
struct QuickAssistantView: View {
    @ObservedObject var model: ApplicationModel
    @ObservedObject var notes: NoteLibraryModel
    @ObservedObject var schedule: ScheduleLibraryModel
    @ObservedObject var settings: AppSettings

    init(model: ApplicationModel) {
        self.model = model
        notes = model.notes
        schedule = model.schedule
        settings = model.settings
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                if settings.isEnabled(.codexFollowUp) { attentionCard }
                if settings.isEnabled(.schedule) {
                    HStack(spacing: 10) { focusCard; nextCard }
                }
                if settings.isEnabled(.quickNotes) { quickNote }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 16)
        }
        .scrollIndicators(.hidden)
    }

    private var attentionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            let pending = model.visibleConversations.filter { $0.state == .needsAction }
            HStack {
                Label(pending.isEmpty ? "当前活动" : "需要你处理 · \(pending.count) 项", systemImage: pending.isEmpty ? "waveform.path" : "hand.raised")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.55))
                Spacer()
                Button("全部", action: model.showActivityWorkspace).buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Color.islandMint)
            }
            if let first = pending.first {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(first.title).font(.system(size: 14, weight: .medium)).lineLimit(1)
                        Text(first.actionPrompt ?? "正在等待你的确认").font(.system(size: 11)).foregroundStyle(.white.opacity(0.52)).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Button { model.open(first) } label: { Label("处理", systemImage: "arrow.up.right") }
                        .buttonStyle(AssistantActionStyle())
                }
            } else {
                Text(model.sourceHasWarning ? model.sourceStatusText : (model.runningCount > 0 ? "\(model.runningCount) 项正在进行，无需处理" : "暂时没有需要处理的事"))
                    .font(.system(size: 13)).foregroundStyle(.white.opacity(0.8)).lineLimit(2)
                if model.sourceHasWarning {
                    Button(model.sourceRecoveryTitle, action: model.recoverSource).buttonStyle(.plain).foregroundStyle(Color.islandMint).font(.system(size: 12))
                }
            }
        }
        .assistantCard()
    }

    private var focusCard: some View {
        Button {
            model.showScheduleWorkspace()
            model.isShowingFocusDetail = running != nil
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Label("当前专注", systemImage: "timer").font(.system(size: 11)).foregroundStyle(.white.opacity(0.52))
                if let item = running {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let seconds = max(0, Int(item.expectedEnd.timeIntervalSince(context.date)))
                        Text(String(format: "%02d:%02d", seconds / 60, seconds % 60))
                            .font(.system(size: 27, weight: .medium, design: .rounded)).monospacedDigit()
                    }
                    Text(item.title).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                } else {
                    Text("留一点专注时间").font(.system(size: 14, weight: .medium)).frame(height: 32)
                    Text("选择日程开始 ↗").font(.system(size: 11)).foregroundStyle(Color.islandMint)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).assistantCard()
        }.buttonStyle(.plain)
    }

    private var nextCard: some View {
        Button(action: model.showScheduleWorkspace) {
            VStack(alignment: .leading, spacing: 6) {
                Label("下一项安排", systemImage: "calendar").font(.system(size: 11)).foregroundStyle(.white.opacity(0.52))
                if let item = nextOccurrence {
                    Text(item.plannedStart, style: .time).font(.system(size: 27, weight: .medium, design: .rounded)).monospacedDigit()
                    Text(item.title).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                } else {
                    Text("今天暂时没有安排").font(.system(size: 14, weight: .medium)).frame(height: 32)
                    Text("查看日程 ↗").font(.system(size: 11)).foregroundStyle(Color.islandMint)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).assistantCard()
        }.buttonStyle(.plain)
    }

    private var running: ScheduleOccurrence? {
        schedule.snapshot.occurrences.first { !$0.isDeleted && $0.status == .running }
    }

    private var nextOccurrence: ScheduleOccurrence? {
        schedule.occurrences(on: Date()).filter { [.planned, .awaitingStart, .overdueDecision].contains($0.status) }
            .sorted { $0.plannedStart < $1.plannedStart }.first
    }

    private var quickNote: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("随手记").font(.system(size: 12, weight: .semibold))
                Spacer()
                Button {
                    NSApp.keyWindow?.makeFirstResponder(nil)
                    notes.createNote()
                } label: { Image(systemName: "plus") }
                .buttonStyle(.plain).help("新建便签").accessibilityLabel("新建便签")
            }
            if let note = notes.selectedNote {
                Text(note.displayTitle).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                RichNoteEditor(documentID: note.id, rtfData: note.bodyRTF, command: nil, focusRequestID: nil,
                               onChange: { notes.updateBody($0, for: note.id) })
                    .id(note.id)
                    .frame(height: 90)
                    .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 9))
            }
            HStack {
                NoteSaveIndicator(state: notes.saveState)
                Spacer()
                Button(action: model.expandNoteEditor) { Label("展开编辑", systemImage: "arrow.up.left.and.arrow.down.right") }
                    .buttonStyle(AssistantActionStyle())
            }
        }.assistantCard()
    }
}

struct NoteSaveIndicator: View {
    let state: NoteSaveState
    var body: some View {
        Group {
            switch state {
            case .saved: Label("已本地保存", systemImage: "checkmark").foregroundStyle(.white.opacity(0.45))
            case .saving: Label("保存中", systemImage: "ellipsis").foregroundStyle(.white.opacity(0.45))
            case .failed: Label("保存失败", systemImage: "exclamationmark.triangle").foregroundStyle(Color.islandAmber)
            }
        }.font(.system(size: 11))
    }
}

struct AssistantActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 10).padding(.vertical, 8)
            .foregroundStyle(Color(red: 0.14, green: 0.23, blue: 0.18))
            .background(Color.islandMint.opacity(configuration.isPressed ? 0.75 : 1), in: RoundedRectangle(cornerRadius: 8))
    }
}

extension Color {
    static let islandMint = Color(red: 0.73, green: 0.84, blue: 0.77)
}

private extension View {
    func assistantCard() -> some View {
        padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [.white.opacity(0.045), .white.opacity(0.015)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(.white.opacity(0.07), lineWidth: 1))
    }
}
