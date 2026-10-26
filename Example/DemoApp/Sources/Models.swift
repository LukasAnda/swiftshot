import SwiftUI

struct Habit: Identifiable {
    let id: Int
    let title: LocalizedStringKey
    /// Today's amount, e.g. "6 of 8 glasses".
    let detail: LocalizedStringKey
    let icon: String
    let progress: Double
    let streak: Int

    var isDone: Bool { progress >= 1 }
}

extension Habit {
    static let samples: [Habit] = [
        Habit(id: 0, title: "Drink water", detail: "6 of 8 glasses", icon: "drop.fill", progress: 0.75, streak: 12),
        Habit(id: 1, title: "Morning run", detail: "5.2 km", icon: "figure.run", progress: 1.0, streak: 31),
        Habit(id: 2, title: "Read 20 pages", detail: "8 of 20 pages", icon: "book.closed.fill", progress: 0.4, streak: 5),
        Habit(id: 3, title: "Meditate", detail: "10 minutes", icon: "figure.mind.and.body", progress: 1.0, streak: 9),
        Habit(id: 4, title: "Journal", detail: "Not yet today", icon: "pencil.line", progress: 0.0, streak: 0),
    ]

    static var doneCount: Int { samples.filter(\.isDone).count }
}

/// A fixed, believable completion history: no randomness, the same every run.
enum History {
    /// Habits completed (0…5) on the day `daysAgo` before `Theme.today`.
    static func completed(daysAgo: Int) -> Int {
        let pattern = [5, 4, 5, 5, 3, 5, 4, 5, 2, 5, 5, 4, 3, 5]
        return daysAgo == 0 ? Habit.doneCount : pattern[daysAgo % pattern.count]
    }

    /// Completion of each day this week, Monday first (today is Monday… so the week is the last seven days).
    static let week: [Double] = [0.6, 0.8, 1.0, 0.8, 0.6, 1.0, 0.4]
}
