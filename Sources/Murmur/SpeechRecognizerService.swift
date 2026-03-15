import Foundation
import Speech
import AVFoundation
import os

private let log = Logger(subsystem: "co.shoptrade.murmur", category: "speech")

final class SpeechRecognizerService: @unchecked Sendable {
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var onFinalResult: ((String) -> Void)?
    private var latestTranscript = ""

    func startRecognition(onResult: @escaping @Sendable (String) -> Void) {
        recognitionTask?.cancel()
        recognitionTask = nil
        latestTranscript = ""

        guard let speechRecognizer, speechRecognizer.isAvailable else {
            log.error("Speech recognizer not available")
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.taskHint = .dictation
        self.recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        log.info("Audio format: \(recordingFormat.sampleRate)Hz, \(recordingFormat.channelCount)ch")

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
            log.info("Audio engine started")
        } catch {
            log.error("Audio engine failed: \(error.localizedDescription)")
            return
        }

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            if let result {
                let text = result.bestTranscription.formattedString
                self?.latestTranscript = text
                onResult(text)
                log.info("Partial: \(text)")

                if result.isFinal {
                    log.info("FINAL: \(text)")
                    self?.onFinalResult?(text)
                    self?.onFinalResult = nil
                    self?.cleanup()
                }
            }
            if let error {
                log.error("Recognition error: \(error.localizedDescription)")
                if let latest = self?.latestTranscript, !latest.isEmpty {
                    self?.onFinalResult?(latest)
                } else {
                    self?.onFinalResult?("")
                }
                self?.onFinalResult = nil
                self?.cleanup()
            }
        }
    }

    func stopRecognition(onComplete: @escaping @Sendable (String) -> Void) {
        onFinalResult = onComplete

        // Keep mic open 500ms longer so recognizer can finish the last word
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            self.audioEngine.stop()
            self.audioEngine.inputNode.removeTap(onBus: 0)
            self.recognitionRequest?.endAudio()
            log.info("Audio stopped after buffer, waiting for final...")
        }

        // Timeout: deliver whatever we have after 2.5s total
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard let self, self.onFinalResult != nil else { return }
            log.warning("Timeout — using latest: \(self.latestTranscript)")
            self.onFinalResult?(self.latestTranscript)
            self.onFinalResult = nil
            self.cleanup()
        }
    }

    private func cleanup() {
        recognitionTask = nil
        recognitionRequest = nil
    }
}
