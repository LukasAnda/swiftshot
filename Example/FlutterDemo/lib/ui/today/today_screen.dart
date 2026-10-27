import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../model/habits.dart';
import '../../theme/theme.dart';
import '../components/app_icons.dart';
import '../components/components.dart';
import '../format.dart';
import 'habit_dialogs.dart';
import 'today_cards.dart';

/// Space for the floating action button under the last card.
const double fabClearance = 88;

/// Today: the day's summary, the habits and what's next. Expanded widths become list-detail:
/// the list on the leading side, the first habit beside it.
///
/// [showFab] is false where the navigation rail already carries the "New habit" action.
class TodayScreen extends StatelessWidget {
  const TodayScreen({super.key, this.showFab = true, this.onAddHabit});

  final bool showFab;
  final VoidCallback? onAddHabit;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final title = l.tabToday;
    final subtitle = context.formatDate(History.today, DateStyle.weekdayDayMonth);
    void confirmDelete(Habit habit) => showDeleteHabitDialog(context);
    return Scaffold(
      floatingActionButton: showFab
          ? FloatingActionButton.extended(
              onPressed: onAddHabit ?? () {},
              icon: const Icon(AppIcons.add),
              label: Text(l.newHabit),
            )
          : null,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          if (width >= WidthClass.expanded) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                HabitsHeader(title: title, subtitle: subtitle, horizontalPadding: Space.xl),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.xl),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: Space.xl,
                      children: [
                        Expanded(
                          child: Align(
                            alignment: AlignmentDirectional.topStart,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 560),
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.only(bottom: Space.xxl),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  spacing: Space.l,
                                  children: [
                                    const TodaySummary(),
                                    const FilterRow(),
                                    HabitList(showWeek: true, onLongPress: confirmDelete),
                                    const UpNextCard(),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        const Expanded(
                          child: SingleChildScrollView(
                            padding: EdgeInsets.only(bottom: Space.xxl),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              spacing: Space.l,
                              children: [HabitDetailPane(habit: Habit.water), MilestoneCard(), InsightCard()],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          }
          return SingleChildScrollView(
            child: Readable(
              child: Padding(
                padding: EdgeInsets.fromLTRB(Space.l, 0, Space.l, showFab ? fabClearance : Space.xxl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: Space.l,
                  children: [
                    HabitsHeader(title: title, subtitle: subtitle, horizontalPadding: 0),
                    const TodaySummary(),
                    const FilterRow(),
                    HabitList(showWeek: width >= WidthClass.medium, onLongPress: confirmDelete),
                    const UpNextCard(),
                    const MilestoneCard(),
                    const InsightCard(),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The detail side of list-detail: one habit's day, week and month.
class HabitDetailPane extends StatelessWidget {
  const HabitDetailPane({super.key, required this.habit});

  final Habit habit;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = context.colors;
    return SurfaceCard(
      radius: Corners.extraLarge,
      padding: Space.xl,
      children: [
        Column(
          spacing: Space.m,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                ProgressRing(progress: habit.progress, size: 168, strokeWidth: 16, checkWhenDone: false),
                AppIcon(habit.icon, size: 44, color: colors.primary),
              ],
            ),
            Text(habit.title(l), style: context.text.headlineSmall, textAlign: TextAlign.center),
            Text(habit.detail(l), style: context.text.bodyLarge!.copyWith(color: colors.onSurfaceVariant)),
            if (habit.streak > 0)
              DecoratedBox(
                decoration: ShapeDecoration(shape: const StadiumBorder(), color: colors.primary.withValues(alpha: 0.12)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: Space.xs,
                    children: [
                      Icon(AppIcons.flame, size: 16, color: colors.primary),
                      Text(l.dayStreak(habit.streak), style: context.text.labelLarge!.copyWith(color: colors.primary)),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: Space.xs),
        CardHeader(l.last7Days),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var i = 0; i < habit.week.length; i++)
              Column(
                spacing: 6,
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: habit.week[i] ? colors.primary : context.brand.track,
                    ),
                    child: habit.week[i] ? Icon(AppIcons.check, size: 18, color: colors.onPrimary) : null,
                  ),
                  Text(
                    context.formatDate(History.dayAgo(6 - i), DateStyle.weekdayNarrow),
                    style: context.text.labelMedium!.copyWith(
                      color: i == habit.week.length - 1 ? colors.primary : colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
          ],
        ),
        CardHeader(l.completionRate, trailing: l.last30Days),
        Row(
          spacing: Space.l,
          children: [
            Text(context.formatPercent(habit.rate), style: Figures.large.copyWith(color: colors.onSurface)),
            Expanded(child: FractionBar(habit.rate, height: 10)),
          ],
        ),
        Row(
          spacing: Space.m,
          children: [
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: () {},
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                icon: const Icon(AppIcons.notifications, size: 18),
                label: Text(l.remindMe, maxLines: 1),
              ),
            ),
            Expanded(
              child: FilledButton.icon(
                onPressed: () {},
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                icon: const Icon(AppIcons.add, size: 18),
                label: Text(l.add, maxLines: 1),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
