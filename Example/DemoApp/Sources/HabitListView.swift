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

/// A month of check-ins: taller than any screen (full-length screenshot demo).
struct HabitHistoryView: View {
    var body: some View {
        NavigationStack {
            List(1...30, id: \.self) { day in
                HStack {
                    Text("Day \(day)")
                    Spacer()
                    Image(systemName: day % 4 == 0 ? "xmark.circle" : "checkmark.circle.fill")
                        .foregroundStyle(day % 4 == 0 ? .red : .green)
                }
            }
            .navigationTitle("History")
        }
    }
}

struct NewHabitView: View {
    @State private var name = "Read 10 pages"
    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                Toggle("Remind me", isOn: .constant(true))
            }
            .navigationTitle("New habit")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview("History") { HabitHistoryView() }
#Preview("New habit sheet") {
    HabitListView().sheet(isPresented: .constant(true)) { NewHabitView().presentationDetents([.medium]) }
}
#Preview("Delete alert") {
    HabitListView().alert("Delete “Drink water”?", isPresented: .constant(true)) {
        Button("Delete", role: .destructive) { }
        Button("Cancel", role: .cancel) { }
    } message: { Text("Your 12 day streak will be lost.") }
}
#Preview("Share dialog") {
    HabitListView().confirmationDialog("Share progress", isPresented: .constant(true), titleVisibility: .visible) {
        Button("Messages") { }
        Button("Copy link") { }
    }
}
