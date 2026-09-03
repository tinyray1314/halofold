import Foundation

protocol CodexEventSource: AnyObject {
    func start(
        snapshot: TrackerSnapshot,
        isFirstLaunch: Bool,
        handler: @escaping (CodexSourceUpdate) -> Void
    )
    func stop()
}

enum CodexSourceUpdate: Sendable {
    case bootstrap(
        active: [ConversationRecord],
        checkpoints: [String: FileCheckpoint],
        todayTokens: Int,
        metadata: [ThreadMetadata]
    )
    case todayTokenBaseline(Int)
    case activity(
        metadata: ThreadMetadata,
        signals: [CodexSignal],
        checkpoint: FileCheckpoint
    )
    case metadata([ThreadMetadata], scannedAt: Date)
    case localRateLimit(usedPercent: Double, resetsAt: Date?, at: Date)
    case failed(String)
}

final class LocalCodexEventSource: CodexEventSource {
    private let queue = DispatchQueue(label: "com.tinyray.halofold.events", qos: .utility)
    private let parser = CodexEventParser()
    private let actionRequestDetector = CodexActionRequestDetector()
    private let database: CodexDatabase
    private var timer: DispatchSourceTimer?
    private var checkpoints: [String: FileCheckpoint] = [:]
    private var monitoredPaths: Set<String> = []
    private var metadataByID: [String: ThreadMetadata] = [:]
    private var installedAt = Date()
    private var lastDatabaseScanAt = Date()
    private var handler: ((CodexSourceUpdate) -> Void)?

    init(database: CodexDatabase = CodexDatabase()) {
        self.database = database
    }

    func start(
        snapshot: TrackerSnapshot,
        isFirstLaunch: Bool,
        handler: @escaping (CodexSourceUpdate) -> Void
    ) {
        queue.async { [weak self] in
            guard let self else { return }
            self.handler = handler
            let persistedPaths = Set(snapshot.records.values.map(\.rolloutPath))
            self.checkpoints = snapshot.checkpoints.filter { persistedPaths.contains($0.key) }
            self.monitoredPaths = Set(snapshot.records.values.filter { $0.state == .running }.map(\.rolloutPath))
            self.installedAt = snapshot.installedAt
            self.lastDatabaseScanAt = snapshot.lastDatabaseScanAt

            do {
                if isFirstLaunch {
                    try self.bootstrapFirstLaunch()
                } else {
                    let metadata = try self.database.recentThreads(limit: 500, includingArchived: true)
                    self.metadataByID = Dictionary(uniqueKeysWithValues: metadata.map { ($0.id, $0) })
                    self.handler?(.metadata(metadata, scannedAt: Date()))
                    self.emitLatestLocalRateLimit(in: metadata)
                }
            } catch {
                self.handler?(.failed(AppLocalization.format("读取 Codex 本地状态失败：%@", error.localizedDescription)))
            }
            self.startTimer()
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.timer?.cancel()
            self?.timer = nil
            self?.handler = nil
        }
    }

    private func bootstrapFirstLaunch() throws {
        let loadedThreadIDs = currentWriterLockThreadIDs()
        let recent = try database.recentThreads(limit: 500, includingArchived: false)
            .filter { loadedThreadIDs.contains($0.id) }
        let startOfToday = Calendar.current.startOfDay(for: Date())
        let touchedToday = try database.threads(updatedAfter: startOfToday)
        var merged: [String: ThreadMetadata] = [:]
        for item in recent + touchedToday { merged[item.id] = item }
        let metadata = Array(merged.values)
        metadataByID = merged
        var active: [ConversationRecord] = []
        var initialFileSizes: [String: UInt64] = [:]

        for thread in metadata where !thread.rolloutPath.isEmpty {
            let url = URL(fileURLWithPath: thread.rolloutPath)
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let fileSize = (attributes[.size] as? NSNumber)?.uint64Value
            else { continue }
            initialFileSizes[thread.rolloutPath] = fileSize

            if !thread.archived,
               let lifecycle = newestLifecycleSignal(in: url),
               case let .taskStarted(_, date) = lifecycle
            {
                checkpoints[thread.rolloutPath] = FileCheckpoint(offset: fileSize)
                monitoredPaths.insert(thread.rolloutPath)
                active.append(ConversationRecord(
                    id: thread.id,
                    title: thread.title,
                    rolloutPath: thread.rolloutPath,
                    state: .running,
                    updatedAt: date,
                    turnStartedAt: date,
                    isArchived: false,
                    kind: thread.kind,
                    parentThreadID: thread.parentThreadID
                ))
            }

        }

        lastDatabaseScanAt = Date()
        handler?(.bootstrap(
            active: active,
            checkpoints: checkpoints,
            todayTokens: 0,
            metadata: metadata
        ))
        emitLatestLocalRateLimit(in: metadata)

        // 状态先返回，确保首屏在 2 秒内出现；今日 Token 基线随后独立计算。
        let tokenFiles = Dictionary(uniqueKeysWithValues: touchedToday.compactMap { thread -> (String, UInt64)? in
            guard let size = initialFileSizes[thread.rolloutPath] else { return nil }
            return (thread.rolloutPath, size)
        })
        let todayTokens = TodayTokenBaselineScanner().scan(files: tokenFiles, day: Date())
        handler?(.todayTokenBaseline(todayTokens))
    }

