import Foundation

enum CodexTodoConfidence: String, Codable, Sendable {
    case explicit
    case possible
}

struct CodexTodoCandidate: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let sourceThreadID: String
    let sourceTitle: String
    let sourceUpdatedAt: Date
    let confidence: CodexTodoConfidence
}

enum CodexTodoDiscoveryError: LocalizedError {
    case noCodexAccess

    var errorDescription: String? {
        switch self {
        case .noCodexAccess:
            return AppLocalization.text("请先在设置中授权只读访问 .codex 文件夹")
        }
    }
}

/// Reads a bounded tail of recent, user-owned Codex rollouts and produces review candidates.
/// It intentionally ignores developer/system messages, tool traffic, subagents, and automations.
final class CodexTodoExtractor {
    private let database: CodexDatabase
    private let maximumBytesPerThread = 1_500_000

    init(database: CodexDatabase = CodexDatabase()) {
        self.database = database
    }

    func discover(
        since: Date,
        maximumThreads: Int = 60,
        excluding importedIDs: Set<String> = []
    ) throws -> [CodexTodoCandidate] {
        guard database.codexDirectory != nil else { throw CodexTodoDiscoveryError.noCodexAccess }
        let threads = try database.threads(updatedAfter: since)
            .filter { !$0.archived && $0.kind == .user && !$0.rolloutPath.isEmpty }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(maximumThreads)

        return discover(in: Array(threads), excluding: importedIDs)
    }

    func discover(
        in threads: [ThreadMetadata],
        excluding importedIDs: Set<String> = []
    ) -> [CodexTodoCandidate] {
        var bestByTask: [String: CodexTodoCandidate] = [:]
        for thread in threads where !thread.archived && thread.kind == .user && !thread.rolloutPath.isEmpty {
            for message in messages(in: URL(fileURLWithPath: thread.rolloutPath)) {
                for extracted in extractCandidates(from: message.text, role: message.role) {
                    let normalized = normalizeForComparison(extracted.title)
                    guard !normalized.isEmpty else { continue }
                    let id = stableID("\(thread.id)|\(message.turnID)|\(normalized)")
                    guard !importedIDs.contains(id) else { continue }
                    let candidate = CodexTodoCandidate(
                        id: id,
                        title: extracted.title,
                        sourceThreadID: thread.id,
                        sourceTitle: thread.title,
                        sourceUpdatedAt: thread.updatedAt,
                        confidence: extracted.confidence
                    )
                    if let existing = bestByTask[normalized] {
                        if candidate.confidence == .explicit && existing.confidence == .possible {
                            bestByTask[normalized] = candidate
                        } else if candidate.confidence == existing.confidence,
                                  candidate.sourceUpdatedAt > existing.sourceUpdatedAt {
                            bestByTask[normalized] = candidate
                        }
                    } else {
                        bestByTask[normalized] = candidate
                    }
                }
            }
        }

        return Array(bestByTask.values.sorted {
            if $0.confidence != $1.confidence { return $0.confidence == .explicit }
            return $0.sourceUpdatedAt > $1.sourceUpdatedAt
        }.prefix(30))
    }

    private struct TranscriptMessage {
        let role: String
        let turnID: String
        let text: String
    }

    private struct ExtractedTask {
        let title: String
        let confidence: CodexTodoConfidence
    }

    private func messages(in url: URL) -> [TranscriptMessage] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        let end = (try? handle.seekToEnd()) ?? 0
        let start = end > maximumBytesPerThread ? end - UInt64(maximumBytesPerThread) : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd(), var text = String(data: data, encoding: .utf8) else { return [] }
        if start > 0, let newline = text.firstIndex(of: "\n") {
            text.removeSubrange(text.startIndex...newline)
        }

