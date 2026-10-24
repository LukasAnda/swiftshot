import SwiftUI

struct Habit: Identifiable {
    let id = UUID()
    let title: LocalizedStringKey
    let icon: String
    let color: Color
    let progress: Double
    let streak: Int
}

extension Habit {
    static let samples: [Habit] = [
        Habit(title: "Drink water", icon: "drop.fill", color: .blue, progress: 0.75, streak: 12),
        Habit(title: "Morning run", icon: "figure.run", color: .orange, progress: 1.0, streak: 31),
        Habit(title: "Read 20 pages", icon: "book.fill", color: .purple, progress: 0.4, streak: 5),
        Habit(title: "Meditate", icon: "leaf.fill", color: .green, progress: 0.0, streak: 0),
        Habit(title: "No sugar", icon: "nosign", color: .pink, progress: 0.9, streak: 8),
    ]
}