    private func currentWriterLockThreadIDs() -> Set<String> {
        guard let directory = database.codexDirectory?
            .appendingPathComponent("thread-writer-locks", isDirectory: true) else { return [] }
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return Set(files.compactMap { url in
            guard url.pathExtension == "lock" else { return nil }
            let value = url.deletingPathExtension().lastPathComponent
            return UUID(uuidString: value) == nil ? nil : value
        })
    }

    private func startTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 0.7, repeating: 1.0, leeway: .milliseconds(180))
        timer.setEventHandler { [weak self] in self?.poll() }
        timer.resume()
        self.timer = timer
    }

    private func poll() {
        do {
            let scanStart = Date()
            let overlap = lastDatabaseScanAt.addingTimeInterval(-3)
            let changed = try database.threads(updatedAfter: overlap)
            for item in changed { metadataByID[item.id] = item }
            lastDatabaseScanAt = scanStart
            if !changed.isEmpty {
                handler?(.metadata(changed, scannedAt: scanStart))
            }

            var candidates = changed
            let knownIDs = Set(candidates.map(\.id))
            candidates.append(contentsOf: metadataByID.values.filter {
                monitoredPaths.contains($0.rolloutPath) && !knownIDs.contains($0.id)
            })

            for item in candidates where !item.rolloutPath.isEmpty {
                readNewActivity(for: item)
            }
        } catch {
            handler?(.failed(AppLocalization.format("Codex 状态监听暂时不可用：%@", error.localizedDescription)))
        }
    }

    private func readNewActivity(for metadata: ThreadMetadata) {
        let url = URL(fileURLWithPath: metadata.rolloutPath)
        guard let size = fileSize(at: url) else { return }

        if checkpoints[metadata.rolloutPath] == nil {
            let signals = classifyLatestCompletion(in: signals(in: url, since: installedAt), rolloutURL: url)
            let checkpoint = FileCheckpoint(offset: size)
            checkpoints[metadata.rolloutPath] = checkpoint
            if !signals.isEmpty {
                updateMonitoring(path: metadata.rolloutPath, signals: signals)
                handler?(.activity(metadata: metadata, signals: signals, checkpoint: checkpoint))
            }
            return
        }

        guard var checkpoint = checkpoints[metadata.rolloutPath] else { return }
        if size < checkpoint.offset {
            checkpoint = FileCheckpoint()
        }
        guard size > checkpoint.offset else { return }

        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            try handle.seek(toOffset: checkpoint.offset)
            let data = try handle.readToEnd() ?? Data()
            guard let newline = data.lastIndex(of: 0x0A) else { return }
            let complete = data.prefix(through: newline)
            let parsedSignals = complete.split(separator: 0x0A, omittingEmptySubsequences: true)
                .flatMap { parser.parseAll(line: Data($0)) }
            let signals = classifyLatestCompletion(in: parsedSignals, rolloutURL: url)
            checkpoint.offset += UInt64(complete.count)
            checkpoints[metadata.rolloutPath] = checkpoint
            if !signals.isEmpty {
                updateMonitoring(path: metadata.rolloutPath, signals: signals)
                handler?(.activity(metadata: metadata, signals: signals, checkpoint: checkpoint))
            }
        } catch {
            handler?(.failed(AppLocalization.format("无法读取对话“%@”的新事件", metadata.title)))
        }
    }

    private func updateMonitoring(path: String, signals: [CodexSignal]) {
        for signal in signals {
            switch signal {
            case .taskStarted:
                monitoredPaths.insert(path)
            case .taskNeedsAction, .taskCompleted, .taskPaused:
                monitoredPaths.remove(path)
            case .tokenDelta, .localRateLimit:
                break
            }
        }
    }

    private func newestLifecycleSignal(in url: URL) -> CodexSignal? {
        var result: CodexSignal?
        enumerateLinesBackwards(in: url) { line in
            for signal in parser.parseAll(line: line) {
                switch signal {
                case .taskStarted, .taskNeedsAction, .taskCompleted, .taskPaused:
                    result = signal
                    return false
                case .tokenDelta, .localRateLimit:
                    continue
                }
            }
            return true
        }
        return result
    }

    private func emitLatestLocalRateLimit(in metadata: [ThreadMetadata]) {
        var latest: (used: Double, reset: Date?, date: Date)?
        // The database is ordered by update time. A bounded scan keeps startup fast while
        // still covering the latest Codex work across normal tasks and automations.
        for thread in metadata.prefix(100) where !thread.rolloutPath.isEmpty {
            let url = URL(fileURLWithPath: thread.rolloutPath)
            var found: (used: Double, reset: Date?, date: Date)?
            enumerateLinesBackwards(in: url) { line in
                for signal in parser.parseAll(line: line) {
                    if case let .localRateLimit(used, reset, date) = signal {
                        found = (used, reset, date)
                        return false
                    }
                }
                return true
            }
            if let found, latest == nil || found.date > latest!.date { latest = found }
        }
        if let latest {
            handler?(.localRateLimit(usedPercent: latest.used, resetsAt: latest.reset, at: latest.date))
        }
    }

    private func signals(in url: URL, since date: Date) -> [CodexSignal] {
        var result: [CodexSignal] = []
        enumerateLinesBackwards(in: url) { line in
            guard let timestamp = parser.timestamp(line: line) else { return true }
            if timestamp < date { return false }
            result.append(contentsOf: parser.parseAll(line: line))
            return true
        }
        return result.reversed()
    }

    private func classifyLatestCompletion(in signals: [CodexSignal], rolloutURL: URL) -> [CodexSignal] {
        guard let index = signals.lastIndex(where: {
            if case .taskCompleted = $0 { return true }
            return false
        }), let request = actionRequestDetector.detect(in: rolloutURL)
        else { return signals }

        var classified = signals
        if case let .taskCompleted(date) = classified[index] {
            classified[index] = .taskNeedsAction(prompt: request.prompt, at: date)
        }
        return classified
    }

    private func enumerateLinesBackwards(in url: URL, endingAt requestedEnd: UInt64? = nil, visit: (Data) -> Bool) {
        guard let handle = try? FileHandle(forReadingFrom: url),
              let fullSize = try? handle.seekToEnd()
        else { return }
        defer { try? handle.close() }

        let chunkSize: UInt64 = 128 * 1024
        let maximumUsefulLineBytes = 256 * 1024
        let size = min(requestedEnd ?? fullSize, fullSize)
        var position = size
        var carry = Data()
        var skippingOversizedLine = false
        var shouldContinue = true

        while position > 0 && shouldContinue {
            let start = position > chunkSize ? position - chunkSize : 0
            let length = Int(position - start)
            do {
                try handle.seek(toOffset: start)
                let chunk = try handle.read(upToCount: length) ?? Data()
                var combined = chunk
                combined.append(carry)
                let parts = combined.split(separator: 0x0A, omittingEmptySubsequences: false)
                if start > 0 {
                    if parts.count == 1, combined.count > maximumUsefulLineBytes {
                        // Codex 的提示或工具结果可能是一条数 MB 的 JSON。token_count 与生命周期
                        // 事件远小于该阈值，因此无需为了无关大行持续保留整段字节。
                        carry.removeAll(keepingCapacity: false)
                        skippingOversizedLine = true
                        position = start
                        continue
                    }
                    carry = Data(parts.first ?? Data.SubSequence())
                    var completeParts = Array(parts.dropFirst())
                    if skippingOversizedLine, !completeParts.isEmpty {
                        completeParts.removeLast()
                        skippingOversizedLine = false
                    }
                    for part in completeParts.reversed() where !part.isEmpty {
                        let keepGoing = autoreleasepool { visit(Data(part)) }
                        if !keepGoing { shouldContinue = false; break }
                    }
                } else {
                    for part in parts.reversed() where !part.isEmpty {
                        let keepGoing = autoreleasepool { visit(Data(part)) }
                        if !keepGoing { shouldContinue = false; break }
                    }
                }
                position = start
            } catch {
                return
            }
        }
    }

    private func fileSize(at url: URL) -> UInt64? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        return (attributes[.size] as? NSNumber)?.uint64Value
    }
}

