import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var engine: DictationEngine

    var body: some View {
        Toggle("Claude polish", isOn: Binding(
            get: { engine.claudeEnabled },
            set: { engine.claudeEnabled = $0 }
        ))
        Divider()
        Button("Quit Murmur") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

struct SettingsView: View {
    @EnvironmentObject var engine: DictationEngine

    var body: some View {
        Form {
            Text("Murmur")
                .font(.title2)
            Text("Hold Fn to dictate")
            Toggle("Claude polish", isOn: Binding(
                get: { engine.claudeEnabled },
                set: { engine.claudeEnabled = $0 }
            ))
        }
        .padding()
        .frame(width: 300, height: 140)
    }
}
