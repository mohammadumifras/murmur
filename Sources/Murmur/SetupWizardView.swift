import SwiftUI
import AVFoundation
import Speech
import ApplicationServices

struct SetupWizardView: View {
    @StateObject private var checker = PermissionChecker()
    @Environment(\.dismiss) var dismiss
    var onComplete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 12) {
                Image(systemName: "waveform")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(.primary)

                Text("Welcome to Murmur")
                    .font(.system(size: 24, weight: .semibold))

                Text("Voice dictation for macOS.\nHold Fn to speak, release to paste.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 32)
            .padding(.bottom, 24)

            Divider()

            // Permission Steps
            ScrollView {
                VStack(spacing: 16) {
                    Text("Murmur needs a few permissions to work")
                        .font(.headline)
                        .padding(.top, 16)

                    PermissionRow(
                        icon: "mic.fill",
                        title: "Microphone",
                        description: "Captures your voice while Fn is held. Audio is processed on-device and never sent to any server.",
                        status: checker.micStatus,
                        action: { checker.requestMic() }
                    )

                    PermissionRow(
                        icon: "text.bubble.fill",
                        title: "Speech Recognition",
                        description: "Converts your speech to text using Apple's on-device speech engine.",
                        status: checker.speechStatus,
                        action: { checker.requestSpeech() }
                    )

                    PermissionRow(
                        icon: "hand.raised.fill",
                        title: "Accessibility",
                        description: "Allows Murmur to paste text into your active app using simulated keystrokes.",
                        status: checker.accessibilityStatus,
                        action: { checker.requestAccessibility() }
                    )

                    InputMonitoringRow(checker: checker)

                    PermissionRow(
                        icon: "globe",
                        title: "Fn Key Setting",
                        description: "macOS uses the Fn key for the emoji picker by default. Change it to \"Do Nothing\" so Murmur can use it.",
                        status: checker.fnKeyStatus,
                        action: { checker.openKeyboardSettings() }
                    )
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }

            Divider()

            // Footer
            HStack {
                Button("Refresh") {
                    checker.checkAll()
                }
                .buttonStyle(.bordered)

                Button("Relaunch") {
                    relaunchApp()
                }
                .buttonStyle(.bordered)

                Spacer()

                if checker.allGranted {
                    Button("Start Using Murmur") {
                        UserDefaults.standard.set(true, forKey: "setupComplete")
                        onComplete()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else {
                    Text("\(checker.grantedCount)/5 granted. Relaunch after granting.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
        }
        .frame(width: 500, height: 620)
        .onAppear { checker.startPolling() }
        .onDisappear { checker.stopPolling() }
    }

    private func relaunchApp() {
        let url = Bundle.main.bundleURL
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = [url.path]
        try? task.run()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSApp.terminate(nil)
        }
    }
}

// MARK: - Permission Row

struct PermissionRow: View {
    let icon: String
    let title: String
    let description: String
    let status: PermissionStatus
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(status == .granted ? .green : .secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title)
                        .font(.system(.body, weight: .medium))

                    Spacer()

                    statusBadge
                }

                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if status != .granted {
                Button(status == .notDetermined ? "Grant" : "Open") {
                    action()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(status == .granted ? Color.green.opacity(0.08) : Color.secondary.opacity(0.06))
        )
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch status {
        case .granted:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .denied:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        case .notDetermined:
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Input Monitoring Row (special handling)

struct InputMonitoringRow: View {
    @ObservedObject var checker: PermissionChecker
    @State private var showConfirm = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "keyboard.fill")
                .font(.title3)
                .foregroundStyle(checker.inputMonitoringStatus == .granted ? .green : .secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Input Monitoring")
                        .font(.system(.body, weight: .medium))
                    Spacer()
                    if checker.inputMonitoringStatus == .granted {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                }
                Text("Detects the Fn key at the hardware level so Murmur can start recording from any app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if showConfirm && checker.inputMonitoringStatus != .granted {
                    Text("After enabling in System Settings, click \"I've Enabled It\" below.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(.top, 2)
                }
            }

            if checker.inputMonitoringStatus != .granted {
                VStack(spacing: 4) {
                    if !showConfirm {
                        Button("Open") {
                            checker.openInputMonitoring()
                            showConfirm = true
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    } else {
                        Button("I've Enabled It") {
                            checker.confirmInputMonitoring()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(checker.inputMonitoringStatus == .granted ? Color.green.opacity(0.08) : Color.secondary.opacity(0.06))
        )
    }
}

// MARK: - Permission Checker

enum PermissionStatus {
    case granted, denied, notDetermined
}

@MainActor
class PermissionChecker: ObservableObject {
    @Published var micStatus: PermissionStatus = .notDetermined
    @Published var speechStatus: PermissionStatus = .notDetermined
    @Published var accessibilityStatus: PermissionStatus = .notDetermined
    @Published var inputMonitoringStatus: PermissionStatus = .notDetermined
    @Published var fnKeyStatus: PermissionStatus = .notDetermined

    var allGranted: Bool {
        micStatus == .granted &&
        speechStatus == .granted &&
        accessibilityStatus == .granted &&
        inputMonitoringStatus == .granted &&
        fnKeyStatus == .granted
    }

    var grantedCount: Int {
        [micStatus, speechStatus, accessibilityStatus, inputMonitoringStatus, fnKeyStatus]
            .filter { $0 == .granted }.count
    }

    private var pollTimer: Timer?

    func startPolling() {
        checkAll()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkAll()
            }
        }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func checkAll() {
        checkMic()
        checkSpeech()
        checkAccessibility()
        checkInputMonitoring()
        checkFnKey()
    }

    // Microphone
    func checkMic() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: micStatus = .granted
        case .denied, .restricted: micStatus = .denied
        case .notDetermined: micStatus = .notDetermined
        @unknown default: micStatus = .notDetermined
        }
    }

    func requestMic() {
        if micStatus == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { _ in
                Task { @MainActor in self.checkMic() }
            }
        } else {
            openPrivacySettings("Microphone")
        }
    }

    // Speech
    func checkSpeech() {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: speechStatus = .granted
        case .denied, .restricted: speechStatus = .denied
        case .notDetermined: speechStatus = .notDetermined
        @unknown default: speechStatus = .notDetermined
        }
    }

    func requestSpeech() {
        if speechStatus == .notDetermined {
            SFSpeechRecognizer.requestAuthorization { _ in
                Task { @MainActor in self.checkSpeech() }
            }
        } else {
            openPrivacySettings("SpeechRecognition")
        }
    }

    // Accessibility
    func checkAccessibility() {
        accessibilityStatus = AXIsProcessTrusted() ? .granted : .denied
    }

    func requestAccessibility() {
        if !AXIsProcessTrusted() {
            let _ = AXIsProcessTrustedWithOptions(
                [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            )
        }
        openPrivacySettings("Accessibility")
    }

    private func openPrivacySettings(_ section: String) {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_\(section)")!)
    }

    // Input Monitoring (can't query directly, check if we've confirmed it before)
    func checkInputMonitoring() {
        if UserDefaults.standard.bool(forKey: "inputMonitoringGranted") {
            inputMonitoringStatus = .granted
        } else {
            inputMonitoringStatus = .denied
        }
    }

    func openInputMonitoring() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
    }

    func confirmInputMonitoring() {
        UserDefaults.standard.set(true, forKey: "inputMonitoringGranted")
        inputMonitoringStatus = .granted
    }

    // Fn Key
    func checkFnKey() {
        let fnUsage = UserDefaults.standard.persistentDomain(forName: "com.apple.HIToolbox")?["AppleFnUsageType"] as? Int
        fnKeyStatus = (fnUsage == 0) ? .granted : .denied
    }

    func openKeyboardSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!)
    }
}