private struct TodayTokenBaselineScanner {
    func scan(files: [String: UInt64], day: Date) -> Int {
        guard !files.isEmpty else { return 0 }
        let start = Calendar.current.startOfDay(for: day)
        guard let end = Calendar.current.date(byAdding: .day, value: 1, to: start) else { return 0 }
        let parser = CodexEventParser()
        var total = 0
        for (path, requestedLength) in files {
            guard let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else { continue }
            defer { try? handle.close() }
            var remaining = requestedLength
            var carry = Data()
            while remaining > 0 {
                let chunkSize = Int(min(remaining, 128 * 1024))
                guard let chunk = try? handle.read(upToCount: chunkSize), !chunk.isEmpty else { break }
                remaining -= UInt64(chunk.count)
                carry.append(chunk)
                let lines = carry.split(separator: 0x0A, omittingEmptySubsequences: false)
                carry = Data(lines.last ?? Data.SubSequence())
                for line in lines.dropLast() {
                    for signal in parser.parseAll(line: Data(line)) {
                        if case let .tokenDelta(value, date) = signal, date >= start, date < end { total += value }
                    }
                }
            }
            if !carry.isEmpty {
                for signal in parser.parseAll(line: carry) {
                    if case let .tokenDelta(value, date) = signal, date >= start, date < end { total += value }
                }
            }
        }
        return total
    }
}
