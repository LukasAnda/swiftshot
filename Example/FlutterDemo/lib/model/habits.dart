import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../ui/components/app_icons.dart';

/// When a habit is usually done; drives the filter chips on Today.
enum DayPart { morning, evening, anytime }

/// The same five habits as the iOS, Android and multiplatform demos, so every platform's
/// screenshots tell one story.
enum Habit {
  water(AppIcons.water, 0.375, 12, [true, true, true, true, true, true, false], 0.93, DayPart.morning),
  run(AppIcons.run, 1, 31, [true, true, true, true, true, true, true], 1, DayPart.morning),
  read(AppIcons.read, 0.4, 5, [false, true, true, true, true, true, false], 0.8, DayPart.evening),
  meditate(AppIcons.meditate, 1, 9, [true, true, true, true, true, true, true], 0.9, DayPart.anytime),
  journal(AppIcons.journal, 0, 0, [false, false, true, false, false, false, false], 0.47, DayPart.evening);

  const Habit(this.icon, this.progress, this.streak, this.week, this.rate, this.dayPart);

  final IconData icon;

  /// Today's progress, 0..1.
  final double progress;

  /// Days in a row, including today when it is done.
  final int streak;

  /// The last seven days, oldest first; the last one is today.
  final List<bool> week;

  /// Share of the last 30 days completed.
  final double rate;

  final DayPart dayPart;

  bool get isDone => progress >= 1;

  String title(AppLocalizations l) => switch (this) {
    Habit.water => l.habitWater,
    Habit.run => l.habitRun,
    Habit.read => l.habitRead,
    Habit.meditate => l.habitMeditate,
    Habit.journal => l.habitJournal,
  };

  /// Today's amount, e.g. "3 of 8 glasses".
  String detail(AppLocalizations l) => switch (this) {
    Habit.water => l.detailWater,
    Habit.run => l.detailRun,
    Habit.read => l.detailRead,
    Habit.meditate => l.detailMeditate,
    Habit.journal => l.detailJournal,
  };

  static int get doneCount => values.where((h) => h.isDone).length;
}

/// A reminder still to come today, at a fixed time in UTC on [History.today].
class Reminder {
  const Reminder(this.habit, this.hour, this.minute, this.note);

  final Habit habit;
  final int hour;
  final int minute;
  final String Function(AppLocalizations) note;

  int get epochSeconds => History.midnight + hour * 3600 + minute * 60;
}

String _nextGlass(AppLocalizations l) => l.noteNextGlass;
String _pagesToGo(AppLocalizations l) => l.notePagesToGo;
String _threeLines(AppLocalizations l) => l.noteThreeLines;

/// A fixed, believable completion history: no clock, no randomness, the same every run, and
/// consistent with the habits' own weeks and streaks.
abstract final class History {
  /// The screenshots' fixed "today": Monday 21 September 2026, 12:53 UTC.
  static const int today = 1790000000;

  /// Midnight UTC at the start of [today].
  static const int midnight = 1789948800;

  static const int day = 86400;

  /// The daily reminder in Settings: 08:00 UTC.
  static const int reminderTime = midnight + 8 * 3600;

  /// The new habit's reminder in the add sheet: 21:30 UTC.
  static const int newHabitTime = 1790026200;

  static const List<int> _pattern = [2, 4, 4, 4, 5, 4, 3, 5, 4, 3, 5, 5, 4, 3];

  /// Habits completed (0..5) on the day [daysAgo] before [today].
  static int completed(int daysAgo) => _pattern[daysAgo % _pattern.length];

  /// Completion of each of the last seven days, oldest first (today last).
  static List<double> get week => [for (var i = 0; i < 7; i++) completed(6 - i) / 5];

  static int get weekCheckIns => [for (var i = 0; i < 7; i++) completed(i)].reduce((a, b) => a + b);

  static int dayAgo(int daysAgo) => today - day * daysAgo;

  static const List<Reminder> upNext = [
    Reminder(Habit.water, 11, 0, _nextGlass),
    Reminder(Habit.read, 20, 30, _pagesToGo),
    Reminder(Habit.journal, 21, 30, _threeLines),
  ];

  /// The last 30 days in Monday-to-Sunday weeks, newest first ([today] is a Monday).
  static List<List<int>> get weeks => [
    [0],
    for (var start = 1; start < 30; start += 7)
      [for (var d = start; d < (start + 7 < 30 ? start + 7 : 30); d++) d],
  ];

  static const List<int> _levels = [3, 4, 2, 4, 4, 1, 3, 4, 4, 2, 0, 4, 3, 4, 4, 3, 2, 4, 1];

  /// Heat map level (0..4) of a day in the consistency grid, or -1 for the future.
  static int level(int week, int day, int weeks) {
    if (week == weeks - 1 && day > 0) return -1;
    final base = _levels[(week * 7 + day) % _levels.length];
    final level = base + (week > 7 ? 1 : 0);
    return level > 4 ? 4 : level;
  }

  static const double completionRate = 0.74;
  static const double completionDelta = 0.06;
  static const int currentStreak = 31;
  static const int bestStreak = 48;
  static const int totalCheckIns = 1234;
  static const int milestone = 50;
}
