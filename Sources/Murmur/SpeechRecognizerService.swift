import Foundation
import Speech
import AVFoundation

final class SpeechRecognizerService: @unchecked Sendable {
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var onFinalResult: ((String) -> Void)?
    private var latestTranscript = ""
    private(set) var isRunning = false
    private var delivered = false

    func startRecognition(onResult: @escaping @Sendable (String) -> Void) {
        forceStop()

        latestTranscript = ""
        delivered = false

        guard let speechRecognizer, speechRecognizer.isAvailable else {
            NSLog("[Murmur] Speech recognizer not available")
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.taskHint = .dictation
        self.recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
            isRunning = true
            NSLog("[Murmur] Recording started")
        } catch {
            NSLog("[Murmur] Audio failed: %@", error.localizedDescription)
            cleanup()
            return
        }

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let text = result.bestTranscription.formattedString
                self.latestTranscript = text
                onResult(text)

                if result.isFinal {
                    NSLog("[Murmur] Final transcript: %@", text)
                    DispatchQueue.main.async {
                        self.deliverResult(text)
                    }
                }
            }
            if let error {
                NSLog("[Murmur] Speech error: %@", error.localizedDescription)
                DispatchQueue.main.async {
                    self.deliverResult(self.latestTranscript)
                }
            }
        }
    }

    func stopRecognition(onComplete: @escaping @Sendable (String) -> Void) {
        guard isRunning else {
            onComplete(latestTranscript)
            return
        }

        onFinalResult = onComplete

        // Keep mic open 500ms to catch last word
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.stopAudioEngine()
        }

        // Timeout after 2.5s
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard let self, self.onFinalResult != nil else { return }
            NSLog("[Murmur] Timeout, using: %@", self.latestTranscript)
            self.deliverResult(self.latestTranscript)
        }
    }

    func forceStop() {
        stopAudioEngine()
        onFinalResult = nil
        delivered = false
        cleanup()
    }

    private func stopAudioEngine() {
        guard isRunning else { return }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        isRunning = false
        NSLog("[Murmur] Mic stopped")
    }

    // All calls to deliverResult are dispatched to main queue, so no race
    private func deliverResult(_ text: String) {
        guard !delivered else { return }
        delivered = true
        let callback = onFinalResult
        onFinalResult = nil
        cleanup()
        callback?(text)
    }

    private func cleanup() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
    }
}
