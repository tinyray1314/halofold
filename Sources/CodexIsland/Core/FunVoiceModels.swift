import AVFoundation
import Foundation

enum FunVoicePreset: String, CaseIterable, Identifiable, Sendable {
    case lively
    case cartoon
    case uncle
    case slowMotion
    case brisk

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lively: return AppLocalization.text("活力播报")
        case .cartoon: return AppLocalization.text("卡通高音")
        case .uncle: return AppLocalization.text("憨厚伯伯")
        case .slowMotion: return AppLocalization.text("慢动作")
        case .brisk: return AppLocalization.text("快嘴助手")
        }
    }

    var subtitle: String {
        switch self {
        case .lively: return AppLocalization.text("稍快、明亮，适合日常提醒")
        case .cartoon: return AppLocalization.text("更高音调，轻松夸张")
        case .uncle: return AppLocalization.text("更低沉、稍慢")
        case .slowMotion: return AppLocalization.text("拉长节奏，有点无厘头")
        case .brisk: return AppLocalization.text("更快的工具型播报")
        }
    }

    var rate: Float {
        switch self {
        case .lively: return 0.52
        case .cartoon: return 0.48
        case .uncle: return 0.40
        case .slowMotion: return 0.34
        case .brisk: return 0.60
        }
    }

    var pitchMultiplier: Float {
        switch self {
        case .lively: return 1.12
        case .cartoon: return 1.55
        case .uncle: return 0.72
        case .slowMotion: return 0.88
        case .brisk: return 1.02
        }
    }

    func makeUtterance(text: String, voice: AVSpeechSynthesisVoice?, volume: Float) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.volume = volume
        utterance.rate = rate
        utterance.pitchMultiplier = pitchMultiplier
        return utterance
    }
}

enum FunVoiceError: LocalizedError {
    case emptyText
    case couldNotCreateAudio
    case speechRecognitionPermissionDenied
    case onDeviceRecognitionUnavailable
    case transcriptionFailed
    case emptyTranscription

    var errorDescription: String? {
        switch self {
        case .emptyText: return AppLocalization.text("请先输入文案，或录音转成文案")
        case .couldNotCreateAudio: return AppLocalization.text("趣味语音生成失败，请换一个系统音色再试")
        case .speechRecognitionPermissionDenied:
            return AppLocalization.text("请在“系统设置 → 隐私与安全性 → 语音识别”中允许 Halofold")
        case .onDeviceRecognitionUnavailable:
            return AppLocalization.text("这台 Mac 当前没有可用的本机语音识别，可先直接输入文案")
        case .transcriptionFailed: return AppLocalization.text("未能识别这段录音，请靠近麦克风重试")
        case .emptyTranscription: return AppLocalization.text("没有识别到可用文字")
        }
    }
}
