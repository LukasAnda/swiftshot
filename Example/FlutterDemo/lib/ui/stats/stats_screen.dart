import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../model/habits.dart';
import '../../theme/theme.dart';
import '../components/app_icons.dart';
import '../components/components.dart';
import '../format.dart';

/// Statistics: the completion rate, the last week, a heat map and each habit's month. Wide
/// screens arrange the cards in two columns.
class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 700;
          final gutter = wide ? Space.xl : Space.l;
          return SingleChildScrollView(
            child: Readable(
              maxWidth: 1100,
              child: Padding(
                padding: EdgeInsets.fromLTRB(gutter, 0, gutter, Space.xxl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: Space.l,
                  children: [
                    HabitsHeader(
                      title: l.statistics,
                      subtitle: context.formatDate(History.today, DateStyle.weekdayDayMonthYear),
                      horizontalPadding: 0,
                    ),
                    if (wide) ...[
                      const Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: SizedBox(width: 360, child: _RangePicker()),
                      ),
                      const IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          spacing: Space.l,
                          children: [
                            Expanded(
                              child: Column(spacing: Space.l, children: [CompletionHero(), MetricGrid()]),
                            ),
                            Expanded(child: WeekChart()),
                          ],
                        ),
                      ),
                      const ConsistencyGrid(weeks: 26),
                      const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: Space.l,
                        children: [Expanded(child: HabitBreakdown()), Expanded(child: Highlights())],
                      ),
                    ] else ...const [
                      _RangePicker(),
                      CompletionHero(),
                      WeekChart(),
                      ConsistencyGrid(),
                      MetricGrid(),
                      HabitBreakdown(),
                    ],
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

/// Week / Month / Year as a connected button group (Week is selected).
class _RangePicker extends StatelessWidget {
  const _RangePicker();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = context.colors;
    final labels = [l.rangeWeek, l.rangeMonth, l.rangeYear];
    const outer = Radius.circular(20);
    const inner = Radius.circular(8);
    BorderRadiusDirectional shape(int i) => switch (i) {
      0 => const BorderRadiusDirectional.horizontal(start: outer, end: inner),
      2 => const BorderRadiusDirectional.horizontal(start: inner, end: outer),
      _ => const BorderRadiusDirectional.all(inner),
    };
    return Semantics(
      label: l.range,
      child: Row(
        spacing: 2,
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: Material(
                color: i == 0 ? colors.primary : colors.surfaceContainer,
                borderRadius: i == 0 ? const BorderRadius.all(outer) : shape(i),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () {},
                  child: SizedBox(
                    height: 40,
                    child: Center(
                      child: Text(
                        labels[i],
                        maxLines: 1,
                        style: context.text.labelLarge!.copyWith(
                          color: i == 0 ? colors.onPrimary : colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The headline number.
class CompletionHero extends StatelessWidget {
  const CompletionHero({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = context.colors;
    return SurfaceCard(
      radius: 28,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: Space.s,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.completionRate, style: context.text.titleSmall!.copyWith(color: colors.onSurfaceVariant)),
                Text(
                  context.formatPercent(History.completionRate),
                  style: Figures.hero.copyWith(color: colors.onSurface),
                  maxLines: 1,
                ),
              ],
            ),
            Expanded(
              child: Align(
                alignment: AlignmentDirectional.topEnd,
                child: DecoratedBox(
                  decoration: ShapeDecoration(
                    shape: const StadiumBorder(),
                    color: colors.primary.withValues(alpha: 0.12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      spacing: Space.xs,
                      children: [
                        Icon(AppIcons.trendingUp, size: 16, color: colors.primary),
                        Flexible(
                          child: Text(
                            l.vsLastWeek('+${context.formatPercent(History.completionDelta)}'),
                            style: context.text.labelMedium!.copyWith(color: colors.primary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Completion of each of the last seven days; today in full accent.
class WeekChart extends StatelessWidget {
  const WeekChart({super.key, this.barHeight = 150});

  final double barHeight;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = context.colors;
    final week = History.week;
    return SurfaceCard(
      children: [
        CardHeader(l.last7Days, trailing: l.nCheckIns(History.weekCheckIns)),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          spacing: Space.m,
          children: [
            for (var i = 0; i < week.length; i++)
              Expanded(
                child: Column(
                  spacing: Space.s,
                  children: [
                    Container(
                      height: barHeight,
                      alignment: Alignment.bottomCenter,
                      decoration: BoxDecoration(
                        color: context.brand.track,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Container(
                        height: barHeight * week[i],
                        decoration: BoxDecoration(
                          color: i == week.length - 1 ? colors.primary : colors.primary.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    Text(
                      context.formatDate(History.dayAgo(6 - i), DateStyle.weekdayNarrow),
                      style: context.text.labelMedium!.copyWith(
                        color: i == week.length - 1 ? colors.primary : colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Weeks of check-ins as a heat map (fixed data). Columns are weeks, oldest first.
class ConsistencyGrid extends StatelessWidget {
  const ConsistencyGrid({super.key, this.weeks = 12});

  final int weeks;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = context.colors;
    Color? color(int level) => switch (level) {
      < 0 => null,
      0 => context.brand.track,
      _ => colors.primary.withValues(alpha: 0.2 + 0.2 * level),
    };
    final legend = context.text.labelSmall!.copyWith(color: colors.onSurfaceVariant);
    return SurfaceCard(
      children: [
        CardHeader(l.consistency, trailing: l.lastNWeeks(weeks)),
        Row(
          spacing: 5,
          children: [
            for (var week = 0; week < weeks; week++)
              Expanded(
                child: Column(
                  spacing: 5,
                  children: [
                    for (var day = 0; day < 7; day++)
                      AspectRatio(
                        aspectRatio: 1,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: color(History.level(week, day, weeks)),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          spacing: 5,
          children: [
            Text(l.less, style: legend),
            for (var level = 0; level <= 4; level++)
              Container(
                width: 11,
                height: 11,
                decoration: BoxDecoration(color: color(level), borderRadius: BorderRadius.circular(3)),
              ),
            Text(l.more, style: legend),
          ],
        ),
      ],
    );
  }
}

class MetricGrid extends StatelessWidget {
  const MetricGrid({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.m,
        children: [
          Expanded(
            child: _MetricTile(
              icon: AppIcons.flame,
              value: l.days(History.currentStreak),
              title: l.currentStreak,
            ),
          ),
          Expanded(
            child: _MetricTile(icon: AppIcons.trophy, value: l.days(History.bestStreak), title: l.bestStreak),
          ),
          Expanded(
            child: _MetricTile(
              icon: AppIcons.verified,
              value: context.formatNumber(History.totalCheckIns),
              title: l.checkIns,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.icon, required this.value, required this.title});

  final IconData icon;
  final String value;
  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final small = context.text.bodySmall!;
    return SurfaceCard(
      radius: 20,
      padding: 14,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: Space.s,
          children: [
            Icon(icon, size: 20, color: colors.primary),
            Text(
              value,
              style: Figures.medium.copyWith(color: colors.onSurface),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            // Always two lines tall, so the three tiles line up.
            SizedBox(
              height: small.fontSize! * small.height! * 2 * MediaQuery.textScalerOf(context).scale(1),
              child: Text(title, style: small.copyWith(color: colors.onSurfaceVariant), maxLines: 2),
            ),
          ],
        ),
      ],
    );
  }
}

/// Each habit's completion over the last 30 days.
class HabitBreakdown extends StatelessWidget {
  const HabitBreakdown({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = context.colors;
    return SurfaceCard(
      children: [
        CardHeader(l.byHabit, trailing: l.last30Days),
        for (final habit in Habit.values)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 6,
            children: [
              Row(
                children: [
                  AppIcon(habit.icon, size: 18, color: colors.primary),
                  const SizedBox(width: Space.s),
                  Expanded(child: Text(habit.title(l), style: context.text.titleSmall)),
                  Text(context.formatPercent(habit.rate), style: Figures.small.copyWith(color: colors.onSurface)),
                ],
              ),
              FractionBar(habit.rate, color: colors.primary.withValues(alpha: 0.35 + 0.65 * habit.rate)),
            ],
          ),
      ],
    );
  }
}

/// A few notable facts, as a short list.
class Highlights extends StatelessWidget {
  const Highlights({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return SurfaceCard(
      children: [
        Text(l.highlights, style: context.text.titleMedium),
        _HighlightRow(icon: AppIcons.calendar, title: l.bestDay, value: l.bestDayValue),
        const Divider(height: 1),
        _HighlightRow(icon: AppIcons.twilight, title: l.bestTime, value: l.bestTimeValue),
        const Divider(height: 1),
        _HighlightRow(icon: AppIcons.run, title: l.mostConsistent, value: l.habitRun),
        const Divider(height: 1),
        _HighlightRow(icon: AppIcons.journal, title: l.needsAttention, value: l.needsAttentionValue),
      ],
    );
  }
}

class _HighlightRow extends StatelessWidget {
  const _HighlightRow({required this.icon, required this.title, required this.value});

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: Space.m,
      children: [
        IconBadge(icon, size: 36),
        Expanded(
          child: Text(title, style: context.text.bodyMedium!.copyWith(color: context.colors.onSurfaceVariant)),
        ),
        Text(value, style: context.text.titleSmall),
      ],
    );
  }
}
