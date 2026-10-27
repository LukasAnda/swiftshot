import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import '../../l10n/app_localizations.dart';
import '../../model/habits.dart';
import '../../previews/preview_support.dart';
import '../../theme/theme.dart';
import '../components/app_icons.dart';
import '../components/components.dart';
import '../format.dart';
import '../habits_root.dart';

const List<IconData> _habitIcons = [
  AppIcons.read,
  AppIcons.water,
  AppIcons.run,
  AppIcons.meditate,
  AppIcons.journal,
  AppIcons.bedtime,
];

/// The widest a bottom sheet gets (Material 3).
const double _sheetMaxWidth = 640;

/// Shows the "New habit" sheet as a modal bottom sheet.
Future<void> showAddHabitSheet(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  backgroundColor: context.colors.surfaceContainerLow,
  constraints: const BoxConstraints(maxWidth: _sheetMaxWidth),
  builder: (context) => AddHabitSheet(onDismiss: () => Navigator.of(context).pop()),
);

/// Shows the "Delete habit" confirmation as a dialog.
Future<void> showDeleteHabitDialog(BuildContext context) => showDialog<void>(
  context: context,
  builder: (context) => DeleteHabitDialog(onDismiss: () => Navigator.of(context).pop()),
);

/// The content of the "New habit" sheet: name, icon, schedule and reminder.
class AddHabitSheet extends StatelessWidget {
  const AddHabitSheet({super.key, this.onDismiss});

  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = context.colors;
    final dismiss = onDismiss ?? () {};
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.l,
          children: [
            Row(
              children: [
                IconButton(onPressed: dismiss, tooltip: l.cancel, icon: const Icon(AppIcons.close)),
                Expanded(
                  child: Text(l.newHabit, style: context.text.titleLarge, textAlign: TextAlign.center),
                ),
                FilledButton(onPressed: dismiss, child: Text(l.add)),
              ],
            ),
            TextFormField(
              initialValue: l.habitRead,
              style: context.text.titleMedium,
              decoration: InputDecoration(
                labelText: l.name,
                filled: true,
                fillColor: context.brand.card,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(Corners.medium)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(Corners.medium),
                  borderSide: BorderSide(color: colors.outline),
                ),
              ),
            ),
            Text(l.icon, style: context.text.labelLarge!.copyWith(color: colors.onSurfaceVariant)),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (var i = 0; i < _habitIcons.length; i++)
                  Container(
                    width: 48,
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i == 0 ? colors.primary : colors.primary.withValues(alpha: 0.12),
                    ),
                    child: AppIcon(_habitIcons[i], size: 22, color: i == 0 ? colors.onPrimary : colors.primary),
                  ),
              ],
            ),
            SegmentedColumn(
              children: [
                _SheetRow(
                  index: 0,
                  icon: AppIcons.repeat,
                  title: l.repeat,
                  trailing: Text(l.everyDay, style: context.text.bodyLarge),
                ),
                _SheetRow(
                  index: 1,
                  icon: AppIcons.notifications,
                  title: l.remindMe,
                  trailing: Switch(value: true, onChanged: (_) {}),
                ),
                _SheetRow(
                  index: 2,
                  icon: AppIcons.schedule,
                  title: l.time,
                  trailing: Text(
                    context.formatDate(History.newHabitTime, DateStyle.time),
                    style: context.text.bodyLarge!.copyWith(color: colors.primary),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetRow extends StatelessWidget {
  const _SheetRow({required this.index, required this.icon, required this.title, required this.trailing});

  final int index;
  final IconData icon;
  final String title;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.brand.card,
      borderRadius: segmentRadius(index, 3),
      clipBehavior: Clip.antiAlias,
      child: ListTile(onTap: () {}, leading: Icon(icon), title: Text(title), trailing: trailing),
    );
  }
}

/// Confirms deleting a habit and its streak.
class DeleteHabitDialog extends StatelessWidget {
  const DeleteHabitDialog({super.key, this.onDismiss, this.onDelete});

  final VoidCallback? onDismiss;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = context.colors;
    final dismiss = onDismiss ?? () {};
    return AlertDialog(
      icon: const Icon(AppIcons.delete),
      iconColor: colors.error,
      backgroundColor: colors.surfaceContainerHigh,
      title: Text(l.deleteTitle, textAlign: TextAlign.center),
      content: Text(l.deleteBody),
      actions: [
        TextButton(onPressed: dismiss, child: Text(l.cancel)),
        FilledButton(
          onPressed: onDelete ?? dismiss,
          style: FilledButton.styleFrom(backgroundColor: colors.error, foregroundColor: colors.onError),
          child: Text(l.delete),
        ),
      ],
    );
  }
}

/// [child] with a modal bottom sheet already open over it: the sheet's settled state, built
/// directly rather than through an animated route, so the first frame is the final one.
class OpenSheet extends StatelessWidget {
  const OpenSheet({super.key, required this.child, required this.sheet});

  final Widget child;
  final Widget sheet;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        ColoredBox(color: colors.scrim.withValues(alpha: 0.32)),
        Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _sheetMaxWidth),
            child: Material(
              color: colors.surfaceContainerLow,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // The Material 3 drag handle.
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 22),
                    child: Container(
                      width: 32,
                      height: 4,
                      decoration: ShapeDecoration(
                        shape: const StadiumBorder(),
                        color: colors.onSurfaceVariant.withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                  sheet,
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// [child] with a dialog already open over it, built directly (no route, no animation).
class OpenDialog extends StatelessWidget {
  const OpenDialog({super.key, required this.child, required this.dialog});

  final Widget child;
  final Widget dialog;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        ColoredBox(color: context.colors.scrim.withValues(alpha: 0.32)),
        Center(child: dialog),
      ],
    );
  }
}

@Preview(name: 'Add habit sheet', wrapper: screenWrapper)
Widget addHabitSheetPreview() => const OpenSheet(sheet: AddHabitSheet(), child: HabitsRoot());

@Preview(name: 'Delete dialog', wrapper: screenWrapper)
Widget deleteDialogPreview() => const OpenDialog(dialog: DeleteHabitDialog(), child: HabitsRoot());
