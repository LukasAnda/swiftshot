import SwiftUI

struct SettingsView: View {
    @State private var reminders = true
    @State private var sounds = false
    @State private var weekStart = 1
    var body: some View {
        NavigationStack {
            Form {
                Section("Notifications") {
                    Toggle("Daily reminders", isOn: $reminders)
                    Toggle("Sounds", isOn: $sounds)
                }
                Section("General") {
                    Picker("Week starts on", selection: $weekStart) {
                        Text("Monday").tag(1)
                        Text("Sunday").tag(0)
                    }
                    LabeledContent("Version", value: "1.0")
                }
            }
            .navigationTitle("Settings")
        }
    }
}

#Preview("Settings") { SettingsView() }
