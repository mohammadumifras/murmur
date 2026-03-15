import SwiftUI
import Combine
import ApplicationServices
import IOKit
import IOKit.hid
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
    private var hidManager: IOHIDManager?
    private var cancellables = Set<AnyCancellable>()
    private var setupWindow: NSWindow?

    static var isHolding = false
    static var engine: DictationEngine?
    static var appDelegate: AppDelegate?

    func applicationDidFinishLaunching(_ notification: Notification) {
        dictationEngine.$isRecording
            .receive(on: DispatchQueue.main)
            .assign(to: &$isRecording)

        AppDelegate.engine = dictationEngine
        AppDelegate.appDelegate = self

        setupHIDMonitoring()
        dictationEngine.requestPermissions()

        NSLog("[Murmur] Ready. Hold Fn to record, release to stop.")

        // Show wizard only on first install
        if !UserDefaults.standard.bool(forKey: "setupComplete") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.showSetupWizard()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let mgr = hidManager {
            IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        }
    }

    // MARK: - Setup Wizard (created on demand, freed when closed)

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

    /// Check if any permissions are missing
    var hasMissingPermissions: Bool {
        let mic = AVCaptureDevice.authorizationStatus(for: .audio) != .authorized
        let speech = SFSpeechRecognizer.authorizationStatus() != .authorized
        let ax = !AXIsProcessTrusted()
        let input = !UserDefaults.standard.bool(forKey: "inputMonitoringGranted")
        let fn = (UserDefaults.standard.persistentDomain(forName: "com.apple.HIToolbox")?["AppleFnUsageType"] as? Int) != 0
        return mic || speech || ax || input || fn
    }

    func markFnReceived() {
        if !UserDefaults.standard.bool(forKey: "inputMonitoringGranted") {
            UserDefaults.standard.set(true, forKey: "inputMonitoringGranted")
            NSLog("[Murmur] Input Monitoring confirmed working")
        }
    }

    // MARK: - HID Monitoring

    private func setupHIDMonitoring() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

        let matching: [String: Any] = [
            kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

        let callback: IOHIDValueCallback = { context, result, sender, value in
            let element = IOHIDValueGetElement(value)
            let usagePage = IOHIDElementGetUsagePage(element)
            let usage = IOHIDElementGetUsage(element)
            let pressed = IOHIDValueGetIntegerValue(value)

            let isFnKey = (usagePage == 0xFF && usage == 0x03) || (usagePage == 0x07 && usage == 0x03)
            guard isFnKey else { return }

            Task { @MainActor in
                AppDelegate.appDelegate?.markFnReceived()
            }

            if pressed != 0 {
                if !AppDelegate.isHolding {
                    AppDelegate.isHolding = true
                    NSLog("[Murmur] Fn PRESSED")
                    Task { @MainActor in
                        AppDelegate.engine?.startRecording()
                    }
                }
            } else {
                if AppDelegate.isHolding {
                    AppDelegate.isHolding = false
                    NSLog("[Murmur] Fn RELEASED")
                    Task { @MainActor in
                        AppDelegate.engine?.stopRecording()
                    }
                }
            }
        }

        IOHIDManagerRegisterInputValueCallback(manager, callback, nil)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if result == kIOReturnSuccess {
            NSLog("[Murmur] HID keyboard monitor installed")
        } else {
            NSLog("[Murmur] ERROR: HID manager failed (code: %d)", result)
        }

        self.hidManager = manager
    }
}

extension AppDelegate: NSWindowDelegate {
    nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor in
            self.setupWindow = nil
        }
    }
}
