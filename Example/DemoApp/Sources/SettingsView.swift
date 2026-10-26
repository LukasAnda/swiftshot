import SwiftUI

struct SettingsView: View {
    @State private var reminders = true
    @State private var sounds = false
    @State private var sync = true
    @State private var weekStart = 1

    var body: some View {
        GeometryReader { geo in
            NavigationStack {
                Form {
                    Section {
                        HStack(spacing: Theme.Space.l) {
                            Text(verbatim: "MK")
                                .font(.figure(.title3))
                                .foregroundStyle(.white)
                                .frame(width: 56, height: 56)
                                .background(Theme.accent.gradient, in: .circle)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: "Mara Keller").font(.headline)
                                Text("Habits Plus · since 2024").font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, Theme.Space.xs)
                    }
                    Section("Reminders") {
                        Toggle(isOn: $reminders) { Label("Daily reminder", systemImage: "bell.badge") }
                        LabeledContent {
                            Text(verbatim: Date(timeIntervalSince1970: 1_789_977_600).formatted(Date.FormatStyle.dateTime.hour().minute().utc))
                        } label: {
                            Label("Reminder time", systemImage: "clock")
                        }
                        Toggle(isOn: $sounds) { Label("Sounds", systemImage: "speaker.wave.2") }
                    }
                    Section("General") {
                        Picker(selection: $weekStart) {
                            Text("Monday").tag(1)
                            Text("Sunday").tag(0)
                        } label: {
                            Label("Week starts on", systemImage: "calendar")
                        }
                        Toggle(isOn: $sync) { Label("iCloud sync", systemImage: "icloud") }
                        LabeledContent {
                            Text("System")
                        } label: {
                            Label("Appearance", systemImage: "circle.lefthalf.filled")
                        }
                    }
                    Section {
                        LabeledContent {
                            Text(verbatim: "1.0")
                        } label: {
                            Label("Version", systemImage: "info.circle")
                        }
                    } footer: {
                        Text("Your data stays on your devices.")
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Theme.canvas)
                .contentMargins(.horizontal, max(0, (geo.size.width - Theme.readableWidth) / 2), for: .scrollContent)
                .navigationTitle("Settings")
                .tint(Theme.accent)
            }
        }
    }
}

#Preview("Settings") { SettingsView() }
