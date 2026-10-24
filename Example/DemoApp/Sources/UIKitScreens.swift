import SwiftUI
import UIKit

/// The habit list again, in UIKit: a navigation controller with a large title, an inset grouped
/// table and a bar button, so UIKit previews are covered too.
final class HabitTableViewController: UITableViewController {
    private let habits = [("Drink water", "drop.fill", 12), ("Morning run", "figure.run", 31), ("Read 20 pages", "book.fill", 5),
                          ("Meditate", "leaf.fill", 0), ("No sugar", "nosign", 8)]

    init() { super.init(style: .insetGrouped) }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "My Habits")
        navigationItem.largeTitleDisplayMode = .always
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .add)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "habit")
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { habits.count }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { String(localized: "Today") }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "habit", for: indexPath)
        let habit = habits[indexPath.row]
        var content = UIListContentConfiguration.subtitleCell()
        content.text = habit.0
        content.secondaryText = String(localized: "\(habit.2) day streak")
        content.image = UIImage(systemName: habit.1)
        cell.contentConfiguration = content
        cell.accessoryType = habit.2 > 0 ? .checkmark : .none
        return cell
    }
}

/// A small UIKit component (a streak badge), previewed at its fitting size.
final class StreakBadgeView: UIView {
    init(days: Int) {
        super.init(frame: .zero)
        backgroundColor = .systemOrange
        layer.cornerRadius = 14
        layer.cornerCurve = .continuous
        let label = UILabel()
        label.text = String(localized: "🔥 \(days) day streak")
        label.font = .preferredFont(forTextStyle: .headline)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
}

#Preview("UIKit habit list") {
    let nav = UINavigationController(rootViewController: HabitTableViewController())
    nav.navigationBar.prefersLargeTitles = true
    return nav
}

#Preview("UIKit streak badge", traits: .sizeThatFitsLayout) {
    StreakBadgeView(days: 12)
}
