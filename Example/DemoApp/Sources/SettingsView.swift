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
                .listSectionSpacing(.compact)
                // The same row heights in every language (Arabic lines are taller), so the iPhone
                // screenshot's tab bar accessory always floats over the gap before About.
                .environment(\.defaultMinListRowHeight, 54)
                .scrollContentBackground(.hidden)
                .background(Theme.canvas)
                // Wide screens: a readable column. Narrow ones keep the system's inset rows.
                .contentMargins(.horizontal, max(20, (geo.size.width - Theme.readableWidth) / 2), for: .scrollContent)
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
                    .frame(width: 48, height: 48)
                    .background(Theme.accent.gradient, in: .circle)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "Mara Keller").font(.headline)
                    Text("Habits Plus · since 2024").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .frame(height: 50)
        }
    }

    private var remindersSection: some View {
        Section {
            Toggle(isOn: $reminders) { Label("Daily reminder", systemImage: "bell.badge") }
            LabeledContent {
                Text(verbatim: Date(timeIntervalSince1970: 1_789_977_600).formatted(Date.FormatStyle.dateTime.hour().minute().utc))
            } label: {
                Label("Reminder time", systemImage: "clock")
            }
            Toggle(isOn: $sounds) { Label("Sounds", systemImage: "speaker.wave.2") }
        } header: {
            SectionHeader("Reminders")
        }
    }

    private var general: some View {
        Section {
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
        } header: {
            SectionHeader("General")
        }
    }

    private var data: some View {
        Section {
            Toggle(isOn: $health) { Label("Apple Health", systemImage: "heart.text.square") }
            LinkRow(title: "Export history", icon: "square.and.arrow.up")
        } header: {
            SectionHeader("Data")
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
        } footer: {
            Text("Your data stays on your devices.")
        }
        .listSectionSpacing(44)
    }
}

/// A section title with the same height in every language.
struct SectionHeader: View {
    let title: LocalizedStringKey
    init(_ title: LocalizedStringKey) { self.title = title }
    var body: some View {
        Text(title).frame(height: 18, alignment: .bottom)
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

#Preview("Settings") { AppTabs(selection: .settings) }
