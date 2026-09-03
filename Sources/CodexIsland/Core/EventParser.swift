import Foundation

struct CodexEventParser {
    private static let relevantMarkers: [Data] = [
        "\"task_started\"", "\"task_complete\"", "\"turn_aborted\"",
        "\"stream_error\"", "\"token_count\"", "\"type\":\"error\""
    ].map { Data($0.utf8) }
    private static let tokenMarker = Data("\"token_count\"".utf8)

    func parse(line: Data) -> CodexSignal? {
        parseAll(line: line).first
    }

    func parseAll(line: Data) -> [CodexSignal] {
        guard Self.relevantMarkers.contains(where: { line.range(of: $0) != nil }) else { return [] }
        guard
            let root = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
            let timestamp = root["timestamp"] as? String,
            let date = ISO8601DateFormatter.parseCodex(timestamp),
            let type = root["type"] as? String
        else { return [] }

        guard type == "event_msg", let payload = root["payload"] as? [String: Any] else {
            return []
        }

        switch payload["type"] as? String {
        case "task_started":
            return [.taskStarted(turnID: payload["turn_id"] as? String, at: date)]
        case "task_complete":
            return [.taskCompleted(at: date)]
        case "turn_aborted":
            return [.taskPaused(reason: pauseReason(from: payload, fallback: AppLocalization.text("任务已中断")), at: date)]
        case "error", "stream_error":
            if (payload["will_retry"] as? Bool) == true || (payload["retryable"] as? Bool) == true {
                return []
            }
            return [.taskPaused(reason: pauseReason(from: payload, fallback: AppLocalization.text("Codex 系统错误")), at: date)]
        case "token_count":
            return parseTokenCount(payload: payload, at: date)
        default:
            return []
        }
    }

    func timestamp(line: Data) -> Date? {
        // Codex JSONL 以 timestamp 开头；这里只解码很短的前缀，避免为普通长消息构造完整 JSON 树。
        let prefix = String(decoding: line.prefix(96), as: UTF8.self)
        guard let marker = prefix.range(of: "\"timestamp\":\"") else { return nil }
        let remainder = prefix[marker.upperBound...]
        guard let quote = remainder.firstIndex(of: "\"") else { return nil }
        let value = String(remainder[..<quote])
        return ISO8601DateFormatter.parseCodex(value)
    }

    func tokenDelta(line: Data) -> (date: Date, tokens: Int)? {
        guard line.range(of: Self.tokenMarker) != nil else { return nil }
        guard
            let root = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
            let timestamp = root["timestamp"] as? String,
            let date = ISO8601DateFormatter.parseCodex(timestamp),
            (root["type"] as? String) == "event_msg",
            let payload = root["payload"] as? [String: Any],
            (payload["type"] as? String) == "token_count",
            let info = payload["info"] as? [String: Any],
            let usage = info["last_token_usage"] as? [String: Any],
            let total = integer(usage["total_tokens"]),
            total > 0
        else { return nil }
        return (date, total)
    }

    private func parseTokenCount(payload: [String: Any], at date: Date) -> [CodexSignal] {
        let info = payload["info"] as? [String: Any] ?? [:]
        var signals: [CodexSignal] = []

        if
            let lastUsage = info["last_token_usage"] as? [String: Any],
            let total = integer(lastUsage["total_tokens"]),
            total > 0
        {
            signals.append(.tokenDelta(total, at: date))
        }

        // Current Codex logs place `rate_limits` beside `info`. Keep the old
        // nested location as a compatibility fallback for earlier logs.
        if
            let rateLimits = (payload["rate_limits"] as? [String: Any])
                ?? (info["rate_limits"] as? [String: Any]),
            let primary = rateLimits["primary"] as? [String: Any],
            let usedPercent = double(primary["used_percent"])
        {
            let reset = double(primary["resets_at"]).map { Date(timeIntervalSince1970: $0) }
            signals.append(.localRateLimit(usedPercent: usedPercent, resetsAt: reset, at: date))
        }
        return signals
    }

    private func pauseReason(from payload: [String: Any], fallback: String) -> String {
        for key in ["message", "reason", "error"] {
            if let value = payload[key] as? String, !value.isEmpty { return value }
            if let value = payload[key] as? [String: Any], let message = value["message"] as? String {
                return message
            }
        }
        return fallback
    }

    private func integer(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }

    private func double(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? NSNumber { return value.doubleValue }
        return nil
    }
}

struct ConversationReducer {
    static func apply(
        _ signal: CodexSignal,
        to record: inout ConversationRecord
    ) -> ConversationState? {
        let previous = record.state
        switch signal {
        case let .taskStarted(_, date):
            record.state = .running
            record.turnStartedAt = date
            record.updatedAt = date
            record.pauseReason = nil
            record.actionPrompt = nil
            record.isCompletionUnread = false
        case let .taskNeedsAction(prompt, date):
            record.state = .needsAction
            record.updatedAt = date
            record.pauseReason = nil
            record.actionPrompt = prompt
            record.isCompletionUnread = false
        case let .taskCompleted(date):
            record.state = .completed
            record.updatedAt = date
            record.pauseReason = nil
            record.actionPrompt = nil
            record.isCompletionUnread = true
        case let .taskPaused(reason, date):
            record.state = .paused
            record.updatedAt = date
            record.pauseReason = reason
            record.actionPrompt = nil
            record.isCompletionUnread = false
        case .tokenDelta, .localRateLimit:
            return nil
        }
        return previous == record.state ? nil : record.state
    }
}
