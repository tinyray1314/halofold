import Foundation

struct CodexActionRequest: Equatable, Sendable {
    let prompt: String
}

/// Classifies only the final assistant answer immediately preceding a completed turn.
/// The rules are intentionally strict: optional offers and general advice remain normal completions.
struct CodexActionRequestDetector {
    private let maximumBytes = 1_000_000

    func detect(in url: URL) -> CodexActionRequest? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let end = (try? handle.seekToEnd()) ?? 0
        let start = end > UInt64(maximumBytes) ? end - UInt64(maximumBytes) : 0
        try? handle.seek(toOffset: start)
        guard var data = try? handle.readToEnd() else { return nil }
        if start > 0, let newline = data.firstIndex(of: 0x0A) {
            data.removeSubrange(data.startIndex...newline)
        }
        return detect(in: data)
    }

    func detect(in data: Data) -> CodexActionRequest? {
        var latestFinalAnswer: String?
        var result: CodexActionRequest?

        for rawLine in data.split(separator: 0x0A, omittingEmptySubsequences: true) {
            guard let root = try? JSONSerialization.jsonObject(with: Data(rawLine)) as? [String: Any],
                  let type = root["type"] as? String,
                  let payload = root["payload"] as? [String: Any]
            else { continue }

            if type == "event_msg", let eventType = payload["type"] as? String {
                if eventType == "task_started" { latestFinalAnswer = nil }
                if eventType == "task_complete" {
                    result = latestFinalAnswer.flatMap(classify)
                }
                continue
            }

            guard type == "response_item",
                  payload["type"] as? String == "message",
                  payload["role"] as? String == "assistant",
                  payload["phase"] as? String == "final_answer",
                  let content = payload["content"] as? [[String: Any]]
            else { continue }
            let text = content.compactMap { item -> String? in
                guard item["type"] as? String == "output_text" else { return nil }
                return item["text"] as? String
            }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            latestFinalAnswer = text.isEmpty ? nil : text
        }
        return result
    }

    private enum ActionKind {
        case login, confirmation, authorization, selection, information, security, generic
    }

    private func classify(_ text: String) -> CodexActionRequest? {
        let optionalSignals = [
            "如果你愿意", "如果需要", "如需", "我可以继续", "可以继续",
            "if you want", "if needed", "i can continue"
        ]
        let directionSignals = [
            "需要你", "请你", "请先", "请在", "请确认", "请登录", "请授权", "请批准",
            "请提供", "请补充", "请上传", "请下载", "请完成", "等待你", "麻烦你", "你需要",
            "please", "need you to", "you need to", "waiting for you"
        ]

        let candidates = text.replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .newlines)
            .map(cleanLine)
            .filter { !$0.isEmpty }

        for line in candidates {
            let lower = line.lowercased()
            guard directionSignals.contains(where: lower.contains),
                  !optionalSignals.contains(where: lower.contains),
                  let kind = actionKind(in: lower)
            else { continue }
            return CodexActionRequest(prompt: prompt(for: kind))
        }
        return nil
    }

    private func actionKind(in text: String) -> ActionKind? {
        if containsAny(text, ["验证码", "密码", "口令", "otp", "2fa", "verification code", "recovery code"]) { return .security }
        if containsAny(text, ["登录", "登陆", "sign in", "log in", "login"]) { return .login }
        if containsAny(text, ["授权", "批准", "允许", "authorize", "approve", "permission"]) { return .authorization }
        if containsAny(text, ["确认", "核对", "confirm", "verify"]) { return .confirmation }
        if containsAny(text, ["选择", "选一个", "决定", "choose", "select", "decide"]) { return .selection }
        if containsAny(text, ["提供", "补充", "输入", "上传", "下载", "填写", "provide", "enter", "upload", "fill in"]) { return .information }
        if containsAny(text, ["处理", "完成操作", "take action"]) { return .generic }
        return nil
    }

    private func prompt(for kind: ActionKind) -> String {
        switch kind {
        case .login: return AppLocalization.text("Codex 需要你登录账号")
        case .confirmation: return AppLocalization.text("Codex 需要你确认信息")
        case .authorization: return AppLocalization.text("Codex 需要你完成授权")
        case .selection: return AppLocalization.text("Codex 需要你完成选择")
        case .information: return AppLocalization.text("Codex 需要你补充信息")
        case .security: return AppLocalization.text("Codex 需要你完成安全验证，请打开查看")
        case .generic: return AppLocalization.text("Codex 有一项任务需要你处理，请打开查看")
        }
    }

    private func containsAny(_ text: String, _ signals: [String]) -> Bool {
        signals.contains(where: text.contains)
    }

    private func cleanLine(_ source: String) -> String {
        source.replacingOccurrences(of: #"^\s*(?:[-*•>]|\d+[\.、\)])\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "`", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
