import SwiftUI
import Combine
import ApplicationServices
import IOKit
import IOKit.hid

@main
struct MurmurApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("Murmur", systemImage: appDelegate.isRecording ? "waveform.circle.fill" : "waveform") {
            MenuBarView()
                .environmentObject(appDelegate.dictationEngine)
        }
        Settings {
            SettingsView()
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

    static var isHolding = false
    static var engine: DictationEngine?

    func applicationDidFinishLaunching(_ notification: Notification) {
        dictationEngine.$isRecording
            .receive(on: DispatchQueue.main)
            .assign(to: &$isRecording)

        AppDelegate.engine = dictationEngine

        checkAccessibility()
        setupHIDMonitoring()
        dictationEngine.requestPermissions()

        NSLog("[Murmur] Ready. Hold Fn to record, release to stop.")
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let mgr = hidManager {
            IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        }
    }

    private func checkAccessibility() {
        let trusted = AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        )
        NSLog("[Murmur] Accessibility: \(trusted ? "granted" : "NOT granted")")
    }

    private func setupHIDMonitoring() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

        // Match keyboard devices
        let matching: [String: Any] = [
            kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

        // Callback for input values
        let callback: IOHIDValueCallback = { context, result, sender, value in
            let element = IOHIDValueGetElement(value)
            let usagePage = IOHIDElementGetUsagePage(element)
            let usage = IOHIDElementGetUsage(element)
            let pressed = IOHIDValueGetIntegerValue(value)

            // Fn key: Usage Page 0xFF (Apple vendor) or Usage Page 0x01 (Generic Desktop)
            // On Apple keyboards, Fn is typically:
            // - Usage Page 0xFF, Usage 0x03
            // - Or Usage Page 0x01, Usage 0x03 (specifically on newer Apple keyboards)
            // - Or kHIDUsage_KeyboardFn = 0x00 on Usage Page 0x07 (Keyboard)
            // The most reliable: look for usage page 0xFF (Apple vendor-specific)

            let isFnKey: Bool
            if usagePage == 0xFF && usage == 0x03 {
                isFnKey = true
            } else if usagePage == 0x07 && usage == 0x03 {
                // Some keyboards report Fn as keyboard usage 0x03
                isFnKey = true
            } else if usagePage == 0x01 && usage == 0x06 {
                // Generic Desktop Keyboard usage
                isFnKey = false
            } else {
                isFnKey = false
            }

            guard isFnKey else { return }

            if pressed != 0 && !AppDelegate.isHolding {
                AppDelegate.isHolding = true
                NSLog("[Murmur] Fn PRESSED (HID: page=0x%x usage=0x%x)", usagePage, usage)
                Task { @MainActor in
                    AppDelegate.engine?.startRecording()
                }
            } else if pressed == 0 && AppDelegate.isHolding {
                AppDelegate.isHolding = false
                NSLog("[Murmur] Fn RELEASED (HID: page=0x%x usage=0x%x)", usagePage, usage)
                Task { @MainActor in
                    AppDelegate.engine?.stopRecording()
                }
            }
        }

        IOHIDManagerRegisterInputValueCallback(manager, callback, nil)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if result == kIOReturnSuccess {
            NSLog("[Murmur] HID keyboard monitor installed")
        } else {
            NSLog("[Murmur] ERROR: HID manager failed to open (code: %d)", result)
            // Fallback to CGEvent tap for other keys
            setupFallbackHotkey()
        }

        self.hidManager = manager
    }

    private func setupFallbackHotkey() {
        NSLog("[Murmur] Fallback: Option+D to toggle")
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.modifierFlags.contains(.option) && event.keyCode == 2 {
                Task { @MainActor in self?.dictationEngine.toggleRecording() }
            }
        }
    }
}
