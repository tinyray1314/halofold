import Foundation
import Speech

@MainActor
final class LocalSpeechTranscriber {
    private var recognitionTask: SFSpeechRecognitionTask?

    var authorizationNeedsPrompt: Bool {
        SFSpeechRecognizer.authorizationStatus() == .notDetermined
    }

    func transcribe(audioAt url: URL) async throws -> String {
        guard await authorizationGranted() else {
            throw FunVoiceError.speechRecognitionPermissionDenied
        }
        guard let recognizer = SFSpeechRecognizer(locale: AppLocalization.speechLocale),
              recognizer.isAvailable,
              recognizer.supportsOnDeviceRecognition
        else {
            throw FunVoiceError.onDeviceRecognitionUnavailable
        }

        recognitionTask?.cancel()
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        request.requiresOnDeviceRecognition = true

        return try await withCheckedThrowingContinuation { continuation in
            var completed = false
            recognitionTask = recognizer.recognitionTask(with: request) { result, error in
                guard !completed else { return }
                if let result, result.isFinal {
                    completed = true
                    let text = result.bestTranscription.formattedString
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(returning: text)
                } else if error != nil {
                    completed = true
                    continuation.resume(throwing: FunVoiceError.transcriptionFailed)
                }
            }
        }
    }

    private func authorizationGranted() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }
}
