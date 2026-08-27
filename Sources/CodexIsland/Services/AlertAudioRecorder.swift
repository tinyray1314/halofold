import AVFoundation
import Foundation

@MainActor
final class LocalAudioRecorder {
    private let audioDirectory: URL
    private var recorder: AVAudioRecorder?
    private var temporaryURL: URL?

    init(audioDirectory: URL = AppPaths.audioDirectory) {
        self.audioDirectory = audioDirectory
    }

    var microphonePermissionNeedsPrompt: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined
    }

    func start(filePrefix: String) async throws {
        guard recorder == nil else { throw AudioRecordingError.alreadyRecording }
        guard await microphoneAccessGranted() else { throw AudioRecordingError.microphonePermissionDenied }

        try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        let url = audioDirectory.appendingPathComponent("recording-\(filePrefix)-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            AVEncoderBitRateKey: 128_000
        ]

        do {
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            guard recorder.prepareToRecord(), recorder.record() else {
                throw AudioRecordingError.couldNotStart
            }
            self.recorder = recorder
            temporaryURL = url
        } catch {
            try? FileManager.default.removeItem(at: url)
            if let recordingError = error as? AudioRecordingError { throw recordingError }
            throw AudioRecordingError.couldNotStart
        }
    }

    func stop() throws -> URL {
        guard let recorder, let temporaryURL else {
            throw AudioRecordingError.notRecording
        }
        recorder.stop()
        self.recorder = nil
        self.temporaryURL = nil

        guard FileManager.default.fileExists(atPath: temporaryURL.path) else {
            throw AudioRecordingError.recordingMissing
        }
        return temporaryURL
    }

    func cancel() {
        recorder?.stop()
        recorder = nil
        if let temporaryURL {
            try? FileManager.default.removeItem(at: temporaryURL)
        }
        temporaryURL = nil
    }

    private func microphoneAccessGranted() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }
}

enum AudioRecordingError: LocalizedError {
    case alreadyRecording
    case notRecording
    case microphonePermissionDenied
    case couldNotStart
    case recordingMissing

    var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            return AppLocalization.text("已有一项提醒正在录音")
        case .notRecording:
            return AppLocalization.text("当前没有正在进行的录音")
        case .microphonePermissionDenied:
            return AppLocalization.text("请在“系统设置 → 隐私与安全性 → 麦克风”中允许 Halofold 录音")
        case .couldNotStart:
            return AppLocalization.text("无法开始录音，请检查麦克风是否可用")
        case .recordingMissing:
            return AppLocalization.text("录音文件没有成功生成，请重新录制")
        }
    }
}
