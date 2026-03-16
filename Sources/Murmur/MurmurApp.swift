import SwiftUI
import Combine
import ApplicationServices
import AVFoundation
import Speech

@main
struct MurmurApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("Murmur", systemImage: appDelegate.isRecording ? "waveform.circle.fill" : "waveform") {
            MenuBarView()
                .environmentObject(appDelegate.dictationEngine)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject, @unchecked Sendable {
    let dictationEngine = DictationEngine()
    @Published var isRecording = false
    private var cancellables = Set<AnyCancellable>()
    private var setupWindow: NSWindow?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    static var appDelegate: AppDelegate?
    private static var fnHeld = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        dictationEngine.$isRecording
            .receive(on: DispatchQueue.main)
            .assign(to: &$isRecording)

        AppDelegate.appDelegate = self

        setupFnEventTap()
        dictationEngine.requestPermissions()

        NSLog("[Murmur] Ready. Hold Fn to record, release to stop.")

        if !UserDefaults.standard.bool(forKey: "setupComplete") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.showSetupWizard()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
            CFMachPortInvalidate(tap)
        }
    }

    // MARK: - Setup Wizard

    func showSetupWizard() {
        if let existing = setupWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = SetupWizardView {
            self.setupWindow?.close()
            self.setupWindow = nil
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 620),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Murmur Setup"
        window.contentView = NSHostingView(rootView: view)
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        setupWindow = window
    }

    var hasMissingPermissions: Bool {
        let mic = AVCaptureDevice.authorizationStatus(for: .audio) != .authorized
        let speech = SFSpeechRecognizer.authorizationStatus() != .authorized
        let ax = !AXIsProcessTrusted()
        let fn = (UserDefaults.standard.persistentDomain(forName: "com.apple.HIToolbox")?["AppleFnUsageType"] as? Int) != 0
        return mic || speech || ax || fn
    }

    // MARK: - Fn Key via CGEvent Tap

    private func setupFnEventTap() {
        // Check and request Accessibility (needed for paste)
        if !AXIsProcessTrusted() {
            NSLog("[Murmur] Requesting Accessibility access...")
            let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }

        // Check and request Input Monitoring (needed for key detection)
        if !CGPreflightListenEventAccess() {
            NSLog("[Murmur] Requesting Input Monitoring access...")
            CGRequestListenEventAccess()
            // Retry after a delay in case user grants quickly
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                self?.setupFnEventTap()
            }
            return
        }

        let eventMask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)

        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let refcon, let tap = Unmanaged<AnyObject>.fromOpaque(refcon).takeUnretainedValue() as? NSValue {
                    let pointer = tap.pointerValue!
                    let machPort = Unmanaged<CFMachPort>.fromOpaque(pointer).takeUnretainedValue()
                    CGEvent.tapEnable(tap: machPort, enable: true)
                }
                return Unmanaged.passRetained(event)
            }

            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            guard keyCode == 63 else { return Unmanaged.passRetained(event) }

            let fnDown = event.flags.contains(.maskSecondaryFn)

            if fnDown && !AppDelegate.fnHeld {
                AppDelegate.fnHeld = true
                NSLog("[Murmur] Fn PRESSED")
                Task { @MainActor in
                    AppDelegate.appDelegate?.dictationEngine.startRecording()
                }
            } else if !fnDown && AppDelegate.fnHeld {
                AppDelegate.fnHeld = false
                NSLog("[Murmur] Fn RELEASED")
                Task { @MainActor in
                    AppDelegate.appDelegate?.dictationEngine.stopRecording()
                }
            }

            return Unmanaged.passRetained(event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: nil
        ) else {
            NSLog("[Murmur] ERROR: Failed to create event tap")
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.eventTap = tap
        self.runLoopSource = source

        NSLog("[Murmur] Fn key event tap installed")
    }
}

extension AppDelegate: NSWindowDelegate {
    nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor in
            self.setupWindow = nil
        }
    }
}
