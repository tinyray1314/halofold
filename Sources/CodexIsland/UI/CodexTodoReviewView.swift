import SwiftUI

struct CodexTodoReviewView: View {
    let candidates: [CodexTodoCandidate]
    @Binding var selectedIDs: Set<String>
    let message: String?
    let onCancel: () -> Void
    let onImport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(AppLocalization.text("从 Codex 发现待办"))
                        .font(.system(size: 18, weight: .semibold))
                    Text(AppLocalization.text("仅扫描最近 7 天的普通对话。请确认后再加入便签。"))
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .background(Color.primary.opacity(0.07), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AppLocalization.text("关闭"))
            }
            .padding(18)

            Divider()

            if candidates.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: message == nil ? "checkmark.circle" : "exclamationmark.triangle")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(message == nil ? Color.green : Color.orange)
                    Text(message ?? AppLocalization.text("最近对话中没有发现新的待办候选"))
                        .font(.system(size: 13.5, weight: .medium))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(28)
            } else {
                ScrollView {
                    LazyVStack(spacing: 9) {
                        ForEach(candidates) { candidate in
                            candidateRow(candidate)
                        }
                    }
                    .padding(14)
                }
            }

            Divider()
            HStack(spacing: 10) {
                if !candidates.isEmpty {
                    Text(AppLocalization.format("已选择 %lld 项", Int64(selectedIDs.count)))
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(AppLocalization.text("取消"), action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(AppLocalization.text("加入 Codex 待办"), action: onImport)
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedIDs.isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(14)
        }
        .frame(width: 480, height: 410)
    }

    private func candidateRow(_ candidate: CodexTodoCandidate) -> some View {
        let selected = selectedIDs.contains(candidate.id)
        return Button {
            if selected {
                selectedIDs.remove(candidate.id)
            } else {
                selectedIDs.insert(candidate.id)
            }
        } label: {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: selected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 6) {
                    Text(candidate.title)
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                    HStack(spacing: 7) {
                        Text(candidate.confidence == .explicit
                             ? AppLocalization.text("明确待办")
                             : AppLocalization.text("可能待办"))
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(candidate.confidence == .explicit ? Color.green : Color.orange)
                        Text(candidate.sourceTitle.isEmpty
                             ? AppLocalization.text("未命名 Codex 对话")
                             : candidate.sourceTitle)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(11)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? Color.accentColor.opacity(0.09) : Color.primary.opacity(0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(selected ? Color.accentColor.opacity(0.4) : Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
