import SwiftUI

struct SettingsView: View {
    @State private var reminders = true
    @State private var sounds = false
    @State private var sync = true
    @State private var health = true
    @State private var weekStart = 1

    var body: some View {
        GeometryReader { geo in
            NavigationStack {
                Form {
                    profile
                    remindersSection
                    general
                    data
                    about
                }
                .scrollContentBackground(.hidden)
                .background(Theme.canvas)
                .contentMargins(.horizontal, max(0, (geo.size.width - Theme.readableWidth) / 2), for: .scrollContent)
                .navigationTitle("Settings")
                .tint(Theme.accent)
            }
        }
    }

    private var profile: some View {
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
    }

    private var remindersSection: some View {
        Section("Reminders") {
            Toggle(isOn: $reminders) { Label("Daily reminder", systemImage: "bell.badge") }
            LabeledContent {
                Text(verbatim: Date(timeIntervalSince1970: 1_789_977_600).formatted(Date.FormatStyle.dateTime.hour().minute().utc))
            } label: {
                Label("Reminder time", systemImage: "clock")
            }
            Toggle(isOn: $sounds) { Label("Sounds", systemImage: "speaker.wave.2") }
        }
    }

    private var general: some View {
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
    }

    private var data: some View {
        Section("Data") {
            Toggle(isOn: $health) { Label("Apple Health", systemImage: "heart.text.square") }
            LinkRow(title: "Export history", icon: "square.and.arrow.up")
        }
    }

    private var about: some View {
        Section {
            LinkRow(title: "Rate Habits", icon: "star")
            LinkRow(title: "Privacy", icon: "hand.raised")
            LabeledContent {
                Text(verbatim: "1.0")
            } label: {
                Label("Version", systemImage: "info.circle")
            }
        } header: {
            Text("About")
        } footer: {
            Text("Your data stays on your devices.")
        }
    }
}

/// A row that leads somewhere: label and a trailing chevron.
private struct LinkRow: View {
    let title: LocalizedStringKey
    let icon: String
    var body: some View {
        LabeledContent {
            Image(systemName: "chevron.forward").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        } label: {
            Label(title, systemImage: icon)
        }
    }
}

#Preview("Settings") { SettingsView() }
