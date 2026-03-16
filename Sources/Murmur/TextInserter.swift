import Foundation
import AppKit
import Carbon.HIToolbox
import ApplicationServices

final class TextInserter: @unchecked Sendable {
    private var savedApp: NSRunningApplication?
    private var savedPID: pid_t = 0
    private var lastInsertedLength: Int = 0

    func saveTargetApp() {
        savedApp = NSWorkspace.shared.frontmostApplication
        savedPID = savedApp?.processIdentifier ?? 0
    }

    var isTargetStillActive: Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == savedPID
    }

    func insert(text: String) {
        lastInsertedLength = text.count

        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)

        activateAndWait()
        usleep(50_000)
        simulateKey(kVK_ANSI_V, flags: .maskCommand)
    }

    func undoAndReplace(newText: String) {
        guard isTargetStillActive else {
            NSLog("[Murmur] Skip replace — user left the app")
            return
        }

        activateAndWait()
        usleep(50_000)

        // Select the previously pasted text by pressing Shift+Left arrow N times
        // This is more reliable than Cmd+Z across different apps
        for _ in 0..<lastInsertedLength {
            simulateKey(kVK_LeftArrow, flags: [.maskShift])
            usleep(2_000) // 2ms between keystrokes
        }
        usleep(30_000)

        // Now paste the new text over the selection
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(newText, forType: .string)
        usleep(30_000)
        simulateKey(kVK_ANSI_V, flags: .maskCommand)

        lastInsertedLength = newText.count
    }

    private func activateAndWait() {
        guard let app = savedApp else { return }
        if app.isActive { return }

        app.activate()
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
