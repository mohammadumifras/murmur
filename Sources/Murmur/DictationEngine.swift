import Foundation
import AVFoundation
import Speech
import Combine
import AppKit

@MainActor
final class DictationEngine: ObservableObject {
    @Published var isRecording = false
    @Published var rawTranscript = ""
    @Published var cleanedText = ""
    @Published var statusMessage = "Ready (Hold Fn)"
    @Published var isProcessing = false
    @Published var claudeEnabled: Bool {
        didSet { UserDefaults.standard.set(claudeEnabled, forKey: "claudeEnabled") }
    }

    private let speechRecognizer = SpeechRecognizerService()
    private let localProcessor = LocalTextProcessor()
    private let claudeRewriter = ClaudeRewriter()
    private let textInserter = TextInserter()

    init() {
        self.claudeEnabled = UserDefaults.standard.object(forKey: "claudeEnabled") as? Bool ?? true
    }

    func requestPermissions() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            if !granted {
                Task { @MainActor in self.statusMessage = "Mic denied" }
            }
        }
        SFSpeechRecognizer.requestAuthorization { status in
            Task { @MainActor in
                self.statusMessage = status == .authorized ? "Ready (Hold Fn)" : "Speech denied"
            }
        }
    }

    func toggleRecording() {
        if isRecording { stopRecording() } else { startRecording() }
    }

    func startRecording() {
        guard !isRecording else { return }

        textInserter.saveTargetApp()
        rawTranscript = ""
        cleanedText = ""
        isRecording = true
        statusMessage = "Listening..."

        speechRecognizer.startRecognition { [weak self] transcript in
            Task { @MainActor in
                self?.rawTranscript = transcript
            }
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        statusMessage = "Processing..."

        // Wait for final transcript with last word included
        speechRecognizer.stopRecognition { [weak self] finalTranscript in
            Task { @MainActor in
                guard let self else { return }

                let transcript = finalTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !transcript.isEmpty else {
                    self.statusMessage = "No speech detected"
                    return
                }

                self.rawTranscript = transcript
                NSLog("[Murmur] Transcript: %@", transcript)

                // Light local cleanup
                let cleaned = self.localProcessor.process(transcript)
                self.cleanedText = cleaned

                // Insert on background thread
                let inserter = self.textInserter
                let rewriter = self.claudeRewriter
                let usesClaude = self.claudeEnabled

                Task.detached {
                    // Paste cleaned text
                    inserter.insert(text: cleaned)
                    await MainActor.run { self.statusMessage = "Done!" }

                    // Optional Claude polish
                    guard usesClaude else { return }
                    await MainActor.run { self.isProcessing = true; self.statusMessage = "Polishing..." }

                    do {
                        let app = await MainActor.run {
                            NSWorkspace.shared.frontmostApplication?.localizedName ?? "unknown"
                        }
                        let polished = try await rewriter.rewrite(
                            transcript: cleaned,
                            context: ClaudeRewriter.Context(activeApp: app)
                        ).trimmingCharacters(in: .whitespacesAndNewlines)

                        if !polished.isEmpty && polished != cleaned {
                            inserter.undoAndReplace(newText: polished)
                            await MainActor.run {
                                self.cleanedText = polished
                                self.statusMessage = "Polished!"
                            }
                        } else {
                            await MainActor.run { self.statusMessage = "Done!" }
                        }
                    } catch {
                        NSLog("[Murmur] Claude: %@", error.localizedDescription)
                        await MainActor.run { self.statusMessage = "Done!" }
                    }

                    await MainActor.run { self.isProcessing = false }
                }
            }
        }
    }
}
