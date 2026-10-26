import SwiftUI

struct HabitRow: View {
    let habit: Habit
    var body: some View {
        HStack(spacing: Theme.Space.m + 2) {
            Image(systemName: habit.icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(habit.isDone ? Color.white : Theme.accent)
                .frame(width: 44, height: 44)
                .background(habit.isDone ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.accent.opacity(0.12)), in: .circle)
            VStack(alignment: .leading, spacing: 3) {
                Text(habit.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                HStack(spacing: Theme.Space.xs) {
                    Text(habit.detail)
                    if habit.streak > 0 {
                        Text(verbatim: "·")
                        Image(systemName: "flame.fill").font(.caption2).foregroundStyle(Theme.accent)
                        Text("\(habit.streak) days")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: Theme.Space.s)
            ProgressRing(progress: habit.progress, size: 30, lineWidth: 3.5)
        }
        .padding(.vertical, Theme.Space.m)
    }
}

/// Today's progress, on glass over the warm backdrop.
struct TodaySummary: View {
    var body: some View {
        let done = Habit.doneCount, total = Habit.samples.count
        HStack(spacing: Theme.Space.l) {
            ZStack {
                ProgressRing(progress: Double(done) / Double(total), size: 76, lineWidth: 9)
                VStack(spacing: 0) {
                    Text("\(done)").font(.figure(.title)).monospacedDigit()
                    Text("of \(total)").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text("Good afternoon, Mara").font(.title3.weight(.semibold))
                Text("Three habits left today. You’re on a 31-day run streak.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Space.l + 4)
        .glassSurface(in: .rect(cornerRadius: Theme.Radius.card + 4, style: .continuous))
    }
}

/// The filter chips above the list; glass capsules that share one container.
struct FilterBar: View {
    var body: some View {
        HStack(spacing: Theme.Space.s) {
            chip("All", count: 5, selected: true)
            chip("Morning", count: 2, selected: false)
            chip("Evening", count: 2, selected: false)
            Spacer(minLength: 0)
        }
        .glassGroup(spacing: Theme.Space.s)
    }

    private func chip(_ title: LocalizedStringKey, count: Int, selected: Bool) -> some View {
        HStack(spacing: 6) {
            Text(title)
            Text("\(count)").monospacedDigit().foregroundStyle(selected ? Color.white.opacity(0.8) : Color.secondary)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(selected ? Color.white : Color.primary)
        .padding(.horizontal, 14).padding(.vertical, 8)
        .glassSurface(in: .capsule, tint: selected ? Theme.accent : nil)
    }
}

struct HabitListView: View {
    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width > 900
            NavigationStack {
                ScrollView {
                    Group {
                        if wide {
                            // iPad: today's overview beside the list.
                            HStack(alignment: .top, spacing: Theme.Space.xl) {
                                VStack(alignment: .leading, spacing: Theme.Space.l) { header; WeekChart() }
                                    .frame(width: 400)
                                list.padding(.top, 30)
                            }
                            .frame(maxWidth: 1100)
                        } else {
                            VStack(alignment: .leading, spacing: Theme.Space.xl) { header; list }
                        }
                    }
                    .padding(.horizontal, Theme.Space.l + 4)
                    .padding(.bottom, Theme.Space.xxl)
                    .frame(maxWidth: .infinity)
                }
                .background { Backdrop() }
                .navigationTitle("Today")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button { } label: { Image(systemName: "plus") }
                            .accessibilityLabel("New habit")
                    }
                }
                .tint(Theme.accent)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text(verbatim: Theme.today.formatted(Date.FormatStyle.dateTime.weekday(.wide).day().month(.wide).utc))
                .eyebrow()
            TodaySummary()
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            FilterBar()
            VStack(spacing: 0) {
                ForEach(Habit.samples) { habit in
                    HabitRow(habit: habit)
                    if habit.id != Habit.samples.last?.id { Divider().padding(.leading, 58) }
                }
            }
            .padding(.horizontal, Theme.Space.l)
            .padding(.vertical, Theme.Space.xs)
            .background(Theme.surface, in: .rect(cornerRadius: Theme.Radius.card, style: .continuous))
        }
    }
}

#Preview("Habit list") { HabitListView() }
#Preview("Habit row", traits: .sizeThatFitsLayout) { HabitRow(habit: Habit.samples[0]).padding() }

/// A month of check-ins: taller than any screen (full-length screenshot demo).
struct HabitHistoryView: View {
    private let days = Array(0..<30)

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(days, id: \.self) { HistoryRow(daysAgo: $0) }
                } header: {
                    Text(verbatim: Theme.today.formatted(Date.FormatStyle.dateTime.month(.wide).year().utc))
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.canvas)
            .navigationTitle("History")
            .tint(Theme.accent)
        }
    }
}

struct HistoryRow: View {
    let daysAgo: Int
    var body: some View {
        let date = Theme.today.addingTimeInterval(-86_400 * Double(daysAgo))
        let done = History.completed(daysAgo: daysAgo)
        HStack(spacing: Theme.Space.l) {
            VStack(spacing: 0) {
                Text(verbatim: date.formatted(Date.FormatStyle.dateTime.day().utc)).font(.figure(.title3)).monospacedDigit()
                Text(verbatim: date.formatted(Date.FormatStyle.dateTime.weekday(.abbreviated).utc)).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
            .frame(width: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(done == 5 ? "Perfect day" : daysAgo == 0 ? "In progress" : "\(done) of 5 habits")
                    .font(.body.weight(done == 5 ? .semibold : .regular))
                if done == 5 { Text("All habits completed").font(.footnote).foregroundStyle(.secondary) }
            }
            Spacer(minLength: Theme.Space.s)
            HStack(spacing: 5) {
                ForEach(0..<5, id: \.self) { i in
                    Circle()
                        .fill(i < done ? Theme.accent : Color.primary.opacity(0.10))
                        .frame(width: 9, height: 9)
                }
            }
        }
        .padding(.vertical, 2)
        .listRowBackground(Theme.surface)
    }
}

struct NewHabitView: View {
    @State private var name = String(localized: "Read 20 pages")
    private let icons = ["book.closed.fill", "drop.fill", "figure.run", "figure.mind.and.body", "pencil.line", "moon.fill"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: Theme.Space.m) {
                        Image(systemName: icons[0])
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(Theme.accent, in: .circle)
                        TextField("Name", text: $name).font(.body.weight(.semibold))
                    }
                }
                Section("Icon") {
                    HStack {
                        ForEach(icons, id: \.self) { icon in
                            Image(systemName: icon)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(icon == icons[0] ? Color.white : Theme.accent)
                                .frame(width: 40, height: 40)
                                .background(icon == icons[0] ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.accent.opacity(0.12)), in: .circle)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.vertical, Theme.Space.xs)
                }
                Section {
                    LabeledContent("Repeat", value: String(localized: "Every day"))
                    Toggle("Remind me", isOn: .constant(true))
                    LabeledContent("Time") {
                        Text(verbatim: Date(timeIntervalSince1970: 1_790_026_200).formatted(Date.FormatStyle.dateTime.hour().minute().utc))
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("New habit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { } label: { Image(systemName: "xmark") }.accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { } label: { Image(systemName: "checkmark") }.accessibilityLabel("Add")
                }
            }
            .tint(Theme.accent)
        }
        .presentationBackground(Theme.canvas)
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
    } message: { Text("Your 12-day streak and its history will be removed.") }
}
#Preview("Share dialog") {
    HabitListView().confirmationDialog("Share your streak", isPresented: .constant(true), titleVisibility: .visible) {
        Button("Messages") { }
        Button("Copy link") { }
        Button("Save image") { }
    }
}
