import AVFoundation
import Foundation

@MainActor
final class FunVoiceGenerator {
    private var previewSynthesizer: AVSpeechSynthesizer?

    func preview(text: String, preset: FunVoicePreset, voice: AVSpeechSynthesisVoice?, volume: Float) throws {
        let cleaned = try preparedText(text)
        previewSynthesizer?.stopSpeaking(at: .immediate)
        let synthesizer = AVSpeechSynthesizer()
        previewSynthesizer = synthesizer
        synthesizer.speak(preset.makeUtterance(text: cleaned, voice: voice, volume: volume))
    }

    func render(
        text: String,
        preset: FunVoicePreset,
        voice: AVSpeechSynthesisVoice?,
        volume: Float,
        to destination: URL
    ) async throws {
        let cleaned = try preparedText(text)
        try? FileManager.default.removeItem(at: destination)

        let synthesizer = AVSpeechSynthesizer()
        let utterance = preset.makeUtterance(text: cleaned, voice: voice, volume: volume)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var outputFile: AVAudioFile?
            var completed = false

            func finish(_ result: Result<Void, Error>) {
                guard !completed else { return }
                completed = true
                continuation.resume(with: result)
            }

            synthesizer.write(utterance) { buffer in
                guard let pcmBuffer = buffer as? AVAudioPCMBuffer else {
                    finish(.failure(FunVoiceError.couldNotCreateAudio))
                    return
                }
                if pcmBuffer.frameLength == 0 {
                    if outputFile == nil {
                        finish(.failure(FunVoiceError.couldNotCreateAudio))
                    } else {
                        outputFile = nil
                        finish(.success(()))
                    }
                    return
                }
                do {
                    if outputFile == nil {
                        outputFile = try AVAudioFile(forWriting: destination, settings: pcmBuffer.format.settings)
                    }
                    try outputFile?.write(from: pcmBuffer)
                } catch {
                    synthesizer.stopSpeaking(at: .immediate)
                    finish(.failure(error))
                }
            }
        }
    }

    private func preparedText(_ text: String) throws -> String {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw FunVoiceError.emptyText }
        return cleaned.replacingOccurrences(of: "{count}", with: "1")
    }
}
