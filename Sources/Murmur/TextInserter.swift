import Foundation
import AppKit
import Carbon.HIToolbox

final class TextInserter: @unchecked Sendable {
    private var savedApp: NSRunningApplication?
    private var savedPID: pid_t = 0

    func saveTargetApp() {
        savedApp = NSWorkspace.shared.frontmostApplication
        savedPID = savedApp?.processIdentifier ?? 0
    }

    var isTargetStillActive: Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == savedPID
    }

    func insert(text: String) {
        // Set clipboard
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)

        // Make sure target app is active
        activateAndWait()

        usleep(20_000) // 20ms settle
        simulateKey(kVK_ANSI_V, flags: .maskCommand)
    }

    func undoAndReplace(newText: String) {
        guard isTargetStillActive else {
            NSLog("[Murmur] Skip replace — user left the app")
            return
        }

        activateAndWait()

        // Undo previous paste
        simulateKey(kVK_ANSI_Z, flags: .maskCommand)
        usleep(80_000) // 80ms for undo

        // Set new text and paste
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(newText, forType: .string)
        usleep(20_000) // 20ms
        simulateKey(kVK_ANSI_V, flags: .maskCommand)
        usleep(50_000) // 50ms
    }

    private func activateAndWait() {
        guard let app = savedApp else { return }
        if app.isActive { return }

        app.activate()
        // Wait until active (poll every 10ms, max 300ms)
        for _ in 0..<30 {
            if app.isActive { return }
            usleep(10_000)
        }
    }

    private func simulateKey(_ keyCode: Int, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
