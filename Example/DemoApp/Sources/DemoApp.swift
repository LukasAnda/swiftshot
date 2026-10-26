import SwiftUI

@main
struct DemoApp: App {
    var body: some Scene {
        WindowGroup {
            // Only needed for the fastlane comparison: swiftshot renders #Previews directly.
            switch UserDefaults.standard.string(forKey: "FastlaneScreen") {
            case "Welcome": WelcomeView()
            case "Habit list": HabitListView()
            case "Stats": StatsView()
            case "Settings": SettingsView()
            default: RootView()
            }
        }
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            HabitListView().tabItem { Label("Habits", systemImage: "checkmark.circle") }
            StatsView().tabItem { Label("Stats", systemImage: "chart.bar.xaxis") }
            SettingsView().tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(Theme.accent)
    }
}

#Preview("Root") { RootView() }
