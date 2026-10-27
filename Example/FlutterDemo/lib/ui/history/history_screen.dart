import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../model/habits.dart';
import '../../theme/theme.dart';
import '../components/components.dart';
import '../format.dart';

/// A month of check-ins, one segmented group per week: taller than any screen.
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final weeks = History.weeks;
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Readable(
              child: HabitsHeader(
                title: l.tabHistory,
                subtitle: context.formatDate(History.today, DateStyle.monthYear),
              ),
            ),
          ),
          for (var week = 0; week < weeks.length; week++)
            SliverPadding(
              padding: EdgeInsets.fromLTRB(Space.l, week > 0 ? Space.l : 0, Space.l, 0),
              sliver: SliverList.list(
                children: [
                  for (var i = 0; i < weeks[week].length; i++)
                    Readable(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: segmentedGap),
                        child: HistoryRow(
                          daysAgo: weeks[week][i],
                          borderRadius: segmentRadius(i, weeks[week].length),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: Space.xxl)),
        ],
      ),
    );
  }
}

class HistoryRow extends StatelessWidget {
  const HistoryRow({super.key, required this.daysAgo, required this.borderRadius});

  final int daysAgo;
  final BorderRadiusGeometry borderRadius;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = context.colors;
    final date = History.dayAgo(daysAgo);
    final done = History.completed(daysAgo);
    final perfect = done == 5;
    final String status;
    if (perfect) {
      status = l.perfectDay;
    } else if (daysAgo == 0) {
      status = l.inProgress;
    } else {
      status = l.nOf5Habits(done);
    }
    return Material(
      color: context.brand.card,
      borderRadius: borderRadius,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 72),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.m),
          child: Row(
            children: [
              SizedBox(
                width: 48,
                child: Column(
                  children: [
                    Text(
                      context.formatDate(date, DateStyle.day),
                      style: Figures.medium.copyWith(color: daysAgo == 0 ? colors.primary : colors.onSurface),
                    ),
                    Text(
                      context.formatDate(date, DateStyle.weekdayShort).toUpperCase(),
                      style: context.text.labelSmall!.copyWith(color: colors.onSurfaceVariant),
                      maxLines: 1,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Space.l),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      status,
                      style: context.text.bodyLarge!.copyWith(fontWeight: perfect ? FontWeight.w600 : FontWeight.w400),
                    ),
                    if (perfect)
                      Text(
                        l.allHabitsCompleted,
                        style: context.text.bodySmall!.copyWith(color: colors.onSurfaceVariant),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: Space.s),
              Row(
                spacing: 5,
                children: [
                  for (var i = 0; i < 5; i++)
                    Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i < done ? colors.primary : context.brand.track,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
