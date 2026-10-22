import SwiftUI

struct ProgressRing: View {
    let progress: Double
    let color: Color
    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.2), lineWidth: 6)
            Circle().trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 36, height: 36)
    }
}

struct HabitRow: View {
    let habit: Habit
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: habit.icon)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(habit.color.gradient, in: .rect(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 2) {
                Text(habit.title).font(.headline)
                Text("\(habit.streak) day streak").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            ProgressRing(progress: habit.progress, color: habit.color)
        }
        .padding(.vertical, 4)
    }
}

struct HabitListView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Today") {
                    ForEach(Habit.samples) { HabitRow(habit: $0) }
                }
            }
            .navigationTitle("My Habits")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { } label: { Image(systemName: "plus") }
                }
            }
        }
    }
}

#Preview("Habit list") { HabitListView() }
#Preview("Habit row", traits: .sizeThatFitsLayout) { HabitRow(habit: Habit.samples[0]).padding() }