        return text.split(separator: "\n").compactMap { rawLine in
            guard let data = String(rawLine).data(using: .utf8),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  root["type"] as? String == "response_item",
                  let payload = root["payload"] as? [String: Any],
                  payload["type"] as? String == "message",
                  let role = payload["role"] as? String,
                  role == "user" || (role == "assistant" && payload["phase"] as? String == "final_answer"),
                  let content = payload["content"] as? [[String: Any]]
            else { return nil }

            let acceptedType = role == "user" ? "input_text" : "output_text"
            let messageText = content.compactMap { item -> String? in
                guard item["type"] as? String == acceptedType else { return nil }
                return item["text"] as? String
            }.joined(separator: "\n")
            guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            let metadata = payload["internal_chat_message_metadata_passthrough"] as? [String: Any]
            let turnID = metadata?["turn_id"] as? String ?? "unknown"
            return TranscriptMessage(role: role, turnID: turnID, text: messageText)
        }
    }

    private func extractCandidates(from text: String, role: String) -> [ExtractedTask] {
        var output: [ExtractedTask] = []
        var taskSectionRemaining = 0
        for rawLine in text.replacingOccurrences(of: "\r", with: "\n").components(separatedBy: .newlines) {
            let compact = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if compact.isEmpty {
                if taskSectionRemaining > 0 { taskSectionRemaining -= 1 }
                continue
            }
            guard compact.count >= 3, compact.count <= 500 else { continue }

            let lower = compact.lowercased()
            let hasUncheckedMarker = lower.hasPrefix("- [ ]") || lower.hasPrefix("* [ ]") || compact.hasPrefix("☐")
            let structuralLine = cleanTaskTitle(compact, removingStatusPrefix: false)
            if isTaskSectionHeading(structuralLine) {
                taskSectionRemaining = 10
                continue
            }
            if compact.hasPrefix("#"), taskSectionRemaining > 0 {
                taskSectionRemaining = 0
            }

            let statusSignals = [
                "todo", "待办", "下一步", "未完成", "尚未", "还需要", "需要你", "需要手动",
                "待处理", "待确认", "待补充", "后续需要", "pending", "not run", "blocked"
            ]
            let futureSignals = ["提醒我", "稍后要", "之后要", "下次要", "记得要", "回头要", "remind me", "do later"]
            let completionSignals = ["已完成", "已经完成", "已实现", "已修复", "全部完成", "[x]", "☑", "completed", "done"]
            let optionalOfferSignals = ["如果你愿意", "如果需要", "如需", "我可以继续", "可以继续", "if you want", "if needed"]

            let statusPrefixed = statusSignals.contains(where: { hasSignalPrefix(structuralLine, signal: $0) })
            let future = futureSignals.contains(where: { lower.contains($0) })
            let completed = completionSignals.contains(where: { lower.contains($0) })
            let optionalOffer = optionalOfferSignals.contains(where: { lower.contains($0) })
            let listedInsideTaskSection = taskSectionRemaining > 0 && isListItem(compact)
            if taskSectionRemaining > 0 { taskSectionRemaining -= 1 }

            if role == "assistant" {
                guard hasUncheckedMarker || statusPrefixed || listedInsideTaskSection else { continue }
                guard !optionalOffer, !(completed && !hasUncheckedMarker) else { continue }
            } else {
                guard hasUncheckedMarker || future || listedInsideTaskSection else { continue }
                guard !(completed && !hasUncheckedMarker) else { continue }
            }

            let title = cleanTaskTitle(compact)
            guard title.count >= 3 else { continue }
            output.append(ExtractedTask(
                title: title,
                confidence: (hasUncheckedMarker || statusPrefixed || listedInsideTaskSection) ? .explicit : .possible
            ))
        }
        return output
    }

    private func isTaskSectionHeading(_ value: String) -> Bool {
        let normalized = value.lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: " :：-—"))
        return ["待办", "待办事项", "下一步", "后续动作", "todo", "todos", "next step", "next steps"]
            .contains(normalized)
    }

    private func hasSignalPrefix(_ value: String, signal: String) -> Bool {
        let lower = value.lowercased()
        guard lower.hasPrefix(signal) else { return false }
        guard lower.count > signal.count else { return true }
        let boundary = lower[lower.index(lower.startIndex, offsetBy: signal.count)]
        return " :：-—".contains(boundary)
    }

    private func isListItem(_ value: String) -> Bool {
        if ["- ", "* ", "• ", "☐ "].contains(where: value.hasPrefix) { return true }
        return value.range(of: #"^\d+[\.\)、]\s+"#, options: .regularExpression) != nil
    }

    private func cleanTaskTitle(_ source: String, removingStatusPrefix: Bool = true) -> String {
        var value = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let fixedPrefixes = ["- [ ] ", "* [ ] ", "☐ ", "- ", "* ", "• ", "> ", "### ", "## ", "# "]
        var removed = true
        while removed {
            removed = false
            for prefix in fixedPrefixes where value.hasPrefix(prefix) {
                value.removeFirst(prefix.count)
                value = value.trimmingCharacters(in: .whitespaces)
                removed = true
            }
        }
        if let range = value.range(of: #"^\d+[\.\)、]\s*"#, options: .regularExpression) {
            value.removeSubrange(range)
        }
        value = value.replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "`", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: " :-—。\t"))
        if removingStatusPrefix {
            for signal in ["后续需要", "需要手动", "需要你", "还需要", "下一步", "未完成", "尚未", "待处理", "待确认", "待补充", "pending", "not run", "blocked", "todo", "待办"] {
                guard hasSignalPrefix(value, signal: signal) else { continue }
                value.removeFirst(signal.count)
                value = value.trimmingCharacters(in: CharacterSet(charactersIn: " :：-—"))
                break
            }
        }
        if value.count > 140 {
            value = String(value.prefix(139)).trimmingCharacters(in: .whitespaces) + "…"
        }
        return value
    }

    private func normalizeForComparison(_ value: String) -> String {
        value.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
            .trimmingCharacters(in: .punctuationCharacters)
    }

    private func stableID(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(format: "%016llx", hash)
    }
}

extension AppPaths {
    static var codexTodoImportsFile: URL { supportDirectory.appendingPathComponent("codex-todo-imports.json") }
}

final class CodexTodoImportStore {
    private struct Snapshot: Codable { var importedIDs: Set<String> }
    private let fileURL: URL

    init(fileURL: URL = AppPaths.codexTodoImportsFile) {
        self.fileURL = fileURL
    }

    func loadIDs() -> Set<String> {
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data)
        else { return [] }
        return snapshot.importedIDs
    }

    func markImported(_ ids: Set<String>) throws {
        guard !ids.isEmpty else { return }
        var merged = loadIDs()
        merged.formUnion(ids)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(Snapshot(importedIDs: merged))
        try data.write(to: fileURL, options: .atomic)
    }
}
