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

/// The iPhone app's persimmon accent (its dark variant: the watch is always dark).
let accent = Color(red: 1.0, green: 0.435, blue: 0.290)
let amber = Color(red: 1.0, green: 0.70, blue: 0.35)

struct WatchHabit: Identifiable {
    let id: Int
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let icon: String
    let progress: Double
}

let watchHabits = [
    WatchHabit(id: 0, title: "Drink water", detail: "3 of 8 glasses", icon: "drop.fill", progress: 0.375),
    WatchHabit(id: 1, title: "Morning run", detail: "5.2 km", icon: "figure.run", progress: 1.0),
    WatchHabit(id: 2, title: "Meditate", detail: "10 minutes", icon: "figure.mind.and.body", progress: 1.0),
    WatchHabit(id: 3, title: "Read 20 pages", detail: "8 of 20 pages", icon: "book.closed.fill", progress: 0.4),
]

struct Ring: View {
    let progress: Double
    var lineWidth: CGFloat
    var body: some View {
        ZStack {
            Circle().stroke(accent.opacity(0.22), lineWidth: lineWidth)
            Circle().trim(from: 0, to: progress)
                .stroke(LinearGradient(colors: [amber, accent], startPoint: .top, endPoint: .bottom),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

struct WatchHabitList: View {
    var body: some View {
        NavigationStack {
            // What's left today: two rows, so the glass buttons below float over empty background
            // on every case size instead of over a row.
            List(watchHabits.filter { $0.progress < 1 }) { habit in
                HStack(spacing: 10) {
                    ZStack {
                        if habit.progress >= 1 { Circle().fill(accent) } else { Ring(progress: habit.progress, lineWidth: 3.5) }
                        Image(systemName: habit.progress >= 1 ? "checkmark" : habit.icon)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(habit.progress >= 1 ? Color.white : accent)
                    }
                    .frame(width: 34, height: 34)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(habit.title).font(.system(.body, weight: .semibold)).lineLimit(1)
                        Text(habit.detail).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .padding(.vertical, 4)
            }
            .navigationTitle("Today")
            .tint(accent)
            .toolbar {
                // watchOS 26 draws these as Liquid Glass buttons in the bottom corners: a clear one
                // and the accent-tinted main action.
                ToolbarItemGroup(placement: .bottomBar) {
                    Button { } label: { Image(systemName: "chart.bar.xaxis").foregroundStyle(accent) }
                        .accessibilityLabel("Statistics")
                    Spacer()
                    Button { } label: { Image(systemName: "plus").foregroundStyle(.white) }
                        .tint(accent)
                        .accessibilityLabel("New habit")
                }
            }
        }
    }
}

struct ProgressDetailView: View {
    var body: some View {
        ViewThatFits(in: .vertical) {
            VStack(spacing: 6) {
                ring.frame(width: 104, height: 104)
                Text("Drink water").font(.headline)
                Label { Text("\(12) days") } icon: { Image(systemName: "flame.fill") }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(accent)
            }
            ring.padding(6)
        }
        .padding(.horizontal)
    }

    private var ring: some View {
        ZStack {
            Ring(progress: 0.375, lineWidth: 12)
            VStack(spacing: 0) {
                Text(verbatim: 3.formatted()).font(.system(size: 34, weight: .bold, design: .rounded))
                Text("of 8").font(.system(.caption2, design: .rounded, weight: .semibold)).foregroundStyle(.secondary)
            }
        }
    }
}

struct WeekView: View {
    let values: [Double] = [0.6, 0.8, 1.0, 0.8, 0.8, 0.8, 0.4]
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Last 7 days").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(0.74, format: .percent.precision(.fractionLength(0)))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(accent)
                Text("completion").font(.footnote).foregroundStyle(.secondary)
            }
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                    let isToday = i == values.count - 1
                    VStack(spacing: 3) {
                        ZStack(alignment: .bottom) {
                            Capsule().fill(Color.white.opacity(0.08))
                            Capsule().fill(isToday ? AnyShapeStyle(accent) : AnyShapeStyle(accent.opacity(0.5)))
                                .frame(height: 64 * v)
                        }
                        .frame(height: 64)
                        Text(Date(timeIntervalSince1970: 1_790_000_000 - 86_400 * Double(6 - i)), format: weekday)
                            .font(.system(size: 11, weight: isToday ? .bold : .medium))
                            .foregroundStyle(isToday ? accent : Color.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal)
    }

    private var weekday: Date.FormatStyle {
        var s = Date.FormatStyle.dateTime.weekday(.narrow)
        s.timeZone = TimeZone(identifier: "UTC")!
        return s
    }
}

struct StreakBadge: View {
    var body: some View {
        let label = Label { Text("\(12)-day streak") } icon: { Image(systemName: "flame.fill") }
            .font(.system(.footnote, design: .rounded, weight: .semibold))
            .padding(.horizontal, 12).padding(.vertical, 8)
        if #available(watchOS 26, *) {
            label.glassEffect(.regular.tint(accent.opacity(0.6)), in: .capsule)
        } else {
            label.background(accent.opacity(0.35), in: Capsule())
        }
    }
}

#Preview("Watch list") { WatchHabitList() }
#Preview("Watch progress") { ProgressDetailView() }
#Preview("Watch week") { WeekView() }
#Preview("Watch badge", traits: .sizeThatFitsLayout) {
    StreakBadge().padding(8)
}
#Preview("Watch ring", traits: .fixedLayout(width: 120, height: 120)) { ProgressDetailView() }
