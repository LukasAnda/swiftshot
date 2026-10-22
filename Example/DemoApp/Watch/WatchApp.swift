import SwiftUI

@main
struct HabitsWatchApp: App {
    var body: some Scene {
        WindowGroup {
            // The launch argument is only used to capture ground-truth screens for verification.
            switch UserDefaults.standard.string(forKey: "WatchScreen") {
            case "Progress": ProgressDetailView()
            case "Week": WeekView()
            default: WatchHabitList()
            }
        }
    }
}

struct WatchHabit: Identifiable {
    let id = UUID()
    let title: LocalizedStringKey
    let icon: String
    let color: Color
    let progress: Double
}

let watchHabits = [
    WatchHabit(title: "Drink water", icon: "drop.fill", color: .blue, progress: 0.75),
    WatchHabit(title: "Morning run", icon: "figure.run", color: .orange, progress: 1.0),
    WatchHabit(title: "Meditate", icon: "leaf.fill", color: .green, progress: 0.3),
    WatchHabit(title: "No sugar", icon: "nosign", color: .pink, progress: 0.9),
]

struct WatchHabitList: View {
    var body: some View {
        NavigationStack {
            List(watchHabits) { habit in
                HStack {
                    Image(systemName: habit.icon).foregroundStyle(habit.color)
                    Text(habit.title)
                    Spacer()
                    Text(habit.progress, format: .percent.precision(.fractionLength(0)))
                        .foregroundStyle(.secondary).font(.footnote)
                }
            }
            .navigationTitle("Today")
        }
    }
}

struct ProgressDetailView: View {
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().stroke(.blue.opacity(0.25), lineWidth: 14)
                Circle().trim(from: 0, to: 0.75)
                    .stroke(.blue.gradient, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: "drop.fill").font(.largeTitle).foregroundStyle(.blue)
            }
            .padding(10)
            Text("Drink water").font(.headline)
            Text("\(12) day streak").font(.footnote).foregroundStyle(.secondary)
        }
        .padding()
    }
}

struct WeekView: View {
    let values: [Double] = [0.4, 0.7, 0.55, 0.9, 0.65, 1.0, 0.8]
    var body: some View {
        VStack(alignment: .leading) {
            Text("This week").font(.headline)
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                    VStack {
                        Capsule().fill(.green.gradient).frame(height: 90 * v)
                        Text(Calendar.current.veryShortWeekdaySymbols[i]).font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            Text(0.873, format: .percent.precision(.fractionLength(1)))
                .font(.title2.bold()).foregroundStyle(.green)
        }
        .padding(.horizontal)
    }
}

#Preview("Watch list") { WatchHabitList() }
#Preview("Watch progress") { ProgressDetailView() }
#Preview("Watch week") { WeekView() }
