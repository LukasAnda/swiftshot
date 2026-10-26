import SwiftUI

struct Habit: Identifiable {
    let id: Int
    let title: LocalizedStringKey
    /// Today's amount, e.g. "3 of 8 glasses".
    let detail: LocalizedStringKey
    let icon: String
    let progress: Double
    let streak: Int
    /// The last seven days, oldest first; the last one is today.
    let week: [Bool]
    /// Share of the last 30 days completed.
    let rate: Double

    var isDone: Bool { progress >= 1 }
}

extension Habit {
    private static let T = true, F = false
    static let samples: [Habit] = [
        Habit(id: 0, title: "Drink water", detail: "3 of 8 glasses", icon: "drop.fill", progress: 0.375, streak: 12,
              week: [T, T, T, T, T, T, F], rate: 0.93),
        Habit(id: 1, title: "Morning run", detail: "5.2 km", icon: "figure.run", progress: 1.0, streak: 31,
              week: [T, T, T, T, T, T, T], rate: 1.0),
        Habit(id: 2, title: "Read 20 pages", detail: "8 of 20 pages", icon: "book.closed.fill", progress: 0.4, streak: 5,
              week: [F, T, T, T, T, T, F], rate: 0.8),
        Habit(id: 3, title: "Meditate", detail: "10 minutes", icon: "figure.mind.and.body", progress: 1.0, streak: 9,
              week: [T, T, T, T, T, T, T], rate: 0.9),
        Habit(id: 4, title: "Journal", detail: "Not yet today", icon: "pencil.line", progress: 0.0, streak: 0,
              week: [F, F, T, F, F, F, F], rate: 0.47),
    ]

    static var doneCount: Int { samples.filter(\.isDone).count }
}

/// A fixed, believable completion history: no randomness, the same every run, and consistent
/// with the habits' own weeks and streaks.
enum History {
    /// Habits completed (0…5) on the day `daysAgo` before `Theme.today`.
    static func completed(daysAgo: Int) -> Int {
        let pattern = [2, 4, 4, 4, 5, 4, 3, 5, 4, 3, 5, 5, 4, 3]
        return pattern[daysAgo % pattern.count]
    }

    /// Completion of each of the last seven days, oldest first (today last).
    static let week: [Double] = (0..<7).map { Double(completed(daysAgo: 6 - $0)) / 5 }
    static var weekCheckIns: Int { (0..<7).map { completed(daysAgo: $0) }.reduce(0, +) }

    /// Reminders still to come today: habit, time (UTC on `Theme.today`) and a note.
    static let upNext: [(habit: Int, hour: Int, minute: Int, note: LocalizedStringKey)] = [
        (0, 11, 0, "Next glass"),
        (2, 20, 30, "12 pages to go"),
        (4, 21, 30, "Three lines are enough"),
    ]
}
