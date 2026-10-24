import SwiftUI

struct StatsView: View {
    let values: [Double] = [0.4, 0.7, 0.55, 0.9, 0.65, 1.0, 0.8]
    let date = Date(timeIntervalSince1970: 1_790_000_000)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(date, format: .dateTime.weekday(.wide).day().month(.wide).year())
                        .font(.subheadline).foregroundStyle(.secondary)
                    HStack(spacing: 16) {
                        StatCard(title: "Completed", value: 1234.5.formatted(.number), icon: "checkmark.circle.fill", tint: .green)
                        StatCard(title: "Success rate", value: 0.873.formatted(.percent.precision(.fractionLength(1))), icon: "flame.fill", tint: .orange)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Text("This week").font(.headline)
                        HStack(alignment: .bottom, spacing: 10) {
                            ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                                VStack {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(.blue.gradient)
                                        .frame(height: 160 * v)
                                    Text(Calendar.current.veryShortWeekdaySymbols[i])
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                        .frame(height: 190)
                    }
                    .padding()
                    .background(.background.secondary, in: .rect(cornerRadius: 16))
                }
                .padding()
            }
            .navigationTitle("Statistics")
        }
    }
}

struct StatCard: View {
    let title: LocalizedStringKey
    let value: String
    let icon: String
    let tint: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon).foregroundStyle(tint).font(.title2)
            Text(value).font(.title.bold()).monospacedDigit()
            Text(title).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background.secondary, in: .rect(cornerRadius: 16))
    }
}

#Preview("Stats") { StatsView() }
#Preview("Stats landscape", traits: .landscapeLeft) { StatsView() }
