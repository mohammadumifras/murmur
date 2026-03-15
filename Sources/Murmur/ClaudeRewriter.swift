import Foundation

final class ClaudeRewriter: Sendable {
    struct Context: Sendable {
        let activeApp: String
    }

    private let claudePath: String

    init() {
        self.claudePath = ClaudeRewriter.findClaude()
    }

    func rewrite(transcript: String, context: Context) async throws -> String {
        let prompt = "Fix grammar, punctuation, spacing. Remove filler words. Keep meaning exact. Output ONLY cleaned text.\n\nApp: \(context.activeApp)\nText: \(transcript)"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: claudePath)
        process.arguments = ["--print", "--model", "claude-haiku-4-5-20251001", prompt]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try process.run()

                    let timer = DispatchSource.makeTimerSource(queue: .global())
                    timer.schedule(deadline: .now() + 10)
                    timer.setEventHandler {
                        if process.isRunning { process.terminate() }
                    }
                    timer.resume()

                    process.waitUntilExit()
                    timer.cancel()

                    let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                    if process.terminationStatus != 0 || output.isEmpty {
                        let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                        continuation.resume(throwing: RewriteError.failed(err))
                    } else {
                        continuation.resume(returning: output)
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func findClaude() -> String {
        let home = NSHomeDirectory()
        let paths = [
            "\(home)/.local/bin/claude",
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude",
            "\(home)/.npm-global/bin/claude",
        ]
        for p in paths {
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }

        // Fallback: `which claude`
        let which = Process()
        which.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        which.arguments = ["claude"]
        let pipe = Pipe()
        which.standardOutput = pipe
        try? which.run()
        which.waitUntilExit()
        let result = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !result.isEmpty && which.terminationStatus == 0 { return result }

        return "claude"
    }

    enum RewriteError: LocalizedError {
        case failed(String)
        var errorDescription: String? {
            switch self { case .failed(let m): return m }
        }
    }
}
