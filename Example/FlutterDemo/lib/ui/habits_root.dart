import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import '../l10n/app_localizations.dart';
import '../previews/preview_support.dart';
import '../theme/theme.dart';
import 'components/app_icons.dart';
import 'components/components.dart';
import 'history/history_screen.dart';
import 'settings/settings_screen.dart';
import 'stats/stats_screen.dart';
import 'today/habit_dialogs.dart';
import 'today/today_screen.dart';

enum AppTab {
  today(AppIcons.today, AppIcons.todaySelected),
  stats(AppIcons.stats, AppIcons.statsSelected),
  history(AppIcons.history, AppIcons.historySelected),
  settings(AppIcons.settings, AppIcons.settingsSelected);

  const AppTab(this.icon, this.selectedIcon);

  final IconData icon;
  final IconData selectedIcon;

  String label(AppLocalizations l) => switch (this) {
    AppTab.today => l.tabToday,
    AppTab.stats => l.tabStats,
    AppTab.history => l.tabHistory,
    AppTab.settings => l.tabSettings,
  };
}

/// The app's four tabs. Compact widths get a bottom navigation bar; tablets and unfolded
/// foldables a navigation rail that also carries the "New habit" action.
///
/// The navigation type follows the width the app is given (not the device), so it is the same
/// in the running app and in every preview renderer.
class HabitsRoot extends StatefulWidget {
  const HabitsRoot({super.key, this.initialTab = AppTab.today});

  final AppTab initialTab;

  @override
  State<HabitsRoot> createState() => _HabitsRootState();
}

class _HabitsRootState extends State<HabitsRoot> {
  late AppTab _tab = widget.initialTab;

  @override
  void didUpdateWidget(HabitsRoot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialTab != widget.initialTab) _tab = widget.initialTab;
  }

  void _select(int index) => setState(() => _tab = AppTab.values[index]);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= WidthClass.medium;
        final screen = switch (_tab) {
          AppTab.today => TodayScreen(showFab: !wide, onAddHabit: () => showAddHabitSheet(context)),
          AppTab.stats => const StatsScreen(),
          AppTab.history => const HistoryScreen(),
          AppTab.settings => const SettingsScreen(),
        };
        if (!wide) {
          return Scaffold(
            body: screen,
            bottomNavigationBar: NavigationBar(
              selectedIndex: _tab.index,
              onDestinationSelected: _select,
              destinations: [
                for (final tab in AppTab.values)
                  NavigationDestination(
                    icon: Icon(tab.icon),
                    selectedIcon: Icon(tab.selectedIcon),
                    label: tab.label(l),
                    tooltip: '',
                  ),
              ],
            ),
          );
        }
        return Scaffold(
          body: Row(
            children: [
              SafeArea(
                child: NavigationRail(
                  selectedIndex: _tab.index,
                  onDestinationSelected: _select,
                  groupAlignment: -1,
                  leading: Padding(
                    padding: const EdgeInsets.only(top: Space.s, bottom: Space.l),
                    child: FloatingActionButton(
                      elevation: 0,
                      onPressed: () => showAddHabitSheet(context),
                      tooltip: l.newHabit,
                      child: const Icon(AppIcons.add),
                    ),
                  ),
                  destinations: [
                    for (final tab in AppTab.values)
                      NavigationRailDestination(
                        icon: Icon(tab.icon),
                        selectedIcon: Icon(tab.selectedIcon),
                        label: Text(tab.label(l)),
                      ),
                  ],
                ),
              ),
              Expanded(child: screen),
            ],
          ),
        );
      },
    );
  }
}

@Preview(name: 'Root', wrapper: screenWrapper)
Widget rootPreview() => const HabitsRoot();

@Preview(name: 'Habit list', wrapper: screenWrapper)
Widget habitListPreview() => const HabitsRoot(initialTab: AppTab.today);

@Preview(name: 'Stats', wrapper: screenWrapper)
Widget statsPreview() => const HabitsRoot(initialTab: AppTab.stats);

@Preview(name: 'History', wrapper: screenWrapper)
Widget historyPreview() => const HabitsRoot(initialTab: AppTab.history);

@Preview(name: 'Settings', wrapper: screenWrapper)
Widget settingsPreview() => const HabitsRoot(initialTab: AppTab.settings);
