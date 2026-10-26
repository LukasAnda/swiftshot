import SwiftUI

@main
struct DemoApp: App {
    var body: some Scene {
        WindowGroup {
            // Only needed for the fastlane comparison: swiftshot renders #Previews directly.
            switch UserDefaults.standard.string(forKey: "FastlaneScreen") {
            case "Welcome": WelcomeView()
            case "Habit list": AppTabs(selection: .today)
            case "Stats": AppTabs(selection: .stats)
            case "Settings": AppTabs(selection: .settings)
            case "History": AppTabs(selection: .history)
            default: AppTabs()
            }
        }
    }
}

enum AppTab: Hashable {
    case today, stats, history, settings
}

/// The app's four tabs. iOS 26: the system Liquid Glass tab bar (floating at the top on iPad),
/// which shrinks while scrolling down, with the next reminder in a glass accessory on iPhone.
/// Earlier versions get the classic tab bar.
struct AppTabs: View {
    @State private var selection: AppTab

    init(selection: AppTab = .today) {
        _selection = State(initialValue: selection)
    }

    var body: some View {
        Group {
            if #available(iOS 26, *) {
                TabView(selection: $selection) {
                    Tab("Today", systemImage: "checkmark.circle", value: AppTab.today) { HabitListView() }
                    Tab("Stats", systemImage: "chart.bar.xaxis", value: AppTab.stats) { StatsView() }
                    Tab("History", systemImage: "calendar", value: AppTab.history) { HabitHistoryView() }
                    Tab("Settings", systemImage: "gearshape", value: AppTab.settings) { SettingsView() }
                }
                .tabBarMinimizeBehavior(.onScrollDown)
                .modifier(UpNextAccessory())
            } else {
                TabView(selection: $selection) {
                    HabitListView().tabItem { Label("Today", systemImage: "checkmark.circle") }.tag(AppTab.today)
                    StatsView().tabItem { Label("Stats", systemImage: "chart.bar.xaxis") }.tag(AppTab.stats)
                    HabitHistoryView().tabItem { Label("History", systemImage: "calendar") }.tag(AppTab.history)
                    SettingsView().tabItem { Label("Settings", systemImage: "gearshape") }.tag(AppTab.settings)
                }
            }
        }
        .tint(Theme.accent)
    }
}

/// The next reminder in the tab bar's accessory, on iPhone only (iPad's tab bar is at the top).
@available(iOS 26, *)
private struct UpNextAccessory: ViewModifier {
    @Environment(\.horizontalSizeClass) private var sizeClass

    func body(content: Content) -> some View {
        if sizeClass == .compact {
            content.tabViewBottomAccessory { UpNextPill() }
        } else {
            content
        }
    }
}

/// "Up next · Drink water · 11:00"; just the habit and time while the tab bar is minimized.
@available(iOS 26, *)
struct UpNextPill: View {
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    var body: some View {
        let next = History.upNext[0]
        let habit = Habit.samples[next.habit]
        HStack(spacing: Theme.Space.s) {
            Image(systemName: habit.icon)
                .font(.footnote.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Theme.accent, in: .circle)
            if placement != .inline {
                Text("Up next").foregroundStyle(.secondary)
                Text(verbatim: "·").foregroundStyle(.tertiary)
            }
            Text(habit.title).foregroundStyle(.primary).lineLimit(1)
            Text(verbatim: "·").foregroundStyle(.tertiary)
            Text(verbatim: History.time(hour: next.hour, minute: next.minute).formatted(Date.FormatStyle.dateTime.hour().minute().utc))
                .font(.figure(.subheadline, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.accent)
            Spacer(minLength: 0)
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, Theme.Space.s + 2)
    }
}

#Preview("Root") { AppTabs() }
