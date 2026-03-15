import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var engine: DictationEngine

    var body: some View {
        Toggle("Claude polish", isOn: Binding(
            get: { engine.claudeEnabled },
            set: { engine.claudeEnabled = $0 }
        ))
        Divider()
        if AppDelegate.appDelegate?.hasMissingPermissions == true {
            Button("Setup...") {
                AppDelegate.appDelegate?.showSetupWizard()
            }
            Divider()
        }
        Button("Quit Murmur") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
