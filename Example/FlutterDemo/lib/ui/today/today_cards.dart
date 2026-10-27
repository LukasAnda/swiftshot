import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import '../../l10n/app_localizations.dart';
import '../../model/habits.dart';
import '../../previews/preview_support.dart';
import '../../theme/theme.dart';
import '../components/app_icons.dart';
import '../components/components.dart';
import '../format.dart';
import 'habit_card.dart';

/// Today's progress and a short note, on a warm wash.
class TodaySummary extends StatelessWidget {
  const TodaySummary({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = context.colors;
    final done = Habit.doneCount;
    final total = Habit.values.length;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(colors.primary.withValues(alpha: 0.16), context.brand.card),
            Color.alphaBlend(context.brand.glow.withValues(alpha: 0.14), context.brand.card),
            context.brand.card,
          ],
        ),
      ),
      padding: const EdgeInsets.all(20),
      child: Row(
        spacing: Space.l,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              ProgressRing(progress: done / total, size: 76, strokeWidth: 9),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(context.formatNumber(done), style: Figures.medium.copyWith(color: colors.onSurface)),
                  Text(l.ofTotal(total), style: context.text.labelSmall!.copyWith(color: colors.onSurfaceVariant)),
                ],
              ),
            ],
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: Space.xs,
              children: [
                Text(l.greeting, style: context.text.titleLarge),
                Text(l.summaryBody, style: context.text.bodyMedium!.copyWith(color: colors.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The filter chips above the list (All is selected).
class FilterRow extends StatelessWidget {
  const FilterRow({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    int count(DayPart part) => Habit.values.where((h) => h.dayPart == part).length;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        spacing: Space.s,
        children: [
          _FilterPill(label: l.filterAll, count: Habit.values.length, selected: true),
          _FilterPill(label: l.filterMorning, count: count(DayPart.morning), selected: false),
          _FilterPill(label: l.filterEvening, count: count(DayPart.evening), selected: false),
        ],
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({required this.label, required this.count, required this.selected});

  final String label;
  final int count;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final style = context.text.labelLarge!;
    return Material(
      color: selected ? colors.primary : context.brand.card,
      shape: StadiumBorder(side: selected ? BorderSide.none : BorderSide(color: colors.outlineVariant)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: () {},
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 6,
            children: [
              Text(label, style: style.copyWith(color: selected ? colors.onPrimary : colors.onSurfaceVariant)),
              Text(
                context.formatNumber(count),
                style: style.copyWith(
                  color: selected ? colors.onPrimary.withValues(alpha: 0.8) : colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The habits as one segmented group.
class HabitList extends StatelessWidget {
  const HabitList({super.key, this.showWeek = false, this.onLongPress});

  final bool showWeek;
  final ValueChanged<Habit>? onLongPress;

  @override
  Widget build(BuildContext context) {
    const habits = Habit.values;
    return SegmentedColumn(
      children: [
        for (var i = 0; i < habits.length; i++)
          HabitCard(
            habit: habits[i],
            borderRadius: segmentRadius(i, habits.length),
            showWeek: showWeek,
            onTap: () {},
            onLongPress: onLongPress == null ? null : () => onLongPress!(habits[i]),
          ),
      ],
    );
  }
}

/// The reminders still to come today, at fixed times.
class UpNextCard extends StatelessWidget {
  const UpNextCard({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = context.colors;
    final muted = colors.onSurfaceVariant;
    const items = History.upNext;
    return SurfaceCard(
      children: [
        Row(
          children: [
            Expanded(child: Text(l.upNext, style: context.text.titleMedium)),
            Icon(AppIcons.notifications, size: 16, color: muted),
            const SizedBox(width: Space.xs),
            Text(l.remindersOn, style: context.text.labelLarge!.copyWith(color: muted)),
          ],
        ),
        Column(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.m),
                child: Row(
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 76),
                      child: Text(
                        context.formatDate(items[i].epochSeconds, DateStyle.time),
                        style: Figures.small.copyWith(color: colors.onSurface),
                        maxLines: 1,
                      ),
                    ),
                    Container(
                      width: 3,
                      height: 36,
                      decoration: ShapeDecoration(shape: const StadiumBorder(), color: colors.primary),
                    ),
                    const SizedBox(width: Space.l),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            items[i].habit.title(l),
                            style: context.text.titleSmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            items[i].note(l),
                            style: context.text.bodyMedium!.copyWith(color: muted),
                            maxLines: 1,
                          ),
                        ],
                      ),
                    ),
                    AppIcon(items[i].habit.icon, size: 20, color: colors.primary),
                  ],
                ),
              ),
              if (i < items.length - 1) const Divider(height: 1),
            ],
          ],
        ),
      ],
    );
  }
}

/// Progress towards the next round-number streak.
class MilestoneCard extends StatelessWidget {
  const MilestoneCard({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = context.colors;
    const toGo = History.milestone - History.currentStreak;
    return SurfaceCard(
      children: [
        Row(
          children: [
            Icon(AppIcons.flag, size: 18, color: colors.onSurfaceVariant),
            const SizedBox(width: 6),
            Expanded(
              child: Text(l.nextMilestone, style: context.text.labelLarge!.copyWith(color: colors.onSurfaceVariant)),
            ),
            Text(l.daysToGo(toGo), style: context.text.labelLarge!.copyWith(color: colors.primary)),
          ],
        ),
        Text(l.milestoneTitle, style: context.text.titleLarge),
        const FractionBar(History.currentStreak / History.milestone, height: 10),
      ],
    );
  }
}

/// One observation from the history, on a soft accent wash.
class InsightCard extends StatelessWidget {
  const InsightCard({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = context.colors;
    return SurfaceCard(
      color: overCanvas(context, colors.primary.withValues(alpha: 0.10)),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: Space.l,
          children: [
            const IconBadge(AppIcons.twilight, filled: true, radius: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: Space.xs,
                children: [
                  Text(l.insightTitle, style: context.text.titleMedium),
                  Text(l.insightBody, style: context.text.bodyMedium!.copyWith(color: colors.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Exercises a custom [MultiPreview]: the summary in light and in dark.
@LightDarkPreview(name: 'Today summary', size: Size.fromWidth(400))
Widget todaySummaryPreview() => const Padding(padding: EdgeInsets.all(Space.l), child: TodaySummary());
