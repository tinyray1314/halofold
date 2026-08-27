import Foundation

struct OfficialUsageResult: Sendable {
    let remainingPercent: Double
    let resetAt: Date?
    let fetchedAt: Date
}

enum CodexUsageError: LocalizedError {
    case binaryNotFound
    case timedOut
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .binaryNotFound: return AppLocalization.text("找不到 Codex app-server")
        case .timedOut: return AppLocalization.text("Codex 用量接口响应超时")
        case .invalidResponse: return AppLocalization.text("Codex 用量接口返回了无法识别的数据")
        }
    }
}

final class CodexUsageClient {
    func readWeeklyUsage(completion: @escaping (Result<OfficialUsageResult, Error>) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            completion(Result { try self.performRead() })
        }
    }

    func performRead() throws -> OfficialUsageResult {
        // The local build intentionally runs without App Sandbox so it can ask the
        // installed Codex app-server for the currently signed-in account's rate limit.
        // Keep the guard so a future sandboxed build fails closed instead of showing
        // another local snapshot as if it were the official account value.
        if CodexDataAccess.shared.isSandboxed { throw CodexUsageError.binaryNotFound }
        guard let binary = locateBinary() else { throw CodexUsageError.binaryNotFound }
        let process = Process()
        let output = Pipe()
        let input = Pipe()
        let errorOutput = Pipe()
        process.executableURL = binary
        process.arguments = ["app-server", "--listen", "stdio://"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errorOutput

        try process.run()

        let requests: [[String: Any]] = [
            ["id": 1, "method": "initialize", "params": ["clientInfo": ["name": "halofold", "title": "Halofold", "version": "1.0.0"]]],
            ["method": "initialized", "params": [:]],
            ["id": 2, "method": "account/rateLimits/read"]
        ]
        for request in requests {
            let data = try JSONSerialization.data(withJSONObject: request)
            input.fileHandleForWriting.write(data)
            input.fileHandleForWriting.write(Data([0x0A]))
        }
        // app-server 是长连接服务，不会主动退出。监听 stdout，拿到目标响应后立即返回，
        // 而不是等待进程结束；否则即使结果已经到达也会错误超时。
        let responseReady = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var buffer = Data()
        var parsedResult: OfficialUsageResult?
        output.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            lock.lock()
            defer { lock.unlock() }
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer.prefix(upTo: newline)
                buffer.removeSubrange(...newline)
                guard
                    let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                    (object["id"] as? NSNumber)?.intValue == 2,
                    let result = object["result"] as? [String: Any],
                    let value = Self.parseRateLimits(result)
                else { continue }
                parsedResult = value
                responseReady.signal()
                return
            }
        }
        guard responseReady.wait(timeout: .now() + 9) == .success else {
            output.fileHandleForReading.readabilityHandler = nil
            try? input.fileHandleForWriting.close()
            process.terminate()
            throw CodexUsageError.timedOut
        }
        output.fileHandleForReading.readabilityHandler = nil
        try? input.fileHandleForWriting.close()
        process.terminate()
        lock.lock()
        let result = parsedResult
        lock.unlock()
        guard let result else { throw CodexUsageError.invalidResponse }
        return result
    }

    static func parseRateLimits(_ result: [String: Any], now: Date = Date()) -> OfficialUsageResult? {
        var candidates: [(id: String, bucket: [String: Any])] = []
        if let buckets = result["rateLimitsByLimitId"] as? [String: Any] {
            for (id, value) in buckets {
                if let bucket = value as? [String: Any] { candidates.append((id, bucket)) }
            }
        }
        if let legacy = result["rateLimits"] as? [String: Any] {
            let id = (legacy["limitId"] as? String) ?? (legacy["limit_id"] as? String) ?? ""
            candidates.append((id, legacy))
        }
        if candidates.isEmpty { candidates.append(("", result)) }

        let weekly = candidates.compactMap { item -> (id: String, primary: [String: Any], duration: Double)? in
            guard let primary = item.bucket["primary"] as? [String: Any],
                  let duration = number(primary["windowDurationMins"] ?? primary["window_duration_mins"]),
                  duration >= 7 * 24 * 60 - 1
            else { return nil }
            return (item.id, primary, duration)
        }
        // `codex` 是账户主额度。其它具名桶（例如 Spark）可能也有独立 7 天窗口，不能替代主额度。
        let selected = weekly.first(where: { $0.id == "codex" })
            ?? weekly.sorted { abs($0.duration - 10080) < abs($1.duration - 10080) }.first
        guard let selected,
              let used = number(selected.primary["usedPercent"] ?? selected.primary["used_percent"])
        else { return nil }
        let resetSeconds = number(selected.primary["resetsAt"] ?? selected.primary["resets_at"])
        return OfficialUsageResult(
            remainingPercent: min(100, max(0, 100 - used)),
            resetAt: resetSeconds.map { Date(timeIntervalSince1970: $0) },
            fetchedAt: now
        )
    }

    private func locateBinary() -> URL? {
        let candidates = [
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex"
        ]
        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }).map(URL.init(fileURLWithPath:))
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? NSNumber { return value.doubleValue }
        return nil
    }
}
