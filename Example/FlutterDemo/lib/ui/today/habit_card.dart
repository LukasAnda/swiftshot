import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import '../../l10n/app_localizations.dart';
import '../../model/habits.dart';
import '../../previews/preview_support.dart';
import '../../theme/theme.dart';
import '../components/app_icons.dart';
import '../components/components.dart';

/// One habit: its icon, today's amount and streak, and a progress ring. Wide layouts also show
/// the last seven days as dots.
class HabitCard extends StatelessWidget {
  const HabitCard({
    super.key,
    required this.habit,
    this.borderRadius = const BorderRadius.all(Radius.circular(Corners.large)),
    this.showWeek = false,
    this.onTap,
    this.onLongPress,
  });

  final Habit habit;
  final BorderRadiusGeometry borderRadius;
  final bool showWeek;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Material(
      color: context.brand.card,
      borderRadius: borderRadius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: Space.l, vertical: showWeek ? Space.l : 14),
          child: Row(
            children: [
              IconBadge(habit.icon, filled: habit.isDone),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 2,
                  children: [
                    Text(habit.title(l), style: context.text.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                    HabitSubtitle(habit: habit),
                  ],
                ),
              ),
              const SizedBox(width: Space.s),
              if (showWeek) ...[WeekDots(habit.week), const SizedBox(width: Space.l)],
              ProgressRing(progress: habit.progress, size: 30, strokeWidth: 3.5),
            ],
          ),
        ),
      ),
    );
  }
}

/// "3 of 8 glasses · (flame) 12 days", or just the amount while there's no streak.
class HabitSubtitle extends StatelessWidget {
  const HabitSubtitle({super.key, required this.habit});

  final Habit habit;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final style = context.text.bodyMedium!.copyWith(color: context.colors.onSurfaceVariant);
    return Row(
      spacing: Space.xs,
      children: [
        Flexible(child: Text(habit.detail(l), style: style, maxLines: 1, overflow: TextOverflow.ellipsis)),
        if (habit.streak > 0) ...[
          Text('·', style: style),
          Icon(AppIcons.flame, size: 14, color: context.colors.primary),
          Flexible(child: Text(l.days(habit.streak), style: style, maxLines: 1, overflow: TextOverflow.ellipsis)),
        ],
      ],
    );
  }
}

@Preview(name: 'Habit card', size: Size(400, 120), wrapper: canvasWrapper)
Widget habitCardPreview() => const Padding(
  padding: EdgeInsets.all(Space.l),
  child: HabitCard(habit: Habit.water, showWeek: true),
);
