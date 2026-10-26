import SwiftUI
import UIKit

/// The habit list again, in UIKit: a navigation controller with a large title, an inset grouped
/// table and a bar button, so UIKit previews are covered too.
final class HabitTableViewController: UITableViewController {
    private struct Row { let title: String.LocalizationValue; let detail: String.LocalizationValue; let icon: String; let streak: Int; let done: Bool }
    private let habits = [
        Row(title: "Drink water", detail: "3 of 8 glasses", icon: "drop.fill", streak: 12, done: false),
        Row(title: "Morning run", detail: "5.2 km", icon: "figure.run", streak: 31, done: true),
        Row(title: "Read 20 pages", detail: "8 of 20 pages", icon: "book.closed.fill", streak: 5, done: false),
        Row(title: "Meditate", detail: "10 minutes", icon: "figure.mind.and.body", streak: 9, done: true),
        Row(title: "Journal", detail: "Not yet today", icon: "pencil.line", streak: 0, done: false),
    ]

    init() { super.init(style: .insetGrouped) }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "Today")
        navigationItem.largeTitleDisplayMode = .always
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .add)
        view.tintColor = UIColor(named: "AccentColor")
        tableView.backgroundColor = UIColor(named: "Canvas")
        tableView.rowHeight = 68
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "habit")
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { habits.count }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        String(localized: "\(Habit.doneCount) of \(habits.count) done")
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "habit", for: indexPath)
        let habit = habits[indexPath.row]
        let accent = UIColor(named: "AccentColor") ?? .systemOrange
        var content = UIListContentConfiguration.subtitleCell()
        content.text = String(localized: habit.title)
        content.textProperties.font = .preferredFont(forTextStyle: .body).withWeight(.semibold)
        content.secondaryText = habit.streak > 0
            ? String(localized: habit.detail) + " · " + String(localized: "\(habit.streak) days")
            : String(localized: habit.detail)
        content.secondaryTextProperties.color = .secondaryLabel
        content.image = UIImage(systemName: habit.icon, withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold))
        content.imageProperties.tintColor = accent
        content.imageProperties.reservedLayoutSize = CGSize(width: 32, height: 32)
        content.imageToTextPadding = 14
        cell.contentConfiguration = content
        cell.backgroundColor = UIColor(named: "Surface")
        if habit.done {
            let check = UIImageView(image: UIImage(systemName: "checkmark.circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 24, weight: .semibold)))
            check.tintColor = accent
            cell.accessoryView = check
        } else {
            let ring = UIImageView(image: UIImage(systemName: "circle", withConfiguration: UIImage.SymbolConfiguration(pointSize: 24, weight: .regular)))
            ring.tintColor = .tertiaryLabel
            cell.accessoryView = ring
        }
        return cell
    }
}

private extension UIFont {
    func withWeight(_ weight: UIFont.Weight) -> UIFont {
        UIFont(descriptor: fontDescriptor.addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: weight]]), size: 0)
    }
}

/// A small UIKit component (a streak badge), previewed at its fitting size.
final class StreakBadgeView: UIView {
    init(days: Int) {
        super.init(frame: .zero)
        backgroundColor = UIColor(named: "AccentColor")
        layer.cornerRadius = 20
        layer.cornerCurve = .continuous
        let icon = UIImageView(image: UIImage(systemName: "flame.fill", withConfiguration: UIImage.SymbolConfiguration(textStyle: .headline)))
        icon.tintColor = .white
        let label = UILabel()
        label.text = String(localized: "\(days)-day streak")
        let base = UIFont.preferredFont(forTextStyle: .headline)
        label.font = base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: 0) } ?? base
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .white
        let stack = UIStackView(arrangedSubviews: [icon, label])
        stack.spacing = 6
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
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
