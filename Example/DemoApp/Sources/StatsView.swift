import SwiftUI

struct StatsView: View {
    @State private var range = 0

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width > 700
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Space.l) {
                        Text(verbatim: Theme.today.formatted(Date.FormatStyle.dateTime.weekday(.wide).day().month(.wide).year().utc))
                            .eyebrow()
                        Picker("Range", selection: $range) {
                            Text("Week").tag(0)
                            Text("Month").tag(1)
                            Text("Year").tag(2)
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: wide ? 360 : .infinity)
                        if wide {
                            HStack(alignment: .top, spacing: Theme.Space.l) {
                                VStack(spacing: Theme.Space.l) { CompletionHero(); MetricGrid() }
                                WeekChart()
                            }
                            ConsistencyGrid(weeks: 26)
                            HStack(alignment: .top, spacing: Theme.Space.l) {
                                HabitBreakdown()
                                Highlights()
                            }
                        } else {
                            CompletionHero()
                            WeekChart()
                            MetricGrid()
                            ConsistencyGrid()
                            HabitBreakdown()
                        }
                    }
                    .padding(.horizontal, Theme.Space.l + 4)
                    .padding(.bottom, Theme.Space.xxl)
                    .frame(maxWidth: wide ? 1100 : .infinity)
                    .frame(maxWidth: .infinity)
                }
                .background { Backdrop() }
                .navigationTitle("Statistics")
                .tint(Theme.accent)
            }
        }
    }
}

/// The headline number, on glass.
struct CompletionHero: View {
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text("Completion rate").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                Text(0.74.formatted(.percent.precision(.fractionLength(0))))
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
            Spacer(minLength: Theme.Space.s)
            Label {
                Text("\(0.06.formatted(.percent.precision(.fractionLength(0)).sign(strategy: .always()))) vs last week")
            } icon: {
                Image(systemName: "arrow.up.right")
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Theme.accent.opacity(0.12), in: .capsule)
            .fixedSize()
        }
        .padding(Theme.Space.l + 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(in: .rect(cornerRadius: Theme.Radius.card + 4, style: .continuous))
    }
}

struct WeekChart: View {
    var barHeight: CGFloat = 150
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            HStack(alignment: .firstTextBaseline) {
                Text("Last 7 days").font(.headline)
                Spacer()
                Text("\(History.weekCheckIns) check-ins").font(.subheadline).foregroundStyle(.secondary)
            }
            HStack(alignment: .bottom, spacing: Theme.Space.m) {
                ForEach(Array(History.week.enumerated()), id: \.offset) { i, v in
                    let date = Theme.today.addingTimeInterval(-86_400 * Double(6 - i))
                    let isToday = i == History.week.count - 1
                    VStack(spacing: Theme.Space.s) {
                        ZStack(alignment: .bottom) {
                            Capsule().fill(Color.primary.opacity(0.06))
                            Capsule()
                                .fill(isToday ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.accent.opacity(0.45)))
                                .frame(height: barHeight * v)
                        }
                        .frame(height: barHeight)
                        Text(verbatim: date.formatted(Date.FormatStyle.dateTime.weekday(.narrow).utc))
                            .font(.caption.weight(isToday ? .bold : .medium))
                            .foregroundStyle(isToday ? Theme.accent : Color.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .card(padding: Theme.Space.l + 4)
    }
}

struct MetricGrid: View {
    var body: some View {
        HStack(spacing: Theme.Space.m) {
            MetricTile(icon: "flame.fill", value: Text("\(31) days"), title: "Current streak")
            MetricTile(icon: "trophy.fill", value: Text("\(48) days"), title: "Best streak")
            MetricTile(icon: "checkmark.seal.fill", value: Text(1234, format: .number), title: "Check-ins")
        }
    }
}

struct MetricTile: View {
    let icon: String
    let value: Text
    let title: LocalizedStringKey
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Image(systemName: icon).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accent)
            value.font(.figure(.title3)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(title).font(.footnote).foregroundStyle(.secondary).lineLimit(2, reservesSpace: true)
        }
        .card(padding: Theme.Space.l - 2, radius: Theme.Radius.tile)
    }
}

/// Weeks of check-ins as a heat map (fixed data).
struct ConsistencyGrid: View {
    var weeks = 12
    func level(week: Int, day: Int) -> Int {
        let i = week * 7 + day
        if week == weeks - 1 && day > 0 { return -1 } // the future
        let base = [3, 4, 2, 4, 4, 1, 3, 4, 4, 2, 0, 4, 3, 4, 4, 3, 2, 4, 1][i % 19]
        return min(4, base + (week > 7 ? 1 : 0))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            HStack(alignment: .firstTextBaseline) {
                Text("Consistency").font(.headline)
                Spacer()
                Text("Last \(weeks) weeks").font(.subheadline).foregroundStyle(.secondary)
            }
            Grid(horizontalSpacing: 5, verticalSpacing: 5) {
                ForEach(0..<7, id: \.self) { day in
                    GridRow {
                        ForEach(0..<weeks, id: \.self) { week in
                            let l = level(week: week, day: day)
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(l < 0 ? Color.clear : l == 0 ? Color.primary.opacity(0.07) : Theme.accent.opacity(0.2 + 0.2 * Double(l)))
                                .aspectRatio(1, contentMode: .fit)
                        }
                    }
                }
            }
            HStack(spacing: 5) {
                Spacer()
                Text("Less").font(.caption2).foregroundStyle(.secondary)
                ForEach(0..<5, id: \.self) { l in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(l == 0 ? Color.primary.opacity(0.07) : Theme.accent.opacity(0.2 + 0.2 * Double(l)))
                        .frame(width: 11, height: 11)
                }
                Text("More").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .card(padding: Theme.Space.l + 4)
    }
}

/// Each habit's completion over the last 30 days.
struct HabitBreakdown: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            HStack(alignment: .firstTextBaseline) {
                Text("By habit").font(.headline)
                Spacer()
                Text("Last 30 days").font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(Habit.samples) { habit in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label { Text(habit.title) } icon: { Image(systemName: habit.icon).foregroundStyle(Theme.accent) }
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(habit.rate.formatted(.percent.precision(.fractionLength(0))))
                            .font(.figure(.subheadline, weight: .semibold)).monospacedDigit()
                    }
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.07))
                            Capsule().fill(Theme.accent.opacity(0.35 + 0.65 * habit.rate)).frame(width: g.size.width * habit.rate)
                        }
                    }
                    .frame(height: 8)
                }
            }
        }
        .card(padding: Theme.Space.l + 4)
    }
}

/// A few notable facts, as a short list.
struct Highlights: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            Text("Highlights").font(.headline)
            row("calendar", "Best day", "Wednesday · 96%")
            Divider()
            row("sunrise.fill", "Best time", "Before 9:00")
            Divider()
            row("figure.run", "Most consistent", "Morning run")
            Divider()
            row("pencil.line", "Needs attention", "Journal · 47%")
        }
        .card(padding: Theme.Space.l + 4)
    }

    private func row(_ icon: String, _ title: LocalizedStringKey, _ value: LocalizedStringKey) -> some View {
        HStack(spacing: Theme.Space.m) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 32, height: 32)
                .background(Theme.accent.opacity(0.12), in: .circle)
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.subheadline.weight(.semibold))
        }
    }
}

#Preview("Stats") { StatsView() }
#Preview("Stats landscape", traits: .landscapeLeft) { StatsView() }
