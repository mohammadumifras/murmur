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
    private var recordingStartTime: Date?

    init() {
        self.claudeEnabled = UserDefaults.standard.object(forKey: "claudeEnabled") as? Bool ?? false
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
        // If already recording, force stop first (handles stuck state)
        if isRecording {
            NSLog("[Murmur] Force stopping previous recording")
            speechRecognizer.forceStop()
            isRecording = false
        }

        textInserter.saveTargetApp()
        rawTranscript = ""
        cleanedText = ""
        recordingStartTime = Date()

        // Check mic availability
        let authStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        guard authStatus == .authorized else {
            statusMessage = "Mic not authorized"
            NSLog("[Murmur] Mic auth status: %d", authStatus.rawValue)
            return
        }

        isRecording = true
        statusMessage = "Listening..."

        // Play start sound
        NSSound(named: "Tink")?.play()

        speechRecognizer.startRecognition { [weak self] transcript in
            Task { @MainActor in
                self?.rawTranscript = transcript
            }
        }

        // Safety: auto-stop after 60s
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in
            guard let self, self.isRecording else { return }
            NSLog("[Murmur] Auto-stop: 60s timeout")
            self.stopRecording()
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        isRecording = false

        let duration = Date().timeIntervalSince(recordingStartTime ?? Date())

        // If held for less than 0.3s, treat as accidental tap
        if duration < 0.3 {
            NSLog("[Murmur] Too short (%.1fs), ignoring", duration)
            speechRecognizer.forceStop()
            statusMessage = "Ready (Hold Fn)"
            return
        }

        statusMessage = "Processing..."
        NSLog("[Murmur] Recording duration: %.1fs", duration)

        // Play stop sound
        NSSound(named: "Pop")?.play()

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

                let cleaned = self.localProcessor.process(transcript)
                self.cleanedText = cleaned

                let inserter = self.textInserter
                let rewriter = self.claudeRewriter
                let usesClaude = self.claudeEnabled

                Task.detached {
                    inserter.insert(text: cleaned)
                    await MainActor.run { self.statusMessage = "Done!" }

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
