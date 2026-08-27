import AVFoundation
import Foundation

enum AlertKind: String, Sendable {
    case completed
    case paused
}

struct AlertBatchAccumulator {
    private(set) var completed = 0
    private(set) var paused = 0

    mutating func add(_ kind: AlertKind, count: Int = 1) {
        guard count > 0 else { return }
        if kind == .paused { paused += count } else { completed += count }
    }

    mutating func drain() -> [(AlertKind, Int)] {
        var output: [(AlertKind, Int)] = []
        if paused > 0 { output.append((.paused, paused)) }
        if completed > 0 { output.append((.completed, completed)) }
        paused = 0
        completed = 0
        return output
    }
}

@MainActor
final class AudioNotifier: NSObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    private enum Playback {
        case speech(String)
        case audio(URL)
    }

    private let settings: AppSettings
    private var synthesizer: AVSpeechSynthesizer?
    private var player: AVAudioPlayer?
    private var accumulator = AlertBatchAccumulator()
    private var batchWorkItem: DispatchWorkItem?
    private var playbackQueue: [Playback] = []

    init(settings: AppSettings) {
        self.settings = settings
        super.init()
    }

    func enqueue(_ kind: AlertKind, count: Int = 1) {
        guard count > 0 else { return }
        accumulator.add(kind, count: count)
        batchWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.flushBatch() }
        batchWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: item)
    }

    func preview(_ kind: AlertKind) throws {
        let playback = try makePlayback(kind: kind, count: 1)
        playbackQueue.insert(playback, at: 0)
        playNextIfNeeded(force: true)
    }

    func validateAudio(at url: URL) throws {
        let supported = ["m4a", "mp3", "wav", "aiff", "aif", "caf"]
        guard supported.contains(url.pathExtension.lowercased()) else {
            throw AudioError.unsupported
        }
        let testPlayer = try AVAudioPlayer(contentsOf: url)
        guard testPlayer.duration > 0 else { throw AudioError.damaged }
    }

    private func flushBatch() {
        batchWorkItem = nil

        // 同批出现时先中断、后完成。
        for (kind, count) in accumulator.drain() {
            let enabled = kind == .paused ? settings.pauseEnabled : settings.completionEnabled
            if enabled, let item = try? makePlayback(kind: kind, count: count) {
                playbackQueue.append(item)
            }
        }
        playNextIfNeeded()
    }

    private func makePlayback(kind: AlertKind, count: Int) throws -> Playback {
        let mode = kind == .completed ? settings.completionMode : settings.pauseMode
        if mode == .system {
            let template = kind == .completed ? settings.completionText : settings.pauseText
            return .speech(template.replacingOccurrences(of: "{count}", with: "\(count)"))
        }
        let path = kind == .completed ? settings.completionAudioPath : settings.pauseAudioPath
        guard let path else { throw AudioError.audioNotSelected }
        let url = URL(fileURLWithPath: path)
        try validateAudio(at: url)
        return .audio(url)
    }

    private func playNextIfNeeded(force: Bool = false) {
        guard force || (synthesizer?.isSpeaking != true && player?.isPlaying != true) else { return }
        if force {
            synthesizer?.stopSpeaking(at: .immediate)
            player?.stop()
        }
        guard !playbackQueue.isEmpty else { return }
        let next = playbackQueue.removeFirst()
        switch next {
        case let .speech(text):
            let synthesizer = speechSynthesizer()
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = settings.selectedVoice
            utterance.volume = Float(settings.voiceVolume)
            utterance.rate = 0.47
            synthesizer.speak(utterance)
        case let .audio(url):
            do {
                player = try AVAudioPlayer(contentsOf: url)
                player?.delegate = self
                player?.volume = Float(settings.voiceVolume)
                player?.prepareToPlay()
                player?.play()
            } catch {
                playNextIfNeeded()
            }
        }
    }

    private func speechSynthesizer() -> AVSpeechSynthesizer {
        if let synthesizer { return synthesizer }
        let created = AVSpeechSynthesizer()
        created.delegate = self
        synthesizer = created
        return created
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.playNextIfNeeded() }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.playNextIfNeeded() }
    }
}

enum AudioError: LocalizedError {
    case unsupported
    case damaged
    case audioNotSelected

    var errorDescription: String? {
        switch self {
        case .unsupported: return AppLocalization.text("仅支持 m4a、mp3、wav、aiff 和 caf 音频")
        case .damaged: return AppLocalization.text("音频文件已损坏或无法播放")
        case .audioNotSelected: return AppLocalization.text("请先录制或选择一段提醒音频")
        }
    }
}
